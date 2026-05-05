# Architect Brief
*Written by Architect. Read by Builder and Reviewer.*
*Overwrite this file each step — it is not a log, it is the current active brief.*

> Locked instructions for the current step. Bob, this is your only source of truth.
> If anything below contradicts the mockup HTML, **the mockup wins**. Tell Arch.

---

## Step 23 — R4 Map / Route timeline redesign + clickable map locations (Phase 2 R4 of the 2026-05-04 UI/UX audit)

### Reference files (read in this order, then stop)

1. `handoff/2026-05-04-ui-audit-mockup-map.html` — **the locked design.** 4 screens (desktop full timeline · sheet open / new catch · sheet open / existing catches · mobile accordion). Mockup wins on every visual + interaction detail.
2. `handoff/2026-05-04-ui-audit.md` § 4 R4 — narrative rationale (~6 lines on what changes).
3. `app/views/map/show.html.erb` — the file you are rewriting. Read end-to-end first.
4. `app/javascript/controllers/timeline_controller.js` — read end-to-end. You will **extend** this controller, not replace it. Existing actions (`selectLocation`, `openPanel/closePanel`, `submitCatch`, `toggleGym`, `filterSpecies`, `selectSpecies`) all stay; new actions are layered on.
5. `app/controllers/map_controller.rb` — read-only. **No change.** The existing `@locations / @progression / @gym_info / @groups_by_location / @players / @gyms_defeated / @pokedex_species` set covers everything the new view needs.
6. `app/helpers/map_helper.rb` — you will extend (`location_status` / `primary_group` / `groups_json_for` / `timeline_node_size` already exist). Add new helpers as needed but keep the public API of the existing ones intact.
7. `app/assets/stylesheets/pixeldex.css` — locate the existing `@media (max-width: 520px)` and `@media (max-width: 900px)` blocks. The new R4 styles get a fresh `/* ── R4 Map ── */` section above the R2 marker; you will **extend** the existing breakpoints, not replace them.
8. `app/controllers/pokemon_groups_controller.rb#create` — read-only. The catch form already POSTs there with `nickname` / `location` / `species[uid]` params; no controller change.
9. `config/soul_link/locations.yml` (skim only) — confirm the `gift / egg / trade / other / starter` keys exist; the special-encounters bar uses these exact keys today.

Do NOT load: domain-models docs, the bot, the auth concern, the Discord notifier, any service file, the dashboard map tab. The brief has the data shapes you need.

### Context

Phase 2 R2 (PC Box) shipped at `1375335` / merged to main at `d442568`. R4 Map is next in the audit's locked ship order: R3 ✓ → R2 ✓ → **R4** → R1. After R4 ships, the session ends — R1 Dashboard gets its own session.

**Surface in scope:** the standalone `/map` page (`app/views/map/show.html.erb`). The dashboard MAP tab (`app/views/dashboard/_map_content.html.erb` — ASCII map + route cards) is **out of scope** — that's the cross-cutting-6 IA decision and R1 reshapes the dashboard chrome anyway.

**New feature on top of the visual redesign:** "clickable map locations." The mockup already routes click-to-open via `selectLocation` — what's new is **(a)** the visible click affordance (mockup's hover lift + amber border + box-shadow on every node, no exceptions), **(b)** the disambiguation when a location has multiple Soul Link groups (dupes-clause re-rolls), and **(c)** URL hash persistence so `#route=route_205` survives refresh + Turbo morph.

**Data model unchanged.** All the data already loads: `@groups_by_location[loc_key]` returns an Array of `SoulLinkPokemonGroup` for any location — multiple groups at the same location is normal (dupes-clause). **No migration. No controller change. No new endpoint. No new YAML.**

### Architect decisions (locked — do not re-litigate)

1. **CSS namespace under `.map-r4`** (Step 22 `.pc-box-r2` precedent). Wrap the new view body in `<div class="map-r4" data-controller="timeline" …>…</div>`. Every new CSS rule prefixed `.map-r4 …`. The mockup's class names (`.timeline-frame`, `.node`, `.sheet`, `.accordion-segment`, `.special-cell`, etc.) are fresh — namespace prevents accidental collision with future `.timeline-*` rules elsewhere AND scopes the redesign cleanly.

2. **The mockup's right-rail sticky SHEET replaces today's overlay slide-out panel.** The old `position: fixed` slide-out + backdrop is **removed** (`backdrop` target, `panel`/`panelTitle`/`panelBody`/`panelForm` retargeted). The new sheet sits in a CSS Grid column on desktop:
   - **Outer layout:** `.map-r4 .layout { display: grid; grid-template-columns: minmax(0, 1fr) 380px; gap: 22px; align-items: flex-start; }` — left column = timeline frame + special-encounters bar; right column = sticky sheet.
   - **Sheet markup:** `<aside class="sheet" data-timeline-target="sheet">` with `.sheet-head` (h3 + close button) + `.sheet-body`. Sheet is `position: sticky; top: 16px;` so it follows page scroll on desktop.
   - **Default empty state** when no location is selected: `.sheet-body` shows a short "Select a route to view or log catches" copy block. (Mockup omits this — Ava decision: idle state must read sensibly because the sheet is always visible on desktop.)
   - **No backdrop, no `translateX` transition, no `overflow-hidden` body lock.** Those are overlay artefacts; sheet is in-flow now.

3. **Mobile breakpoint = 720px for the timeline → accordion swap; 520px for the layout-stack + special-encounters reflow.** Two-tier:
   - At `@media (max-width: 720px)`: hide `.map-r4 .timeline-frame`, show `.map-r4 .accordion-frame`, drop `.map-r4 .layout` to `grid-template-columns: 1fr` so the sheet stacks under the accordion. Inside the same block, the sticky sheet drops `position: sticky` (it's full-width and inline now).
   - At `@media (max-width: 520px)`: existing `gb-grid-N` rules (Step 20) already cascade. The mockup's `.special-grid` uses `grid-template-columns: repeat(4, 1fr)` — extend the 520px block to also reflow `.map-r4 .special-grid` to `repeat(2, 1fr)`.
   - **Both breakpoints extend existing blocks, not new blocks.** Same pattern as Step 22.

4. **Mockup's pulse-ring + "↓ NOW" pin marks the next-uncaught route.** Identification rule (locked): walk `@progression["segments"]` in order, then `(segment["locations"] || []).each`, find the **first** location whose `location_status(@groups_by_location[loc_key])` returns `"uncaught"` AND whose `loc_data["type"]` is `"route"` (skip cities, dungeons, special). The first match wins. Apply `.next` class to that node + render `<span class="node-now-pin">↓ NOW</span>` inside it. If no uncaught route exists (all caught — late-game), no `.next` class anywhere; that's fine.
   - The existing `scrollToCurrentProgress()` action keeps working — it already targets `dataset.status === "uncaught"`.
   - Helper: `MapHelper#next_uncaught_route_key(progression, locations, groups_by_location)` returns the loc_key string or `nil`. Pure-function, view-rendered. No DB call.

5. **Always-visible legend strip** sits between the status bar and the timeline frame. Five glyphs + labels: caught (●) · dead (☠) · uncaught (○) · special (★) · gym (G). Use the mockup's exact `.node-legend` markup verbatim. Do NOT make this collapsible; it's mockup-locked as always-visible.

6. **Segment dividers between segments.** Render the existing `@progression["segments"]` array as before, but between each pair of segments emit a `<div class="timeline-segment-divider" data-segment="VEILSTONE">` with the segment label uppercased. Existing data already has `segment["name"]` or similar — confirm the key during your "Files to verify" pass. If the YAML has no per-segment label, fall back to the next-gym name (`@gym_info[segment["gym"]]["location_name"]` uppercase). Locked.

7. **Edge gradient fade** is two CSS pseudo-elements on `.timeline-frame::before` (left, 36px) + `.timeline-frame::after` (right, 64px). Mockup verbatim. The user can scroll past them; they're decorative. **Pure CSS, no JS.**

8. **"JUMP TO NOW" pill** is a `<button class="jump-btn" data-action="click->timeline#jumpToNow">` in the status bar (right-aligned via `margin-left: auto`). New action `jumpToNow()` on the existing controller — finds the `.next` node and `scrollIntoView({ behavior: "smooth", inline: "center" })`. If no `.next` node exists (all caught), the action is a no-op; **also add `data-timeline-target="jumpBtn"` and hide the button via `if (!this.hasNextNode) this.jumpBtnTarget.classList.add("hidden")` in `connect()`**. Mockup's `subtleBlink` keyframe stays as-is.

9. **Status bar (`.status-bar`) replaces today's "Level Cap" pill.** Three items + the JUMP TO NOW button:
   - `NEXT GYM` → `@next_gym["leader"] · @next_gym["type"]` (or `All 8 earned · Elite Four ahead` if `@next_gym.nil?`)
   - `LEVEL CAP` → `@next_gym["max_level"]` (or `—` if no next gym)
   - `CURRENT SEG` → segment label of the segment containing the next-uncaught route (or `Final stretch · Elite Four` if all caught). Helper: `MapHelper#current_segment_label(progression, next_uncaught_key)`.
   - The existing "All 8 badges earned!" copy gets folded into NEXT GYM's `—` state.

10. **Badge strip on `.map-head` is the existing badge buttons restyled.** The Stimulus action `click->timeline#toggleGym` stays. Replace the inline-styled `<button>` with the mockup's `.badge` / `.badge.earned` markup. The `title` attribute (gym name + leader + type + level) stays — it's the existing tooltip + hover behavior. **No interaction change.**

11. **Click-to-open routing — the new feature.** `selectLocation(event)` keeps its current shape but the **rendering path branches differently**:
    - `groups.length === 0` (uncaught) → render `_renderSheetCatchForm(key, name)` (Screen 2 of mockup)
    - `groups.length === 1` → render `_renderSheetGroup(group)` then **also** append the dashed `+ ANOTHER ENCOUNTER (DUPES CLAUSE)` button at the bottom (Screen 3 of mockup) — clicking it switches the sheet body to the catch-form layout for adding a second group at the same location
    - `groups.length > 1` → render the most-recent group's card prominently AND render a stacked sub-list of additional group cards below (each with its own EDIT / MARK DEAD inline-confirm buttons), then the dashed `+ ANOTHER ENCOUNTER` button at the bottom.
    - **Disambiguation interpretation:** in Soul Link, ONE group = ONE soul-linked catch with all 4 players' species. Multiple groups at same location = dupes-clause re-rolls / backfills. The user's "default to current_user's catch" maps cleanly to: show the most-recent group prominently, additional groups stacked below as cards.

12. **Sheet form is the existing multi-player Soul Link group form, restyled.** It POSTs to `pokemon_groups#create` exactly as today — `nickname` + `location` + `species[uid]` per player. Reuse `submitCatch` action verbatim. Restyle to mockup Screen 2's `.form-row` / `.player-row` / `.preview` / `.submit-btn` (`+ LOG GROUP` copy). The existing `filterSpecies` / `selectSpecies` combobox + `speciesPreview` target chain stays — that's already a custom Stimulus combobox, not `<datalist>`, despite the audit's prose suggesting the contrary.
    - **Do NOT** route into the dashboard's `_catch_modal.html.erb`. That partial is single-player manual entry to a different model (`SoulLinkPokemon` direct, not `PokemonGroup`). Different semantics.

13. **Sheet "view existing catches" markup follows mockup Screen 3.** Per group: `.group-card` with `.head` (nickname + ALIVE/DEAD pill) + four `.player-row` rows (player name + sprite preview + `Species · Lv N`) + footer row with `EDIT` + `MARK DEAD` buttons. Build via `_renderSheetGroup(group)` JS method (analogue of the existing `buildDetailsHtml`).
    - **EDIT button:** opens the existing `_pokemon_modal.html.erb` partial — the per-Pokemon edit modal already lives on the page; same `dashboard#openPokemonModal` action with the group's first pokemon as the data payload. **Wait — `_pokemon_modal.html.erb` is rendered on the dashboard, NOT on `/map`.** Decision: render the existing `_pokemon_modal.html.erb` + `_mark_dead_modal.html.erb` partials on `/map` too, so the EDIT and MARK DEAD buttons can dispatch to them. They're already ARIA-wired (Step 20). Add to the bottom of `map/show.html.erb`.
    - **MARK DEAD:** triggers the existing `_mark_dead_modal.html.erb` partial via `confirm-modal#open` — already wired in Step 20. Same flow as the dashboard.
    - **Nicknames render in the existing modal partials:** the per-pokemon edit modal already takes nickname/species/level/ability/nature; no field changes. Mark-dead modal already takes eulogy.

14. **URL hash `#route=<key>` preserves sheet state.** On `selectLocation`, write `location.hash = "#route=" + key`. On `connect()`, if `location.hash.startsWith("#route=")`, parse the key and re-trigger `selectLocation` against the matching node. Empty hash = idle sheet. Closing the sheet (X button or no-op) clears the hash via `history.replaceState(null, "", location.pathname)`. **Same pattern as Step 22's `pc_box_filter_controller.js`.**
    - Use `#route=<key>` (hash, not query string) — Step 22 precedent + survives Turbo morph + no server round-trip.
    - The mockup's `+ ANOTHER ENCOUNTER` toggle does NOT change the hash; it just swaps the sheet body to form mode for that already-selected route.

15. **Visible click affordance on every node = the mockup's hover treatment.** The user's prompt mentioned "+" / eye-icon overlays as suggestions; the mockup's design ships:
    - `cursor: pointer` (already on the `<button>`)
    - `transform: translateY(-2px)` on `:hover .glyph`
    - `border-color: var(--amber)` on `:hover .glyph`
    - `box-shadow: 0 4px 0 rgba(212, 177, 74, 0.3)` on `:hover .glyph`
    - `outline: 3px solid var(--amber)` on `:focus-visible .glyph`
    - `.next` adds the pulse-ring animation as a permanent affordance on the active route
    - **Locked: this IS the click affordance.** No literal "+" / eye-icon overlays — the mockup's interaction language is consistent and color-blind-safe (motion + outline + amber, not just color).

16. **Read-only mode (`dashboard_read_only?(@run)`) hides the catch form + the EDIT / MARK DEAD buttons + the dupes-clause "+ ANOTHER ENCOUNTER" button.** Same gate as today (`<% unless dashboard_read_only?(@run) %>` already wraps the panelForm at line 227 of the existing view). View-only sheet (showing groups) still works.

17. **Special-encounters bar (`gift / egg / trade / other`) follows mockup Screen 2's `.special-bar`.** Replace the existing `gb-grid-4` block with the mockup's `.special-bar` + `.special-grid` markup (`grid-template-columns: repeat(4, 1fr)` on desktop, reflows to `repeat(2, 1fr)` at 520px). Each `.special-cell` keeps `data-action="click->timeline#selectLocation"` + `data-timeline-target="locationNode"` + `data-location-key`/`name`/`status`/`groups`. **Same click semantics as the timeline nodes** — they go through the same sheet-rendering path.

18. **Coloured node states + glyphs (mockup-verbatim):**
    - `.node.caught .glyph` → green-glow border, dark fill, ● glyph (or sprite if first pokemon has one — keep the existing `pokemon_sprite_tag` rendering inside the glyph for caught nodes)
    - `.node.dead .glyph` → crimson border, `#4a1c1c` fill, ☠ glyph
    - `.node.uncaught .glyph` → l2 fill, d2 border, ○ glyph (small, faint)
    - `.node.special .glyph` → amber border, d1 fill, ★ glyph (for `loc_type == "special"`)
    - `.node.gym .glyph` → amber fill, gym number text, 64×64
    - `.node.gym.beaten .glyph` → d1 fill, amber text + border (defeated style)
    - `.node.next` → adds the amber pulse-ring + the floating "↓ NOW" pin
    - **Tokens:** `--green-glow` and `--crimson` already exist (Step 21). `--d0` already exists. **No new design tokens.**

19. **Mobile accordion (Screen 4).** Replace `.timeline-frame` with `.accordion-frame` containing one `<details class="accordion-segment">` per segment. Open the segment containing the next-uncaught route by default (use `<details open>` server-rendered by the helper). Each accordion body lists `.acc-row` items per location with a 36px glyph + meta (loc + nick) + chevron. Tapping an `.acc-row` triggers the same `click->timeline#selectLocation` flow → opens the sheet (which on mobile sits below the accordion).
    - **Accordion body is server-rendered** — no JS needed for open/close (native `<details>`). Stimulus only needs to add `open` to the active segment in `connect()` if not already open via server-render.
    - Helper: `MapHelper#segment_progress(segment, groups_by_location)` returns a `{ caught: N, total: M }` hash so the summary can render `5/6 ✓` or `1/6 NOW`. New helper.

20. **Existing slide-out panel cleanup.** Delete the old panel markup (lines ~209-274 of `show.html.erb`): `data-timeline-target="panel"`, `panelTitle`, `panelBody`, `panelForm`, `formLocationKey`, `nicknameInput`, `formStatus`, `speciesSearchWrapper`, `speciesHidden`, `speciesDropdown`, `speciesPreview`, `backdrop`. Re-introduce the equivalents under the new `.sheet` markup with **the same target names** so the JS extension is minimal:
    - `panel` → `sheet`
    - `panelTitle` → `sheetTitle`
    - `panelBody` → `sheetBody`
    - `panelForm` → `sheetForm` (lives inside `.sheet-body`, hidden until needed)
    - `backdrop` → **removed** (no overlay)
    - All other targets keep their current names (`formLocationKey`, `nicknameInput`, `formStatus`, `speciesSearchWrapper`, `speciesHidden`, `speciesDropdown`, `speciesPreview`).
    - Update `openPanel` / `closePanel` to operate on the new sheet (no `translateX`, no `backdrop`). Empty state is a sibling block inside `.sheet-body` toggled visible when no key is selected.

### What's out of scope (escalate if you reach for any of these)

- Dashboard MAP tab (`_map_content.html.erb`) — R1 reshapes the dashboard chrome.
- Schema changes / new columns / new endpoints / new model methods.
- New YAML keys. The existing `progression.yml` / `locations.yml` / `gym_info.yml` provide everything.
- Real combobox migration / `<datalist>` cleanup — `filterSpecies` / `selectSpecies` already IS a custom combobox; mockup is correct that it should be used (it already is). No conversion work.
- Half-height bottom-sheet snap behavior on mobile. Mockup mentions it as polish; out of scope. The mobile sheet just stacks under the accordion in-flow.
- Per-segment auto-scroll / "intersection observer" wayfinding. JUMP TO NOW button is the only wayfinding CTA shipped in this step.
- New click-to-copy / share-route-URL features. URL hash persistence is `#route=<key>` only; no copy button on the sheet.
- Discord notification changes.

### Constraints

1. **Mockup wins on every visual detail.** Step 21 + 22 precedent. Where the prompt and the mockup conflict, mockup wins. Surface conflicts in REVIEW-REQUEST.md so Ava can audit.
2. **`.map-r4` namespace prefix on every new CSS rule.** No bare `.timeline-frame` / `.node` / `.sheet` etc. selectors.
3. **Extend the existing 520px and 900px media blocks; do not create new ones at those widths.** Add a fresh `@media (max-width: 720px)` block for the timeline → accordion swap (R4-specific breakpoint, not a generic gb-grid one).
4. **Preserve existing Stimulus action signatures.** `selectLocation`, `submitCatch`, `toggleGym`, `filterSpecies`, `selectSpecies`, `closeAllDropdowns`, `handleKeydown`, `scrollToCurrentProgress` — all stay callable. Add new ones (`jumpToNow`, possibly internal helpers) without renaming the old ones.
5. **`MapController#show` is read-only.** No new instance variables, no new queries.
6. **No new gem dependencies. No new design tokens. No migration. No JS bundling change.** Verify by `git diff Gemfile Gemfile.lock db/ config/importmap.rb` showing zero changes.
7. **Read-only mode (`dashboard_read_only?(@run)`) gates LOG / EDIT / MARK DEAD / `+ ANOTHER ENCOUNTER` exactly like today.**
8. **Render `_pokemon_modal.html.erb` + `_mark_dead_modal.html.erb` partials at the bottom of `map/show.html.erb`** so the in-sheet EDIT and MARK DEAD actions can dispatch into them. They're rendered on the dashboard today; rendering them here too is mockup-required and Step 20 already made them ARIA-safe.

### Files to write / edit

- **`app/views/map/show.html.erb`** — full body rewrite per mockup Screens 1, 2, 3, 4. Outer wrapper `<div class="map-r4" data-controller="timeline" …>`. Includes: `.map-head` (title + badges) + `.status-bar` + `.node-legend` + `.layout` grid (left: `.timeline-frame` desktop / `.accordion-frame` mobile + `.special-bar`; right: `.sheet`). Render `_pokemon_modal.html.erb` + `_mark_dead_modal.html.erb` partials at the bottom.
- **`app/assets/stylesheets/pixeldex.css`** — new `/* ── R4 Map ── */` section above the existing `/* ── R2 PC Box ── */` marker. Mockup CSS verbatim with `.map-r4` prefix on every selector. Extend the existing `@media (max-width: 520px)` and `@media (max-width: 900px)` blocks. Add a NEW `@media (max-width: 720px)` block for the timeline → accordion swap. **Zero new design tokens** (`--green-glow`, `--crimson`, `--d0`, `--amber`, `--d1`, `--d2`, `--l1`, `--l2`, `--white` already declared).
- **`app/javascript/controllers/timeline_controller.js`** — extend, don't replace. Rename target vocabulary (`panel*` → `sheet*`, drop `backdrop`). Rewrite `openPanel`/`closePanel` for the new sheet. Add `jumpToNow` action. Add hash-read in `connect()` + hash-write in `selectLocation` + hash-clear in `closePanel`. Keep all existing actions and value contracts.
- **`app/helpers/map_helper.rb`** — add three helpers:
   - `next_uncaught_route_key(progression, locations, groups_by_location)` → returns the loc_key string (or `nil`).
   - `current_segment_label(progression, next_uncaught_key)` → returns the segment name uppercase (or `"Final stretch"` fallback).
   - `segment_progress(segment, groups_by_location)` → returns `{ caught: N, total: M }`. Pure functions over the existing inputs, no DB calls.
- **`test/integration/responsive_grids_test.rb`** — extend with Step 23 R4 assertions:
   - `.map-r4` namespace declared outside any media block.
   - `@media (max-width: 720px)` block exists; inside it, `.map-r4 .timeline-frame { display: none; }` and `.map-r4 .accordion-frame { display: block; }`.
   - `@media (max-width: 520px)` block reflows `.map-r4 .special-grid` to `repeat(2, 1fr)`.
   - Neither breakpoint sets `display: none` on `.map-r4 .node`, `.map-r4 .sheet`, `.map-r4 .acc-row` (Step 21 / 22 contract).
- **`test/integration/map_redesign_test.rb`** — NEW integration test, Step 22 `pc_box_redesign_test.rb` is the template. Cover the assertions in the next section.
- **`test/helpers/map_helper_test.rb`** — NEW unit tests for the three new helper methods + the existing `location_status` / `primary_group` (currently untested). FactoryBot only — no fixtures.

### Tests to add (locked buckets)

Use FactoryBot. New file: `test/integration/map_redesign_test.rb`.

1. **`.map-r4` wrapper + dual-targeted Stimulus controller** — assert `<div class="map-r4" data-controller="timeline"` is present in `get /map`.
2. **Always-visible legend strip** — assert `.node-legend` block with five glyph items: `.glyph.caught`, `.glyph.dead`, `.glyph.uncaught`, `.glyph.special`, `.glyph.gym`. Each carries the matching label text.
3. **Pulse-ring on next-uncaught route** — set up a run where Route 201 is caught and Route 202 is uncaught (factory). Assert the Route 202 `<button class="node next` exists exactly once + carries `<span class="node-now-pin">↓ NOW</span>`.
4. **JUMP TO NOW button is hidden when no uncaught route exists** — set up a run where every route is caught. Assert `.jump-btn.hidden` (or absent + the helper returns nil — pick one and lock it). Test is the contract.
5. **Status bar renders next-gym, level cap, current segment** — assert the three `.item` blocks under `.status-bar`. With `gyms_defeated = 8` (no next gym), assert the `—` fallback copy.
6. **Click-route-without-catches opens form sheet** — *integration test cannot click; assert markup contract instead.* Assert `.sheet-body` has both `.empty-state` and `.sheet-form` (both starting hidden) + the form's species inputs are one per `SoulLink::GameState.players` entry. The JS swap between empty / form / group-list is unit-tested at the controller level (no integration test needed).
7. **Click-route-with-catches sheet markup** — *as above.* Group-card markup is built JS-side; assert the `.sheet` element exists and the `data-groups` attribute on the relevant `.node` carries the expected JSON shape (existing `groups_json_for` test).
8. **Disambiguation list — multiple groups at same location** — factory: create 2 `PokemonGroup`s on the same location_key. Assert `groups_json_for(groups)` (existing helper) returns a 2-element JSON array on the matching node's `data-groups` attribute. Sheet rendering of the second group is a JS concern; the test asserts the data is delivered.
9. **`#route=<key>` URL hash persistence is JS-only — no integration test required.** Document the contract in the controller comment but skip the unit test for hash read/write (Step 22 KG-35-style — Stimulus hash logic is hard to assert without a headless driver).
10. **Empty / read-only mode hides catch form + EDIT + MARK DEAD + DUPES-CLAUSE button** — set `run.wiped_at = Time.now`, render. Assert no `.sheet-form`, no `EDIT`, no `MARK DEAD`, no `+ ANOTHER ENCOUNTER` text in response body.
11. **Special-encounters bar** — assert `.special-bar` with four `.special-cell` children for `gift / egg / trade / other`. Each cell carries `data-action="click->timeline#selectLocation"` + the right `data-location-key`.
12. **Mobile accordion markup** — assert `.accordion-frame` exists with one `<details class="accordion-segment">` per segment. The segment containing the next-uncaught route has the `open` attribute. Each `.acc-row` carries `data-action="click->timeline#selectLocation"`.
13. **Pokemon + Mark-Dead modals are rendered on `/map`** — assert `id="pokemon-modal"` and `id="mark-dead-modal"` (or whatever the existing partial ids are; verify before locking) exist in `get /map` body.

In `responsive_grids_test.rb`:

14. `.map-r4` namespace declared outside any media block (parallel to Step 22 R2 namespace test).
15. `@media (max-width: 720px)` block exists + sets `.map-r4 .timeline-frame { display: none }` + `.map-r4 .accordion-frame { display: block }`.
16. `@media (max-width: 520px)` block reflows `.map-r4 .special-grid` to `grid-template-columns: repeat(2, 1fr)`.
17. Neither breakpoint sets `display: none` on `.map-r4 .node`, `.map-r4 .sheet`, `.map-r4 .acc-row`.

In `map_helper_test.rb`:

18. `next_uncaught_route_key` returns the first uncaught route across segments; skips cities/dungeons; returns `nil` when all routes are caught.
19. `current_segment_label` returns the next-gym name uppercased when a next-uncaught route exists; returns `"Final stretch"` when nil.
20. `segment_progress` returns `{ caught: 5, total: 6 }` for the existing `progression.yml` fixture-like setup.
21. (Bonus, low cost) `location_status` returns `"caught"` / `"dead"` / `"uncaught"` correctly given a mixed groups Array. `primary_group` returns the most-recent caught group.

### Files to verify before writing code

Bob: **before you write a single line of code, do this read pass and confirm the brief is complete in REVIEW-REQUEST.md.** Specifically verify:

A. **What exact key does `progression.yml` use for the segment label?** Does `segment["name"]` exist, or is it derived from `gym["location_name"]`? Confirm before locking the segment-divider rendering. If neither exists, adapt — log the divergence in REVIEW-REQUEST.md.

B. **What `data-*` attributes does `_pokemon_modal.html.erb` need on the dispatch button?** Today it's invoked from the dashboard's pixeldex grid via `pixeldex#selectPokemon`. The map's EDIT button needs to dispatch the same payload — verify whether the EDIT click should fire `pixeldex#selectPokemon` (with the same `data-group-*` attributes) OR a new action. Lock whichever works without controller surgery.

C. **Confirm `_mark_dead_modal.html.erb` is wired through the Step 20 `confirm-modal#open` pattern OR has its own ad-hoc trigger.** If ad-hoc, the map's MARK DEAD button matches that pattern; if `confirm-modal#open`, dispatch via that action. Either way, **don't reinvent**.

D. **Confirm the mockup's "+ ANOTHER ENCOUNTER (DUPES CLAUSE)" surface re-uses the same `submitCatch` action** — it must, because the form fields are identical. Lock it: clicking `+ ANOTHER ENCOUNTER` toggles `.sheet-body` from group-list mode to form mode at the same location key (no hash change, no new endpoint).

E. **Does the existing `auto-scroll to first uncaught` behavior in `scrollToCurrentProgress()` already do the right thing post-redesign?** Yes — it targets `dataset.status === "uncaught"`. The new pulse-ring `.next` node is the first uncaught node, so the first-uncaught-target rule still works. Confirm.

F. **Verify `_pokemon_modal.html.erb` and `_mark_dead_modal.html.erb` partial paths and how they're currently rendered on the dashboard.** Render them with the same partial path on `/map`, ensuring no breakage of their existing dashboard wiring.

If any of A–F surface a contradiction with the brief, **ask in REVIEW-REQUEST.md before writing code.**

### Guardrails for the diff

- Diff scope: 2 modified files (view + CSS) + 1 modified file (timeline_controller.js extension) + 1 modified file (map_helper.rb extension) + 2 new test files + 1 modified test file (responsive_grids_test.rb extension). No more than ~7 files touched outside `handoff/`.
- **Zero changes** under `app/controllers/`, `app/models/`, `db/`, `app/services/`, `app/jobs/`, `config/`, `Gemfile*`. If you want one, escalate.
- Run `bin/rails test` and `bundle exec rubocop` clean before posting REVIEW-REQUEST.md. Brakeman should remain at the same 2 pre-existing weak-confidence warnings (Steps 18/19/20/21/22 baseline).
- Test count: 712 (Step 22) → 712 + new tests (target +12 to +18 net new). 0 failures, 0 errors.
- **No emojis in source files** unless mockup-locked (the mockup uses ☠ ● ○ ★ ↓ which are Unicode chars baked into the design — those are fine and required).

### Build order

1. **Files to verify pass (A–F).** Post early in REVIEW-REQUEST.md if anything's off.
2. **Helpers first** (`MapHelper#next_uncaught_route_key` + `current_segment_label` + `segment_progress`) + their unit tests. Lands the new locked rules before any view code calls them.
3. **CSS section** (`pixeldex.css` `/* ── R4 Map ── */` + breakpoint extensions + new 720px block). Mockup verbatim with `.map-r4` prefix.
4. **View rewrite** (`map/show.html.erb` full body) + render `_pokemon_modal.html.erb` + `_mark_dead_modal.html.erb` at the bottom.
5. **Stimulus controller extension** (`timeline_controller.js`): rename targets, replace overlay markup with sheet logic, add `jumpToNow`, add hash read/write, keep all other actions intact.
6. **Tests**: add the integration buckets to `map_redesign_test.rb` + extend `responsive_grids_test.rb` + write `map_helper_test.rb`. All must be FactoryBot-only.
7. **Lint + brakeman + full test run** before posting REVIEW-REQUEST.md.

### Done criteria

- All 21 test buckets above pass.
- Existing `/map` smoke test (if any) still green. Existing dashboard tests still green.
- 0 new design tokens. 0 migrations. 0 controller changes. 0 model changes.
- Visual fidelity: every annotated element from mockup Screens 1–4 maps to a class in the rendered output. Reviewer Richard will spot-check the diff against the mockup screen-by-screen.
- Read-only mode tested + visibly correct.
- The new feature (clickable map locations) lands the four cases: no-catch → form, single-catch → group card + dupes button, multi-catch → group cards stacked + dupes button, special-encounter cell → same routing.

---

*End of brief. If anything above is unclear, ask in REVIEW-REQUEST.md before writing code. The mockup wins where the brief is ambiguous.*

---

## Builder Plan — Bob, 2026-05-05

*Posted before writing any code. Awaiting Architect endorsement.*

### Files-to-verify pass (A–F outcomes)

**A. Segment label key in `progression.yml`.**
Confirmed: `progression.yml` has NO `segment["name"]` key — only `locations:` (Array of loc_keys) and `gym:` (gym_info key, e.g. `first_gym`). The brief's locked fallback applies: derive the divider label from `@gym_info[segment["gym"]]["location"]` → look up `@locations[that_loc]["name"]`. So for `gym: second_gym`, gym_info.yml says `location: eterna_city`; locations.yml says `name: "Eterna City"`. Uppercase to `"ETERNA CITY"`.
- **Edge case 1:** the final segment has `gym: null` (Victory Road → Elite Four). Use `"ELITE FOUR"` for that divider (matches mockup's `data-segment="…"` ellipsis spirit; "ELITE FOUR" is the canonical endpoint).
- **Edge case 2:** the brief says "between each pair of segments." That means N segments → N-1 dividers (after segments 1..N-1, before the next). The label on each divider is the **upcoming** segment's gym/endpoint name — i.e. divider after segment 1 reads "ETERNA" (segment 2's gym is `second_gym` = Eterna Gym), matching the mockup which puts `data-segment="ETERNA"` between Roark's gym and Floaroma. **This matches the mockup verbatim.** Locked.
- I'll use the gym leader's city name (e.g. "ETERNA", "VEILSTONE") not the gym's `name` field ("Eterna Gym") — the mockup uses "ETERNA" / "VEILSTONE" as bare city names. Helper: pull `@gym_info[next_seg["gym"]]["location"]` → strip `_city`/`_town` suffix → upcase. Cleaner than a separate name field.

**B. `_pokemon_modal.html.erb` dispatch payload.**
Confirmed: the dashboard's PC box cells (`_pc_box_content.html.erb:218-230`) fire `data-action="click->pixeldex#selectPokemon"` with `data-group-id`, `-nickname`, `-species`, `-location`, `-status`, `-types`, `-pokemon` (the last being `pixeldex_group_pokemon_json(group, current_user_id)`). The map sheet's EDIT button will mirror this exact payload — fire `pixeldex#selectPokemon` with the same `data-group-*` attributes. The button is constructed JS-side inside `_renderSheetGroup(group)` from the data already in `dataset.groups` JSON.
- **Caveat:** `data-group-pokemon` must include the `is_mine` boolean for `pixeldex#selectPokemon` to find the user's pokemon row. The existing `groups_json_for(groups)` helper does NOT include `is_mine` or `id` per pokemon — only `species`, `player`, `sprite`. **So the JS-built EDIT cannot use `groups_json_for` JSON directly to populate the modal**. Two options:
  - **(a) Extend `groups_json_for` to include `id`, `is_mine`, `level`, `ability`, `nature`, `sprite_url`** (mirroring `pixeldex_group_pokemon_json`'s shape) — but this changes the existing helper's public payload.
  - **(b) Add a parallel helper** `pixeldex_groups_json_for(groups, current_user_id)` that emits the pixeldex-shaped JSON, and use it on each node + special-cell as a SECOND data attribute (`data-pixeldex-pokemon` keyed per-group inside the JSON array). Or simpler: add a minimal `id`/`is_mine` to existing `groups_json_for` (additive, not breaking).
  - **My pick (b-lite, additive only):** extend `groups_json_for` to also emit `id`, `is_mine`, `level`, `ability`, `nature`, `types`, `sprite_url` per pokemon. Existing JS callers (the current `buildDetailsHtml`) only read `species` / `player` / `sprite`, so additive fields are harmless. The EDIT button is built from this enriched payload. **One helper, one shape, no controller call needed.**
- **Locked plan:** extend `groups_json_for` to add `id`, `is_mine`, `level`, `ability`, `nature`, `sprite_url`, `types` per pokemon, plus `id`, `location`, `species_for_user` (the current user's species, for `data-group-species`), `types_for_user`, `pokemon_json_for_modal` (the pixeldex-shaped JSON string) on each group. The EDIT button reads these from the rendered group card.
- **Question for Architect:** is "extend `groups_json_for` additively" OK, or do you prefer a parallel helper to keep the existing payload shape pure? **Default if no answer: extend additively (lowest churn, single source of truth).**

**C. `_mark_dead_modal.html.erb` wiring.**
Confirmed: it's wired to `dashboard` Stimulus controller (NOT the Step 20 `confirm-modal#open` shared partial). The trigger is `data-action="click->dashboard#openMarkDeadModal"` with `data-group-id` + `data-group-nickname` on the button. Map MARK DEAD button mirrors that exact dispatch. The `dashboard` controller targets `markDeadModal`, `markDeadNickname`, `markDeadGroupId` are all inside the partial — partial render at the bottom of `map/show.html.erb` makes them available.

**D. "+ ANOTHER ENCOUNTER (DUPES CLAUSE)" reuses `submitCatch`.**
Confirmed mockup-verbatim. The button toggles `.sheet-body` from group-list mode to form mode for the same `loc_key` (no hash change). The form is the existing multi-player Soul Link group form — same `submitCatch` action, same hidden `formLocationKey` carrying the already-selected key. Since the form submits and reloads the page (existing behavior), the new group simply appears as an additional card next time the route's sheet opens. **Locked.**

**E. `scrollToCurrentProgress()` post-redesign.**
Confirmed: it targets `dataset.status === "uncaught"`. The new `.next` node IS the first uncaught route node (helper rule walks segments in order, finds first uncaught route — same order as DOM). Existing behavior survives the redesign with zero changes. The existing scroll-restore (`sessionStorage.getItem("timeline-scroll")`) also works as-is.

**F. Modal partial paths + render call.**
Confirmed paths: `app/views/dashboard/_pokemon_modal.html.erb` + `app/views/dashboard/_mark_dead_modal.html.erb`. They're rendered on the dashboard at `app/views/dashboard/show.html.erb:58-59` via `<%= render "pokemon_modal" %>` (auto-resolves to `dashboard/_pokemon_modal`). On `/map` we'll render with the explicit path: `<%= render "dashboard/pokemon_modal" %>` and `<%= render "dashboard/mark_dead_modal" %>`. Same partial, no duplication, no breakage.
- **Caveat:** `_pokemon_modal.html.erb:46` references `@pokedex_species` — already loaded in `MapController#show:22`. ✓.
- **Caveat:** `_pokemon_modal.html.erb:75` references `PixeldexHelper::NATURES` — module constant, controller-agnostic. ✓.
- **Caveat:** `pixeldex` controller needs `abilities-data`, `evolutions-data`, `sprite-map`, `natures-data`, `pokemon-update-url`, `group-update-url`, `update-slots-url`, `csrf` values on the wrapper. The map wrapper currently has `data-controller="timeline"` only. **Locked decision:** the map's `.map-r4` wrapper will declare `data-controller="timeline dashboard pixeldex"` and add ALL the value attributes the dashboard's `<div data-controller="dashboard pixeldex">` wrapper carries (`groups-url`, `csrf`, `user-id`, `abilities-data`, `evolutions-data`, `sprite-map`, `natures-data`, `pokemon-update-url`, `group-update-url`, `update-slots-url`). This is what the brief implies in §13 ("re-use existing partials") and §22 ("render `_pokemon_modal.html.erb` + `_mark_dead_modal.html.erb` partials at the bottom"). Pixeldex's `connect()` runs `#initSortables()` (no-op when no team grids exist) + `#applyHashTab()` (reads `window.location.hash` looking for tab names; none of `team` / `gyms` / etc. match the new `#route=<key>` hash, so no-op). Safe to attach.

### Buckets (matches brief's Build Order)

**Bucket 1 — Helpers + unit tests.** First commit. (No view changes yet → tests run in isolation.)
- Add `MapHelper#next_uncaught_route_key(progression, locations, groups_by_location)` — walks segments in order, then `(segment["locations"] || [])`, returns first loc_key where `location_status` is `"uncaught"` AND `loc_data["type"] == "route"`. Returns `nil` if none.
- Add `MapHelper#current_segment_label(progression, gym_info, locations, next_uncaught_key)` — finds the segment containing `next_uncaught_key`, returns the bare-city label (e.g. `"VEILSTONE"`) derived from `gym_info[seg["gym"]]["location"]` → strip `_city`/`_town` → upcase. Returns `"FINAL STRETCH"` when `next_uncaught_key` is nil.
- Add `MapHelper#segment_progress(segment, locations, groups_by_location)` — returns `{ caught: N, total: M }`. Total = count of locations whose `loc_data["type"]` is route OR dungeon OR lake (i.e. catchable; excludes cities and towns and special). Caught = count where `location_status` is `"caught"` or `"dead"` (both consume the encounter slot).
- Add `MapHelper#segment_divider_label(progression, gym_info, locations, seg_idx)` — for the divider AFTER segment seg_idx, returns the upcoming segment's bare-city label (e.g. between seg_0 and seg_1 → look at seg_1's gym → `"ETERNA"`). Returns `"ELITE FOUR"` for the last divider when the gym is null.
- Extend `groups_json_for(groups, current_user_id)` — additively add `id`, `is_mine`, `level`, `ability`, `nature`, `sprite_url`, `types` per pokemon row + a top-level `id` per group. Update existing call sites (single helper) — `app/views/map/show.html.erb` is the only call site, and it'll be rewritten in bucket 3 anyway. The signature changes from `groups_json_for(groups)` to `groups_json_for(groups, current_user_id)` — second arg required.
- New helper `MapHelper#node_status_class(loc_data, status)` — pure-function returns `"caught"` / `"dead"` / `"uncaught"` / `"special"` (special only when `loc_data["type"] == "special"` AND status is uncaught — caught-special still shows as caught). Centralizes the class logic that the view will use.
- New helper `MapHelper#segment_open_by_default?(segment, next_uncaught_key)` — returns true if `segment["locations"]` includes `next_uncaught_key`.
- New `test/helpers/map_helper_test.rb` — 8+ unit tests covering all branches + bonus `location_status` / `primary_group` tests per brief §21.

**Bucket 2 — CSS section.** New `/* ── R4 Map ── */` block above the `── R2 PC Box ──` marker (line 1045). Mockup CSS verbatim with `.map-r4` prefix on every selector. Extend the existing `@media (max-width: 520px)` block (line 1564) with a `.map-r4 .special-grid { grid-template-columns: repeat(2, 1fr); }` rule. Add a NEW `@media (max-width: 720px)` block AFTER the 900px block but BEFORE the 520px block (clean cascade, larger to smaller) — this hides `.map-r4 .timeline-frame` and shows `.map-r4 .accordion-frame`, drops `.map-r4 .layout` to single column, drops `.map-r4 .sheet`'s `position: sticky`. **Zero new tokens.** Matches Step 22 pattern.

**Bucket 3 — View rewrite.** Full body rewrite of `app/views/map/show.html.erb` per mockup Screens 1, 2, 3, 4. Outer wrapper: `<div class="map-r4" data-controller="timeline dashboard pixeldex" …>`. Sections:
- `.map-head` (h2 + sub + badge strip)
- `.status-bar` (NEXT GYM + LEVEL CAP + CURRENT SEG + jump-btn)
- `.node-legend` (5 glyphs)
- `.layout` grid:
  - left column: `.timeline-frame` with edge fades + `.timeline-scroll` + `.timeline-track` (rendered server-side per segment with dividers); below it `.special-bar` with `.special-grid` of 4 cells.
  - right column: `<aside class="sheet">` with `.sheet-head` + `.sheet-body` containing `.empty-state` (default visible), `.sheet-form` (hidden, gated by `dashboard_read_only?`), and `.sheet-group-list` (hidden — populated by JS).
- `.accordion-frame` (mobile-only, hidden on desktop via CSS): one `<details class="accordion-segment">` per segment, with `open` attribute on the segment containing the next-uncaught route. Each `.acc-rows` lists `.acc-row` items per location with the same `data-action="click->timeline#selectLocation"` chain.
- At the bottom: `<%= render "dashboard/pokemon_modal" %>` + `<%= render "dashboard/mark_dead_modal" %>`.
- Old slide-out + backdrop at lines 209-274 — **removed**.

**Bucket 4 — Stimulus controller extension.** `timeline_controller.js`:
- Targets renamed: `panel` → `sheet`, `panelTitle` → `sheetTitle`, `panelBody` → `sheetBody`, `panelForm` → `sheetForm`. Drop `backdrop` from targets.
- Add new targets: `emptyState` (default-visible block in sheet), `groupList` (the JS-populated group cards container), `jumpBtn`, `accordionSegment`.
- `connect()`: parse `window.location.hash` for `#route=<key>`, find matching `locationNode`, call `selectLocation` with synthetic event. Hide `jumpBtn` if no `.next` node exists. Existing `scrollToCurrentProgress()` keeps running.
- Rewrite `openPanel`/`closePanel` for the in-flow sheet (no `translateX`, no body lock, no backdrop). `closePanel` clears the hash via `history.replaceState`.
- New action `jumpToNow(event)` — finds `.node.next`, `scrollIntoView({ behavior: "smooth", inline: "center" })`. No-op if absent.
- New internal method `_renderSheetCatchForm(key, name)` — sets `sheetTitle` text, hides `emptyState` + `groupList`, shows `sheetForm`, sets `formLocationKey.value = key`, focuses nickname input. (Called when status is `"uncaught"`.)
- New internal method `_renderSheetGroupList(key, name, groups)` — sets title, hides `emptyState` + `sheetForm`, shows `groupList` populated with one `.group-card` per group + the dashed `+ ANOTHER ENCOUNTER` button (only if not read-only). Each card has EDIT + MARK DEAD buttons wired to `pixeldex#selectPokemon` + `dashboard#openMarkDeadModal` with the appropriate `data-group-*` attributes. Read-only mode is detected via the absence of `sheetForm` target (gate at view level).
- New action `showCatchFormForCurrent(event)` — fired by the `+ ANOTHER ENCOUNTER` button; toggles `sheetForm` visible, hides `groupList`, leaves `formLocationKey` as-is.
- `selectLocation`: write `location.hash = "#route=" + key` after rendering. Branch on `groups.length`: 0 → catch form; 1 or more → group list (dupes button rendered automatically).
- Existing actions `submitCatch`, `toggleGym`, `filterSpecies`, `selectSpecies`, `closeAllDropdowns`, `handleKeydown`, `scrollToCurrentProgress` — all preserved verbatim. `scrollContainerTarget` still works for the sessionStorage scroll-restore. `handleKeydown` — Escape calls `closePanel` (now: clear hash + show empty state).
- Highlight logic: drop the inline `ring-*` Tailwind class names; add a `.selected` class on the `.glyph` div instead, styled by `.map-r4 .node.selected .glyph` in CSS (amber outline).

**Bucket 5 — Tests.**
- Extend `responsive_grids_test.rb` with the 4 brief assertions (#14-17).
- New `test/integration/map_redesign_test.rb` per brief §1-13 (Step 22 template). 12+ tests.
- New `test/helpers/map_helper_test.rb` with helper-level tests (brief §18-21 plus the new helpers I'm adding). All FactoryBot.

**Bucket 6 — Lint + brakeman + full test run.** Then post REVIEW-REQUEST.md.

### Surfaced contradictions / ambiguities

1. **`groups_json_for` payload shape.** Brief §B (Files to verify) asks me to confirm the dispatch payload. Resolution: extend additively (see (b-lite) above). Architect: confirm or override.

2. **Segment divider label source.** Brief §6 says "if YAML has no per-segment label, fall back to the next-gym name (`@gym_info[segment["gym"]]["location_name"]` uppercase)". `gym_info.yml` has `location` (the loc_key, e.g. `eterna_city`), NOT `location_name`. The actual location name lives in `locations.yml[loc_key]["name"]` (`"Eterna City"`). Mockup uses bare `"ETERNA"` / `"VEILSTONE"` (city without the `_city` suffix). I'm picking the bare-city pattern (strip `_city`/`_town`) to match the mockup verbatim. Architect: lock this or pick the gym `name` field (e.g. `"ETERNA GYM"`)?

3. **Last-divider label.** The final segment in `progression.yml` has `gym: null` (Victory Road). I'm planning to emit `"ELITE FOUR"` on the divider before that segment (or skip it — between segment N-1 (`eighth_gym`) and the final null-gym segment). The mockup ends with `data-segment="…"` (ellipsis) for the final divider. I'll match the mockup: emit `data-segment="…"` literally for the divider before the null-gym segment, and put a final Elite Four endpoint node at the very end (mirroring today's existing markup). Architect: confirm "…" is right, or you want "ELITE FOUR" textually?

4. **`next-uncaught-route` rule and dungeons/lakes.** Brief §4 locks: "find the first location whose status is uncaught AND `loc_data["type"]` is `"route"`". So Lake Verity (type: `lake`), Eterna Forest (type: `dungeon`), Oreburgh Mine (type: `dungeon`) etc. are SKIPPED for the NOW pin. That's locked, but it means a player who's caught all routes but no dungeons would see no NOW pin and an empty `JUMP TO NOW`. That's the intended late-game behavior per brief §4 ("If no uncaught route exists … no `.next` class anywhere; that's fine"). **No question, just flagging.**

5. **`segment_progress` denominator.** Brief §19 says "5/6 ✓" so the total counts catchable locations. Cities (`oreburgh_city`) and towns (`floaroma_town`) are catchable in real Pokémon (tall grass nearby), but their `type` in the YAML is `city`/`town`. Looking at `locations.yml`, MOST cities/towns have NO `tall_grass` key (Sandgem, Twinleaf, Floaroma, Solaceon, Celestic — none have tall grass). Eterna City and Pastoria City don't have tall grass. So the segment sum is NOT 1:1 with the segment locations Array. **My rule:** total = locations where `type` is `route|dungeon|lake|special` (excludes city/town). Caught = those locations whose `groups_by_location` has a caught/dead group. Architect: lock this or pick "all locations in segment" (matches segment Array length)?

### Architect questions (locked)

- **Q1 (above):** extend `groups_json_for` additively, or parallel helper? **Default: additive.**
- **Q2 (above):** segment divider label — bare city ("ETERNA") or gym name ("ETERNA GYM")? **Default: bare city to match mockup.**
- **Q3 (above):** final divider before the null-gym segment — `"…"` (mockup-verbatim) or `"ELITE FOUR"`? **Default: `"…"` to match mockup.**
- **Q4 (above):** segment_progress denominator — catchable types only (route/dungeon/lake/special) or all locations in the array? **Default: catchable types only.**
- **Q5 (read-only mode JS detection):** the JS-rendered `_renderSheetGroupList` decides whether to render EDIT/MARK DEAD/dupes button. View renders `sheetForm` only when `!dashboard_read_only?`. JS uses `this.hasSheetFormTarget` as the gate (no need for a separate value). **Default: this.**
- **Q6 (Stimulus value contract for sheet status):** the JS needs to read `data-status="<%= dashboard_read_only?(@run) %>"` somewhere. Cleanest: a new `static values = { ... readOnly: Boolean }` on the controller, set on the wrapper. **Default: add `readOnly` value.**

### Diff scope estimate

- 1 modified view (`map/show.html.erb`, full body rewrite ~250 lines)
- 1 modified CSS (`pixeldex.css`, +~330 lines new R4 section + ~10 lines extending media blocks + new 720px block ~12 lines)
- 1 modified Stimulus controller (`timeline_controller.js`, +~120 lines for sheet/jumpToNow/hash, ~40 lines edited for target rename + openPanel/closePanel rewrite)
- 1 modified helper (`map_helper.rb`, +~80 lines for the 5 new helpers + extended `groups_json_for`)
- 1 modified test (`responsive_grids_test.rb`, +~50 lines, 4 new tests)
- 2 new test files (`map_redesign_test.rb` ~250 lines + `map_helper_test.rb` ~150 lines)

Total: 5 modified + 2 new files (within the brief's "≤7 files outside handoff/" budget).

### What I won't do (sanity check)

- No controller changes, no model changes, no migrations, no new YAML, no new design tokens, no new gem deps.
- No conversion of existing `<datalist>` → combobox (it's already a combobox).
- No mobile bottom-sheet snap behavior.
- No click-to-copy / share-route URL.
- Not touching `_map_content.html.erb` (dashboard MAP tab).
- Not touching the Discord notifier.

**Awaiting Architect endorsement before writing code.**

---

## Architect endorsement — Ava, 2026-05-05

Plan endorsed. The buckets, scope estimate, and Files-to-Verify outcomes (A–F) are correct. Build per the plan, with the following question-by-question answers locked in:

**Q1 — `groups_json_for` extension:** **Additive — yes.** Extend `groups_json_for(groups, current_user_id)` to include the pixeldex-shaped per-pokemon fields (`id`, `is_mine`, `level`, `ability`, `nature`, `sprite_url`, `types`) plus a top-level group `id`. Single source of truth. The signature change (added `current_user_id` arg) is fine — only call site is the map view, which is being rewritten anyway. Lock the new shape in the helper docstring.

**Q2 — Segment divider label:** **Bare city ("ETERNA") — yes.** Mockup wins. Strip `_city` / `_town` from the loc_key derived from `gym_info[seg["gym"]]["location"]`, upcase. e.g. `eterna_city` → `"ETERNA"`, `veilstone_city` → `"VEILSTONE"`, `sunyshore_city` → `"SUNYSHORE"`.

**Q3 — Final divider label:** **`"ELITE FOUR"` — overrides your default.** The mockup's `data-segment="…"` was a truncation artifact (mockup only renders 3 segments, not the full 9). For the real implementation, the divider before the null-gym segment names the destination. Use `"ELITE FOUR"` (or derive from `progression["endpoint"]&.split(" / ")&.first&.upcase` — both work; pick whichever is cleaner). The existing Elite Four endpoint node at the very end of the track is preserved as-is.

**Q4 — `segment_progress` denominator:** **Catchable types only — yes.** Total counts locations whose `loc_data["type"]` is `route`, `dungeon`, `lake`, or `special`. Excludes `city` and `town`. Caught counts those with status `caught` OR `dead` (both consume the encounter slot). Matches the audit's intent and the mockup's "5/6 ✓" math.

**Q5 — Read-only mode JS detection via `hasSheetFormTarget`:** **Yes.** Single gate. The view conditionally renders `sheetForm` only when `!dashboard_read_only?(@run)`; absent target means read-only mode → JS skips rendering EDIT, MARK DEAD, and `+ ANOTHER ENCOUNTER` in the group cards. Same pattern as the existing dashboard read-only gates.

**Q6 — `readOnly` Stimulus value:** **Skip it — overrides your default.** `hasSheetFormTarget` (Q5) is sufficient as the single source of truth. Adding a parallel `readOnlyValue` is duplication. One gate, one place to forget to update.

### Additional locked items (not questions, but addressing concerns flagged in your plan)

- **`data-controller="timeline dashboard pixeldex"` on the wrapper is approved.** Before writing code, do a quick `connect()`-side-effects pass on `dashboard_controller.js` AND `pixeldex_controller.js` to confirm both are benign on `/map`: no DOM-required targets that would error, no `applyHashTab` collision with `#route=<key>` (your §F note covers pixeldex; same for dashboard). If `dashboard#connect` does anything that would error without a dashboard's `data-dashboard-*` value attrs, surface it BEFORE adding the controllers — we may need to set `data-dashboard-*` value attrs on the wrapper, or the controller may need to gracefully no-op when its targets aren't present. The dashboard partial that the modals depend on has its own `data-controller`, so the modal partials themselves carry the controller attachment for the modal's internal targets — verify whether the wrapper itself needs `dashboard` / `pixeldex` declared, or only the modal partials' inner wrappers do. **Pick the minimal attachment that makes the modals functional.**

- **`.selected` class on `.glyph` instead of Tailwind `ring-*`:** approved, cleaner. CSS owns the visual.

- **JS file-rename or new file:** keep extending `timeline_controller.js` — the brief is explicit. Don't fork a new controller.

- **Test count target:** brief said +12 to +18; your plan implies more (8+ helper tests, 12+ integration tests, 4 responsive tests = ~24+). That's fine — overshoot is welcome where each test guards a distinct contract. Avoid duplicate assertions across files.

- **Mockup-verbatim:** I see your CSS section is ~330 lines. The mockup's CSS is ~340 lines including the body/page/banner/legend/annotation chrome that we DON'T need (those are mockup-page styling, not the app's). Strip the mockup-only chrome (`.page`, `.page-banner`, `.legend`, `.section-anchor`, `.annotation`, `.phone`, `.phone-bezel`) and ship only the actual component styles. Should land closer to ~250-280 lines of new CSS, namespaced.

- **Existing `gb-page-title` / `gb-page-subtitle` / `gb-card` / `gb-card-dark` usage in the current `map/show.html.erb`:** drop them in the rewrite. The `.map-r4 .map-head` markup replaces them with mockup-verbatim styles. Don't try to reuse the legacy classes for the new sections.

- **Modal partial paths:** confirmed `<%= render "dashboard/pokemon_modal" %>` and `<%= render "dashboard/mark_dead_modal" %>` is the right call — explicit dashboard/ prefix because the partials live under `app/views/dashboard/`.

### Build order overrides

Build order locked exactly as your bucket plan (1→6). Bucket 1 (helpers + tests) lands first as a self-contained commit-able chunk. Don't bundle bucket 1 with the view rewrite — it'll be useful even if the view rewrite needs iteration.

Once Richard signs off, **post REVIEW-REQUEST.md** following the standard shape (file list with line ranges + decisions made + open questions + `Ready for Review: YES`). Don't commit; deploy gate is mine.

**Greenlight. Start with Bucket 1.**

---

