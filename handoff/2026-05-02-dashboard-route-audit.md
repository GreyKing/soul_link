# Dashboard Route + Action Audit
*2026-05-02 · Architect (Ava) · Investigation only — no code changes in this turn.*
*Pair this with `handoff/2026-05-01-gym-draft-audit.md` (the prior, deeper draft-flow audit).*

The Step 14.1 hotfix exposed a class of bug: `button_to ... data: { turbo: false }` posting to a controller that returns JSON-only causes the browser to render the JSON body as page text. This audit walks every reachable button / link / form / fetch on the dashboard and dashboard-adjacent surfaces (Map, Emulator, Runs, Species, Teams, Gym Drafts, Gym Schedules, Sessions) and flags any other instance of the same class — plus broken links, orphaned routes, and post-action redirects that lose tab state the same way Step 14.1 just fixed.

**Methodology.** Inventoried every `button_to` / `link_to` / `<form>` / `<a href>` in `app/views/**`, every `fetch()` and `subscription.perform()` in `app/javascript/controllers/**`, every `def` and `render`/`redirect_to`/`head` in `app/controllers/**`. Cross-referenced routes against caller surfaces. Walked each `data: { turbo: false }` form to its controller's final response.

**Headline.** No 🔴 dead-ends remain after Step 14.1. Four 🟡 findings — three are the same "Gyms tab not preserved across reload" pattern Step 14.1 partially fixed but didn't fully sweep; one is a redirect to a path with no GET handler. Several 🟢 confirmations.

---

## 🔴 Broken / dead-ends user

**None.** Step 14.1's fix to `GymProgressController#update` was the only verified dead-end (JSON body rendering as page text). No other button/form on the dashboard has the same combination of `data: { turbo: false }` + JSON-only controller response.

---

## 🟡 Weird but recoverable

### 🟡 1. `gym_drafts#mark_beaten` redirects to `root_path` without `#gyms` anchor

**Location:** `app/controllers/gym_drafts_controller.rb:100`

```ruby
redirect_to root_path, notice: "Gym #{gym_number} marked as beaten!"
```

**Trigger:** completing a draft → MARK GYM N AS BEATEN button on `gym_drafts/show.html.erb:158-165`.

**Outcome:** user is sent to `/` and lands on the default PC BOX tab, not the Gyms tab they were heading toward to see their newly-earned badge. Same class as the bug Step 14.1 fixed for `gym_progress#update`, but a different controller — Step 14.1 only patched the dashboard's MARK BEATEN/UNMARK buttons, not the draft's MARK BEATEN.

**One-line fix:** `redirect_to root_path(anchor: "gyms"), notice: ...` (the `pixeldex_controller.js#applyHashTab()` Step 14.1 added picks it up).

### 🟡 2. `dashboard_controller.js#confirmResetDraft` reloads without setting hash

**Location:** `app/javascript/controllers/dashboard_controller.js:165`

```js
if (response.ok) {
  window.location.reload()
}
```

**Trigger:** RESET DRAFT button on the Gyms tab (`_gyms_content.html.erb:9-13`) → modal → CONFIRM RESET → fetch DELETE `/gym_drafts/:id` → success → reload.

**Outcome:** page reload defaults to PC BOX tab, losing the user's Gyms-tab context after they explicitly performed a Gyms-tab action.

**Two-line fix:** before reload, set `window.location.hash = "gyms"` (or replace with `window.location.assign("/#gyms")`). The `applyHashTab()` Step 14.1 added handles the rest.

### 🟡 3. `gym_backfill_controller.js` reloads without setting hash

**Location:** `app/javascript/controllers/gym_backfill_controller.js:93`

```js
window.location.reload()
```

**Trigger:** + ADD TEAM button on `_gyms_content.html.erb:102` (only renders on a defeated gym row that has a `gym_result` without a `team_snapshot`) → backfill picker → submit → fetch PATCH `/gym_results/:id` → success → reload.

**Outcome:** same as #2 — Gyms-tab user backfilling a missing team snapshot lands on PC BOX after.

**Two-line fix:** identical to #2.

### 🟡 4. `gym_drafts#mark_beaten` redirects to `gym_drafts_path` which has no GET handler

**Location:** `app/controllers/gym_drafts_controller.rb:75`

```ruby
unless draft&.complete?
  redirect_to gym_drafts_path, alert: "Draft is not complete."
  return
end
```

**Why it's broken:** `routes.rb:36` declares `resources :gym_drafts, only: [ :create, :show, :destroy ]` — there is **no `:index`**. `gym_drafts_path` resolves to `/gym_drafts`, which has a POST handler (create) but no GET. A `redirect_to` always issues a GET, so this lands the user on a `No route matches [GET] "/gym_drafts"` (`ActionController::RoutingError` in dev, 404 in prod).

**Trigger:** an incomplete-draft state hitting `mark_beaten`. The UI gates the button on `@draft.complete?` (`gym_drafts/show.html.erb:158`), so this branch is unreachable from the happy path — but a direct curl, a stale form submission, or a state-machine race can hit it.

The other two `redirect_to gym_draft_path(draft), alert: ...` branches in the same controller (lines 81, 87, 102) all redirect to the SHOW route (singular), which IS defined. Only line 75 uses the plural `gym_drafts_path`.

**One-line fix:** change to `redirect_to root_path(anchor: "gyms"), alert: "Draft is not complete."` — or `redirect_to gym_draft_path(draft), alert: ...` if the draft is loaded by then (it is — line 73 sets `draft = run.gym_drafts.find_by(id: params[:id])` and the guard is `draft&.complete?`, so `draft` may be nil when the redirect fires; only `root_path` is unconditionally safe here).

---

## 🟢 Working as designed (audit confirmations)

These were inspected and pass — listing for completeness so anyone re-running this audit doesn't re-investigate them.

### Forms with `data: { turbo: false }` (the dangerous pattern)

| Form | Posts to | Controller response | Verdict |
|---|---|---|---|
| `_gyms_content.html.erb:49` MARK BEATEN | `gym_progress#update` | content-type-branched after Step 14.1 (HTML→redirect, JSON→json) | ✅ |
| `_gyms_content.html.erb:64` UNMARK | `gym_progress#update` | same | ✅ |
| `sessions/new.html.erb:7` Discord login | `/auth/discord` (OmniAuth) | full-page navigation to Discord OAuth — `turbo: false` is correct here | ✅ |

No other `data: { turbo: false }` instances anywhere in `app/views/`.

### Forms WITHOUT `turbo: false` (Turbo Drive handles → controller redirects → fine)

| Form | Posts to | Controller response | Verdict |
|---|---|---|---|
| `_gyms_content.html.erb:5` START GYM DRAFT | `gym_drafts#create` | `redirect_to gym_draft_path(draft)` | ✅ |
| `gym_ready/show.html.erb:7` START GYM DRAFT | `gym_drafts#create` | same | ✅ |
| `gym_drafts/show.html.erb:158` MARK GYM N AS BEATEN | `gym_drafts#mark_beaten` | `redirect_to root_path` (see 🟡 #1) | works but loses tab |
| `gym_schedules/index.html.erb:19` PROPOSE A GYM DAY | `gym_schedules#create` | `redirect_to gym_schedule_path(schedule)` | ✅ |
| `application.html.erb:49` Logout | `sessions#destroy` | `redirect_to login_path` | ✅ |

### JSON XHR endpoints (consumed by `fetch()` — JSON-only is correct)

All verified: each route is consumed by a real JS caller that handles the JSON response.

| Route | Consumer | Response shape |
|---|---|---|
| `POST /pokemon_groups` | `dashboard_controller.js:51` (catch modal) | JSON ✅ |
| `PATCH /pokemon_groups/:id` | `pixeldex_controller.js:126` (status changes) | JSON ✅ |
| `DELETE /pokemon_groups/:id` | `species_assignment_controller.js:221` | JSON ✅ |
| `PATCH /pokemon_groups/reorder` | `species_assignment_controller.js:288` | JSON ✅ |
| `POST /pokemon` | `pixeldex_controller.js:344` | JSON ✅ |
| `PATCH /pokemon/:id` | `pixeldex_controller.js:330,398` (save + evolve) | JSON ✅ |
| `PATCH /team` (update_slots) | `team_builder_controller.js:75` | JSON ✅ |
| `PATCH /species/assign` | `species_assignment_controller.js:179` | JSON ✅ |
| `PATCH /species/assign_from_pokedex` | `species_assignment_controller.js:339` | JSON ✅ |
| `PATCH /species/unassign` | `species_assignment_controller.js:245` | JSON ✅ |
| `PATCH /gym_results/:id` | `gym_backfill_controller.js:86` | JSON ✅ |
| `DELETE /gym_drafts/:id` | `dashboard_controller.js:156` (RESET DRAFT modal) | JSON ✅ |
| `PATCH /gym_progress` (JSON path) | `timeline_controller.js:342` (map page) | JSON ✅ |
| `POST /api/calculator` | `quick_calc_controller.js:123`, `full_calc_controller.js:159,299` | JSON ✅ |
| `GET /api/pokemon/:species` | `quick_calc_controller.js:151`, `full_calc_controller.js:299` | JSON ✅ |
| `GET /emulator/save_slots` | `save_slots_controller.js` initial load | JSON ✅ |
| `POST /emulator/save_slots` | `emulator_controller.js:228` | JSON ✅ |
| `PATCH /emulator/save_slots/:n` | `save_slots_controller.js:148` | JSON ✅ |
| `DELETE /emulator/save_slots/:n` | `save_slots_controller.js:71` | `head :no_content` ✅ |
| `POST /emulator/save_slots/:n/restore` | `save_slots_controller.js:48` | `head :no_content` ✅ |
| `DELETE /emulator/save_data` | `clear_save_controller.js:23` (wipe-all) | `head :no_content` ✅ |

All consumers handle the JSON contract or `head :no_content`. None of these are reachable via an HTML form — no JSON-as-page risk.

### ActionCable channels (no HTTP, out of "JSON-as-page" bug class)

- `RunChannel` — `start_run`, `end_run`, `setup_discord`, `generate_emulator_roms`, `regenerate_emulator_roms`. Consumed by `run_management_controller.js`. Channel broadcasts back; no redirect concept. ✅
- `GymDraftChannel` — `ready`, `vote`, `pick`, `nominate`, `skip`. Consumed by `gym_draft_controller.js`. ✅
- `GymScheduleChannel` — `rsvp`, `cancel`. Consumed by `gym_schedule_controller.js`. ✅

### Route inventory (no orphans)

Every route in `config/routes.rb` is referenced from at least one view or JS surface. Cross-referenced 35+ named routes against view path helpers and JS hardcoded URLs — zero orphans.

### Auth

`before_action :require_login` is consistent across every controller that needs it. `current_run` lookups go through `SoulLinkRun.current(session[:guild_id])`, which Step 11 made guaranteed-unique-or-nil at the DB level.

### Tab persistence (the post-Step-14.1 surface area)

The `pixeldex_controller.js#applyHashTab()` private method (added in Step 14.1) reads `window.location.hash` on `connect()` and clicks the matching tab button. Any redirect or reload that wants the user to land on a non-default tab can do so by including the anchor:

- Server-side: `redirect_to root_path(anchor: "gyms")` — the GymProgressController does this after Step 14.1.
- Client-side: set `window.location.hash = "gyms"` before `window.location.reload()`, OR use `window.location.assign("/#gyms")`.

The three 🟡 findings above (#1, #2, #3) are all this same pattern that just hasn't been retrofitted yet.

---

## What's NOT in this audit

- **Map page reloads** (`timeline_controller.js:358` after gym toggle) — different layout, no tab system. Out of "JSON-as-page" bug class. The reload is preceded by a sessionStorage scroll save (line 356), so scroll position is preserved.
- **Emulator page reloads** — different layout. The save-slot flow uses targeted DOM updates, not full reloads. Verified working.
- **`pixeldex_controller.js#savePokemon` / `submitCatch` / `confirmMarkDead` reloads** — all triggered from the PC BOX tab, all reload to PC BOX (the default), so the "wrong tab" issue doesn't apply.
- **Discord bot** (`lib/tasks/soul_link.rake`, `app/services/soul_link_bot/`) — separate process, no web routes.
- **Channel-side auth edge cases** — covered in the prior gym-draft audit at `handoff/2026-05-01-gym-draft-audit.md`.

---

## Recommendation

All four 🟡 findings are small. They could ship as one hotfix step (call it Step 14.2) — total diff is ~6 lines:

| Finding | Lines changed |
|---|---|
| #1 — `gym_drafts#mark_beaten` add anchor | 1 |
| #2 — `confirmResetDraft` set hash | 2 |
| #3 — `gym_backfill_controller` set hash | 2 |
| #4 — `gym_drafts#mark_beaten` line 75 fix | 1 |

Plus minimal regression tests:
- `gym_drafts_controller_test.rb`: assert mark_beaten redirects to `root_path(anchor: "gyms")` on success; assert the line-75 incomplete-draft branch redirects somewhere routable (currently it would hit a routing error in dev — easy to test).
- The two JS reloads don't lend themselves to unit tests (they're side effects); rely on manual smoke for those.

Or split into two: server-side fixes (#1, #4) as a small Rails hotfix, JS fixes (#2, #3) as a separate small JS hotfix. Either way, low risk.

Once you pick, I'll write a tight Step 14.2 brief and send Bob in.
