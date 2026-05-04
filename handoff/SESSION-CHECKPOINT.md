# Session Checkpoint
*Read this before reading anything else. If it covers current state, skip BUILD-LOG.*
*Session-scoped — archived to `handoff/archive/` at session end.*

---

## Where We Stopped

Step 19 (Move-name lookup + Discord notifier + Wipe check) shipped at `435a1c9`, FF-merged to `origin/main` and pushed. Worktree branch `claude/pedantic-jemison-e7d667` also pushed. Awaiting next brief from Project Owner.

---

## What Was Built

**Step 19 — Move-name lookup + Discord notifier + Wipe check.**

Three orthogonal "events that happen during a run get observed and surfaced" features bundled. The move-name lookup mirrors the species (KG-20) and met-location (KG-12) static-data lookup pattern. The Discord notifier follows the Step-15 fan-out architecture — coordinators do model state, the notifier does Discord, separation enforced by treating the notifier as a fire-and-forget side effect at the END of each coordinator/controller branch. The wipe coordinator is a third Step-15-style coordinator but invoked from the controller path (Mark Dead) rather than from `SaveDiffDispatcher` — wipes only fire on manual death transitions in this step.

**Surfaces introduced:**
- `config/soul_link/move_names.yml` — 467 entries (IDs 1..467 contiguous, no gaps). Sourced from PKHeX `text_Moves_en.txt` lines 2..468 (line 1 is the `———` no-move sentinel; ID 0 intentionally absent). Cross-checked against pret/pokeplatinum `MOVE_SHADOW_FORCE = 467`. Citation header in the file.
- `SoulLink::GameState.move_name(id)` — nil-safe lookup with integer coercion (mirrors `map_name` and `met_location_name`). `move_names` (memoized loader) and `@move_names` reset added to `reload!`.
- `EmulatorHelper#format_move_name(id)` — `"Move ##{id}"` fallback for unknown IDs (mirrors `format_map_name`'s shape).
- `_pc_box_content.html.erb` STATS expander — `MOVE n: #N · PP n · ↑n` → `MOVE n: <Name> · PP n · ↑n`.
- `app/services/soul_link/discord_notifier.rb` — class-only outgoing-message service. Six fire-and-forget public methods. Full rescue chain (REST/socket exceptions enumerated for documentation, terminating in `StandardError`). Never raises. Channel routing per decision in BUILD-LOG.
- `app/services/soul_link/wipe_coordinator.rb` — `process(run)` walks `SoulLink::GameState.player_ids`, finds the first player with caught Pokemon AND zero alive, sets `wiped_at` inside `with_lock` (idempotent: outer guard + inner double-check), fires `notify_wipe` with the most recent dead Pokemon's location.
- `db/migrate/20260504000001_add_wiped_at_to_soul_link_runs.rb` — `add_column :soul_link_runs, :wiped_at, :datetime` (nullable, no index).
- `SoulLinkRun#wiped?` / `#read_only?` (`wiped_at.present? && !completed?`) / `broadcast_state[:wiped_at]`.
- `ApplicationHelper#dashboard_read_only?(run)` — single-source-of-truth helper for v1 UI gating.
- Wipe banner in `_runs_content.html.erb` (`💀 RUN ENDED — WIPED <date>`, above gb-grid-4 stats).
- Affordance hide-guards on `_pc_box_content.html.erb` (NEW CATCH), `_pokemon_modal.html.erb` (MARK DEAD), `_gyms_content.html.erb` (MARK BEATEN / UNMARK / START GYM DRAFT), and `map/show.html.erb` (NEW CATCH form — folded in during deploy gate per Richard's escalation).
- Notifier wired into `CatchCoordinator.create_pokemon_row` (party + box paths, after `create!`, inside slot transaction), `GymBeatenCoordinator.process` (per-player on every `BadgeGained`; team on the `!was_marked && now_marked` precondition flip), `HallOfFameCoordinator.process` (after `update!(completed_at:)`; idempotency from existing `completed_at.present?` guard), `PokemonGroupsController#update` (notify_death per linked Pokemon after `mark_as_dead!`, then `WipeCoordinator.process(run)`), `GymProgressController#update` (manual MARK BEATEN = team event; UNMARK fires nothing).

**Counts:** 596 → 654 tests (+58). 1906 → 2011 assertions, 0 failures, 0 errors. Rubocop clean (184 → 191 files, 0 offenses). Brakeman clean (0 errors, 2 pre-existing weak-confidence warnings unchanged). 1 migration.

**Review:** 0 Must Fix, 0 Should Fix, 2 Nice-to-Have (rescue list redundancy + view-var inconsistency, both noted as-is). 1 Note escalated and folded in (map-view NEW CATCH form gating for read-only consistency — two-line edit to `app/views/map/show.html.erb`).

---

## What Was Decided This Session

- **Discord notifier is a NEW service, NOT a touch of `discord_bot.rb`.** Project review flagged the 978-LOC god-object; brief explicitly forbade adding load. Notifier uses `Discordrb::API::Channel.create_message(token, channel_id, content)` directly — same pattern as `DiscordApi.create_run_channels`. The bot god-object decomposition remains a future step.
- **Notifier failure isolation: log + return, never raise.** Full rescue chain ends in `StandardError`. Underlying coordinator/controller transactions always commit even when Discord is down.
- **Notifier invocation is at coordinator/controller granularity, NOT pub/sub.** No ActiveSupport::Notifications. No event-bus indirection. Direct method calls at the end of each mutation path. The notifier itself is dumb; the call site decides whether to invoke.
- **Wipe trigger = any single player has 0 alive AND has caught at least one.** Translation of the user's exact convention ("If we get all our mons killed in a battle, the run is over") into coordinator logic. The `has caught at least one` guard prevents brand-new-run false-positives.
- **`WipeCoordinator` idempotency = outer guard + inner double-check inside `with_lock`.** Handles concurrent Mark Dead requests safely. Ruby `do/end` block `return` exits the enclosing method.
- **HoF wins over wipe in `read_only?`.** `read_only? = wiped_at.present? && !completed?`. Semantic: HoF means a player actually finished, even if a partner wiped after.
- **Read-only mode = UI hide-only in v1.** Server-side authz on disabled endpoints is logged as KG-28. The buttons hide; the underlying controllers still accept requests. The single-source-of-truth helper `dashboard_read_only?(run)` keeps gating decisions in one place.
- **Wipe is reversible via direct AR ONLY.** `run.update!(wiped_at: nil)`. No UI for un-wiping. KG-27.
- **Map-view NEW CATCH form gated.** Richard escalated this as a parallel surface not in the brief's affordance list. Architect call: fold in. Read-only mode propagates to all catch surfaces, not just dashboard ones. Two-line edit.
- **HoF Discord notification bundled (closes KG-17).** Brief left it as "bundle if trivial OR defer." Architect picked bundle — the coordinator is right there and the notifier is being built; one more 1-liner.
- **Move-name source = PKHeX `text_Moves_en.txt` lines 2..468.** Brief specified IDs 1..467. PKHeX file is 1-indexed but line 1 is the no-move sentinel; lines 2..468 map to IDs 1..467 cleanly. Bob caught the off-by-one; Richard verified all five boundary IDs (1, 33, 165, 257, 467) plus three Gen-IV-only spot-checks (354, 400, 428) match the source.

---

## Known Gaps / Future Work

*See `handoff/BUILD-LOG.md` Known Gaps — running list maintained there.*

Step 19 closed KG-17 (HoF Discord notification), KG-22 (auto-detected catch Discord notification), KG-24 (move-name lookup). Logged five new gaps:
- **KG-26** — No real-SRAM smoke test for `move_names.yml` lookup. Same parity argument as KG-25 (synthetic test data uses the same lookup the production code does).
- **KG-27** — No UI to un-wipe a run. `run.update!(wiped_at: nil)` is the only un-wipe path. Mirrors KG-19 (HoF un-completion).
- **KG-28** — No server-side authz for read-only-mode-disabled endpoints. UI-hide only is the v1 contract. Server enforcement (`before_action :reject_when_read_only` returning 422) is a follow-up.
- **KG-29** — No auto-detect of dead Pokemon from save diff. A Pokemon disappearing from both party and box could be a release; future inference step would need a heuristic + confirmation UX.
- **KG-30** — `broadcast_state[:wiped_at]` has no current consumer. Forward-looking key for future client-side wipe-state UI.

KG-7 (real-save offset verification for `MAP_ID_OFFSET`), KG-20 (species ID fallback), KG-23 (no UI for "this auto-catch is wrong"), KG-25 (real-SRAM smoke test for `BoxParser` + `PkmDecoder`) still open from earlier steps.

In-browser smoke deferred this step — same pattern as Steps 15/16/17/18 (parse-job + service code + view extension; existing `SoulLinkPokemon` + `SoulLinkRun` `broadcasts_refreshes_to` covers the new banner's real-time path).

---

## Resume Prompt

Copy and paste this to resume:

---

You are Ava (Architect) on Soul Link — Three Man Team.
Read handoff/SESSION-CHECKPOINT.md, then handoff/BUILD-LOG.md.
Confirm status and next action. Then wait for direction.

---
