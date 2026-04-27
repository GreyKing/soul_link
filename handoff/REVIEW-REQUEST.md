# Review Request — Step 3

*Written by Builder. Read by Reviewer.*
*Session-scoped — archived and reset at session end.*

**Builder:** Bob
**Step:** 3 — EmulatorJS asset rake task
**Ready for Review:** YES

---

## Summary

Step 3 ships `lib/tasks/emulatorjs.rake` with two tasks under the `emulatorjs:`
namespace: `install` (download + extract latest or pinned upstream release into
`public/emulatorjs/`) and `clean` (remove that directory). Stdlib only — no new
gems. Manual HTTP redirect handling for `api.github.com → codeload.github.com`,
extraction via system `tar` through `Open3.capture3`, idempotent by full
destruction of the destination before extract. The tarball wrapper directory
(`EmulatorJS-EmulatorJS-<sha>/`) is stripped — files land at
`public/emulatorjs/data/loader.js`, not nested under the wrapper.

Per project convention (matching `lib/tasks/pokemon_data.rake`) there is no
test file. Verification is by running the task; results below.

---

## Files Created

| File | Purpose |
|------|---------|
| `lib/tasks/emulatorjs.rake` (~140 lines) | `EmulatorJSInstaller` helper module + `emulatorjs:install` / `emulatorjs:clean` tasks. |

## Files Modified

| File | Change |
|------|--------|
| `.gitignore` | Added `/public/emulatorjs/` (with a one-line header comment) below the existing `/public/assets` rule. |
| `handoff/ARCHITECT-BRIEF.md` | Appended a 5-line Builder Plan to the bottom (per directive). |

---

## Version Installed

**`tag_name: v4.2.3`** (latest, resolved at run time).

Tarball URL: `https://api.github.com/repos/EmulatorJS/EmulatorJS/tarball/v4.2.3`
Wrapper directory inside the tarball: `EmulatorJS-EmulatorJS-e150dc0/`
Tarball size: 561,414 bytes.

---

## Actual Disk Layout

`find public/emulatorjs/ -maxdepth 2 | sort` after a fresh install:

```
public/emulatorjs/
public/emulatorjs/.gitattributes
public/emulatorjs/.github
public/emulatorjs/.github/FUNDING.yml
public/emulatorjs/.github/ISSUE_TEMPLATE
public/emulatorjs/.github/workflows
public/emulatorjs/.gitignore
public/emulatorjs/.npmignore
public/emulatorjs/CHANGES.md
public/emulatorjs/CODE_OF_CONDUCT.md
public/emulatorjs/CONTRIBUTING.md
public/emulatorjs/LICENSE
public/emulatorjs/README.md
public/emulatorjs/build.js
public/emulatorjs/data
public/emulatorjs/data/compression
public/emulatorjs/data/cores
public/emulatorjs/data/emulator.css
public/emulatorjs/data/loader.js
public/emulatorjs/data/localization
public/emulatorjs/data/src
public/emulatorjs/data/version.json
public/emulatorjs/docs
public/emulatorjs/docs/Logo-light.png
public/emulatorjs/docs/Logo.png
public/emulatorjs/docs/Logo.svg
public/emulatorjs/docs/contributors.json
public/emulatorjs/docs/contributors.md
public/emulatorjs/docs/favicon.ico
public/emulatorjs/index.html
public/emulatorjs/minify
public/emulatorjs/minify/README.md
public/emulatorjs/minify/minify.js
public/emulatorjs/package.json
public/emulatorjs/update.js
```

**Step-5-relevant entrypoints confirmed:**
- `public/emulatorjs/data/loader.js` ✓
- `public/emulatorjs/data/emulator.css` ✓
- `public/emulatorjs/data/cores/` ✓
- `public/emulatorjs/data/version.json` ✓

The wrapper directory is **not** present at the top level — files were moved
out of `EmulatorJS-EmulatorJS-e150dc0/` correctly.

---

## Verification Run

### 1. `rake emulatorjs:install` (cold)

```
Fetching latest EmulatorJS release...
  Resolved version: v4.2.3
  Tarball URL: https://api.github.com/repos/EmulatorJS/EmulatorJS/tarball/v4.2.3
Downloading tarball...
  Downloaded 561414 bytes to /var/folders/.../emulatorjs.tar.gz
Extracting...
  Wrapper directory: EmulatorJS-EmulatorJS-e150dc0
Replacing /Users/gferm/personal/projects/soul_link/public/emulatorjs...

Installed EmulatorJS v4.2.3 to /Users/gferm/personal/projects/soul_link/public/emulatorjs
Top-level entries (16):
  .gitattributes
  .github/
  .gitignore
  .npmignore
  CHANGES.md
  CODE_OF_CONDUCT.md
  CONTRIBUTING.md
  LICENSE
  README.md
  build.js
  data/
  docs/
  index.html
  minify/
  package.json
  update.js
```

### 2. `git status` after install

```
* main...origin/main [ahead 4]
~ Modified: 2 files
   .gitignore
   handoff/ARCHITECT-BRIEF.md
? Untracked: 1 files
   lib/tasks/emulatorjs.rake
```

No entries inside `public/emulatorjs/` appear — fully gitignored. ✓

### 3. `rake emulatorjs:clean` (with directory present)

```
Removed public/emulatorjs/
```

`ls public/emulatorjs/` → `No such file or directory` ✓

### 4. `rake emulatorjs:clean` (already absent — defensive re-run)

```
public/emulatorjs/ already absent
```

### 5. `rake emulatorjs:install` (re-run after clean — idempotency)

Same successful output as step 1. Same 16 top-level entries. ✓

### 6. Full Rails test suite

```
mise exec -- ruby -S bundle exec rails test
131 runs, 408 assertions, 0 failures, 0 errors, 0 skips
```

No regressions. (Step 2 baseline of 131 preserved — this step adds no tests.)

---

## Definition of Done

- [x] `lib/tasks/emulatorjs.rake` exists with `install` and `clean` under `emulatorjs:` namespace
- [x] `.gitignore` includes `/public/emulatorjs/`
- [x] `rake emulatorjs:install` runs successfully against the live GitHub API
- [x] `public/emulatorjs/` populated with upstream contents — no wrapper dir, files at expected paths
- [x] `git status` shows `public/emulatorjs/` is fully ignored
- [x] `rake emulatorjs:clean` removes the directory
- [x] Re-install after clean succeeds (idempotency confirmed)
- [x] Full test suite still passes (no regressions)
- [x] REVIEW-REQUEST.md includes actual `public/emulatorjs/` directory listing + version installed

---

## Implementation Notes

**HTTP redirect handling.** `EmulatorJSInstaller.http_get_body` (used for the
JSON release lookup) and `download_to_file` (streams the tarball to disk) each
implement their own recursive redirect loop with a `MAX_REDIRECTS = 5` cap and a
clear "Too many redirects" error if exceeded. They share `User-Agent`
(`soul_link-emulatorjs-installer`) — GitHub requires one or returns 403. JSON
calls also send `Accept: application/vnd.github+json`.

**Streaming download.** The tarball is read with `response.read_body { |chunk|
io.write(chunk) }` rather than buffered into memory, so the 500+ KB payload
(and any future growth) doesn't sit in RAM. Open block form of `Net::HTTP.start`
ensures the socket is closed on exception.

**Wrapper directory detection.** `locate_wrapper_dir` requires *exactly one*
top-level entry in the extraction sandbox and that it be a directory. If
upstream ever changes the tarball layout (e.g., adds a sibling file), the task
raises with the actual entries listed — per the brief's "if the upstream
release structure may change" flag.

**Idempotent destination.** `FileUtils.rm_rf(dest)` runs before `mkdir_p +
move_contents` — no diff/merge logic, full replacement each install. This also
covers the rare partial-failure recovery: a half-extracted directory from a
previous failed run gets blown away on the next attempt.

**Loud failures.** Every error path names the URL or path that broke:
- Non-200 from GitHub: `"HTTP <code> fetching <url>: <body[0..200]>"`.
- Redirect with no Location: `"Redirect with no Location header from <url>"`.
- `tar` non-zero exit: includes exit code, stderr, and stdout.
- Unexpected wrapper layout: `"Expected exactly one top-level entry in extracted tarball, got N: [...]"`.

**Sandbox cleanup.** `Dir.mktmpdir(...) do |tmpdir| ... end` block form ensures
the temp directory (containing the tarball + extraction) is removed on success
*and* on exception.

**No `:environment` dep.** Both tasks are pure Ruby — no DB, no models, no
app-eager-load needed. Skipped the `task install: :environment` form on
purpose; matches the spec's "this task touches no DB" flag and shaves a few
seconds off cold runs.

---

## Open Questions / Flags

### 1. `.github/`, `docs/`, `LICENSE`, `package.json`, `build.js` etc. land in `public/emulatorjs/`

The upstream tarball is the entire repo, not a release-shaped artifact. So
`public/emulatorjs/` ends up with the full source tree: README, license,
GitHub workflow YAML, the build script, etc. — alongside the
`data/` subdirectory we actually need.

This matches the brief ("locate that single inner directory and move its
contents") but is worth flagging: ~15 of the 16 top-level entries are
documentation / repo-meta / build tooling that we won't serve. Step 5 will
just `<script src="/emulatorjs/data/loader.js">`, ignoring the rest.

**Possible follow-up (NOT done — outside Step 3 scope):** if you'd rather only
ship `data/` to disk, the rake could move only `wrapper/data` into
`public/emulatorjs/data` and skip the rest. The brief explicitly said "move
its contents (or its `data/` subdirectory and other files we need) up" —
i.e., either-or, my call. I went with **all contents** because (a) it's the
simpler, closer-to-upstream layout, (b) the README is occasionally useful for
quick reference, and (c) `docs/Logo.svg` may be the cleanest source for a
favicon if Step 5 wants one. None of it is served unless explicitly linked.

Happy to switch to data-only on a one-line change if you prefer a leaner
public surface area.

### 2. `nil` → `""` defensive checks on `tag_name` / `tarball_url`

I added `raise "Release JSON missing tag_name"` and `tarball_url` guards
before extracting them from the parsed release JSON. GitHub has never omitted
these in practice, but if someone ever runs `VERSION=v999.0.0` against a
non-existent tag we'd otherwise get a confusing `nil` somewhere downstream.
Keeping it.

### 3. No automated test

Per the brief's project-convention flag (matching `pokemon_data.rake` which
has no tests), no test file. The task makes a real network call — mocking
`Net::HTTP` redirects + GitHub API + system `tar` would be more brittle than
just running the task.

---

## What I Did NOT Touch

- No controllers, routes, views — Step 5 territory.
- No new gems (stdlib `Net::HTTP`, `JSON`, `FileUtils`, `Tmpdir`, `Open3`, `URI` only).
- No DB migrations.
- No Step 5 wiring — that's a separate step.
- No commits — Architect commits.

---

Ready for Review: YES
