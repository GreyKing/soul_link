module SoulLink
  # Walks the Pokemon Platinum **storage** (PC-box) block out of a raw
  # SRAM dump and returns the decoded `Pkm` value objects for each
  # occupied slot across all 18 boxes × 30 slots.
  #
  # **Contract: zero side effects, never raises.** Same shape as
  # `PartyParser` — pure function on input bytes, returns Array<Pkm>
  # (size 0..540) on success and `[]` on any failure. Per-slot decode
  # errors are isolated by `PkmDecoder` (returns nil for the corrupt
  # slot); the rest of the box is still surfaced.
  #
  # Eggs are filtered before return (mirrors `PartyParser` decision 11).
  # Boxed eggs that hatch will appear later as a "new PID" in the
  # party-side diff path.
  #
  # ── Layout (cited from primary sources) ────────────────────────────
  #
  # The storage block sits in each save partition immediately after
  # the general block. PKHeX `PKHeX.Core/Saves/SAV4Pt.cs` declares:
  #
  #   public const  int GeneralSize = 0xCF2C;
  #   private const int StorageSize = 0x121E4; // Start 0xCF2C, +4 starts box data
  #
  # — the storage block follows the general block within the partition,
  # and the FIRST 4 bytes of the storage block are the "current box
  # index" pointer (0..17). Box-PKM records start at storage block
  # offset 0x04.
  #
  # Layout summary inside the storage block:
  #
  #   0x000..0x003       u32 currentBoxIndex (0..17, informational)
  #   0x004..0x11EE3     18 boxes × 30 slots × 136-byte box-PKM records
  #                      (= 0x11EE0 bytes total)
  #   0x11EE4..0x121CF   box names / wallpapers / etc. (we ignore)
  #   0x121D0..0x121E3   20-byte block footer
  #                        +0x00 u32 saveCounter
  #                        +0x04 u32 blockCounter
  #                        +0x08 u32 size
  #                        +0x0C u32 signature
  #                        +0x10 u8  blockID
  #                        +0x12 u16 checksum (CRC-16-CCITT-FALSE)
  #
  # Footer structure is identical to the general block — pret/pokeplatinum
  # `include/savedata.h` defines a single `SaveBlockFooter` struct used
  # by both blocks, and PKHeX uses the same `Checksums.CRC16_CCITT(...)`
  # validator + `^2..` CRC location for both. Counter is at footer +0
  # (block size - 20), CRC at footer +0x12 (block size - 2).
  #
  # Active partition pick: each partition (0x40000 bytes) carries its
  # OWN storage block. The active storage block can live in a different
  # partition than the active general block (PKHeX swaps them
  # independently via `StorageBlockPosition`). We re-implement the
  # partition picker pointed at the storage range and select the higher
  # save_counter among CRC-valid candidates.
  class BoxParser
    # ── Storage block layout ─────────────────────────────────────────
    STORAGE_OFFSET_IN_PARTITION   = 0xCF2C   # = SAV4Pt.GeneralSize; storage starts where general ends
    STORAGE_SIZE                  = 0x121E4  # SAV4Pt.StorageSize
    BOX_DATA_OFFSET_IN_STORAGE    = 4        # first 4 bytes are currentBoxIndex (PKHeX comment cites this)

    # Box content dimensions.
    BOX_COUNT                     = 18       # PKHeX SAV4 BoxCount = 18
    SLOTS_PER_BOX                 = 30       # PKHeX SAV4 BoxSlotCount = 30
    BOX_RECORD_SIZE               = SoulLink::PkmDecoder::BOX_SIZE  # 136 bytes (no party stats)
    BOX_DATA_TOTAL_SIZE           = BOX_COUNT * SLOTS_PER_BOX * BOX_RECORD_SIZE  # 0x11EE0

    # Storage-block footer offsets (mirrors general-block layout — the
    # `SaveBlockFooter` struct is shared in pret/pokeplatinum).
    STORAGE_FOOTER_SIZE           = 20
    STORAGE_FOOTER_OFFSET         = STORAGE_SIZE - STORAGE_FOOTER_SIZE  # 0x121D0
    STORAGE_COUNTER_OFFSET        = STORAGE_FOOTER_OFFSET               # 0x121D0 (u32 saveCounter at footer +0)
    STORAGE_CRC_OFFSET            = STORAGE_SIZE - 2                    # 0x121E2 (u16 checksum, last 2 bytes)
    # CRC body is `data[..^FooterSize]` per PKHeX SAV4.cs:113
    # (`Checksums.CRC16_CCITT(data[..^FooterSize])`) with FooterSize = 0x14
    # for SAV4Sinnoh (SAV4Sinnoh.cs:12). So the CRC excludes the entire
    # 20-byte footer, NOT just the trailing 2-byte CRC field — i.e.
    # `block_size - 20`, not `block_size - 2`. Same lesson SaveParser
    # learned empirically (see save_parser.rb:46-49: 0..0xCF18 vs 0..0xCF2A).
    STORAGE_CRC_RANGE_END         = STORAGE_FOOTER_OFFSET               # 0x121D0 — body excludes full footer

    # Re-stated SaveParser constants (kept loosely coupled — same as
    # PartyParser's pattern).
    SLOT_SIZE                     = SoulLink::SaveParser::SLOT_SIZE          # 0x40000
    EXPECTED_TOTAL                = SoulLink::SaveParser::EXPECTED_TOTAL     # 0x80000

    class << self
      # @param save_data [String] raw decompressed full save (0x80000 bytes)
      # @return [Array<Pkm>] occupied & non-egg box slots, walked in
      #   (box, slot) order.
      def parse(save_data)
        return [] unless save_data.is_a?(String)
        return [] if save_data.bytesize != EXPECTED_TOTAL

        storage = pick_active_storage_block(save_data)
        return [] if storage.nil?

        results = []
        BOX_COUNT.times do |box_idx|
          SLOTS_PER_BOX.times do |slot_idx|
            offset = BOX_DATA_OFFSET_IN_STORAGE + ((box_idx * SLOTS_PER_BOX + slot_idx) * BOX_RECORD_SIZE)
            record = storage.byteslice(offset, BOX_RECORD_SIZE)
            next if record.nil? || record.bytesize != BOX_RECORD_SIZE

            pkm = SoulLink::PkmDecoder.decrypt(record, slot_index: nil)
            next if pkm.nil?
            next if pkm.is_egg
            next if pkm.species.to_i.zero?

            results << pkm
          end
        end
        results
      rescue StandardError
        []
      end

      private

      # Pick the active storage block. The two partitions hold mirror
      # storage blocks; we want the higher save_counter among the
      # CRC-valid candidates. The active storage partition can differ
      # from the active general partition — we read each partition's
      # storage block independently rather than reusing PartyParser's
      # general-block selection.
      def pick_active_storage_block(bytes)
        partition_a = bytes.byteslice(0,         SLOT_SIZE)
        partition_b = bytes.byteslice(SLOT_SIZE, SLOT_SIZE)
        return nil if partition_a.nil? || partition_b.nil?

        block_a = partition_a.byteslice(STORAGE_OFFSET_IN_PARTITION, STORAGE_SIZE)
        block_b = partition_b.byteslice(STORAGE_OFFSET_IN_PARTITION, STORAGE_SIZE)
        a_ok = block_a && storage_block_valid?(block_a)
        b_ok = block_b && storage_block_valid?(block_b)

        case [ a_ok, b_ok ]
        when [ true,  true ]
          counter_a = read_save_counter(block_a)
          counter_b = read_save_counter(block_b)
          counter_b > counter_a ? block_b : block_a
        when [ true,  false ] then block_a
        when [ false, true  ] then block_b
        else nil
        end
      end

      def storage_block_valid?(block)
        return false if block.bytesize < STORAGE_SIZE
        body_for_crc  = block.byteslice(0, STORAGE_CRC_RANGE_END)
        stored_crc_bs = block.byteslice(STORAGE_CRC_OFFSET, 2)
        return false if body_for_crc.nil? || stored_crc_bs.nil? || stored_crc_bs.bytesize < 2
        stored_crc_bs.unpack1("v") == crc16_ccitt(body_for_crc)
      rescue StandardError
        false
      end

      def read_save_counter(block)
        chunk = block.byteslice(STORAGE_COUNTER_OFFSET, 4)
        return 0 if chunk.nil? || chunk.bytesize < 4
        chunk.unpack1("V")
      end

      # CRC-16-CCITT-FALSE: poly 0x1021, init 0xFFFF, no xorout, MSB-first.
      # Re-uses SaveParser's polynomial / init constants — identical
      # variant the general block + HoF block use.
      def crc16_ccitt(data)
        crc = SoulLink::SaveParser::CRC_INIT
        data.each_byte do |byte|
          crc ^= (byte << 8)
          8.times do
            crc = (crc & 0x8000).zero? ? (crc << 1) : ((crc << 1) ^ SoulLink::SaveParser::CRC_POLY)
            crc &= 0xFFFF
          end
        end
        crc
      end
    end
  end
end
