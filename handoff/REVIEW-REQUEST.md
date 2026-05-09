# Review Request — Step 29
*Bob → Richard. Replace red-dot favicon with a pokeball icon.*

**Branch:** `claude/funny-payne-4df13d`
**Builder:** Bob
**Status:** Ready for Review: YES

---

## Scope reminder

Step 29 is a tiny three-file change. The browser-tab icon is currently a red dot
(`public/icon.svg` was a leftover Rails default — `<circle … fill="red"/>`). The
brief asks for a chunky pokeball at the canon palette that reads at 16×16, the
matching 512×512 PNG fallback for Safari and the PWA, and the PWA manifest's stale
`"red"` theme/background swapped for canon `--d1` / `--white` hex.

No layout-file edits; no new tests. The brief explicitly forbids both.

---

## Files changed

### `public/icon.svg` — rewrite (red-dot → pokeball)
- **L1–13** (full file). New 16×16 viewBox so coordinates map 1:1 to favicon
  pixels. Structure follows the brief's canonical SVG verbatim:
  - `<clipPath id="ball">` masks two halves to a r=8 circle.
  - `<rect 0,0,16,8 fill="#c75a5a">` — top crimson half (`--crimson`).
  - `<rect 0,8,16,8 fill="#c0d0a0">` — bottom parchment half (`--white`).
  - `<rect 0,7,16,2 fill="#1a2e1a">` — 2px equator band (`--d1`).
  - Outer ring: `circle r=7.5 stroke="#1a2e1a" stroke-width="1"` — 1px ink ring.
  - Button outer: `circle r=2.5 fill="#1a2e1a"` — 5px ink dot.
  - Button inner: `circle r=1.25 fill="#c0d0a0"` — parchment center.
- Hex literals are intentional — favicon contexts can't resolve `var(--token)`.
- No `#fff`, no `#000`, no new reds (per brief).
- No structural deviations from the canonical SVG in the brief.

### `public/icon.png` — regenerate at 512×512 from the new SVG
- Built via `magick -background none -density 1024 public/icon.svg -resize 512x512 public/icon.png`
  from the worktree root, exactly as the brief specifies.
- `file public/icon.png` reports `PNG image data, 512 x 512, 16-bit/color RGBA, non-interlaced`
  (was `512 x 512, 8-bit colormap, non-interlaced`; size 4.1 KB → 86.3 KB — the new
  PNG has more colour data because the pokeball needs three colours plus
  anti-aliased edges).
- `magick` succeeded on first run; no need for the `convert` fallback.

### `app/views/pwa/manifest.json.erb` — fix stale red theme
- **L20** `"theme_color": "red"` → `"theme_color": "#1a2e1a"` (canon `--d1`,
  matches the GB UI chrome).
- **L21** `"background_color": "red"` → `"background_color": "#c0d0a0"` (canon
  `--white`, matches the canvas page bg used as PWA splash).
- Nothing else in the file touched. The icon entries (L4–14) already point at
  `/icon.png`, which we just regenerated.

### Files NOT touched (per brief D4)

- `app/views/layouts/application.html.erb:14-16` — already references `/icon.svg`
  + `/icon.png`. Correct as-is.
- `app/views/layouts/pixeldex.html.erb:14-16` — same. Correct as-is.

---

## Test status

- `bin/rails test`: **783 runs, 2644 assertions, 0 failures, 0 errors, 0 skips.**
  Test count unchanged from Step 28 (brief explicitly required this — no favicon
  tests exist, none added).
- `bundle exec rubocop`: **clean** (203 files, 0 offenses).
- `bundle exec brakeman`: not re-run for Step 29 — no Ruby / ERB-logic changes
  were made (the manifest.json.erb edit is two literal-string swaps inside a
  static JSON template; no controller / model / service code touched). Same
  pre-existing 2 weak-confidence warnings carried over from Step 28; zero delta
  on Step-29-touched files.

(Note on test-runner mechanics: bare `bundle exec` resolves to the system
Bundler 2.4.11 under Ruby 3.0.6, which can't load Rails 8.1's gem set. Used
`/Users/gferm/.local/share/mise/installs/ruby/3.4.5/bin/bundle exec …` with a
sanitized PATH to force Bundler to run under Ruby 3.4.5 against the project's
gemset. This is purely a Bob-side environment issue; nothing in the project's
shell or CI changes.)

---

## Standing rules check

- **Canon palette only:** every colour in the SVG resolves to an existing canon
  token by hex — `#c75a5a` = `--crimson`, `#c0d0a0` = `--white`, `#1a2e1a` =
  `--d1`. Manifest hex values match `--d1` / `--white`. No `#fff`, no `#000`,
  no new reds.
- **Scope lock:** three files touched, exactly the three the brief enumerates.
  Layout files, tests, controllers, models, services all untouched.
- **No speculative additions:** no PWA manifest icon-entry edits beyond the two
  colour swaps; no `apple-touch-icon` rule added; no extra favicon sizes
  generated. Brief said don't, so I didn't.
- **Hard-coded hex justification:** the brief explicitly notes favicon SVGs
  can't resolve `var(--token)` because they load outside the page's CSS scope.
  Hex literals here are canonical, not a token violation.

---

## Open questions for Richard

None. The brief was unambiguous on every directive (D1–D5). The two judgement
calls were trivial:

1. **`magick` vs `convert` fallback:** `magick` succeeded first try, so no
   fallback needed.
2. **Brakeman:** chose not to re-run (no Ruby logic touched). Flag if you'd
   prefer a fresh run before clearing.

The brief notes Bob "may also do a sanity check" of the rendered favicon at
16×16 in a browser tab but that this is Reviewer's responsibility. I confirmed
the SVG renders correctly in the Launch preview panel — the pokeball reads as
expected (top red, bottom off-white, 2px ink equator, centred 5px button with
parchment dot). I deferred booting `bin/dev` for the actual browser-tab capture
to your review pass per the brief's explicit ownership split. **Flag if you want
me to re-attempt at-tab-size now.**

If at 16×16 the equator + button mush into a blob, the brief allows two
acceptable simplifications: thicken equator to 3px, or drop the button's white
center and leave a solid ink dot. Both are flag-then-fix; happy to do whichever
you call.

Ready for Review: YES
