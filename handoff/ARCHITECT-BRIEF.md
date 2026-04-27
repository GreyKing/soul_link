# Architect Brief
*Written by Architect. Read by Builder and Reviewer.*
*Overwrite this file each step — it is not a log, it is the current active brief.*

---

## Step 3 — EmulatorJS Asset Rake Task

Context: Step 5 will load EmulatorJS via a direct `<script>` tag served from `public/emulatorjs/`. This step provides the rake task that populates that directory from the upstream GitHub release. Assets are gitignored — every fresh checkout (laptop, VPS, CI when needed) re-runs the install task.

Source: <https://github.com/EmulatorJS/EmulatorJS>

### Files to Create

- `lib/tasks/emulatorjs.rake`

### Files to Modify

- `.gitignore` — add `/public/emulatorjs/`

### Rake Task Spec

Two tasks under the `emulatorjs:` namespace.

**`rake emulatorjs:install`**

- Default: download the **latest** release from the EmulatorJS GitHub repo.
- `VERSION=v4.x` env var to pin a specific tag (use `https://api.github.com/repos/EmulatorJS/EmulatorJS/releases/tags/<tag>` instead of `/latest`).
- Idempotent: remove `public/emulatorjs/` before extraction.
- Print version installed (the `tag_name` field) and a final tree summary (top-level files/dirs in `public/emulatorjs/`).

**`rake emulatorjs:clean`**
- `FileUtils.rm_rf(Rails.root.join("public", "emulatorjs"))`.
- Print `"Removed public/emulatorjs/"` if it existed, or `"public/emulatorjs/ already absent"` if not.

### Implementation Constraints

- **Stdlib only.** `Net::HTTP`, `JSON`, `FileUtils`, `Dir.mktmpdir`, plus the system `tar` command via `Open3.capture3` for extraction. Do NOT add `minitar`, `rubyzip`, or any other gem.
- **Follow HTTP redirects** — GitHub's `tarball_url` redirects to `codeload.github.com`. `Net::HTTP` does not follow redirects automatically; implement a small redirect loop (cap at 5 hops, raise after).
- **Tarball extraction layout:** GitHub release tarballs extract to a top-level directory like `EmulatorJS-EmulatorJS-<sha>/`. After extraction, locate that single inner directory and move its contents (or its `data/` subdirectory and other files we need) up to `public/emulatorjs/`. Do not copy the tarball wrapper directory itself into `public/emulatorjs/`.
- **Use `Dir.mktmpdir`** for the download + extraction sandbox. Clean up on exit (block form).
- **Errors should be loud.** If GitHub API returns non-200, if the tarball download fails, if `tar` fails, raise with a clear message that names the URL or path that broke. Don't swallow errors silently.
- **No GitHub auth.** Public API works unauthenticated for 60 req/hr — fine for a one-time install task.

### Verification (manual — no automated tests)

Bob runs locally and reports actual results in REVIEW-REQUEST.md:

1. `mise exec -- ruby -S bundle exec rake emulatorjs:install` — succeeds, prints version, lands files in `public/emulatorjs/`.
2. List the top-level entries of `public/emulatorjs/` (e.g., `ls public/emulatorjs/` or `find public/emulatorjs/ -maxdepth 2`). Confirm `data/loader.js` (or whatever the upstream entrypoint is) exists. Tell me the actual structure — do not assume.
3. `git status` shows `public/emulatorjs/` is fully gitignored — no untracked entries inside it.
4. `mise exec -- ruby -S bundle exec rake emulatorjs:clean` — removes the directory.
5. Re-run install — succeeds again (idempotency).
6. `mise exec -- ruby -S bundle exec rails test` — full suite still passes (no regressions).

**Project convention:** `lib/tasks/pokemon_data.rake` has no tests. Match — no test file for this rake. Verification is by running the task.

### Build Order

1. Add `/public/emulatorjs/` to `.gitignore`.
2. Create `lib/tasks/emulatorjs.rake` with both tasks.
3. Run `rake emulatorjs:install` — capture output + the actual top-level directory structure.
4. Run `git status` — confirm `public/emulatorjs/` is gitignored.
5. Run `rake emulatorjs:clean` — confirm directory removed.
6. Re-run install — confirm idempotent.
7. Run full test suite — confirm no regressions.
8. Write REVIEW-REQUEST.md including: actual `public/emulatorjs/` directory listing, version installed, idempotency confirmation, full-suite results.

### Flags

- Flag: **Stdlib only** — no new gems. Use `Net::HTTP` + `Open3` + system `tar`.
- Flag: **Handle HTTP redirects manually** — GitHub will 302 from `api.github.com` to `codeload.github.com`. Without redirect handling, you'll download an empty body or get a redirect HTML.
- Flag: **Tarball wrapper directory** — extract, then move the inner `EmulatorJS-EmulatorJS-<sha>/` contents up. Don't blindly extract the tarball into `public/emulatorjs/` — you'll get `public/emulatorjs/EmulatorJS-EmulatorJS-<sha>/data/loader.js` which won't match Step 5's expectation of `public/emulatorjs/data/loader.js`.
- Flag: **Idempotency by destruction** — `FileUtils.rm_rf` the destination first, then extract. Simpler than diff-based updates.
- Flag: **No commits.** Architect commits.
- Flag: **Don't run `rake db:*`** — this task touches no DB.
- Flag: **The upstream release structure may change** — if the tarball doesn't contain a `data/` directory at the expected location, report what IS there and stop. Don't invent a workaround.
- Flag: All Rails commands prefixed `mise exec -- ruby -S bundle exec`.

### Definition of Done

- [ ] `lib/tasks/emulatorjs.rake` exists with `install` and `clean` tasks under `emulatorjs:` namespace
- [ ] `.gitignore` includes `/public/emulatorjs/`
- [ ] `rake emulatorjs:install` runs successfully against the live GitHub API
- [ ] `public/emulatorjs/` populated with the upstream release contents (no wrapper dir, files at expected paths)
- [ ] `git status` shows `public/emulatorjs/` is fully ignored
- [ ] `rake emulatorjs:clean` removes the directory
- [ ] Re-install after clean succeeds (idempotency confirmed)
- [ ] Full test suite still passes (no regressions)
- [ ] REVIEW-REQUEST.md includes actual `public/emulatorjs/` directory listing + version installed

---

## Builder Plan
*Builder adds their plan here before building. Architect reviews and approves.*

1. Append `/public/emulatorjs/` to `.gitignore` (one line, end of file).
2. Create `lib/tasks/emulatorjs.rake` matching `pokemon_data.rake` style: top-level `require`s, helper module `EmulatorJSInstaller`, `namespace :emulatorjs do ... end` with `install` and `clean` tasks (no `:environment` dep — pure stdlib, no DB).
3. `install` flow: hit GitHub API for latest (or tagged) release, parse `tag_name` + `tarball_url`, manual redirect loop (max 5 hops) downloading to a `Dir.mktmpdir` file, `tar -xzf` via `Open3.capture3`, locate the single `EmulatorJS-EmulatorJS-<sha>/` wrapper dir, `rm_rf` destination, `mv` wrapper contents into `public/emulatorjs/`, print `tag_name` + `Dir.children` of destination.
4. `clean` flow: stat destination, `rm_rf`, print conditional message.
5. Verify: install -> ls/find output, git status, clean, re-install, full test suite.
