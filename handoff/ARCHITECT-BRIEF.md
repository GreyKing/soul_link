# Architect Brief
*Written by Architect. Read by Builder and Reviewer.*
*Overwrite this file each step — it is not a log, it is the current active brief.*

---

## Step 8 — Full Calculator Tab in Dashboard

Context: Step 7 added a Quick Calculator modal on the party page with API endpoints (`GET /api/pokemon/:species`, `POST /api/calculator`). This step adds a full-featured CALC tab to the dashboard with both attacker and defender sides fully selectable, your team pokemon as quick-pick buttons, and a history of recent calculations.

### What the User Sees

A new "CALC" tab in the dashboard tab bar (7th tab, after RUNS). The tab content has:

1. **Two-column layout** — Attacker (left) vs Defender (right)
2. **Each side has:**
   - Species input with datalist autocomplete (493 pokemon)
   - Quick-pick buttons for your current team pokemon (pre-fills species + level + nature)
   - Level input (default 50)
   - Nature select (25 natures)
   - Base stats display (filled on species select)
   - Sprite + type badges
3. **Move section** (below columns) — dropdown of attacker's damaging moves, move info display
4. **Results section** — damage range, total, crit, effectiveness, STAB, all the fields from Step 5
5. **Swap button** — swaps attacker and defender (useful for "what if they attack back?")
6. **Calculation history** — last 5 calculations shown as compact rows below results, clickable to re-load

### Architecture Decisions

- **Reuse Step 7 API endpoints.** No new backend code needed (except the tab + partial + controller data).
- **New Stimulus controller:** `full_calc_controller.js` — manages both sides, swap, history
- **Tab added to existing pixeldex tab system** — button in `_tab_bar.html.erb`, content div in `show.html.erb`
- **Team quick-pick data** passed via Stimulus values from `@team_groups` already loaded in `DashboardController`

### Tab Integration

**_tab_bar.html.erb** — add after RUNS button:
```erb
<button class="tab-item" data-action="click->pixeldex#switchTab" data-pixeldex-target="tabButton" data-tab="calc">CALC</button>
```

**show.html.erb** — add after runs tab content div (before closing `</div>` of `.panel`):
```erb
<div data-pixeldex-target="tabContent" data-tab="calc" class="hidden">
  <%= render "calc_content" %>
</div>
```

### Controller Data

In `DashboardController#show`, add:
```ruby
@calc_team_pokemon = @team_groups.flat_map do |group|
  group.soul_link_pokemon.select { |p| p.discord_user_id == current_user_id }.map do |p|
    { species: p.species, level: p.level || 50, nature: p.nature }
  end
end
```

### New Partial: dashboard/_calc_content.html.erb

Wrap in `full-calc` controller div with values: `csrf`, `pokemonUrl` (`/api/pokemon/`), `calcUrl` (`/api/calculator`), `teamPokemon` (JSON array from `@calc_team_pokemon`).

**Layout:**
- Two-column grid: Attacker (left) / Defender (right)
- Each side: quick-pick buttons, species input with datalist, level + nature row, sprite + types + stats display
- Center swap button (⇄ SWAP)
- Move section (full-width card below)
- Results section (full-width card, hidden until calc)
- History section (last 5 calcs, compact rows)
- Shared datalist `id="full-calc-species"` with all 493 species

Nature `<select>` options rendered server-side from `PixeldexHelper::NATURES.keys`. Include empty "Neutral" option.

### Stimulus Controller: full_calc_controller.js

**Values:** `csrf` (String), `pokemonUrl` (String), `calcUrl` (String), `teamPokemon` (Array)

**Targets:**
- `attackerSpecies`, `attackerLevel`, `attackerNature`, `attackerSprite`, `attackerTypes`, `attackerStats`, `attackerQuickPick`
- `defenderSpecies`, `defenderLevel`, `defenderNature`, `defenderSprite`, `defenderTypes`, `defenderStats`, `defenderQuickPick`
- `moveSelect`, `moveInfo`
- `resultSection`
- `historySection`, `historyList`

**Methods:**

`connect()` — render quick-pick buttons for both sides from `teamPokemonValue`. Each button: species name + level, styled as small pill. Click fills that side + triggers fetch.

`attackerChanged()` — fetch attacker data → populate sprite/types/stats + move dropdown.

`defenderChanged()` — fetch defender data → populate sprite/types/stats. Auto-calculate if move selected.

`moveChanged()` — display move info, trigger calculate.

`calculate()` — POST to calc API, display results, add to history.

`swap()` — swap all field values between sides. Re-fetch both sides. Clear move dropdown and re-fetch new attacker's moves.

`_addToHistory(attacker, defender, moveName, result)` — prepend to history list (max 5). Each entry: compact div "Attacker → Defender: Move (min-max)". Clickable to re-load all fields.

**Keep self-contained.** Do NOT extract shared code with quick_calc_controller. Duplication is fine.

### Results Display

```
Per Hit:  124 - 147
Total:    248 - 294  (2 hits)     ← only if multi-hit
Average:  271                      ← only if multi-hit
Crit:     248 - 294

STAB ✓  |  Super Effective (2x)  |  Crit Chance: 6.25%

Attacker: 200 Atk (Adamant)  |  Defender: 91 Def
```

Color-code effectiveness: 4x red, 2x orange, 1x neutral, 0.5x/0.25x blue, 0x gray.

### Quick-Pick Buttons

Rendered in `connect()` from `teamPokemonValue`:
```
[Garchomp Lv.48] [Lucario Lv.45] [Togekiss Lv.42] ...
```

Style: `font-size: 9px; padding: 2px 6px; border: var(--border-thin); cursor: pointer;`
On hover: subtle highlight. On click: fill species/level/nature → trigger changed.

### Build Order

1. Add CALC tab button to `_tab_bar.html.erb`
2. Add `@calc_team_pokemon` to `DashboardController#show`
3. Create `dashboard/_calc_content.html.erb`
4. Add tab content div to `show.html.erb`
5. Create `full_calc_controller.js`

### Flags
- Flag: No new API endpoints — reuse from Step 7.
- Flag: No new backend tests — API endpoints covered.
- Flag: `@team_groups` already loaded in DashboardController. Filter by `current_user_id`.
- Flag: Datalist ID: `full-calc-species` (distinct from quick calc's `calc-species-list`).
- Flag: History is in-memory only (JS array). Lost on reload. Fine.
- Flag: Swap clears move dropdown and re-fetches new attacker's moves.
- Flag: All text via textContent. Zero innerHTML with variables.
- Flag: Read `_strategy_panel.html.erb` as reference for tab content structure.
- Flag: `helpers.asset_path` provides digested sprite URLs via API.
- Flag: `current_user_id` available in dashboard controller (from DiscordAuthentication concern).
- Flag: Use `mise exec -- ruby -S bundle exec rails test` to run tests.

### Definition of Done
- [ ] CALC tab button in tab bar, switches correctly
- [ ] Two-column layout: attacker (left) + defender (right)
- [ ] Quick-pick buttons populate from team pokemon
- [ ] Species input with datalist autocomplete
- [ ] Level + nature inputs on both sides
- [ ] Sprite, types, stats display for both sides (using API sprite_url)
- [ ] Move dropdown populated from attacker's damaging moves
- [ ] Results display: per-hit, total (multi-hit), crit, effectiveness, STAB
- [ ] Swap button exchanges attacker ↔ defender
- [ ] History shows last 5 calculations
- [ ] All text rendered via textContent (no innerHTML with variables)
- [ ] Existing 100 tests still pass

---

## Builder Plan
*Builder adds their plan here before building. Architect reviews and approves.*
