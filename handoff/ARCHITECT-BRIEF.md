# Architect Brief
*Written by Architect. Read by Builder and Reviewer.*
*Overwrite this file each step — it is not a log, it is the current active brief.*

---

## Step 4 — Run Roster Sidebar on `/emulator`

Context: emulator is shipping and Project Owner just verified the canvas works. Next polish: a sidebar on the right side of the emulator showing the four sessions of the current run — who's claimed each, last activity, save size, etc. **Tier 1 only** (existing model data; no SRAM parsing). Tier 2 (parsing the SRAM blob to extract in-game info like time-played, money, party) is **deferred to a future step**, do NOT implement here.

This is a small, self-contained step. One controller change, one view change, one new partial, controller tests.

### Files to Modify

- `app/controllers/emulator_controller.rb` — load `@run_sessions` on `:ready` state only
- `app/views/emulator/show.html.erb` — wrap the ready-state UI in a flex container; render the new partial on the right
- `test/controllers/emulator_controller_test.rb` — extend with assertions for the ivar

### Files to Create

- `app/views/emulator/_run_sidebar.html.erb` — the sidebar markup

### Controller Change

In `EmulatorController#show`, after `@cheats` is set and ONLY when state is `:ready`, add:

```ruby
@run_sessions = @run.soul_link_emulator_sessions.order(:id)
```

Eager loading: not strictly needed (we only read trivial columns + access `save_data` raw bytes via `read_attribute_before_type_cast`), but `.order(:id)` is required for stable display order across renders.

Don't load `@run_sessions` in non-ready branches — they don't render the sidebar so it'd be wasted DB.

### View Change — `app/views/emulator/show.html.erb`

In the `else` branch (the ready-state, currently lines 54–71), wrap the existing `.gb-card` (emulator stage) and a new sidebar in a flex layout:

```erb
<% else %>
  <div style="display: flex; gap: 16px; align-items: flex-start; flex-wrap: wrap;">
    <%# Existing emulator-stage card — keep it intact, just place inside the flex %>
    <div style="flex: 1 1 auto; min-width: 0;">
      <div class="gb-card" style="padding: 12px;"
           data-controller="emulator"
           data-emulator-rom-url-value="<%= rom_emulator_path %>"
           data-emulator-save-data-url-value="<%= save_data_emulator_path %>"
           data-emulator-csrf-value="<%= form_authenticity_token %>"
           data-emulator-core-value="<%= EmulatorController::EMULATOR_CORE %>"
           data-emulator-pathtodata-value="/emulatorjs/data/"
           data-emulator-cheats-value="<%= @cheats.to_json %>">
        <div id="emulator-game" data-emulator-target="game"
             style="aspect-ratio: 2 / 3; max-width: min(100%, 60vh); max-height: 90vh; margin: 0 auto;"></div>
      </div>
    </div>

    <aside style="width: 280px; flex-shrink: 0;">
      <%= render "run_sidebar" %>
    </aside>
  </div>
<% end %>
```

**Critical:** keep the existing emulator-game div's style attribute exactly as it is now (`aspect-ratio: 2 / 3; max-width: min(100%, 60vh); max-height: 90vh; margin: 0 auto;`). It was sized in `9b0bf29` and works. Don't tweak it.

**Responsive note:** `flex-wrap: wrap` lets the sidebar drop below the canvas on narrow viewports. The canvas's `max-width: min(100%, 60vh)` already caps its width on small screens, so wrapping is clean. `min-width: 0` on the flex item is a flexbox quirk required for `flex: 1 1 auto` to actually shrink — keep it.

### Partial — `app/views/emulator/_run_sidebar.html.erb`

Renders 4 cards, one per session in `@run_sessions`. GB styling, no Tailwind utilities. Data per card:

| Field | Source |
|---|---|
| Player name (or "Unclaimed") | `SoulLink::GameState.player_name(s.discord_user_id)`; fall back to `"Unclaimed"` |
| Status badge | `s.status` mapped to a label/color (ready=green, generating/pending=amber, failed=red) |
| Last activity | If `s.save_data.present?`: "Played #{time_ago_in_words(s.updated_at)} ago"; else "Not started" |
| Save size on disk | `bytes = s.read_attribute_before_type_cast("save_data")&.bytesize`; render via `number_to_human_size(bytes)` if present, else "—" |
| Seed | `s.seed` (informational, since CLI mode auto-seeds — show as a faint detail) |
| YOU badge | If `s.discord_user_id == current_user_id`, add a visible "YOU" label and accent border on the card |

Suggested structure:

```erb
<div class="gb-card" style="padding: 10px; margin-bottom: 8px;">
  <div style="font-size: 11px; color: var(--d2); margin-bottom: 6px; letter-spacing: 1px;">RUN ROSTER</div>
</div>

<% @run_sessions.each do |s| %>
  <% is_you = s.discord_user_id == current_user_id %>
  <% saved_bytes = s.read_attribute_before_type_cast("save_data")&.bytesize %>
  <% player_label = SoulLink::GameState.player_name(s.discord_user_id).presence ||
                    (s.discord_user_id ? s.discord_user_id.to_s : "Unclaimed") %>

  <div class="gb-card" style="padding: 10px; margin-bottom: 8px; <%= "border-color: var(--accent);" if is_you %>">
    <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 4px;">
      <div style="font-size: 12px; color: var(--d1);"><%= player_label %></div>
      <% if is_you %>
        <div style="font-size: 9px; color: var(--accent); letter-spacing: 1px;">YOU</div>
      <% end %>
    </div>

    <div style="font-size: 10px; color: var(--d2); margin-bottom: 2px;">
      Status: <%= s.status.upcase %>
    </div>

    <% if saved_bytes %>
      <div style="font-size: 10px; color: var(--d2); margin-bottom: 2px;">
        Played <%= time_ago_in_words(s.updated_at) %> ago
      </div>
      <div style="font-size: 10px; color: var(--d2); margin-bottom: 2px;">
        Save: <%= number_to_human_size(saved_bytes) %>
      </div>
    <% else %>
      <div style="font-size: 10px; color: var(--d2); margin-bottom: 2px;">Not started</div>
    <% end %>

    <div style="font-size: 9px; color: var(--d2); opacity: 0.6;">
      Seed: <%= s.seed %>
    </div>
  </div>
<% end %>
```

The above is a **starting shape**, not a literal spec. Match the GB aesthetic of `app/views/runs/index.html.erb` — use whatever existing classes (`gb-card`, etc.) and CSS vars (`--d1`, `--d2`, `--accent`, `--l1`, `--l2`) already work in the project. If `var(--accent)` doesn't exist, pick a reasonable highlight color from what does.

### Status badge — color/styling

Map session status to readable label + color:
- `"ready"` → green-ish (use `var(--l2)` or whatever the existing positive-state color is)
- `"pending"` / `"generating"` → amber/yellow (look at the runs page "ROMs generating…" label for a precedent)
- `"failed"` → red (the existing `gb-btn-danger` color or similar)

Don't invent CSS classes; use inline `style` with project vars if that's the easiest path.

### Tests

`test/controllers/emulator_controller_test.rb` — extend the existing "ready state" tests:

- `@run_sessions is set on ready state` — assert the ivar is present, has 4 entries, ordered by id
- `@run_sessions is nil/unset on non-ready states` — verify it's not loaded for no-run / no-roms / all-claimed / generating / failed branches (or just isn't accessed in those branches; whichever is simpler to assert)
- View-rendering check — make a `get` request to a logged-in ready player, assert response body contains:
  - The current player's display name (or fallback)
  - The string `"YOU"` (the badge)
  - The string `"RUN ROSTER"` (the section header)
  - At least one `"Unclaimed"` if other sessions are unclaimed
- View should NOT contain `"YOU"` for the non-ready branches (defensive)

Don't try to test pixel-level layout. Just assert the data flows through.

### Build Order

1. Read `app/views/runs/index.html.erb` and `app/assets/stylesheets/pixeldex.css` to identify what `gb-card`, `gb-btn-*`, and CSS vars are actually defined. Don't invent new ones.
2. Update `EmulatorController#show` — add `@run_sessions = @run.soul_link_emulator_sessions.order(:id)` on the ready branch only.
3. Create `app/views/emulator/_run_sidebar.html.erb`.
4. Update `app/views/emulator/show.html.erb` — wrap ready-state in flex container, render partial.
5. Extend controller tests.
6. Run targeted tests: `bin/rails test test/controllers/emulator_controller_test.rb`. Iterate.
7. Run full suite: `bin/rails test`. Confirm 216 baseline + new tests pass.
8. Run full suite 3+ times in parallel for flake check.

### Flags

- Flag: **Tier 1 only.** Do NOT parse SRAM. Do NOT extract in-game character name, time played, money, party, etc. Those are deferred.
- Flag: **Don't change the emulator-game div's inline style.** The aspect-ratio CSS that was added in `9b0bf29` solves the canvas sizing — keep it byte-for-byte identical.
- Flag: **No real-time updates.** Page-load refresh only. ActionCable broadcasts can come later if anyone wants live "X just saved" updates.
- Flag: **Use `read_attribute_before_type_cast` for save size**, not `save_data.bytesize`. The latter triggers gzip decompression, which is wasteful for a display-only stat. The former returns the raw compressed bytes from the DB.
- Flag: **`current_user_id` is bigint Integer** (locked architecture decision). Compare directly to `s.discord_user_id` without coercion.
- Flag: **`SoulLink::GameState.player_name`** is the right lookup. Fall back to the raw discord_user_id String if the GameState mapping doesn't have an entry, and "Unclaimed" if discord_user_id is nil.
- Flag: **Match GB aesthetic.** No Tailwind utility classes. Use existing `gb-*` classes + CSS vars from `pixeldex.css`. If a color/class doesn't exist, pick the closest existing one — don't add new CSS to `pixeldex.css` for this step.
- Flag: **Responsive: flex-wrap is enough.** No media queries needed. Sidebar wraps below canvas on narrow viewports.
- Flag: Rails commands use `bin/rails ...` (e.g. `bin/rails test`). Fall back to `mise exec -- bundle exec rails ...` only if `bin/rails` fails. Do NOT use `mise exec -- ruby -S bundle exec`.
- Flag: Do NOT commit. Architect commits.

### Definition of Done

- [ ] `EmulatorController#show` sets `@run_sessions` on ready state, ordered by id
- [ ] `app/views/emulator/_run_sidebar.html.erb` exists
- [ ] Ready-state view renders the canvas + sidebar in a flex layout, sidebar on the right
- [ ] Each session card shows: player name (or fallback), status, last-played time (or "Not started"), save size (or "—"), seed
- [ ] Current player's card has a visible "YOU" badge and an accent border
- [ ] Non-ready states (no-run / no-roms / all-claimed / generating / failed) render unchanged — sidebar is absent, no `@run_sessions` access
- [ ] Canvas's `aspect-ratio: 2 / 3; max-width: min(100%, 60vh); max-height: 90vh; margin: 0 auto;` style is preserved exactly as in `9b0bf29`
- [ ] Controller tests cover: ivar set on ready, view contains player name + "YOU" + "RUN ROSTER" + at least one "Unclaimed"
- [ ] Full suite passes: 216 baseline + new tests, 0 failures
- [ ] 3+ consecutive parallel runs without flakes

---

## Builder Plan
*Builder adds their plan here before building. Architect reviews and approves.*

- Verified: `gb-card`, `gb-card-dark`, CSS vars `--d1`/`--d2`/`--l1`/`--l2`/`--white` exist; **no `--accent` var** — will use `var(--d1)` (matches "ACTIVE" badge in runs/index) for YOU border accent and `var(--white)` for the YOU label, and `var(--l2)` for status text on dark cards.
- Note on `player_name` semantics: actual code returns `"Player #{uid}"` (never nil) for unknown uids; brief's `presence ||` chain still works — it falls back to "Unclaimed" only when `discord_user_id` is nil. This satisfies DoD.
- Status badge palette: ready → green (use `var(--l2)` text on `var(--d1)` bg, mirroring `.gb-status-caught` style); pending/generating → amber inline color `#d4b14a`; failed → use `gb-flash-alert` palette (`#e8a0a0` on `#4a1c1c`).
- Tests: 5 new — ivar set+ordered+count, ivar absent on no-run state, view contains player name + "YOU" + "RUN ROSTER" + "Unclaimed", view does NOT contain "RUN ROSTER" on no-run/generating/failed branches.
- Build order matches brief; will run targeted tests then full suite x3 in parallel for flake check.
