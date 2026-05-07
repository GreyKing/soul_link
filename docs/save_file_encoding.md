# Pokémon Platinum Save File Encoding

This document is the rote-form reference for how a Pokémon Platinum SRAM
dump is structured on disk and how the Soul Link app decodes it. It
consolidates the knowledge accumulated across Steps 11–19 of the
auto-tracking pipeline (see `handoff/BUILD-LOG.md` for the per-step
history; this file is the durable reference that survives session
archival).

The audience is a future contributor (or future-you) who needs to fix a
bug in the parser, add a new field, or onboard the pipeline cold. Every
offset and algorithm cited here is also cited inline in the code; this
file does the joining-up between primary sources and our implementation
so nobody has to re-derive the picture from scratch.

Primary sources used throughout:

- **PKHeX** — kwsch's reference Pokémon save editor. We treat the
  source as documentation only (no code copied — license). Files cited
  by class name + method name. Repository:
  <https://github.com/kwsch/PKHeX>.
- **pret/pokeplatinum** — the decompilation of the Platinum ROM.
  Cited by header / source filename + struct or function name.
  Repository: <https://github.com/pret/pokeplatinum>.
- **Project Pokémon Gen-IV docs** — informal cross-checks, especially
  the PKM record structure (r65) and save-file structure (r113) docs.

---

## 1. What's in a Pokémon Platinum SRAM

A Pokémon Platinum cartridge save dump is a contiguous **0x80000-byte
(512 KB) binary blob**. The app receives it gzip-compressed via the
emulator save-slot upload flow and decompresses it before parsing.

The blob is split into two **0x40000-byte (256 KB) partitions**:

| Partition | File offset       | Size       |
|-----------|-------------------|------------|
| A         | `0x00000–0x3FFFF` | `0x40000`  |
| B         | `0x40000–0x7FFFF` | `0x40000`  |

Each partition contains a complete copy of the save state — **two
sub-blocks**:

| Sub-block       | Offset within partition | Size       | Contents                                                              |
|-----------------|-------------------------|------------|-----------------------------------------------------------------------|
| General block   | `0x00000–0x0CF2B`       | `0xCF2C`   | Trainer info, party, Pokédex flags, badges, money, play time, map ID  |
| Storage block   | `0x0CF2C–0x1F10F`       | `0x121E4`  | PC boxes (18 boxes × 30 slots × 136-byte box-PKM records)             |
| Unused          | `0x1F110–0x3FFFF`       | —          | Padding within the partition                                          |

The two partitions hold **mirrored copies** of these blocks. The game
double-buffers writes: when you save, it writes to the inactive
partition with an incremented save counter, then on next boot picks the
higher-counter partition that also has a valid CRC. That's how a
mid-write power loss can't brick the save — the prior copy is always
intact in the other partition.

A handful of additional **"extra blocks"** sit at fixed absolute
offsets in the 512 KB file, *outside* the two partitions. The only one
the app currently reads is the **Hall of Fame block** at `0x20000` (and
its mirror at `0x60000`).

Citation: PKHeX `PKHeX.Core/Saves/SAV4Pt.cs` declares the block sizes
(`GeneralSize = 0xCF2C`, `StorageSize = 0x121E4`) and `ExtraBlocks =>
[ new(0, 0x20000, 0x2AC0), … ]` for the HoF entry. pret/pokeplatinum's
`include/savedata.h` defines `SAVEDATA_PT_GENERAL_BLOCK_SIZE` matching
the same value.

The app implements partition / block discovery in three places, one per
parsed dimension, all driven from the same constants in
`SoulLink::SaveParser`:

- `app/services/soul_link/save_parser.rb` — general block (trainer,
  badges, money, Pokédex, TID/SID, HoF reference).
- `app/services/soul_link/party_parser.rb` — party slots (offset
  `0xA0` *within* the active general block).
- `app/services/soul_link/box_parser.rb` — PC boxes (storage block;
  picks its own active partition independently — see Section 4).

---

## 2. The save-block layout map

This is the complete catalogue of every byte the app currently reads
out of the SRAM, with file location, size, meaning, and the parser
that handles it.

### 2a. General block (within the active partition, base `0x00000` of partition)

Offsets are given relative to the **start of the block** — i.e. `0x00`
is the first byte of the block. To locate them in the raw SRAM file
add the partition base (`0x00000` for partition A, `0x40000` for B).

| Offset (block)   | Size  | Field                              | Parser & constant                               |
|------------------|-------|------------------------------------|-------------------------------------------------|
| `0x0060` (96)    | 1     | Badges bitfield (8 Sinnoh badges)  | `SaveParser::BADGES_OFFSET`                     |
| `0x0068` (104)   | 16    | Trainer name (8 × u16 Gen IV chars)| `SaveParser::NAME_OFFSET`                       |
| `0x0078` (120)   | 2     | Trainer ID (TID, u16 LE)           | `SaveParser::TRAINER_ID_OFFSET`                 |
| `0x007A` (122)   | 2     | Secret ID (SID, u16 LE)            | `SaveParser::SECRET_ID_OFFSET`                  |
| `0x007C` (124)   | 4     | Money (u32 LE)                     | `SaveParser::MONEY_OFFSET`                      |
| `0x0080` (128)   | 1     | Gender (unused)                    | `SaveParser::GENDER_OFFSET`                     |
| `0x0084` (132)   | 1     | Game version (`0x0C` = Pt)         | doc only                                        |
| `0x0086` (134)   | 2     | Play hours (u16 LE)                | `SaveParser::PLAY_HOURS_OFFSET`                 |
| `0x0088` (136)   | 1     | Play minutes                       | `SaveParser::PLAY_MINUTES_OFFSET`               |
| `0x0089` (137)   | 1     | Play seconds                       | `SaveParser::PLAY_SECONDS_OFFSET`               |
| `0x00A0` (160)   | 8     | Party header: capacity + count (u32 each) | `PartyParser::PARTY_OFFSET_IN_GENERAL_BLOCK` |
| `0x00A8` (168)   | 1416  | Party slots (6 × 236-byte party-PKM records) | `PartyParser::PARTY_RECORD_SIZE`         |
| `0x1234` (4660)  | 2     | Map ID (u16 LE) — **unverified**   | `SaveParser::MAP_ID_OFFSET` (KG-7 open)         |
| `0x1328` (4904)  | 4     | Pokédex magic (skip)               | `SaveParser::POKEDEX_OFFSET`                    |
| `0x132C` (4908)  | 64    | Pokédex `caughtPokemon[16]` u32 array — bit-per-species (region 0) | `SaveParser::POKEDEX_CAUGHT_OFFSET` |
| `0x136C` (4972)  | 64    | Pokédex `seenPokemon[16]` u32 array — bit-per-species (region 1)   | `SaveParser::POKEDEX_SEEN_OFFSET`   |
| `0xCF18` (52,984)| 4     | Save counter (u32 LE) — footer +0  | `SaveParser::BLOCK_COUNTER_OFFSET`              |
| `0xCF18`         | 20    | Block footer (counter / size / magic / reserved / CRC) | `SaveParser::BLOCK_FOOTER_OFFSET`   |
| `0xCF2A` (52,1006)| 2    | CRC-16 over `0x00..0xCF18` (footer-excluded) | `SaveParser::BLOCK_CRC_OFFSET`           |

The 20-byte footer's full layout is:

```
+0x00 (4)  saveCounter         (u32 LE)
+0x04 (4)  reserved/duplicate counter
+0x08 (4)  blockSize = 0xCF2C  (u32 LE)
+0x0C (4)  magic = 0x20060623  (DP/Pt version stamp)
+0x10 (2)  reserved 0x0000
+0x12 (2)  CRC-16-CCITT-FALSE  (u16 LE)
```

Citations:

- PKHeX `SAV4Pt.cs` `GetSAVOffsets()` for `Party = 0xA0`,
  `Trainer1 = 0x68`. Closes KG-11.
- PKHeX `SAV4Pt.cs` `private const int PokeDex = 0x1328` plus
  `Zukan4.cs` (`SIZE_REGION = 0x40`, region 0 = caught, region 1 =
  seen). Closes KG-14.
- pret/pokeplatinum `include/pokedex.h` `struct Pokedex` confirms
  `u32 magic; u32 caughtPokemon[16]; u32 seenPokemon[16]; …`.
- pret/pokeplatinum `include/party.h` `struct Party` confirms
  `int capacity; int currentCount; Pokemon[6];` for the party block.
- Trainer name / money / play-time offsets verified empirically against
  a real Platinum save dumped via the `soul_link:debug_save_offsets`
  rake task on 2026-04-30.
- `MAP_ID_OFFSET = 0x1234` is **unverified** (KG-7 is open) — the
  parser returns `nil` on zero so the sidebar omits the field rather
  than rendering a wrong value.

### 2b. Storage block (immediately after the general block in the same partition)

Storage starts at partition-relative offset `0xCF2C` and is `0x121E4`
bytes long. Layout:

| Offset (block)    | Size      | Field                                                       | Parser & constant                          |
|-------------------|-----------|-------------------------------------------------------------|--------------------------------------------|
| `0x00000` (0)     | 4         | currentBoxIndex (u32 LE, 0..17 — informational)             | `BoxParser::BOX_DATA_OFFSET_IN_STORAGE`    |
| `0x00004`         | 73,440    | 18 boxes × 30 slots × 136-byte box-PKM records (`0x11EE0`)  | `BoxParser::BOX_RECORD_SIZE`               |
| `0x11EE4`         | 748       | Box names / wallpapers / etc. (we ignore)                   | —                                          |
| `0x121D0` (74,192)| 20        | Storage-block footer (same shape as general)                | `BoxParser::STORAGE_FOOTER_OFFSET`         |
| `0x121E2`         | 2         | CRC-16 over `0x00..0x121D0` (footer-excluded)               | `BoxParser::STORAGE_CRC_OFFSET`            |

Citations: PKHeX `SAV4Pt.cs` `GeneralSize = 0xCF2C` + `StorageSize =
0x121E4`. PKHeX `SAV4.cs:113` `Checksums.CRC16_CCITT(data[..^FooterSize])`
+ `SAV4Sinnoh.cs:12` `FooterSize => 0x14` for the CRC body — see
Section 3 for the bug this caused (Step 18 Must Fix). Closes KG-21.

### 2c. Hall of Fame block (extra block, absolute offsets)

The HoF block sits *outside* both partitions, double-buffered at two
fixed absolute file offsets:

| File offset       | Size       | Contents                          |
|-------------------|------------|-----------------------------------|
| `0x20000` (131,072)  | `0x2AC0` | Primary HoF block                 |
| `0x60000` (393,216)  | `0x2AC0` | Mirror HoF block                  |

Inside one HoF block (`0x2AC0` total = `0x2AB0` data + `0x10` footer):

| Offset (block)  | Size       | Field                               |
|-----------------|------------|-------------------------------------|
| `0x0000`        | `0x2AA8`   | 30 × `0x16C` HoF records            |
| `0x2AA8`        | 4          | `IndexNextOverwrite` (u32 LE)       |
| `0x2AAC`        | 4          | `ClearCount` (u32 LE) — **the field the app reads** |
| `0x2AB0`        | 16         | Footer (4 magic / 4 revision / 4 size / 2 blockID / 2 CRC) |
| `0x2ABE`        | 2          | CRC-16 over `0x00..0x2ABE`          |

Constants: `SaveParser::HOF_PRIMARY_OFFSET = 0x20000`,
`HOF_PARTITION_SIZE = 0x40000` (mirror at `+0x40000` → `0x60000`),
`HOF_BLOCK_TOTAL_SIZE = 0x2AC0`, `HOF_CLEAR_COUNT_OFFSET = 0x2AAC`,
`HOF_CRC_OFFSET = 0x2ABE`.

Citations: PKHeX `SAV4Pt.cs` `ExtraBlocks => [ new(0, 0x20000, 0x2AC0),
… ]`; PKHeX `Substructures/Gen4/Dendou4.cs` for the per-record /
ClearCount layout; pret/pokeplatinum `include/savedata/save_table.h`
defining `EXTRA_SAVE_TABLE_ENTRY_HALL_OF_FAME = 0`.

---

## 3. CRC validation

Every block in the save (general, storage, HoF) is protected by a
**CRC-16-CCITT-FALSE** checksum stored in the block's footer. The
parser refuses to trust any block whose stored CRC doesn't match the
recomputed value.

### 3a. The algorithm

CRC-16-CCITT-FALSE parameters (constants in `SaveParser`):

- Polynomial: `0x1021` (`SaveParser::CRC_POLY`)
- Initial value: `0xFFFF` (`SaveParser::CRC_INIT`)
- No XOR-out
- Bitwise MSB-first, byte-by-byte

The implementation lives in `SaveParser#crc16_ccitt(data)` (lines
306–316). It's a textbook bit-walk:

```ruby
crc = CRC_INIT
data.each_byte do |byte|
  crc ^= (byte << 8)
  8.times do
    crc = (crc & 0x8000).zero? ? (crc << 1) : ((crc << 1) ^ CRC_POLY)
    crc &= 0xFFFF
  end
end
crc
```

`PartyParser` and `BoxParser` re-state the same constants and
re-implement the same routine to stay loosely coupled to `SaveParser`.

Citation: PKHeX `Util/Checksums.cs` `CRC16_CCITT` (poly 0x1021,
seed 0xFFFF, MSB-first); `SAV4.cs` and `Dendou4.cs` both call
`Checksums.CRC16_CCITT(...)` for their respective blocks.

### 3b. The CRC range — the `^FooterSize` lesson

The CRC covers **everything in the block from offset 0 up to (but not
including) the start of the footer** — *not* up to the CRC field
itself. This is `block_size - footer_size`, not `block_size - 2`.

Empirically discovered for the general block on 2026-04-29 against a
real Platinum save:

- Variant `0..0xCF18` (footer-excluded): CRC = `0x6C3C` ✅ matches the
  stored value
- Variant `0..0xCF2A` (only the 2-byte CRC field excluded): CRC =
  `0x533D` ❌ off

So `SaveParser::CRC_RANGE_END = BLOCK_FOOTER_OFFSET = 0xCF18`. The
storage block makes the same choice (`STORAGE_CRC_RANGE_END =
STORAGE_FOOTER_OFFSET = 0x121D0`); we got that one right by citing
PKHeX `SAV4.cs:113` `data[..^FooterSize]` with `FooterSize = 0x14`
directly. The HoF block uses `[..^2]` semantics (Dendou4 uses
`Checksums.CRC16_CCITT(GetRegion()[..^2])`), so its CRC body excludes
just the trailing 2 bytes — a different rule than the partition
blocks.

This was the **Must Fix #1 from Richard's review of Step 18**: an
earlier `BoxParser` draft computed CRC over `data[..^2]` instead of
`data[..^FooterSize]`. That would have failed every real Platinum save
silently (no boxes ever surface). The fix landed before merge.

### 3c. What happens on CRC failure

Each parser handles CRC failure independently and **never raises** —
the entire pipeline is contractually pure:

- `SaveParser.parse` returns `nil` if neither partition's general block
  validates. The job logs and stamps only `parsed_at`; the slot card
  renders the prior parsed values.
- `PartyParser.parse` and `BoxParser.parse` return `[]` if no partition
  validates. The job persists an empty array; `SaveDiff` correctly
  emits no catch / box events.
- `SaveParser.safe_hof_count` returns `nil` (NOT `0`) on dual CRC
  failure — important because the run-completion AND-gate would
  otherwise treat `0` as "no HoF" but a valid block with `ClearCount =
  0` (player saved before HoF) is also `0`. The `nil`-vs-`0` distinction
  encodes "we don't know" vs "we know it's zero". On nil-coerced-to-0
  the `>= 1` check still correctly fails.

The parse-failure path is governed by the **KG-13 invariant** (Step
15): on parser failure, `ParseSaveDataJob` updates **only** `parsed_at`
and leaves every other `parsed_*` column at its prior value. Without
this rule, a CRC-bad save would zero out `parsed_badges`, the diff
layer would see "8 → 0" and emit eight spurious `BadgeLost` events.

---

## 4. Active-partition selection

The save file always carries two copies of each block. Picking the
right one is more subtle than "pick the higher counter."

### 4a. The selection rule

For each block (general, storage), the parser:

1. Computes the CRC of each partition's copy.
2. Reads the save-counter from each copy's footer.
3. Returns the **higher-counter copy whose CRC also validates**.

If the higher-counter copy is corrupt (mid-write power loss), it falls
back to the lower-counter copy. If both fail, parse fails for that
block.

Code: `SaveParser.active_slot` (lines 263–279), `PartyParser.pick_active_slot`
(lines 114–131), `BoxParser.pick_active_storage_block` (lines 125–144).

A "newest counter wins" rule alone isn't enough: a half-written save
*does* have the higher counter (it gets bumped before the data write
completes), but its CRC is invalid because the data was corrupted
mid-write. The CRC check is the safety net.

### 4b. Independent selection per block

The general and storage blocks are picked **independently**. The
active general block can live in partition A while the active storage
block lives in partition B (or vice versa). Step 18 learned this from
PKHeX, which exposes a `StorageBlockPosition` separately from the
general-block selection.

This is why `BoxParser` doesn't reuse `PartyParser`'s slot picker —
they walk different per-partition offsets and apply CRC validation to
different ranges. Sharing the picker would couple them together
incorrectly.

### 4c. The Hall of Fame block

HoF uses a different rule. It's not part of either partition; it's its
own double-buffered extra block at fixed file offsets. The app reads
both copies' `ClearCount`, validates their CRCs independently, and
returns **the higher of the two CRC-valid values** (or nil if both
fail). See `SaveParser.safe_hof_count` (lines 397–404) and
`extract_hof_count` (lines 411–430).

For our run-completion question (`hof_count >= 1`), picking the higher
valid value is simpler than tracking which copy is "active" — both are
written together when the player enters HoF, so any valid copy gives
the right answer.

---

## 5. PKM record decryption

A single Pokémon record is **136 bytes** (box format) or **236 bytes**
(party format — box record + 100 extra bytes for level and runtime
stats). Inside, the data is **PID-shuffled and LCG-encrypted**. This
section walks the entire decryption sequence.

Implementation: `SoulLink::PkmDecoder` in
`app/services/soul_link/pkm_decoder.rb`. Every step is cited inline
against pret/pokeplatinum and PKHeX.

### 5a. Record-level layout (encrypted form, before any decoding)

| Offset      | Size  | Field                                                 |
|-------------|-------|-------------------------------------------------------|
| `0x00–0x03` | 4     | **PID** (u32 LE) — never encrypted                    |
| `0x04–0x05` | 2     | flags (`partyDecrypted`, `boxDecrypted`, `checksumFailed`) |
| `0x06–0x07` | 2     | **Checksum** (u16 LE) — also the LCG seed for blocks A–D |
| `0x08–0x87` | 128   | **Data blocks A/B/C/D** — PID-shuffled, LCG-encrypted (4 × 32-byte blocks) |
| `0x88–0xEB` | 100   | **Party stats** — separate LCG keyed with PID (party records only) |

### 5b. Step 1 — LCG-decrypt the data-blocks region

The 128-byte blocks region is XORed with a **Linear Congruential
Generator (LCG) keystream seeded with the checksum**. The same
algorithm is used to decrypt and re-encrypt — XOR is its own inverse.

LCG parameters (constants from pret/pokeplatinum `include/math_util.h`
and `src/math_util.c:217-234` `EncodeData` / `LCRNG_NextFrom`):

- Multiplier: `0x41C64E6D` (1,103,515,245)
- Increment: `0x6073` (24,691)
- Step: `seed = seed * mult + inc; return seed >> 16` (top 16 bits of
  the new state)
- Operates on u16 half-words: `data[i] ^= LCRNG_NextFrom(&seed)`

In Ruby (`PkmDecoder.lcg_xor`, lines 300–312):

```ruby
seed &= 0xFFFFFFFF
word_count.times do |i|
  seed = ((seed * 0x41C64E6D) + 0x6073) & 0xFFFFFFFF
  ks   = (seed >> 16) & 0xFFFF
  word = bytes.byteslice(i * 2, 2).unpack1("v")
  out_words << (word ^ ks)
end
```

### 5c. Step 2 — Verify the checksum

The post-decrypt 128-byte region must sum (as little-endian u16 words,
mod `0x10000`) to the stored checksum. This is the same algorithm as
pret/pokeplatinum `Pokemon_GetDataChecksum` (`src/pokemon.c:4827-4839`).
A mismatch means either the wrong checksum (corrupt record) or the
wrong key (corrupt PID); either way we return `nil` for that slot and
move on.

This check happens **before** the un-shuffle step because the sum is
order-independent.

### 5d. Step 3 — Un-shuffle blocks A/B/C/D

The 128-byte buffer is logically four 32-byte blocks. Their encrypted
order is determined by the PID:

```
shuffle_index = (pid >> 13) & 0x1F   # ∈ [0..31]
```

A 32-entry table maps each shuffle index to a 4-tuple `[a, b, c, d]`
giving the **source position** of each canonical block in the
encrypted buffer. To get canonical ABCD ordering, copy block `a` to
position 0, block `b` to position 1, and so on. The full table is
`PkmDecoder::SHUFFLE_TABLE` (lines 167–200), transcribed from
pret/pokeplatinum `src/pokemon.c:4861-4924`
`BoxPokemon_GetDataBlock` (and verified against PKHeX
`PokeCrypto.BlockPosition`).

There are only 24 unique orderings but the index runs 0–31, so cases
24–31 are duplicates of cases 0–7 (`% 24`). The table mirrors them so
the lookup is one indexed read, no modulo.

### 5e. Step 4 — LCG-decrypt the party-stats region (party records only)

For 236-byte party records, bytes `0x88–0xEB` (100 bytes) hold the
party-only stats. They're encrypted with **a separate LCG keyed by the
PID itself** (not the checksum). Same `lcg_xor` function, different
seed.

Reference: pret/pokeplatinum `src/pokemon.c:317-349`
`Pokemon_EnterDecryptionContext`, which calls
`Pokemon_DecryptData(&mon->party, sizeof(PartyPokemon),
mon->box.personality)` — `personality` is the PID.

Box-only records (136 bytes) skip this step; their decoded `Pkm.level`
field is `nil` because the level field lives in the party-stats block.

---

## 6. What's in each PKM block post-decryption

Once un-shuffled, the 128-byte blocks region splits cleanly into four
32-byte blocks at offsets `0x00`, `0x20`, `0x40`, `0x60` (within the
unshuffled buffer). The app reads a focused subset of fields. Each is
cited against PKHeX `PK4.cs` (which uses **PK4-absolute** offsets — i.e.
relative to the full 136-byte record including the 8-byte PID/flags/
checksum header) and pret/pokeplatinum `include/struct_defs/pokemon.h`
(which uses **block-relative** offsets within `PokemonDataBlock`).

The two coordinate systems differ by 8 bytes: PK4 absolute = block
buffer + 8.

### 6a. Block A (unshuffled `0x00–0x1F`, PK4 absolute `0x08–0x27`)

| Block-buffer offset | PK4 absolute | Field                       | App constant                                |
|---------------------|--------------|-----------------------------|---------------------------------------------|
| `0x00`              | `0x08`       | Species (u16 LE)            | `UNSHUFFLED_SPECIES_OFFSET`                 |
| `0x04`              | `0x0C`       | OT Trainer ID (u16 LE)      | `UNSHUFFLED_OT_ID_OFFSET`                   |
| `0x06`              | `0x0E`       | OT Secret ID (u16 LE)       | `UNSHUFFLED_OT_SID_OFFSET`                  |
| `0x10–0x15`         | `0x18–0x1D`  | EVs (u8 × 6: HP/Atk/Def/Spe/SpA/SpD) | `UNSHUFFLED_EV_OFFSET`             |

Other Block A fields (held item, contest stats, friendship) are
documented in PKHeX `PK4.cs` but unused by the app today.

### 6b. Block B (unshuffled `0x20–0x3F`, PK4 absolute `0x28–0x47`)

| Block-buffer offset | PK4 absolute | Field                                         | App constant            |
|---------------------|--------------|-----------------------------------------------|-------------------------|
| `0x20`              | `0x28`       | Move 1 ID (u16 LE)                            | `UNSHUFFLED_MOVES_OFFSET` |
| `0x22`              | `0x2A`       | Move 2 ID                                     |                         |
| `0x24`              | `0x2C`       | Move 3 ID                                     |                         |
| `0x26`              | `0x2E`       | Move 4 ID                                     |                         |
| `0x28–0x2B`         | `0x30–0x33`  | Current PP (u8 × 4)                           | `UNSHUFFLED_PP_OFFSET`  |
| `0x2C–0x2F`         | `0x34–0x37`  | PP-up (u8 × 4)                                | `UNSHUFFLED_PP_UP_OFFSET` |
| `0x30`              | `0x38`       | IV / Egg / Nicknamed dword (u32 LE)           | `UNSHUFFLED_IV_DWORD_OFFSET` |
| `0x3E`              | `0x46`       | Met-Location (Pt/HGSS) (u16 LE)               | `UNSHUFFLED_MET_LOC_OFFSET` |

The IV dword packs six 5-bit IV values + the egg + nickname bits:

```
bits  0– 4 : HP IV    (mask 0x1F)
bits  5– 9 : Atk IV
bits 10–14 : Def IV
bits 15–19 : Spe IV
bits 20–24 : SpA IV
bits 25–29 : SpD IV
bit  30    : isEgg
bit  31    : hasNickname
```

Per pret/pokeplatinum `include/struct_defs/pokemon.h`. The egg bit is
`PkmDecoder::IV_EGG_BIT = 30`; the app collapses the egg sentinel and
`species == 0` to a single "is_egg / no Pokémon" flag (Section 9).

### 6c. Block C (unshuffled `0x40–0x5F`, PK4 absolute `0x48–0x67`)

Nickname (u16 chars, Gen-IV charset), met origin (game version, met
date), language byte, ribbons. The app does not currently read any
Block C fields — nicknames and origin metadata aren't displayed on
catch rows. Documented for completeness; PKHeX `PK4.cs` is the
authoritative reference if a future feature needs them.

### 6d. Block D (unshuffled `0x60–0x7F`, PK4 absolute `0x68–0x87`)

| Block-buffer offset | PK4 absolute | Field                              | App constant                  |
|---------------------|--------------|------------------------------------|-------------------------------|
| `0x7C`              | `0x84`       | Met level (u8, mask `0x7F`)        | `UNSHUFFLED_MET_LEVEL_OFFSET` |

Other Block D fields (pokerus, encounter type, level-met u8, ball-caught
ID) live in PKHeX `PK4.cs` and pret's `PokemonDataBlock` definition
but aren't used today.

### 6e. Party stats region (record offset `0x88–0xEB`, 100 bytes; party records only)

| Offset (party-stats) | Size  | Field         | App constant                       |
|----------------------|-------|---------------|------------------------------------|
| `0x00–0x03`          | 4     | Status flags (u32) | doc only                      |
| `0x04`               | 1     | **Level**     | `PARTY_STATS_LEVEL_OFFSET = 0x04` |
| `0x05–0x63`          | 95    | HP / max HP / current stats / mail data | unused by app  |

The level is the only party-stats field the app uses today (the rest
are runtime-derived and reproducible from species + level + IVs/EVs +
nature).

### 6f. Derived fields

**Nature** is computed directly from the PID, no decryption needed:

```
nature_id = pid % 25     # ∈ [0..24]
```

The 25-entry name table (Hardy=0, Lonely=1, …, Quirky=24) lives in
`SoulLink::Natures` (`app/services/soul_link/natures.rb`), citing
PKHeX `Nature.cs`. The app stores the nature *string* on
`SoulLinkPokemon.nature` for display.

---

## 7. The lookup tables

Numeric IDs out of the SRAM are useless to a human. The app maintains
four reference tables to translate them.

| Table                     | File                                | Source                                                                                                  | Entries  | KG closed | Fallback                |
|---------------------------|-------------------------------------|---------------------------------------------------------------------------------------------------------|----------|-----------|-------------------------|
| Map IDs                   | `config/soul_link/maps.yml`         | pret/pokeplatinum `include/constants/map.h`                                                             | ~80      | KG-6      | `"Map #N"`              |
| Met-locations             | `config/soul_link/met_locations.yml`| PKHeX `Resources/text/locations/gen4/text_hgss_00000_en.txt` + PKHeX `Locations.cs` (special pseudo-IDs)| 127      | KG-12     | `"Met-Location #N"`     |
| Move names                | `config/soul_link/move_names.yml`   | PKHeX `Resources/text/other/en/text_Moves_en.txt` (lines 2–468) + pret `include/constants/moves.h`      | 467      | KG-24     | `"Move #N"`             |
| Species names (numeric)   | `pokemon_base_stats` AR table       | Seed task; `national_dex_number` column                                                                 | 493      | KG-20 open| `"Species #N"`          |

All four are accessed through `SoulLink::GameState`:

- `GameState.map_name(id)` — for the trainer-block map ID. View helper:
  `EmulatorHelper#format_map_name`.
- `GameState.met_location_name(id)` — for per-PKM met-location IDs.
  `GameState.event_met_location?(id)` flags daycare / link-trade /
  mystery-gift / ranger / faraway sentinels (IDs 0, 2000, 2001, 2002,
  3001, 3002).
- `GameState.move_name(id)` — for move IDs (1..467; ID 0 is the "no
  move" sentinel and is omitted from the YAML).
- `CatchCoordinator.resolve_species_string(species_id)` — reads the
  inverse `national_dex_number → species` map from `PokemonBaseStat`.
  Memoized per-process in `species_name_by_id`.

Two enum spaces, two distinct YAMLs: **map IDs and met-location IDs are
not the same enum**. The general-block map field at offset `0x1234`
indexes into `maps.yml`; the per-PKM Block-B met-location field at
unshuffled offset `0x3E` indexes into `met_locations.yml`. They overlap
in *names* (both have "Twinleaf Town") but not in *numeric values*. The
met-locations table is the more authoritative one — it's the value
stored on the Pokémon record itself.

Missing-ID fallbacks degrade gracefully via
`EmulatorHelper#format_map_name(id)` /
`format_move_name(id)` and `CatchCoordinator.resolve_route_name(id)`
/ `resolve_species_string(species_id)`. None of them ever return nil;
they always render a string, always carry the numeric ID forward so a
contributor can extend the YAML.

---

## 8. The pipeline from raw bytes to events

A new save lands → events reach Discord. Here's the full path.

### 8a. The trigger: a save-slot write

The user uploads a `.sav` (or the emulator pushes one) via the **Save
Slots** flow, which writes binary data into
`SoulLinkEmulatorSaveSlot.save_data` (gzip-encoded by the model's
`GzipCoder`). An `after_update_commit` callback enqueues
`SoulLink::ParseSaveDataJob` for the slot.

### 8b. ParseSaveDataJob — pure parser + persist

`app/jobs/soul_link/parse_save_data_job.rb`. The job:

1. **Captures pre-update state** via `capture_state(slot)` — reads the
   prior `parsed_*` columns into a Hash. This is the "prev" snapshot
   the diff layer uses.
2. **Parses three independent streams** off the raw bytes:
   - `SoulLink::SaveParser.parse(save_data)` → trainer fields
     (`Result` struct: name, money, play seconds, badges count, map ID,
     TID, SID, Pokédex caught/seen, HoF count).
   - `SoulLink::PartyParser.parse(save_data)` → `Array<Pkm>` for party
     slots (eggs filtered, slot 0..5 in order).
   - `SoulLink::BoxParser.parse(save_data)` → `Array<Pkm>` for PC-box
     slots (eggs filtered, walked in box × slot order; size 0..540).
3. **Persists** all parsed values via `update_columns(...)` (NOT
   `update!`) to bypass the `after_update_commit` callback that
   enqueued this job — otherwise an infinite loop.
4. **Captures post-update state** and hands `(prev, curr)` to
   `SoulLink::SaveDiffDispatcher.dispatch(slot, prev:, curr:)`.

On parser failure (`SaveParser.parse` returns nil), step 3 stamps
**only** `parsed_at` and skips dispatch. KG-13 invariant: never zero
out the prior parsed values, never emit spurious lost-state events.

The three parsers are **independent**: a corrupt party block doesn't
preclude a valid box parse, a CRC-failed general block doesn't
preclude reading the HoF block. Each parser returns a defensive empty
result on failure rather than raising.

### 8c. SaveDiff — pure event emission

`app/services/soul_link/save_diff.rb`.
`SaveDiff.between(prev_*, curr_*)` is a pure module function (no AR,
no `Time.current`, no `Rails.logger`) that emits a `Result` struct
with seven event arrays:

| Event                            | When                                                    |
|----------------------------------|---------------------------------------------------------|
| `BadgeGained(gym_number)`        | `curr_badges > prev_badges` (one event per badge)       |
| `BadgeLost(gym_number)`          | `curr_badges < prev_badges` (informational; coordinator no-ops) |
| `TidObserved(trainer_id, secret_id)` | `(prev_tid, prev_sid) ≠ (curr_tid, curr_sid)` and curr is non-zero |
| `PokedexProgress(...)`           | Either caught or seen popcount changed                  |
| `HallOfFameEntered(hof_count)`   | `curr_hof_count >= 1` and prev was nil/0                |
| `PokemonCaughtEvent(...)`        | A PID present in `curr_party` but not in `prev_party`   |
| `PokemonRemovedEvent(pid)`       | A PID present in `prev_party` but not in `curr_party`   |
| `BoxedPokemonObservedEvent(...)` | A PID present in `curr_box` but not in `prev_box`       |

The diff key for party / box events is **PID** — a uint32 unique to
each Pokémon (the same value used as the encryption seed). This is
what makes deposit-and-re-catch round-trips a no-op: a Pokémon
deposited to PC and later withdrawn keeps its PID, so the second
appearance sees the prev side already has that PID indexed.

### 8d. SaveDiffDispatcher — fan-out to coordinators

`app/services/soul_link/save_diff_dispatcher.rb`. Two responsibilities:

1. **Baseline rule** — short-circuit on first-ever parse
   (`prev[:parsed_at].nil?`). Importing a save with 8 badges does NOT
   fire 8 gym-beaten events; the diff is between *parses*, not from
   zero.
2. **Fan-out** — call each coordinator with its slice of events:

   - `GymBeatenCoordinator.process(slot, diff.badge_events)` —
     all-4 AND-gate; auto-marks gym beaten when every session has
     `parsed_badges >= gym_number`. Fires per-player progress and
     team-beaten Discord notifications.
   - `TidObservationCoordinator.process(slot, diff.tid_events)` —
     log-only; the user-visible value comes from the parser persisting
     `parsed_trainer_id` / `parsed_secret_id` and the dashboard
     surfacing a "⚠ TID CONFLICT" pill via
     `SoulLinkRun#tid_conflict_groups`.
   - `PokedexProgressCoordinator.process(slot, diff.pokedex_events)`
     — log-only; counts come from `parsed_pokedex_caught` /
     `parsed_pokedex_seen`.
   - `HallOfFameCoordinator.process(slot, diff.hof_events)` —
     all-4 AND-gate on `parsed_hof_count >= 1`; stamps
     `run.completed_at` and fires a `notify_run_complete` Discord ping
     once.
   - `CatchCoordinator.process(slot, [catches] + [removals] + [box])` —
     **single call** with the three event arrays concatenated, in that
     order. Order matters: party catches first, then removals, then
     box-observed. PID dedup against
     `(soul_link_run_id, discord_user_id, pid)` ensures a same-snapshot
     party+box double-fire creates **one** row, with the party-side
     `caught_off_feed: false` winning over the box-side
     `caught_off_feed: true` (the box event short-circuits on the
     `.exists?` check because the party-created row is already
     persisted).

### 8e. CatchCoordinator — the side-effecting heavy lifter

The catch coordinator does the most work. Per event, in a
`slot.transaction { }`:

- Filter eggs (`event.is_egg → return`) and zero PIDs.
- Resolve the species string (`pokemon_base_stats.national_dex_number
  → species`, fallback `"Species #N"`).
- Resolve the route (`GameState.met_location_name`, fallback
  `"Met-Location #N"`).
- Detect trade-in (event's OT-ID/SID differs from the slot's parsed
  TID/SID → `trade_in: true`, `acquired_via: 'trade_in'`).
- Detect event-gift (`GameState.event_met_location?(met_id) →
  acquired_via: 'event_gift'`).
- `SoulLinkPokemon.create!` with the resolved values, plus per-Pokémon
  stats (nature/IVs/EVs/moves) for Step-18-aware records.
- Fire `DiscordNotifier.notify_catch(run, uid, species, route, level,
  off_feed:)`. Box-observed catches set `off_feed: true` and append
  `[off-feed]` to the message.

`PokemonRemovedEvent` is a deliberate no-op (logged at info level).
A Pokémon disappearing from the party could be a release, a deposit,
a daycare drop-off, or a death — none of them are unambiguously a
death event. KG-29 documents the "auto-detect dead Pokémon" question
as out of scope; the manual Mark Dead button is the only path.

### 8f. WipeCoordinator — wired downstream of Mark Dead

`app/services/soul_link/wipe_coordinator.rb`. Not on the parse path —
it runs when `PokemonGroupsController#update` calls `mark_as_dead!`.
Wipe rule: a player has at least one catch in the run AND zero alive
Pokémon → the run is wiped (`run.update!(wiped_at: Time.current)`,
fires `DiscordNotifier.notify_wipe`). Idempotent via
`run.wiped_at.present?` outer guard + double-check inside `with_lock`.

This coordinator catches dead-state changes the SRAM pipeline
deliberately does *not* infer.

---

## 9. Edge cases the pipeline handles

A list of behaviours that are easy to miss reading the code linearly.

- **Egg sentinel filtering.** `PartyParser.parse` and `BoxParser.parse`
  drop entries with the egg bit set OR `species == 0`. Eggs round-trip
  invisibly through the auto-tracker until they hatch — the next parse
  sees the post-hatch PID as a "new" PID and fires
  `PokemonCaughtEvent` cleanly.

- **Trade-in detection via OT-ID mismatch.** If a Pokémon's stored
  `(ot_id, ot_sid)` doesn't match the slot's parsed
  `(parsed_trainer_id, parsed_secret_id)`, the catch row is created
  with `trade_in: true` AND `acquired_via: 'trade_in'`. Trades surface
  as catches; they aren't silently dropped (per Step 17 brief decision
  8). Both-zero slot TID/SID short-circuits to `false` (we can't know
  yet if the slot hasn't parsed TID).

- **PID-based catch de-duplication.** The same PID appearing through
  the party path *and* the box path in the same snapshot creates only
  one `SoulLinkPokemon` row. The dispatcher orders party events first,
  the row is created via the party path with `caught_off_feed: false`,
  and the subsequent box event short-circuits on the
  `.exists?(soul_link_run_id:, discord_user_id:, pid:)` check.

- **Save going down (older save loaded).** A negative `caught_delta`
  in `PokedexProgress`, or a `BadgeLost` event, is treated as
  informational only — coordinators log but do not auto-revert state.
  Loading an older save state is normal Soul Link reset behaviour.
  Manual UNMARK BEATEN is the only un-mark path.

- **Parse-failure path preserves prior state (KG-13).** A CRC-bad save
  doesn't zero `parsed_badges` (or any other parsed_* column). The job
  stamps only `parsed_at`. The slot card renders the most recent
  successful parse. Without this rule, sandwiching a corrupt save
  between two good ones would emit eight false `BadgeLost` events.

- **Independent active-block selection for storage vs general.** The
  active general block can live in partition A while the active
  storage block lives in partition B. `BoxParser` runs its own
  partition picker against the storage range (`pick_active_storage_block`).

- **Storage-block CRC range (Step 18 Must Fix from Richard).** The
  storage block CRC covers `data[..^FooterSize]` (= block_size − 20),
  not `data[..^2]` (= block_size − 2). The earlier draft would have
  silently failed every real Platinum save's box parse. Fixed before
  merge; see `box_parser.rb:73-79`.

- **HoF clear-count semantics.** `nil` (both copies CRC-failed) is
  distinct from `0` (valid block, player has not yet entered HoF).
  The run-completion AND-gate uses `to_i >= 1`, which correctly
  treats nil-coerced-to-0 as "no". A corrupted HoF block can't
  false-positive a "Run complete".

- **Pokémon Platinum `0xFFFF` name terminator.** The Gen-IV trainer
  name decoder stops at index `0xFFFF`, skips `0x0000` padding, and
  emits `U+FFFD` REPLACEMENT CHARACTER for unknown indices rather
  than crashing. Unknown glyphs render as a visible question-block
  rather than a stack trace.

- **Map-ID zero treated as nil.** `SaveParser::MAP_ID_OFFSET` is
  unverified (KG-7). The parser returns `nil` on a zero read so the
  sidebar gracefully omits the field; a non-zero read renders via
  `EmulatorHelper#format_map_name(id)` with `"Map #N"` fallback for
  unknown IDs.

---

## 10. Open Known Gaps touching the SRAM pipeline

Tracked in `handoff/BUILD-LOG.md` § Known Gaps. The list below is the
subset that touches encoding / decoding / persistence — for the full
ledger including UI-only gaps see the BUILD-LOG itself.

- **KG-7: real-save MAP_ID validation.** `SaveParser::MAP_ID_OFFSET =
  0x1234` is a placeholder. It hasn't been validated against a known
  in-game position on a real `.sav`. The companion gap is the
  `maps.yml` integer IDs being best-effort from
  pret/pokeplatinum `include/constants/map.h` rather than empirically
  verified. Both validations should happen together when a real save
  is available.

- **KG-15: HM bag.** No SRAM read of the bag/HM contents. Out of scope
  through Step 19; relevant if a future feature wants to surface
  "which HMs has the team obtained."

- **KG-18: TID conflict resolution UI.** The dashboard shows a
  "⚠ TID CONFLICT" pill on cards where two players' slots share the
  same `(parsed_trainer_id, parsed_secret_id)`, but offers no UI to
  resolve it. Players currently re-upload the correct save manually.

- **KG-20: species lookup fallback.** `CatchCoordinator.resolve_species_string`
  reads `pokemon_base_stats.national_dex_number → species`. If the
  table is empty (fresh dev DB without the seed task), every catch
  gets `"Species #N"`. Functional, but worth wiring the seed into
  CI.

- **KG-25: real-SRAM smoke for `BoxParser` + extended `PkmDecoder`.**
  Step-18 tests use synthetic SRAM/PKM builders that recompute CRCs
  and LCG-encrypt payloads with the same constants the production
  code uses. A regression of the `^FooterSize` CRC-range fix (Must
  Fix #1 from Richard) would only be caught against a real Platinum
  dump. Recommended: capture a real `.sav` from the Project Owner's
  emulator, drop into `test/fixtures/files/`, wire one integration
  test through `BoxParser.parse` + `PkmDecoder.decrypt` for IVs / EVs
  / moves field reads. See `handoff/2026-05-02-sram-auto-tracking-audit.md`
  if it's still on disk for the parity argument context.

- **KG-26: real-SRAM smoke for `move_names.yml` lookup.** Same shape
  as KG-25. Bundle the verification into the same real-SRAM audit
  when one happens.

- **KG-29: no auto-detect of dead Pokémon from save diff.** A Pokémon
  disappearing from BOTH party and box could be a release, trade-out,
  or death. Without confirmation UX, an auto-mark-dead would generate
  false positives. WipeCoordinator runs on manual Mark Dead only;
  auto-detection would need a heuristic (e.g. multiple disappearances
  + level-cap reached recently) plus a confirmation prompt.

- **KG-23: no UI to dismiss a false-positive auto-catch.** Auto-detected
  rows can be edited via the existing dashboard pokemon modal but
  there's no dedicated "this is wrong, undo" flow. Re-detection would
  need a "RE-DETECT" button.

For older SRAM-adjacent gaps that closed during Steps 9-19, see the
BUILD-LOG entry. The relevant closures: KG-6 (maps.yml + helper),
KG-11 (party offset 0xA0), KG-12 (met_locations.yml), KG-13 (parse
failure path), KG-14 (Pokédex offsets), KG-21 (PC box parsing), KG-24
(move_names.yml).

---

## Appendix A — Source-of-truth file map

The doc you're reading is *prose*. The authoritative source of truth
is the code.

| Concern                                | File                                                         |
|----------------------------------------|--------------------------------------------------------------|
| General-block parse + CRC + name decode + Pokédex/HoF | `app/services/soul_link/save_parser.rb`        |
| Party-block walk + active-slot picker  | `app/services/soul_link/party_parser.rb`                     |
| PC-box walk + storage active-block picker | `app/services/soul_link/box_parser.rb`                    |
| PKM record decryption (LCG + shuffle)  | `app/services/soul_link/pkm_decoder.rb`                      |
| Nature ID → name                       | `app/services/soul_link/natures.rb`                          |
| Diff event emission (pure)             | `app/services/soul_link/save_diff.rb`                        |
| Dispatcher + baseline rule             | `app/services/soul_link/save_diff_dispatcher.rb`             |
| Coordinators                           | `app/services/soul_link/{gym_beaten,catch,hall_of_fame,tid_observation,pokedex_progress,wipe}_coordinator.rb` |
| Discord notifications                  | `app/services/soul_link/discord_notifier.rb`                 |
| Parse job                              | `app/jobs/soul_link/parse_save_data_job.rb`                  |
| Lookup-table accessors                 | `app/services/soul_link/game_state.rb`                       |
| Maps                                   | `config/soul_link/maps.yml`                                  |
| Met-locations                          | `config/soul_link/met_locations.yml`                         |
| Move names                             | `config/soul_link/move_names.yml`                            |
| Species (numeric)                      | `pokemon_base_stats` AR table (seeded)                       |

## Appendix B — Reference repositories

- PKHeX: <https://github.com/kwsch/PKHeX>
- pret/pokeplatinum: <https://github.com/pret/pokeplatinum>
- Project Pokémon Gen-IV docs: <https://projectpokemon.org/home/docs/>
