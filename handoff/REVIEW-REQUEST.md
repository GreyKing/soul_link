# Review Request — Step 26: Rebase `--accent` from `--amber` to `--green-glow`

**Branch:** `claude/hungry-cray-ff4938`
**Builder:** Bob
**Status:** Ready for Review: YES
**Date:** 2026-05-06

---

## Summary

Rebases the design canon's main accent token from amber/gold (`#d4b14a`) to vibrant green (`#5fd45f`) per user feedback ("use the lighter green from the gym draft view as the main color"). Mechanical sweep of `var(--amber)` → `var(--accent)` site-wide, plus matching rgba glow decompositions, plus canon-doc + test updates. The `.conflict-warning` block keeps `var(--amber)` per the canon's out-of-canon list.

Slice-by-slice execution per ARCHITECT-BRIEF.md. No scope expansion.

---

## Files changed

| # | File | Change |
|---|---|---|
| 1 | `app/assets/stylesheets/pixeldex.css` | Slice A: line 24 alias `--accent: var(--amber)` → `--accent: var(--green-glow)`. Slice B: 60 of 62 `var(--amber)` swept to `var(--accent)` (2 `.conflict-warning` references at lines 2111-2112 preserved). Slice C: 10 rgba decompositions `rgba(212, 177, 74, …)` → `rgba(95, 212, 95, …)`. |
| 2 | `app/views/dashboard/_runs_content.html.erb` | Line 33: HoF "🏆 COMPLETE" pill — `border-color` + `background` now `var(--accent)` (`color: var(--d1)` untouched). |
| 3 | `app/views/dashboard/_gyms_content.html.erb` | Line 52: NEXT pill `border-color` + `color` → `var(--accent)`. |
| 4 | `app/views/map/show.html.erb` | Line 251: "↓ NOW · log first encounter" caption `color` → `var(--accent)`. |
| 5 | `app/views/gym_drafts/show.html.erb` | Line 194: coin-flip result `color` → `var(--accent)`. |
| 6 | `app/javascript/controllers/gym_draft_controller.js` | Lines 157, 262, 263, 572: 4 inline-style writes `"var(--amber)"` → `"var(--accent)"`. |
| 7 | `app/assets/stylesheets/design_canon.md` | § 1 Accents row: `--accent (= --amber)` `#d4b14a` → `--accent (= --green-glow)` `#5fd45f`. New Step 26 note added under `## 1. Color tokens`. § 8 Borders parenthetical: "4px amber = warn-emphasis" → "4px accent-green = active-emphasis". Opening sentence: "dimmed amber accent" → "dimmed green accent". |
| 8 | `test/integration/design_canon_test.rb` | First test assertion + message updated from amber-aliased expectation to green-glow-aliased expectation (Step 26 wording). |

`--amber: #d4b14a` token in `:root` left intact (positional palette token). `--success: var(--green-glow)` left intact. `.conflict-warning` block intentionally retains `var(--amber)`.

---

## Acceptance grep counts (all match the brief)

```
$ grep -c "var(--amber)" app/assets/stylesheets/pixeldex.css
2                 # the .conflict-warning declaration only (lines 2111-2112) — expected 2 ✓

$ grep -c "rgba(212, 177, 74" app/assets/stylesheets/pixeldex.css
0                 # expected 0 ✓

$ grep -rn "var(--amber)" app/views/ app/javascript/
                  # no hits — expected no hits ✓

$ grep -c "var(--accent)" app/assets/stylesheets/pixeldex.css
59                # was 0 pre-Step-26; now 59 (62 baseline amber − 2 conflict-warning kept − 1 line-24 alias source). Brief said "~45+" ✓

$ grep -rn "var(--amber)" app/
app/assets/stylesheets/pixeldex.css:2111:  background: #4a3a1c; color: var(--amber);
app/assets/stylesheets/pixeldex.css:2112:  border: 1px solid var(--amber);
                  # only the two intentional .conflict-warning references ✓

$ grep -c "rgba(95, 212, 95" app/assets/stylesheets/pixeldex.css
10                # all 10 rgba decompositions migrated ✓
```

`var(--accent)` references in views/JS after Step 26: 4 view occurrences + 4 JS occurrences = 8 — matches the brief's Slice D (4) + Slice E (4) targets exactly.

---

## Test output

Ran the full test suite via `PATH="…/ruby/3.4.5/bin:$PATH" bundle exec rails test` (`bin/rails` is mis-shimmed to ruby 3.0.6 on this worktree — used the standing rule's documented fallback path with the correct ruby pinned).

**Before Step 26:**
```
ok rake test: 782 runs, 0 failures
```

**After Step 26:**
```
ok rake test: 782 runs, 0 failures
```

The `design_canon_test.rb` first assertion now passes against the new alias regex `/--accent:\s*var\(--green-glow\)/`. Other 4 design-canon tests unchanged and still passing. Same total run count, same zero failures — no regressions across the redesign / responsive-grids / pc-box / map / dashboard / wipe-flow / confirm-modal integration tests.

---

## Rubocop output

```
$ bundle exec rubocop
ok ✓ rubocop (203 files)
```

Clean.

---

## Brakeman delta

```
$ bundle exec brakeman --quiet --no-pager
File Access: 2

== Warnings ==
Confidence: Weak — Check: SendFile — emulator_controller.rb:79
Confidence: Weak — Check: FileAccess — gym_schedule_discord_update_job.rb:14
```

Both warnings are pre-existing on Step-26-untouched files (an emulator ROM controller and a Discord update job). **Zero delta on Step-26-touched files** — Step 26 only edited CSS, ERB inline-style attributes, JS string literals, Markdown prose, and an integration test assertion.

---

## Notes & exceptions confirmed

- `--amber: #d4b14a` token in `:root` **kept defined** (positional palette token, no live references). Per brief's explicit "do not delete" instruction.
- `.conflict-warning` block (lines 2110-2118) **keeps** `var(--amber)` border + amber-tinted bg. Per brief's exception + canon § 9.
- `--success: var(--green-glow)` line **kept**. Both `--accent` and `--success` now resolve to the same hex; semantic distinction documented in § 1's new Step 26 note + § 5 pill modifiers.
- Coin-flip modal `#c0392b` red border in `gym_drafts/show.html.erb:179, 183` **untouched** — out of scope per audit doc.
- `#4a3a1c` deep-amber bg on `.conflict-warning` **untouched** — out of canon per § 9.
- One trap successfully avoided: `gym_draft_controller.js:263` had `"0 0 0 2px var(--amber)"` (amber embedded inside a longer string), so the bare-literal `replace_all` did not catch it on the first pass. Caught by the post-edit `grep -rn "var(--amber)" app/views/ app/javascript/` audit and fixed before this review.

---

## Open questions

None. Brief was unambiguous; all acceptance gates green.

## Visual smoke (described, not rendered)

Across the dashboard runs/gyms tabs, save-slot strip, PC box review tray, map "NOW" caption + next-pulse, HoF COMPLETE pill, run-pill, gym-draft coin-flip text + ready-status + turn-indicator chip — every previously-amber surface should now render in green-glow `#5fd45f`. The four documented exceptions remain unchanged: `.conflict-warning` (amber bg+border), `--amber` token still defined in `:root`, coin-flip modal red `#c0392b` border, `--success` markers (already green-glow).

Ready for Review: YES
