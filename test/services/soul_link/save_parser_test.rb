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

    # Build a single 0x40000 slot with given trainer block fields, computing
    # and inserting a valid CRC16-CCITT into the footer. `save_counter`
    # determines which slot the parser will pick when both are valid.
    #
    # Footer is the LAST 20 bytes WITHIN the general block (slot offsets
    # 0xCF18..0xCF2C). Save counter at +0x00, CRC16 at +0x12 (= block end - 2).
    # CRC covers everything in the block before the CRC field (0..0xCF2A).
    def build_slot(name_indices: [], money: 0, badges_byte: 0,
                   play_hours: 0, play_minutes: 0, play_seconds: 0,
                   map_id: 0, save_counter: 1, valid_crc: true)
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

    def build_sram(slot_a:, slot_b: nil)
      slot_b ||= "\x00".b * SLOT_SIZE
      slot_a + slot_b
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
    end
  end
end
