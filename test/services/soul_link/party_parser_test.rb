require "test_helper"

module SoulLink
  # PartyParser unit tests. Builds a synthetic 0x80000-byte SRAM blob
  # with a CRC-valid general block and a party block populated with N
  # PartyParser-compatible records (built via the same helper as the
  # PkmDecoder round-trip tests). Verifies count semantics, egg
  # filtering, and corrupt-record isolation.
  class PartyParserTest < ActiveSupport::TestCase
    SLOT_SIZE             = SoulLink::SaveParser::SLOT_SIZE          # 0x40000
    EXPECTED_TOTAL        = SoulLink::SaveParser::EXPECTED_TOTAL     # 0x80000
    GENERAL_BLOCK_SIZE    = SoulLink::SaveParser::GENERAL_BLOCK_SIZE # 0xCF2C
    BLOCK_FOOTER_OFFSET   = SoulLink::SaveParser::BLOCK_FOOTER_OFFSET
    BLOCK_CRC_OFFSET      = SoulLink::SaveParser::BLOCK_CRC_OFFSET
    CRC_INIT              = SoulLink::SaveParser::CRC_INIT
    CRC_POLY              = SoulLink::SaveParser::CRC_POLY

    PARTY_OFFSET          = SoulLink::PartyParser::PARTY_OFFSET_IN_GENERAL_BLOCK
    PARTY_RECORD_SIZE     = SoulLink::PartyParser::PARTY_RECORD_SIZE
    PARTY_HEADER_SIZE     = SoulLink::PartyParser::PARTY_HEADER_SIZE

    LCG_MULTIPLIER = SoulLink::PkmDecoder::LCG_MULTIPLIER
    LCG_INCREMENT  = SoulLink::PkmDecoder::LCG_INCREMENT
    U16_MASK       = SoulLink::PkmDecoder::U16_MASK
    U32_MASK       = SoulLink::PkmDecoder::U32_MASK
    BLOCK_SIZE     = SoulLink::PkmDecoder::BLOCK_SIZE
    SHUFFLE_TABLE  = SoulLink::PkmDecoder::SHUFFLE_TABLE

    # ── Helpers (mirrors PkmDecoderTest's synthetic builder) ─────────

    def build_party_record(pid:, species:, ot_id: 1, ot_sid: 1, met_location: 16,
                            met_level: 5, is_egg: false, level: 5)
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

      party_canonical = "\x00".b * 100
      party_canonical.setbyte(SoulLink::PkmDecoder::PARTY_STATS_LEVEL_OFFSET, level & 0xFF)
      encrypted_party = lcg_xor(party_canonical, pid)

      header = String.new(capacity: 8).b
      header << [ pid       & U32_MASK ].pack("V")
      header << [ 0 ].pack("v")
      header << [ checksum  & U16_MASK ].pack("v")
      header + encrypted_blocks + encrypted_party
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

    # CRC16-CCITT-FALSE (same as SaveParser).
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

    # Build a 0x80000 SRAM blob with one CRC-valid slot containing the
    # given party records.
    def build_sram(records: [], count_override: nil)
      slot = "\x00".b * SLOT_SIZE
      # Set the save_counter to 1 so the active-slot picker selects this slot.
      slot[SoulLink::SaveParser::BLOCK_COUNTER_OFFSET, 4] = [ 1 ].pack("V")

      # Party block: u32 capacity + u32 count + 6 * 236-byte records.
      count = count_override || records.size
      party_block = String.new(capacity: PARTY_HEADER_SIZE + 6 * PARTY_RECORD_SIZE).b
      party_block << [ 6 ].pack("V")        # capacity
      party_block << [ count ].pack("V")    # currentCount
      records.each do |r|
        party_block << r
      end
      remaining = (PARTY_HEADER_SIZE + 6 * PARTY_RECORD_SIZE) - party_block.bytesize
      party_block << ("\x00".b * remaining) if remaining > 0
      slot[PARTY_OFFSET, party_block.bytesize] = party_block

      # Compute and write CRC.
      body_for_crc = slot.byteslice(0, BLOCK_FOOTER_OFFSET)
      slot[BLOCK_CRC_OFFSET, 2] = [ crc16(body_for_crc) ].pack("v")

      # Slot B is all zeros (CRC won't validate; slot A wins).
      sram = slot + ("\x00".b * SLOT_SIZE)
      sram
    end

    # ── Tests ─────────────────────────────────────────────────────────

    test "empty party (count=0) returns []" do
      sram = build_sram(records: [], count_override: 0)
      assert_equal [], SoulLink::PartyParser.parse(sram)
    end

    test "single-Pokemon party returns one Pkm" do
      record = build_party_record(pid: 0x12345678, species: 387,
                                  met_location: 16, met_level: 5, level: 12)
      sram = build_sram(records: [ record ])
      result = SoulLink::PartyParser.parse(sram)
      assert_equal 1, result.size
      assert_equal 387, result.first.species
      assert_equal 12,  result.first.level
    end

    test "three-Pokemon party returns three Pkms with correct slot indices" do
      records = [
        build_party_record(pid: 0xAAAA1111, species: 100),
        build_party_record(pid: 0xBBBB2222, species: 200),
        build_party_record(pid: 0xCCCC3333, species: 300)
      ]
      sram = build_sram(records: records)
      result = SoulLink::PartyParser.parse(sram)
      assert_equal 3, result.size
      assert_equal [ 100, 200, 300 ], result.map(&:species)
      assert_equal [ 0, 1, 2 ],         result.map(&:slot_index)
    end

    test "full six-Pokemon party returns six Pkms" do
      records = (1..6).map { |i| build_party_record(pid: 0xDEAD0000 | i, species: 100 + i) }
      sram = build_sram(records: records)
      result = SoulLink::PartyParser.parse(sram)
      assert_equal 6, result.size
    end

    test "eggs are filtered out before return" do
      records = [
        build_party_record(pid: 0x11110001, species: 100, is_egg: false),
        build_party_record(pid: 0x22220002, species: 200, is_egg: true),  # egg → filtered
        build_party_record(pid: 0x33330003, species: 300, is_egg: false)
      ]
      sram = build_sram(records: records)
      result = SoulLink::PartyParser.parse(sram)
      assert_equal 2, result.size
      assert_equal [ 100, 300 ], result.map(&:species)
    end

    test "corrupt PKM is dropped, others returned" do
      good1 = build_party_record(pid: 0x11110001, species: 100)
      good2 = build_party_record(pid: 0x33330003, species: 300)
      bad   = build_party_record(pid: 0x22220002, species: 200).dup
      # Corrupt one byte in the encrypted blocks region of the bad record.
      bad.setbyte(0x10, bad.getbyte(0x10) ^ 0xFF)
      records = [ good1, bad, good2 ]
      sram = build_sram(records: records)
      result = SoulLink::PartyParser.parse(sram)
      assert_equal 2, result.size
      assert_equal [ 100, 300 ], result.map(&:species)
    end

    test "wrong total bytesize returns []" do
      assert_equal [], SoulLink::PartyParser.parse("\x00".b * 100)
    end

    test "nil and non-String input returns [] (never raises)" do
      assert_nothing_raised do
        assert_equal [], SoulLink::PartyParser.parse(nil)
        assert_equal [], SoulLink::PartyParser.parse(123)
      end
    end

    test "SRAM with no CRC-valid slot returns []" do
      assert_equal [], SoulLink::PartyParser.parse("\x00".b * EXPECTED_TOTAL)
    end

    test "out-of-bounds count falls back to walking all 6 slots" do
      records = (1..3).map { |i| build_party_record(pid: 0xDEAD0000 | i, species: 100 + i) }
      # Set count_override = 99 (bogus). Records 1-3 are valid; slots 4-6
      # are zero-filled and PkmDecoder returns nil for those (zero bytes
      # → checksum 0 of all-zero is 0; zero PID; species=0; surfaces as
      # is_egg=true and gets filtered out).
      sram = build_sram(records: records, count_override: 99)
      result = SoulLink::PartyParser.parse(sram)
      # 3 valid + 0 from empty slots after filtering
      assert_equal 3, result.size
      assert_equal [ 101, 102, 103 ], result.map(&:species)
    end
  end
end
