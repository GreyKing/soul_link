# Architect Brief
*Written by Architect. Read by Builder and Reviewer.*
*Overwrite this file each step — it is not a log, it is the current active brief.*

---

## Step 3 — Save Slots (5 per session)

### Context

The current model stores ONE save per `SoulLinkEmulatorSession` in the `save_data` column (gzipped) plus parsed-cache columns (`parsed_trainer_name`, `parsed_money`, `parsed_play_seconds`, `parsed_badges`, `parsed_map_id`, `parsed_at`) on the session itself. Every PATCH overwrites the previous bytes — no history, no rollback, no checkpointing.

Project Owner wants a slot-based system: 5 named slots per player, save-to-empty-first with overwrite-picker if all 5 are full. UI lives in a new left column on `/emulator` that mirrors the right-column run roster pattern. Per-slot actions: download `.sav`, make-active (reload-on-refresh pointer change, no mutation), delete.

After this step, the SRAM round-trip looks like: player clicks EmulatorJS "Save File" → Stimulus POSTs bytes → backend writes to first empty slot OR (if all full) returns 409 with slot metadata → Stimulus arms the left column for overwrite-click → player clicks a slot card → PATCH that slot → done.

### Project Owner decisions (locked)

- **5 slots per session**, hardcoded constant. No configurability.
- **Cross-player visibility: own only.** Players see/manage only their own slots; sidebar still shows everyone's parsed in-game info (via the active slot).
- **Make-active = pointer change, no byte mutation.** Setting `active_save_slot = 3` doesn't copy slot 3's bytes anywhere; it's just where `GET /emulator/save_data` reads from. The other 4 slots stay intact.
- **After "Make active", manual refresh.** No auto-reload. Toast says "Slot N is now active. Refresh to load it."
- **Layout: three columns.** `[280px slot column] [1fr canvas] [280px run roster]`. Slot column on the LEFT, run roster on the RIGHT (existing).
- **Save-trigger UX**: keep the EmulatorJS "Save File" button as the single save trigger. On 409 (all slots full), the page banner-prompts user to click a slot card in the left column to overwrite. NOT a modal — the slots are already visible.

### Files to Create

- `db/migrate/<timestamp>_create_soul_link_emulator_save_slots.rb` — migration
- `app/models/soul_link_emulator_save_slot.rb` — model with `GzipCoder` for `save_data`, parse callback
- `app/controllers/save_slots_controller.rb` — RESTful slot management
- `app/views/emulator/_save_slots_sidebar.html.erb` — left-column partial
- `app/javascript/controllers/save_slots_controller.js` — Stimulus for slot interactions (download / make-active / delete / overwrite-on-click)
- `test/models/soul_link_emulator_save_slot_test.rb`
- `test/controllers/save_slots_controller_test.rb`
- `test/factories/soul_link_emulator_save_slots.rb`

### Files to Modify

- `app/models/soul_link_emulator_session.rb` — `has_many :save_slots`; remove `save_data` + `parsed_*` accessors and the `enqueue_parse_if_save_changed` callback (move callback to slot model)
- `app/jobs/soul_link/parse_save_data_job.rb` — operate on a `SoulLinkEmulatorSaveSlot`, not a session
- `app/controllers/emulator_controller.rb` — `save_data` GET reads from `active_save_slot`'s bytes; `save_data` DELETE wipes ALL slots + clears `active_save_slot`; `save_data` PATCH **removed** (Stimulus now POSTs to `/emulator/save_slots`)
- `app/javascript/controllers/emulator_controller.js` — `_uploadSave` now POSTs to `/emulator/save_slots` (auto-empty path); on 409 it dispatches a custom DOM event the slot Stimulus controller listens for; remove direct PATCH-to-`save_data` path. `EJS_onSaveSave` flow stays the same shape.
- `app/javascript/controllers/clear_save_controller.js` — DELETE endpoint still exists, server now wipes all slots
- `app/views/emulator/show.html.erb` — three-column grid layout, render `_save_slots_sidebar` on left
- `app/views/emulator/_run_sidebar.html.erb` — drop the inline "Clear Save Data" button (moves to slot column instead) AND drop the parsed-info display from the YOU card if it duplicates the slot column. **Keep parsed info on OTHER players' cards** (they still need their own progress visible). Remove the `clear-save` Stimulus mount.
- `config/routes.rb` — `delete :save_data` stays (now wipes all slots); `patch :save_data` removed; nested `resources :save_slots` under `:emulator`
- `test/controllers/emulator_controller_test.rb` — remove PATCH save_data tests; update GET save_data tests to source from active slot; update DELETE tests to assert all slots wiped
- `test/models/soul_link_emulator_session_test.rb` — remove the `enqueue_parse_if_save_changed` callback tests; ensure existing structure is otherwise intact
- `test/jobs/soul_link/parse_save_data_job_test.rb` — exercise the job against a slot, not a session
- `lib/tasks/soul_link/debug_save.rake` — `reparse_all_saves` and `debug_save_offsets` now iterate slots, not sessions

### Migration spec

```ruby
class CreateSoulLinkEmulatorSaveSlots < ActiveRecord::Migration[8.1]
  def change
    create_table :soul_link_emulator_save_slots do |t|
      t.references :soul_link_emulator_session, null: false, foreign_key: true, index: true
      t.integer :slot_number, null: false
      t.binary  :save_data, limit: 16.megabytes
      t.string  :parsed_trainer_name, limit: 16
      t.integer :parsed_money
      t.integer :parsed_play_seconds
      t.integer :parsed_badges, default: 0, null: false
      t.integer :parsed_map_id, limit: 2
      t.datetime :parsed_at
      t.timestamps
      t.index [:soul_link_emulator_session_id, :slot_number], unique: true,
              name: "idx_soul_link_emulator_save_slots_session_slot"
    end

    add_column :soul_link_emulator_sessions, :active_save_slot, :integer

    reversible do |dir|
      dir.up do
        # Migrate every existing per-session save into slot 1 of that session.
        # save_data goes through the GzipCoder on read (it's still a String at
        # the AR level here since we haven't dropped the column yet) — we want
        # the RAW gzipped bytes to write directly into the new slot's
        # save_data column without double-gzipping. Use update_columns + raw
        # bytes via `read_attribute_before_type_cast`.
        execute <<~SQL.squish
          INSERT INTO soul_link_emulator_save_slots (
            soul_link_emulator_session_id, slot_number, save_data,
            parsed_trainer_name, parsed_money, parsed_play_seconds,
            parsed_badges, parsed_map_id, parsed_at,
            created_at, updated_at
          )
          SELECT id, 1, save_data,
                 parsed_trainer_name, parsed_money, parsed_play_seconds,
                 COALESCE(parsed_badges, 0), parsed_map_id, parsed_at,
                 NOW(), NOW()
          FROM soul_link_emulator_sessions
          WHERE save_data IS NOT NULL
        SQL

        execute <<~SQL.squish
          UPDATE soul_link_emulator_sessions
          SET active_save_slot = 1
          WHERE save_data IS NOT NULL
        SQL
      end
    end

    remove_column :soul_link_emulator_sessions, :save_data
    remove_column :soul_link_emulator_sessions, :parsed_trainer_name
    remove_column :soul_link_emulator_sessions, :parsed_money
    remove_column :soul_link_emulator_sessions, :parsed_play_seconds
    remove_column :soul_link_emulator_sessions, :parsed_badges
    remove_column :soul_link_emulator_sessions, :parsed_map_id
    remove_column :soul_link_emulator_sessions, :parsed_at
  end
end
```

The raw-SQL INSERT preserves the gzipped bytes byte-for-byte. The new model will use the same `GzipCoder` so `slot.save_data` returns the inflated bytes transparently.

### Model spec

```ruby
class SoulLinkEmulatorSaveSlot < ApplicationRecord
  MIN_SLOT = 1
  MAX_SLOT = 5

  serialize :save_data, coder: SoulLinkEmulatorSession::GzipCoder

  belongs_to :soul_link_emulator_session

  validates :slot_number, presence: true,
                          inclusion: { in: MIN_SLOT..MAX_SLOT },
                          uniqueness: { scope: :soul_link_emulator_session_id }

  after_update_commit :enqueue_parse_if_save_changed

  private

  def enqueue_parse_if_save_changed
    return unless saved_change_to_attribute?("save_data")
    return if save_data.blank?
    SoulLink::ParseSaveDataJob.perform_later(self)
  end
end
```

`GzipCoder` already exists on `SoulLinkEmulatorSession`; reference it explicitly until / if it migrates to a top-level concern. Do NOT duplicate the coder — pull it out into its own file (`app/models/concerns/gzip_coder.rb`) ONLY if Reviewer flags it; for this step, keep it accessible via the existing class reference.

### Controller spec — `SaveSlotsController`

```ruby
class SaveSlotsController < ApplicationController
  include DiscordAuthentication

  MAX_SAVE_DATA_BYTES = EmulatorController::MAX_SAVE_DATA_BYTES

  before_action :require_login
  before_action :set_session
  before_action :set_slot, only: [ :update, :destroy, :restore, :download ]

  protect_from_forgery with: :null_session,
                       only: [ :create, :update ],
                       if: -> { request.post? || request.patch? }

  # GET /emulator/save_slots — JSON list of all slots for the current
  # player's session, used for the modal-less overwrite picker on the
  # left column. Returns up to 5 entries with parsed metadata.
  def index
    return head :not_found if @session.nil?
    slots = @session.save_slots.order(:slot_number).map { |s| slot_payload(s) }
    render json: { slots: slots, active_slot: @session.active_save_slot, max: SoulLinkEmulatorSaveSlot::MAX_SLOT }
  end

  # POST /emulator/save_slots — write SRAM bytes to first empty slot.
  # 200 on success with slot info; 409 with current slots if all 5 full.
  def create
    return head :not_found if @session.nil?
    return head :content_too_large if oversized?
    bytes = read_body
    return head :content_too_large if bytes.bytesize > MAX_SAVE_DATA_BYTES

    used = @session.save_slots.pluck(:slot_number).to_set
    empty = (SoulLinkEmulatorSaveSlot::MIN_SLOT..SoulLinkEmulatorSaveSlot::MAX_SLOT).find { |n| !used.include?(n) }

    if empty.nil?
      slots = @session.save_slots.order(:slot_number).map { |s| slot_payload(s) }
      return render json: { error: "all_slots_full", slots: slots }, status: :conflict
    end

    slot = @session.save_slots.create!(slot_number: empty, save_data: bytes)
    @session.update_column(:active_save_slot, slot.slot_number)
    render json: slot_payload(slot), status: :created
  end

  # PATCH /emulator/save_slots/:slot_number — overwrite specific slot.
  # Used for the explicit-overwrite path after 409 on create.
  def update
    return head :not_found if @session.nil? || @slot.nil?
    return head :content_too_large if oversized?
    bytes = read_body
    return head :content_too_large if bytes.bytesize > MAX_SAVE_DATA_BYTES

    @slot.update!(save_data: bytes)
    @session.update_column(:active_save_slot, @slot.slot_number)
    render json: slot_payload(@slot)
  end

  # DELETE /emulator/save_slots/:slot_number — wipe a single slot.
  # If the slot was active, also nil out active_save_slot.
  def destroy
    return head :not_found if @session.nil? || @slot.nil?
    was_active = @session.active_save_slot == @slot.slot_number
    @slot.destroy!
    @session.update_column(:active_save_slot, nil) if was_active
    head :no_content
  end

  # POST /emulator/save_slots/:slot_number/restore — pointer change only.
  # Sets active_save_slot to this slot. No byte mutation.
  def restore
    return head :not_found if @session.nil? || @slot.nil?
    @session.update_column(:active_save_slot, @slot.slot_number)
    head :no_content
  end

  # GET /emulator/save_slots/:slot_number/download — .sav download for one slot.
  def download
    return head :not_found if @session.nil? || @slot.nil?
    return head :no_content if @slot.save_data.blank?
    send_data @slot.save_data,
              type: "application/octet-stream",
              disposition: "attachment",
              filename: "pokemon-platinum-slot#{@slot.slot_number}.sav"
  end

  private

  def slot_payload(slot)
    {
      slot_number: slot.slot_number,
      parsed_trainer_name: slot.parsed_trainer_name,
      parsed_money: slot.parsed_money,
      parsed_play_seconds: slot.parsed_play_seconds,
      parsed_badges: slot.parsed_badges,
      parsed_map_id: slot.parsed_map_id,
      updated_at: slot.updated_at,
      saved_bytes: slot.read_attribute_before_type_cast("save_data")&.bytesize
    }
  end

  def set_session
    run = SoulLinkRun.current(session[:guild_id])
    @session = run&.soul_link_emulator_sessions&.find_by(discord_user_id: current_user_id)
  end

  def set_slot
    @slot = @session&.save_slots&.find_by(slot_number: params[:slot_number])
  end

  def oversized?
    request.content_length && request.content_length > MAX_SAVE_DATA_BYTES
  end

  def read_body
    request.body.read
  end
end
```

### Routes

Replace the existing emulator resource block:

```ruby
resource :emulator, only: [ :show ], controller: "emulator" do
  get    :rom
  get    :save_data
  delete :save_data         # now wipes all slots
  get    :firmware
  resources :save_slots, only: [ :index, :create, :update, :destroy ], param: :slot_number do
    member do
      post :restore
      get  :download
    end
  end
end
```

Note: removed `patch :save_data` — Stimulus no longer hits it.

### `EmulatorController` updates

- `save_data` GET: `bytes = @session&.active_slot&.save_data` (add `active_slot` association on session that finds the slot record matching `active_save_slot`)
- `save_data` DELETE: `@session.save_slots.destroy_all; @session.update_column(:active_save_slot, nil)`
- `save_data` PATCH: **remove the entire `request.patch?` branch** from the action

### Stimulus changes

**`emulator_controller.js`** — `_uploadSave` now POSTs to `/emulator/save_slots`:

```js
async _uploadSave(saveBytes) {
  if (!saveBytes || saveBytes.byteLength === 0) return
  const blob = saveBytes instanceof Uint8Array ? saveBytes : new Uint8Array(saveBytes)
  try {
    const res = await fetch(this.saveSlotsUrlValue, {
      method: "POST",
      headers: { "Content-Type": "application/octet-stream", "X-CSRF-Token": this.csrfValue },
      credentials: "same-origin",
      body: blob
    })
    if (res.status === 409) {
      // All slots full. Dispatch a custom event the slot column listens for.
      const data = await res.json()
      window.dispatchEvent(new CustomEvent("save-slots:overwrite-needed", { detail: data }))
      return
    }
    if (!res.ok) {
      console.error("Emulator: save_slots POST failed:", res.status)
      return
    }
    // 201 Created — refresh the slot column with new data
    window.dispatchEvent(new CustomEvent("save-slots:saved"))
  } catch (e) {
    console.error("Emulator: error saving slot:", e)
  }
}
```

Add a new Stimulus value `saveSlotsUrl: String` and pass it from the view (`save_slots_emulator_path`). Keep `saveDataUrl` for the GET on load and DELETE for clear.

When the slot column receives `save-slots:overwrite-needed`, it puts itself in "overwrite-pending" mode: each slot card becomes a PATCH-to-that-slot click target.

**`save_slots_controller.js`** — new file:
- Stimulus values: `slotsUrl: String`, `csrf: String`, `saveBytes: Object` (transient — held when waiting for overwrite click)
- On connect: `fetch slotsUrl` to populate, render slot cards
- Listens for `save-slots:overwrite-needed` window event → enter overwrite-pending mode (set Stimulus class on container, change "Save here" labels, capture the bytes from event detail OR re-fetch by asking the emulator controller — see "details" below)
- Click handlers on slot cards: download / make-active / delete / overwrite (only in pending mode)

**Important detail for overwrite path**: when 409 fires, the emulator controller has the SRAM bytes that the user just tried to save. Those bytes are NOT in the event detail (we didn't put them there to keep the event small). Two approaches:

1. **Stash on emulator controller**: emulator controller keeps the failed-to-save bytes in `this._pendingOverwriteBytes`. Slot column dispatches `save-slots:do-overwrite` with `{slot_number}` when a slot is clicked; emulator controller picks bytes from its stash and PATCHes them.
2. **Re-grab bytes from the emulator**: when the slot is clicked, slot controller calls `window.EJS_emulator.gameManager.getSaveFile()` to get fresh bytes and PATCHes directly. Avoids cross-controller state.

**Use approach 2.** It's stateless, avoids the bytes living in JS memory longer than necessary, and matches how the manual button path already works. The slot controller becomes responsible for the overwrite PATCH.

### View spec — `_save_slots_sidebar.html.erb`

Mirror the run-roster layout. Top-level `data-controller="save-slots"` on the column container. 5 slot cards, plus a Clear-All button at the bottom. Each card:

- Slot number badge (1-5)
- ACTIVE badge if `active_save_slot == this.slot_number`
- If filled: parsed_trainer_name, time-played, money, badges, "Saved X ago"
- If empty: "Empty"
- Action row: Download (link to `download_emulator_save_slot_path`), Make Active (POST to restore), Delete (DELETE)
- In overwrite-pending mode (CSS class on container): card becomes click-target with "Click to overwrite" overlay

Use the existing `--d1`/`--l2` Tailwind palette tokens and `gb-card` / `type-text` classes. Match the right-column style.

The view is rendered server-side with the current slot state loaded by `EmulatorController#show` (eager-load `@session.save_slots`). Stimulus then enhances with client-side actions.

### Layout — `show.html.erb`

Replace the two-column grid:

```erb
<div style="display: grid; grid-template-columns: 280px minmax(0, 1fr) 280px; gap: 16px; align-items: start;">
  <aside><%= render "save_slots_sidebar" %></aside>
  <main style="min-width: 0;"><%= render the canvas + emulator data-controller %></main>
  <aside><%= render "run_sidebar" %></aside>
</div>
```

Keep the existing `data-emulator-*` attributes on the canvas wrapper. Add `data-emulator-save-slots-url-value="<%= save_slots_emulator_path %>"`.

### Out of Scope (do NOT expand)

- DeSmuME removal from gear menu (deferred, not blocking)
- Real-time slot sync via ActionCable (page-load refresh is fine)
- Sharing slots across runs (slots are scoped to the session; new run = new slots)
- Slot naming / renaming (slots are 1-5 numbered; no labels)
- Cross-player slot visibility (own only — locked above)
- Auto-snapshot via interval (we just disabled the auto-tick for the SRAM race; do NOT re-introduce a tick here either)
- Migration rollback for existing parsed_* columns (the migration is one-way; if rolled back we'd lose the data — Project Owner accepts this since prod has 2-3 saves)
- Touching the firmware path (`/emulator/firmware`), the parser, the cheats system, or any non-emulator feature

### Constraints / Flags

- DO NOT add a modal. The slot column IS the picker.
- DO NOT skip the migration's data-preservation step. Existing players have saves that must land in slot 1.
- DO NOT use `update!` in places where the brief calls for `update_column` — `update_column` skips callbacks, which is what we want for `active_save_slot` updates (no parse re-trigger, no validation churn).
- DO NOT introduce a `GzipCoder` concern unless Reviewer flags duplication explicitly. For this step, reach into `SoulLinkEmulatorSession::GzipCoder` directly.
- DO NOT change the 2MB size cap. Reuse `EmulatorController::MAX_SAVE_DATA_BYTES`.
- DO NOT remove the `clear-save` Stimulus controller file — repurpose / rewire if needed; the DELETE endpoint still serves it.
- DO NOT touch `EmulatorController#firmware`, `app/services/soul_link/save_parser.rb` core constants, or any GameState / cheats / discord_authentication code.
- Authorization: `set_session` resolves the current player's own session via `current_user_id`. There is NO admin / cross-player path here. A player CANNOT view or modify another player's slots — verify in tests.

### Acceptance Criteria

- 263 → ~290 tests passing (rough estimate: +25 new across model, controller, callback). 0 failures.
- Migration runs cleanly on prod data: existing save_data + parsed_* end up in slot 1 with `active_save_slot = 1`.
- After deploy, the existing players' `/emulator` page shows their slot 1 populated with their last save's parsed metadata; slots 2-5 empty.
- Clicking EmulatorJS "Save File" with empty slots: saves to next empty, toast "Saved to slot N", slot card updates.
- Clicking EmulatorJS "Save File" with all 5 full: banner appears in left column "All slots full — click a slot to overwrite". Clicking a slot card overwrites it and clears the banner.
- Per-slot Download produces a `.sav` named `pokemon-platinum-slot<N>.sav`.
- Make Active changes the highlighted slot; toast says "Slot N is active. Refresh to load it." After hard-refresh, the emulator boots from that slot.
- Delete clears the slot (back to "Empty"); if it was active, no slot is now active and the page falls back to "Not started" semantics on next refresh.
- Clear Save Data button (now in slot column or repurposed) wipes all slots.
- Cross-player attempt: a player who tries `GET/POST/PATCH/DELETE /emulator/save_slots/...` while not logged in as the slot's session owner gets 404 (session resolves to nil).

### Files Bob Should Read

- `app/controllers/emulator_controller.rb` (existing patterns)
- `app/models/soul_link_emulator_session.rb` (GzipCoder location, existing callbacks)
- `app/views/emulator/_run_sidebar.html.erb` (style and structure to mirror)
- `app/views/emulator/show.html.erb` (current layout)
- `app/javascript/controllers/emulator_controller.js` (current SRAM upload flow)
- `app/javascript/controllers/clear_save_controller.js` (DELETE flow pattern)
- `app/jobs/soul_link/parse_save_data_job.rb` (current parse flow — needs adapting)
- `db/schema.rb` (current shape)
- One existing migration in `db/migrate/` for style reference

DO NOT load the entire EmulatorJS source again. The save event lifecycle is already documented — `EJS_onSaveSave` handler unchanged in shape, only the URL it POSTs to changes.

### Files Bob Should Update at the End

- `handoff/REVIEW-REQUEST.md` — files-changed table with line ranges, self-review answers, open questions
- `handoff/BUILD-LOG.md` — Step History entry for Step 3 (status: Awaiting review)

---

## Notes for Reviewer

When this lands on your desk, focus on:

1. **Migration idempotency and data preservation.** Verify the raw-SQL INSERT preserves gzipped bytes byte-for-byte (no double-gzip). Consider running `db:migrate:status` mental-check of the order: create table → migrate data → drop columns. A failure mid-way must not leave the schema in a partially-broken state.
2. **Authorization** — every `SaveSlotsController` action must scope by `current_user_id`. A logged-in player CANNOT touch another player's slots, even by manipulating `slot_number` or the URL. Confirm with a test.
3. **`active_save_slot` consistency.** When a slot is destroyed, the pointer must clear. When a slot is overwritten, the pointer should update (it's the most-recently-saved). When a slot is "made active", the pointer should change without mutating any bytes.
4. **The 409 → overwrite-click round-trip.** Verify the bytes the user attempted to save actually make it into the chosen slot. Approach 2 from the brief calls `getSaveFile()` again on the emulator at click time — that's a fresh flush, so the SRAM at overwrite-click may differ slightly from the SRAM at original Save File click (a few seconds of drift). Project Owner accepts this; document the behavior in a comment but don't try to "preserve" the original bytes.
5. **No auto-tick re-introduction.** The brief explicitly forbids periodic save triggers. If Builder added any setInterval / setTimeout that fires save logic, that's a Condition.
6. **Layout regression risk.** Verify the three-column grid still degrades gracefully on narrow viewports (the right column already had a wrap fix; confirm the left column doesn't reintroduce the issue).

Out-of-scope items found during review → BUILD-LOG Known Gaps. Do not bundle.
