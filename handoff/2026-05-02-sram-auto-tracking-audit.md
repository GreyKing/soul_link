# SRAM Auto-Tracking Feasibility Audit
*Architect (Ava) — 2026-05-02 — read-only investigation, no implementation.*

The Project Owner asked: how much of what we currently track manually (gyms beaten, gym battle teams, catches + routes) can be derived automatically from the SRAM blob we now collect on every emulator save?

This audit answers that question per category, ranks them by ROI, and identifies the shared infrastructure that pays for two of the three.

---

## 0. Current parser baseline

What ships today (`app/services/soul_link/save_parser.rb`):

| Field | Offset (within slot) | Status | Notes |
|---|---|---|---|
| Trainer name | `0x0068` (16 bytes) | Verified | Gen-IV charset decode, real-save confirmed 2026-04-29 |
| Money | `0x007C` (uint32 LE) | Verified | |
| Play time | `0x0086` h / `0x0088` m / `0x0089` s | Verified | |
| **Badges** | `0x0060` (1-byte bitfield) | **Verified** | `count_set_bits` → `parsed_badges` integer 0-8 |
| Map ID | `0x1234` (uint16) | **UNVERIFIED — KG-7** | Returns nil today; never rendered in any view because the offset is suspect |
| Active slot picker | save_counter @ `0xCF18` + CRC16-CCITT @ `0xCF2A` | Verified | Tolerates a corrupt slot if the other one CRCs |

What is **explicitly out of scope** today (parser doc-comment, lines 5-7 + 14-20):
> "Pokemon party data and PC boxes are encrypted/scrambled and live in the box ('large') block; those are out of scope here (Phase 2+)."

That single sentence is the gating decision for everything below. Categories 2 and 3 require us to enter Phase 2: implement Gen-IV PKM block decryption.

Job lifecycle (do not refactor lightly): `SoulLinkEmulatorSaveSlot.after_update_commit` (`app/models/soul_link_emulator_save_slot.rb:19`) → `ParseSaveDataJob.perform_later` (`app/jobs/soul_link/parse_save_data_job.rb:21`) → `update_columns` of `parsed_*` (avoids re-firing the callback). Any new auto-tracking writes additional `parsed_*` columns the same way; **never** broadcast to the run-state writes from this job — those need their own service to keep the parse path side-effect-free.

Schema row that already exists for catches: `soul_link_pokemon` (`db/schema.rb:153`) — `species`, `level`, `location`, `nickname`, `status`, `caught_at`. Fields 1, 2, 4 are exactly what a PKM row gives us; `location` is the manual-entry field we'd be replacing.

Schema row for gyms: `gym_results` (`db/schema.rb:27`) — `gym_number`, `beaten_at`, **`team_snapshot` (JSON, already exists, currently nullable)**. The `team_snapshot` column is the natural landing place for category 2 output; nothing populates it consistently today.

---

## 1. Gyms beaten

**Verdict: ship this. Effort: SMALL. ROI: HIGH.**

We already parse `parsed_badges` reliably. The only missing piece is the diff: when a slot's `parsed_badges` increments past the run's `gyms_defeated`, fire `gym_results.create!(gym_number: N, beaten_at:, soul_link_run_id:)` and bump `soul_link_runs.gyms_defeated`. No new SRAM offset is needed.

### Detection strategy

After `ParseSaveDataJob` writes `parsed_*`, a new `DetectGymProgressService` (or an inline branch in the job) computes:

- `previous_max = soul_link_run.soul_link_emulator_sessions.flat_map(&:save_slots).map(&:parsed_badges).max` (memoized snapshot before this parse — easier: track `previous_changes["parsed_badges"]` on the slot)
- If new `parsed_badges` > `gyms_defeated`, create `gym_results` for each missing badge index in canonical Sinnoh order (Roark = bit 0 → gym 1; Volkner = bit 7 → gym 8). Bit-to-gym is a flat lookup.

The Sinnoh badge bitfield is canonical: bit 0 = Coal (Oreburgh / Roark), bit 1 = Forest (Eterna / Gardenia), bit 2 = Cobble (Veilstone / Maylene), bit 3 = Fen (Pastoria / Crasher Wake), bit 4 = Relic (Hearthome / Fantina), bit 5 = Mine (Canalave / Byron), bit 6 = Icicle (Snowpoint / Candice), bit 7 = Beacon (Sunyshore / Volkner). Source: pret/pokeplatinum `include/constants/badges.h`. **Trust this — the bitfield is the same across every Gen IV English save.**

### What needs to be added

- **Per-gym detection logic** (~40 lines of service code). Bit-by-bit compare: `(new_badges & ~old_badges)` gives the new bits, iterate, create one `gym_results` row per bit.
- **Per-run aggregation across the 4 players.** Soul Link is a 4-player co-op. Each player has their own session + save slots. The current `gyms_defeated` counter on `soul_link_runs` is run-level, not per-player. **Decision needed (escalate to PO):** do we mark a gym beaten when (a) the first player reports the badge, (b) all 4 players report it, or (c) per-player tracking with a new `gym_results.discord_user_id` column? Current manual MARK BEATEN button is a single-shot run-level action — option (a) is the closest to current UX, option (b) is the closest to "Soul Link" semantics. **Recommend (b) with an exposed override**: gym auto-confirms when the 4th player saves with the badge; UI still shows progress (3/4 players have it).
- **Idempotency.** If `gym_results.where(soul_link_run_id:, gym_number:)` exists, do nothing — the badge bit may have flipped weeks ago and we're seeing it on every save thereafter.

### Edge cases

| Case | Handling |
|---|---|
| Player marks BEATEN via UI before save reflects it | Idempotency check — `gym_results` exists, skip. The auto-detect just confirms what the user already entered. |
| Player imports a save mid-run with badges already set | First-parse baseline. On a slot's first parse, write `parsed_badges` but **don't** trigger gym-beaten events; only diffs against a previous parsed value count. Tracked via `parsed_at` being null pre-parse. |
| Player loads an older save (badges go DOWN) | Never un-create a `gym_results`. Only act on positive diffs. |
| Multi-slot: player saves to slot 3 with 4 badges, then to slot 1 with 2 badges (older save) | Trigger fires on the slot whose `parsed_badges` increased relative to its OWN previous value. Slot 1's drop from "previously 2" to "now 2" produces no diff. The interesting comparison is `slot.parsed_badges_was` vs. `slot.parsed_badges`, **not** an aggregate across slots. |
| Save-state vs. cartridge | Not relevant today. EmulatorJS is the only intake path (`app/controllers/save_slots_controller.rb:75`). Cartridge dumps would need a separate upload route; out of scope. |
| PKHeX edits | We trust the byte. If a player edits in 8 badges, the system will fire 8 gym-beaten events. Acceptable — Soul Link is not anti-cheat. |
| CRC-failed save | `SaveParser` returns nil → `parsed_badges` stays at its previous value via the nil-write path (`parse_save_data_job.rb:39` writes 0, which is its own bug worth fixing while we're in there: a parse failure shouldn't reset badge count to 0 and then auto-detect a "new" gym on the next valid save). **Pre-req fix**: the failure branch should NOT zero `parsed_badges`; leave the prior value alone. |

### Effort sizing in this codebase

**SMALL.** Roughly:
- 1 new service (`SoulLink::DetectGymProgressService`, ~80 lines)
- 1 hook in `ParseSaveDataJob` (call the service after `update_columns`)
- 1 schema addition optional (`gym_results.discord_user_id` if PO picks per-player)
- 1 migration to add `parsed_badges_baseline_seen_at` or equivalent first-parse marker (or use existing `parsed_at`)
- ~20 tests covering the bitfield-diff, idempotency, baseline-skip, and CRC-failure-don't-reset paths

No SRAM parser changes. No cryptography. Touches surfaces we already exercise.

---

## 2. Pokémon used to beat each gym

**Verdict: medium-confidence approximation only. Ship after category 1 and only if PO accepts the approximation. Effort: MEDIUM. ROI: MEDIUM.**

There is **no SRAM field that records "this Pokémon won the gym battle."** The closest signal is "the party at the moment the badge bit flipped." That's what we'd capture in `gym_results.team_snapshot`.

This category cannot ship without category 2's prerequisite: parsing the party block. That's the Gen-IV PKM decryption work, which is the bulk of the cost.

### What's known about the party block

From the projectpokemon Gen-IV PKM doc + pret/pokeplatinum:

- **Party Pokémon:** 6 entries × 236 bytes each. Box Pokémon are 136 bytes (no battle-stat block). For team_snapshot, we only need party.
- **PKM data structure** (post-decrypt):
  - `0x06-0x07`: 16-bit checksum (also the encryption key)
  - `0x08-0x09`: National Pokédex species ID
  - `0x10-0x13`: Experience (uint32)
  - `0x46-0x47`: **Met-location ID (Platinum-specific layout)**
  - `0x82`: Pokerus
  - `0x8C`: Level (party only — box PKM derives from EXP)
- **Encryption:**
  - The 128 bytes from `0x08-0x87` are split into 4 × 32-byte blocks A/B/C/D
  - PID-based shuffle: `((PV & 0x3E000) >> 0xD) % 24` selects one of 24 block orderings
  - LCG decryption: `X[n+1] = (0x41C64E6D * X[n] + 0x6073)`, seeded with the checksum, XOR'd against each 16-bit word
- **Party block offset within the save:** projectpokemon's Platinum doc cites `0xA0` within the small/general block, but their page is explicitly "under construction." pret/pokeplatinum's `SaveData` layout is the authoritative source — confirm against `include/savedata.h` before building. **This is a knowledge gap (KG-11) we'd need to close in the design phase, the same way KG-7 still gates `MAP_ID_OFFSET`.**

References to cite in the parser doc-comment when this lands:
- pret/pokeplatinum `include/savedata.h` + `src/savedata/` — block layouts, struct offsets
- projectpokemon Gen-IV PKM structure doc (https://projectpokemon.org/home/docs/gen-4/pkm-structure-r65/)
- PKHeX `SAV4Pt.cs` and `PK4.cs` — schema cross-check, READ-ONLY (license)
- Bulbapedia "Pokémon data structure (Generation IV)" — informal cross-check

### Detection strategy

When `DetectGymProgressService` (from category 1) fires a new `gym_results` row, it also reads the party from the same SRAM blob we just parsed:

```
party_species = SoulLink::PartyParser.parse(slot.save_data).map { |pkm| { species: pkm.species, level: pkm.level } }
gym_results.update!(team_snapshot: party_species)
```

The team_snapshot is the post-victory party state, not the literal battle team — but for any normal player, those are usually identical (you don't wholesale swap teams between winning a gym and saving). It's good enough to render "Beaten by: Empoleon (38), Staraptor (36), Luxray (34)..." on the gym results page.

### Refinements deliberately rejected

- **"Pokémon with EXP gained between pre-fight and post-fight saves."** Requires guaranteed pre-fight saves, which we can't enforce. Players save when they want.
- **Reading "last battled" or "exp-gained-this-battle" flags from PKM data.** These don't exist in Gen-IV PKM structure (verified against the projectpokemon doc — no such field).
- **Inferring battle team from HP deltas.** Same problem as EXP — requires a pre-fight save.

The team_snapshot approximation is the right answer. Don't over-engineer it.

### Edge cases

| Case | Handling |
|---|---|
| Player heals + swaps team between fight-end and save | Snapshot reflects post-swap team, not battle team. **Acceptable approximation** — render with caveat ("party at time of save"). |
| Player saves DURING gym (between sub-fights) | Badge bit only flips on FINAL victory. The first save with the flipped bit is post-victory; snapshot is post-fight party. Works. |
| 4-player AND-condition: which player's snapshot wins? | Depends on the category-1 decision. If gym auto-confirms when 4th player saves, snapshot is the 4th player's party — but that's only useful if we record per-player snapshots. **Recommend:** new column `gym_results.team_snapshots_by_player` (JSON keyed by `discord_user_id`), or denormalize to a new `gym_battle_teams` table. PO call. |
| PKM data decrypts to garbage (player edited via PKHeX badly) | Checksum mismatch at PKM level → skip that PKM, snapshot the rest. Don't fail the whole detection. |
| Party has eggs (species ID 491 in some references, also flagged via the IsEgg bit) | Filter out eggs from team_snapshot — they didn't fight. |

### Effort sizing

**MEDIUM.** Roughly:
- 1 new module (`SoulLink::PartyParser`, ~250 lines: PID shuffle table + LCG decrypt + PKM struct decoder)
- 1 new module (`SoulLink::PkmDecoder`, ~150 lines: parse one decrypted 236-byte PKM into a value object)
- Schema decisions per above (probably 1-2 small migrations)
- Hook into `DetectGymProgressService`
- ~50 tests covering: known-good party, all-eggs, PID-shuffle correctness across all 24 orderings, checksum-fail PKM skipped, LCG round-trip, real-save fixture (gated on KG-7-style real-save availability)

The cryptography is well-documented and deterministic — there's no novel research, just careful translation of the spec. PKHeX has been correctly implementing this for a decade.

---

## 3. Pokémon caught + on which routes

**Verdict: ship this — it's the highest-user-value automation. Effort: MEDIUM (shares all of category 2's infrastructure). ROI: HIGH.**

This is what the user actually does most often: catch a Pokémon, switch tabs to the Soul Link app, fill in route + species. Every one of those manual entries is something the SRAM already knows.

Met-location is canonically per-PKM at offset `0x46-0x47` (post-decrypt, Platinum layout). Once we have `PartyParser` from category 2, this is mostly the table mapping (location ID → route name) plus the diff logic.

### Detection strategy

After `ParseSaveDataJob`, run `DetectNewCatchesService`:

1. Read all PKM in `party + boxes`. Build a set of `{species, met_location_id, level_at_catch}` tuples.
2. Compare to the previous parse's set. Differences are new catches.
3. For each new entry, look up `met_location_id → route_name` via a new `config/soul_link/met_locations.yml` (parallel to `maps.yml`).
4. Fire `SoulLinkPokemon.create!(species:, location: route_name, ...)` — but **route the create through the existing catch flow** so Soul Link's pairing logic (linking the catch to the corresponding pair on the same route from another player) still runs.

Note that **met-location IDs are a different enum from map header IDs.** Maps.yml is for "where am I right now" (map header); met-location is "where was this Pokémon encountered" (encounter table location). Different table, different IDs. Source these from pret/pokeplatinum `include/constants/location.h` (which is split across both, sometimes).

### What needs to be added

- All of category 2's parser infrastructure (party + box decryption).
- New `config/soul_link/met_locations.yml` — Platinum met-location IDs → route names. Bigger than `maps.yml` (Sinnoh has ~100 met-location entries, including special "Distant Land" / event slots). Same shape: `{ id => { name: "...", route_number: N? } }`.
- PC box parser (boxes are 136-byte PKM × 30 per box × 18 boxes = 73,440 bytes). Same decryption, different array shape.
- `DetectNewCatchesService` — diff and dispatch.

### Edge cases

| Case | Handling |
|---|---|
| Trade-in / mystery gift Pokémon | Met-location is a special "in-game trade" or "event" ID. **Skip** these — not a Soul Link catch. Tag the special IDs in `met_locations.yml` with `event: true` and filter. |
| Egg hatch | Egg met-location is "where the egg was received" (offset `0x44-0x45` — egg met-location); after hatch, hatched-location goes to `0x46-0x47`. There's also an `IsEgg` flag in Block B. Soul Link doesn't currently have egg semantics — **skip eggs entirely** for v1. |
| Pokémon released → disappears from save | Don't auto-mark as dead. The species disappearing from the set could be a release, a trade out, or just bad detection. Death stays manual until we have a reliable signal. |
| Pokémon evolved | Same met-location, different species. Evolution should be detected via "this PKM's PID exists in both old and new sets but species differs" — that's the signal for `Pokemon#evolve!`, not a new catch. **Diff key must include PID, not just species**, to avoid double-counting. PIDs are at offset `0x00-0x03` (pre-decrypt — they don't get encrypted because they're the seed). |
| Multi-slot: player catches a Pokémon, then loads an older save | Set diff handles this — the species + PID combo doesn't appear, no new catch fires. The reverse (Pokémon present in older slot but not new slot) is just "this slot doesn't have it" — never fire deletes. |
| PKHeX-spawned Pokémon | Met-location reads as whatever PKHeX wrote. Trust it; not anti-cheat. |
| 4-player coordination: each player catches their pair on the same route | Each player's SRAM independently fires a new-catch event with the same `met_location_id`. The existing pairing logic in the catch flow handles 4-up linking — **don't** re-implement; just dispatch through the same service the manual flow uses. |

### Effort sizing

**MEDIUM, mostly shared with category 2.** Marginal cost:
- The `met_locations.yml` table (~100 entries — meaningful but tractable, similar to the `maps.yml` work in Step 12)
- `DetectNewCatchesService` (~150 lines)
- PC box parsing extension to `PartyParser` (~50 extra lines)
- ~30 tests for diff semantics, evolution-vs-new-catch distinction, event-PKM filtering, egg filtering

If you're already paying for category 2, category 3 is roughly the same again on top — but it's the category that visibly changes the daily-use experience.

---

## 4. Where this goes next

### Highest-ROI ship order

1. **Category 1 (gyms beaten)** — ship first. Already 90% of the way there, no decryption work, exercises the "after-parse detection service" pattern that the next two categories also need. It's the lowest-risk introduction of "the SRAM tells us things now."
2. **Category 3 (catches + routes)** — ship second. This is where users feel the difference daily. Pay the decryption cost here.
3. **Category 2 (gym teams)** — ship third, opportunistically, on top of category 3's parser. Smallest user-visible win, comes mostly free once decryption is built.

### Minimum new SRAM offset surface for category 1

**Zero new offsets.** `parsed_badges` is already verified and shipping. The work is purely in the diff/dispatch layer plus one schema decision (per-player vs. run-level).

### One shared infrastructure or three independent?

**One shared, in two layers.**

- **Layer A — `SoulLink::SaveDiff`** — a service that takes a slot and its previous-state snapshot, and surfaces a structured diff `{badges_gained: [bits], catches_added: [pkm], catches_evolved: [pkm], party_changed: [pkm]}`. Categories 1, 2, 3 are all diff consumers.
- **Layer B — `SoulLink::PartyParser` + `SoulLink::PkmDecoder`** — the cryptographic layer. Required by 2 and 3, optional for 1 (1 only needs the existing trainer-block parse).

**Don't** put the dispatch (creating `gym_results`, `soul_link_pokemon`) into the parse job itself. Keep the parse job a pure data extractor; have a separate `DetectChangesJob` (or a fan-out from the parse job) own the dispatch. Same separation of concerns the existing parser already follows — pure function returning a `Result` struct, side effects in the job. Mirror that pattern.

### New knowledge gaps this audit surfaces

- **KG-11: Party block offset within the SRAM slot is not yet pinned to a credible source.** projectpokemon's Platinum doc has `0xA0` but is "under construction"; pret/pokeplatinum's `SaveData` struct is the gold reference but not yet read by anyone on this team. Close before designing category 2.
- **KG-12: Met-location ID → route-name table not yet sourced.** Need a Platinum-specific location enum (different from `maps.yml`'s map-header enum). Similar to KG-7 in shape — need a real save with known catches to validate.
- **KG-13: Parse-failure path zeroes `parsed_badges` (`parse_save_data_job.rb:39`).** Pre-existing bug worth fixing before category 1 lands, otherwise the auto-detect will re-fire gym-beaten events every time a CRC-bad save lands and is then followed by a CRC-good save.

### Recommended next move

Get PO sign-off on the category-1 scope (per-player vs. run-level decision is the only blocker), then write a Step-15 brief for category 1 alone. It's a clean, ~SMALL step with zero crypto risk. If it lands well, Step 16 opens the category-3 (party + box decryption) work — at which point KG-11 and KG-12 become the design-phase prerequisites, and the brief calls for closing them before any code goes in, the same discipline that worked for KG-7 and `MAP_ID_OFFSET`.

— Ava
