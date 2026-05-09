# Review Feedback — Step 29
Date: 2026-05-09
Ready for Builder: YES

## Must Fix
None.

## Should Fix
None.

## Escalate to Architect
None.

## Cleared

Step 29 — red-dot favicon → pokeball — is clear.

### D1 — `public/icon.svg` (L1–15)

Matches the brief's canonical SVG verbatim. 16×16 viewBox preserved. Six
fill/stroke literals all resolve to canon hex:

- `#c75a5a` (`--crimson`) — top half rect (L8)
- `#c0d0a0` (`--white`) — bottom half rect (L9), button inner (L14)
- `#1a2e1a` (`--d1`) — equator band (L10), outer ring stroke (L12),
  button outer (L13)

`grep` for forbidden literals (`#fff`, `#000`, `#FFF`, `red`, `#FF0000`)
returns zero matches. Geometry per brief: equator at y=7–9 (2px), outer
ring r=7.5 stroke=1, button r=2.5 / r=1.25.

### D2 — `public/icon.png`

`file public/icon.png` reports `PNG image data, 512 x 512, 16-bit/color
RGBA, non-interlaced`. Size 86.3 KB (was 4.1 KB stale red-dot — the new
file has three colours plus anti-aliased edges, so the size jump is
expected). Visual inspection of the rendered PNG at native 512×512
confirms it is the new pokeball, not a stale leftover: top crimson half,
bottom parchment half, dark equator with centred button containing a
parchment dot — matches the new SVG one-for-one.

### D3 — `app/views/pwa/manifest.json.erb` (L20–21)

- L20 `theme_color` is `"#1a2e1a"` (canon `--d1`) — matches brief exactly.
- L21 `background_color` is `"#c0d0a0"` (canon `--white`) — matches brief
  exactly.
- Nothing else in the file changed; icon entries (L4–14) still point at
  `/icon.png`.

### D4 — Layout files untouched

`git status` shows three working-tree changes outside handoff docs:
`public/icon.svg`, `public/icon.png`, `app/views/pwa/manifest.json.erb`
— exactly the three the brief enumerates. `app/views/layouts/
application.html.erb` and `app/views/layouts/pixeldex.html.erb` both
still reference `/icon.svg` + `/icon.png` at L14–16 and were not
modified.

### D5 — Readability at favicon size (Reviewer's owned check)

I rendered the SVG at 16×16 and 32×32 directly from `public/icon.svg`
via `magick -background none public/icon.svg -resize 16x16 …` (and
32×32), then nearest-neighbour zoomed each to 512×512 for inspection.

- **At 32×32:** clean and unambiguous — top crimson, dark equator,
  centred ink button with a clearly visible parchment-tinted core,
  bottom parchment. Reads as a pokeball at a glance.
- **At 16×16:** the four cardinal regions are all distinguishable —
  top red half, dark equator band running edge-to-edge, bottom
  parchment half, centred button. The button's parchment inner core
  is rendered as 4 mixed-green pixels (the r=1.25 sub-pixel circle
  smears under nearest-pixel coverage) but it still reads as a
  hollow ring rather than a solid blob. The equator and button do
  not mush together.

The two pre-approved D5 simplifications (3px equator OR solid ink
button without the white center) are **not needed** — neither failure
mode triggered. Shipping as-is.

### Other checks

- **Test count:** Bob reports 783 runs / 0 failures / 0 errors / 0
  skips, unchanged from Step 28 (brief required this — no favicon
  tests added).
- **Rubocop:** Bob reports 203 files / 0 offenses.
- **Brakeman:** Bob did not re-run because no Ruby/ERB-logic changes
  were made — the manifest edit is two literal-string swaps inside a
  static JSON template. I concur; the two pre-existing weak-confidence
  warnings carry over from Step 28 with zero delta. Re-running on a
  pure-asset change would be ceremony.
- **Bundler-under-mise note:** Bob's PATH-sanitization workaround for
  Ruby 3.0.6 / Bundler 2.4.11 colliding with Rails 8.1's gemset is a
  Bob-environment issue only; nothing in CI or the project shell
  changed.

Step 29 is clear.
