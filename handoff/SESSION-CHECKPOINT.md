# Session Checkpoint
*Read this before reading anything else. If it covers current state, skip BUILD-LOG.*
*Session-scoped — archived to `handoff/archive/` at session end.*

---

## Where We Stopped

Step 14 (Gym Draft — Path B unified nominate-or-endorse model) shipped + FF-merged to `main` + pushed. Awaiting next brief from Project Owner.

---

## What Was Built

**Step 14 — Path B: unified nominate-or-endorse + avatar caching + 60s skip grace + TCG-coin tiebreak.**

The nominating phase of gym drafts was rewired from "submit nomination → up/down vote → resolve" round-robin into a single 4-pick "nominate or endorse" pass. Each of the 4 players makes exactly one pick during nominating; the model auto-detects whether the picked group is a NEW candidate (creates one) or an ENDORSEMENT (adds picker to existing candidate's voters list). After all 4 picks, top-2 by voter count fill slots 5+6. Tied at the slot boundary → server randomly picks winners + populates a `tiebreak` payload; the client animates a TCG-coin flip modal during the reveal.

**Also shipped:**
- Avatar caching layer (`SoulLinkRun#player_avatars` JSON column, upserted on login, helper for rendering with initial-circle fallback).
- 60s skip grace (timer in `state_data`, model + channel auth: nominator-only inside grace, anyone after).
- Q5 button-weight fix on the draft-complete page (BACK TO GYM READY no longer competes with MARK BEATEN).

**Counts:** 343 → 370 tests (+27). Rubocop clean (152 files, 0 offenses). 2 migrations.

**TCG-coin path:** primary (not the fallback). Two-face 3D coin: pokeball face via radial+linear gradients (red top / white bottom / black equator / central button), character face as gold disc with star glyph (deliberate simplification within the 30-min time-box). 1.8s rotateY 0→1980deg + cubic-bezier easing + 12px translateY settle bounce.

---

## What Was Decided This Session

- **Path B chosen over Path A** after reading the gym-draft audit (`handoff/2026-05-01-gym-draft-audit.md`). Project Owner unified Path B's two phases (nominate + rank) into a single pass via the "endorsement" affordance.
- **Captain has no special role in nominating.** All 4 players have equal weight; tiebreaks are uniform-random (Array#sample). The Path A captain-tiebreak narrative was discarded.
- **Edge case "1-candidate consensus"** (all 4 endorse same group) → team has 5 picks, slot 6 stays empty. Explicit decision; do not "fix" by re-running a round.
- **Skip auth: 60s grace.** Nominator-only inside; anyone after. Visible per-second countdown in UI.
- **TCG-coin > pokéball.** Pokémon-themed but specifically the trading-card-game metal coin aesthetic with 3D rotateY animation. Modal copy: "★ WILD COIN APPEARED! ★". Server picks winners; client only animates.
- **Avatar caching via JSON column on SoulLinkRun.** Upserted on login. No new table, no Discord API hits beyond OAuth.
- **`current_turn_started_at` lives in state_data**, not as a column. Avoids a third migration.
- **Path A mockup left in `handoff/`** as historical record (not archived). The user explicitly approved leaving it.

---

## Known Gaps / Future Work

*See `handoff/BUILD-LOG.md` Known Gaps — running list maintained there.*

Step 14 logged one new gap: **in-browser smoke deferred** for the TCG-coin animation visual fidelity, the per-second grace countdown tick, and the avatar-pile image-vs-initial branch (only rendered with real Discord URLs in the wild). Continuation of the Step 13 environmental quirk (`bin/dev` / foreman / tailwind-v4 collision in the sandbox). Pick up next dashboard- or draft-touching step that gets a real browser. All algorithmic + payload-shape correctness is test-covered.

KG-7 (real-save offset verification) still open from Step 12.

---

## Resume Prompt

Copy and paste this to resume:

---

You are Ava (Architect) on Soul Link — Three Man Team.
Read handoff/SESSION-CHECKPOINT.md, then handoff/BUILD-LOG.md.
Confirm status and next action. Then wait for direction.

---
