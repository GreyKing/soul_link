# Ability Effect Blurbs + Hover Popups Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give every Pokémon ability a short inline effect blurb (parallel to the nature `+Atk -Spd` label) plus a Game-Boy-styled hover popup with the full Gen-IV description, on every surface an ability renders.

**Architecture:** A new `config/soul_link/ability_effects.yml` (name → `{short, full}`, all 123 abilities) is loaded by `SoulLink::GameState`, surfaced to ERB via `PixeldexHelper`, and to JS as a JSON data-attribute. A single delegated Stimulus `ability-tooltip` controller mounted on the pixeldex root renders one reusable, `position: fixed` popup for any element carrying `data-ability-full`, avoiding the clipping a pure-CSS tooltip would hit inside the scrollable dropdown/snapshot containers. Blurbs are injected at three sites: the detail modal (field + searchable-select options), the JS linked-Pokémon cards, and the gym team snapshot.

**Tech Stack:** Ruby 3.4 / Rails 8.1, YAML config, Minitest, Stimulus (Importmap, no Node), Tailwind + `pixeldex.css` (Game-Boy theme).

---

## File Structure

**Create:**
- `config/soul_link/ability_effects.yml` — data: 123 abilities → `{short, full}`.
- `app/javascript/controllers/ability_tooltip_controller.js` — shared delegated hover popup.

**Modify:**
- `app/services/soul_link/game_state.rb` — path constant + `ability_effects` / `ability_effect` loaders + `reload!`.
- `app/helpers/pixeldex_helper.rb` — `ability_effect_short` / `ability_effect_full`.
- `app/views/dashboard/show.html.erb` — add `ability-tooltip` controller + effects JSON data-attr.
- `app/views/map/show.html.erb` — same two additions.
- `app/javascript/controllers/pixeldex_controller.js` — `abilityEffectsData` value, `modalAbilityLabel` target + updater, linked-card ability span.
- `app/views/dashboard/_pokemon_modal.html.erb` — ABILITY EFFECT blurb line + `meta` value on the ability searchable-select.
- `app/javascript/controllers/searchable_select_controller.js` — optional `meta` value → per-option blurb + `data-ability-full`.
- `app/views/dashboard/_gyms_content.html.erb` — ability rendered as a tooltip span.
- `app/assets/stylesheets/pixeldex.css` — `.gb-tooltip` + `.ss-option-meta` styles.

**Test:**
- `test/services/soul_link/game_state_test.rb` — loader + data-integrity.
- `test/helpers/pixeldex_helper_test.rb` — helper blurbs.

---

## Task 1: Ability effects data + GameState loader

**Files:**
- Create: `config/soul_link/ability_effects.yml`
- Modify: `app/services/soul_link/game_state.rb` (path constants ~`:14`, loaders after `abilities_for` ~`:187`, `reload!` ~`:214`)
- Test: `test/services/soul_link/game_state_test.rb`

- [ ] **Step 1: Write the failing test**

Add to `test/services/soul_link/game_state_test.rb` (inside the existing test class):

```ruby
test "ability_effect returns short and full for a known ability" do
  effect = SoulLink::GameState.ability_effect("Levitate")
  assert_equal "Immune to Ground", effect["short"]
  assert_equal "Gives full immunity to all Ground-type moves.", effect["full"]
end

test "ability_effect returns nil for an unknown ability" do
  assert_nil SoulLink::GameState.ability_effect("Not An Ability")
end

test "ability_effects is a non-empty hash keyed by ability name" do
  assert SoulLink::GameState.ability_effects.is_a?(Hash)
  assert SoulLink::GameState.ability_effects.key?("Static")
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bin/rails test test/services/soul_link/game_state_test.rb`
Expected: FAIL — `NoMethodError: undefined method 'ability_effect'`.

- [ ] **Step 3: Create the data file**

Create `config/soul_link/ability_effects.yml` with all 123 entries:

```yaml
# config/soul_link/ability_effects.yml
# Gen IV Platinum ability effects. Keys match abilities.yml exactly.
# `short` = terse blurb for inline display; `full` = one-sentence hover text.
Adaptability:  { short: "Boosts same-type moves",  full: "Powers up moves of the same type as the Pokémon." }
Aftermath:     { short: "Hurts foe on fainting",    full: "Damages the attacker if it lands the finishing hit with a contact move." }
Air Lock:      { short: "Negates weather",          full: "Eliminates the effects of all weather while the Pokémon is in battle." }
Anger Point:   { short: "Max Attack when crit",     full: "Maxes the Attack stat after taking a critical hit." }
Anticipation:  { short: "Senses danger",            full: "Senses when an opposing Pokémon has a dangerous move." }
Arena Trap:    { short: "Foes can't escape",        full: "Prevents opposing Pokémon from fleeing or switching out." }
Bad Dreams:    { short: "Saps sleeping foes",       full: "Reduces the HP of any sleeping opposing Pokémon each turn." }
Battle Armor:  { short: "Blocks critical hits",     full: "Protects the Pokémon from critical hits." }
Blaze:         { short: "Boosts Fire at low HP",    full: "Powers up Fire-type moves when the Pokémon's HP is low." }
Chlorophyll:   { short: "Fast in sunshine",         full: "Doubles the Pokémon's Speed in harsh sunlight." }
Clear Body:    { short: "Blocks stat drops",        full: "Prevents other Pokémon from lowering its stats." }
Cloud Nine:    { short: "Negates weather",          full: "Eliminates the effects of all weather while the Pokémon is in battle." }
Color Change:  { short: "Takes attacker's type",    full: "Changes the Pokémon's type to that of the move that last hit it." }
Compound Eyes: { short: "Boosts accuracy",          full: "Increases the accuracy of the Pokémon's moves." }
Cute Charm:    { short: "May infatuate on contact", full: "Contact with this Pokémon may cause infatuation." }
Damp:          { short: "Blocks explosions",        full: "Prevents the use of Selfdestruct and Explosion by any Pokémon." }
Download:      { short: "Boosts on entry",          full: "Raises Attack or Sp. Atk based on the opposing Pokémon's weaker defense." }
Drizzle:       { short: "Summons rain",             full: "Makes it rain when the Pokémon enters battle." }
Drought:       { short: "Summons sunlight",         full: "Turns the sunlight harsh when the Pokémon enters battle." }
Dry Skin:      { short: "Reacts to water & sun",    full: "Restores HP in rain and from Water moves, but takes more from Fire and loses HP in sun." }
Early Bird:    { short: "Wakes up fast",            full: "Awakens from sleep in half the usual time." }
Effect Spore:  { short: "May afflict on contact",   full: "Contact may leave the attacker poisoned, paralyzed, or asleep." }
Filter:        { short: "Softens super-effective",  full: "Reduces damage taken from super-effective moves." }
Flame Body:    { short: "May burn on contact",      full: "Contact with this Pokémon may leave the attacker with a burn." }
Flash Fire:    { short: "Powered by Fire",          full: "Absorbs Fire moves, taking no damage and boosting its own Fire moves." }
Flower Gift:   { short: "Boosts stats in sun",      full: "Raises the Attack and Sp. Def of ally Pokémon in harsh sunlight." }
Forecast:      { short: "Changes with weather",     full: "Changes the Pokémon's type with the weather." }
Forewarn:      { short: "Reveals a strong move",    full: "Reveals one of the opposing Pokémon's moves when battle begins." }
Frisk:         { short: "Checks foe's item",        full: "Reveals the held item of an opposing Pokémon when battle begins." }
Gluttony:      { short: "Eats Berry early",         full: "Uses a held Berry sooner than usual, when HP drops to half." }
Guts:          { short: "Attack up when statused",  full: "Boosts Attack if the Pokémon has a status condition." }
Heatproof:     { short: "Halves Fire damage",       full: "Weakens the damage from Fire-type moves and from burns." }
Honey Gather:  { short: "Gathers Honey",            full: "May gather Honey after a battle." }
Huge Power:    { short: "Doubles Attack",           full: "Doubles the Pokémon's Attack stat." }
Hustle:        { short: "Power over accuracy",      full: "Boosts Attack but lowers the accuracy of physical moves." }
Hydration:     { short: "Cures status in rain",     full: "Heals status conditions if it is raining." }
Hyper Cutter:  { short: "Attack can't be cut",      full: "Prevents other Pokémon from lowering its Attack stat." }
Ice Body:      { short: "Heals in hail",            full: "Restores HP each turn during hail and takes no hail damage." }
Illuminate:    { short: "Lures wild Pokémon",       full: "Increases the likelihood of encountering wild Pokémon." }
Immunity:      { short: "Can't be poisoned",        full: "Prevents the Pokémon from becoming poisoned." }
Inner Focus:   { short: "Never flinches",           full: "Protects the Pokémon from flinching." }
Insomnia:      { short: "Can't sleep",              full: "Prevents the Pokémon from falling asleep." }
Intimidate:    { short: "Lowers foe's Attack",      full: "Lowers the opposing Pokémon's Attack stat on entering battle." }
Iron Fist:     { short: "Boosts punch moves",       full: "Powers up punching moves." }
Keen Eye:      { short: "Accuracy can't drop",      full: "Prevents other Pokémon from lowering its accuracy." }
Klutz:         { short: "Can't use items",          full: "Prevents the Pokémon from using its held item." }
Leaf Guard:    { short: "No status in sun",         full: "Prevents status conditions in harsh sunlight." }
Levitate:      { short: "Immune to Ground",         full: "Gives full immunity to all Ground-type moves." }
Lightning Rod: { short: "Draws Electric moves",     full: "In double battles, draws in all Electric-type moves to itself." }
Limber:        { short: "Can't be paralyzed",       full: "Prevents the Pokémon from becoming paralyzed." }
Liquid Ooze:   { short: "Poisons HP drainers",      full: "Damages foes that drain its HP instead of healing them." }
Magic Guard:   { short: "Only direct damage",       full: "Takes damage only from attacks; indirect damage is prevented." }
Magma Armor:   { short: "Can't be frozen",          full: "Prevents the Pokémon from becoming frozen." }
Magnet Pull:   { short: "Traps Steel types",        full: "Prevents Steel-type Pokémon from fleeing or switching out." }
Marvel Scale:  { short: "Defense up when statused", full: "Boosts Defense if the Pokémon has a status condition." }
Minus:         { short: "Teams with Plus",          full: "Raises Sp. Atk when an ally has the Plus ability." }
Mold Breaker:  { short: "Ignores foe abilities",    full: "Moves can be used regardless of the target's ability." }
Motor Drive:   { short: "Electric boosts Speed",    full: "Raises Speed and takes no damage when hit by an Electric move." }
Multitype:     { short: "Type matches Plate",       full: "Changes the Pokémon's type to match its held Plate." }
Natural Cure:  { short: "Cures on switch-out",      full: "Heals status conditions when the Pokémon switches out." }
No Guard:      { short: "Every move lands",         full: "Ensures moves used by or against the Pokémon always hit." }
Normalize:     { short: "Moves turn Normal",        full: "Makes all of the Pokémon's moves Normal-type." }
Oblivious:     { short: "Ignores attraction",       full: "Prevents the Pokémon from becoming infatuated." }
Overgrow:      { short: "Boosts Grass at low HP",   full: "Powers up Grass-type moves when the Pokémon's HP is low." }
Own Tempo:     { short: "Can't be confused",        full: "Prevents the Pokémon from becoming confused." }
Pickup:        { short: "Picks up items",           full: "May pick up an item after a battle." }
Plus:          { short: "Teams with Minus",         full: "Raises Sp. Atk when an ally has the Minus ability." }
Poison Heal:   { short: "Poison heals it",          full: "Restores HP instead of losing it when poisoned." }
Poison Point:  { short: "May poison on contact",    full: "Contact with this Pokémon may leave the attacker poisoned." }
Pressure:      { short: "Drains foe's PP",          full: "Causes the opposing Pokémon to use more PP for its moves." }
Pure Power:    { short: "Doubles Attack",           full: "Doubles the Pokémon's Attack stat using its own power." }
Quick Feet:    { short: "Speed up when statused",   full: "Boosts Speed if the Pokémon has a status condition." }
Rain Dish:     { short: "Heals in rain",            full: "Gradually restores HP in rain." }
Reckless:      { short: "Boosts recoil moves",      full: "Powers up moves that cause recoil damage." }
Rivalry:       { short: "Fights by gender",         full: "Deals more damage to same-gender foes and less to opposite-gender." }
Rock Head:     { short: "No recoil damage",         full: "Protects the Pokémon from recoil damage." }
Rough Skin:    { short: "Hurts on contact",         full: "Damages the attacker on contact." }
Run Away:      { short: "Always escapes",           full: "Ensures escape from any wild Pokémon." }
Sand Stream:   { short: "Summons sandstorm",        full: "Summons a sandstorm when the Pokémon enters battle." }
Sand Veil:     { short: "Evasion up in sand",       full: "Boosts evasion during a sandstorm and blocks sandstorm damage." }
Scrappy:       { short: "Hits Ghost types",         full: "Enables Normal- and Fighting-type moves to hit Ghost-type Pokémon." }
Serene Grace:  { short: "Boosts move effects",      full: "Raises the chance of a move's added effect occurring." }
Shadow Tag:    { short: "Foes can't escape",        full: "Prevents opposing Pokémon from fleeing or switching out." }
Shed Skin:     { short: "May cure status",          full: "May heal its own status conditions each turn." }
Shell Armor:   { short: "Blocks critical hits",     full: "Protects the Pokémon from critical hits." }
Shield Dust:   { short: "Blocks added effects",     full: "Blocks the added effects of attacks taken." }
Simple:        { short: "Doubles stat changes",     full: "Doubles the effect of the Pokémon's stat changes." }
Skill Link:    { short: "Max multi-hits",           full: "Multi-strike moves always hit the maximum number of times." }
Slow Start:    { short: "Slow to warm up",          full: "Halves Attack and Speed for five turns after entering battle." }
Sniper:        { short: "Stronger crits",           full: "Powers up critical hits beyond the usual boost." }
Snow Cloak:    { short: "Evasion up in hail",       full: "Boosts evasion during hail and blocks hail damage." }
Snow Warning:  { short: "Summons hail",             full: "Summons a hailstorm when the Pokémon enters battle." }
Solar Power:   { short: "Sp.Atk up in sun",         full: "Boosts Sp. Atk in harsh sunlight but loses HP each turn." }
Solid Rock:    { short: "Softens super-effective",  full: "Reduces damage taken from super-effective moves." }
Soundproof:    { short: "Blocks sound moves",       full: "Gives immunity to sound-based moves." }
Speed Boost:   { short: "Speed rises each turn",    full: "Raises the Pokémon's Speed every turn." }
Stall:         { short: "Acts last",                full: "Causes the Pokémon to move after all others." }
Static:        { short: "May paralyze on contact",  full: "Contact with this Pokémon may leave the attacker paralyzed." }
Steadfast:     { short: "Speed up on flinch",       full: "Raises Speed each time the Pokémon flinches." }
Stench:        { short: "Repels wild Pokémon",      full: "Helps keep wild Pokémon away with its stench." }
Sticky Hold:   { short: "Holds its item",           full: "Prevents the Pokémon's held item from being taken." }
Storm Drain:   { short: "Draws Water moves",        full: "In double battles, draws in all Water-type moves to itself." }
Sturdy:        { short: "Blocks OHKO moves",        full: "Protects the Pokémon against one-hit KO moves." }
Suction Cups:  { short: "Can't be moved",           full: "Prevents the Pokémon from being switched out by moves or items." }
Super Luck:    { short: "Crits more often",         full: "Raises the likelihood of landing critical hits." }
Swarm:         { short: "Boosts Bug at low HP",     full: "Powers up Bug-type moves when the Pokémon's HP is low." }
Swift Swim:    { short: "Fast in rain",             full: "Doubles the Pokémon's Speed in rain." }
Synchronize:   { short: "Shares its status",        full: "Passes a burn, poison, or paralysis to the Pokémon that caused it." }
Tangled Feet:  { short: "Evasion up when confused", full: "Raises evasion while the Pokémon is confused." }
Technician:    { short: "Boosts weak moves",        full: "Powers up the Pokémon's weaker moves." }
Thick Fat:     { short: "Resists Fire & Ice",       full: "Halves damage taken from Fire- and Ice-type moves." }
Tinted Lens:   { short: "Boosts weak hits",         full: "Doubles the power of not-very-effective moves." }
Torrent:       { short: "Boosts Water at low HP",   full: "Powers up Water-type moves when the Pokémon's HP is low." }
Trace:         { short: "Copies foe's ability",     full: "Copies an opposing Pokémon's ability on entering battle." }
Truant:        { short: "Acts every other turn",    full: "Causes the Pokémon to loaf around every other turn." }
Unaware:       { short: "Ignores stat changes",     full: "Ignores the opposing Pokémon's stat changes when dealing or taking damage." }
Unburden:      { short: "Speed up when item used",  full: "Doubles Speed if the Pokémon's held item is used or lost." }
Vital Spirit:  { short: "Can't sleep",              full: "Prevents the Pokémon from falling asleep." }
Volt Absorb:   { short: "Electric heals it",        full: "Restores HP when hit by an Electric move, taking no damage." }
Water Absorb:  { short: "Water heals it",           full: "Restores HP when hit by a Water move, taking no damage." }
Water Veil:    { short: "Can't be burned",          full: "Prevents the Pokémon from getting a burn." }
White Smoke:   { short: "Blocks stat drops",        full: "Prevents other Pokémon from lowering its stats." }
Wonder Guard:  { short: "Only super-effective hurt", full: "Only super-effective moves can damage the Pokémon." }
```

- [ ] **Step 4: Add the loaders to GameState**

In `app/services/soul_link/game_state.rb`, add the path constant next to `ABILITIES_PATH` (~`:14`):

```ruby
    ABILITY_EFFECTS_PATH = Rails.root.join('config', 'soul_link', 'ability_effects.yml')
```

Add these methods right after `all_abilities` (~`:194`), inside the `class << self` block:

```ruby
      # Ability effects: ability name → { "short" =>, "full" => }
      def ability_effects
        @ability_effects ||= File.exist?(ABILITY_EFFECTS_PATH) ? YAML.load_file(ABILITY_EFFECTS_PATH) : {}
      end

      # Returns the { "short" =>, "full" => } hash for an ability, or nil
      def ability_effect(name)
        ability_effects[name]
      end
```

Add the reset line to `reload!` next to `@all_abilities = nil` (~`:226`):

```ruby
        @ability_effects = nil
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `bin/rails test test/services/soul_link/game_state_test.rb`
Expected: PASS (all three new tests green).

- [ ] **Step 6: Commit**

```bash
git add config/soul_link/ability_effects.yml app/services/soul_link/game_state.rb test/services/soul_link/game_state_test.rb
git commit -m "feat(abilities): add ability_effects data + GameState loader"
```

---

## Task 2: Data-integrity test (every ability is covered)

**Files:**
- Test: `test/services/soul_link/game_state_test.rb`

- [ ] **Step 1: Write the test**

Add to `test/services/soul_link/game_state_test.rb`:

```ruby
test "every ability has a non-empty short and full effect entry" do
  missing = []
  SoulLink::GameState.all_abilities.each do |name|
    effect = SoulLink::GameState.ability_effect(name)
    if effect.nil? || effect["short"].to_s.strip.empty? || effect["full"].to_s.strip.empty?
      missing << name
    end
  end
  assert_empty missing, "abilities missing short/full effect: #{missing.join(', ')}"
end
```

- [ ] **Step 2: Run the test**

Run: `bin/rails test test/services/soul_link/game_state_test.rb`
Expected: PASS. If it FAILS, the failure message lists exactly which ability names are missing or blank in `ability_effects.yml` — add/fix those entries (spelling must match `abilities.yml`) until green.

- [ ] **Step 3: Commit**

```bash
git add test/services/soul_link/game_state_test.rb
git commit -m "test(abilities): assert every ability has an effect entry"
```

---

## Task 3: Helper blurbs for ERB

**Files:**
- Modify: `app/helpers/pixeldex_helper.rb` (after `pixeldex_nature_label` ~`:59`)
- Test: `test/helpers/pixeldex_helper_test.rb`

- [ ] **Step 1: Write the failing test**

Add to `test/helpers/pixeldex_helper_test.rb` (create the file if it does not exist — see structure below):

```ruby
require "test_helper"

class PixeldexHelperTest < ActionView::TestCase
  test "ability_effect_short returns the blurb for a known ability" do
    assert_equal "Immune to Ground", ability_effect_short("Levitate")
  end

  test "ability_effect_short returns empty string for an unknown ability" do
    assert_equal "", ability_effect_short("Not An Ability")
  end

  test "ability_effect_full returns the full text for a known ability" do
    assert_equal "Contact with this Pokémon may leave the attacker paralyzed.", ability_effect_full("Static")
  end

  test "ability_effect_full returns empty string for an unknown ability" do
    assert_equal "", ability_effect_full("Not An Ability")
  end
end
```

> If `test/helpers/pixeldex_helper_test.rb` already exists, add just the four `test` blocks inside the existing class instead of recreating the file.

- [ ] **Step 2: Run the test to verify it fails**

Run: `bin/rails test test/helpers/pixeldex_helper_test.rb`
Expected: FAIL — `NoMethodError: undefined method 'ability_effect_short'`.

- [ ] **Step 3: Implement the helpers**

In `app/helpers/pixeldex_helper.rb`, add after `pixeldex_nature_label` (~`:59`):

```ruby
  # Short inline blurb for an ability, or "" when unknown
  def ability_effect_short(ability_name)
    SoulLink::GameState.ability_effect(ability_name)&.fetch("short", "") || ""
  end

  # Full hover description for an ability, or "" when unknown
  def ability_effect_full(ability_name)
    SoulLink::GameState.ability_effect(ability_name)&.fetch("full", "") || ""
  end
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bin/rails test test/helpers/pixeldex_helper_test.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/helpers/pixeldex_helper.rb test/helpers/pixeldex_helper_test.rb
git commit -m "feat(abilities): add ability_effect_short/full helpers"
```

---

## Task 4: Shared tooltip controller + styles

**Files:**
- Create: `app/javascript/controllers/ability_tooltip_controller.js`
- Modify: `app/assets/stylesheets/pixeldex.css` (append near the searchable-select block ~`:2829`)

> No JS test framework exists in this repo (the existing Stimulus controllers have no unit tests). Verify manually per the steps below.

- [ ] **Step 1: Create the controller**

Create `app/javascript/controllers/ability_tooltip_controller.js`:

```js
import { Controller } from "@hotwired/stimulus"

// One reusable, position:fixed popup for any descendant carrying
// `data-ability-full`. Mounted once high in the tree; uses event
// delegation (mouseover/mouseout bubble; focusin/focusout for keyboard)
// so it also covers elements created later by JS (dropdown options,
// linked-pokemon cards).
export default class extends Controller {
  connect() {
    this._popup = null
    this._onOver = (e) => this.#maybeShow(e.target)
    this._onOut = (e) => this.#maybeHide(e.target, e.relatedTarget)
    this.element.addEventListener("mouseover", this._onOver)
    this.element.addEventListener("mouseout", this._onOut)
    this.element.addEventListener("focusin", this._onOver)
    this.element.addEventListener("focusout", this._onOut)
  }

  disconnect() {
    this.element.removeEventListener("mouseover", this._onOver)
    this.element.removeEventListener("mouseout", this._onOut)
    this.element.removeEventListener("focusin", this._onOver)
    this.element.removeEventListener("focusout", this._onOut)
    this.#destroyPopup()
  }

  #maybeShow(target) {
    const host = target?.closest?.("[data-ability-full]")
    if (!host) return
    const text = host.getAttribute("data-ability-full")
    if (!text) return
    this.#show(host, text)
  }

  #maybeHide(target, related) {
    const host = target?.closest?.("[data-ability-full]")
    if (!host) return
    // Ignore moves that stay within the same host element.
    if (related && host.contains(related)) return
    this.#hide()
  }

  #show(host, text) {
    const popup = this.#ensurePopup()
    popup.textContent = text
    popup.style.visibility = "hidden"
    popup.style.display = "block"

    const rect = host.getBoundingClientRect()
    const pr = popup.getBoundingClientRect()
    // Prefer above; flip below if it would clip the viewport top.
    let top = rect.top - pr.height - 6
    if (top < 4) top = rect.bottom + 6
    let left = rect.left
    const maxLeft = window.innerWidth - pr.width - 4
    if (left > maxLeft) left = Math.max(4, maxLeft)

    popup.style.top = `${Math.round(top)}px`
    popup.style.left = `${Math.round(left)}px`
    popup.style.visibility = "visible"
  }

  #hide() {
    if (this._popup) this._popup.style.display = "none"
  }

  #ensurePopup() {
    if (!this._popup) {
      this._popup = document.createElement("div")
      this._popup.className = "gb-tooltip"
      this._popup.setAttribute("role", "tooltip")
      document.body.appendChild(this._popup)
    }
    return this._popup
  }

  #destroyPopup() {
    if (this._popup) {
      this._popup.remove()
      this._popup = null
    }
  }
}
```

- [ ] **Step 2: Add the styles**

Append to `app/assets/stylesheets/pixeldex.css`:

```css
/* Ability hover popup — shared, fixed-position, never clipped. */
.gb-tooltip {
  position: fixed;
  z-index: 80;                /* above modal (50/60) and dropdown (70) */
  display: none;
  max-width: 220px;
  padding: 4px 6px;
  font-size: 10px;
  line-height: 14px;
  background: var(--d1);
  color: var(--l2);
  border: var(--border-thin);
  pointer-events: none;
}

/* Dimmed short blurb inside a searchable-select option. */
.ss-option-meta {
  color: var(--d2);
  font-size: 9px;
  margin-left: 6px;
}
.searchable-select-option.is-active .ss-option-meta,
.searchable-select-option:hover .ss-option-meta {
  color: var(--l2);
}
```

- [ ] **Step 3: Commit**

```bash
git add app/javascript/controllers/ability_tooltip_controller.js app/assets/stylesheets/pixeldex.css
git commit -m "feat(abilities): shared ability-tooltip controller + gb-tooltip styles"
```

(The controller auto-registers via `eagerLoadControllersFrom`; it does nothing until mounted + data attributes exist, wired in the next tasks.)

---

## Task 5: Wire effects JSON to JS and mount the tooltip

**Files:**
- Modify: `app/views/dashboard/show.html.erb` (`.dash-r1` root ~`:13-30`)
- Modify: `app/views/map/show.html.erb` (root data attrs ~`:18-35`)
- Modify: `app/javascript/controllers/pixeldex_controller.js` (`static values` ~`:16`)

- [ ] **Step 1: Add the controller + data-attr on the dashboard root**

In `app/views/dashboard/show.html.erb`, change the `data-controller` on `.dash-r1` (~`:14`) to include `ability-tooltip`:

```erb
     data-controller="dashboard pixeldex run-management party-drag ability-tooltip"
```

And add this data-attribute alongside `data-pixeldex-natures-data-value` (~`:22`):

```erb
     data-pixeldex-ability-effects-data-value="<%= SoulLink::GameState.ability_effects.to_json %>"
```

- [ ] **Step 2: Add the controller + data-attr on the map root**

In `app/views/map/show.html.erb`, find the root element's `data-controller` attribute and append ` ability-tooltip` to its value. Then add alongside `data-pixeldex-natures-data-value` (~`:29`):

```erb
     data-pixeldex-ability-effects-data-value="<%= SoulLink::GameState.ability_effects.to_json %>"
```

> To locate the map root's `data-controller`: `grep -n 'data-controller' app/views/map/show.html.erb` — append `ability-tooltip` to the existing space-separated list on that element.

- [ ] **Step 3: Register the value on the pixeldex controller**

In `app/javascript/controllers/pixeldex_controller.js`, add to `static values` (~`:16-25`):

```js
    abilityEffectsData: Object,
```

(Place it after `naturesData: Object,` for readability.)

- [ ] **Step 4: Manual verification**

Run: `bin/dev`, open the dashboard. In the browser console:
```js
document.querySelector(".dash-r1").dataset.pixeldexAbilityEffectsDataValue.slice(0, 40)
```
Expected: a JSON string beginning `{"Adaptability":{"short":`. No console errors on load.

- [ ] **Step 5: Commit**

```bash
git add app/views/dashboard/show.html.erb app/views/map/show.html.erb app/javascript/controllers/pixeldex_controller.js
git commit -m "feat(abilities): expose ability effects to JS + mount tooltip"
```

---

## Task 6: ABILITY EFFECT blurb in the detail modal

**Files:**
- Modify: `app/views/dashboard/_pokemon_modal.html.erb` (ability field ~`:64-90`)
- Modify: `app/javascript/controllers/pixeldex_controller.js` (targets ~`:9`, `#populateAbilities` ~`:532`, add updater near `#updateNatureLabelFromValue` ~`:526`)

- [ ] **Step 1: Add the blurb element + meta value in the modal**

In `app/views/dashboard/_pokemon_modal.html.erb`, add the `meta` value to the ability `.searchable-select` wrapper (~`:64-67`), so the block reads:

```erb
        <div class="searchable-select"
             data-controller="searchable-select"
             data-searchable-select-options-value="<%= SoulLink::GameState.all_abilities.to_json %>"
             data-searchable-select-meta-value="<%= SoulLink::GameState.ability_effects.to_json %>"
             data-searchable-select-visible-count-value="5">
```

Then add the blurb line **inside** the `.searchable-select` div, immediately after the hidden input (~`:88`) and before that div's closing `</div>` (~`:89`) — so it sits under the ABILITY field within the same grid column. Do **not** place it after `:89` (that would make it a third grid child and misalign the two-column row):

```erb
          <input type="hidden"
                 data-searchable-select-target="hidden"
                 data-pixeldex-target="modalAbility"
                 data-action="change->pixeldex#updateAbilityLabel">
          <div data-pixeldex-target="modalAbilityLabel"
               style="font-size: 9px; color: var(--d2); margin-top: 3px; min-height: 12px; cursor: help;"></div>
```

(The `data-action` on the hidden input is added here too; Step 4 explains why — the searchable-select fires `change` on commit. If you prefer, add the blurb `<div>` first and the `data-action` in Step 4; the end state is identical.)

- [ ] **Step 2: Register the target**

In `app/javascript/controllers/pixeldex_controller.js`, add `"modalAbilityLabel"` to `static targets` (~`:9`, next to `"modalAbility"`):

```js
    "modalSpeciesInput", "modalSpeciesHidden", "modalLevel", "modalAbility", "modalAbilityLabel",
```

- [ ] **Step 3: Add the updater and call it on populate**

In `app/javascript/controllers/pixeldex_controller.js`, add this private method right after `#updateNatureLabelFromValue` (~`:526`):

```js
  #updateAbilityLabelFromValue(ability) {
    if (!this.hasModalAbilityLabelTarget) return
    const label = this.modalAbilityLabelTarget
    const effect = this.abilityEffectsDataValue?.[ability]
    if (!ability || !effect) {
      label.textContent = ""
      label.removeAttribute("data-ability-full")
    } else {
      label.textContent = effect.short || ""
      if (effect.full) {
        label.setAttribute("data-ability-full", effect.full)
      } else {
        label.removeAttribute("data-ability-full")
      }
    }
  }
```

Then, at the end of `#populateAbilities` (~`:538`, after the `if (input) input.value = ...` line), call it:

```js
    this.#updateAbilityLabelFromValue(currentAbility || "")
```

- [ ] **Step 4: Keep the blurb in sync when the user picks a new ability**

The ability searchable-select commits into the hidden field `data-pixeldex-target="modalAbility"` and dispatches a `change` event (see `searchable_select_controller.js#commit`). Wire that change to refresh the blurb: in `_pokemon_modal.html.erb`, add a `data-action` to the hidden ability field (~`:86-88`):

```erb
          <input type="hidden"
                 data-searchable-select-target="hidden"
                 data-pixeldex-target="modalAbility"
                 data-action="change->pixeldex#updateAbilityLabel">
```

And add the public action in `pixeldex_controller.js` right after the `updateNatureLabel()` method (~`:514`):

```js
  updateAbilityLabel() {
    this.#updateAbilityLabelFromValue(this.modalAbilityTarget.value)
  }
```

- [ ] **Step 5: Manual verification**

Run `bin/dev`, open the dashboard, click a PC box cell to open the modal.
- Expected: under the ABILITY field, the current ability's short blurb shows (e.g. `Immune to Ground` for a Levitate mon).
- Hover the blurb: the `.gb-tooltip` popup shows the full sentence.
- Pick a different ability from the dropdown: the blurb updates immediately.
- Clear/empty ability: blurb disappears, no stray tooltip.

- [ ] **Step 6: Commit**

```bash
git add app/views/dashboard/_pokemon_modal.html.erb app/javascript/controllers/pixeldex_controller.js
git commit -m "feat(abilities): ABILITY EFFECT blurb + hover in detail modal"
```

---

## Task 7: Blurbs inside the ability dropdown options

**Files:**
- Modify: `app/javascript/controllers/searchable_select_controller.js` (values ~`:10-13`, `#render` ~`:119-145`)

> `.ss-option-meta` CSS was already added in Task 4.

- [ ] **Step 1: Add the optional `meta` value**

In `app/javascript/controllers/searchable_select_controller.js`, extend `static values` (~`:10-13`):

```js
  static values = {
    options: Array,
    meta: Object,
    visibleCount: { type: Number, default: 5 }
  }
```

- [ ] **Step 2: Render the blurb + tooltip attr per option**

In `#render` (~`:130-141`), replace the option-building loop body so each `<li>` carries the blurb and `data-ability-full` when metadata exists. The full loop becomes:

```js
    this._filtered.forEach((option, index) => {
      const li = document.createElement("li")
      li.dataset.value = option
      li.id = `${this._uid}-opt-${index}`
      li.setAttribute("role", "option")
      li.setAttribute("aria-selected", String(index === this._activeIndex))
      li.className =
        "searchable-select-option" + (index === this._activeIndex ? " is-active" : "")
      li.setAttribute("data-action", "mousedown->searchable-select#selectOption")

      const meta = this.hasMetaValue ? this.metaValue[option] : null
      if (meta) {
        const name = document.createElement("span")
        name.textContent = option
        li.appendChild(name)
        if (meta.short) {
          const blurb = document.createElement("span")
          blurb.className = "ss-option-meta"
          blurb.textContent = meta.short
          li.appendChild(blurb)
        }
        if (meta.full) li.setAttribute("data-ability-full", meta.full)
      } else {
        li.textContent = option
      }

      this.listTarget.appendChild(li)
    })
```

> Note: `textContent = option` from the original code is preserved in the `else` branch, so a searchable-select without a `meta` value renders exactly as before.

- [ ] **Step 3: Manual verification**

Run `bin/dev`, open the modal, focus the ABILITY search input to open the dropdown.
- Expected: each option shows the ability name plus a dimmed short blurb to its right.
- Hover an option: the full-description popup appears (not clipped by the scrolling list).
- Confirm keyboard arrow-select still works and picking an option still fills the field.

- [ ] **Step 4: Commit**

```bash
git add app/javascript/controllers/searchable_select_controller.js
git commit -m "feat(abilities): show effect blurbs in the ability dropdown"
```

---

## Task 8: Ability blurb on the linked-Pokémon cards

**Files:**
- Modify: `app/javascript/controllers/pixeldex_controller.js` (`#renderLinkedPokemon` stats row ~`:747-762`)

- [ ] **Step 1: Render the ability as a tooltip span with its blurb**

In `#renderLinkedPokemon`, the stats row is currently assembled as plain text joined by `" / "`. Replace the block that builds and appends the stats row (~`:747-762`) with node-based assembly so the ability token can carry a blurb + `data-ability-full` while level/nature stay text:

```js
        // Stats row: level, ability (with effect blurb), nature
        const statsRow = document.createElement("div")
        statsRow.style.cssText = "font-size: 9px; color: var(--d2);"
        const parts = []
        if (p.level) parts.push(document.createTextNode(`Lv.${p.level}`))
        if (p.ability) {
          const effect = this.abilityEffectsDataValue?.[p.ability]
          const abilitySpan = document.createElement("span")
          abilitySpan.textContent = effect?.short ? `${p.ability} (${effect.short})` : p.ability
          if (effect?.full) {
            abilitySpan.setAttribute("data-ability-full", effect.full)
            abilitySpan.style.cursor = "help"
          }
          parts.push(abilitySpan)
        }
        if (p.nature) {
          const info = naturesData[p.nature]
          const effect = (info && info.up) ? ` (+${info.up} -${info.down})` : ""
          parts.push(document.createTextNode(`${p.nature}${effect}`))
        }

        if (parts.length) {
          parts.forEach((node, i) => {
            if (i > 0) statsRow.appendChild(document.createTextNode(" / "))
            statsRow.appendChild(node)
          })
          card.appendChild(statsRow)
        }
```

> This preserves the existing `Lv.X / Ability / Nature` layout and the nature `(+X -Y)` treatment; only the ability token becomes a hoverable span. `naturesData` is the local const already defined at the top of `#renderLinkedPokemon` (~`:705`).

- [ ] **Step 2: Manual verification**

Run `bin/dev`, open a modal for a group where other players have assigned Pokémon (LINKED POKEMON section populated).
- Expected: each linked Pokémon's stats line shows `Ability (short blurb)`.
- Hover the ability: full-description popup appears.
- A Pokémon with an unknown/blank ability still renders its name with no blurb and no tooltip.

- [ ] **Step 3: Commit**

```bash
git add app/javascript/controllers/pixeldex_controller.js
git commit -m "feat(abilities): effect blurb + hover on linked-pokemon cards"
```

---

## Task 9: Ability blurb on the gym team snapshot

**Files:**
- Modify: `app/views/dashboard/_gyms_content.html.erb` (per-Pokémon line ~`:91-96`)

- [ ] **Step 1: Render the ability token as a tooltip span**

In `app/views/dashboard/_gyms_content.html.erb`, replace the stats block (~`:91-96`) that currently builds `stats = [Lv, ability, nature].compact` and joins with `" / "`. New version keeps level/nature as plain text and wraps the ability in a span carrying its blurb + `data-ability-full`:

```erb
                    <div style="margin-left: 8px; color: var(--d2);">
                      <%= p["player_name"] %>: <%= p["species"] %>
                      <% parts = [] %>
                      <% parts << ERB::Util.html_escape("Lv.#{p["level"]}") if p["level"] %>
                      <% if p["ability"].present? %>
                        <% blurb = ability_effect_short(p["ability"]) %>
                        <% full = ability_effect_full(p["ability"]) %>
                        <% label = blurb.present? ? "#{p["ability"]} (#{blurb})" : p["ability"] %>
                        <% parts << content_tag(:span, label, "data-ability-full": full.presence, style: ("cursor: help;" if full.present?)) %>
                      <% end %>
                      <% parts << ERB::Util.html_escape(p["nature"]) if p["nature"].present? %>
                      <% if parts.any? %><span style="color: var(--d2);"> &mdash; <%= safe_join(parts, " / ") %></span><% end %>
                    </div>
```

> `content_tag` with a nil `data-ability-full` omits the attribute; `full.presence` yields nil when blank, so unknown abilities get a plain span with no tooltip. `safe_join` keeps the escaped level/nature text safe while allowing the ability span's markup.

- [ ] **Step 2: Manual verification**

Run `bin/dev`, open the GYMS tab and expand a gym result that has a `team_snapshot` (a recorded gym battle team).
- Expected: each Pokémon line reads `Player: Species — Lv.X / Ability (blurb) / Nature`.
- Hover the ability: full-description popup appears (the `ability-tooltip` controller on `.dash-r1` covers this server-rendered surface).
- If no gym result has a snapshot locally, verify the ERB renders without error by loading the GYMS tab (no exception) and spot-check markup via view source.

- [ ] **Step 3: Run the full suite + lint**

Run: `bin/rails test`
Expected: PASS (all suites, including the new helper/GameState tests).

Run: `bundle exec rubocop app/helpers/pixeldex_helper.rb app/services/soul_link/game_state.rb app/views/dashboard/_gyms_content.html.erb`
Expected: no new offenses.

- [ ] **Step 4: Commit**

```bash
git add app/views/dashboard/_gyms_content.html.erb
git commit -m "feat(abilities): effect blurb + hover on gym team snapshot"
```

---

## Self-Review Notes

- **Spec coverage:** Goal 1 (inline blurb) → Tasks 6/8/9; Goal 2 (styled hover) → Tasks 4/5; Goal 3 (all three surfaces) → Tasks 6+7 (modal), 8 (linked cards), 9 (gym snapshot); Goal 4 (all 123 authored) → Task 1 data + Task 2 integrity test.
- **Type/name consistency:** `abilityEffectsData` value → `this.abilityEffectsDataValue` (Tasks 5/6/8); `meta` value → `this.metaValue` / `this.hasMetaValue` (Task 7); `data-ability-full` attribute is the single contract the `ability-tooltip` controller reads (Tasks 4/6/7/8/9); `ability_effect` (hash) vs `ability_effect_short`/`ability_effect_full` (strings) used consistently.
- **YAML safety:** all values are double-quoted flow scalars; `Pokémon` is UTF-8; no unescaped colons/quotes inside values.
- **No-op safety:** `searchable_select` without a `meta` value falls through to `li.textContent = option` (unchanged behavior for any future adopter).

## Known follow-ups (out of scope)

- Ability descriptions are transcribed from Gen-IV Platinum mechanics and warrant a human spot-check for wording/accuracy (the integrity test guarantees completeness, not correctness).
- The PC box cell list (`_pc_box_content.html.erb`) shows nature only, not ability — left unchanged, consistent with the current design.
