# Architect Brief
*Written by Architect. Read by Builder and Reviewer.*

---

## Step 5 — Gym Result: Mark Beaten + Team Snapshot + Backfill

Context: Gyms are currently tracked by a simple integer counter `gyms_defeated` on SoulLinkRun. No per-gym history, no team snapshots. This step adds a GymResult model to track individual gym victories with frozen team snapshots, plus a backfill mechanism for retroactively adding teams to already-beaten gyms.

### Decisions
- GymResult is the source of truth for gym victories. `gyms_defeated` is kept in sync as a derived value (max gym_number of results, or set directly on mark/unmark).
- Team snapshots are JSON blobs frozen at the time of recording — they don't change if pokemon are later modified.
- Backfill uses the same snapshot builder, just from user-selected group_ids instead of draft picks.
- The Game Boy theme (gb-card, gb-btn, etc.) is used for all new UI — match existing patterns in `_gyms_content.html.erb`.
- The gym backfill picker is a modal with selectable group cards, max 6, matching the existing UI patterns.

### Build Order

**1. Migration: Create gym_results table**

Generate: `mise exec -- bin/rails generate migration CreateGymResults`

```ruby
class CreateGymResults < ActiveRecord::Migration[8.1]
  def change
    create_table :gym_results do |t|
      t.references :soul_link_run, null: false, foreign_key: true
      t.integer :gym_number, null: false
      t.datetime :beaten_at, null: false
      t.references :gym_draft, null: true, foreign_key: true
      t.json :team_snapshot

      t.timestamps
    end

    add_index :gym_results, [:soul_link_run_id, :gym_number], unique: true
  end
end
```

Run `mise exec -- bin/rails db:migrate`.

**2. Model: GymResult (`app/models/gym_result.rb`)**

```ruby
class GymResult < ApplicationRecord
  belongs_to :soul_link_run
  belongs_to :gym_draft, optional: true

  validates :gym_number, presence: true,
            inclusion: { in: 1..8 },
            uniqueness: { scope: :soul_link_run_id }
  validates :beaten_at, presence: true

  def self.snapshot_from_groups(groups)
    players = SoulLink::GameState.players
    {
      "groups" => groups.map do |group|
        {
          "group_id" => group.id,
          "nickname" => group.nickname,
          "location" => group.location,
          "pokemon" => group.soul_link_pokemon.map do |p|
            player = players.find { |pl| pl["discord_user_id"] == p.discord_user_id }
            {
              "discord_user_id" => p.discord_user_id.to_s,
              "player_name" => player&.[]("display_name") || p.discord_user_id.to_s,
              "species" => p.species,
              "level" => p.level,
              "ability" => p.ability,
              "nature" => p.nature
            }
          end
        }
      end
    }
  end

  def self.snapshot_from_draft(draft)
    group_ids = draft.final_team_group_ids
    groups = draft.soul_link_run.soul_link_pokemon_groups
                  .where(id: group_ids)
                  .includes(:soul_link_pokemon)
    snapshot_from_groups(groups)
  end

  def self.snapshot_from_group_ids(run, group_ids)
    groups = run.soul_link_pokemon_groups
                .where(id: group_ids)
                .includes(:soul_link_pokemon)
    snapshot_from_groups(groups)
  end
end
```

**3. Model: Update SoulLinkRun (`app/models/soul_link_run.rb`)**

Add after line 6 (`has_many :gym_schedules`):
```ruby
has_many :gym_results, dependent: :destroy
```

**4. Controller: Rework GymProgressController (`app/controllers/gym_progress_controller.rb`)**

Replace the `update` method. New logic:

```ruby
def update
  run = current_run
  head :not_found and return unless run

  gym_number = params[:gym_number].to_i
  unless gym_number.between?(1, 8)
    render json: { error: "Invalid gym number" }, status: :unprocessable_entity
    return
  end

  existing = run.gym_results.find_by(gym_number: gym_number)

  if existing
    # Unmark: destroy result, recalculate counter
    existing.destroy!
    new_max = run.gym_results.maximum(:gym_number) || 0
    run.update!(gyms_defeated: new_max)
  else
    # Mark beaten: create result (no snapshot from this path)
    run.gym_results.create!(
      gym_number: gym_number,
      beaten_at: Time.current
    )
    run.update!(gyms_defeated: [run.gyms_defeated, gym_number].max)
  end

  render json: { gyms_defeated: run.gyms_defeated }
end
```

**5. Controller: Add mark_beaten to GymDraftsController (`app/controllers/gym_drafts_controller.rb`)**

Add after the `show` action:

```ruby
def mark_beaten
  run = current_run
  redirect_to login_path, alert: "No active run found." and return unless run

  draft = run.gym_drafts.find_by(id: params[:id])
  unless draft&.complete?
    redirect_to gym_drafts_path, alert: "Draft is not complete."
    return
  end

  gym_number = run.gyms_defeated + 1
  unless gym_number.between?(1, 8)
    redirect_to gym_draft_path(draft), alert: "All gyms already defeated!"
    return
  end

  # Check if this gym already has a result
  if run.gym_results.exists?(gym_number: gym_number)
    redirect_to gym_draft_path(draft), alert: "Gym #{gym_number} already marked as beaten."
    return
  end

  snapshot = GymResult.snapshot_from_draft(draft)
  run.gym_results.create!(
    gym_number: gym_number,
    beaten_at: Time.current,
    gym_draft: draft,
    team_snapshot: snapshot
  )
  run.update!(gyms_defeated: gym_number)

  redirect_to root_path, notice: "Gym #{gym_number} marked as beaten!"
end
```

**6. Controller: New GymResultsController (`app/controllers/gym_results_controller.rb`)**

```ruby
class GymResultsController < ApplicationController
  before_action :require_login

  def update
    run = current_run
    head :not_found and return unless run

    result = run.gym_results.find_by(id: params[:id])
    unless result
      render json: { error: "Gym result not found" }, status: :not_found
      return
    end

    group_ids = (params[:group_ids] || []).first(6).map(&:to_i)
    if group_ids.empty?
      render json: { error: "At least one group is required" }, status: :unprocessable_entity
      return
    end

    snapshot = GymResult.snapshot_from_group_ids(run, group_ids)
    result.update!(team_snapshot: snapshot)

    render json: { status: "saved", gym_number: result.gym_number }
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def current_run
    guild_id = session[:guild_id]
    return nil unless guild_id
    SoulLinkRun.current(guild_id)
  end
end
```

**7. Routes (`config/routes.rb`)**

Change line 30 from:
```ruby
resources :gym_drafts, only: [ :create, :show ]
```
To:
```ruby
resources :gym_drafts, only: [ :create, :show ] do
  member { post :mark_beaten }
end
resources :gym_results, only: [ :update ]
```

**8. Dashboard Controller: Load gym_results (`app/controllers/dashboard_controller.rb`)**

Add to the show action, after loading `@gym_info`:
```ruby
@gym_results = run.gym_results.index_by(&:gym_number)
```

Also load caught groups for the backfill picker:
```ruby
@caught_groups_for_backfill = run.caught_groups.includes(:soul_link_pokemon)
```

**9. View: Gym Draft Complete Panel (`app/views/gym_drafts/show.html.erb`)**

In the complete panel (around line 152, before the closing `</div>`), add the mark beaten button. The controller should also set `@next_gym_number = @draft.soul_link_run.gyms_defeated + 1` and `@gym_already_marked = @draft.soul_link_run.gym_results.exists?(gym_number: @next_gym_number)` and `@next_gym_info = SoulLink::GameState.gym_info_by_number(@next_gym_number)`.

```erb
<% if @draft.complete? && !@gym_already_marked && @next_gym_number.between?(1, 8) %>
  <div style="text-align: center; margin-top: 12px;">
    <%= button_to "MARK GYM #{@next_gym_number} — #{@next_gym_info&.[]('leader')&.upcase} AS BEATEN",
        mark_beaten_gym_draft_path(@draft),
        method: :post,
        class: "gb-btn-primary" %>
  </div>
<% end %>
```

**10. View: Dashboard Gyms Tab (`app/views/dashboard/_gyms_content.html.erb`)**

Rework the gym leaders list (lines 27-57). For each gym:

a) **Beaten gyms WITH snapshot** — show the gym info + expandable team snapshot below.
b) **Beaten gyms WITHOUT snapshot** — show gym info + "ADD TEAM" button that opens backfill picker.
c) **Next gym** — existing highlight + "MARK BEATEN" button.
d) **Future gyms** — unchanged (dimmed).

For beaten gyms, after each `gym-list-item` div, add a team snapshot section:

```erb
<% result = @gym_results[num] %>
<% if defeated && result %>
  <% if result.team_snapshot.present? %>
    <%# Collapsible team snapshot %>
    <div class="gb-card-dark" style="margin: 4px 0 8px 20px; padding: 8px; font-size: 9px;">
      <% result.team_snapshot["groups"]&.each do |group_data| %>
        <div style="margin-bottom: 6px;">
          <div style="font-weight: bold;"><%= group_data["nickname"] %></div>
          <% group_data["pokemon"]&.each do |p| %>
            <div style="margin-left: 8px; color: var(--d2);">
              <%= p["player_name"] %>: <%= p["species"] %>
              <% stats = [p["level"] ? "Lv.#{p["level"]}" : nil, p["ability"], p["nature"]].compact %>
              <% if stats.any? %><span style="color: var(--d2);"> — <%= stats.join(" / ") %></span><% end %>
            </div>
          <% end %>
        </div>
      <% end %>
    </div>
  <% else %>
    <%# Backfill button %>
    <div style="margin: 4px 0 8px 20px;">
      <button type="button" class="gb-btn gb-btn-sm" style="font-size: 9px;"
              data-controller="gym-backfill"
              data-gym-backfill-result-id-value="<%= result.id %>"
              data-gym-backfill-update-url-value="<%= gym_result_path(result) %>"
              data-gym-backfill-csrf-value="<%= form_authenticity_token %>"
              data-gym-backfill-groups-value="<%= @caught_groups_for_backfill.map { |g|
                my = g.soul_link_pokemon.find { |p| p.discord_user_id == current_user_id }
                { id: g.id, nickname: g.nickname, species: my&.species || '?' }
              }.to_json %>"
              data-action="click->gym-backfill#openPicker">
        + ADD TEAM
      </button>
      <div data-gym-backfill-target="picker" class="hidden"></div>
    </div>
  <% end %>
<% end %>
```

For the next gym, add a "MARK BEATEN" button alongside the existing content:
```erb
<%= button_to "MARK BEATEN", gym_progress_path(gym_number: num),
    method: :patch, class: "gb-btn-primary gb-btn-sm",
    style: "font-size: 9px; padding: 3px 8px; margin-left: auto;",
    data: { turbo: false } %>
```

**11. Stimulus: Gym Backfill Controller (`app/javascript/controllers/gym_backfill_controller.js`)**

```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["picker"]
  static values = {
    resultId: Number,
    updateUrl: String,
    csrf: String,
    groups: Array
  }

  openPicker() {
    this.selected = new Set()
    const picker = this.pickerTarget
    picker.replaceChildren()

    const grid = document.createElement("div")
    grid.style.cssText = "display: grid; grid-template-columns: repeat(3, 1fr); gap: 4px; margin-top: 8px;"

    this.groupsValue.forEach(g => {
      const card = document.createElement("div")
      card.className = "gb-card-dark"
      card.style.cssText = "padding: 6px; text-align: center; cursor: pointer; font-size: 9px;"
      card.dataset.groupId = g.id

      const nick = document.createElement("div")
      nick.textContent = g.nickname
      nick.style.fontWeight = "bold"

      const spec = document.createElement("div")
      spec.textContent = g.species
      spec.style.cssText = "color: var(--d2); font-size: 8px;"

      card.append(nick, spec)
      card.addEventListener("click", () => this.toggleCard(card, g.id))
      grid.appendChild(card)
    })

    const saveBtn = document.createElement("button")
    saveBtn.className = "gb-btn-primary gb-btn-sm"
    saveBtn.style.cssText = "margin-top: 8px; font-size: 9px;"
    saveBtn.textContent = "SAVE TEAM"
    saveBtn.addEventListener("click", () => this.save())

    const cancelBtn = document.createElement("button")
    cancelBtn.className = "gb-btn gb-btn-sm"
    cancelBtn.style.cssText = "margin-top: 8px; margin-left: 6px; font-size: 9px;"
    cancelBtn.textContent = "CANCEL"
    cancelBtn.addEventListener("click", () => this.closePicker())

    const btnRow = document.createElement("div")
    btnRow.append(saveBtn, cancelBtn)

    picker.append(grid, btnRow)
    picker.classList.remove("hidden")
  }

  toggleCard(card, groupId) {
    if (this.selected.has(groupId)) {
      this.selected.delete(groupId)
      card.style.borderColor = ""
      card.style.background = ""
    } else {
      if (this.selected.size >= 6) return // max 6
      this.selected.add(groupId)
      card.style.borderColor = "var(--d1)"
      card.style.background = "var(--d2)"
    }
  }

  async save() {
    if (this.selected.size === 0) return

    const response = await fetch(this.updateUrlValue, {
      method: "PATCH",
      headers: { "Content-Type": "application/json", "X-CSRF-Token": this.csrfValue },
      body: JSON.stringify({ group_ids: Array.from(this.selected) })
    })

    if (response.ok) {
      window.location.reload()
    }
  }

  closePicker() {
    this.pickerTarget.classList.add("hidden")
    this.pickerTarget.replaceChildren()
  }
}
```

### Flags
- Flag: `SoulLink::GameState.gym_info_by_number` may not exist yet. Check if it does — if not, add a helper method to the GameState service that looks up gym info by number. Alternatively, use the existing `gym_info` hash and find the entry where `number == n`.
- Flag: The "MARK BEATEN" button on the gyms tab should use `button_to` with `method: :patch` and `data: { turbo: false }` to ensure a full page reload on submit.
- Flag: Use `mise exec --` prefix for Rails generators and migrations.
- Flag: The backfill picker uses `textContent` (not innerHTML) for all user data — match the pattern from Step 2.
- Flag: The `@caught_groups_for_backfill` should be loaded in the dashboard controller only — don't load it in every controller.

### Definition of Done
- [ ] Migration created and runs
- [ ] GymResult model with snapshot builder methods
- [ ] SoulLinkRun has `has_many :gym_results`
- [ ] GymProgressController creates/destroys GymResult records + syncs counter
- [ ] GymDraftsController#mark_beaten creates GymResult with draft snapshot
- [ ] GymResultsController#update accepts group_ids for backfill
- [ ] Routes added for mark_beaten and gym_results
- [ ] Dashboard gyms tab shows: mark beaten button, team snapshots, backfill button
- [ ] Gym draft complete page shows mark beaten button
- [ ] Gym backfill Stimulus controller works (select groups, save, reload)
- [ ] All user data rendered via textContent, not innerHTML

---

## Builder Plan
*Builder adds their plan here before building. Architect reviews and approves.*

**Plan:**

Brief is complete. All code patterns, file locations, and flags are clear. Here's my execution plan:

1. **Migration** — Create gym_results table exactly as specified.
2. **GymResult model** — Snapshot builder methods using `SoulLink::GameState.players`.
3. **GameState helper** — `gym_info_by_number(n)` doesn't exist. I'll add it using `GYM_KEYS[n - 1]` lookup since it's needed in the gym draft show view. Small addition, fits the existing pattern.
4. **SoulLinkRun** — Add `has_many :gym_results` after line 6.
5. **GymProgressController** — Replace `update` with create/destroy GymResult + sync counter logic.
6. **GymDraftsController** — Add `mark_beaten` action. Add `@next_gym_number`, `@gym_already_marked`, `@next_gym_info` to `show` for the complete panel button.
7. **GymResultsController** — New controller for backfill `update` (accepts `group_ids`).
8. **Routes** — Wrap `gym_drafts` with member `mark_beaten`, add `gym_results` resource.
9. **DashboardController** — Load `@gym_results` and `@caught_groups_for_backfill` in show action.
10. **Views** — Mark beaten button in gym draft complete panel + reworked gyms tab with snapshots/backfill.
11. **Stimulus** — `gym_backfill_controller.js` with textContent only, matching Step 2 pattern.

**Decisions:**
- `gym_info_by_number` will be a 3-line class method on GameState, not a separate service.
- All user data via textContent — confirmed in Stimulus controller.
- Discord user IDs will use `.to_s` everywhere they touch the frontend.

Architect approval: [ ] Approved / [ ] Redirect — see notes below
