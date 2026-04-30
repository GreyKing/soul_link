# Review Request
*Written by Builder. Read by Reviewer.*
*Session-scoped — archived and reset at session end.*

Ready for Review: YES

---

## Step 3 — Save Slots (5 per session)

**Builder:** Bob
**Tests:** 305 passing, 0 failures, 0 errors (was 263 — added ~42)
**Lint:** `bundle exec rubocop` clean on all touched files
**Migration verified:** `db:migrate → db:rollback → db:migrate` cycle works in dev

---

## Files Changed

### Created (8 files)

| Path | Lines | Purpose |
|------|-------|---------|
| `db/migrate/20260430143102_create_soul_link_emulator_save_slots.rb` | 1-67 | Slots table + `active_save_slot` pointer + data preservation INSERT + reversible column drops |
| `app/models/soul_link_emulator_save_slot.rb` | 1-34 | Model: GzipCoder reuse, slot_number 1..5 validation, parse-enqueue callbacks |
| `app/controllers/save_slots_controller.rb` | 1-149 | RESTful slot management: index, create, update, destroy, restore, download |
| `app/views/emulator/_save_slots_sidebar.html.erb` | 1-138 | Left-column partial: 5 slot cards, banner, per-slot actions, Clear-All |
| `app/javascript/controllers/save_slots_controller.js` | 1-141 | Stimulus: overwrite-mode toggle, makeActive, deleteSlot, overwriteSlot (calls `getSaveFile()` at click time) |
| `test/models/soul_link_emulator_save_slot_test.rb` | 1-176 | 18 tests: validations, gzip round-trip, parse callbacks |
| `test/controllers/save_slots_controller_test.rb` | 1-411 | 33 tests: 6 actions × happy/error/cross-player paths, size cap, CSRF bypass |
| `test/factories/soul_link_emulator_save_slots.rb` | 1-19 | Factory with `:filled` and `:parsed` traits |

### Modified (12 files)

| Path | Range | Change |
|------|-------|--------|
| `app/models/soul_link_emulator_session.rb` | 50-58, 81-86 | `has_many :save_slots dependent: :destroy`; new `active_slot` association method; removed `serialize :save_data` and the parse callback (moved to slot model) |
| `app/jobs/soul_link/parse_save_data_job.rb` | 17-46 | Operates on a slot; same update_columns contract |
| `app/controllers/emulator_controller.rb` | 47-57, 79-94 | Eager-load + pre-fetch slots in `show`; DELETE wipes all slots; GET reads `@session.active_slot.save_data`; PATCH branch removed entirely |
| `app/javascript/controllers/emulator_controller.js` | 22, 215-249 | Added `saveSlotsUrl` value; `_uploadSave` POSTs to slots endpoint; 409 dispatches `save-slots:overwrite-needed`; 201 dispatches `save-slots:saved` |
| `app/views/emulator/show.html.erb` | 54-89 | Three-column grid (280px / 1fr / 280px); save_slots_sidebar partial on left; data attribute for save_slots URL |
| `app/views/emulator/_run_sidebar.html.erb` | 1-110 | Parsed info now sources from `active_slot` for OTHER players; YOU card omits parsed info; clear-save button removed (moved to slot column) |
| `config/routes.rb` | 46-58 | Removed `patch :save_data`; nested `resources :save_slots` with `member { post :restore; get :download }` |
| `lib/tasks/soul_link/debug_save.rake` | 1-70 | Iterates slots not sessions |
| `lib/tasks/emulator_cleanup.rake` | 1-31 | Counts/wipes slots instead of `session.save_data` (transitive — original migration removes that column) |
| `test/controllers/emulator_controller_test.rb` | full rewrite | Removed PATCH save_data tests; updated GET to source from active slot; DELETE asserts all slots wiped; parsed-roster uses other-player slots |
| `test/models/soul_link_emulator_session_test.rb` | 285-336 | Replaced gzip+parse tests with save_slots association + active_slot resolution tests |
| `test/jobs/soul_link/parse_save_data_job_test.rb` | full rewrite | Exercises against a slot |
| `test/lib/tasks/emulator_cleanup_test.rb` | full rewrite | Seeds slots; asserts on `session.save_slots.count` |

---

## Self-Review

### What would Reviewer most likely flag?

1. **`after_create_commit :enqueue_parse_if_save_present` on the slot model is NOT in the brief.** The brief only specified `after_update_commit :enqueue_parse_if_save_changed`. I added the create-time hook because `SaveSlotsController#create` does `@session.save_slots.create!(slot_number:, save_data: bytes)` — there is no update event on a freshly-created row, so without after_create_commit the first save into an empty slot would never enqueue a parse. The slot card would show "no parsed data" indefinitely. This addition is necessary for the spec's "parsed metadata appears on slot cards after save" behavior. If Reviewer prefers a different approach (e.g., explicit `SoulLink::ParseSaveDataJob.perform_later(slot)` from the controller), I can refactor.

2. **`slot_payload`'s `saved_bytes` calculation handles the `ActiveModel::Type::Binary::Data` wrapper.** Freshly-created records return that wrapper from `read_attribute_before_type_cast`, not a String — calling `.bytesize` on the wrapper raises NoMethodError. I normalized via `raw.to_s.bytesize`. An alternative would be `slot.reload` before payload generation, but that adds a SQL round-trip purely to flatten the cache. Documented inline.

3. **Migration column-drop type args.** The brief showed bare `remove_column :soul_link_emulator_sessions, :save_data` etc. Without type args, `db:rollback` raises `ActiveRecord::IrreversibleMigration`. I added the type args (matching the original migrations) so rollback is reversible at the schema level. Data is still lost on rollback (Project Owner acceptance per brief). Verified end-to-end: `migrate → rollback → migrate` cycle works.

4. **Run roster YOU card no longer shows parsed in-game info.** Brief said "drop the parsed-info display from the YOU card if it duplicates the slot column." I implemented exactly that — the YOU card now shows status, save size, seed, but NOT name/money/play time/badges. Other players' cards still show their parsed info from their active slot. If Reviewer wants the YOU card to retain parsed info as a quick-glance summary, I can revert.

5. **`save_slots_controller.js` reloads the page after overwrite + restore.** Simple but coarse — a future iteration could swap to a `fetch` of `index` JSON and DOM-patch. For Step 3, reload keeps the contract simple and matches the existing `clear_save_controller.js` behavior.

### Did every item in the brief ship?

- [x] Migration with data preservation INSERT, byte-for-byte preservation, columns dropped after data move
- [x] Slot model with `MIN_SLOT`/`MAX_SLOT` constants, GzipCoder reuse, slot_number 1..5 validation + uniqueness, parse callback
- [x] `SaveSlotsController` with all 6 actions per brief skeleton
- [x] Authorization scoped by `current_user_id` at every endpoint — cross-player access returns 404 (enforced by `set_session`; verified in 6 tests including a dedicated "ARATY cannot read GREY's slots" test)
- [x] `active_save_slot` pointer consistency: cleared on destroy of active slot, updated on overwrite, changes on restore (no byte mutation) — covered by 4 dedicated tests
- [x] 409 → overwrite uses Approach 2 (slot Stimulus calls `getSaveFile()` for fresh bytes)
- [x] Modal-less UI: slot column IS the picker (banner inside the column, not a modal overlay)
- [x] Three-column grid layout: 280px slots / canvas / 280px run roster
- [x] Routes: nested `resources :save_slots` with member `restore` + `download`; `patch :save_data` removed
- [x] `EmulatorController` updates: DELETE wipes all slots + clears active pointer; GET reads from active slot; PATCH branch removed
- [x] Stimulus emulator: POSTs to slots URL; 409 dispatches event; 201 dispatches event
- [x] Stimulus save_slots: connect handler, listeners for two window events, makeActive/deleteSlot/overwriteSlot
- [x] Run sidebar: parsed info on OTHER players' cards; clear-save button removed; YOU card parsed info dropped
- [x] Save slots sidebar: 5 cards, ACTIVE badge, parsed metadata for filled, Empty for empty, banner for overwrite mode, Clear-All at bottom
- [x] Parse job operates on a slot
- [x] Debug rake iterates slots
- [x] Tests: model (18), controller (33), factory; updated emulator-controller, session, parse-job, cleanup-task tests
- [x] 263 → 305 tests passing (+42, 0 failures, 0 errors)
- [x] `bundle exec rubocop` clean on touched files

### What does the user see if data is empty or a request fails?

- **Empty slots:** server-rendered "Empty" text in slot card. No actions besides Download (which 204s), Make Active (404 since no slot), Delete (404).
- **All 5 slots full + click "Save File":** 409 from server → JS dispatches `save-slots:overwrite-needed` → banner appears, click overlays appear on filled cards. User clicks a slot → confirm dialog → PATCH with fresh bytes from `getSaveFile()` → reload.
- **Download empty slot:** 204 (route returns empty 204; slots in practice are destroyed when emptied, so this is defensive only).
- **Failed PATCH (5xx):** JS console.error + alert "Could not overwrite the slot. Try again or contact the run creator."
- **Failed DELETE (5xx):** JS console.error, no reload (page state preserved). User can retry.
- **Failed restore (5xx):** JS console.error, no toast. User can retry.
- **Cross-player attempt:** 404. The set_session before_action resolves to nil because the player has no claimed session matching `current_user_id` for the current run. URL manipulation cannot bypass this.
- **Body > 2MB on POST/PATCH:** 413 (`content_too_large`). Two-stage check: `request.content_length` pre-read, then `bytes.bytesize` post-read.
- **Player has no claimed session at all:** every endpoint returns 404. The slot column doesn't render in this state because `show` short-circuits to a different state branch.

---

## Open Questions / Notes

1. **Ordering of slot cards under index when slots aren't contiguous.** I order by `slot_number` ascending. If slots 1, 3, 5 are filled, the JSON returns `[1, 3, 5]`. The view renders cards 1..5 left-to-right with empty cards for 2 and 4. Confirmed in tests (`index returns the player's own slots ordered by slot_number`).

2. **`emulator_controller.js`'s `_uploadSave` reload-on-201.** I dispatch `save-slots:saved` and `save_slots_controller.js` does `window.location.reload()` on it. The brief said "201 Created — refresh the slot column with new data" — I interpreted "refresh" as full reload for simplicity. If Reviewer wants partial DOM patch (fetch index JSON, re-render slot cards in place), it's a follow-up.

3. **`EmulatorController#show` eager-loads `:save_slots` for both `@run_sessions` (for run roster parsed info) AND pre-fetches `@save_slots` for the current player.** The eager-load handles the run-roster N+1 (one query for all 4 sessions' slots). The `@save_slots` ivar is the player's own slots in slot_number order, used by the slot column partial. Two queries total when in the ready state.

4. **Slot column re-uses the existing `clear_save_controller` JS.** No change to that controller — it still DELETEs `/emulator/save_data` (server now wipes all slots) and reloads. Did not remove the file (brief said don't remove).

5. **Did NOT introduce a `GzipCoder` concern.** Brief explicitly said "do NOT introduce a GzipCoder concern unless Reviewer flags duplication explicitly. For this step, reach into `SoulLinkEmulatorSession::GzipCoder` directly." I did exactly that.

6. **Did NOT touch `_uploadSave`'s null/0-byte guard.** Brief Step 2 added it; Step 3 keeps it intact.

7. **`EJS_onSaveSave` flow shape unchanged** — it still calls `_uploadSave(event.save)` and `_triggerDownload(event.save)`. Only the URL `_uploadSave` POSTs to changed.

8. **No auto-tick re-introduction.** Confirmed via grep — no `setInterval` / `setTimeout` in any of the JS files I touched. The save-save-interval option remains "0" (auto-flush disabled).

---

**Ready for Review: YES**
