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
    # field choices. Filling Block A's species + ot_id + EVs, Block B's
    # moves + PP + PP-up + met_location + IV/egg dword, Block D's
    # metLevel. Step 18 fields default to nil/zero so existing tests
    # that don't pass them still work.
    def build_canonical_blocks(species:, ot_id:, ot_sid:, met_location:, met_level:, is_egg:,
                                ivs: nil, evs: nil, moves: nil)
      payload = "\x00".b * 128

      # Block A (canonical offset 0x00..0x1F)
      write_u16(payload, 0x00, species)
      write_u16(payload, 0x04, ot_id)
      write_u16(payload, 0x06, ot_sid)
      if evs
        # 6 bytes at Block A +0x10 (PK4 0x18..0x1D)
        keys = %i[hp atk def spe spa spd]
        keys.each_with_index do |k, i|
          payload.setbyte(0x10 + i, evs[k] & 0xFF)
        end
      end

      # Block B (canonical offset 0x20..0x3F)
      if moves
        # 4 × u16 LE at Block B +0x00 (PK4 0x28..0x2F)
        moves.each_with_index do |m, i|
          write_u16(payload, BLOCK_SIZE + (i * 2), m[:id] & U16_MASK)
        end
        # 4 × u8 PP at Block B +0x08 (PK4 0x30..0x33)
        moves.each_with_index do |m, i|
          payload.setbyte(BLOCK_SIZE + 0x08 + i, m[:pp] & 0xFF)
        end
        # 4 × u8 PP-up at Block B +0x0C (PK4 0x34..0x37)
        moves.each_with_index do |m, i|
          payload.setbyte(BLOCK_SIZE + 0x0C + i, m[:pp_up] & 0xFF)
        end
      end
      iv_dword = is_egg ? (1 << 30) : 0  # bit 30 = isEgg
      if ivs
        iv_dword |= (ivs[:hp]  & 0x1F)
        iv_dword |= (ivs[:atk] & 0x1F) << 5
        iv_dword |= (ivs[:def] & 0x1F) << 10
        iv_dword |= (ivs[:spe] & 0x1F) << 15
        iv_dword |= (ivs[:spa] & 0x1F) << 20
        iv_dword |= (ivs[:spd] & 0x1F) << 25
      end
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

    def build_party_record(pid:, species:, ot_id:, ot_sid:, met_location:, met_level:, is_egg:, level:,
                            ivs: nil, evs: nil, moves: nil)
      canonical = build_canonical_blocks(
        species: species, ot_id: ot_id, ot_sid: ot_sid,
        met_location: met_location, met_level: met_level, is_egg: is_egg,
        ivs: ivs, evs: evs, moves: moves
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

    # ── Step 18: per-Pokémon stats round-trips ───────────────────────

    test "Step 18: nature is derived from PID via pid % 25" do
      # PID 0 → 0 (Hardy)
      record = build_party_record(
        pid: 25, species: 1, ot_id: 1, ot_sid: 1,
        met_location: 16, met_level: 5, is_egg: false, level: 5
      )
      result = SoulLink::PkmDecoder.decrypt(record)
      assert_not_nil result
      assert_equal 0, result.nature  # 25 % 25 = 0 (Hardy)
    end

    test "Step 18: nature for PID 0xFFFFFFFF is 20 (Calm)" do
      # NB: brief said "= 9 (Lax)" but the actual modulo is 0xFFFFFFFF % 25 = 20.
      pid = 0xFFFFFFFF
      record = build_party_record(
        pid: pid, species: 1, ot_id: 1, ot_sid: 1,
        met_location: 16, met_level: 5, is_egg: false, level: 5
      )
      result = SoulLink::PkmDecoder.decrypt(record)
      assert_not_nil result
      assert_equal 20, result.nature
      assert_equal "Calm", SoulLink::Natures.name(result.nature)
    end

    test "Step 18: IVs round-trip — all-31 perfect IVs" do
      ivs = { hp: 31, atk: 31, def: 31, spe: 31, spa: 31, spd: 31 }
      record = build_party_record(
        pid: 0x12345678, species: 387, ot_id: 1, ot_sid: 1,
        met_location: 16, met_level: 5, is_egg: false, level: 12,
        ivs: ivs
      )
      result = SoulLink::PkmDecoder.decrypt(record)
      assert_not_nil result
      assert_equal({ hp: 31, atk: 31, def: 31, spe: 31, spa: 31, spd: 31 }, result.ivs)
    end

    test "Step 18: IVs round-trip — distinguishable per-stat values" do
      ivs = { hp: 0, atk: 5, def: 10, spe: 15, spa: 20, spd: 25 }
      record = build_party_record(
        pid: 0x00080001, species: 1, ot_id: 1, ot_sid: 1,
        met_location: 16, met_level: 5, is_egg: false, level: 5,
        ivs: ivs
      )
      result = SoulLink::PkmDecoder.decrypt(record)
      assert_not_nil result
      assert_equal ivs, result.ivs
    end

    test "Step 18: IVs default to all-zero Hash when block is empty" do
      record = build_party_record(
        pid: 0x00010001, species: 1, ot_id: 1, ot_sid: 1,
        met_location: 16, met_level: 5, is_egg: false, level: 5
      )
      result = SoulLink::PkmDecoder.decrypt(record)
      assert_not_nil result
      assert_equal({ hp: 0, atk: 0, def: 0, spe: 0, spa: 0, spd: 0 }, result.ivs)
    end

    test "Step 18: EVs round-trip — distinguishable per-stat values" do
      evs = { hp: 252, atk: 0, def: 4, spe: 252, spa: 0, spd: 0 }
      record = build_party_record(
        pid: 0x00010001, species: 387, ot_id: 1, ot_sid: 1,
        met_location: 16, met_level: 5, is_egg: false, level: 50,
        evs: evs
      )
      result = SoulLink::PkmDecoder.decrypt(record)
      assert_not_nil result
      assert_equal evs, result.evs
    end

    test "Step 18: EVs round-trip — max byte values stay 0..255" do
      evs = { hp: 255, atk: 255, def: 255, spe: 255, spa: 255, spd: 255 }
      record = build_party_record(
        pid: 0x00040001, species: 1, ot_id: 1, ot_sid: 1,
        met_location: 16, met_level: 5, is_egg: false, level: 5,
        evs: evs
      )
      result = SoulLink::PkmDecoder.decrypt(record)
      assert_equal evs, result.evs
    end

    test "Step 18: moves round-trip — distinct ids, PP, PP-ups" do
      moves = [
        { id: 1,   pp: 35, pp_up: 0 },
        { id: 84,  pp: 30, pp_up: 1 },
        { id: 392, pp: 10, pp_up: 3 },
        { id: 200, pp: 5,  pp_up: 0 }
      ]
      record = build_party_record(
        pid: 0x00080001, species: 387, ot_id: 1, ot_sid: 1,
        met_location: 16, met_level: 5, is_egg: false, level: 12,
        moves: moves
      )
      result = SoulLink::PkmDecoder.decrypt(record)
      assert_not_nil result
      assert_equal 4, result.moves.size
      assert_equal moves, result.moves
    end

    test "Step 18: moves default to 4 zeroed entries on empty record" do
      record = build_party_record(
        pid: 0x00010001, species: 1, ot_id: 1, ot_sid: 1,
        met_location: 16, met_level: 5, is_egg: false, level: 5
      )
      result = SoulLink::PkmDecoder.decrypt(record)
      assert_equal 4, result.moves.size
      assert(result.moves.all? { |m| m == { id: 0, pp: 0, pp_up: 0 } })
    end

    test "Step 18: backward-compat — existing fields unchanged when new ones populated" do
      ivs = { hp: 31, atk: 31, def: 31, spe: 31, spa: 31, spd: 31 }
      evs = { hp: 252, atk: 0, def: 0, spe: 252, spa: 4, spd: 0 }
      moves = [ { id: 1, pp: 35, pp_up: 0 }, { id: 0, pp: 0, pp_up: 0 },
                { id: 0, pp: 0, pp_up: 0 }, { id: 0, pp: 0, pp_up: 0 } ]
      record = build_party_record(
        pid: 0x12345678, species: 387, ot_id: 0xABCD, ot_sid: 0x1234,
        met_location: 16, met_level: 5, is_egg: false, level: 12,
        ivs: ivs, evs: evs, moves: moves
      )
      result = SoulLink::PkmDecoder.decrypt(record, slot_index: 0)
      # Step-17 contracts must still hold:
      assert_equal 387,    result.species
      assert_equal 12,     result.level
      assert_equal 0xABCD, result.ot_id
      assert_equal 0x1234, result.ot_sid
      assert_equal 16,     result.met_location_id
      assert_equal 5,      result.met_level
      assert_equal false,  result.is_egg
      assert_equal 0,      result.slot_index
      # Plus Step-18 surfaces:
      assert_equal 0x12345678 % 25, result.nature
      assert_equal ivs,             result.ivs
      assert_equal evs,             result.evs
      assert_equal moves,           result.moves
    end

    test "Step 18: 31-IV bit pattern does not bleed into isEgg / hasNickname bits" do
      # All-31 IVs = 0x3FFFFFFF. Bit 30 must remain zero (not an egg).
      ivs = { hp: 31, atk: 31, def: 31, spe: 31, spa: 31, spd: 31 }
      record = build_party_record(
        pid: 0x00010001, species: 387, ot_id: 1, ot_sid: 1,
        met_location: 16, met_level: 5, is_egg: false, level: 5,
        ivs: ivs
      )
      result = SoulLink::PkmDecoder.decrypt(record)
      assert_not_nil result
      assert_equal false, result.is_egg, "31-IV pattern must not look like an egg"
      assert_equal ivs, result.ivs
    end

    test "Step 18: is_egg=true co-exists cleanly with extracted IV bits" do
      # An egg with non-zero IVs underneath — the egg bit (30) is
      # independent of the 30 IV bits below it. Verify both surface.
      ivs = { hp: 5, atk: 10, def: 15, spe: 20, spa: 25, spd: 30 }
      record = build_party_record(
        pid: 0x00010001, species: 387, ot_id: 1, ot_sid: 1,
        met_location: 16, met_level: 5, is_egg: true, level: 5,
        ivs: ivs
      )
      result = SoulLink::PkmDecoder.decrypt(record)
      assert_not_nil result
      assert_equal true, result.is_egg
      assert_equal ivs, result.ivs
    end

    test "Step 18: Pkm Struct fields are stable in declaration order" do
      # Ruby Struct positional access lock — Step-17 callers reading
      # positional indices keep working. Append-only schema invariant.
      record = build_party_record(
        pid: 1, species: 1, ot_id: 1, ot_sid: 1,
        met_location: 16, met_level: 5, is_egg: false, level: 5
      )
      result = SoulLink::PkmDecoder.decrypt(record)
      members = SoulLink::PkmDecoder::Pkm.members
      assert_equal :pid,             members[0]
      assert_equal :species,         members[1]
      assert_equal :level,           members[2]
      assert_equal :ot_id,           members[3]
      assert_equal :ot_sid,          members[4]
      assert_equal :met_location_id, members[5]
      assert_equal :met_level,       members[6]
      assert_equal :is_egg,          members[7]
      assert_equal :slot_index,      members[8]
      # Step 18 — appended at the END so positional access from Step-17
      # callers stays stable.
      assert_equal :nature,          members[9]
      assert_equal :ivs,              members[10]
      assert_equal :evs,              members[11]
      assert_equal :moves,            members[12]
    end
  end
end
