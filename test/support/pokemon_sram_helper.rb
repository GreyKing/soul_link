# Helpers for tests that need a Pokemon Platinum SRAM payload accepted by
# `SoulLink::SaveParser`. Builds the minimum valid 512KB image — slot A has
# a CRC16-CCITT footer matching the parser's expectations; slot B and the
# extra-block region (HoF) stay zero-padded (the parser tolerates that).
#
# Mirrors the same constants and CRC routine used in `save_parser_test.rb`
# rather than importing them, so a parser regression can't silently
# tautology-pass these tests.
module PokemonSramHelper
  SLOT_SIZE            = 0x40000
  EXPECTED_TOTAL       = 0x80000
  BLOCK_COUNTER_OFFSET = 0xCF18
  BLOCK_CRC_OFFSET     = 0xCF2A
  CRC_RANGE_END        = 0xCF18

  # Returns a 0x80000-byte string that `SoulLink::SaveParser.parse`
  # accepts (returns non-nil Result). Slot A's general block carries a
  # valid CRC over an otherwise-zero payload; that's enough for the
  # parser's slot-selection + CRC-validation path.
  def build_minimal_valid_sram(save_counter: 1)
    slot_a = "\x00".b * SLOT_SIZE
    slot_a[BLOCK_COUNTER_OFFSET, 4] = [ save_counter ].pack("V")
    crc = crc16_ccitt_for_sram(slot_a.byteslice(0, CRC_RANGE_END))
    slot_a[BLOCK_CRC_OFFSET, 2] = [ crc ].pack("v")

    slot_b = "\x00".b * SLOT_SIZE
    sram = slot_a + slot_b
    sram + ("\x00".b * (EXPECTED_TOTAL - sram.bytesize))
  end

  # CRC16-CCITT-FALSE: poly 0x1021, init 0xFFFF, no xorout, MSB-first.
  # Renamed from `crc16_ccitt` to avoid clashing with the same-named
  # helper in `save_parser_test.rb` when both modules co-load.
  def crc16_ccitt_for_sram(data)
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
end
