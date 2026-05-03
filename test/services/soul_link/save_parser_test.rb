require "test_helper"

module SoulLink
  class SaveParserTest < ActiveSupport::TestCase
    # --- synthetic SRAM construction ---------------------------------------
    #
    # Pokemon Platinum SRAM is 0x80000 (512KB) total: two 0x40000 (256KB)
    # slots. A real save's general-block footer carries a CRC16-CCITT over
    # the block payload; we mirror that here so the parser's slot-selection
    # path exercises the production code rather than a synthetic shortcut.
    #
    # These helpers build a minimal SRAM image with controllable trainer
    # block fields. The parser only reads the general block + footer, so
    # we leave the rest of each slot zero-padded.

    SLOT_SIZE = SoulLink::SaveParser::SLOT_SIZE
    GENERAL_BLOCK_SIZE = SoulLink::SaveParser::GENERAL_BLOCK_SIZE
    EXPECTED_TOTAL = SoulLink::SaveParser::EXPECTED_TOTAL

    # Build a single 0x40000 slot with given trainer block fields, computing
    # and inserting a valid CRC16-CCITT into the footer. `save_counter`
    # determines which slot the parser will pick when both are valid.
    #
    # Footer is the LAST 20 bytes WITHIN the general block (slot offsets
    # 0xCF18..0xCF2C). Save counter at +0x00, CRC16 at +0x12 (= block end - 2).
    # CRC covers everything in the block before the CRC field (0..0xCF2A).
    def build_slot(name_indices: [], money: 0, badges_byte: 0,
                   play_hours: 0, play_minutes: 0, play_seconds: 0,
                   map_id: 0, save_counter: 1, valid_crc: true,
                   trainer_id: 0, secret_id: 0,
                   pokedex_caught_bits: 0, pokedex_seen_bits: 0)
      slot = "\x00".b * SLOT_SIZE

      # Trainer name: 8 little-endian uint16 indices, padded with 0x0000.
      name_bytes = name_indices.first(8).pack("v*")
      name_bytes += "\x00".b * (16 - name_bytes.bytesize)
      slot[SoulLink::SaveParser::NAME_OFFSET, 16] = name_bytes

      slot[SoulLink::SaveParser::MONEY_OFFSET, 4] = [ money ].pack("V")
      slot.setbyte(SoulLink::SaveParser::BADGES_OFFSET, badges_byte & 0xFF)
      slot[SoulLink::SaveParser::PLAY_HOURS_OFFSET, 2] = [ play_hours ].pack("v")
      slot.setbyte(SoulLink::SaveParser::PLAY_MINUTES_OFFSET, play_minutes & 0xFF)
      slot.setbyte(SoulLink::SaveParser::PLAY_SECONDS_OFFSET, play_seconds & 0xFF)
      slot[SoulLink::SaveParser::MAP_ID_OFFSET, 2] = [ map_id ].pack("v")

      slot[SoulLink::SaveParser::TRAINER_ID_OFFSET, 2] = [ trainer_id & 0xFFFF ].pack("v")
      slot[SoulLink::SaveParser::SECRET_ID_OFFSET, 2]  = [ secret_id  & 0xFFFF ].pack("v")

      # Pokédex caught/seen regions: write `pokedex_caught_bits` set
      # bits starting at species index 0 (sequential). Real saves set
      # bits at species-id positions, but for popcount tests the
      # arrangement doesn't matter — only the count does.
      if pokedex_caught_bits.positive?
        slot[SoulLink::SaveParser::POKEDEX_CAUGHT_OFFSET, SoulLink::SaveParser::POKEDEX_CAUGHT_BYTES] =
          bytes_with_n_bits_set(pokedex_caught_bits, SoulLink::SaveParser::POKEDEX_CAUGHT_BYTES)
      end
      if pokedex_seen_bits.positive?
        slot[SoulLink::SaveParser::POKEDEX_SEEN_OFFSET, SoulLink::SaveParser::POKEDEX_SEEN_BYTES] =
          bytes_with_n_bits_set(pokedex_seen_bits, SoulLink::SaveParser::POKEDEX_SEEN_BYTES)
      end

      # Save counter at footer start (block-relative 0xCF18, = BLOCK_COUNTER_OFFSET).
      slot[SoulLink::SaveParser::BLOCK_COUNTER_OFFSET, 4] = [ save_counter ].pack("V")

      # CRC over body bytes 0..CRC_RANGE_END (everything before the footer),
      # written at BLOCK_CRC_OFFSET (last 2 bytes of the block).
      crc_value = if valid_crc
        crc16_ccitt(slot.byteslice(0, SoulLink::SaveParser::CRC_RANGE_END))
      else
        0xDEAD
      end
      slot[SoulLink::SaveParser::BLOCK_CRC_OFFSET, 2] = [ crc_value ].pack("v")

      slot
    end

    def build_sram(slot_a:, slot_b: nil, hof_a: nil, hof_b: nil)
      slot_b ||= "\x00".b * SLOT_SIZE
      sram = slot_a + slot_b
      # Pad to the full 0x80000 file size (slots only take 0..0x80000;
      # the HoF / extra-block regions live at fixed absolute offsets but
      # are within the same 512KB file).
      sram = sram.b
      sram += "\x00".b * (EXPECTED_TOTAL - sram.bytesize) if sram.bytesize < EXPECTED_TOTAL
      sram = sram.byteslice(0, EXPECTED_TOTAL)

      # Hall of Fame block: primary at 0x20000, secondary mirror at
      # 0x60000. Either build_hof_block(...) (valid CRC) or pass raw
      # bytes for adversarial cases.
      if hof_a
        sram[SoulLink::SaveParser::HOF_PRIMARY_OFFSET, SoulLink::SaveParser::HOF_BLOCK_TOTAL_SIZE] = hof_a
      end
      if hof_b
        sram[SoulLink::SaveParser::HOF_PRIMARY_OFFSET + SoulLink::SaveParser::HOF_PARTITION_SIZE,
             SoulLink::SaveParser::HOF_BLOCK_TOTAL_SIZE] = hof_b
      end
      sram
    end

    # Build a 0x2AC0-byte HoF block with the given ClearCount and a
    # valid CRC16-CCITT footer. CRC covers everything before the last
    # 2 bytes (the CRC field itself). Set `valid_crc: false` to inject
    # a corruption that the parser must reject.
    def build_hof_block(clear_count:, valid_crc: true)
      block = "\x00".b * SoulLink::SaveParser::HOF_BLOCK_TOTAL_SIZE
      block[SoulLink::SaveParser::HOF_CLEAR_COUNT_OFFSET, 4] = [ clear_count ].pack("V")

      crc_value = if valid_crc
        crc16_ccitt(block.byteslice(0, SoulLink::SaveParser::HOF_CRC_RANGE_END))
      else
        0xDEAD
      end
      block[SoulLink::SaveParser::HOF_CRC_OFFSET, 2] = [ crc_value ].pack("v")
      block
    end

    # Returns `byte_length` bytes containing exactly `n` set bits,
    # starting from LSB of byte 0. Used to seed Pokédex caught/seen
    # regions with a known popcount.
    def bytes_with_n_bits_set(n, byte_length)
      raise ArgumentError if n > byte_length * 8
      out = "\x00".b * byte_length
      remaining = n
      byte_length.times do |i|
        break if remaining.zero?
        bits = [ remaining, 8 ].min
        out.setbyte(i, (1 << bits) - 1)
        remaining -= bits
      end
      out
    end

    # Mirror of the parser's CRC routine — kept inline so tests don't accidentally
    # become a tautology by reading the production constant under test.
    def crc16_ccitt(data)
      crc = 0xFFFF
      data.each_byte do |byte|
        crc ^= (byte << 8)
        8.times do
          crc = (crc & 0x8000).zero? ? (crc << 1) : ((crc << 1) ^ 0x1021)
          crc &= 0xFFFF
        end
      end
      crc
    end

    # Convenience: build name indices from a string of A-Za-z + space + digits.
    def name_indices_for(str)
      table = SoulLink::SaveParser::GEN4_CHAR_TABLE.invert
      str.chars.map { |ch| table.fetch(ch) }
    end

    # --- happy path ---------------------------------------------------------

    test "parses trainer name, money, play time, badges, map id from a valid synthetic save" do
      indices = name_indices_for("Lyra")
      slot = build_slot(
        name_indices: indices,
        money: 12_345,
        badges_byte: 0b00001111, # 4 badges set
        play_hours: 5,
        play_minutes: 30,
        play_seconds: 12,
        map_id: 426
      )
      sram = build_sram(slot_a: slot)

      result = SoulLink::SaveParser.parse(sram)

      assert_not_nil result, "expected parse to succeed on a synthetic well-formed save"
      assert_equal "Lyra",      result.trainer_name
      assert_equal 12_345,      result.money
      assert_equal 4,           result.badges_count
      assert_equal 5 * 3600 + 30 * 60 + 12, result.play_seconds
      assert_equal 426,         result.map_id
    end

    test "trainer name terminator stops decoding before padding" do
      # "Bob" + 0xFFFF terminator + 0x0000 padding. The terminator must
      # stop decoding so we don't render replacement chars.
      indices = name_indices_for("Bob") + [ 0xFFFF, 0x0000, 0x0000, 0x0000, 0x0000 ]
      slot = build_slot(name_indices: indices, money: 0, save_counter: 1)
      sram = build_sram(slot_a: slot)

      result = SoulLink::SaveParser.parse(sram)
      assert_not_nil result
      assert_equal "Bob", result.trainer_name
    end

    test "all 8 badges set produces badges_count of 8" do
      slot = build_slot(name_indices: name_indices_for("X"), badges_byte: 0xFF)
      sram = build_sram(slot_a: slot)

      result = SoulLink::SaveParser.parse(sram)
      assert_not_nil result
      assert_equal 8, result.badges_count
    end

    test "zero money, zero play time, zero badges decode cleanly (not nil)" do
      slot = build_slot(name_indices: name_indices_for("A"))
      sram = build_sram(slot_a: slot)

      result = SoulLink::SaveParser.parse(sram)
      assert_not_nil result
      assert_equal 0, result.money
      assert_equal 0, result.play_seconds
      assert_equal 0, result.badges_count
    end

    test "maxed money (999_999) decodes correctly" do
      slot = build_slot(name_indices: name_indices_for("A"), money: 999_999)
      sram = build_sram(slot_a: slot)

      result = SoulLink::SaveParser.parse(sram)
      assert_not_nil result
      assert_equal 999_999, result.money
    end

    # --- slot selection -----------------------------------------------------

    test "picks higher save_counter slot when both are valid" do
      slot_low  = build_slot(name_indices: name_indices_for("Old"), money: 100, save_counter: 5)
      slot_high = build_slot(name_indices: name_indices_for("New"), money: 200, save_counter: 7)

      result = SoulLink::SaveParser.parse(build_sram(slot_a: slot_low, slot_b: slot_high))
      assert_not_nil result
      assert_equal "New", result.trainer_name
      assert_equal 200,   result.money
    end

    test "falls back to the other slot when higher-counter slot has bad CRC" do
      slot_corrupt = build_slot(name_indices: name_indices_for("Bad"), save_counter: 9, valid_crc: false)
      slot_good    = build_slot(name_indices: name_indices_for("Ok"), save_counter: 4, valid_crc: true)

      result = SoulLink::SaveParser.parse(build_sram(slot_a: slot_corrupt, slot_b: slot_good))
      assert_not_nil result
      assert_equal "Ok", result.trainer_name
    end

    test "returns nil when both slots have invalid CRC" do
      slot_a = build_slot(name_indices: name_indices_for("Aa"), save_counter: 3, valid_crc: false)
      slot_b = build_slot(name_indices: name_indices_for("Bb"), save_counter: 4, valid_crc: false)

      result = SoulLink::SaveParser.parse(build_sram(slot_a: slot_a, slot_b: slot_b))
      assert_nil result
    end

    # --- failure paths ------------------------------------------------------

    test "returns nil for nil input" do
      assert_nil SoulLink::SaveParser.parse(nil)
    end

    test "returns nil for non-string input" do
      assert_nil SoulLink::SaveParser.parse(42)
      assert_nil SoulLink::SaveParser.parse([])
      assert_nil SoulLink::SaveParser.parse({})
    end

    test "returns nil for empty string" do
      assert_nil SoulLink::SaveParser.parse("")
    end

    test "returns nil for input of wrong size (smaller than 0x80000)" do
      assert_nil SoulLink::SaveParser.parse("\x00".b * 1024)
    end

    test "returns nil for input of wrong size (larger than 0x80000)" do
      assert_nil SoulLink::SaveParser.parse("\x00".b * (0x80000 + 1))
    end

    test "returns nil for garbage input of correct size" do
      # Random bytes — the CRC will not match by overwhelming probability.
      garbage = SecureRandom.random_bytes(0x80000)
      assert_nil SoulLink::SaveParser.parse(garbage)
    end

    test "never raises on adversarial payloads" do
      [
        "\xFF".b * 0x80000,
        "\x00".b * 0x80000,
        "\xAA".b * 0x80000
      ].each do |payload|
        assert_nothing_raised { SoulLink::SaveParser.parse(payload) }
      end
    end

    # --- character decoding edge cases -------------------------------------

    test "unknown character index renders as U+FFFD replacement char" do
      # Inject an index that's not in the table (0x0500 is unmapped).
      indices = [ 0x012B, 0x0500, 0x012C ] # 'A', UNKNOWN, 'B'
      slot = build_slot(name_indices: indices)
      sram = build_sram(slot_a: slot)

      result = SoulLink::SaveParser.parse(sram)
      assert_not_nil result
      assert_equal "A\u{FFFD}B", result.trainer_name
    end

    test "padding bytes (0x0000) past the terminator do not produce extra chars" do
      # Single-char name, no explicit terminator — the rest of the field
      # is 0x00 padding from the build helper. Padding (0x0000) is *not*
      # the terminator; we treat it as "unset slot — skip" so we don't
      # spam replacement characters across the empty tail.
      indices = [ 0x012B ] # 'A'
      slot = build_slot(name_indices: indices)
      sram = build_sram(slot_a: slot)

      result = SoulLink::SaveParser.parse(sram)
      assert_not_nil result
      assert_equal "A", result.trainer_name
    end

    test "result has expected struct shape" do
      slot = build_slot(name_indices: name_indices_for("A"))
      result = SoulLink::SaveParser.parse(build_sram(slot_a: slot))
      assert_not_nil result
      assert_kind_of SoulLink::SaveParser::Result, result
      assert_respond_to result, :trainer_name
      assert_respond_to result, :money
      assert_respond_to result, :play_seconds
      assert_respond_to result, :badges_count
      assert_respond_to result, :map_id
      assert_respond_to result, :trainer_id
      assert_respond_to result, :secret_id
      assert_respond_to result, :pokedex_caught
      assert_respond_to result, :pokedex_seen
      assert_respond_to result, :hof_count
    end

    # ── Step 16: TID / SID ────────────────────────────────────────────────

    test "parses trainer_id (TID) at offset 0x0078 as little-endian uint16" do
      slot = build_slot(name_indices: name_indices_for("A"), trainer_id: 0x1234)
      result = SoulLink::SaveParser.parse(build_sram(slot_a: slot))

      assert_not_nil result
      assert_equal 0x1234, result.trainer_id
    end

    test "parses secret_id (SID) at offset 0x007A as little-endian uint16" do
      slot = build_slot(name_indices: name_indices_for("A"), secret_id: 0x5678)
      result = SoulLink::SaveParser.parse(build_sram(slot_a: slot))

      assert_not_nil result
      assert_equal 0x5678, result.secret_id
    end

    test "trainer_id and secret_id default to 0 when slot is all zeros" do
      slot = build_slot(name_indices: name_indices_for("A"))
      result = SoulLink::SaveParser.parse(build_sram(slot_a: slot))

      assert_not_nil result
      assert_equal 0, result.trainer_id
      assert_equal 0, result.secret_id
    end

    # ── Step 16: Pokédex caught/seen popcount ─────────────────────────────

    test "pokedex_caught popcount matches the number of set bits" do
      slot = build_slot(name_indices: name_indices_for("A"), pokedex_caught_bits: 47)
      result = SoulLink::SaveParser.parse(build_sram(slot_a: slot))

      assert_not_nil result
      assert_equal 47, result.pokedex_caught
    end

    test "pokedex_seen popcount matches the number of set bits" do
      slot = build_slot(name_indices: name_indices_for("A"), pokedex_seen_bits: 89)
      result = SoulLink::SaveParser.parse(build_sram(slot_a: slot))

      assert_not_nil result
      assert_equal 89, result.pokedex_seen
    end

    test "pokedex_caught is 0 when no bits are set (player hasn't caught anything)" do
      slot = build_slot(name_indices: name_indices_for("A"))
      result = SoulLink::SaveParser.parse(build_sram(slot_a: slot))

      assert_not_nil result
      assert_equal 0, result.pokedex_caught
      assert_equal 0, result.pokedex_seen
    end

    test "pokedex defensive cap: bit count > 493 returns nil for that field" do
      # 494 set bits exceeds POKEDEX_BIT_LIMIT (493 = NATIONAL_DEX_COUNT
      # for Sinnoh) — the offset must be wrong; surface nil so the view
      # omits the field rather than rendering nonsense.
      slot = build_slot(name_indices: name_indices_for("A"), pokedex_caught_bits: 494)
      result = SoulLink::SaveParser.parse(build_sram(slot_a: slot))

      assert_not_nil result
      assert_nil result.pokedex_caught
    end

    # ── Step 16: Hall of Fame ─────────────────────────────────────────────

    test "hof_count is 0 when valid HoF block contains ClearCount=0 (player hasn't entered HoF)" do
      slot = build_slot(name_indices: name_indices_for("A"))
      hof = build_hof_block(clear_count: 0)
      result = SoulLink::SaveParser.parse(build_sram(slot_a: slot, hof_a: hof))

      assert_not_nil result
      assert_equal 0, result.hof_count
    end

    test "hof_count is 1 when valid HoF block contains ClearCount=1 (player just entered HoF)" do
      slot = build_slot(name_indices: name_indices_for("A"))
      hof = build_hof_block(clear_count: 1)
      result = SoulLink::SaveParser.parse(build_sram(slot_a: slot, hof_a: hof))

      assert_not_nil result
      assert_equal 1, result.hof_count
    end

    test "hof_count is the higher of two valid partition mirrors" do
      slot = build_slot(name_indices: name_indices_for("A"))
      hof_primary   = build_hof_block(clear_count: 1)
      hof_secondary = build_hof_block(clear_count: 3)
      result = SoulLink::SaveParser.parse(build_sram(slot_a: slot, hof_a: hof_primary, hof_b: hof_secondary))

      assert_not_nil result
      assert_equal 3, result.hof_count
    end

    test "hof_count is nil when both HoF partitions have CRC fail (never false-positive completion)" do
      slot = build_slot(name_indices: name_indices_for("A"))
      hof_bad_a = build_hof_block(clear_count: 1, valid_crc: false)
      hof_bad_b = build_hof_block(clear_count: 1, valid_crc: false)
      result = SoulLink::SaveParser.parse(build_sram(slot_a: slot, hof_a: hof_bad_a, hof_b: hof_bad_b))

      assert_not_nil result
      assert_nil result.hof_count
    end

    test "hof_count falls back to the valid partition when one mirror is corrupt" do
      slot = build_slot(name_indices: name_indices_for("A"))
      hof_bad   = build_hof_block(clear_count: 1, valid_crc: false)
      hof_good  = build_hof_block(clear_count: 2)
      result = SoulLink::SaveParser.parse(build_sram(slot_a: slot, hof_a: hof_bad, hof_b: hof_good))

      assert_not_nil result
      assert_equal 2, result.hof_count
    end

    test "hof_count is nil when both HoF partitions are zero-padded (no init / fresh save)" do
      # A fresh ROM with no HoF data ever written has the block region
      # zero-padded. The CRC over all zeros is some specific value, NOT
      # 0x0000 (the stored field). So the CRC check fails on both
      # partitions and we return nil — distinct from "valid block, count
      # is 0" which means "player initialized the save but hasn't entered
      # HoF." Both render the same to the user (no completion pill), but
      # the parser's nil-vs-0 distinction matters for the diff layer.
      slot = build_slot(name_indices: name_indices_for("A"))
      result = SoulLink::SaveParser.parse(build_sram(slot_a: slot))

      assert_not_nil result
      assert_nil result.hof_count
    end

    # ── Step 16: backward compat ──────────────────────────────────────────

    test "existing fields populate alongside the new Step 16 fields" do
      slot = build_slot(
        name_indices: name_indices_for("Lyra"),
        money: 12_345,
        badges_byte: 0b00001111,
        play_hours: 5, play_minutes: 30, play_seconds: 12,
        map_id: 426,
        trainer_id: 0xABCD, secret_id: 0x1357,
        pokedex_caught_bits: 50, pokedex_seen_bits: 75
      )
      hof = build_hof_block(clear_count: 1)
      result = SoulLink::SaveParser.parse(build_sram(slot_a: slot, hof_a: hof))

      assert_not_nil result
      # Step 1-pre fields untouched.
      assert_equal "Lyra", result.trainer_name
      assert_equal 12_345, result.money
      assert_equal 4,      result.badges_count
      assert_equal 426,    result.map_id
      # Step 16 fields populated.
      assert_equal 0xABCD, result.trainer_id
      assert_equal 0x1357, result.secret_id
      assert_equal 50,     result.pokedex_caught
      assert_equal 75,     result.pokedex_seen
      assert_equal 1,      result.hof_count
    end
  end
end
