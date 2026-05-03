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
    # CRC covers bytes 0..0xCF18 — i.e., everything BEFORE the footer (not just
    # before the CRC field). Verified empirically against a real Platinum save
    # on 2026-04-29: variant `0..0xCF18 init=0xFFFF MSB poly=0x1021` produced
    # the matching stored CRC of 0x6C3C; `0..0xCF2A` produced 0x533D (off).
    CRC_RANGE_END             = BLOCK_FOOTER_OFFSET

    # Trainer ("general") block field offsets within the slot.
    # English Pokemon Platinum. Source: Project Pokemon save-file docs +
    # pret/pokeplatinum (struct PlayerData / SaveData) + PKHeX SAV4Pt.cs
    # offsets, cross-referenced against a real Platinum save dumped via
    # the soul_link:debug_save_offsets rake task on 2026-04-30.
    BADGES_OFFSET        = 0x0060  # 1-byte bitfield, 8 Sinnoh badges (verified)
    NAME_OFFSET          = 0x0068  # 16 bytes (8 * uint16 chars), Gen IV charset
    NAME_BYTES           = 16
    TRAINER_ID_OFFSET    = 0x0078  # 2 bytes LE (uint16) — unused here, doc only
    SECRET_ID_OFFSET     = 0x007A  # 2 bytes LE (uint16) — unused here, doc only
    MONEY_OFFSET         = 0x007C  # 4 bytes LE (uint32) — verified
    GENDER_OFFSET        = 0x0080  # 1 byte (unused here; reserved for Phase 2)
    # 0x0081 country, 0x0082 language, 0x0083 trainer-card avatar — unused
    # 0x0084 game version (0x0C = Pt) — was previously misread as BADGES_OFFSET,
    # which gave a constant "2 / 8" on every English Pt save (0x0C has two bits).
    PLAY_HOURS_OFFSET    = 0x0086  # 2 bytes LE (uint16) — verified
    PLAY_MINUTES_OFFSET  = 0x0088  # 1 byte — verified
    PLAY_SECONDS_OFFSET  = 0x0089  # 1 byte — verified
    # Map id ("current location"): less consistently documented than the
    # fields above. Returning nil on out-of-band values keeps the sidebar
    # honest if the offset turns out to be wrong for this game.
    MAP_ID_OFFSET        = 0x1234  # 2 bytes LE (uint16) — UNVERIFIED, see notes

    # ── Step 16: Pokédex caught/seen counters (KG-14) ─────────────────────
    #
    # Pokédex page within the general block. Layout (PKHeX SAV4Pt.cs +
    # pret/pokeplatinum include/pokedex.h `struct Pokedex`):
    #
    #   u32  magic
    #   u32  caughtPokemon[16]   ← 0x40 bytes, bit-per-species, region 0
    #   u32  seenPokemon[16]     ← 0x40 bytes, bit-per-species, region 1
    #   u32  recordedGenders[2][16] ← regions 2 + 3 (gender first/second)
    #   ...form/language/upgrade flags...
    #
    # Cited from primary sources (closes KG-14):
    # - PKHeX `PKHeX.Core/Saves/SAV4Pt.cs`: `private const int PokeDex = 0x1328;`
    # - PKHeX `PKHeX.Core/Saves/Substructures/PokeDex/Zukan4.cs`: comment
    #   block "Region 0: Caught (Captured/Owned) flags / Region 1: Seen
    #   flags", with `SIZE_REGION = 0x40` and `var ofs = 4 + (region *
    #   SIZE_REGION) + (index >> 3)` — the +4 skips the magic, then each
    #   region is 0x40 bytes of bit-per-species flags.
    # - pret/pokeplatinum `include/pokedex.h` `struct Pokedex` declares
    #   `u32 magic; u32 caughtPokemon[DEX_SIZE_U32]; u32
    #   seenPokemon[DEX_SIZE_U32]; ...` with `DEX_SIZE_U32 = 16`,
    #   identical layout.
    #
    # Bit-per-species, indexed by (species_id - 1). NATIONAL_DEX_COUNT in
    # pret = 493 (Sinnoh national dex max). Defensive cap: a popcount above
    # POKEDEX_BIT_LIMIT means the offset is wrong and we returned nonsense
    # — surface nil so the view omits the field rather than rendering
    # absurd numbers.
    POKEDEX_OFFSET           = 0x1328
    POKEDEX_MAGIC_BYTES      = 4
    POKEDEX_CAUGHT_OFFSET    = POKEDEX_OFFSET + POKEDEX_MAGIC_BYTES                # 0x132C
    POKEDEX_CAUGHT_BYTES     = 0x40                                                # 64 bytes = 512 bits
    POKEDEX_SEEN_OFFSET      = POKEDEX_CAUGHT_OFFSET + POKEDEX_CAUGHT_BYTES        # 0x136C
    POKEDEX_SEEN_BYTES       = 0x40                                                # 64 bytes = 512 bits
    POKEDEX_BIT_LIMIT        = 493                                                  # NATIONAL_DEX_COUNT (Sinnoh)

    # ── Step 16: Hall of Fame block ───────────────────────────────────────
    #
    # The HoF block lives OUTSIDE the two general/box slot pairs — it's
    # one of the "extra blocks" that sit at fixed absolute offsets in the
    # 512KB save file, NOT within either 0x40000 slot. Like the general
    # block, it's double-buffered (a primary copy and a backup mirror that
    # PartitionSize bytes apart). Both are written together when the
    # player enters the Hall of Fame, so picking either valid copy is
    # fine for our "did the player enter HoF?" question — we pick the
    # higher ClearCount among any CRC-valid copies.
    #
    # Cited from primary sources:
    # - PKHeX `PKHeX.Core/Saves/SAV4Pt.cs`: `ExtraBlocks => [ new(0,
    #   0x20000, 0x2AC0), // Hall of Fame, ... ]`. Block ID 0, absolute
    #   offset 0x20000, total size 0x2AC0 (= 0x2AB0 data + 0x10 footer).
    # - PKHeX `PKHeX.Core/Saves/Substructures/Gen4/Dendou4.cs`: layout is
    #   `Dendou4Record[30]` records (each 0x16C bytes) followed by
    #   `u32 IndexNextOverwrite` then `u32 ClearCount`. The footer
    #   (16 bytes) is `[u32 magic][u32 revision][s32 blockSize][u16
    #   blockID][u16 checksum]`. Checksum is CRC16-CCITT over the data
    #   region except the last 2 bytes (the checksum field itself).
    # - pret/pokeplatinum `include/savedata/save_table.h` defines
    #   `EXTRA_SAVE_TABLE_ENTRY_HALL_OF_FAME = 0` and
    #   `src/savedata/save_table.c` registers it via
    #   `HallOfFame_SaveSize` / `HallOfFame_Init` in the extra-save table.
    #
    # `hof_count` semantics (locked): for our Soul Link "run completion"
    # purposes, `hof_count == ClearCount` (number of times the player has
    # entered the HoF). `hof_count >= 1` means "this player has entered
    # HoF at least once" — that's all the run-completion AND-gate cares
    # about. Higher values (1 → 2 → ...) just mean repeat clears, also
    # treated as "completed" by our coordinator.
    #
    # On CRC fail OR any other error we return nil (NEVER 0) so a
    # corrupted HoF block can't false-positive a "Run complete" — the
    # coordinator's `>= 1` check on a nil-coerced-to-0 correctly fails.
    HOF_PRIMARY_OFFSET   = 0x20000
    HOF_PARTITION_SIZE   = SLOT_SIZE                         # mirror is +0x40000 → 0x60000
    HOF_BLOCK_TOTAL_SIZE = 0x2AC0                            # data (0x2AB0) + footer (0x10)
    HOF_DATA_SIZE        = 0x2AB0
    HOF_FOOTER_SIZE      = 0x10
    HOF_RECORD_COUNT     = 30
    HOF_RECORD_SIZE      = 0x16C
    HOF_END_DATA_OFFSET  = HOF_RECORD_COUNT * HOF_RECORD_SIZE  # 30 * 0x16C = 0x2AA8
    HOF_CLEAR_COUNT_OFFSET = HOF_END_DATA_OFFSET + 4           # 0x2AAC — u32 LE
    # Footer starts at HOF_DATA_SIZE (= 0x2AB0). CRC is the LAST 2 bytes of
    # the 0x2AC0 region, covering everything before it.
    HOF_FOOTER_OFFSET    = HOF_DATA_SIZE                       # 0x2AB0
    HOF_CRC_OFFSET       = HOF_BLOCK_TOTAL_SIZE - 2            # 0x2ABE
    HOF_CRC_RANGE_END    = HOF_CRC_OFFSET                      # CRC covers 0..0x2ABE

    # Gen IV English character table (index → Unicode codepoint).
    # Empirically verified against a real Pokemon Platinum save on 2026-04-29:
    # the trainer-name index 0x0131 corresponded to "G" in-game, which fixes
    # the offset of the alphanumeric block. Before that, an earlier
    # speculative table mapped A=0x000C and put trainer-name decoding into
    # U+FFFD-only territory.
    #
    # Layout: 0x0001 = space, digits start at 0x0121, uppercase at 0x012B,
    # lowercase at 0x0145. Punctuation is included for names that contain
    # apostrophes / quotes (some defaults do).
    #
    # Source: pret/pokeplatinum charmap_en.txt + Project Pokemon Gen-4
    # character encoding doc (https://projectpokemon.org/home/docs/).
    # Anything outside the table renders as U+FFFD REPLACEMENT CHARACTER.
    # Terminator 0xFFFF stops decoding.
    GEN4_CHAR_TABLE = {
      # Space
      0x0001 => " ",
      # Digits 0-9
      0x0121 => "0", 0x0122 => "1", 0x0123 => "2", 0x0124 => "3", 0x0125 => "4",
      0x0126 => "5", 0x0127 => "6", 0x0128 => "7", 0x0129 => "8", 0x012A => "9",
      # Uppercase A-Z
      0x012B => "A", 0x012C => "B", 0x012D => "C", 0x012E => "D", 0x012F => "E",
      0x0130 => "F", 0x0131 => "G", 0x0132 => "H", 0x0133 => "I", 0x0134 => "J",
      0x0135 => "K", 0x0136 => "L", 0x0137 => "M", 0x0138 => "N", 0x0139 => "O",
      0x013A => "P", 0x013B => "Q", 0x013C => "R", 0x013D => "S", 0x013E => "T",
      0x013F => "U", 0x0140 => "V", 0x0141 => "W", 0x0142 => "X", 0x0143 => "Y",
      0x0144 => "Z",
      # Lowercase a-z
      0x0145 => "a", 0x0146 => "b", 0x0147 => "c", 0x0148 => "d", 0x0149 => "e",
      0x014A => "f", 0x014B => "g", 0x014C => "h", 0x014D => "i", 0x014E => "j",
      0x014F => "k", 0x0150 => "l", 0x0151 => "m", 0x0152 => "n", 0x0153 => "o",
      0x0154 => "p", 0x0155 => "q", 0x0156 => "r", 0x0157 => "s", 0x0158 => "t",
      0x0159 => "u", 0x015A => "v", 0x015B => "w", 0x015C => "x", 0x015D => "y",
      0x015E => "z",
      # Common punctuation in trainer names
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
      :trainer_id,      # Step 16 — uint16, save-mix-up detection (TID)
      :secret_id,       # Step 16 — uint16, save-mix-up detection (SID)
      :pokedex_caught,  # Step 16 — popcount of caught region (0..493) or nil
      :pokedex_seen,    # Step 16 — popcount of seen region (0..493) or nil
      :hof_count,       # Step 16 — Hall of Fame ClearCount (0..9999) or nil on CRC fail
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
          trainer_name:   decode_name(slot.byteslice(NAME_OFFSET, NAME_BYTES)),
          money:          read_uint32_le(slot, MONEY_OFFSET),
          play_seconds:   total_play_seconds(slot),
          badges_count:   count_set_bits(slot.getbyte(BADGES_OFFSET).to_i),
          map_id:         safe_map_id(slot),
          trainer_id:     read_uint16_le(slot, TRAINER_ID_OFFSET),
          secret_id:      read_uint16_le(slot, SECRET_ID_OFFSET),
          pokedex_caught: count_pokedex_bits(slot, POKEDEX_CAUGHT_OFFSET, POKEDEX_CAUGHT_BYTES, POKEDEX_BIT_LIMIT),
          pokedex_seen:   count_pokedex_bits(slot, POKEDEX_SEEN_OFFSET,   POKEDEX_SEEN_BYTES,   POKEDEX_BIT_LIMIT),
          hof_count:      safe_hof_count(bytes)
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

      # Step 16 — 2-byte little-endian read with nil-safe boundary check.
      # Returns 0 (not nil) when the slice is missing/short, mirroring
      # `read_uint32_le`'s contract. Used for TID + SID; the diff layer
      # treats 0 as "unset / not yet parsed" and skips emission.
      def read_uint16_le(slot, offset)
        chunk = slot.byteslice(offset, 2)
        return 0 if chunk.nil? || chunk.bytesize < 2
        chunk.unpack1("v")
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

      # Step 16 — popcount the Pokédex caught/seen bit region. Returns
      # the number of set bits (which equals the number of unique
      # species ever caught/seen) or nil if the count exceeds
      # POKEDEX_BIT_LIMIT (a wrong-offset sentinel — see KG-14 closure
      # comment above the constants block). Nil on any boundary error
      # too — never raises.
      def count_pokedex_bits(slot, offset, byte_length, bit_limit)
        chunk = slot.byteslice(offset, byte_length)
        return nil if chunk.nil? || chunk.bytesize < byte_length
        total = 0
        chunk.each_byte do |byte|
          # Brian Kernighan's bit count via String#count is fast enough
          # for 64 bytes per region (~28 species per byte worst case).
          total += byte.to_s(2).count("1")
        end
        return nil if total > bit_limit
        total
      end

      # Step 16 — read Hall of Fame ClearCount across both partition
      # mirrors and return the higher CRC-valid value. Returns:
      #   - Integer (incl. 0) when at least one partition's CRC validates
      #   - nil when both partitions are corrupt (so the coordinator's
      #     `>= 1` check on a nil-coerced-to-0 correctly fails — never
      #     false-positive a "Run complete")
      def safe_hof_count(bytes)
        candidates = [
          extract_hof_count(bytes, HOF_PRIMARY_OFFSET),
          extract_hof_count(bytes, HOF_PRIMARY_OFFSET + HOF_PARTITION_SIZE)
        ].compact
        return nil if candidates.empty?
        candidates.max
      end

      # Returns the ClearCount for a single HoF partition, or nil if the
      # block boundary is out of range or the CRC fails. The "valid CRC
      # over an all-zero data region" case yields a real count of 0 —
      # that's a player who has not yet entered HoF on a save that has
      # at least been initialized.
      def extract_hof_count(bytes, base_offset)
        block = bytes.byteslice(base_offset, HOF_BLOCK_TOTAL_SIZE)
        return nil if block.nil? || block.bytesize < HOF_BLOCK_TOTAL_SIZE

        body_for_crc = block.byteslice(0, HOF_CRC_RANGE_END)
        stored_crc_bs = block.byteslice(HOF_CRC_OFFSET, 2)
        return nil if body_for_crc.nil? || stored_crc_bs.nil? || stored_crc_bs.bytesize < 2

        stored_crc = stored_crc_bs.unpack1("v")
        # PKHeX Dendou4 uses Checksums.CRC16_CCITT(GetRegion()[..^2]) —
        # same CRC16-CCITT-FALSE variant the general block uses. Reuse
        # the existing helper.
        return nil unless crc16_ccitt(body_for_crc) == stored_crc

        chunk = block.byteslice(HOF_CLEAR_COUNT_OFFSET, 4)
        return nil if chunk.nil? || chunk.bytesize < 4
        chunk.unpack1("V")
      rescue StandardError
        nil
      end
    end
  end
end
