# Architect Brief
*Written by Architect. Read by Builder and Reviewer.*
*Overwrite this file each step — it is not a log, it is the current active brief.*

---

## Step 29 — Replace red-dot favicon with a pokeball icon

The browser tab icon is currently a red dot — `public/icon.svg` is literally `<circle cx="256" cy="256" r="256" fill="red"/>`, the Rails default. Replace with a chunky pokeball that reads at 16×16 and uses the canon palette.

### Palette (canon, hex literals — the SVG can't resolve `var(--token)` in favicon contexts)

| Role          | Token       | Hex       |
|---------------|-------------|-----------|
| Top half      | `--crimson` | `#c75a5a` |
| Bottom half   | `--white`   | `#c0d0a0` |
| Equator + ring + button outer | `--d1`      | `#1a2e1a` |
| Button inner  | `--white`   | `#c0d0a0` |

The project's GB-toned `--white` reads as a slightly olive parchment, not pure white. That's the canonical pairing — keep it. **Do not introduce `#fff`, `#000`, or new reds.**

### D1 — Rewrite `public/icon.svg`

Use a **16×16 viewBox** so coordinates map 1:1 to favicon pixels (chunkier sub-pixel rendering than 512×512). Canonical structure:

```svg
<svg width="16" height="16" viewBox="0 0 16 16" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <clipPath id="ball">
      <circle cx="8" cy="8" r="8"/>
    </clipPath>
  </defs>
  <g clip-path="url(#ball)">
    <rect x="0" y="0" width="16" height="8" fill="#c75a5a"/>
    <rect x="0" y="8" width="16" height="8" fill="#c0d0a0"/>
    <rect x="0" y="7" width="16" height="2" fill="#1a2e1a"/>
  </g>
  <circle cx="8" cy="8" r="7.5" fill="none" stroke="#1a2e1a" stroke-width="1"/>
  <circle cx="8" cy="8" r="2.5" fill="#1a2e1a"/>
  <circle cx="8" cy="8" r="1.25" fill="#c0d0a0"/>
</svg>
```

- Top crimson half + bottom parchment half clipped to the ball outline.
- 2px equator band (y=7–9) — chunky enough to survive 16×16 rendering.
- 1px ink ring (r=7.5, stroke=1) — outer edge.
- Button: r=2.5 ink ring with r=1.25 white center (5px-wide button at 16×16).

You may tune the structure if you spot a clearer way to express the same design, but: keep viewBox 0 0 16 16, keep the same three colors, keep the equator at y=7–9, keep button radii ≥ 2.5/1.25 so it doesn't disappear at 16px. Flag if you want to deviate.

### D2 — Regenerate `public/icon.png` from the new SVG

The PNG is the fallback for Safari and the PWA manifest, so it has to match. `magick` is available at `/opt/homebrew/bin/magick`. From the worktree root:

```
magick -background none -density 1024 public/icon.svg -resize 512x512 public/icon.png
```

Verify the output: `file public/icon.png` should report `PNG image data, 512 x 512`. If `magick` fails, fall back to `convert` (also at `/opt/homebrew/bin/convert`) with the same flags. If both fail, escalate — don't ship a 4 KB red-dot PNG with a pokeball SVG.

### D3 — Fix the PWA manifest's stale red theme

`app/views/pwa/manifest.json.erb` currently has `"theme_color": "red"` and `"background_color": "red"` — Rails default leftovers, never updated to canon. While we're touching the icon flow, fix these:

- `theme_color`: `"#1a2e1a"` (`--d1`, the dark frame ink — matches the GB UI chrome)
- `background_color`: `"#c0d0a0"` (`--white`, matches the canvas page bg used as PWA splash)

Don't change anything else in this file — the icon entries already point at `/icon.png` which we're regenerating.

### D4 — No layout-file changes

`app/views/layouts/application.html.erb:14-16` and `app/views/layouts/pixeldex.html.erb:14-16` already reference `/icon.svg` and `/icon.png`. They're correct as-is. Do not touch them.

### D5 — Verification

1. **Rubocop:** `bundle exec rubocop` — clean.
2. **Tests:** `bin/rails test` — there are zero existing favicon tests (verified by Architect via grep). Test count must remain unchanged at 783, 0 failures, 0 errors.
3. **Browser screenshot at favicon size** (Reviewer's responsibility, not Bob's, but Bob may also do a sanity check):
   - Boot `bin/dev`, navigate to `http://localhost:3000`, capture the browser tab. The pokeball must be readable as a pokeball — top red, bottom off-white, dark equator with a centered button. If at 16×16 the equator and button mush together into an indistinct blob, **simplify** (e.g., thicken the equator to 3px, or drop the button's white center and leave it as a solid ink dot). Flag any simplification before shipping.

### Files in scope

| File | Change |
|------|--------|
| `public/icon.svg` | Rewrite (red-dot → pokeball) |
| `public/icon.png` | Regenerate from new SVG (512×512) |
| `app/views/pwa/manifest.json.erb` | `theme_color` `"red"` → `"#1a2e1a"`; `background_color` `"red"` → `"#c0d0a0"` |

Three files. Nothing else.

### Flags

- **Flag if:** the 2px equator + 5px button render unreadable at 16×16 in the browser tab. Acceptable simplification: 3px equator, or solid ink button (drop the white center). Don't pile on detail; chunkier reads better.
- **Flag if:** `magick` and `convert` both fail. Don't hand-roll a PNG.
- **Do not:** change layout files, change manifest icon entries, touch any other file, add tests.
