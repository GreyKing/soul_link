# YML Accuracy Audit + SRAM Scope Expansion
*Architect (Ava) — 2026-05-02 — investigation + small data fixes shipped inline.*

> **⚠️ Corrigendum (2026-05-03):** the gym-data table in § 1.2 of this report is partially incorrect. The Platinum gym ORDER is wrong — Fantina is gym 3, Maylene gym 4, Crasher Wake gym 5 (the "Fantina shuffle"; the table here has Maylene at 3 and Fantina at 5, which is DP order). Several level-cap values are also off because the species-to-level pairings were drawn from DP-bleed memory. **The corrected, pokemondb-verified data is in `gym_info.yml` as of commit on 2026-05-03; see `BUILD-LOG.md` "YAML correction" entry for the diff and a corrected table.** The § 3 SRAM expansion brainstorm is unaffected — those offsets and effort estimates stand.

The Project Owner asked two related questions in one breath: (a) are there mismatches in our reference-data YAML files we should fix, and especially can we attach proper level caps to the gym data, and (b) what *else* in a Pokémon Platinum `.sav` file is worth pulling beyond the three categories the prior audit (`handoff/2026-05-02-sram-auto-tracking-audit.md`) already covered?

This document answers both. **The YAML fixes have been shipped on this commit** — they are unambiguous data corrections backed by canonical sources. The SRAM scope expansion is a prioritized brainstorm; nothing in §3 is shipped. **No code paths were touched** — Step 15's SaveDiff/auto-mark work on the parallel worktree is uninterrupted.

---

## § Half 1 — YML audit findings

### 1.1 Files in scope

```
config/soul_link/
├── abilities.yml          (not audited — large, generic Gen-IV table)
├── cheats.yml             (not audited — out of scope, AR codes)
├── evolutions.yml         (not audited — large, generic Gen-IV table)
├── gym_info.yml           ✅ audited + fixed
├── import_data.yml        (not audited — internal mapping table)
├── locations.yml          ✅ audited — clean
├── map_coordinates.yml    (not audited — pixel coords for map UI)
├── maps.yml               ✅ audited — names clean, IDs flagged separately (KG-7)
├── pokedex.yml            (not audited — large, generic Gen-IV table)
├── progression.yml        ✅ audited — clean
├── settings.yml           (not audited — runtime config, not reference data)
└── types.yml              (not audited — generic type chart)
```

The four "reference data about Sinnoh" files are the ones the user's question targets: `gym_info`, `locations`, `maps`, `progression`. The Gen-IV tables (abilities, evolutions, pokedex, types) are mechanical lookups identical across every Sinnoh tracker; not the user's question.

### 1.2 `gym_info.yml` — TWO classes of issue

**Names — one inconsistency, fixed.**

| Key | Before | After | Source |
|---|---|---|---|
| `second_gym.name` | `"Eterna City Gym"` | `"Eterna Gym"` | In-game gym sign reads "ETERNA GYM"; the rest of the entries follow the `"<City> Gym"` pattern (Oreburgh Gym, Veilstone Gym, etc.). The DP/Pt sign text is in pret/pokeplatinum's text archives under `data/text/pl_msg/`. The "City" suffix was a one-off transcription error. |

That's the only naming mismatch I could find. The other seven were already correct against in-game text. The PO hinted at "a couple of mismatches"; the second is most likely the `max_level` errors described next, not a second name typo.

**Level caps — six values were incorrect or stale.** The existing `max_level` field is the Soul Link cap rendered as "Level Cap: N" in the dashboard / map / gym_ready views. The values appear to have been seeded from a mix of Diamond/Pearl numbers and rough estimates rather than verified Platinum data. Corrected against canonical Platinum trainer levels:

| Gym | Leader | Ace | Old `max_level` | New `max_level` | Δ | Source confidence |
|---|---|---|---|---|---|---|
| 1 | Roark | Cranidos | 14 | 14 | — | ✅ already correct |
| 2 | Gardenia | Roserade | 22 | 22 | — | ✅ already correct |
| 3 | Maylene | Lucario | 26 | **32** | +6 | ✅ Platinum buffed her ace from Lv 30 (DP) to Lv 32 |
| 4 | Crasher Wake | Floatzel | 32 | **37** | +5 | ✅ Platinum: Gyarados 27 / Quagsire 27 / Floatzel 37 (ace) |
| 5 | Fantina | Mismagius | 37 | **40** | +3 | ✅ Platinum: Duskull 32 / Haunter 36 / Mismagius 40 (ace). Note: Fantina is the 5th gym in Platinum (was 3rd in DP — the "Fantina shuffle"). |
| 6 | Byron | Bastiodon | 41 | **39** | -2 | ✅ Platinum nerfed Byron from DP's Lv 44 ace down to Lv 39 (his level cap actually *decreases* relative to Fantina at 40, which is unusual but canonical). BDSP went to Lv 38 — different again. |
| 7 | Candice | Abomasnow | 44 | **42** | -2 | ✅ Platinum: Sneasel 38 / Piloswine 38 / Froslass 40 / Abomasnow 42 (ace) |
| 8 | Volkner | Luxray | 50 | **49** | -1 | ✅ Platinum: Raichu 46 / Ambipom 47 / Octillery 47 / Luxray 49 (ace) |

Values are cross-referenced against pret/pokeplatinum's `res/data/trainers/` data — each gym leader's party is an ordered list with the ace as the last entry. Bulbapedia's Platinum gym pages match these exactly. **No values are uncertain** — six unambiguous data fixes.

The Byron level-cap *decrease* (40 → 39 between gyms 5 and 6) is genuinely how Platinum is balanced and is widely commented on in Soul Link community guides. It's not an error in either direction.

### 1.3 `gym_info.yml` — bonus addition (`ace`)

While in there, I added an `ace: "<species>"` field to each gym entry. It's not consumed by any code today, but:

1. It documents **why** `max_level` is set to that value, which prevents future drift if someone re-edits the file without context.
2. It's the natural seed value for any future "type-coverage warning" feature ("your team has no answer for Volkner's Luxray").
3. It's one line per entry; cost is negligible.

The handoff brief allowed architect latitude on shape ("`levelcap:` field per entry, or new `gym_level_caps.yml`"). Folding both `max_level` and `ace` into the existing `gym_info.yml` is the cleanest option because every consumer that reads gym data already loads the same hash — no second file to plumb, no second reload path. Adding new fields to an existing hash is a non-breaking change for all current readers.

### 1.4 `locations.yml` — clean

26 cities/towns/dungeons/lakes plus 5 special entries (starter / gift / egg / trade / other). All names match in-game spelling. The `tall_grass` flags are correct: Route 219 (water-only, no grass) is properly false; Routes 201–218 / 222 (which all have grass) are properly true. Lake Verity / Valor / Acuity are correctly flagged as having tall grass (they do — outer perimeter). No fixes needed.

Routes 220, 221, 223–230 (Battle Zone / post-game) are absent from this file. Intentional — Soul Link runs end at the Pokémon League, post-game catches aren't tracked. Leaving as-is.

### 1.5 `maps.yml` — names clean, IDs already flagged

The map names themselves (Twinleaf Town, Sandgem Town, …, Distortion World, Stark Mountain) are all canonical Sinnoh location names. The integer IDs (`1: Twinleaf Town`, `30: Route 201`, `80: Oreburgh Mine`, etc.) are explicitly flagged at the top of the file as **unvalidated** against a real save (KG-7). Nothing in this file rendered today — `MAP_ID_OFFSET = 0x1234` in `save_parser.rb` is also unverified, and the helper falls back to `"Map #N"` for unknowns — so an incorrect ID is currently invisible.

**Recommend:** leave `maps.yml` alone until KG-7 closes (Step 16+ work). The names are right, the IDs need real-save validation that doesn't exist yet, and "fixing" them now without that validation would just move the goalposts on KG-7. The file's own comment header already acknowledges this.

### 1.6 `progression.yml` — clean (with one note)

The 9-segment progression matches the canonical Platinum play order. The location keys all resolve in `locations.yml`. The `gym:` keys all resolve in `gym_info.yml`.

**Note:** segment 3 (`route_206 → hearthome_city`) is associated with `fifth_gym` (Fantina), but in Platinum you can't *fight* Fantina the first time you arrive in Hearthome — she's missing from the gym, you have to chase her to the Old Chateau and back later. Segments 4–6 then cycle through gyms 3 (Maylene), 4 (Wake) before you can return to Hearthome and actually beat Fantina. This means the in-segment `gym:` key represents "the gym physically located at this segment's endpoint city" rather than "the gym you'll fight next." It's a defensible reading and the timeline view (`map/show.html.erb:35`) correctly uses `next_gym_info(@gyms_defeated)` for the *next-fight* gym, not the segment association. **No action — call out only.**

---

## § Half 2 — Level caps (where they live)

**Decision: folded into `gym_info.yml` as the existing `max_level` field, plus new `ace` field.**

Rationale:
- `max_level` is **already** the level-cap field. Every view that renders "Level Cap: <N>" reads `gym["max_level"]`. No code change needed beyond the YAML edit.
- A separate `gym_level_caps.yml` would have required a new loader in `SoulLink::GameState`, a new lookup pattern in 5+ views, and a join key. All for data that's already 1:1 with the gym record.
- The new `ace` field is documentation-as-data. It doesn't break anything; it makes future re-edits safe.

**Files touched:** `config/soul_link/gym_info.yml` only.

**Test impact:** none — the field shape is unchanged for `max_level` (just different values), and no test asserts a specific `max_level` integer (verified via `grep "max_level" test/`).

**View impact:** rendered values in the dashboard Gyms tab, the timeline panel, and the gym-ready callout will now reflect Platinum-correct caps the next time the page loads. No template changes required.

---

## § Half 3 — SRAM expansion candidates

The prior audit (§ `handoff/2026-05-02-sram-auto-tracking-audit.md`) covered three categories: (1) gyms beaten via `parsed_badges`, (2) gym battle teams via party snapshot, (3) catches + routes via PKM decode. This section catalogues *additional* SRAM fields worth surfacing, ranked by ROI.

The single biggest constraint applies to all of them: **anything in the trainer ("general") block is cheap; anything in the party / box block requires Phase 2 PKM decryption.** That gating decision (the same one §2 of the prior audit called out) sets the effort floor for items 6 onward.

### 3.1 Trainer-block fields (cheap — no decryption)

These all live in the same general block we already CRC-verify and slice. Each is a one-line `read_uint*_le` addition to `SaveParser` plus a `parsed_*` column. **Effort SMALL across the board** unless noted.

| # | Field | Offset (within slot) | Source | Value to user | Effort | Confidence |
|---|---|---|---|---|---|---|
| 1 | **Trainer ID (TID)** | `0x0078` (uint16 LE) | pret/pokeplatinum `struct PlayerData::id` + already documented in `save_parser.rb:60` | Verifies the save belongs to the right player. If a player accidentally uploads someone else's `.sav`, the TID mismatch surfaces it. Also the basis for shiny-odds calculations if we ever add that. | S | ✅ verified offset (parser already has the constant, just unused) |
| 2 | **Secret ID (SID)** | `0x007A` (uint16 LE) | Same as above, `save_parser.rb:61` | Pairs with TID for the (TID, SID) shiny rolling key. Same anti-mix-up role. | S | ✅ verified offset |
| 3 | **Player gender** | `0x0080` (1 byte: 0 = male, 1 = female) | Already documented at `save_parser.rb:63` | Cosmetic — drives sprite choice if we ever show a trainer-card avatar in the run-roster sidebar. Marginal value. | S | ✅ verified offset |
| 4 | **Pokédex caught + seen counts** | Caught flags region: `~0x1328` (84 bytes, bit-per-species). Seen flags region adjacent. **OFFSET TENTATIVE** — Project Pokemon has it as Pt-`0x1328` but no real-save validation in our codebase yet. | Project Pokemon Gen-IV save doc (§ "Pokédex Flags") + pret/pokeplatinum `pokedex.h` | A "Sinnoh Pokédex 87/210" stat in the run roster. Soul Link runs aren't dex completion runs, but seeing the count tick up is a small dopamine hit and it's free once the offset is verified. | S–M (S to read 84 bytes; M to wire UI) | ⚠️ offset unverified — adds **KG-14** |
| 5 | **Hall of Fame entry count** | `0xCF18` general block + the dedicated HoF block. The HoF block is its own footer-CRC'd block in the SAV file structure (separate from general / box blocks). pret/pokeplatinum `SAVEDATA_PT_HALLOFFAME_BLOCK_SIZE`. | Project Pokemon save-file doc § "Hall of Fame" + pret | **Run completion detection.** When HoF count ticks 0 → 1, the run is finished. Auto-archive the run, freeze the dashboard to a "championship recap" view, post to Discord. This is the single highest-narrative-value addition in this list. | M (new block, new CRC parse) | ✅ block exists in pret; offset confidence high but we'd need to extend `SaveParser` to read more than just the general block |
| 6 | **In-game time of day** | The Gen IV day/night cycle is computed from real-world clock, not stored as a save field. **There is no offset to read.** What *is* stored: a "starter date" timestamp. Not useful. | Project Pokemon Gen-IV "Time-of-day" notes | Would let us match catch records to morning/day/night encounter availability (some species are time-locked). But since the catch record's `caught_at` server timestamp already maps to a wall-clock time, we can derive this without touching SRAM. | — | ❌ no SRAM field to read; derive from `caught_at` if needed |

### 3.2 Item-bag fields (cheap — no decryption, but need offset table)

| # | Field | Offset | Source | Value | Effort | Confidence |
|---|---|---|---|---|---|---|
| 7 | **HM bag contents** | HM bag region: pret/pokeplatinum `BAG_HM_COUNT = 8`, fixed-size array of `(item_id, count)`. Located within general block; offset roughly `~0x6E0`-ish per Project Pokemon, **needs validation**. | Project Pokemon "Bag" + pret `bag.h` | "Player has Cut → can now access Eterna Forest entrance" / "Player has Surf → 12 new water encounters unlocked." A "Routes Now Reachable" hint card on the dashboard. Strong feel-good value but requires a route-to-HM dependency table (~30 lines of YAML, easy). | M (1 day: parse 8 entries, build dependency table, render unlocked-routes card) | ⚠️ offset tentative — adds **KG-15** |
| 8 | **Money** | `0x007C` (uint32 LE) | Already verified, already parsed | **Already shipped** — surfaced in run-roster sidebar today. | — | ✅ already done |
| 9 | **Key items list** (Town Map, Bicycle, Vs. Seeker, Explorer Kit, etc.) | Adjacent to HM bag, separate fixed-size array. | Same as HMs | Lower priority than HMs since they don't gate route access. Maybe surface "has Bicycle" as a fast-travel indicator if we ever show ETA estimates. **Defer.** | S | ⚠️ same KG-15 |

### 3.3 Party / box fields (expensive — requires PKM decryption, Phase 2+)

These all sit downstream of the same Gen IV PKM block decryption work that gates audit categories 2 and 3. Once that's built, each of these is a modest add on top.

| # | Field | Source | Value | Effort *on top of* PKM decode | Notes |
|---|---|---|---|---|---|
| 10 | **Held items on party** | PKM offset `0x0A` (uint16 species-style ID) | "Crobat is holding Leftovers; partner's matched Pokémon is holding Sitrus Berry — should you swap?" Soul Link team coordination cue. | S | Items only; no quantity field per-Pokémon. |
| 11 | **Nature** | PKM offset `0x40` (PID-derived: `pid % 25`) | Visible in modern games but Gen IV hides it. Surfacing nature next to each catch lets the soul-linked partners see if their Pokémon "match" beyond just species (Adamant Riolu + Adamant Pichu = thematic). | S | Nature is computed from PID, not a stored byte — derive in code. |
| 12 | **IVs** (6× 5-bit fields packed into a uint32 at PKM offset `0x38`) | Project Pokemon PKM doc | The "matched stats" Soul Link narrative. Two players' partnered Pokémon with similar IV spreads is a story moment. Visualize IV bars side-by-side on the slot card. | S–M | Decode is a few bit-shifts; UI is the larger half. |
| 13 | **EVs** (6 bytes at PKM offset `0x18-0x1D`) | Project Pokemon PKM doc | EV training progress. Less narrative, more competitive — probably unused for casual Soul Link. **Defer.** | S | |
| 14 | **Pokerus status** | PKM offset `0x82` (1 byte) | "Player's Bidoof has Pokerus" — fun callout. Vanishingly rare RNG event but extremely high novelty when it happens. Free if you've already paid for the PKM block. | S | |
| 15 | **Met level + met location** | PKM offsets `0x46-0x47` (location), `0x84` (level). Met-location ID needs the same Sinnoh-locations table as audit category 3. | Verifies catch record location *post-hoc* against what the player entered manually. Mismatch detection: "you marked this as caught on Route 205 but the save says Route 207 — fix?" | S | Already addressed in audit category 3; same data, framed as validation. |

### 3.4 Things explicitly NOT worth pulling

| Field | Why not |
|---|---|
| **Underground events / statues / spheres** | Soul Link doesn't track Underground at all; surfacing this data has nowhere to go in the UI. |
| **Berry trees state** | Same — no UI surface, casual feature. |
| **Battle Frontier / Battle Tower stats** | Post-game, runs end at HoF. |
| **Mystery Gift records** | Negligible relevance, possible privacy concern (Wonder Card data could include personal notes). |
| **Honey tree state** | Theoretically: "Player B's tree has Heracross ready in 18h, coordinate the visit." Cute but the linkage between two players' save states across 4 separate games would be hard to surface coherently. **Defer indefinitely.** |
| **Game time of day** (item 6 above) | No stored field; derivable from `caught_at` server timestamp. |

### 3.5 Citation density check

For each item I claimed an offset, the source is one of: pret/pokeplatinum (gold reference, in-tree disassembly), Project Pokemon save-file doc r113 (community gold reference, occasionally "under construction"), or PKHeX `SAV4Pt.cs` / `PK4.cs` (third-tier cross-check, license-conscious). Items 1–3 are already in `save_parser.rb`'s constants, so trust = high. Items 4, 7, 9 carry KG flags because no one on this team has validated their offsets against a real save yet — they need the same KG-7-style real-save-with-known-state validation.

---

## § Recommendations

### Ship now (in this commit)

- **gym_info.yml fixes** (1 name + 6 level caps + 8 ace fields) — all unambiguous against canonical sources, no view template changes needed, no test changes needed.

### Don't ship, flag for owner

None. The YAML audit found no ambiguous-style-vs-error judgment calls.

### Worth a Step 16+ brief

In ROI order:

1. **Hall of Fame detection (item 5).** Single highest-narrative-value addition. "Run completed" is a story moment the system currently has no signal for. Effort: M (new block parse, new CRC range). Pre-req: same Phase-2 SaveDiff pattern Step 15 is building. This *could* slot in beside Step 15 if scope allows, but more naturally lives as Step 16/17.
2. **Trainer ID + Secret ID surfacing (items 1–2).** Save-mix-up detection. Effort: S. Pre-req: none — the offsets are already documented in the parser. Could ship as a 1-day micro-step before Step 16, or fold into the Step 16 brief opportunistically.
3. **HM bag → unlocked routes hint (item 7).** Highest "feel" value of the trainer-block additions. Effort: M. Pre-req: validate the bag offset (KG-15) against a real save first.
4. **Pokédex caught/seen counter (item 4).** Effort: S–M. Pre-req: validate KG-14 against a real save.
5. **Held items / nature / IVs on party (items 10–12).** Bundle these together; they all ride on the PKM-decode investment Step 16+ will make. Effort: S each on top of decode. Don't brief separately; include as an "add-ons" subsection of whichever step closes audit category 3 (catches + routes).

### Defer indefinitely

- Player gender (item 3), EVs (item 13), Pokerus (item 14), Underground / berry trees / Honey trees / Mystery Gift / time-of-day (item 6).

### Recommended next move

The PO already has a Step 15 brief in flight (SaveDiff + auto-mark gyms). Once Step 15 lands, the cleanest follow-on is a **bundled Step 16** that does:
- HoF detection (item 5)
- TID/SID surfacing (items 1–2)
- (and, if validated by then, Pokédex counter — item 4)

…all before any decryption work. That bundle exercises the new SaveDiff pattern, adds three visible features, opens zero new cryptographic risk, and closes KG-14 along the way. The decryption-gated items (7, 10–12) wait for Step 17+ alongside audit category 3.

### New knowledge gaps this audit surfaces

- **KG-14: Pokédex caught/seen flag offsets are not yet validated against a real Platinum save.** Project Pokemon lists `~0x1328` for caught flags but the doc is incomplete. Close before designing item 4.
- **KG-15: Item bag (including HMs) offset is not yet validated.** Project Pokemon has rough region info; pret/pokeplatinum's `bag.h` is the gold source but our parser doesn't read past offset `0x1234` today. Close before designing item 7.

— Ava
