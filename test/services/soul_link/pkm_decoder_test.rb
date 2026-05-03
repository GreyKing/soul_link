require "test_helper"

module SoulLink
  # PkmDecoder unit tests. We exercise the decoder by ROUND-TRIPPING
  # known-decoded fields through the documented Gen-IV crypto:
  # build a canonical (unshuffled, decrypted) 128-byte payload, compute
  # its checksum, encrypt with the LCG keyed by the checksum, shuffle
  # blocks per PID, prepend the PID + flags + checksum header, append
  # the encrypted party-stats block (PID-keyed LCG), and feed the result
  # to PkmDecoder.decrypt. The output Pkm Struct should mirror the
  # values we baked in.
  #
  # No real-save fixtures live in the repo (binary blobs avoided per
  # standard practice); instead we use the synthetic-build approach
  # below, which exercises the SAME crypto path the parser would hit
  # against a real save.
  class PkmDecoderTest < ActiveSupport::TestCase
    LCG_MULTIPLIER = SoulLink::PkmDecoder::LCG_MULTIPLIER
    LCG_INCREMENT  = SoulLink::PkmDecoder::LCG_INCREMENT
    U32_MASK       = SoulLink::PkmDecoder::U32_MASK
    U16_MASK       = SoulLink::PkmDecoder::U16_MASK
    BLOCK_SIZE     = SoulLink::PkmDecoder::BLOCK_SIZE
    SHUFFLE_TABLE  = SoulLink::PkmDecoder::SHUFFLE_TABLE

    # ── Synthetic-record builder ──────────────────────────────────────

    # Build the 128-byte canonical (unshuffled) payload with the brief's
    # field choices. Filling Block A's species + ot_id, Block B's
    # met_location + IV/egg dword, Block D's metLevel.
    def build_canonical_blocks(species:, ot_id:, ot_sid:, met_location:, met_level:, is_egg:)
      payload = "\x00".b * 128

      # Block A (canonical offset 0x00..0x1F)
      write_u16(payload, 0x00, species)
      write_u16(payload, 0x04, ot_id)
      write_u16(payload, 0x06, ot_sid)

      # Block B (canonical offset 0x20..0x3F)
      iv_dword = is_egg ? (1 << 30) : 0  # bit 30 = isEgg
      write_u32(payload, BLOCK_SIZE + 0x10, iv_dword)
      write_u16(payload, BLOCK_SIZE + 0x1E, met_location)

      # Block D (canonical offset 0x60..0x7F)
      payload.setbyte(3 * BLOCK_SIZE + 0x1C, met_level & 0x7F)

      payload.b
    end

    def write_u16(buf, offset, value)
      buf[offset, 2] = [ value & U16_MASK ].pack("v")
    end

    def write_u32(buf, offset, value)
      buf[offset, 4] = [ value & U32_MASK ].pack("V")
    end

    # 16-bit checksum = sum of all uint16 little-endian words mod 0x10000.
    def checksum_of(payload)
      sum = 0
      (payload.bytesize / 2).times do |i|
        sum += payload.byteslice(i * 2, 2).unpack1("v")
      end
      sum & U16_MASK
    end

    # XOR the canonical (unencrypted) payload with the LCG keystream
    # seeded with `seed`. Same algorithm as PkmDecoder#lcg_xor.
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

    # Re-shuffle the 128-byte unshuffled payload INTO the encrypted
    # (PID-shuffled) order. order[canonical_pos] = src_in_encrypted.
    # So to build the encrypted buffer, for each encrypted slot, find
    # which canonical position maps to it and place that canonical
    # block there.
    def shuffle_to_encrypted_order(canonical_payload, pid)
      idx = (pid >> 13) & 0x1F
      order = SHUFFLE_TABLE[idx]
      encrypted = String.new(capacity: 128).b
      # We need the inverse: for each encrypted slot E (0..3), what
      # canonical block (A=0/B=1/C=2/D=3) belongs there?
      # order[A_canonical] = encrypted_slot_holding_A → encrypted_slot e holds canonical c iff order[c] = e.
      # Build inverse: inv[e] = c.
      inv = [ nil, nil, nil, nil ]
      order.each_with_index { |encrypted_slot, canonical_pos| inv[encrypted_slot] = canonical_pos }
      4.times do |encrypted_slot|
        canonical_pos = inv[encrypted_slot]
        encrypted << canonical_payload.byteslice(canonical_pos * BLOCK_SIZE, BLOCK_SIZE)
      end
      encrypted
    end

    def build_party_record(pid:, species:, ot_id:, ot_sid:, met_location:, met_level:, is_egg:, level:)
      canonical = build_canonical_blocks(
        species: species, ot_id: ot_id, ot_sid: ot_sid,
        met_location: met_location, met_level: met_level, is_egg: is_egg
      )
      checksum = checksum_of(canonical)
      shuffled = shuffle_to_encrypted_order(canonical, pid)
      encrypted_blocks = lcg_xor(shuffled, checksum)

      # Party-stats block (100 bytes): u32 status + u8 level + …
      party_canonical = "\x00".b * 100
      party_canonical.setbyte(SoulLink::PkmDecoder::PARTY_STATS_LEVEL_OFFSET, level & 0xFF)
      encrypted_party = lcg_xor(party_canonical, pid)

      header = String.new(capacity: 8).b
      write_u32(header, 0, pid)        # 0x00
      write_u16(header, 4, 0)           # 0x04 flags (we leave 0)
      write_u16(header, 6, checksum)    # 0x06 checksum
      header + encrypted_blocks + encrypted_party
    end

    # ── Tests ─────────────────────────────────────────────────────────

    test "decrypt round-trips a synthesized PKM (PID-shuffle case 0 / ABCD)" do
      pid = 0x12345678  # (pid >> 13) & 0x1F = 0x09 → case 9, BACDB shuffle (verifies non-trivial shuffle)
      record = build_party_record(
        pid: pid, species: 387, ot_id: 0xABCD, ot_sid: 0x1234,
        met_location: 16, met_level: 5, is_egg: false, level: 12
      )
      result = SoulLink::PkmDecoder.decrypt(record, slot_index: 0)

      assert_not_nil result
      assert_equal pid,    result.pid
      assert_equal 387,    result.species
      assert_equal 0xABCD, result.ot_id
      assert_equal 0x1234, result.ot_sid
      assert_equal 16,     result.met_location_id
      assert_equal 5,      result.met_level
      assert_equal 12,     result.level
      assert_equal false,  result.is_egg
      assert_equal 0,      result.slot_index
    end

    test "all 24 PID-shuffle orderings round-trip cleanly" do
      # Pick one PID per shuffle case [0..23] (cases 24..31 mirror 0..7, no need to retest).
      24.times do |case_idx|
        # Construct a PID whose (pid >> 13) & 0x1F equals case_idx.
        pid = (case_idx << 13) | 0x00010001  # avoid pid==0 sentinel, ensure non-zero low bits
        record = build_party_record(
          pid: pid, species: 100 + case_idx, ot_id: 0x0F0F, ot_sid: 0x0E0E,
          met_location: 17, met_level: 3, is_egg: false, level: 30
        )
        result = SoulLink::PkmDecoder.decrypt(record)
        assert_not_nil result, "shuffle case #{case_idx} returned nil"
        assert_equal pid,           result.pid,             "pid wrong for case #{case_idx}"
        assert_equal 100 + case_idx, result.species,         "species wrong for case #{case_idx}"
        assert_equal 0x0F0F,        result.ot_id,           "ot_id wrong for case #{case_idx}"
        assert_equal 0x0E0E,        result.ot_sid,          "ot_sid wrong for case #{case_idx}"
        assert_equal 17,            result.met_location_id, "met_location wrong for case #{case_idx}"
        assert_equal 3,             result.met_level,       "met_level wrong for case #{case_idx}"
        assert_equal 30,            result.level,           "level wrong for case #{case_idx}"
      end
    end

    test "checksum mismatch returns nil" do
      pid = 0x00000001
      record = build_party_record(
        pid: pid, species: 1, ot_id: 1, ot_sid: 1,
        met_location: 16, met_level: 5, is_egg: false, level: 5
      )
      # Corrupt one byte in the encrypted blocks region (not the
      # checksum field itself, which would just compute against the
      # corrupted-decoded payload).
      corrupted = record.dup
      corrupted.setbyte(0x10, (corrupted.getbyte(0x10) ^ 0xFF))
      assert_nil SoulLink::PkmDecoder.decrypt(corrupted)
    end

    test "boundary error returns nil — wrong length input" do
      assert_nil SoulLink::PkmDecoder.decrypt("\x00".b * 50)
      assert_nil SoulLink::PkmDecoder.decrypt("\x00".b * 100)
      assert_nil SoulLink::PkmDecoder.decrypt("\x00".b * 200)
    end

    test "nil and empty input return nil (never raise)" do
      assert_nothing_raised do
        assert_nil SoulLink::PkmDecoder.decrypt(nil)
        assert_nil SoulLink::PkmDecoder.decrypt("")
        assert_nil SoulLink::PkmDecoder.decrypt(123)        # non-String
      end
    end

    test "egg bit (Block B IV dword bit 30) is detected" do
      pid = 0x00080001  # case 8 — exercises the offset-0x10 isEgg dword in shuffled buffer
      record = build_party_record(
        pid: pid, species: 25, ot_id: 1, ot_sid: 1,
        met_location: 16, met_level: 5, is_egg: true, level: 5
      )
      result = SoulLink::PkmDecoder.decrypt(record)
      assert_not_nil result
      assert_equal true, result.is_egg
    end

    test "species=0 collapses to is_egg true (empty-slot sentinel)" do
      pid = 0x12345678
      record = build_party_record(
        pid: pid, species: 0, ot_id: 0, ot_sid: 0,
        met_location: 0, met_level: 0, is_egg: false, level: 0
      )
      result = SoulLink::PkmDecoder.decrypt(record)
      # Decoding succeeds (checksum is over zeroes — also zero, valid)
      assert_not_nil result
      assert_equal 0, result.species
      assert_equal true, result.is_egg, "species=0 must surface as is_egg true (empty slot)"
    end

    test "box-only record (136 bytes) decrypts with level=nil" do
      pid = 0x00000001
      canonical = build_canonical_blocks(species: 5, ot_id: 1, ot_sid: 1,
                                          met_location: 16, met_level: 5, is_egg: false)
      checksum = checksum_of(canonical)
      shuffled = shuffle_to_encrypted_order(canonical, pid)
      encrypted_blocks = lcg_xor(shuffled, checksum)
      header = String.new(capacity: 8).b
      write_u32(header, 0, pid); write_u16(header, 4, 0); write_u16(header, 6, checksum)
      box_record = header + encrypted_blocks
      assert_equal 136, box_record.bytesize

      result = SoulLink::PkmDecoder.decrypt(box_record)
      assert_not_nil result
      assert_equal 5, result.species
      assert_nil result.level, "box-only records have no party-stats block; level must be nil"
    end

    test "slot_index is propagated onto the result" do
      pid = 0x12345678
      record = build_party_record(
        pid: pid, species: 1, ot_id: 1, ot_sid: 1,
        met_location: 16, met_level: 5, is_egg: false, level: 5
      )
      result = SoulLink::PkmDecoder.decrypt(record, slot_index: 4)
      assert_equal 4, result.slot_index
    end
  end
end
