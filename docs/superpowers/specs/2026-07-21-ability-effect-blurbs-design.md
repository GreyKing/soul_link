# Ability Effect Blurbs + Hover Popups — Design

**Date:** 2026-07-21
**Branch:** `claude/nature-ability-stat-effects-3f183d`

## Problem

Natures show their effect at a glance. `PixeldexHelper::NATURES` maps each of the
25 natures to `{ up:, down: }` and renders a compact delta like `+Atk -Spd`. It
surfaces in the detail modal's "STAT EFFECT" field, the damage-calc nature
dropdowns, and the JS linked-Pokémon cards.

Abilities have no equivalent. All 123 Gen-IV abilities render as a bare name
string with zero indication of what they do. A player reading a team has to
already know that "Levitate" means Ground immunity or that "Static" can paralyze
on contact. There is **no ability description/effect data anywhere in the repo.**

## Goals

1. A **short inline blurb** next to each ability name (parallel to the nature
   `+X -Y` label), e.g. `Levitate` → `Immune to Ground`.
2. A **Game-Boy-styled hover popup** showing the full Gen-IV description when the
   user hovers an annotated ability. (Hover-only, matching the nature label,
   which has no keyboard/tooltip treatment; the annotated elements are
   non-focusable, so focus-based popups would be dead code.)
3. Applied on **every surface an ability renders**: the detail modal (including
   its searchable-select dropdown), the JS linked-Pokémon cards, and the gym
   team snapshot.
4. Authored data for **all 123 abilities** so no ability is ever blank.

## Non-goals

- No change to how natures render — this only adds a parallel ability treatment.
- No ability data in the damage calculator (the calc has no ability input, and
  abilities do not feed damage math here).
- No hidden abilities, no per-species restriction — the annotation is keyed on
  ability name alone, matching the existing "any Pokémon may have any ability"
  selector behavior.
- No tooltips on arbitrary non-ability text; scoped to ability names.

## Design

### 1. Data — `config/soul_link/ability_effects.yml`

New YAML file beside `abilities.yml`, mapping each ability name → a hash with a
`short` and `full` string:

```yaml
# config/soul_link/ability_effects.yml
Levitate:  { short: "Immune to Ground",        full: "Gives full immunity to all Ground-type moves." }
Static:    { short: "May paralyze on contact", full: "Contact with this Pokémon may leave the attacker paralyzed." }
Overgrow:  { short: "Boosts Grass at low HP",  full: "Powers up Grass-type moves when the Pokémon's HP is low." }
Intimidate:{ short: "Lowers foe's Attack",     full: "Lowers the opposing Pokémon's Attack stat on entering battle." }
```

- **All 123 abilities** from `SoulLink::GameState.all_abilities` get an entry.
  Descriptions are authored from Gen-IV Platinum mechanics. `short` is a terse
  ~2–5 word blurb; `full` is a single sentence matching the in-game flavor.
- Keys match ability strings in `abilities.yml` exactly (same source of truth for
  spelling/casing, e.g. `Compound Eyes`, `Lightning Rod`).

### 2. Loader + helper

`app/services/soul_link/game_state.rb` — parallel to `pokemon_abilities`:

- `ABILITY_EFFECTS_PATH = CONFIG_DIR.join("ability_effects.yml")` (match the
  existing path-constant convention).
- `ability_effects` — memoized `YAML.load_file` guarded by `File.exist?`,
  returns `{}` when absent.
- `ability_effect(name)` — returns the `{ "short" =>, "full" => }` hash for a
  name, or `nil`.
- `reload!` — nils `@ability_effects`.

`app/helpers/pixeldex_helper.rb`:

- `ability_effect_short(name)` — returns the short blurb string, or `""` when the
  ability is unknown/missing (mirrors `pixeldex_nature_label`'s empty-string
  fallback).
- `ability_effect_full(name)` — returns the full string, or `""`.

**JS exposure:** the pixeldex root already carries
`data-pixeldex-abilities-data-value` (species → abilities). Add a sibling
`data-pixeldex-ability-effects-data-value="<%= SoulLink::GameState.ability_effects.to_json %>"`
on both `dashboard/show.html.erb` and `map/show.html.erb`, read into a new
`abilityEffectsData: Object` value on the pixeldex controller.

### 3. Tooltip — one shared, delegated popup

The dropdown list, linked-cards container, and gym snapshot card all live inside
`overflow: auto`/`hidden` scroll containers (e.g. `.searchable-select-list` has
`overflow-y: auto` + `max-height`), so a pure-CSS `::after` tooltip would be
**clipped**. Instead:

- **`app/javascript/controllers/ability_tooltip_controller.js`** — a small
  Stimulus controller mounted once on the pixeldex root. Because `_gyms_content`
  renders inside that same root (`.dash-r1`), one mount covers all three surfaces
  — no separate mount on the gym container. It delegates `mouseover`/`mouseout`
  (both bubble). When the event target (or its closest ancestor) carries
  `data-ability-full`, it positions a single reusable `position: fixed` popup
  element next to that element and fills it with the full text; on out it hides.
  One popup node is reused (created lazily), never one per ability.
  - Positioning: anchor above the element, flipping below when it would clip the
    viewport top; clamp into the viewport on both axes. Keep it simple — no
    external positioning lib.
- **`.gb-tooltip` in `pixeldex.css`** — dark background (`var(--d1)`), pixel
  border (`var(--border-thin)`), light text (`var(--l2)`), ~10px font, high
  `z-index` (above the modal's 70), `pointer-events: none`, `max-width` ~220px so
  long descriptions wrap.
- Delegation means it works uniformly for server-rendered ERB spans **and**
  JS-generated cards/`<li>`s without per-element wiring.

### 4. The three surfaces

**a. Detail modal — `app/views/dashboard/_pokemon_modal.html.erb` + `pixeldex_controller.js`**

- Add an **"ABILITY EFFECT"** blurb line directly under the ABILITY
  searchable-select (parallel to the NATURE / STAT EFFECT pairing), targeted as
  `modalAbilityLabel`. On ability select/populate, JS sets its text to the short
  blurb and sets `data-ability-full` to the full text (blank both when no
  ability). Populated in `#populateAbilities` and on select, mirroring
  `#updateNatureLabelFromValue`.
- **Searchable-select dropdown options:** extend the generic
  `searchable_select_controller.js` with an **optional** `meta` value
  (`Object`, option → `{ short, full }`). When present, `#render` appends a dimmed
  short blurb to each `<li>` and sets `data-ability-full` on it; when absent the
  controller behaves exactly as today (stays option-agnostic). The modal's
  ability `.searchable-select` passes
  `data-searchable-select-meta-value="<%= SoulLink::GameState.ability_effects.to_json %>"`.

**b. Linked-Pokémon cards — `pixeldex_controller.js` `#populateLinked`**

- Where the stats row currently pushes the plain ability string, render the
  ability as a `<span>` reading `Ability (short blurb)` — mirroring the nature
  `(+X -Y)` treatment two lines below it — with `data-ability-full` set. Because
  this row is built as text today, the ability entry becomes a small span while
  level/nature stay text (assemble the row from nodes, or keep it HTML with the
  ability span). Blurb/full looked up from `abilityEffectsDataValue`.

**c. Gym team snapshot — `app/views/dashboard/_gyms_content.html.erb`**

- The per-Pokémon line currently does
  `stats = [Lv, ability, nature].compact` then `stats.join(" / ")`. Rebuild the
  ability portion as a `<span>` carrying `ability_effect_short` (as `(blurb)`)
  and `data-ability-full`, `safe_join`-ing the parts so the ability span keeps
  its tooltip while level/nature remain plain text.
- No extra controller mount is needed here: `_gyms_content` renders inside
  `.dash-r1`, which already hosts the `ability-tooltip` controller, so hover works
  on this server-rendered surface via delegation.

### 5. Tests

- **`pixeldex_helper_test.rb`** — `ability_effect_short` / `ability_effect_full`
  return the authored blurb/full for a known ability and `""` for an unknown one.
- **`game_state_ability_effects_test.rb`** (new, per-feature — GameState tests are
  split per feature; there is no `game_state_test.rb`) — `ability_effects` loads
  the YAML; `ability_effect` returns the hash for a known name and `nil` for an
  unknown one.
- **Data-integrity test** (same file) — asserts **every** name in
  `all_abilities` has an entry in `ability_effects.yml` with non-empty `short`
  and `full`. This is the guard that catches missing/mis-typed authoring for any
  of the 123.
- No JS test framework exists in the repo; the Stimulus controllers are verified
  manually (the existing `searchable_select`/`pixeldex` controllers have no unit
  tests either — consistent with house convention).

## Trade-offs

- **Shared JS tooltip over pure CSS:** ~40 extra lines of controller + a reused
  popup node, but it is the only approach that won't clip inside the scrollable
  dropdown and snapshot containers, given the "everywhere" scope. Accepted
  (user-confirmed styled-tooltip + everywhere).
- **Authoring 123 descriptions by hand:** the data is the bulk of the work and is
  transcribed from Gen-IV mechanics, so it warrants a spot-check by the user. The
  data-integrity test guarantees completeness (no blanks) but not correctness of
  wording — that is a human review.
- **`meta` on the generic combobox:** slightly widens the "option-agnostic"
  contract of `searchable_select_controller`. Kept strictly optional and no-op
  when unset so the species field (a future adopter) is unaffected.
- **Gym snapshot becomes HTML-assembled:** the `join(" / ")` string becomes a
  `safe_join` of spans. Marginally more markup, but required to attach the
  tooltip data to just the ability token.
