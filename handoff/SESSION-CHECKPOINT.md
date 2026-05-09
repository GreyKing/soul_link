# Session Checkpoint
*Read this before reading anything else. If it covers current state, skip BUILD-LOG.*
*Session-scoped — archived to `handoff/archive/` at session end.*

---

## Where We Stopped

Step 29 (Replace red-dot favicon with a canon-palette pokeball) shipped on the worktree branch `claude/funny-payne-4df13d` at `d18b966`, FF-merged to `origin/main`, and pushed. Awaiting next brief from the Project Owner.

Step 29 follows Step 28 (Dashboard rebuild against `designs/04-pixeldex.html`). Step 28 reshaped the dashboard chrome; Step 29 fixes a small visual gap that pre-dates this whole UI sweep — `public/icon.svg` was still the Rails generator's flat red dot, so every browser tab read as a generic Rails app. Now the tab carries a chunky GB-toned pokeball.

---

## What Was Built

**Step 29 — Pokeball favicon at canon palette.** Three files. No tests added (none existed for favicons; brief said don't add).

- **`public/icon.svg`** — rewritten from `<circle r="256" fill="red"/>` to a 16×16-viewBox pokeball. Hex literals (`#c75a5a` top, `#c0d0a0` bottom, `#1a2e1a` ring/equator/button-outer, `#c0d0a0` button-inner) — SVG can't resolve `var(--token)` in favicon contexts, so canon hex literals are required. Structure: `<clipPath>` ball outline; rect halves (crimson y=0–8, parchment y=8–16); 2px ink equator band (y=7–9); 1px ink stroke ring (r=7.5); button as r=2.5 ink + r=1.25 white circles.
- **`public/icon.png`** — regenerated at 512×512 from the new SVG via `magick -background none -density 1024 public/icon.svg -resize 512x512 public/icon.png`. Size went 4 KB → 86 KB (3 colors + anti-aliasing). PWA manifest + Safari fallback now match the SVG.
- **`app/views/pwa/manifest.json.erb`** — `theme_color` `"red"` → `"#1a2e1a"` (`--d1`); `background_color` `"red"` → `"#c0d0a0"` (`--white`). PWA splash now matches GB UI chrome over canvas-bg instead of the Rails-default red.

**Layouts not touched.** `app/views/layouts/application.html.erb:14-16` and `app/views/layouts/pixeldex.html.erb:14-16` already linked `/icon.svg` and `/icon.png` correctly — confirmed by Architect grep, left alone per D4.

**Counts:** **783** tests, 2644 assertions, 0 failures, 0 errors, 0 skips (test count unchanged from Step 28). Rubocop clean (203 files). Brakeman: not re-run (manifest edit was two literal-string swaps, no Ruby/ERB logic touched — Bob's call, Architect concurred).

**Review:** Richard cleared 0 / 0 / 0 (Must Fix / Should Fix / Escalate). Specifically rendered the SVG at 16×16 and 32×32 with `magick` nearest-neighbour zoom: top crimson, dark equator band, centred ring-button, bottom parchment all distinguishable at favicon size. **Neither pre-approved D5 simplification needed** (the brief had two pre-approved fallbacks — thicken equator to 3px, or drop button's white center for solid ink dot — neither triggered).

---

## What Was Decided This Session

- **The Rails-default favicon drop is a step in its own right, not a Step 28 cleanup.** Worth a clean PR. The red dot has been there since `bin/rails new` and pre-dates everything else. Better as a discrete "icon ships now" change than buried in a CSS sweep.
- **Pokeball uses canon palette, not real pokeball palette.** Brief explicitly bars `#fff` / `#000` / new reds. So: top is `#c75a5a` (canon `--crimson`, the project's danger token), bottom is `#c0d0a0` (canon `--white`, GB-toned parchment), ink is `#1a2e1a` (canon `--d1`). Recognizably a pokeball, but reads in the project's voice — same way the rest of the UI reads in GB-toned green-dominant palette.
- **16×16 viewBox, not 512×512.** Coordinates map 1:1 to favicon pixels. A 512×512 viewBox forces sub-pixel rendering at 16×16 and reads muddy; chunky pixel-grid coordinates render cleanly at small sizes. The 86 KB PNG is fine — modern browsers prefer the SVG when both are linked, so the PNG is mostly Safari + PWA fallback.
- **PWA manifest theme/background colors swept while the icon flow was open.** `theme_color: "red"` and `background_color: "red"` were Rails defaults that nobody had migrated. Brief explicitly authorized this. New values: `--d1` for theme (matches GB UI chrome bands), `--white` for background (matches canvas page bg the PWA splash transitions into).
- **No new favicon tests.** Architect grepped for any existing favicon coverage — zero. Brief explicitly said don't add any. The verification path is "render the SVG and look at it," and `magick` at 16×16 is sufficient evidence (Reviewer ran it).

---

## Known Gaps / Future Work

*See `handoff/BUILD-LOG.md` Known Gaps — running list maintained there.*

Step 29 closed nothing — it was a presentation fix predating the gap-tracking system. No new gaps logged. KG-7, KG-19, KG-20, KG-23, KG-25, KG-26, KG-27, KG-28, KG-29, KG-30, KG-31, KG-32, KG-33, KG-34, KG-35, KG-36, KG-37, KG-38, KG-39 still open from earlier steps.

---

## Resume Prompt

Copy and paste this to resume:

---

You are Ava (Architect) on Soul Link — Three Man Team.
Read handoff/SESSION-CHECKPOINT.md, then handoff/BUILD-LOG.md.
Confirm status and next action. Then wait for direction.

---
