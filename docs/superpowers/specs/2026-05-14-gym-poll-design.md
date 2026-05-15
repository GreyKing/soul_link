# Gym Poll — Design Spec

**Date:** 2026-05-14
**Status:** Approved (brainstorming complete; ready for implementation planning)
**Replaces:** The existing `GymSchedule` single-time RSVP feature

## Problem

The team currently coordinates gym battles through `GymSchedule`: a single proposed datetime, one RSVP (yes/maybe/no) per player, auto-confirmed when all four say yes. In practice the team wants to negotiate over **multiple candidate times** each week and have the system pick a winner once everyone agrees on a slot. The client phrased it as:

> "we want to be able to schedule/sign up for a new gym run from discord or from the site. were thinking something like setup a weekly poll or vote. Pop it into a discord channel. We tally the votes and send out a ping for the time/date we decided to do a gym run. Resets after we meet/when we click a button"

This spec replaces `GymSchedule` with a multi-slot poll model.

## Confirmed Requirements

| # | Requirement |
|---|---|
| R1 | Polls have multiple candidate slots; players vote yes/maybe/no on each |
| R2 | A slot "wins" (locks) only when **all 4 players say yes** on it |
| R3 | When a slot locks, a ping with @-mentions is posted to the run's `#general` Discord channel |
| R4 | Slots come from a **per-run weekly template** (e.g., Mon 7pm / Wed 8pm / Sat 2pm) editable from the dashboard |
| R5 | Template materializes for the **current Mon–Sun calendar week** in the run's timezone; if today is Sunday, rolls forward to the next Mon–Sun |
| R6 | Polls reset **manually only** — no auto-rollover. No-winner state stays open until reset |
| R7 | Polls are creatable from both the website and Discord (`/new_gym_poll` slash command) |
| R8 | Polls are generic "next meetup" — not bound to a specific gym |
| R9 | Anyone (any of the 4 players) can reset a poll |

## Architecture

### Data model

Two schema changes plus the retirement of `gym_schedules`.

**(a) Drop `gym_schedules`; add `gym_polls`.**

```ruby
create_table :gym_polls do |t|
  t.references :soul_link_run, null: false, foreign_key: true
  t.references :gym_draft,     null: true,  foreign_key: true
  t.string  :status, null: false, default: "open"   # open | locked
  t.bigint  :discord_message_id
  t.integer :locked_slot_index                       # NULL until a slot wins
  t.datetime :locked_at                              # NULL until a slot wins
  t.datetime :pinged_at                              # NULL until ping fired; idempotency guard
  t.json    :state_data, null: false                 # slots + votes
  t.timestamps
end
add_index :gym_polls, [:soul_link_run_id, :status]
```

`state_data` shape:

```json
{
  "slots": [
    { "index": 0, "scheduled_at": "2026-05-16T21:00:00Z" },
    { "index": 1, "scheduled_at": "2026-05-19T02:00:00Z" },
    { "index": 2, "scheduled_at": "2026-05-21T03:00:00Z" }
  ],
  "votes": {
    "<player_uid>": { "0": "yes", "1": "no", "2": "maybe" }
  }
}
```

Slot indices (0..N) are stable for the life of the poll. Votes key off the index, not the datetime — changing a slot's datetime mid-poll is impossible by construction. The only way to "change slots" is to reset and create a new poll.

**(b) Extend `soul_link_runs` with `schedule_template` (JSON) and `timezone` (string).**

```ruby
add_column :soul_link_runs, :schedule_template, :json
add_column :soul_link_runs, :timezone, :string,
  null: false, default: "America/Phoenix"
```

Template shape:

```json
{
  "slots": [
    { "day_of_week": 1, "time_of_day": "19:00" },
    { "day_of_week": 3, "time_of_day": "20:00" },
    { "day_of_week": 6, "time_of_day": "14:00" }
  ]
}
```

`day_of_week` uses ISO 8601 weekday numbering: Monday = 1, Sunday = 7. `time_of_day` is `"HH:MM"` (24h) interpreted in the run's `timezone`.

`schedule_template` defaults to `nil`. Poll creation requires it to be set and non-empty.

### Retirement of `GymSchedule`

Removed entirely:

- `app/models/gym_schedule.rb`
- `app/controllers/gym_schedules_controller.rb`
- `app/channels/gym_schedule_channel.rb`
- `app/jobs/gym_schedule_discord_update_job.rb`
- `app/javascript/controllers/gym_schedule_controller.js`
- `app/views/gym_schedules/` (entire directory)
- The `resources :gym_schedules` line in `config/routes.rb`
- Discord bot handlers for `soul_link:gym_rsvp:*` custom IDs
- Any nav links pointing to `/gym_schedules`
- `test/models/gym_schedule_test.rb`, related controller/channel/job specs, and `test/factories/gym_schedules.rb`
- The `gym_schedules` table (via migration)
- `.claude/documents/gym-schedule.md` (or rewritten as `gym-poll.md`)

The team is in active testing; no production data needs migration. The migration drops the table outright.

## Lifecycle & State Machine

Two states:

```
       create poll                 all 4 yes on a slot
   ─────────────────►  OPEN  ───────────────────────────►  LOCKED
                       │  ▲                                    │
                       │  │                                    │
                       │  └──────────── reset ────────────────┘
                       │                (destroys row)
                       │
                       └─── reset ───► (poll destroyed, fresh slate)
```

**OPEN** — accepts vote changes from any player. After every vote, recomputes `all_yes?(slot_index)` for the touched slot; transitions to LOCKED if true.

**LOCKED** — `locked_slot_index` and `locked_at` set, ping fired exactly once on first entry (guarded by `pinged_at`), no further vote mutations accepted. Vote attempts return an error to the caller (channel/controller/bot). The poll still renders so the team can see the locked time until they reset.

**Reset** — destroys the row. Same effect from either state. To start the next poll, anyone runs `/new_gym_poll` (Discord) or clicks "Start poll" (dashboard), which creates a new row from the current `schedule_template`.

### Lifecycle edge cases

| Case | Handling |
|---|---|
| Slot already past at vote time | Vote rejected at the model level. Slot rendered grayed-out with "(passed)" label; vote buttons disabled. |
| All slots past | UI renders a banner: "All slots have passed. Reset to start next week's poll." Reset is the only available action. |
| Template empty when creation attempted | Refuses creation with "Configure your weekly slots on the dashboard first" + link to template editor. |
| Poll already exists when creation attempted | Refuses creation with "An open poll already exists — reset it first" + link to existing poll. |
| Lock job retried after transient Discord failure | `pinged_at` short-circuits the ping POST; embed PATCH is naturally idempotent (rebuilds from state). |

## Slot Materialization

Pure function from `(SoulLinkRun, now)` to an array of concrete slots.

```ruby
def self.materialize_slots(run, now: Time.current)
  raise EmptyTemplateError unless run.schedule_template&.dig("slots").present?

  tz       = ActiveSupport::TimeZone[run.timezone]
  zone_now = now.in_time_zone(tz)

  # Sunday rollover: if today is Sunday, the "current calendar week"
  # would already be ending — roll forward to next Mon-Sun.
  effective = zone_now.sunday? ? zone_now + 1.day : zone_now
  monday    = effective.beginning_of_week(:monday).to_date

  run.schedule_template["slots"].each_with_index.map do |slot, idx|
    target_date = monday + ((slot["day_of_week"].to_i - 1) % 7).days
    hour, min   = slot["time_of_day"].split(":").map(&:to_i)
    scheduled_at = tz.local(target_date.year, target_date.month, target_date.day, hour, min)
    { "index" => idx, "scheduled_at" => scheduled_at.utc.iso8601 }
  end
end
```

Lives on `GymPoll.materialize_slots` (class method) or in a `SoulLink::PollMaterializer` service object — implementer's call. It's pure and fully testable in isolation either way.

### Materialization edge cases (all covered by unit tests)

| Case | Expected behavior |
|---|---|
| Created Monday 6 AM | Mon 7 PM slot is in the future, included normally |
| Created Tuesday 8 PM | Mon 7 PM slot materialized but already past — `past: true` on render |
| Created Saturday afternoon | Weekday slots past, only Sat slot future |
| Created Sunday | Rolls forward to next Mon–Sun; new poll is fully forward-looking |
| Spring-forward DST week | `ActiveSupport::TimeZone#local` honors zone DST; 2 AM slot on the transition day shifts correctly |
| Fall-back DST week | Same — `local` resolves to the unambiguous post-transition time when needed |
| Empty template | Raises `EmptyTemplateError`; controller/bot convert to friendly user-facing error |
| Malformed template (non-int day, bad time) | Raises; same error path |

Note: Arizona (`America/Phoenix`) does not observe DST. DST tests still matter because the timezone is a per-run setting and a future run could be configured to a DST-observing zone.

## Web Surface

### Routes

Replaces the three `gym_schedules` routes:

```ruby
resource :gym_poll, only: %i[show create destroy], controller: "gym_polls" do
  post :vote, on: :member
end

# Extend the existing plural :runs resource (currently only: [:index])
resources :runs, only: %i[index edit update]   # template editor lives on edit
```

The existing `RunsController` (`app/controllers/runs_controller.rb`) currently only implements `index`; this spec extends it with `edit` and `update` actions for the schedule template + timezone form. The controller resolves which run to edit via the session's `guild_id` (matching the pattern in `GymSchedulesController#current_run`).

`DELETE /gym_poll` = reset (destroys the row). `POST /gym_poll` = start new poll from template. `GET /gym_poll` = show current poll or empty state. `POST /gym_poll/vote` = controller fallback if ActionCable isn't connected.

### Controller — `GymPollsController`

Mirrors the existing `GymSchedulesController` shape:

```ruby
class GymPollsController < ApplicationController
  before_action :require_login

  def show     # current poll OR "no active poll" empty state
  def create   # materialize slots from template, create row
  def destroy  # reset — destroys row
  def vote     # POST fallback for vote casting
end
```

`create` guards (each returns a user-friendly error):

1. Run exists for the current session's guild_id → else redirect with alert
2. `schedule_template` present and non-empty → else 422 with link to edit
3. No existing open/locked poll → else 409 with link to existing

### Views

- `app/views/gym_polls/show.html.erb` — full poll UI; loads full state, Stimulus controller subscribes to ActionCable and re-renders on each `state_update`. Same architectural pattern as `gym_draft_controller.js` / `gym_schedule_controller.js`.
- `app/views/gym_polls/_slot_card.html.erb` — one card per slot: datetime, 4 player chips with yes/maybe/no status, three vote buttons for the current user, past-slot disabled state.
- `app/views/gym_polls/_empty.html.erb` — "No active poll. [Start one]" + conditional link to template editor when template is empty.

### Dashboard — new "Schedule" tab

A new tab in `app/views/dashboard/_tab_bar.html.erb` and a corresponding `_schedule_content.html.erb` partial. The tab contains:

- **Current poll summary** (status, time slots, vote tallies) with a link to the full `/gym_poll` page
- **Weekly slot template editor**:
  - Timezone dropdown (offers common US zones + an "Other" text field)
  - Repeating slot rows: `[day-of-week dropdown] [time-of-day input] [remove]`
  - "Add slot" button (Stimulus-controlled, client-side row append, max 5 slots due to Discord button-row limits)
  - Save → `PATCH /run` updates `schedule_template` and `timezone`

### Status-rail tile

The existing dashboard status rail (`_status_rail.html.erb`) gains a tile summarizing the current poll state ("Open — 2 of 4 voted on Sat 2 PM" or "🔒 Locked: Sat 2 PM"), linking to `/gym_poll`. Matches the rail's existing tile pattern.

## Discord Surface

### Slash commands

| Command | Behavior |
|---|---|
| `/new_gym_poll` | Defers, validates (run / template / no-existing-poll), materializes slots, creates `GymPoll`, posts the poll message to the run's `general_channel_id`, stores `message.id` on `discord_message_id`. |
| `/reset_gym_poll` | Defers, finds the open poll, destroys it. Posts a confirmation in the channel ("Poll reset. Run `/new_gym_poll` to start the next one."). |

Both registered via `SoulLink::DiscordBot#register_commands` alongside existing commands.

### Poll message format

Single embed with one field per slot, plus button rows below. Example with 3 slots:

```
🗓️  Gym Poll — Week of May 11

Sat 2:00 PM   ✅ Riley   ✅ Marin   ❓ Casey   ⬜ Quinn   (2 yes / 1 maybe / 0 no / 1 pending)
Mon 7:00 PM   ✅ Riley   ❌ Marin   ✅ Casey   ✅ Quinn   (3 yes / 0 maybe / 1 no / 0 pending)
Wed 8:00 PM   ⬜ Riley   ⬜ Marin   ⬜ Casey   ⬜ Quinn   (0 yes / 0 maybe / 0 no / 4 pending)

[Sat 2pm ✅] [Sat 2pm ❓] [Sat 2pm ❌]
[Mon 7pm ✅] [Mon 7pm ❓] [Mon 7pm ❌]
[Wed 8pm ✅] [Wed 8pm ❓] [Wed 8pm ❌]
[🔄 Reset]
```

Button labels use day + 12-hour time (e.g. `Sat 2pm`) to disambiguate slots if two share a day. Three buttons per slot, plus a Reset button on its own row. With up to 5 slots = 15 vote buttons + 1 reset = 16, under Discord's 25-component cap.

### Custom IDs

Extending the existing `soul_link:` namespacing:

| Custom ID | Action |
|---|---|
| `soul_link:gym_poll_vote:POLL_ID:SLOT_INDEX:yes\|maybe\|no` | Record vote for the clicking user |
| `soul_link:gym_poll_reset:POLL_ID` | Destroy the poll (anyone can click) |

Bot interaction handler matches these via the existing regex-dispatch pattern in `discord_bot.rb`.

### Vote handler flow

1. Defer the interaction ephemerally.
2. Look up the poll. Reject ephemerally if locked: "Poll is locked — reset to vote again."
3. Map Discord user ID → player UID via `SoulLink::GameState.players`. Unknown user → ephemeral "You aren't a player in this run."
4. Call `GymPoll#vote!(uid, slot_index, response)` on the model.
5. Send ephemeral confirmation to the clicker: "Got it — Sat 2pm ✅".
6. Model's `after_commit` callback enqueues `GymPollDiscordSyncJob` (embed refresh).
7. If the vote triggered a lock, the model also enqueues `GymPollLockJob` (separate side effect: ping + embed swap).

### Lock side effect — `GymPollLockJob`

Modeled on the existing `GymScheduleDiscordUpdateJob`. Two Discord API calls:

1. **PATCH** the poll message — embed gains a 🔒 header, vote buttons removed, only the Reset button remains.
2. **POST** a new message in the same `#general` channel:
   > `🎉 Gym poll locked: **Saturday, May 17 at 2:00 PM Phoenix time**. @Riley @Marin @Casey @Quinn — see you there!`

Player mentions resolved from `discord_user_id` in `players.yml`. Both API calls via `Net::HTTP` with the bot token (existing pattern).

**Idempotency:** the job checks `poll.pinged_at.nil?` before POSTing the ping; sets `pinged_at = Time.current` on success. Retries after a 5xx on the PATCH won't double-ping.

### Vote-state sync from the web side

When a vote comes in via ActionCable from the website, the bot needs to update the Discord message embed too. The `after_commit` callback on `GymPoll` handles this uniformly:

```ruby
after_commit -> { GymPollDiscordSyncJob.perform_later(id) if discord_message_id.present? },
             on: :update
```

Every state-mutating path (web vote, Discord vote, channel vote, future webhook, console fix-up) keeps the Discord embed in sync. The sync job is idempotent — it rebuilds the embed from current state.

## Real-Time Channel & Broadcasts

### Channel — `GymPollChannel`

```ruby
class GymPollChannel < ApplicationCable::Channel
  def subscribed
    poll = GymPoll.find(params[:id])
    stream_for poll
  end

  def vote(data)
    poll = GymPoll.find(params[:id])
    poll.vote!(current_user_id, data["slot_index"].to_i, data["response"])
  rescue => e
    transmit(type: "error", message: e.message)
  end

  def reset
    poll = GymPoll.find(params[:id])
    GymPollChannel.broadcast_to(poll, type: "poll_reset")
    poll.destroy
  end
end
```

`current_user_id` lifts from the existing connection identification (sessions are wired the same way as `GymScheduleChannel` and `GymDraftChannel`).

### Broadcast contract

One canonical message shape, broadcast after every state-changing mutation:

```json
{
  "type": "state_update",
  "state": {
    "id": 17,
    "status": "open",
    "locked_slot_index": null,
    "locked_at": null,
    "timezone": "America/Phoenix",
    "slots": [
      {
        "index": 0,
        "scheduled_at": "2026-05-16T21:00:00Z",
        "past": false,
        "yes_count": 2,
        "maybe_count": 1,
        "no_count": 0,
        "pending_count": 1
      }
    ],
    "votes": { "<player_uid>": { "0": "yes" } },
    "players": [{ "id": "...", "name": "Riley", "discord_user_id": "..." }],
    "discord_message_id": "1234567890"
  }
}
```

`past` is computed server-side per broadcast — clients don't need timezone math.

**Reset broadcast** (special-case): emitted *before* destroying the row so subscribers can swap to the empty-state UI:

```json
{ "type": "poll_reset" }
```

After destroy, the channel unsubscribes naturally.

**Lock broadcast**: just a normal `state_update` with `status: "locked"` and `locked_slot_index` set. The Stimulus controller's render logic notices the transition and disables vote buttons. No special event needed.

### Stimulus controller — `gym_poll_controller.js`

Patterned on `gym_schedule_controller.js`:

- **Targets:** `slotList`, `slotCard` (with `data-slot-index`), `voteButton`, `resetButton`, `bannerLocked`, `bannerAllPast`
- **`handleMessage(data)`** switches on `data.type`:
  - `state_update` → `this.state = data.state; this.render()`
  - `poll_reset` → `window.location.reload()` (simplest; matches the `gym_draft_controller` reset behavior)
  - `error` → flash inline (e.g., "Poll is locked")
- **`render()`** iterates slots and updates DOM in place — no full re-render.

## Testing Strategy

Project conventions: Minitest, FactoryBot factories (no fixtures since the 2026-04-30 sweep).

### New factories

- `factory :gym_poll` — defaults to `status: "open"`, empty votes, two future slots in `state_data`
- `:soul_link_run` factory gains traits: `with_schedule_template`, `in_timezone(zone)`

### Test surfaces

| Surface | Coverage | Rationale |
|---|---|---|
| `GymPoll` model | `vote!` happy path; vote on locked = raise; vote on past slot = raise; vote-flip flips counts; all-yes triggers lock + `locked_at` + `locked_slot_index`; lock fires once (re-call doesn't reset `pinged_at`) | Core state machine — densest coverage |
| `GymPoll.materialize_slots` | Mid-week, Sunday rollover, all-past slots, spring-forward DST week, fall-back DST week, empty template, malformed template | Pure function over time math — exhaustive |
| `SoulLinkRun#schedule_template` / `#timezone` | Validations, defaults, round-trip persistence | Thin layer, light coverage |
| `GymPollsController` | `create` happy + no-template + no-run + already-open; `destroy` happy + no-poll; `show` with/without active poll; all under both logged-in and not | Boundary surface; guard-heavy |
| `GymPollChannel` | Vote dispatches to model; reset broadcasts `poll_reset` then destroys; error path transmits error frame; unauthorized user rejected | Delegates to model — light coverage |
| `GymPollDiscordSyncJob` | Webmock-stubbed PATCH succeeds; embed payload contains expected fields; no-op when `discord_message_id` is nil; retry on 5xx | Same pattern as existing `GymScheduleDiscordUpdateJob` tests |
| `GymPollLockJob` | Posts ping with correct mentions; edits poll embed to locked state; idempotent (running twice doesn't double-post — `pinged_at` guard); ping uses `discord_user_id` from players.yml | Side-effect-heavy, thorough Webmock coverage |
| Integration test | Full happy path: create poll → cast 4 yes votes via channel → lock fires → both Discord stubs hit → reset destroys | One end-to-end test that proves the seams connect |

### Live verification

- The worktree won't boot `bin/dev` cleanly (no MySQL / OAuth) — live browser verification is deferred to a project-owner check post-merge, matching the Step 30 precedent.
- Discord live test happens against the real bot in a dev guild — by hand: configure template → `/new_gym_poll` → vote from multiple Discord accounts → confirm lock + ping → `/reset_gym_poll`.

### Explicitly out of scope for tests

- Discord's component-rendering correctness (their renderer, not ours)
- Stimulus DOM updates beyond a smoke test (no JS test infra in this project — matches the existing `gym_draft_controller.js` precedent)
- Cross-timezone display correctness for players in other zones (design is single-timezone-per-run by choice)

## Files Affected (Summary)

### Created

- `db/migrate/YYYYMMDDHHMMSS_create_gym_polls.rb`
- `db/migrate/YYYYMMDDHHMMSS_drop_gym_schedules.rb`
- `db/migrate/YYYYMMDDHHMMSS_add_schedule_template_and_timezone_to_soul_link_runs.rb`
- `app/models/gym_poll.rb`
- `app/controllers/gym_polls_controller.rb`
- `app/channels/gym_poll_channel.rb`
- `app/jobs/gym_poll_discord_sync_job.rb`
- `app/jobs/gym_poll_lock_job.rb`
- `app/javascript/controllers/gym_poll_controller.js`
- `app/views/gym_polls/show.html.erb`
- `app/views/gym_polls/_slot_card.html.erb`
- `app/views/gym_polls/_empty.html.erb`
- `app/views/dashboard/_schedule_content.html.erb` *(new tab)*
- `test/models/gym_poll_test.rb`
- `test/controllers/gym_polls_controller_test.rb`
- `test/channels/gym_poll_channel_test.rb`
- `test/jobs/gym_poll_discord_sync_job_test.rb`
- `test/jobs/gym_poll_lock_job_test.rb`
- `test/integration/gym_poll_flow_test.rb`
- `test/factories/gym_polls.rb`
- `.claude/documents/gym-poll.md` *(replaces gym-schedule.md)*

### Modified

- `config/routes.rb` — remove `gym_schedules` routes; add `gym_poll` resource; extend `resources :runs` with `:edit`, `:update`
- `app/controllers/runs_controller.rb` — add `edit` and `update` actions (template + timezone form)
- `app/services/soul_link/discord_bot.rb` — register `/new_gym_poll` and `/reset_gym_poll`, add interaction handlers for new custom IDs, remove `soul_link:gym_rsvp:*` handlers
- `app/views/dashboard/_tab_bar.html.erb` — add Schedule tab
- `app/views/dashboard/_status_rail.html.erb` — add poll-status tile
- `app/models/soul_link_run.rb` — add `schedule_template` and `timezone` accessors / validations
- `test/factories/soul_link_runs.rb` — add `with_schedule_template`, `in_timezone(zone)` traits
- `CLAUDE.md` — update doc table (replace `gym-schedule.md` link with `gym-poll.md`)

### Removed

- `app/models/gym_schedule.rb`
- `app/controllers/gym_schedules_controller.rb`
- `app/channels/gym_schedule_channel.rb`
- `app/jobs/gym_schedule_discord_update_job.rb`
- `app/javascript/controllers/gym_schedule_controller.js`
- `app/views/gym_schedules/` *(entire directory)*
- `test/models/gym_schedule_test.rb`
- `test/controllers/gym_schedules_controller_test.rb`
- `test/channels/gym_schedule_channel_test.rb`
- `test/jobs/gym_schedule_discord_update_job_test.rb`
- `test/factories/gym_schedules.rb`
- `.claude/documents/gym-schedule.md`
- `gym_schedules` table (via migration)

## Open Questions / Implementation Notes

- **`gym_draft_id` linkage:** The existing `GymSchedule` had an optional `gym_draft` reference. Spec preserves it on `GymPoll` so a locked poll can be linked to the draft that picks the team for that meeting. The integration is unchanged from current behavior; the link is set after draft completion, not at poll creation.
- **Status-rail tile copy:** The exact wording ("Open — 2 of 4 voted on Sat 2 PM" vs "🔒 Locked: Sat 2 PM") is a polish detail; implementer should iterate during build.
- **Max slots in template:** Soft cap of 5 due to Discord's 25-component-per-message limit (5 slots × 3 buttons + 1 reset = 16, with headroom). Editor enforces this client-side.
- **Timezone dropdown population:** Suggest a curated list of common US zones (Phoenix, Pacific, Mountain, Central, Eastern) plus an "Other" free-text option. Full IANA list is too long for a friend-group UX.

## Non-Goals

- Cross-week scheduling (only this week, manually rolled forward)
- Auto-reset on cron / time-of-week trigger
- Reporting on past polls / historical analytics
- Per-player timezone display (single run timezone)
- Recurring meetings beyond the weekly template (no biweekly, monthly, etc.)
- Notifications outside Discord (no email, no in-browser push)
