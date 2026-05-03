module SoulLink
  # Walks the Pokemon Platinum party block out of a raw SRAM dump and
  # returns the decoded `Pkm` value objects for each occupied slot.
  #
  # **Contract: zero side effects, never raises.** Same shape as
  # `SaveParser` — pure function on input bytes, returns Array<Pkm> on
  # success and `[]` on any failure (no slot data to surface). Per-slot
  # decode errors are isolated by `PkmDecoder` (returns nil for that
  # one slot); we just skip those.
  #
  # **Eggs are filtered out before return** (per Step 17 brief decision
  # 11). When an egg hatches, the next parse sees the now-non-egg PID
  # appear in the diff as a "new" PID → fires `PokemonCaughtEvent`. Net
  # behavior: an egg is invisible to the auto-tracker until it hatches,
  # at which point it materializes as a "caught" event.
  #
  # ── Layout (cited from primary sources) ────────────────────────────
  #
  # The Party block sits at offset `0xA0` within the general/small save
  # block (the same block `SaveParser` reads trainer name / money /
  # badges from). Sources:
  # - PKHeX `PKHeX.Core/Saves/SAV4Pt.cs` `GetSAVOffsets()` →
  #   `Party = 0xA0` alongside `Trainer1 = 0x68` and `Extra = 0x2820`.
  #   **This closes KG-11.**
  # - pret/pokeplatinum `include/party.h:9-15`:
  #   ```
  #   typedef struct Party {
  #       int capacity;       // 0x00 — 4 bytes
  #       int currentCount;   // 0x04 — 4 bytes
  #       Pokemon pokemon[MAX_PARTY_SIZE];  // 0x08 — 6 * 236 bytes
  #   } Party;
  #   ```
  #   `MAX_PARTY_SIZE = 6` (constants/pokemon.h). Each `Pokemon` is a
  #   236-byte party-PKM record (`BoxPokemon` 136 bytes + `PartyPokemon`
  #   100 bytes — see `include/struct_defs/pokemon.h:120-157`).
  #
  # The savedata.h shows the save body lives in `SaveDataBody.data`
  # (a contiguous u8 buffer) and the per-block offsets are recorded
  # at runtime via `SaveBlockInfo`. PKHeX's `0xA0` is the EFFECTIVE
  # static offset for an English Platinum cartridge save — verified
  # against PKHeX's `SAV4Pt.cs` since the alternative (parsing the
  # runtime SaveBlockInfo table) would require decoding the save's
  # bookkeeping structs, which we don't have in scope.
  #
  # Note the `capacity` and `currentCount` fields are runtime-only
  # bookkeeping; we read `currentCount` (at +0x04) to know how many
  # slots to walk, then attempt PkmDecoder.decrypt on each. If the
  # count looks bogus (out of [0..6]), we fall back to walking all 6
  # slots and let PkmDecoder.decrypt nil out empty/corrupt ones.
  class PartyParser
    PARTY_OFFSET_IN_GENERAL_BLOCK = 0xA0

    PARTY_HEADER_SIZE             = 8        # capacity (u32) + currentCount (u32)
    PARTY_COUNT_OFFSET            = 4        # within the 8-byte header

    PARTY_RECORD_SIZE             = SoulLink::PkmDecoder::PARTY_SIZE  # 236
    MAX_PARTY_SIZE                = 6        # pret/pokeplatinum constants/pokemon.h
    PARTY_BLOCK_TOTAL_SIZE        = PARTY_HEADER_SIZE + (MAX_PARTY_SIZE * PARTY_RECORD_SIZE)

    # Same SaveParser constants for slot selection. Re-stated here so
    # changes to the SaveParser side stay loosely coupled.
    SLOT_SIZE                     = SoulLink::SaveParser::SLOT_SIZE          # 0x40000
    EXPECTED_TOTAL                = SoulLink::SaveParser::EXPECTED_TOTAL     # 0x80000
    GENERAL_BLOCK_SIZE            = SoulLink::SaveParser::GENERAL_BLOCK_SIZE # 0xCF2C

    class << self
      # @param save_data [String] raw decompressed full save (0x80000 bytes)
      # @return [Array<Pkm>] occupied & non-egg party slots, in slot order
      def parse(save_data)
        return [] unless save_data.is_a?(String)
        return [] if save_data.bytesize != EXPECTED_TOTAL

        slot = pick_active_slot(save_data)
        return [] if slot.nil?

        party_block = slot.byteslice(PARTY_OFFSET_IN_GENERAL_BLOCK, PARTY_BLOCK_TOTAL_SIZE)
        return [] if party_block.nil? || party_block.bytesize < PARTY_BLOCK_TOTAL_SIZE

        count = read_u32_le(party_block, PARTY_COUNT_OFFSET) || 0
        # If the count is out of bounds, fall back to walking all 6
        # slots and let PkmDecoder filter empties (a misaligned offset
        # would surface as "all 6 slots return nil from PkmDecoder",
        # i.e. an empty result — which is what we want).
        count = MAX_PARTY_SIZE unless count.between?(0, MAX_PARTY_SIZE)

        results = []
        count.times do |slot_index|
          record = party_block.byteslice(
            PARTY_HEADER_SIZE + (slot_index * PARTY_RECORD_SIZE),
            PARTY_RECORD_SIZE
          )
          next if record.nil? || record.bytesize != PARTY_RECORD_SIZE

          pkm = SoulLink::PkmDecoder.decrypt(record, slot_index: slot_index)
          next if pkm.nil?
          next if pkm.is_egg                # eggs filtered per brief decision 11
          next if pkm.species.to_i.zero?    # extra defense: empty slot

          results << pkm
        end
        results
      rescue StandardError
        []
      end

      private

      # Mirrors `SaveParser.active_slot` semantics — read the
      # save_counter from each slot's general-block footer, verify CRC,
      # return the higher-counter valid slot. Re-implemented (not
      # delegated) because `SaveParser.active_slot` is private; the
      # alternative would be to expose it, which couples the parsers
      # tighter than they need to be. Pure read, no AR.
      def pick_active_slot(bytes)
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

      def slot_valid?(slot)
        return false if slot.bytesize < GENERAL_BLOCK_SIZE
        body_for_crc  = slot.byteslice(0, SoulLink::SaveParser::CRC_RANGE_END)
        stored_crc_bs = slot.byteslice(SoulLink::SaveParser::BLOCK_CRC_OFFSET, 2)
        return false if body_for_crc.nil? || stored_crc_bs.nil? || stored_crc_bs.bytesize < 2
        stored_crc_bs.unpack1("v") == crc16_ccitt(body_for_crc)
      rescue StandardError
        false
      end

      def read_save_counter(slot)
        chunk = slot.byteslice(SoulLink::SaveParser::BLOCK_COUNTER_OFFSET, 4)
        return 0 if chunk.nil? || chunk.bytesize < 4
        chunk.unpack1("V")
      end

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

      def read_u32_le(bytes, offset)
        chunk = bytes.byteslice(offset, 4)
        return nil if chunk.nil? || chunk.bytesize < 4
        chunk.unpack1("V")
      end
    end
  end
end
