# Review Feedback — Step 3
Date: 2026-04-30
Status: APPROVED

## Conditions

None.

## Escalate to Architect

None.

## Cleared

Reviewed Step 3 (Save Slots, 5 per session) end-to-end: the new migration, slot model, controller, view, Stimulus controller, factory, model + controller tests, plus modifications to the session model, parse job, EmulatorController, emulator Stimulus, show.html.erb, _run_sidebar.html.erb, routes, and both rake tasks. Diff scope matches the brief exactly — no out-of-scope changes.

Verifications performed (independently of Bob's claims):

- **Migration `db/migrate/20260430143102_create_soul_link_emulator_save_slots.rb`** — order is correct (create table → add `active_save_slot` → data INSERT → drop columns). The raw-SQL `INSERT ... SELECT save_data` copies the BLOB byte-for-byte, no Ruby-side typecasting; the new model's `GzipCoder` inflates on read, no double-gzip path. `remove_column` type args match the original migrations exactly: `:binary, limit: 16.megabytes`; `:string, limit: 16`; `:integer, limit: 4` (×2); `:integer, limit: 1, default: 0, null: false`; `:integer, limit: 2`; `:datetime`. Rollback is reversible at schema level. `db:migrate:status` shows `20260430143102` up; the migrate → rollback → migrate cycle Bob ran is consistent with what I see in dev.

- **`after_create_commit` deviation on the slot model is sound.** Rails fires `after_create_commit` and `after_update_commit` mutually exclusively per record event — `create!(slot_number:, save_data:)` fires only `after_create_commit`, and `update!(save_data: ...)` fires only `after_update_commit`. No double-parse on either path. The `saved_change_to_attribute?("save_data")` short-circuit on the update hook is preserved. Without the create hook the controller's `@session.save_slots.create!(...)` path would never enqueue a parse, so first-time saves would leave parsed_* nil indefinitely. Necessary deviation.

- **`SaveSlotsController` authorization** — `set_session` resolves only the player's own session via `current_user_id`; `set_slot` scopes via `@session.save_slots`. Cross-player URL manipulation always returns 404. Tests exist for cross-player PATCH (line 391), DELETE (line 284), restore (line 322), download (line 362), and index (line 379). Defense in depth confirmed.

- **`active_save_slot` consistency across all four paths** — cleared on destroy of active slot (controller line 87, test line 265), updated on overwrite (line 76, test line 189), updated on create (line 60, test line 88), changed without byte mutation on restore (line 97, test line 298). The 409 path explicitly does NOT touch active_save_slot (test line 148 asserts).

- **409 → overwrite round-trip uses Approach 2.** `save_slots_controller.js#overwriteSlot` calls `window.EJS_emulator.gameManager.getSaveFile()` at click time (line 119) — fresh bytes, stateless, no JS-side stash. Verified: zero matches for `setInterval`, `setTimeout`, or any `_pendingOverwriteBytes`-style stash across all touched JS files. No auto-tick re-introduction.

- **`slot_payload`'s `saved_bytes` normalization is correct.** `read_attribute_before_type_cast` on a freshly-inserted record returns `ActiveModel::Type::Binary::Data` rather than a `String`; `.to_s` on the wrapper unwraps to the underlying gzipped bytes. The `raw.respond_to?(:to_s) ? raw.to_s.bytesize : nil` pattern handles both shapes; the final `raw.nil? ? nil : saved_bytes` correctly returns nil for absent payloads.

- **Routes** — `patch :save_data` removed, `delete :save_data` retained, `resources :save_slots` nested with `param: :slot_number` and `member { post :restore; get :download }`. URL helpers (`emulator_save_slots_path`, `emulator_save_slot_path`, `restore_emulator_save_slot_path`, `download_emulator_save_slot_path`) all resolve and are exercised in tests.

- **`EmulatorController#save_data`** — GET reads `@session&.active_slot&.save_data`; DELETE wipes all slots (`save_slots.destroy_all`) and clears `active_save_slot`; the entire `request.patch?` branch and the `protect_from_forgery if: -> { request.patch? }` line are both removed.

- **`emulator_controller.js#_uploadSave`** — POSTs to `saveSlotsUrlValue`; on 409 dispatches `save-slots:overwrite-needed` with the JSON body as detail; on 201 dispatches `save-slots:saved`; null/0-byte guard preserved at the top. Manual `EJS_onSaveSave` flow shape unchanged.

- **`_save_slots_sidebar.html.erb`** — iterates 1..5 from `MIN_SLOT`/`MAX_SLOT`, ACTIVE badge gated on `@session.active_save_slot == n`, overwrite overlay rendered with `data-filled` toggle for filled slots only, empty slots show "Empty" with no actions, Clear-All at bottom reuses the existing `clear_save_controller`. Pre-rendered server-side from `@save_slots` ivar (eager-loaded in `EmulatorController#show`).

- **Layout** — 3-column grid `280px minmax(0, 1fr) 280px` extends the prior `minmax(0, 1fr) 280px` 2-column shape with the same `min-width: 0` shrink unlock on the canvas main column. Same degradation profile as before; no new regression risk.

- **Schema** — no leftover `save_data` / `parsed_*` columns on `soul_link_emulator_sessions`; new `active_save_slot` integer column; new `soul_link_emulator_save_slots` table with the unique `(soul_link_emulator_session_id, slot_number)` index per the brief.

- **Edge cases** — download empty slot returns 204 (controller line 106; test line 348); destroy nonexistent slot returns 404 via `set_slot` resolving nil (test line 277); index with no slots returns empty array (test line 52).

- **`_run_sidebar.html.erb` parsed-info refactor** — sources from `s.save_slots.find { |sl| ... }` over the eager-loaded collection (no N+1; `EmulatorController#show` calls `.includes(:save_slots)`). YOU card omits parsed info; OTHER cards render it from their active slot. `&.` chains throughout handle the dangling-pointer case.

- **Tests** — ran `bundle exec rails test` locally: **305 runs, 0 failures, 0 errors** (matches Bob's claim).

- **Rubocop** — ran `bundle exec rubocop` on all 16 touched files locally: **clean** (matches Bob's claim).

Bob built exactly what the brief specified. Two flagged deviations (`after_create_commit` on the slot model; `remove_column` type args for reversible rollback) are both well-reasoned and necessary. Authorization is airtight. The 409 round-trip is properly stateless. Ships as-is.
