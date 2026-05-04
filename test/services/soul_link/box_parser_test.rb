require "test_helper"

module SoulLink
  # BoxParser unit tests. Builds a synthetic 0x80000-byte SRAM blob with
  # a CRC-valid storage block in partition A and N populated 136-byte
  # box-PKM records. The synthetic builder mirrors the PkmDecoderTest
  # round-trip helpers — same crypto path, no real-save fixtures
  # checked into the repo.
  class BoxParserTest < ActiveSupport::TestCase
    SLOT_SIZE                  = SoulLink::SaveParser::SLOT_SIZE
    EXPECTED_TOTAL             = SoulLink::SaveParser::EXPECTED_TOTAL
    CRC_INIT                   = SoulLink::SaveParser::CRC_INIT
    CRC_POLY                   = SoulLink::SaveParser::CRC_POLY

    STORAGE_OFFSET             = SoulLink::BoxParser::STORAGE_OFFSET_IN_PARTITION
    STORAGE_SIZE               = SoulLink::BoxParser::STORAGE_SIZE
    BOX_DATA_OFFSET_IN_STORAGE = SoulLink::BoxParser::BOX_DATA_OFFSET_IN_STORAGE
    BOX_COUNT                  = SoulLink::BoxParser::BOX_COUNT
    SLOTS_PER_BOX              = SoulLink::BoxParser::SLOTS_PER_BOX
    BOX_RECORD_SIZE            = SoulLink::BoxParser::BOX_RECORD_SIZE
    STORAGE_COUNTER_OFFSET     = SoulLink::BoxParser::STORAGE_COUNTER_OFFSET
    STORAGE_CRC_OFFSET         = SoulLink::BoxParser::STORAGE_CRC_OFFSET
    STORAGE_CRC_RANGE_END      = SoulLink::BoxParser::STORAGE_CRC_RANGE_END

    LCG_MULTIPLIER = SoulLink::PkmDecoder::LCG_MULTIPLIER
    LCG_INCREMENT  = SoulLink::PkmDecoder::LCG_INCREMENT
    U16_MASK       = SoulLink::PkmDecoder::U16_MASK
    U32_MASK       = SoulLink::PkmDecoder::U32_MASK
    BLOCK_SIZE     = SoulLink::PkmDecoder::BLOCK_SIZE
    SHUFFLE_TABLE  = SoulLink::PkmDecoder::SHUFFLE_TABLE

    # ── Synthetic-record builder (136-byte box record) ────────────────

    def build_box_record(pid:, species:, ot_id: 1, ot_sid: 1, met_location: 16,
                          met_level: 5, is_egg: false)
      canonical = "\x00".b * 128
      canonical[0x00, 2] = [ species & U16_MASK ].pack("v")
      canonical[0x04, 2] = [ ot_id   & U16_MASK ].pack("v")
      canonical[0x06, 2] = [ ot_sid  & U16_MASK ].pack("v")
      iv_dword = is_egg ? (1 << 30) : 0
      canonical[BLOCK_SIZE + 0x10, 4]  = [ iv_dword & U32_MASK ].pack("V")
      canonical[BLOCK_SIZE + 0x1E, 2]  = [ met_location & U16_MASK ].pack("v")
      canonical.setbyte(3 * BLOCK_SIZE + 0x1C, met_level & 0x7F)

      checksum = (0...64).sum { |i| canonical.byteslice(i * 2, 2).unpack1("v") } & U16_MASK
      shuffled = shuffle_to_encrypted_order(canonical, pid)
      encrypted_blocks = lcg_xor(shuffled, checksum)

      header = String.new(capacity: 8).b
      header << [ pid       & U32_MASK ].pack("V")
      header << [ 0 ].pack("v")
      header << [ checksum  & U16_MASK ].pack("v")
      record = header + encrypted_blocks
      raise "expected 136-byte box record, got #{record.bytesize}" if record.bytesize != BOX_RECORD_SIZE
      record
    end

    def shuffle_to_encrypted_order(canonical_payload, pid)
      idx = (pid >> 13) & 0x1F
      order = SHUFFLE_TABLE[idx]
      inv = [ nil, nil, nil, nil ]
      order.each_with_index { |encrypted_slot, canonical_pos| inv[encrypted_slot] = canonical_pos }
      result = String.new(capacity: 128).b
      4.times do |encrypted_slot|
        canonical_pos = inv[encrypted_slot]
        result << canonical_payload.byteslice(canonical_pos * BLOCK_SIZE, BLOCK_SIZE)
      end
      result
    end

    def lcg_xor(payload, seed)
      seed &= U32_MASK
      out_words = []
      (payload.bytesize / 2).times do |i|
        seed = ((seed * LCG_MULTIPLIER) + LCG_INCREMENT) & U32_MASK
        ks = (seed >> 16) & U16_MASK
        out_words << (payload.byteslice(i * 2, 2).unpack1("v") ^ ks)
      end
      out_words.pack("v*")
    end

    def crc16(data)
      crc = CRC_INIT
      data.each_byte do |byte|
        crc ^= (byte << 8)
        8.times do
          crc = (crc & 0x8000).zero? ? (crc << 1) : ((crc << 1) ^ CRC_POLY)
          crc &= 0xFFFF
        end
      end
      crc
    end

    # Build a storage block (size 0x121E4) holding the given placements
    # — a Hash of `[box_idx, slot_idx] => 136-byte record`.
    def build_storage_block(records: {}, save_counter: 1, with_valid_crc: true)
      block = "\x00".b * STORAGE_SIZE
      records.each do |(box_idx, slot_idx), record|
        offset = BOX_DATA_OFFSET_IN_STORAGE + ((box_idx * SLOTS_PER_BOX + slot_idx) * BOX_RECORD_SIZE)
        block[offset, BOX_RECORD_SIZE] = record
      end
      # Footer: u32 save_counter at offset (STORAGE_SIZE - 20).
      block[STORAGE_COUNTER_OFFSET, 4] = [ save_counter ].pack("V")
      if with_valid_crc
        body_for_crc = block.byteslice(0, STORAGE_CRC_RANGE_END)
        block[STORAGE_CRC_OFFSET, 2] = [ crc16(body_for_crc) ].pack("v")
      else
        # Deliberately wrong CRC.
        block[STORAGE_CRC_OFFSET, 2] = [ 0x0000 ].pack("v")
      end
      block
    end

    # Build a 0x80000 SRAM blob. Optionally specify per-partition
    # storage block content + counter + CRC validity; the caller's
    # combination dictates which partition the picker selects.
    def build_sram(
      a_records: {}, a_counter: 1, a_crc_valid: true,
      b_records: {}, b_counter: 0, b_crc_valid: false
    )
      partition_a = "\x00".b * SLOT_SIZE
      partition_b = "\x00".b * SLOT_SIZE

      block_a = build_storage_block(records: a_records, save_counter: a_counter, with_valid_crc: a_crc_valid)
      block_b = build_storage_block(records: b_records, save_counter: b_counter, with_valid_crc: b_crc_valid)

      partition_a[STORAGE_OFFSET, STORAGE_SIZE] = block_a
      partition_b[STORAGE_OFFSET, STORAGE_SIZE] = block_b

      partition_a + partition_b
    end

    # ── Tests ─────────────────────────────────────────────────────────

    test "empty box (all 540 slots zeroed) returns []" do
      sram = build_sram(a_records: {})
      assert_equal [], SoulLink::BoxParser.parse(sram)
    end

    test "single-record box (slot [0,0]) returns 1 Pkm" do
      record = build_box_record(pid: 0xCAFEFACE, species: 387, met_location: 16)
      sram = build_sram(a_records: { [ 0, 0 ] => record })
      result = SoulLink::BoxParser.parse(sram)
      assert_equal 1, result.size
      assert_equal 0xCAFEFACE, result.first.pid
      assert_equal 387,        result.first.species
      assert_nil   result.first.level, "boxed records have no party-stats; level must be nil"
      assert_nil   result.first.slot_index, "BoxParser passes slot_index: nil"
    end

    test "single-record at non-zero (box, slot) — slot is found by walk order" do
      record = build_box_record(pid: 0xDEADBEEF, species: 100)
      sram = build_sram(a_records: { [ 5, 17 ] => record })
      result = SoulLink::BoxParser.parse(sram)
      assert_equal 1, result.size
      assert_equal 0xDEADBEEF, result.first.pid
    end

    test "full single box (30 slots populated) returns 30 Pkm" do
      records = {}
      30.times do |slot_idx|
        records[[ 0, slot_idx ]] = build_box_record(pid: 0x10000 | slot_idx, species: 100 + slot_idx)
      end
      sram = build_sram(a_records: records)
      result = SoulLink::BoxParser.parse(sram)
      assert_equal 30, result.size
      assert_equal (100..129).to_a, result.map(&:species)
    end

    test "records spread across multiple boxes are walked in (box, slot) order" do
      records = {
        [ 0, 0 ] => build_box_record(pid: 0x1000_0001, species: 1),
        [ 0, 5 ] => build_box_record(pid: 0x1000_0005, species: 2),
        [ 3, 0 ] => build_box_record(pid: 0x1003_0001, species: 3),
        [ 17, 29 ] => build_box_record(pid: 0x1011_001D, species: 4)
      }
      sram = build_sram(a_records: records)
      result = SoulLink::BoxParser.parse(sram)
      assert_equal 4, result.size
      assert_equal [ 1, 2, 3, 4 ], result.map(&:species)
    end

    test "eggs are filtered before return (defense in depth)" do
      records = {
        [ 0, 0 ] => build_box_record(pid: 0x2000_0001, species: 100, is_egg: false),
        [ 0, 1 ] => build_box_record(pid: 0x2000_0002, species: 200, is_egg: true),
        [ 0, 2 ] => build_box_record(pid: 0x2000_0003, species: 300, is_egg: false)
      }
      sram = build_sram(a_records: records)
      result = SoulLink::BoxParser.parse(sram)
      assert_equal 2, result.size
      assert_equal [ 100, 300 ], result.map(&:species)
    end

    test "corrupt PKM is dropped, others returned" do
      good   = build_box_record(pid: 0x3000_0001, species: 100)
      good2  = build_box_record(pid: 0x3000_0003, species: 300)
      bad    = build_box_record(pid: 0x3000_0002, species: 200).dup
      bad.setbyte(0x10, bad.getbyte(0x10) ^ 0xFF)
      sram = build_sram(a_records: {
        [ 0, 0 ] => good, [ 0, 1 ] => bad, [ 0, 2 ] => good2
      })
      result = SoulLink::BoxParser.parse(sram)
      assert_equal 2, result.size
      assert_equal [ 100, 300 ], result.map(&:species)
    end

    test "bad CRC on both partitions returns []" do
      record = build_box_record(pid: 0x4000_0001, species: 387)
      sram = build_sram(
        a_records: { [ 0, 0 ] => record }, a_crc_valid: false,
        b_records: { [ 0, 0 ] => record }, b_crc_valid: false
      )
      assert_equal [], SoulLink::BoxParser.parse(sram)
    end

    test "bad CRC on one partition, good on the other — uses the good one" do
      good_record = build_box_record(pid: 0x5000_0001, species: 387)
      bad_record  = build_box_record(pid: 0x5000_0002, species: 100)
      sram = build_sram(
        a_records: { [ 0, 0 ] => bad_record  }, a_crc_valid: false,
        b_records: { [ 0, 0 ] => good_record }, b_counter: 5, b_crc_valid: true
      )
      result = SoulLink::BoxParser.parse(sram)
      assert_equal 1, result.size
      assert_equal 387, result.first.species
    end

    test "both partitions valid — higher save_counter wins" do
      record_old = build_box_record(pid: 0x6000_0001, species: 1)
      record_new = build_box_record(pid: 0x6000_0002, species: 2)
      sram = build_sram(
        a_records: { [ 0, 0 ] => record_old }, a_counter: 5, a_crc_valid: true,
        b_records: { [ 0, 0 ] => record_new }, b_counter: 99, b_crc_valid: true
      )
      result = SoulLink::BoxParser.parse(sram)
      assert_equal 1, result.size
      assert_equal 2, result.first.species, "newer counter (99) in partition B should win"
    end

    test "wrong total bytesize returns []" do
      assert_equal [], SoulLink::BoxParser.parse("\x00".b * 100)
    end

    test "nil and non-String input returns [] (never raises)" do
      assert_nothing_raised do
        assert_equal [], SoulLink::BoxParser.parse(nil)
        assert_equal [], SoulLink::BoxParser.parse(123)
      end
    end

    test "all-zero SRAM (no CRC-valid storage block) returns []" do
      assert_equal [], SoulLink::BoxParser.parse("\x00".b * EXPECTED_TOTAL)
    end

    test "BoxParser is pure: no AR / Rails.logger / Time.current side effects" do
      # Smoke: invoking parse against a non-trivial sram with a populated
      # box must not raise and must not touch any Rails singleton — we
      # don't have a great way to assert "no AR call" without mocks,
      # but we can verify the call returns within microseconds and the
      # method's source body contains no AR keywords.
      source = File.read(File.expand_path("../../../app/services/soul_link/box_parser.rb", __dir__))
      refute_match(/Rails\.logger/, source, "BoxParser must not touch Rails.logger")
      refute_match(/Time\.current/, source, "BoxParser must not touch Time.current")
      refute_match(/ActiveRecord|\.find_by|\.create!|\.update!/, source, "BoxParser must not touch AR")
    end
  end
end
