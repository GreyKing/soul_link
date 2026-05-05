# Architect Brief
*Written by Architect. Read by Builder and Reviewer.*
*Overwrite this file each step — it is not a log, it is the current active brief.*

> Locked instructions for the current step. Bob, this is your only source of truth.
> If anything below contradicts the mockup HTML, **the mockup wins**. Tell Arch.

---

## Step 22 — R2 PC Box redesign (Phase 2 R2 of the 2026-05-04 UI/UX audit)

### Reference files (read in this order, then stop)

1. `handoff/2026-05-04-ui-audit-mockup-pc-box.html` — **the locked design.** 4 screens (default / filter applied / empty tray / mobile). Mockup wins on every visual + interaction detail.
2. `handoff/2026-05-04-ui-audit.md` § 4 R2 — narrative rationale (one paragraph, ~6 lines).
3. `app/views/dashboard/_pc_box_content.html.erb` — the file you are rewriting. Read end-to-end before touching.
4. `app/views/dashboard/_catch_modal.html.erb` — read-only. Confirm the input `name=` attributes for species/location/level (your `prefillCatch` Stimulus action depends on them).
5. `app/javascript/controllers/dashboard_controller.js` — read-only. Confirm `openCatchModal` action exists and is dispatchable via `data-action="click->dashboard#openCatchModal"`.
6. `app/javascript/controllers/pixeldex_controller.js` — read-only. Confirm `selectPokemon` action signature and which `data-group-*` attributes the cells supply today (so the new merged grid carries them through unchanged).
7. `app/assets/stylesheets/pixeldex.css` — locate the existing `@media (max-width: 520px)` and `@media (max-width: 900px)` blocks. You'll **extend** these, not replace.
8. `app/controllers/dashboard_controller.rb:54-72` — confirm the `@on_team_groups / @storage_groups / @fallen_groups / @auto_detected_catches` shape. **No change to this controller.**

Do NOT load: domain-models docs, the bot, the auth concern, any service file beyond what's grep-required. The brief has the data shapes and column names you need.

### Context

Phase 2 R3 (Save Slots) shipped at `3c001ed` / merged to main at `9cd2009`. R2 is next in the audit's locked ship order: R3 → **R2** → R4 → R1. After R2 ships, the session ends — R4 gets its own session.

**Surface in scope:** the dashboard PC BOX **tab** (`_pc_box_content.html.erb`). The sidebar partial (`_pc_box_panel.html.erb`, 5-col compact) is **out of scope** — that's the cross-cutting-6 sidebar/main duplication, deferred to a separate IA decision.

**Data model is unchanged.** All needed columns already exist on `soul_link_pokemon`: `pid`, `acquired_via`, `caught_off_feed`, `trade_in`, `nature`, `ivs`, `evs`, `moves`. Controller already exposes `@on_team_groups / @storage_groups / @fallen_groups / @auto_detected_catches / @type_analysis`. **No migration. No controller change. No new endpoint.**

### Architect decisions (locked — do not re-litigate)

1. **LOG CATCH / EDIT route into the existing `+ NEW CATCH` modal pre-filled. SKIP is a client-side dismiss only — does NOT persist.** The mockup's per-row primary action is a click affordance, not a new round-trip. The audit's "small migration" hand-wave is **not in scope**: the prompt is explicit that backend pipelines (Steps 17/18/19) are not changing. Wiring spec:
   - **LOG CATCH / LOG AGAIN / EDIT** → `data-action="click->review-tray#prefillCatch click->dashboard#openCatchModal"`. The new `prefillCatch` action populates the modal's species / location / level inputs from `data-*` params on the button, then the existing `dashboard#openCatchModal` opens the modal exactly as today.
   - **SKIP** → toggles a `.dismissed` class on the row (opacity 0.4 per mockup CSS), and decrements the tray's count pill. Stays dismissed for the lifetime of the page; reload resurfaces it. Acknowledged v1 limitation — log as **KG-35**.

2. **No backend changes — none.** No new column, no new endpoint, no migration, no model method. If you find yourself reaching for a controller change, **escalate**.

3. **CSS namespace under `.pc-box-r2` wrapper.** The mockup's `.box-grid / .box-cell / .sprite` selectors collide with existing pixeldex.css rules (`.box-grid` is used by the sidebar partial; `.box-cell` is referenced from multiple places). Wrap the entire new view in `<div class="pc-box-r2">…</div>` and **prefix every new CSS rule with `.pc-box-r2 …`**. Mockup CSS transcribed verbatim except: (a) every selector gains the `.pc-box-r2` ancestor; (b) any kebab-case adjustment needed for project convention; (c) the `.first / .dismissed / .team / .dead` modifier classes stay as the mockup wrote them.

4. **Mobile breakpoint = 520px (Step 20 contract), not the mockup's 600px prose.** The mockup's phone shell is 360px wide — well below 520 — so any sub-520 reflow rule applies. Inside the **existing** `@media (max-width: 520px)` block:
   - `.pc-box-r2 .box-grid { grid-template-columns: repeat(3, 1fr); gap: 6px; }`
   - `.pc-box-r2 .box-cell { padding: 6px; }`
   - `.pc-box-r2 .review-row { grid-template-columns: 36px 1fr; padding: 8px 10px; }`
   - `.pc-box-r2 .review-row .sprite { width: 36px; height: 36px; }`
   - `.pc-box-r2 .review-row .actions { grid-column: 1 / -1; flex-direction: row; gap: 6px; margin-top: 6px; }`
   - `.pc-box-r2 .review-row .actions button { flex: 1; min-width: 0; }`
   - `.pc-box-r2 .badge-legend { grid-template-columns: 1fr; }`

5. **Type-coverage rail layout uses a single grid that reflows.** Declare `.pc-box-r2 .box-layout` outside any media block as `grid-template-columns: minmax(0, 1fr) 280px;` (mockup-verbatim — desktop case). In the **existing** `@media (max-width: 900px)` block, add: `.pc-box-r2 .box-layout { grid-template-columns: 1fr; }` so the rail stacks below on narrower viewports. **No new design tokens.** Existing tokens (`--d0/--d1/--d2`, `--l1/--l2`, `--white`, `--amber`, `--crimson`, `--green-glow`, `--border`, `--border-thin`) cover everything. If you find a hex literal in the mockup CSS that doesn't map to an existing token, prefer the closest existing token over adding a new one. Inline literals are acceptable for one-off shadow / overlay values that don't cleanly token-map (matching Step 21's mockup-verbatim precedent for `rgba(...)` overlays).

6. **One unified grid in `[on_team, storage, fallen]` order** with a corner `group-marker` glyph (`★` team / `▣` storage / `☠` fallen). Each cell carries `data-pc-box-filter-target="cell"` and `data-status="team"|"storage"|"fallen"` so the new Stimulus controller can hide/show by attribute. **The three existing controller arrays stay** (`@on_team_groups`, `@storage_groups`, `@fallen_groups`) — the partial just iterates them in sequence into one grid, no controller change.

7. **Filter chips are status-only + a free-text search.** Chips: `ALL · N`, `ON TEAM · N`, `STORAGE · N`, `FALLEN · N`. The Project Owner's prompt mentioned "route / status / player" filters in the gist — that's prose drift; the mockup itself only shows status + search. **Mockup wins.** No route chip. No player chip. Logging not-in-mockup filter ideas as **KG-36**.

8. **URL hash preserves filter state.** `#team / #storage / #fallen / #all`. Stimulus controller reads `location.hash` on `connect()` and applies; chip click writes `location.hash`. Empty hash = ALL.

9. **Recommended-action highlight is computed view-side from the row's badges.** New helper `recommended_review_action(p)` returns `:log` or `:skip`:
   - `acquired_via == "event_gift"` → `:skip`
   - `trade_in == true` → `:skip`
   - else → `:log`
   The view applies `class="primary"` to the matching button (LOG for `:log`, SKIP for `:skip`). The first-encounter visual highlight (`.review-row.first` border treatment, green-glow 3px border) keys off the existing `first_ids_by_location` calc, independent of the helper.

10. **Empty review tray = the dashed-border ✓ bar from Screen 3, NOT a hidden empty `<div>`.** When `@auto_detected_catches.empty?`, render a `.empty-tray-bar` block verbatim from the mockup (dashed border, green ✓ glyph, copy: `No new parsed catches to review. New saves will land here for confirmation.`). Panel-head right side switches from `N TOTAL · K NEW PARSED` (when catches present) to `N TOTAL · ALL CAUGHT-UP` (when empty).

11. **Click affordance on cells stays as today** — `data-action="click->pixeldex#selectPokemon"` opens the existing pokemon modal. The mockup's `cursor: pointer` + `:hover` border-color shift + 2px lift is purely CSS in the new R2 section. **Don't touch `pixeldex_controller.js`** or the pokemon modal partial.

12. **No mark-dead surface on the new tab.** The mockup has no inline mark-dead button. The existing `_mark_dead_modal.html.erb` flow stays untouched. Any prose in the prompt mentioning "mark dead" was drift — not in the mockup, not in scope.

13. **Read-only mode: hide the `+ NEW CATCH` button AND the per-row LOG / EDIT actions.** SKIP can stay (it's client-only and dismissable, no backend impact). Existing helper `dashboard_read_only?(@run)` already governs the NEW CATCH button — extend the same gate to the review-row primary actions.

### What to build

#### A. View — `app/views/dashboard/_pc_box_content.html.erb` (full body rewrite)

Wrap everything in `<div class="pc-box-r2" data-controller="pc-box-filter review-tray">…</div>`.

Computed locals at the top of the partial:
```erb
<%
  total = @on_team_groups.size + @storage_groups.size + @fallen_groups.size
  auto_catches = (@auto_detected_catches || []).reject { |p| p.id.nil? }
  first_ids_by_location = auto_catches
    .group_by { |p| p.location.to_s }
    .each_with_object({}) { |(loc, list), out| out[loc] = list.min_by { |p| p.caught_at || Time.at(0) }.id }
  read_only = dashboard_read_only?(@run)
%>
```

Hard requirements per region:

- **Panel head** uses the existing `panel-header` class (don't rebuild that chrome). Right-side: `M TOTAL · K NEW PARSED` when `auto_catches.any?`; `N TOTAL · ALL CAUGHT-UP` when empty. NEW CATCH button gated by `read_only`.

- **Review tray** (`.review-tray`) — render only when `auto_catches.any?`:
  - Header: `<h3>REVIEW PARSED CATCHES</h3>` + count pill `<span class="count">K NEW</span>` (target: `data-review-tray-target="count"`).
  - Badge legend (`.badge-legend`, 2-col grid) — exactly the four rows in the mockup, copied verbatim:
    - `1ST` (green) — first encounter on a route — log it
    - `TRADE-IN` (amber) — obtained via trade — usually skip
    - `EVENT` (filled l1) — mystery gift / event — not a real encounter
    - `OFF-FEED` (l1 outline) — from PC box, not active party
  - One `.review-row` per auto-catch. Add `.first` class when the row IS a first-encounter (`first_ids_by_location[p.location.to_s] == p.id`) AND `recommended_review_action(p) == :log`. Each row carries:
    - `data-review-tray-target="row"`, `data-pid="<%= p.pid %>"`
    - 56×56 `.sprite` div containing `pokemon_sprite_tag(p.species, size: 56)` (or fallback "SPR" if helper doesn't accept size 56 — check first; reuse 40 if needed and let the CSS center it)
    - `.meta .name` with species + the same badge pills the existing partial uses (1ST / TRADE-IN / EVENT / OFF-FEED — kept consistent with Step 17/18 logic)
    - `.meta .loc` — `<%= p.location %><% if p.level %> · Lv <%= p.level %><% end %>`
    - `.meta .stats` — Step 18 fields rendered inline if present: `NATURE · IVS h/a/d/sp/sa/sd · MOVE-NAMES (first 4 joined with ·)`. Use existing `format_move_name(id)` for moves. **Don't render the `<details>STATS</details>` block** — the new tray surfaces stats in one line.
    - `.actions` column: three buttons — LOG CATCH / EDIT / SKIP (text "LOG AGAIN" instead of "LOG CATCH" when `acquired_via == "event_gift"`, per Screen 1 row 3). Recommended action gets `class="primary"`. Each LOG/EDIT button carries:
      - `data-action="click->review-tray#prefillCatch click->dashboard#openCatchModal"`
      - `data-review-tray-prefill-species-param="<%= p.species %>"`
      - `data-review-tray-prefill-location-param="<%= p.location %>"`
      - `data-review-tray-prefill-level-param="<%= p.level %>"`
      - SKIP: `data-action="click->review-tray#dismiss"` (no params needed; reads the parent row).
    - LOG/EDIT hidden when `read_only`. SKIP stays.

- **Empty review-tray bar** — render only when `auto_catches.empty?`:
  ```html
  <div class="empty-tray-bar">
    <span class="check">✓</span>
    No new parsed catches to review. New saves will land here for confirmation.
  </div>
  ```

- **Filter bar** (`.filter-bar`):
  - Four `<button class="filter-chip" type="button">` elements (use `<button>`, not `<span>` — for keyboard accessibility): ALL / ON TEAM / STORAGE / FALLEN with `· N` counts. Each carries `data-action="click->pc-box-filter#applyFilter"`, `data-pc-box-filter-status-param="all|team|storage|fallen"`, `data-pc-box-filter-target="chip"`, `data-status="all|team|storage|fallen"`.
  - The `ALL` chip starts with `class="filter-chip active"`. Stimulus controller toggles `.active` class when filter changes.
  - Search input on the right: `<input type="search" class="filter-search-input" aria-label="Search nicknames or species" placeholder="Search nickname or species…" data-action="input->pc-box-filter#applySearch" data-pc-box-filter-target="searchInput">` wrapped in `<div class="filter-search">`.

- **Box layout** (`.box-layout`):
  - Left: `.box-grid` containing **all groups merged in `[on_team, storage, fallen]` order**. Each cell:
    ```erb
    <div class="box-cell <%= 'team' if status == 'team' %><%= 'dead' if status == 'fallen' %>"
         data-pc-box-filter-target="cell"
         data-status="<%= status %>"
         data-action="click->pixeldex#selectPokemon"
         data-group-id="<%= group.id %>"
         data-group-nickname="<%= group.nickname %>"
         data-group-species="<%= my_pokemon&.species || '' %>"
         data-group-location="<%= group.location %>"
         data-group-status="<%= group.dead? ? 'dead' : 'caught' %>"
         data-group-types="<%= my_pokemon&.species.present? ? SoulLink::GameState.types_for(my_pokemon.species).join(',') : '' %>"
         data-group-pokemon="<%= pixeldex_group_pokemon_json(group, current_user_id) %>">
      <span class="group-marker" aria-hidden="true"><%= status == 'team' ? '★' : status == 'storage' ? '▣' : '☠' %></span>
      <div class="nick"><%= group.nickname.upcase %></div>
      <div class="sprite"><%= pokemon_sprite_tag(my_pokemon.species, size: 40) if my_pokemon&.species.present? %></div>
      <div class="loc"><%= group.location %></div>
    </div>
    ```
    (The exact iteration shape is up to you — this is illustrative; match the existing partial's `data-group-*` set so the pokemon modal opens correctly.)
  - Right: `<aside class="type-coverage" data-pc-box-filter-target="rail">` per mockup — three sub-sections: COVERED (filled green pills), GAPS (dashed crimson pills), SHARED WEAKNESSES (filled crimson with `× N`). Use the existing `pixeldex_type_coverage(@type_analysis)` helper for covered/gaps; iterate `@type_analysis[:shared_weaknesses]` (already shaped as `[{type:, count:}, …]`) for the weaknesses section.
  - When the active filter ≠ `team` AND ≠ `all`, the rail dims (Stimulus toggles `.dimmed` on the rail, CSS sets `opacity: 0.6`) and shows the explainer `computed against your 6-slot team — switch to ON TEAM to focus`. The explainer block is inside the rail; CSS hides it by default and shows it when `.dimmed`.

#### B. CSS — `app/assets/stylesheets/pixeldex.css`

Add a new section block, placed **above** the existing `/* ── R3 Save Slots ── */` section so each redesign reads chronologically. Header comment: `/* ── R2 PC Box ── */`.

Selectors to declare, mockup-verbatim **except** all wrapped under `.pc-box-r2` parent selector:
- `.pc-box-r2` (block-level reset; no own visual treatment beyond `display: block` if needed)
- `.pc-box-r2 .review-tray`, `.review-tray-head`, `.review-tray-head h3`, `.review-tray-head .count`
- `.pc-box-r2 .badge-legend`, `.badge-legend .row`, `.badge-legend .badge`, `.badge.first`, `.badge.trade`, `.badge.event`, `.badge.offfeed`
- `.pc-box-r2 .review-row`, `.review-row.first`, `.review-row.dismissed`, `.review-row .sprite`, `.review-row .meta .name`, `.review-row .meta .loc`, `.review-row .meta .stats`, `.review-row .meta .stats span`, `.review-row .actions`, `.review-row .actions button`, `.review-row .actions button.primary`, `.review-row .actions button:hover`
- `.pc-box-r2 .empty-tray-bar`, `.empty-tray-bar .check` (the Screen 3 dashed bar — give it a meaningful class name; mockup left it inline-styled)
- `.pc-box-r2 .filter-bar`, `.filter-chip`, `.filter-chip.active`, `.filter-chip:hover:not(.active)`, `.filter-search`, `.filter-search input`, `.filter-search input::placeholder`
- `.pc-box-r2 .box-layout`, `.box-grid`, `.box-cell`, `.box-cell:hover`, `.box-cell.team`, `.box-cell.dead`, `.box-cell .nick`, `.box-cell .sprite`, `.box-cell .loc`, `.box-cell .group-marker`, `.box-cell.dead .group-marker`, `.box-cell.team .group-marker`
- `.pc-box-r2 .type-coverage`, `.type-coverage h3`, `.type-coverage .sub`, `.type-coverage.dimmed`, `.type-coverage.dimmed .dimmed-explainer` (display: block when dimmed; display: none otherwise)
- `.pc-box-r2 .type-pill`, `.type-pill.covered`, `.type-pill.gap`, `.type-pill.weak`

**Media queries** — extend existing blocks; do NOT open new ones:
- In the existing `@media (max-width: 900px)` block, add: `.pc-box-r2 .box-layout { grid-template-columns: 1fr; }`
- In the existing `@media (max-width: 520px)` block, add the rules listed under decision #4.

#### C. Stimulus — two new controllers

**`app/javascript/controllers/pc_box_filter_controller.js`** (new, ~80 lines):
- Targets: `chip`, `cell`, `searchInput`, `rail`, `count` (panel-head count display — for Screen 2's `K OF N SHOWN` update).
- `connect()` — read `location.hash`, apply matching filter (default `all`).
- `applyFilter({ params: { status } })` — set `this.status`, write `location.hash = "#" + status`, then `_render()`.
- `applySearch(event)` — debounce 150ms, set `this.search = event.target.value.toLowerCase().trim()`, call `_render()`.
- `_render()` — for each cell:
  - Hide if `this.status !== 'all'` AND `cell.dataset.status !== this.status`
  - Hide if `this.search.length > 0` AND neither `data-group-nickname` nor `data-group-species` (lowercased) includes `this.search`
  - Else show.
  - Toggle chip `.active` class. Toggle rail `.dimmed` class when `this.status !== 'team' && this.status !== 'all'`. Update `count` target text.

**`app/javascript/controllers/review_tray_controller.js`** (new, ~50 lines):
- Targets: `row`, `count` (the "K NEW" pill).
- `prefillCatch({ params: { species, location, level } })` — find the catch modal form and populate inputs by `name=`. Look up the modal via `document.getElementById('catch-modal')` if it has that id; otherwise via `[data-controller~="dashboard"]` ancestor + `[name=species]` etc. Verify the input names against `_catch_modal.html.erb` before writing (this is an `Files to verify` step). Doesn't open the modal — the second `data-action` handles that.
- `dismiss(event)` — find the closest `[data-review-tray-target="row"]` ancestor of the click target, add `.dismissed` class, decrement `this.countTarget`'s text by parsing the number.
- Keep the controllers decoupled — both attached to the same `.pc-box-r2` wrapper via space-separated `data-controller="pc-box-filter review-tray"`.

**Don't touch `pixeldex_controller.js`** — the cell click for opening the pokemon modal flows through it as today via the merged-grid cells' data-action.

#### D. Helper — `recommended_review_action(p)`

Place in `app/helpers/pixeldex_helper.rb` if that file exists; else `app/helpers/dashboard_helper.rb`. Grep first; pick the closest existing surface — the helper file that already houses `pixeldex_type_coverage` or `format_move_name` is the right home. Definition:

```ruby
def recommended_review_action(pokemon)
  return :skip if pokemon.acquired_via == "event_gift"
  return :skip if pokemon.trade_in
  :log
end
```

#### E. Tests

All tests under `test/integration/` (markup-assertion pattern, matching `confirm_modal_flow_test.rb` and `responsive_grids_test.rb`). System tests are not set up in this repo — don't introduce them.

**`test/integration/pc_box_redesign_test.rb`** (new):
- Setup: factory a run with the test user (`GREY = 153665622641737728` per the precedent test), one team_group on the team, one storage group, one fallen group, and two `@auto_detected_catches` (one first-encounter; one trade_in).
- Test: GET `/dashboard` returns success and response body contains:
  - The `class="pc-box-r2"` wrapper
  - `data-controller=` containing both `pc-box-filter` and `review-tray`
  - `class="review-tray"` and `<h3>REVIEW PARSED CATCHES</h3>`
  - `class="badge-legend"` with the four legend rows for `1ST`, `TRADE-IN`, `EVENT`, `OFF-FEED`
  - One `.review-row` per auto-catch, each with three `<button>` children
  - The first-encounter row carries `class="review-row first"` AND its LOG button class includes `primary`
  - The trade-in row's SKIP button class includes `primary`
  - The four filter chips with the correct counts (`ALL · 3`, `ON TEAM · 1`, `STORAGE · 1`, `FALLEN · 1`)
  - The unified grid contains exactly 3 cells, with `data-status` attributes covering `team`, `storage`, `fallen` (one each)
  - The `aside` with class `type-coverage` is present
- Test: with no auto-catches (factory the run without parsed catches), the `.empty-tray-bar` renders AND the panel-head includes `ALL CAUGHT-UP`.
- Test: in read-only mode (mock `dashboard_read_only?(@run)` to return true via stub or factory the run into a state where the helper returns true), the `+ NEW CATCH` button is absent AND the LOG/EDIT buttons in the review tray are absent (SKIP stays).
- Test: every grid cell's `data-action` is `click->pixeldex#selectPokemon` (preserves the existing modal flow).

**`test/integration/responsive_grids_test.rb`** (extend existing):
- Add `test "Step 22 R2 declares .pc-box-r2 selectors and reflows the grid at the 520px and 900px breakpoints"`:
  - Assert `.pc-box-r2 ` (with trailing space — to distinguish from any future `.pc-box-r2-*` selectors) appears in `pixeldex.css` at least once.
  - Assert the `@media (max-width: 520px)` block contains a `.pc-box-r2 .box-grid` rule with `repeat(3, 1fr)`.
  - Assert the `@media (max-width: 900px)` block contains a `.pc-box-r2 .box-layout` rule with `grid-template-columns: 1fr`.
  - Assert no `.pc-box-r2 .box-cell` rule with `display: none` exists in either breakpoint block (mockup-fidelity contract — same shape as the Step 21 contract for `.slot` / `.roster-card`).

**Existing tests must stay green:** `confirm_modal_flow_test.rb`, `responsive_grids_test.rb`'s existing assertions, `wipe_flow_test.rb`, every model test, every catch-coordinator test, every parser test. The `_pc_box_panel.html.erb` sidebar partial is not touched — any test that references it stays green.

### Constraints (do not violate)

- **No backend changes.** No new column, no migration, no new endpoint, no model method. If you feel you need one to satisfy the mockup, **escalate**.
- **No new design tokens.** Existing tokens cover the mockup. Closest existing token > new token. Inline literals OK only for one-off shadow / overlay values that don't cleanly token-map.
- **No new CSS classes outside the `.pc-box-r2` namespace.** Only exception: extending the existing `@media (max-width: 520px)` and `@media (max-width: 900px)` blocks with `.pc-box-r2 …` rules.
- **No edits to `_pc_box_panel.html.erb`** (sidebar). Cross-cutting 6 sidebar/main consolidation is out of scope.
- **No edits to `pixeldex_controller.js`, `_pokemon_modal.html.erb`, or `_catch_modal.html.erb`.** The new controllers + the existing modals talk via `data-action` chaining and DOM attribute lookup; no upstream code change required.
- **Read-only mode preserved.** `dashboard_read_only?(@run)` gates BOTH the `+ NEW CATCH` button (existing) AND the LOG/EDIT buttons in the review tray (new).
- **Step 17 / 18 catch render unchanged at the data layer.** The view's per-row stats summary is a new one-liner; the underlying fields and pipeline are untouched. Existing `format_move_name` helper is reused.
- **Brakeman + Rubocop clean.** No new offenses, no new warnings.
- **Same broadcast contract.** `SoulLinkPokemon#broadcasts_refreshes_to ->(p) { [p.soul_link_run, :dashboard] }` already drives Turbo morphs on auto-catch arrival — the new view must render correctly under a morph (no Stimulus state lost on filter chip click → save parses → broadcast). Stimulus controllers re-instantiate on morph; since `connect()` reads `location.hash`, state survives. Don't depend on instance state outliving morph.

### Acceptance — Reviewer's checklist (Richard, focus areas)

1. **Visual fidelity to the mockup.** Each of the 4 mockup screens has a 1:1 surface in the new view (Screen 1 default / Screen 2 filter applied / Screen 3 empty tray / Screen 4 mobile). Compare side-by-side with the mockup HTML; flag any spacing / typography / color drift.
2. **Filter chips actually filter.** Markup includes the four chips with correct status params + counts. `data-action` wires to `pc-box-filter#applyFilter`. Cells carry `data-status` matching their group classification. URL hash on chip click is part of the contract.
3. **Badge legend visible AND each badge documented.** All four badge rows in the legend; copy matches the mockup verbatim.
4. **Empty-state copy + CTA.** When no auto-catches: the dashed-border bar with the locked copy AND the panel-head reads `ALL CAUGHT-UP`.
5. **Mobile breakpoint via `responsive_grids_test.rb`.** New assertions at 520px and 900px present. No `display: none` on cells / rows in either breakpoint.
6. **Read-only mode honored.** `+ NEW CATCH` AND LOG/EDIT both gated by `dashboard_read_only?(@run)`. SKIP stays available (client-only).
7. **Accessibility.** Each filter chip is a `<button type="button">`. Search input has an `aria-label`. The review tray's per-row buttons are real `<button>` elements with descriptive text. Group-marker glyphs have `aria-hidden="true"`.
8. **No backend drift.** Search the diff for any change under `app/controllers/`, `app/models/`, `db/`, `config/routes.rb` — there should be **none**. Same for `app/services/soul_link/` and `app/jobs/`.
9. **CSS namespace integrity.** Every new selector in pixeldex.css is prefixed with `.pc-box-r2`. The existing `.box-grid` / `.box-cell` rules used by the sidebar partial are untouched.
10. **Existing test suite green.** Full run: 0 failures, 0 errors. Rubocop clean. Brakeman clean.
11. **No scope creep.** No mark-dead button, no route filter, no player filter, no `skipped_at` column. KG-35 (SKIP non-persistence) and KG-36 (richer filters) logged in BUILD-LOG.

### Build order (suggested)

1. Read the four "Files to verify" — confirm the catch modal input names, the dashboard controller's `openCatchModal`, the existing `data-group-*` attributes on cells, and `pokemon_sprite_tag`'s acceptable size values.
2. Add the `recommended_review_action` helper + a unit test (one test: event_gift → :skip; trade_in → :skip; otherwise :log).
3. Write the new view (`_pc_box_content.html.erb`) — start with the panel-head + review-tray sections, then the filter bar, then the unified grid + rail. Manually render-smoke against a fixture (no auto-catches, with auto-catches, read-only).
4. Add the CSS section to `pixeldex.css` (mockup-verbatim, namespaced) + the two media-query block extensions.
5. Write the two Stimulus controllers (`pc_box_filter_controller.js`, `review_tray_controller.js`).
6. Write the integration test (`pc_box_redesign_test.rb`) + extend `responsive_grids_test.rb` with the Step 22 assertions.
7. Full test run (`PARALLEL_WORKERS=10 bin/rails test`) → 0 fail / 0 error. Rubocop + Brakeman clean.
8. Write `REVIEW-REQUEST.md` with file list + line ranges + open questions.

Flag immediately if: (a) the catch modal's input names don't match what `prefillCatch` expects, (b) any mockup selector collides with an existing rule outside `.pc-box-r2`'s scope, (c) the merged-grid + filter behavior breaks the existing `pixeldex_controller#selectPokemon` flow, (d) you find that backend changes are unavoidable for some part of the mockup.

---

## Builder Plan — Step 22

### Findings from "Files to verify"

**1. The catch modal uses Stimulus targets, NOT `name=` attributes.** From `_catch_modal.html.erb`:
- Nickname input: `data-dashboard-target="catchNickname"` (no `name=`)
- Location select: `data-dashboard-target="catchLocation"` (no `name=`)
- Species input: `data-dashboard-target="catchSpecies"` (no `name=`)

**2. `dashboard#openCatchModal` BLANKS the three fields before opening** (`dashboard_controller.js:17-24`). If `prefillCatch` runs first, `openCatchModal` wipes the values.

**3. The brief's spec for `prefillCatch` needs three fixes**:
- Look up inputs via the dashboard controller's targets, not `[name=...]`. Concretely: find the `[data-controller~="dashboard"]` ancestor, query for `[data-dashboard-target="catchNickname|catchLocation|catchSpecies"]`. Even simpler: query the document for those targets (there's only one dashboard controller per page).
- The `data-action` chain must be **reversed**: `click->dashboard#openCatchModal click->review-tray#prefillCatch`. Stimulus runs actions in declaration order; opening first then prefilling means the user sees the modal pop with values already filled (no flicker).
- The auto-catch row's "species" maps to the modal's SPECIES field. The modal's NICKNAME field has no obvious source from the auto-catch row (auto-catches don't have a user-chosen nickname yet) — leave nickname empty so the user types one. Pre-fill species + location only. The level field doesn't exist on the modal (modal has nickname / location / species; no level). Drop the `level` param from prefillCatch.

**4. Helper homes (confirmed):**
- `recommended_review_action` → `app/helpers/pixeldex_helper.rb` (alongside `pixeldex_type_coverage`)
- `pokemon_sprite_tag(species, size:)` → ApplicationHelper, accepts any size, returns `"".html_safe` when no sprite mapping
- `format_move_name(id)` → EmulatorHelper (Rails auto-includes; usable from dashboard render)

**5. Catch modal location values:** the `<select>` `<option value="<%= key %>">` uses location *keys* (e.g. `route_201`), not display names (e.g. `Route 201`). Auto-catch `p.location` may be either depending on the Step 17/18 pipeline. **Best-effort prefill**: set the select value to `p.location` and let the browser silently fall back to "Select location..." if no match. User can correct before submitting; this is graceful.

### Resolution

Update the wiring spec in the brief to:
- `data-action="click->dashboard#openCatchModal click->review-tray#prefillCatch"` (open first, then prefill)
- `prefillCatch({ params: { species, location } })` — drop `level`
- Stimulus implementation queries the document for `[data-dashboard-target="catchSpecies"]` and `[data-dashboard-target="catchLocation"]`, sets `.value` on each. Nickname stays empty (user types it). Status/feedback target unchanged.

This is a JS implementation correction, not a scope change. Backend / data model / endpoint contracts all unchanged. **Architect endorsement requested inline below; if endorsed, code follows immediately.**

### Architect endorsement

✅ **Endorsed.** Reverse the action chain, drop `level`, look up via Stimulus targets, leave nickname empty. The brief's Constraints section (#5: "the catch modal partial's existing inputs (`name=...`) are the contract") is corrected — the contract is **Stimulus targets**, not `name=`. This is the correct mechanical fix; no scope movement. — Ava

### Build plan (sequenced)

1. Add `recommended_review_action(p)` to `pixeldex_helper.rb` + a one-pass helper test (`test/helpers/pixeldex_helper_test.rb`).
2. Rewrite `app/views/dashboard/_pc_box_content.html.erb` per the brief, with the corrected action chain + dropped level param.
3. Add the namespaced CSS section to `app/assets/stylesheets/pixeldex.css`. Extend the existing `@media (max-width: 520px)` and `@media (max-width: 900px)` blocks (don't open new ones).
4. Write `app/javascript/controllers/pc_box_filter_controller.js` (chip + search + URL hash + rail-dim + count update).
5. Write `app/javascript/controllers/review_tray_controller.js` (prefillCatch via Stimulus targets + dismiss + count decrement).
6. Add `test/integration/pc_box_redesign_test.rb` per the brief's test list.
7. Extend `test/integration/responsive_grids_test.rb` with the Step 22 selector + breakpoint assertions.
8. Run full test suite + Rubocop + Brakeman. Fix any offenses inline.
9. Append KG-35 (SKIP non-persistence) and KG-36 (richer filters out-of-mockup-scope) to BUILD-LOG.md.
10. Write REVIEW-REQUEST.md with file list, line ranges, focus areas.

