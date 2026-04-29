module SoulLink
  # Parses the trainer ("general") block out of a Pokemon Platinum (English)
  # SRAM dump and returns the user-facing fields the run roster sidebar needs.
  #
  # Phase 1 only: trainer name, money, play time, badges count, map id.
  # Pokemon party data and PC boxes are encrypted/scrambled and live in the
  # box ("large") block; those are out of scope here (Phase 2+).
  #
  # The parser is a pure function — no AR, no I/O, no side effects. Returns a
  # +Result+ struct on success and +nil+ on **any** error. The caller writes
  # nil columns; the sidebar renders "—". The parser must NEVER raise — a
  # malformed save should degrade gracefully.
  #
  # Layout reference (general block, English Platinum):
  # - https://projectpokemon.org/home/docs/gen-4/pkm-structure-r65/
  # - https://projectpokemon.org/home/docs/gen-4/save-file-structure-r113/
  # - pret/pokeplatinum disassembly (https://github.com/pret/pokeplatinum) —
  #   see `include/savedata.h` and `src/savedata` for block sizes & footer
  # - PKHeX SAV4Pt.cs for cross-checking offsets (read-only reference, no
  #   code copied — license)
  #
  # **Offset confidence:** the trainer name / gender / money / badges /
  # play-time offsets within the general block are well-documented across
  # all three sources and consistent. The map id offset is less commonly
  # documented; on a parse failure (or any unverified offset that returns a
  # nonsense value) the column stays nil and the sidebar simply omits the
  # field. See the per-constant comments below.
  class SaveParser
    SLOT_SIZE      = 0x40000      # 256KB per slot
    EXPECTED_TOTAL = 0x80000      # 512KB total file

    # Pokemon Platinum general-block size (bytes). The footer is the LAST 20
    # bytes WITHIN the block (NOT after it) — verified against a real Platinum
    # save on 2026-04-29. Footer layout from block-relative offset 0xCF18:
    #   +0x00 (4 bytes): save counter (used to pick the active slot)
    #   +0x04 (4 bytes): reserved/duplicate counter
    #   +0x08 (4 bytes): block size (0xCF2C)
    #   +0x0C (4 bytes): magic 0x20060623 (DP/Pt version)
    #   +0x10 (2 bytes): reserved (0x0000)
    #   +0x12 (2 bytes): CRC16-CCITT over bytes 0..0xCF2A (everything before CRC)
    # Source: pret/pokeplatinum SAVEDATA_PT_GENERAL_BLOCK_SIZE + dumped real save.
    GENERAL_BLOCK_SIZE        = 0xCF2C
    BLOCK_FOOTER_OFFSET       = 0xCF18           # footer starts here, within the block
    BLOCK_COUNTER_OFFSET      = 0xCF18           # save counter at start of footer
    BLOCK_CRC_OFFSET          = 0xCF2A           # 2 bytes before block end
    CRC_RANGE_END             = BLOCK_CRC_OFFSET # CRC covers bytes 0..0xCF2A (exclusive)

    # Trainer ("general") block field offsets within the slot.
    # English Pokemon Platinum. Source: Project Pokemon save-file docs +
    # pret/pokeplatinum (struct PlayerData / SaveData).
    NAME_OFFSET          = 0x0068  # 16 bytes (8 * uint16 chars), Gen IV charset
    NAME_BYTES           = 16
    GENDER_OFFSET        = 0x0078  # 1 byte (unused here; reserved for Phase 2)
    MONEY_OFFSET         = 0x0078 + 4  # 0x007C, 4 bytes LE (uint32)
    BADGES_OFFSET        = 0x0084  # 1-byte bitfield, 8 Sinnoh badges
    PLAY_HOURS_OFFSET    = 0x0086  # 2 bytes LE (uint16)
    PLAY_MINUTES_OFFSET  = 0x0088  # 1 byte
    PLAY_SECONDS_OFFSET  = 0x0089  # 1 byte
    # Map id ("current location"): less consistently documented than the
    # fields above. Returning nil on out-of-band values keeps the sidebar
    # honest if the offset turns out to be wrong for this game.
    MAP_ID_OFFSET        = 0x1234  # 2 bytes LE (uint16) — UNVERIFIED, see notes

    # Gen IV English character table (index → Unicode codepoint).
    # Source: https://projectpokemon.org/home/docs/gen-4/character-encoding-r68/
    # Only the English subset is implemented per the Phase 1 scope. Anything
    # outside the table renders as U+FFFD REPLACEMENT CHARACTER. Terminator
    # 0xFFFF stops decoding (the Pokemon-internal end-of-string marker).
    GEN4_CHAR_TABLE = {
      # Space + digits
      0x0001 => " ",
      0x0002 => "0", 0x0003 => "1", 0x0004 => "2", 0x0005 => "3", 0x0006 => "4",
      0x0007 => "5", 0x0008 => "6", 0x0009 => "7", 0x000A => "8", 0x000B => "9",
      # Uppercase A-Z
      0x000C => "A", 0x000D => "B", 0x000E => "C", 0x000F => "D", 0x0010 => "E",
      0x0011 => "F", 0x0012 => "G", 0x0013 => "H", 0x0014 => "I", 0x0015 => "J",
      0x0016 => "K", 0x0017 => "L", 0x0018 => "M", 0x0019 => "N", 0x001A => "O",
      0x001B => "P", 0x001C => "Q", 0x001D => "R", 0x001E => "S", 0x001F => "T",
      0x0020 => "U", 0x0021 => "V", 0x0022 => "W", 0x0023 => "X", 0x0024 => "Y",
      0x0025 => "Z",
      # Lowercase a-z
      0x0026 => "a", 0x0027 => "b", 0x0028 => "c", 0x0029 => "d", 0x002A => "e",
      0x002B => "f", 0x002C => "g", 0x002D => "h", 0x002E => "i", 0x002F => "j",
      0x0030 => "k", 0x0031 => "l", 0x0032 => "m", 0x0033 => "n", 0x0034 => "o",
      0x0035 => "p", 0x0036 => "q", 0x0037 => "r", 0x0038 => "s", 0x0039 => "t",
      0x003A => "u", 0x003B => "v", 0x003C => "w", 0x003D => "x", 0x003E => "y",
      0x003F => "z",
      # Common punctuation present in trainer names
      0x00AB => "!",
      0x00AC => "?",
      0x00AD => ",",
      0x00AE => ".",
      0x00B5 => "'",
      0x00B6 => "\""
    }.freeze

    REPLACEMENT_CHAR = "\u{FFFD}".freeze
    TERMINATOR       = 0xFFFF

    # CRC16-CCITT-FALSE: poly 0x1021, init 0xFFFF, no xorout, MSB-first.
    # The Gen IV save block footer uses this same variant.
    CRC_INIT = 0xFFFF
    CRC_POLY = 0x1021

    Result = Struct.new(
      :trainer_name,
      :money,
      :play_seconds,
      :badges_count,
      :map_id,
      keyword_init: true
    )

    class << self
      # @param bytes [String] raw decompressed save_data (binary encoding)
      # @return [Result, nil] Result on success, nil on any parse failure
      def parse(bytes)
        return nil unless bytes.is_a?(String)
        return nil if bytes.bytesize != EXPECTED_TOTAL

        slot = active_slot(bytes)
        return nil if slot.nil?

        Result.new(
          trainer_name: decode_name(slot.byteslice(NAME_OFFSET, NAME_BYTES)),
          money:        read_uint32_le(slot, MONEY_OFFSET),
          play_seconds: total_play_seconds(slot),
          badges_count: count_set_bits(slot.getbyte(BADGES_OFFSET).to_i),
          map_id:       safe_map_id(slot)
        )
      rescue StandardError
        # Any error -> nil. Wrapped because the caller's contract is to write
        # nil columns and render "—" rather than blow up the request.
        nil
      end

      private

      # Picks the active save slot. Algorithm: read the save_counter from
      # each slot's general-block footer, verify the CRC over the block
      # payload, and return the higher-counter slot whose CRC checks out.
      # Falls back to the other slot if the higher-counter one is corrupt;
      # returns nil if neither slot verifies.
      def active_slot(bytes)
        slot_a = bytes.byteslice(0, SLOT_SIZE)
        slot_b = bytes.byteslice(SLOT_SIZE, SLOT_SIZE)
        return nil if slot_a.nil? || slot_b.nil?

        a_ok = slot_valid?(slot_a)
        b_ok = slot_valid?(slot_b)

        case [ a_ok, b_ok ]
        when [ true,  true ]
          counter_a = read_save_counter(slot_a)
          counter_b = read_save_counter(slot_b)
          counter_b > counter_a ? slot_b : slot_a
        when [ true,  false ] then slot_a
        when [ false, true  ] then slot_b
        else nil
        end
      end

      # CRC verification over the general block. The footer is the last 20
      # bytes WITHIN the block; the CRC field is the last 2 bytes of the block;
      # the CRC covers everything in the block UP TO BUT NOT INCLUDING the
      # CRC field itself.
      def slot_valid?(slot)
        return false if slot.bytesize < GENERAL_BLOCK_SIZE

        body_for_crc  = slot.byteslice(0, CRC_RANGE_END)
        stored_crc_bs = slot.byteslice(BLOCK_CRC_OFFSET, 2)
        return false if body_for_crc.nil? || stored_crc_bs.nil? || stored_crc_bs.bytesize < 2

        stored_crc = stored_crc_bs.unpack1("v")
        computed   = crc16_ccitt(body_for_crc)
        stored_crc == computed
      rescue StandardError
        false
      end

      def read_save_counter(slot)
        chunk = slot.byteslice(BLOCK_COUNTER_OFFSET, 4)
        return 0 if chunk.nil? || chunk.bytesize < 4
        chunk.unpack1("V")
      end

      def crc16_ccitt(data)
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

      # Decodes 16 bytes (8 little-endian uint16 indices) into UTF-8.
      # Stops at terminator 0xFFFF. Unknown indices map to U+FFFD so a
      # surprising glyph never crashes the page.
      def decode_name(bytes)
        return "" if bytes.nil? || bytes.empty?
        out = +""
        # 8 chars max; walk in 2-byte little-endian indices.
        (0...(bytes.bytesize / 2)).each do |i|
          idx = bytes.byteslice(i * 2, 2).unpack1("v")
          break if idx == TERMINATOR
          next if idx.zero? # Padding / unset slot — skip rather than emit replacement.
          out << (GEN4_CHAR_TABLE[idx] || REPLACEMENT_CHAR)
        end
        out
      end

      def total_play_seconds(slot)
        h = slot.byteslice(PLAY_HOURS_OFFSET, 2).to_s.unpack1("v") || 0
        m = slot.getbyte(PLAY_MINUTES_OFFSET).to_i
        s = slot.getbyte(PLAY_SECONDS_OFFSET).to_i
        h * 3600 + m * 60 + s
      end

      def count_set_bits(byte)
        # Only the low 8 bits (8 Sinnoh badges) matter.
        (byte & 0xFF).to_s(2).count("1")
      end

      def read_uint32_le(slot, offset)
        chunk = slot.byteslice(offset, 4)
        return 0 if chunk.nil? || chunk.bytesize < 4
        chunk.unpack1("V")
      end

      # Map id reads as a uint16. Until validated against a real save we
      # treat 0 as "unknown / unset" so the sidebar can omit the field;
      # the offset itself is documented as unverified above.
      def safe_map_id(slot)
        chunk = slot.byteslice(MAP_ID_OFFSET, 2)
        return nil if chunk.nil? || chunk.bytesize < 2
        v = chunk.unpack1("v")
        v.zero? ? nil : v
      end
    end
  end
end
