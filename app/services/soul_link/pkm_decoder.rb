module SoulLink
  # Decrypts a single Generation-IV "party" PKM record (236 bytes) and
  # surfaces the per-Pokemon fields the Step 17 catch+route auto-tracker
  # needs. Box-only records (136 bytes) are also accepted — for those the
  # `level` field comes back nil because the level lives in the
  # party-only stats block (`0x88-0xEB`) which box records don't carry.
  #
  # **Contract: zero side effects, never raises.** Same shape as
  # `SaveParser` and `SaveDiff`. AR / Rails.logger / Time.current are
  # forbidden — pure integer arithmetic on the input bytes. Returns a
  # `Pkm` value object on success and `nil` on:
  #   - bad checksum (post-decrypt sum doesn't match stored checksum)
  #   - any boundary error (slice short, nil input, wrong length)
  #   - any other error caught by the top-level `rescue StandardError`
  #
  # The caller (`PartyParser`) treats nil as "skip this slot" and
  # carries on with the rest of the party — a corrupt PKM doesn't
  # poison the whole parse.
  #
  # ── Crypto layout (cited from primary sources) ─────────────────────
  #
  # Per record:
  #   0x00-0x03   PID            (uint32 LE, never encrypted)
  #   0x04-0x05   flags          (partyDecrypted/boxDecrypted/checksumFailed bits)
  #   0x06-0x07   checksum       (uint16 LE; also the LCG key for blocks A-D)
  #   0x08-0x87   data blocks    (4 × 32-byte blocks A/B/C/D; PID-shuffled and LCG-encrypted)
  #   0x88-0xEB   party stats    (PartyPokemon struct; second LCG keyed with PID)
  #
  # Sources:
  # - pret/pokeplatinum `include/struct_defs/pokemon.h:120-149`
  #   (`BoxPokemon { u32 personality; u16 flags; u16 checksum;
  #   PokemonDataBlock dataBlocks[4]; }` then `PartyPokemon { u32
  #   status; u8 level @ 0x08C; ... }`).
  # - pret/pokeplatinum `src/pokemon.c:317-349`
  #   (`Pokemon_EnterDecryptionContext` calls
  #   `Pokemon_DecryptData(&mon->party,  sizeof(PartyPokemon), mon->box.personality)`
  #   and
  #   `Pokemon_DecryptData(&mon->box.dataBlocks, sizeof(PokemonDataBlock)*4, mon->box.checksum)`).
  # - pret/pokeplatinum `src/math_util.c:217-234` + `include/math_util.h:8-9`
  #   (`EncodeData` walks half-words `data[i] ^= LCRNG_NextFrom(&seed)`,
  #   `LCRNG_MULTIPLIER = 1103515245 = 0x41C64E6D`,
  #   `LCRNG_INCREMENT = 24691 = 0x6073`,
  #   `LCRNG_NextFrom = (seed = seed*mult + inc; seed >> 16)`).
  # - PKHeX `PokeCrypto.cs` `Decrypt45`/`CryptArray`/`Shuffle45`
  #   (identical algorithm; cross-checks the table indices below).
  # - pret/pokeplatinum `src/pokemon.c:4861-4924`
  #   (`BoxPokemon_GetDataBlock` switch maps `(personality & 0x3E000) >> 13`
  #   ∈ [0..31] to one of 24 ABCD orderings; cases 24..31 collapse to
  #   cases 0..7. The 32-entry table below is a direct transcription).
  # - projectpokemon Gen-4 PKM-structure r65 doc — informal cross-check.
  #
  # ── PKM field offsets (post-decrypt, after un-shuffle to ABCD order) ─
  #
  # Block A (record 0x08-0x27, 32 bytes):
  #   +0x00  u16 species         → record offset 0x08
  #   +0x04  u32 otID            → record offsets 0x0C-0x0F (TID low + SID high)
  # Block B (record 0x28-0x47, 32 bytes):
  #   +0x10  u32 IV/Egg dword    → record offset 0x38; isEgg = bit 30
  #   +0x1E  u16 MetLocation_PtHGSS → record offset 0x46-0x47
  # Block D (record 0x68-0x87, 32 bytes):
  #   +0x1C  u8  metLevel : 7    → record offset 0x84 (mask 0x7F)
  # Party stats (record 0x88-0xEB, 100 bytes, encrypted with PID-LCG):
  #   +0x04  u8  level           → record offset 0x8C
  class PkmDecoder
    BOX_SIZE          = 136     # 0x88 — block-A..D end + flags + checksum + PID
    PARTY_SIZE        = 236     # 0xEC — BOX_SIZE + 100-byte party stats block
    DATA_BLOCKS_SIZE  = 128     # 0x80 — sum of 4 × 32-byte blocks A/B/C/D

    # Within the unshuffled 128-byte payload (canonical ABCD):
    BLOCK_SIZE        = 32      # 0x20

    # PKM record absolute offsets (within a 236-byte party record).
    PID_OFFSET        = 0x00
    CHECKSUM_OFFSET   = 0x06
    BLOCKS_OFFSET     = 0x08    # start of the 128-byte data-blocks region
    PARTY_STATS_OFFSET = 0x88   # start of the 100-byte party stats region

    # Field offsets within the 128-byte unshuffled (canonical ABCD) payload.
    # I.e. these are offsets into the buffer after un-shuffling, so
    # block A starts at 0x00, block B at 0x20, block C at 0x40, block D at 0x60.
    UNSHUFFLED_SPECIES_OFFSET     = 0x00              # block A +0x00
    UNSHUFFLED_OT_ID_OFFSET       = 0x04              # block A +0x04 (uint16 TID)
    UNSHUFFLED_OT_SID_OFFSET      = 0x06              # block A +0x06 (uint16 SID)
    UNSHUFFLED_IV_DWORD_OFFSET    = BLOCK_SIZE + 0x10 # block B +0x10 (0x30)
    UNSHUFFLED_MET_LOC_OFFSET     = BLOCK_SIZE + 0x1E # block B +0x1E (0x3E)
    UNSHUFFLED_MET_LEVEL_OFFSET   = (3 * BLOCK_SIZE) + 0x1C # block D +0x1C (0x7C)

    # Within the 100-byte decrypted party stats block:
    #   +0x00  u32 status, +0x04 u8 level
    PARTY_STATS_LEVEL_OFFSET      = 0x04

    IV_EGG_BIT                    = 30                # bit 30 of the IV dword

    # Gen-IV LCG (cited above):
    LCG_MULTIPLIER = 0x41C64E6D
    LCG_INCREMENT  = 0x6073
    U32_MASK       = 0xFFFFFFFF
    U16_MASK       = 0xFFFF

    # PID-shuffle ABCD orderings, indexed by `(pid >> 13) & 0x1F` ∈ [0..31].
    # Each entry is a 4-tuple `[a, b, c, d]` giving the ENCRYPTED-buffer
    # position of the canonical block. To unshuffle: `out[A_dest..A_dest+31] = enc[a*32..a*32+31]`
    # where A_dest = 0; same for B/C/D at canonical indices 1/2/3.
    #
    # Transcribed from pret/pokeplatinum src/pokemon.c:4861-4924
    # `BoxPokemon_GetDataBlock` switch statement. Cases 24..31 collapse
    # to cases 0..7 (via `% 24`); we mirror them here so the lookup is
    # a single-index table operation rather than `index % 24`.
    #
    # Verified against PKHeX `PokeCrypto.BlockPosition` (same table,
    # same indices).
    SHUFFLE_TABLE = [
      [ 0, 1, 2, 3 ], # case 0   (and 24)
      [ 0, 1, 3, 2 ], # case 1   (and 25)
      [ 0, 2, 1, 3 ], # case 2   (and 26)
      [ 0, 3, 1, 2 ], # case 3   (and 27)
      [ 0, 2, 3, 1 ], # case 4   (and 28)
      [ 0, 3, 2, 1 ], # case 5   (and 29)
      [ 1, 0, 2, 3 ], # case 6   (and 30)
      [ 1, 0, 3, 2 ], # case 7   (and 31)
      [ 2, 0, 1, 3 ], # case 8
      [ 3, 0, 1, 2 ], # case 9
      [ 2, 0, 3, 1 ], # case 10
      [ 3, 0, 2, 1 ], # case 11
      [ 1, 2, 0, 3 ], # case 12
      [ 1, 3, 0, 2 ], # case 13
      [ 2, 1, 0, 3 ], # case 14
      [ 3, 1, 0, 2 ], # case 15
      [ 2, 3, 0, 1 ], # case 16
      [ 3, 2, 0, 1 ], # case 17
      [ 1, 2, 3, 0 ], # case 18
      [ 1, 3, 2, 0 ], # case 19
      [ 2, 1, 3, 0 ], # case 20
      [ 3, 1, 2, 0 ], # case 21
      [ 2, 3, 1, 0 ], # case 22
      [ 3, 2, 1, 0 ], # case 23
      [ 0, 1, 2, 3 ], # case 24 = case 0
      [ 0, 1, 3, 2 ], # case 25 = case 1
      [ 0, 2, 1, 3 ], # case 26 = case 2
      [ 0, 3, 1, 2 ], # case 27 = case 3
      [ 0, 2, 3, 1 ], # case 28 = case 4
      [ 0, 3, 2, 1 ], # case 29 = case 5
      [ 1, 0, 2, 3 ], # case 30 = case 6
      [ 1, 0, 3, 2 ]  # case 31 = case 7
    ].map(&:freeze).freeze

    # Value object returned by `decrypt`. All Integer fields are
    # decoded straight from the (decrypted) PKM record. `slot_index`
    # is informational (0..5, set by `PartyParser`) — useful in tests
    # and logs, never load-bearing for AR.
    Pkm = Struct.new(
      :pid,
      :species,
      :level,
      :ot_id,
      :ot_sid,
      :met_location_id,
      :met_level,
      :is_egg,
      :slot_index,
      keyword_init: true
    )

    class << self
      # Decrypts one PKM record. Accepts a 236-byte (party) or 136-byte
      # (box) binary string. `slot_index` is propagated onto the result
      # for traceability; it has no semantic meaning during decode.
      #
      # @param bytes [String] raw binary PKM record
      # @param slot_index [Integer, nil] 0..5 for party slots; nil for box
      # @return [Pkm, nil] decoded value object, or nil on any failure
      def decrypt(bytes, slot_index: nil)
        return nil unless bytes.is_a?(String)
        size = bytes.bytesize
        return nil unless size == BOX_SIZE || size == PARTY_SIZE

        pid       = read_u32_le(bytes, PID_OFFSET)
        checksum  = read_u16_le(bytes, CHECKSUM_OFFSET)
        return nil if pid.nil? || checksum.nil?

        # Decrypt blocks A-D (128 bytes seeded with checksum) and
        # un-shuffle them to canonical ABCD order.
        encrypted_blocks = bytes.byteslice(BLOCKS_OFFSET, DATA_BLOCKS_SIZE)
        return nil if encrypted_blocks.nil? || encrypted_blocks.bytesize != DATA_BLOCKS_SIZE

        decrypted_blocks = lcg_xor(encrypted_blocks, checksum)
        # Verify checksum BEFORE unshuffling (sum is order-independent).
        return nil unless checksum_valid?(decrypted_blocks, checksum)

        unshuffled = unshuffle(decrypted_blocks, pid)

        # Decrypt the party stats region with a separate LCG seeded by
        # PID, when present. Box-only records (136 bytes) skip this and
        # return Pkm.level == nil.
        level = nil
        if size == PARTY_SIZE
          encrypted_party = bytes.byteslice(PARTY_STATS_OFFSET, PARTY_SIZE - PARTY_STATS_OFFSET)
          if encrypted_party && encrypted_party.bytesize == (PARTY_SIZE - PARTY_STATS_OFFSET)
            decrypted_party = lcg_xor(encrypted_party, pid)
            level = decrypted_party.getbyte(PARTY_STATS_LEVEL_OFFSET).to_i
          end
        end

        Pkm.new(
          pid:             pid,
          species:         read_u16_le(unshuffled, UNSHUFFLED_SPECIES_OFFSET),
          level:           level,
          ot_id:           read_u16_le(unshuffled, UNSHUFFLED_OT_ID_OFFSET),
          ot_sid:          read_u16_le(unshuffled, UNSHUFFLED_OT_SID_OFFSET),
          met_location_id: read_u16_le(unshuffled, UNSHUFFLED_MET_LOC_OFFSET),
          met_level:       (unshuffled.getbyte(UNSHUFFLED_MET_LEVEL_OFFSET).to_i & 0x7F),
          is_egg:          extract_egg_bit(unshuffled),
          slot_index:      slot_index
        )
      rescue StandardError
        nil
      end

      private

      # XOR an even-length binary string with the LCG keystream seeded
      # with the given 32-bit value. Returns a new binary String of the
      # same length. Mirrors pret/pokeplatinum `EncodeData` /
      # `DecodeData` (they are the same function — XOR is involutive).
      def lcg_xor(bytes, seed)
        seed &= U32_MASK
        out_words = []
        word_count = bytes.bytesize / 2
        word_count.times do |i|
          # LCRNG_NextFrom: seed = seed*mult + inc; return seed >> 16
          seed = ((seed * LCG_MULTIPLIER) + LCG_INCREMENT) & U32_MASK
          ks = (seed >> 16) & U16_MASK
          word = bytes.byteslice(i * 2, 2).unpack1("v")
          out_words << (word ^ ks)
        end
        out_words.pack("v*")
      end

      # Sum of all little-endian uint16 words in the decrypted blocks
      # region must equal the stored checksum (mod 0x10000). Same
      # algorithm as `Pokemon_GetDataChecksum` in pret/pokeplatinum
      # `src/pokemon.c:4827-4839`.
      def checksum_valid?(decrypted_blocks, expected_checksum)
        sum = 0
        (decrypted_blocks.bytesize / 2).times do |i|
          sum += decrypted_blocks.byteslice(i * 2, 2).unpack1("v")
        end
        (sum & U16_MASK) == (expected_checksum & U16_MASK)
      end

      # Re-orders the 4 × 32-byte blocks from PID-shuffled order into
      # canonical ABCD order. SHUFFLE_TABLE[idx] = [a, b, c, d] where
      # each entry is the SOURCE block index in the encrypted buffer.
      def unshuffle(blocks, pid)
        idx = (pid >> 13) & 0x1F
        order = SHUFFLE_TABLE[idx]
        result = String.new(capacity: DATA_BLOCKS_SIZE).b
        4.times do |canonical_pos|
          src_block = order[canonical_pos]
          result << blocks.byteslice(src_block * BLOCK_SIZE, BLOCK_SIZE)
        end
        result
      end

      def read_u32_le(bytes, offset)
        chunk = bytes.byteslice(offset, 4)
        return nil if chunk.nil? || chunk.bytesize < 4
        chunk.unpack1("V")
      end

      def read_u16_le(bytes, offset)
        chunk = bytes.byteslice(offset, 2)
        return 0 if chunk.nil? || chunk.bytesize < 2
        chunk.unpack1("v")
      end

      # Bit 30 of the IV/Egg/Nicknamed dword (Block B +0x10) flags egg.
      # Returns true iff the bit is set OR species is 0 (uninitialized
      # / egg sentinel — pret uses species 0 for no-Pokemon slots; we
      # collapse both to "is_egg / no Pokemon").
      def extract_egg_bit(unshuffled)
        chunk = unshuffled.byteslice(UNSHUFFLED_IV_DWORD_OFFSET, 4)
        return true if chunk.nil? || chunk.bytesize < 4
        dword = chunk.unpack1("V")
        species = read_u16_le(unshuffled, UNSHUFFLED_SPECIES_OFFSET)
        ((dword >> IV_EGG_BIT) & 1) == 1 || species.to_i.zero?
      end
    end
  end
end
