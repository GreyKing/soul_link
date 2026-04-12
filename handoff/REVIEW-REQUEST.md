# Review Request
*Written by Builder. Read by Reviewer.*

Ready for Review: YES

---

## Step 8 — Full Calculator Tab in Dashboard

### Files Created

#### 1. `app/views/dashboard/_calc_content.html.erb`
- New partial for the CALC tab content
- Wrapped in `full-calc` Stimulus controller div with values: `csrf`, `pokemonUrl`, `calcUrl`, `teamPokemon`
- Two-column grid layout: Attacker (left) / Swap button (center) / Defender (right)
- Each side has: quick-pick button container (rendered by JS), species input with `full-calc-species` datalist, level input (default 50), nature select (25 natures from `PixeldexHelper::NATURES` with stat labels), sprite + types + stats display area
- Move section: full-width card with select dropdown and move info display
- Results section: hidden by default, populated by JS after calculation
- History section: hidden by default, shows last 5 calculations
- Shared `<datalist id="full-calc-species">` rendered server-side from `@pokedex_species`

#### 2. `app/javascript/controllers/full_calc_controller.js`
- Self-contained Stimulus controller (no shared code with `quick_calc_controller.js`)
- Values: `csrf` (String), `pokemonUrl` (String), `calcUrl` (String), `teamPokemon` (Array)
- 14 targets covering both sides, move section, results, and history
- `connect()`: renders quick-pick buttons for both attacker and defender from `teamPokemonValue`
- `attackerChanged()`: fetches attacker data, populates sprite/types/stats + move dropdown
- `defenderChanged()`: fetches defender data, populates sprite/types/stats, auto-calculates if move selected
- `moveChanged()`: displays move info line, triggers calculation
- `calculate()`: POST to `/api/calculator`, displays results with per-hit/total/crit/effectiveness/STAB
- `swap()`: exchanges all field values between sides, swaps cached data, clears and re-populates moves from new attacker
- `_addToHistory()`: prepends to in-memory history (max 5), renders compact clickable rows
- `_loadFromHistory()`: re-fetches both sides, sets move, re-calculates
- All text rendered via `textContent` -- zero `innerHTML` with variables
- Effectiveness color-coded: 4x red, 2x orange, 0.5x/0.25x blue, 0x gray
- Quick-pick buttons styled as small pills with hover highlight

### Files Modified

#### 3. `app/views/dashboard/_tab_bar.html.erb`
- Added CALC tab button after RUNS, wired to `pixeldex#switchTab` with `data-tab="calc"`

#### 4. `app/views/dashboard/show.html.erb`
- Added `calc` tab content div after `runs` div, rendering `_calc_content` partial
- Uses `data-pixeldex-target="tabContent"` and `data-tab="calc"` for tab switching

#### 5. `app/controllers/dashboard_controller.rb`
- Added `@calc_team_pokemon` instance variable: flat-maps team groups to extract current player's pokemon with species, level, and nature
- Filters by `current_user_id` to only show the logged-in player's team pokemon as quick-pick options

### Test Results

```
100 runs, 256 assertions, 0 failures, 0 errors, 0 skips
```

All existing tests pass unchanged.

### Definition of Done

- [x] CALC tab button in tab bar, switches correctly
- [x] Two-column layout: attacker (left) + defender (right)
- [x] Quick-pick buttons populate from team pokemon
- [x] Species input with datalist autocomplete
- [x] Level + nature inputs on both sides
- [x] Sprite, types, stats display for both sides (using API sprite_url)
- [x] Move dropdown populated from attacker's damaging moves
- [x] Results display: per-hit, total (multi-hit), crit, effectiveness, STAB
- [x] Swap button exchanges attacker <-> defender
- [x] History shows last 5 calculations
- [x] All text rendered via textContent (no innerHTML with variables)
- [x] Existing 100 tests still pass

### Notes for Reviewer

- No new API endpoints created -- reuses `GET /api/pokemon/:species` and `POST /api/calculator` from Step 7.
- No new backend tests needed -- API endpoints already covered by existing test suite.
- Stimulus auto-discovery handles controller registration -- no importmap pin needed.
- Datalist ID is `full-calc-species` (distinct from quick calc's `calc-species-list`).
- History is in-memory only (JS array), lost on page reload. This is intentional per the brief.
- `@team_groups` was already loaded in `DashboardController` -- the new code just filters for the current player's pokemon.
- Swap clears the move dropdown and re-populates with the new attacker's moves from cached data, avoiding an extra API call.
- The controller caches fetched pokemon data (`_attackerData` / `_defenderData`) so swap and history reload can re-render sides without redundant fetches where possible.
