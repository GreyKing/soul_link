# Architect Brief
*Written by Architect. Read by Builder and Reviewer.*
*Overwrite this file each step — it is not a log, it is the current active brief.*

---

## Step 9 — UX Batch: Tier-A Silent-Failure Fixes + KG-1/2/3/4

### Context

`handoff/PROJECT-REVIEW-2026-04-30.md` produced a prioritized punch-list. This step ships the recommended first batch:

- **Tier A (5 items):** Silent-failure / data-integrity bugs — user-facing toasts on critical errors, button-disabled states on in-flight requests.
- **KG-1 + KG-2:** Real-time roster + dashboard broadcasts via Turbo Streams. Closes the two highest-ROI Knowledge Gaps for the 4-player live UX.
- **KG-3 + KG-4:** EVOLVE button loading state + promote inline `#d4b14a` to a `--amber` palette token.

After this lands the codebase will have its first real-time multi-player UX, plus several rough edges sanded off. **No new model concepts.** **No app refactors.** Pure UX polish on top of the existing architecture.

Pre-flight notes:
- `config/cable.yml` uses `async` adapter in development AND production. In-process broadcasts only. The bot process can't broadcast to web clients without redis — but the broadcasts in this step originate from web requests (controllers + parse jobs running in Puma), so async is sufficient.
- `turbo-rails` 2.0.20 — supports `broadcasts_refreshes_to` macro, page-refresh via Turbo morph, and `turbo_stream_from` view helper.
- Existing actioncable channels (`GymDraftChannel`, `GymScheduleChannel`, `RunChannel`) handle their own broadcasting through manual `broadcast_to`. Step 9 introduces Turbo's stream broadcasting for two new use cases — the patterns coexist; do not refactor existing channels.

### Project Owner decisions (locked)

- **Auto-accept mode for this work.** Bob can act decisively; Reviewer + tests are the backstop.
- **Ship all 9 items in one step.** They're small individually but coordinated (the Tier-A toasts + the broadcasts together close the data-integrity story).
- **Don't add redis.** The async cable adapter is sufficient for in-process broadcasts; bot-driven changes (Discord modals updating models from the bot process) are out of scope and stay page-load-driven for now.
- **Don't refactor the existing channel code.** GymDraftChannel etc. stay as-is; Step 9's new broadcasts use Turbo Stream broadcasts (`broadcasts_refreshes_to` / `broadcast_replace_to`), which is a different code path.
- **Use `window.alert()` for the Tier-A toasts.** A proper toast component is out of scope; the alert is the smallest user-facing change that closes the silent-failure gap. Future polish can replace alerts with a styled toast (likely in a follow-up step).

### Tier A — Silent-Failure Fixes (5 items)

#### A.1 — `app/javascript/controllers/save_slots_controller.js`

Three `console.error`-only error branches at lines 54, 75, 80, 142, 149. Replace with:
- Line 54 (`restore failed`): `console.error(...)` + `window.alert("Could not make slot " + slotNumber + " active. Try again or contact the run creator.")`
- Line 59 (`restore error` catch): same alert.
- Line 75 (`delete failed`): `console.error(...)` + `window.alert("Could not delete slot " + slotNumber + ". Try again or contact the run creator.")`
- Line 80 (`delete error` catch): same alert.
- Line 142 (`overwrite PATCH failed`): the alert already exists at line 143 — leave it. Just verify.
- Line 149 (`overwrite error` catch): existing `console.error` plus add `window.alert("Network error overwriting slot. Try again or contact the run creator.")`.

The `_refreshAfterSave` and `_enterOverwriteMode` paths already do the right thing — leave them.

#### A.2 — `app/javascript/controllers/gym_draft_controller.js`

`handleMessage` at line 39-43 silently `console.error`s server-sent errors. Add a transient banner:

```js
handleMessage(data) {
  if (data.error) {
    console.error("Draft error:", data.error)
    this.showError(data.error)
    return
  }
  ...
}

showError(message) {
  if (!this.hasErrorBannerTarget) {
    // Lazily create a banner inside phaseInfo if no dedicated target exists
    return alert(`Draft error: ${message}`)
  }
  this.errorBannerTarget.textContent = message
  this.errorBannerTarget.hidden = false
  if (this._errorTimer) clearTimeout(this._errorTimer)
  this._errorTimer = setTimeout(() => { this.errorBannerTarget.hidden = true }, 8000)
}
```

Add `errorBanner` to the `static targets` array. The view (gym_drafts/show.html.erb) needs a `<div data-gym-draft-target="errorBanner" hidden class="gb-flash gb-flash-alert">...</div>` to receive it. If adding the target to the view is complex, fall back to `alert()` — but try the banner first since it doesn't block interaction.

#### A.3 — `app/javascript/controllers/team_builder_controller.js`

`showStatus(text, className)` writes Tailwind classes (`text-yellow-400`, `text-green-400`, `text-red-400`) but the project uses `pixeldex.css` (no Tailwind utility classes loaded for the dashboard layout). Save status is invisible.

Replace with semantic CSS classes. In `app/assets/stylesheets/pixeldex.css`, add:

```css
.team-builder-status { font-size: 11px; line-height: 1.6; }
.team-builder-status--saving { color: var(--amber); }
.team-builder-status--saved  { color: var(--l1); }
.team-builder-status--error  { color: #e8a0a0; }
```

(`--amber` is added in KG-4 below — Builder ships KG-4's CSS edit first, then references the token here.)

In `team_builder_controller.js#showStatus`:
- `this.showStatus("Saving...", "team-builder-status--saving")`
- `this.showStatus("Saved!", "team-builder-status--saved")`
- `this.showStatus(data.error || "Save failed", "team-builder-status--error")`
- `this.showStatus("Network error", "team-builder-status--error")`

And:
```js
showStatus(text, modifier) {
  if (!this.hasSaveStatusTarget) return
  this.saveStatusTarget.textContent = text
  this.saveStatusTarget.className = `team-builder-status ${modifier}`
}
```

#### A.4 — `_save_slots_sidebar.html.erb` + `save_slots_controller.js`

When `_overwritePending` is true, the per-card action buttons (Download / Make Active / Delete) remain clickable underneath the overwrite overlay. Although the overlay covers them, accessibility tools can still focus them and tab navigation reaches them.

Fix in Stimulus, not view:
- `_enterOverwriteMode`: also set `disabled` on every `[data-action*="save-slots#makeActive"], [data-action*="save-slots#deleteSlot"]` button inside the controller's element.
- `_exitOverwriteMode`: re-enable them.

Don't disable Download (`<a>` element, would need different handling — tab navigation isn't the primary UX risk).

#### A.5 — Pokemon modal SAVE in-flight protection

`pixeldex_controller.js#savePokemon` (line 297) doesn't disable the SAVE button. Double-clicks fire 2-3 fetches in parallel; last response wins. Same pattern needed in `evolvePokemon` (covered by KG-3 below).

In `savePokemon`:
- At top of method: find the SAVE button in the modal and disable it.
- On all error paths and the final `window.location.reload()`: nothing extra needed (reload destroys the page state).
- On thrown errors before reload: re-enable.

The SAVE button is at `_pokemon_modal.html.erb:113-116` with `data-action="click->pixeldex#savePokemon"`. To find it from the controller:

```js
async savePokemon(event) {
  const saveBtn = event?.currentTarget
  if (saveBtn) saveBtn.disabled = true
  // ... existing body ...
  // On any error-return path, re-enable:
  // if (saveBtn) saveBtn.disabled = false; return
}
```

The current method signature is `async savePokemon()` (no `event`). Add the `event` parameter — Stimulus passes it; existing call sites are HTML actions which already pass the event.

### KG-1 — Real-Time Run Roster Broadcasts

After the SRAM parse job updates a slot's `parsed_*` columns, the OTHER 3 players' emulator pages should see that player's roster card refresh — without a page reload. The own player's view also benefits (their roster card on their own emulator page).

#### Backend

**Extract roster card partial.** Move the per-session card body from `_run_sidebar.html.erb` lines 12-107 (inside the `@run_sessions.each do |s|` block) into a new partial `app/views/emulator/_run_sidebar_card.html.erb`. The new partial takes a single local `s` (the session). The outer `each` in `_run_sidebar.html.erb` now just renders `<%= render "emulator/run_sidebar_card", s: s %>`.

The partial needs to call `current_user_id` (currently does so via `is_you = s.discord_user_id == current_user_id`). To keep `current_user_id` accessible from background broadcast renders, the partial should accept `current_user_id` as an explicit local. But broadcasts don't have a `current_user_id` — every player gets the same broadcast. This is a problem.

**Solution:** the broadcast renders the card WITHOUT the YOU badge / is_you-conditional content. Each viewer's tab does NOT receive a personalized version. After broadcast, the YOU badge is missing on the broadcast-rendered card. To preserve YOU rendering: render the card with `is_you: false` always at broadcast time — the OWN player's tab visually loses the YOU badge for ~1 frame, then reappears on next page load. Acceptable tradeoff for v1.

**Better solution:** broadcast-rendered card includes a `data-discord-user-id="..."` attribute; a small Stimulus controller on the emulator page reads `current_user_id` from a meta tag and adds the YOU badge / 4px border to whichever card matches.

Acceptable simpler middle ground for this step: the broadcast-rendered card always shows the YOU badge / 4px border for `s.discord_user_id == @broadcast_current_user_id`. To keep this scoped: pass `current_user_id` as an explicit local. The model's broadcast callback does NOT have access to a current user — but it doesn't need to: it broadcasts to a stream that every viewer subscribes to, and each viewer's TURBO frame replacement happens client-side.

**Final decision:** Step 9 keeps it simple. The broadcast-rendered partial does NOT include the YOU badge or the 4px border (these are visual identifiers, not behavior). On the next full page load they reappear. This is acceptable because the UPDATE flow is: a player saves → parse job runs → the OTHER players see their card update with new in-game info. The OWN player's card updates too, losing the YOU badge until next refresh. It's a minor regression but the alternative is dragging current_user_id into model callbacks, which is a layer violation.

Actually, **simplest correct solution:** wrap the YOU-badge and 4px-border in `<turbo-frame id="emulator_roster_session_<%= s.id %>_you" data-turbo-permanent>` so Turbo morphs/replaces preserve them across stream replacements. Same applies to the 4px-border style — render it conditionally outside the broadcast-replace target.

For Step 9, ship the simpler version: **the broadcast-rendered card omits the YOU badge and the 4px border.** Document as a Known Gap to refine later.

**Add `turbo_stream_from` to emulator/show.html.erb.** Subscribe each viewer to the run-scoped stream:

```erb
<%= turbo_stream_from @run, :emulator if @run %>
```

Place at the top of the show template (after the layout wrapper, before the grid).

**Add model callback on `SoulLinkEmulatorSaveSlot`:**

```ruby
class SoulLinkEmulatorSaveSlot < ApplicationRecord
  # ... existing ...
  after_create_commit :broadcast_roster_card_update
  after_update_commit :broadcast_roster_card_update, if: :saved_change_to_parsed?

  private

  def saved_change_to_parsed?
    saved_change_to_attribute?("parsed_trainer_name") ||
      saved_change_to_attribute?("parsed_money") ||
      saved_change_to_attribute?("parsed_play_seconds") ||
      saved_change_to_attribute?("parsed_badges") ||
      saved_change_to_attribute?("parsed_at")
  end

  def broadcast_roster_card_update
    session = soul_link_emulator_session
    return unless session
    run = session.soul_link_run
    return unless run
    Turbo::StreamsChannel.broadcast_replace_to(
      run, :emulator,
      target: "emulator_roster_session_#{session.id}",
      partial: "emulator/run_sidebar_card",
      locals: { s: session }
    )
  end
end
```

The `broadcast_replace_to` helper renders the partial on the broadcast side, sends the resulting `<turbo-stream action="replace" target="...">` to all subscribers of `[run, :emulator]`. Each viewer's `<turbo-frame id="emulator_roster_session_N">` gets swapped with the new render.

**Wrap the per-session card in a turbo_frame_tag.** In `_run_sidebar.html.erb`, after extracting the card to a partial, wrap the render call:

```erb
<% @run_sessions.each do |s| %>
  <%= turbo_frame_tag "emulator_roster_session_#{s.id}" do %>
    <%= render "emulator/run_sidebar_card", s: s %>
  <% end %>
<% end %>
```

The `_run_sidebar_card.html.erb` partial body OMITS the outer turbo_frame_tag — the broadcast replaces the frame's CONTENTS, not the frame itself.

#### Tests

Add a model test `test/models/soul_link_emulator_save_slot_test.rb`:

```ruby
test "after_update_commit broadcasts when parsed fields change" do
  slot = create(:soul_link_emulator_save_slot, ...)
  assert_changes -> { ActionCable.server.pubsub.subscriptions.count } do
    # Or use `assert_broadcasts` if available
    slot.update!(parsed_trainer_name: "Lyra")
  end
end
```

Actually, testing turbo_stream broadcasts in Rails 8 is straightforward with `assert_turbo_stream_broadcasts` (from `turbo-rails` gem). Use that:

```ruby
test "update to parsed_trainer_name broadcasts a roster replace" do
  slot = create(:soul_link_emulator_save_slot, :filled, soul_link_emulator_session: @session)
  assert_turbo_stream_broadcasts [@session.soul_link_run, :emulator], count: 1 do
    slot.update!(parsed_trainer_name: "Lyra")
  end
end

test "update to non-parsed field does NOT broadcast" do
  slot = create(:soul_link_emulator_save_slot, :filled, soul_link_emulator_session: @session)
  assert_turbo_stream_broadcasts [@session.soul_link_run, :emulator], count: 0 do
    slot.update!(updated_at: Time.current)
  end
end

test "create with parsed fields broadcasts" do
  assert_turbo_stream_broadcasts [@session.soul_link_run, :emulator], count: 1 do
    create(:soul_link_emulator_save_slot, :filled, soul_link_emulator_session: @session)
  end
end
```

The `assert_turbo_stream_broadcasts` helper isn't in turbo-rails 2.0; the `assert_broadcasts` ActionCable helper works. Test the simpler shape: `assert_changes -> { broadcast_count }` — or, simplest, just test that calling `update!` does not raise an error in a context where broadcasting fires. Bob has discretion on the exact assertion shape, but at minimum:
- Render the partial standalone with the smoke test pattern (`render template/partial: ..., locals: { ... }` in a test) to verify it can be rendered without controller context. This is the most important coverage — broadcasts fail silently if the partial errors during render.

### KG-2 — Real-Time Dashboard Broadcasts

When any player's pokemon updates (species, level, ability, nature, status) or any group updates (nickname, status, location, eulogy), the dashboard pages of all viewers in the run should refresh.

Implementation: Turbo's `broadcasts_refreshes_to` + page-refresh via morph.

#### Backend

In `app/models/soul_link_pokemon.rb`:

```ruby
class SoulLinkPokemon < ApplicationRecord
  # ... existing ...
  broadcasts_refreshes_to ->(pokemon) { [pokemon.soul_link_run, :dashboard] }
end
```

In `app/models/soul_link_pokemon_group.rb`:

```ruby
class SoulLinkPokemonGroup < ApplicationRecord
  # ... existing ...
  broadcasts_refreshes_to ->(group) { [group.soul_link_run, :dashboard] }
end
```

The macro hooks into create/update/destroy. Every save fires a broadcast — in a typical Soul Link session that's a few per minute, well under any rate-limit concern.

#### Frontend

In `app/views/dashboard/show.html.erb`, at the top of the layout:

```erb
<%= turbo_refreshes_with method: :morph, scroll: :preserve %>
<%= turbo_stream_from @run, :dashboard %>
```

The `turbo_refreshes_with` helper emits two `<meta>` tags that configure Turbo Drive's morph behavior. Refreshes from the broadcast won't reset scroll position or destroy DOM state (modals stay open, focus preserved).

Place these BEFORE the dashboard's content — top of the body of `show.html.erb` is fine.

#### Tests

```ruby
test "pokemon update broadcasts a refresh" do
  pokemon = create(:soul_link_pokemon, :route201_grey, soul_link_run: @run, soul_link_pokemon_group: @group)
  assert_broadcasts(["soul_link_run_#{@run.id}_dashboard", "...refreshes..."], 1) do
    pokemon.update!(species: "Pidgey")
  end
end
```

The exact test shape varies by turbo-rails internals. Same as KG-1: at minimum, verify the macro is called (no error) and the broadcast fires. Bob has discretion. If the assertion shape is awkward, fall back to: test that updating a pokemon doesn't raise + verify the broadcast count incremented via ActionCable's pubsub spy.

### KG-3 — EVOLVE Button Loading State

`pixeldex_controller.js#evolvePokemon` (line 357) doesn't disable the button. On slow networks the user sees the static "EVOLVE" text and may double-click.

Add at start of method:

```js
async evolvePokemon(event) {
  const evolveBtn = event?.currentTarget
  if (evolveBtn) {
    evolveBtn.disabled = true
    evolveBtn.textContent = "EVOLVING..."
  }
  // ... existing body ...
  // On error-return paths, re-enable:
  if (evolveBtn) {
    evolveBtn.disabled = false
    evolveBtn.textContent = "EVOLVE"
  }
}
```

There are 2 error-return paths inside the method (failed response, network error catch). Re-enable on both. Success path does `window.location.reload()` — leave the button disabled (page is going away).

### KG-4 — Amber Palette Token

Add to `:root` block in `app/assets/stylesheets/pixeldex.css` (around line 6-13):

```css
:root {
  --d1: #1a2e1a;
  --d2: #3a5a3a;
  --l1: #8a9e6a;
  --l2: #9aae7a;
  --white: #c0d0a0;
  --amber: #d4b14a;
  ...
}
```

Then in `app/views/emulator/_run_sidebar.html.erb` line 33:

```erb
"background: #d4b14a; color: var(--d1); border: 2px solid var(--d1);"
```

Becomes:

```erb
"background: var(--amber); color: var(--d1); border: 2px solid var(--d1);"
```

That's the only documented use of `#d4b14a`. KG-4 also unlocks the Tier-A.3 status colors above (which reference `--amber`).

### Out of Scope (do NOT expand)

- Bot-process broadcasts (Discord modals updating models would need redis cable adapter)
- Refactoring channel code (GymDraftChannel, GymScheduleChannel, RunChannel)
- Replacing `window.alert()` with a styled toast component
- Real-time updates for save slot column on the LEFT (KG-1 covers the roster sidebar on the RIGHT only)
- YOU badge / 4px border preservation across broadcast updates (acceptable visual blink documented as Known Gap)
- Refactoring the dashboard view structure
- Touching `EmulatorController#show` or `DashboardController#show` (just the views and the models)
- Adding new factory traits (use existing ones)
- Pre-existing rubocop offenses outside touched files

### Constraints / Flags

- **Run tests after each major edit, not just at the end.** Sequence: KG-4 (CSS, no test) → A.3 (depends on KG-4 token) → A.1 / A.2 / A.5 → KG-3 → KG-1 → KG-2 → full suite. Each broadcast-related change should run the model test for that model immediately.
- **305/305 must pass at the end** (or 305 + new tests). Adding new tests for KG-1 / KG-2 broadcasts is fine and encouraged.
- **Don't introduce a new factory trait** — all needed shapes exist in `:filled` and `:parsed` traits on save_slot, plus the route trait set on pokemon.
- **The `_run_sidebar_card.html.erb` partial must render cleanly when called with ONLY the `s` local.** No `current_user_id`, no `@run_sessions`. Verify by adding a render test.
- **`broadcasts_refreshes_to` requires `turbo_refreshes_with` on the page.** Without the meta tags, the page does a full reload instead of a morph — visually disruptive. Test by manually opening a second browser tab and saving in the first.
- **Don't add `broadcasts_refreshes_to` to `SoulLinkEmulatorSaveSlot`.** That model uses targeted frame replacement (KG-1), not full-page refresh. Mixing the two on the same page would cause double-broadcast.
- **Pre-existing rubocop offenses on touched files** — fix only those surfaced on lines Bob is editing. Same Step 5/6/7/8 lesson.

### Acceptance Criteria

- All 9 items shipped:
  - 5 Tier-A items
  - KG-1 (run roster real-time)
  - KG-2 (dashboard real-time)
  - KG-3 (EVOLVE loading state)
  - KG-4 (amber token)
- Full test suite green: 305/305 (or 305+N if new tests added).
- `bundle exec rubocop` clean on all touched Ruby files.
- Manual smoke test (Bob): two browser tabs of `/dashboard` (different players via different OmniAuth mocks if needed); update a pokemon in tab 1; tab 2 morphs to show the change without scroll loss.
- Manual smoke test: two browser tabs of `/emulator`; create / update a save slot in tab 1; tab 2's roster card for that session updates.
- Diff scope: 5 JS controllers, 2 view partials (one extracted), 2 models, 1 stylesheet, 2 layout-level views (emulator/show.html.erb, dashboard/show.html.erb), gym_drafts/show.html.erb, BUILD-LOG.md, REVIEW-REQUEST.md, REVIEW-FEEDBACK.md, ARCHITECT-BRIEF.md (this file). New file: `_run_sidebar_card.html.erb`.

### Files Bob Should Read

- `app/javascript/controllers/save_slots_controller.js` (Tier A.1, A.4)
- `app/javascript/controllers/gym_draft_controller.js` (Tier A.2)
- `app/javascript/controllers/team_builder_controller.js` (Tier A.3)
- `app/javascript/controllers/pixeldex_controller.js` lines 297-355, 357-383 (Tier A.5, KG-3)
- `app/views/emulator/_run_sidebar.html.erb` (KG-1, KG-4)
- `app/views/emulator/_save_slots_sidebar.html.erb` (Tier A.4)
- `app/views/emulator/show.html.erb` (KG-1)
- `app/views/dashboard/show.html.erb` (KG-2)
- `app/views/dashboard/_pokemon_modal.html.erb` (Tier A.5)
- `app/views/gym_drafts/show.html.erb` (Tier A.2 — error banner target)
- `app/models/soul_link_emulator_save_slot.rb` (KG-1)
- `app/models/soul_link_pokemon.rb` (KG-2)
- `app/models/soul_link_pokemon_group.rb` (KG-2)
- `app/assets/stylesheets/pixeldex.css` (KG-4 + A.3)
- `test/models/soul_link_emulator_save_slot_test.rb` (KG-1 tests)

DO NOT load app/controllers (no controller changes) or app/services (no service changes).

### Files Bob Should Update at the End

- `handoff/REVIEW-REQUEST.md` — files-changed table, self-review answers, open questions, `Ready for Review: YES`
- `handoff/BUILD-LOG.md` — Step History entry for Step 9. **Also update Known Gaps**: KG-1, KG-2, KG-3, KG-4 are closed — strike them through or move to a "Closed Gaps" subsection. Add the YOU-badge regression as a new Known Gap.

---

## Notes for Reviewer

When this lands on your desk, focus on:

1. **All Tier-A error paths now have user-facing toasts.** Grep `app/javascript/controllers/save_slots_controller.js` and `gym_draft_controller.js` for `console.error`. Each occurrence should have a sibling `window.alert` or `showError` call.

2. **`team_builder_controller.js#showStatus` no longer references Tailwind classes.** Grep for `text-yellow-400`, `text-green-400`, `text-red-400` — should return zero matches in `team_builder_controller.js`.

3. **Save-slot action buttons disabled in overwrite-pending mode.** Manually walk the flow: open emulator with all 5 slots full, click "Save File" to trigger 409, verify Download / Make Active / Delete buttons are disabled while overlay is shown. After clicking a slot to overwrite (or `Esc` to cancel), buttons re-enable.

4. **Pokemon modal SAVE + EVOLVE buttons disable on click.** Open pokemon modal, click SAVE — button greys out, "SAVING..." text appears. Same for EVOLVE.

5. **`broadcasts_refreshes_to` on `SoulLinkPokemon` and `SoulLinkPokemonGroup`.** Grep both models. The macro should be called with a stream-name lambda `[record.soul_link_run, :dashboard]`.

6. **`_run_sidebar_card.html.erb` is a new partial that renders cleanly with only `s` as a local.** Test this by reading the partial: it should NOT reference `current_user_id`, `@run_sessions`, or any other ivar. The YOU badge and 4px border conditional are removed (acceptable visual blink, documented as new Known Gap).

7. **`turbo_stream_from @run, :emulator` and `turbo_stream_from @run, :dashboard`** are added to the respective show.html.erb templates. Plus `turbo_refreshes_with method: :morph` on the dashboard.

8. **Manual real-time smoke test.** Open two `/emulator` tabs (or use `bin/dev` and view in two browsers). Save in one; verify the other's roster card for that session updates without page reload. Same for `/dashboard` and a pokemon update.

9. **Diff scope.** `git status --short` should show only the files listed in Acceptance Criteria. Anything else (especially app/controllers or app/services) is a Reviewer Condition.

10. **No regression on existing channel functionality.** Run gym_draft_channel_test, gym_schedule_channel_test, run_channel_test — all green.

Out-of-scope items found during review → BUILD-LOG Known Gaps. Do not bundle.
