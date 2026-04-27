# Architect Brief
*Written by Architect. Read by Builder and Reviewer.*
*Overwrite this file each step — it is not a log, it is the current active brief.*

---

## Step 5 — Player-Facing Emulator (Routes + Controller + View + Stimulus)

Context: Steps 1–4 built the data layer, ROM generation, the asset task, and the run-creator trigger. Now players need a page where they visit `/emulator`, get auto-assigned an unclaimed ROM, and play it in the browser. This step is the consumer side — three-state UI, ROM streaming, save round-trip via PATCH.

This is a **larger step** than the previous ones. Brief is detailed to compensate.

### Files to Create

- `app/controllers/emulator_controller.rb`
- `app/views/emulator/show.html.erb`
- `app/javascript/controllers/emulator_controller.js`
- `test/controllers/emulator_controller_test.rb`

### Files to Modify

- `config/routes.rb` — add `resource :emulator do ... end`
- `app/views/layouts/application.html.erb` — add "Play" link to the existing nav (find the nav, match the link style)

### Routes

```ruby
resource :emulator, only: [:show] do
  get   :rom
  get   :save_data
  patch :save_data
end
```

Generates:
- `GET /emulator` — `EmulatorController#show`
- `GET /emulator/rom` — `EmulatorController#rom`
- `GET /emulator/save_data` — `EmulatorController#save_data` (split via HTTP method)
- `PATCH /emulator/save_data` — `EmulatorController#save_data`

### Controller — `app/controllers/emulator_controller.rb`

```ruby
class EmulatorController < ApplicationController
  include DiscordAuthentication
  before_action :require_login
  before_action :set_run
  before_action :set_session, only: [:show, :rom, :save_data]
  protect_from_forgery with: :null_session, only: [:save_data], if: -> { request.patch? }

  def show
    # Renders three states:
    #   - @run.nil? -> "No active run" message
    #   - @run.emulator_status == :none -> "ROMs haven't been generated yet" message
    #   - @session.nil? -> "All ROMs claimed by other players" (no unclaimed available)
    #   - @session.status == "generating" || "pending" -> "Your ROM is being generated, refresh shortly"
    #   - @session.status == "failed" -> "ROM generation failed: <error>"
    #   - @session.status == "ready" -> full emulator UI
  end

  def rom
    return head :not_found unless @session&.ready? && @session.rom_full_path&.exist?
    send_file @session.rom_full_path, type: "application/octet-stream", disposition: "attachment", filename: "rom.nds"
  end

  def save_data
    if request.patch?
      blob = request.body.read
      @session.update!(save_data: blob)
      head :no_content
    else  # GET
      data = @session&.save_data
      return head :no_content if data.blank?
      send_data data, type: "application/octet-stream", disposition: "attachment", filename: "save.dat"
    end
  end

  private

  def set_run
    @run = SoulLinkRun.current(session[:guild_id])
  end

  def set_session
    return @session = nil if @run.nil? || @run.emulator_status == :none

    # Find player's claimed session, or auto-claim the first unclaimed one.
    @session = @run.soul_link_emulator_sessions.find_by(discord_user_id: current_user_id)
    return if @session

    unclaimed = @run.soul_link_emulator_sessions.unclaimed.ready.first
    return @session = nil if unclaimed.nil?  # all claimed, none left

    begin
      unclaimed.claim!(current_user_id)
      @session = unclaimed
    rescue SoulLinkEmulatorSession::AlreadyClaimedError
      # Race: another request claimed this one between our SELECT and UPDATE.
      # Retry once with a fresh query.
      retry_unclaimed = @run.soul_link_emulator_sessions.unclaimed.ready.first
      if retry_unclaimed
        retry_unclaimed.claim!(current_user_id)
        @session = retry_unclaimed
      else
        @session = nil
      end
    end
  end
end
```

**Auth notes:**
- `require_login` is for HTML; if save_data PATCH ever goes off the page (it won't here), you'd need `require_login_json`. For this step, the user is authenticated via the same session cookie that loaded `/emulator`, so `require_login` is fine.
- `protect_from_forgery with: :null_session, only: [:save_data], if: -> { request.patch? }` is the standard Rails escape for binary-body API endpoints. The Stimulus controller sends the CSRF token in a header anyway — both should be belt-and-suspenders.

**Auto-claim race:** If two requests for the same player hit at the same instant (unlikely but possible — page reload + Stimulus connect), the SQL-level `claim!` ensures only one wins; the loser retries. After retry, if all are claimed, `@session = nil` and the view shows "All ROMs claimed."

### View — `app/views/emulator/show.html.erb`

Three-state ERB. Use raw CSS vars (`--d1`, `--d2`, `--border-thin`, etc.) — no Tailwind utilities. Match the GB aesthetic of `app/views/runs/index.html.erb`.

```erb
<% if @run.nil? %>
  <div class="emulator-message panel">
    <h2>No active run</h2>
    <p>Start a new run from the runs page to play.</p>
    <%= link_to "Go to runs", runs_path, class: "gb-btn-primary" %>
  </div>

<% elsif @run.emulator_status == :none %>
  <div class="emulator-message panel">
    <h2>ROMs not generated yet</h2>
    <p>The run creator needs to click "Generate Emulator ROMs" on the runs page first.</p>
    <%= link_to "Go to runs", runs_path, class: "gb-btn-primary" %>
  </div>

<% elsif @session.nil? %>
  <div class="emulator-message panel">
    <h2>No ROM available</h2>
    <p>All four ROMs have been claimed by other players. Contact the run creator if this looks wrong.</p>
  </div>

<% elsif @session.status == "pending" || @session.status == "generating" %>
  <div class="emulator-message panel" data-controller="emulator-pending">
    <h2>ROM generating…</h2>
    <p>Your randomized Pokemon Platinum ROM is being prepared. Refresh in a moment.</p>
  </div>

<% elsif @session.status == "failed" %>
  <div class="emulator-message panel">
    <h2>ROM generation failed</h2>
    <p>The randomizer reported: <%= @session.error_message.presence || "(no details)" %></p>
    <p>Tell the run creator to regenerate the ROMs.</p>
  </div>

<% else  # ready %>
  <div class="emulator-stage"
       data-controller="emulator"
       data-emulator-rom-url-value="<%= rom_emulator_path %>"
       data-emulator-save-data-url-value="<%= save_data_emulator_path %>"
       data-emulator-csrf-value="<%= form_authenticity_token %>"
       data-emulator-core-value="<%= EmulatorController::EMULATOR_CORE %>"
       data-emulator-pathtodata-value="/emulatorjs/data/">
    <div id="game" data-emulator-target="game"></div>
  </div>
<% end %>
```

**Required constants:** put `EMULATOR_CORE = "melonds"` (or `"desmume"`) at the top of `EmulatorController`. **Bob: read `public/emulatorjs/data/cores/` to confirm which DS core ships in v4.2.3 and use the actual core name.** If both ship, prefer melonDS (more accurate). If neither, stop and report.

### Stimulus — `app/javascript/controllers/emulator_controller.js`

EmulatorJS uses `window.EJS_*` globals + a `<script>` tag pointing at `loader.js`. The Stimulus controller's job is to (a) set those globals, (b) inject the loader script, (c) wire up save round-trip.

```js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    romUrl: String,
    saveDataUrl: String,
    csrf: String,
    core: String,
    pathtodata: String
  }

  static targets = ["game"]

  async connect() {
    // 1. Fetch existing save (if any) so EmulatorJS can boot with state.
    const save = await this._fetchSave()

    // 2. Configure EmulatorJS globals BEFORE injecting the loader.
    window.EJS_player = "#" + this.gameTarget.id
    window.EJS_gameUrl = this.romUrlValue
    window.EJS_core = this.coreValue
    window.EJS_pathtodata = this.pathtodataValue
    window.EJS_startOnLoaded = true
    window.EJS_Buttons = { /* keep defaults — don't customize until we need to */ }

    if (save) {
      // EmulatorJS expects a Uint8Array via EJS_loadStateURL or similar.
      // Bob: check EmulatorJS v4.2.3 docs in public/emulatorjs/ for the exact hook.
      // The currently expected API is window.EJS_loadStateURL = this.saveDataUrlValue
      // OR providing the bytes directly. Verify and pick whichever is more reliable.
      window.EJS_loadStateURL = this.saveDataUrlValue
    }

    // 3. Wire save callback. EmulatorJS fires window.EJS_onSaveState (or similar) with bytes.
    window.EJS_onSaveState = ({ screenshot, state }) => this._uploadSave(state)

    // 4. Inject loader script.
    const script = document.createElement("script")
    script.src = this.pathtodataValue + "loader.js"
    document.body.appendChild(script)
  }

  disconnect() {
    // Best-effort cleanup. EmulatorJS doesn't have a clean teardown API in v4 —
    // a full page nav handles it.
    window.EJS_player = undefined
    window.EJS_gameUrl = undefined
    window.EJS_onSaveState = undefined
  }

  async _fetchSave() {
    const res = await fetch(this.saveDataUrlValue, {
      method: "GET",
      headers: { "Accept": "application/octet-stream" },
      credentials: "same-origin"
    })
    if (res.status === 204) return null
    if (!res.ok) {
      console.error("Failed to load save:", res.status)
      return null
    }
    const buf = await res.arrayBuffer()
    return buf.byteLength > 0 ? new Uint8Array(buf) : null
  }

  async _uploadSave(stateBytes) {
    const blob = stateBytes instanceof Uint8Array ? stateBytes : new Uint8Array(stateBytes)
    const res = await fetch(this.saveDataUrlValue, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/octet-stream",
        "X-CSRF-Token": this.csrfValue
      },
      credentials: "same-origin",
      body: blob
    })
    if (!res.ok) {
      console.error("Failed to save:", res.status)
    }
  }
}
```

**Bob: the EmulatorJS save-callback name is uncertain across versions.** v4.2.3's docs are in `public/emulatorjs/docs/` (Step 3 installed them). Read those before settling on `EJS_onSaveState`. If the actual hook differs, use the real one and document the choice in REVIEW-REQUEST.

### Layout — Add "Play" Link

Find the nav bar in `app/views/layouts/application.html.erb`. There's an existing nav with links to runs/dashboard/etc. Add a sibling link to `/emulator` matching the existing style. Don't reformat anything else.

If the nav uses `Current.user`-style helpers or session checks, gate the Play link the same way (only show when logged in).

### Tests — `test/controllers/emulator_controller_test.rb`

Use FactoryBot.

Cover:

- **Auth** — unauthenticated → redirect to login (or 401, whatever existing controllers do; check `dashboard_controller_test.rb` for the convention).
- **show: no active run** — guild has no active run; renders the "No active run" view; status 200.
- **show: emulator_status == :none** — active run exists, no sessions yet; renders "ROMs not generated yet"; status 200.
- **show: all claimed, none unclaimed** — 4 sessions all claimed by other players; renders "No ROM available"; status 200.
- **show: auto-claims first unclaimed** — visiting player has no claimed session, 4 unclaimed exist; after request, exactly one session has `discord_user_id == current_user_id`. Verify session count unchanged.
- **show: already claimed, status pending** — renders "ROM generating…"; status 200.
- **show: already claimed, status failed** — renders "ROM generation failed"; status 200; error_message visible.
- **show: already claimed, status ready** — renders the emulator stage; status 200; response body contains `data-controller="emulator"`.
- **show: claim race** — simulate `AlreadyClaimedError` on first attempt (stub or use a real race), confirm retry path picks up another unclaimed session.
- **rom: not ready** — session.status != "ready" → 404.
- **rom: ready, file missing** — rom_full_path doesn't exist on disk → 404 (defensive).
- **rom: ready, file present** — returns 200, `Content-Type: application/octet-stream`, body matches the file bytes. Use `Tempfile` or stub `send_file` to avoid real fs writes.
- **save_data GET: empty** — session.save_data nil → 204 No Content.
- **save_data GET: present** — returns 200, body matches the bytes.
- **save_data PATCH: writes the body** — POST a Uint8Array-equivalent String, assert `session.reload.save_data == sent_bytes`.
- **save_data PATCH: csrf bypass works** — without the CSRF token but with valid session, PATCH still succeeds (because of `protect_from_forgery with: :null_session`). Verify.

Don't add Stimulus tests — JS unit testing isn't set up in this project.

### Build Order

1. Read `public/emulatorjs/data/cores/` to confirm DS core name (`melonds` vs `desmume`). Read `public/emulatorjs/docs/` to confirm the save-callback API.
2. Add the route block to `config/routes.rb`.
3. Create `EmulatorController` skeleton with all 5 actions and the `set_run` / `set_session` before_actions.
4. Create the view with all six rendered states.
5. Add the "Play" link to the layout nav.
6. Create the Stimulus controller. Read existing controllers (`run_management_controller.js`, `quick_calc_controller.js`) for style.
7. Write controller tests. Run them: `mise exec -- ruby -S bundle exec rails test test/controllers/emulator_controller_test.rb`. Iterate to green.
8. Run full suite: `mise exec -- ruby -S bundle exec rails test`. Confirm 146 + new tests, 0 failures.
9. **Browser verification (best effort):** if you can't run a real browser, write a code-trace describing what would happen end-to-end. Be explicit about what the user will need to verify locally:
   - `/emulator` shows the right state for each user × run combination
   - The actual EmulatorJS canvas loads and the game runs
   - Save game persists across refresh

### Flags

- Flag: **No real ROM file writes in tests.** Stub `send_file` or use `Tempfile`. CI doesn't have ROMs.
- Flag: **No real save_data fetches in tests.** Use FactoryBot to set `save_data` directly on the session.
- Flag: **CSRF: `null_session` bypass for PATCH only**, scoped via `if: -> { request.patch? }`. Don't blanket-disable CSRF.
- Flag: **`current_user_id` is bigint** (locked architecture decision). Pass it directly to `claim!` — no String coercion.
- Flag: **Use FactoryBot** for all test data.
- Flag: **`emulator_path` and `rom_emulator_path` / `save_data_emulator_path`** — Rails generates these from the `resource :emulator` block. Use them via the `_path` helpers in views.
- Flag: **Don't add a controller for the "playing" presence broadcast.** That was the multiplayer step we dropped. Keep the player UI single-player.
- Flag: **Bob can't drive a browser.** That's expected. Provide the code-trace + write the user a clear "what to verify locally" checklist in REVIEW-REQUEST.
- Flag: **EmulatorJS API may differ from the brief's assumptions.** If the save callback isn't `EJS_onSaveState` or the core isn't `melonds`, use what's actually documented in `public/emulatorjs/docs/`. Don't guess. If the docs are unhelpful, stop and flag.
- Flag: All Rails commands prefixed `mise exec -- ruby -S bundle exec`.
- Flag: Do NOT commit. Architect commits.

### Definition of Done

- [ ] Routes added; `rake routes | grep emulator` shows all 4 endpoints
- [ ] `EmulatorController` exists with all 5 actions, before-actions, and the auto-claim race-retry logic
- [ ] `app/views/emulator/show.html.erb` renders all six states correctly
- [ ] "Play" link added to layout nav
- [ ] `app/javascript/controllers/emulator_controller.js` configures EmulatorJS, handles save round-trip, uses CSRF correctly
- [ ] Controller tests cover: auth, all six show-states, auto-claim happy path + race retry, rom 404 + 200, save_data GET 204 + 200, save_data PATCH writes correctly, CSRF bypass works
- [ ] Full suite: 146 baseline + new tests, 0 failures
- [ ] EmulatorJS core name + save callback verified against `public/emulatorjs/data/` and `public/emulatorjs/docs/`
- [ ] REVIEW-REQUEST includes a "What to verify in browser" checklist for the user

---

## Builder Plan
*Builder adds their plan here before building. Architect reviews and approves.*

1. **Core**: `EMULATOR_CORE = "melonds"`. Source: `data/src/GameManager.js` line 26 maps system `"nds"` → `["melonds", "desmume", "desmume2015"]` (first = preferred). Cores download dynamically at runtime; `data/cores/` ships empty templates only.
2. **Save callback**: deviating from brief — using `EJS_onSaveSave` (event payload `{screenshot, format, save}`) instead of `EJS_onSaveState`. The brief's hook captures *save states* (RetroArch snapshots); `onSaveSave` captures the actual SRAM the player writes via in-game "Save". Confirmed in `data/loader.js` lines 162-167 and `data/src/emulator.js` line 1954. For preload, no `loadSaveURL` config exists — instead I'll fetch save bytes on `connect()`, then inject into the emulator FS inside the `EJS_ready` hook via `gameManager.FS.writeFile(getSaveFilePath(), bytes)` + `loadSaveFiles()`.
3. **Controller** matches brief verbatim including race-retry. CSRF: `null_session` only on PATCH.
4. **Tests**: 16 cases per the brief's list, FactoryBot, stub `send_file` / use Tempfile. Race test uses Minitest::Mock to throw `AlreadyClaimedError` on the first `claim!`.
5. **Stimulus**: configures globals → `EJS_onSaveSave` → injects loader script. JS not unit tested. Browser verification = code-trace + checklist for user.

