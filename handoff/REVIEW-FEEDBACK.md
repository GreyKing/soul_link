# Review Feedback — Step 3

Date: 2026-04-26
Ready for Builder: YES

---

## Must Fix

None.

---

## Should Fix

- `lib/tasks/emulatorjs.rake:67` — The non-success branch in `download_to_file`
  raises `"HTTP #{response.code} downloading #{url}"` without including the
  response body, while the equivalent branch in `http_get_body` (line 43)
  includes `response.body.to_s[0, 200]`. Minor inconsistency; if GitHub ever
  returns a meaningful error payload during the tarball fetch (rate-limit
  JSON, etc.), it'd be useful to surface it the same way. One-liner: append
  `: #{response.body.to_s[0, 200]}` to match. Not blocking.

- `lib/tasks/emulatorjs.rake:144-152` — `task :clean` uses `File.exist?(dest)`
  where `dest` is a `Pathname`. Works correctly, but `dest.exist?` would be
  marginally more idiomatic. Not blocking.

---

## Escalate to Architect

None. The full-tarball-vs-`data/`-only question Bob raised in Open Question
\#1 was already ruled by Architect (ship everything, GPL LICENSE must
accompany redistributed code). Not re-litigated.

---

## Cleared

Reviewed `lib/tasks/emulatorjs.rake`, `.gitignore`, `handoff/REVIEW-REQUEST.md`,
and cross-checked against `lib/tasks/pokemon_data.rake` for convention.

Verified each scrutiny point:

**1. HTTP redirect handling.** Both `http_get_body` (rake:25-46) and
`download_to_file` (rake:48-71) implement bounded recursive redirect loops.
`MAX_REDIRECTS = 5`. Counter decrements on every hop; raises
`"Too many redirects ..."` when `redirects_left.negative?`. `Location`
header is read; raises clearly when missing or empty. No infinite-loop
risk. `URI.join(url, location).to_s` correctly handles relative redirect
targets.

**2. Wrapper-directory strip.** `locate_wrapper_dir` (rake:80-88) requires
exactly one non-dotfile top-level entry, asserts it's a directory, and
returns its full path. `move_contents` (rake:90-95) iterates
`Dir.children(wrapper)` and `FileUtils.mv`s each child into `dest` — so the
wrapper directory itself is discarded and its contents land at
`public/emulatorjs/data/loader.js` (matching DoD), not nested under
`public/emulatorjs/EmulatorJS-EmulatorJS-<sha>/`. Bob's directory listing in
REVIEW-REQUEST corroborates this — 16 top-level entries, no
`EmulatorJS-EmulatorJS-e150dc0/`.

**3. Stdlib-only constraint.** `require`s are `net/http`, `json`,
`fileutils`, `tmpdir`, `open3`, `uri` — all stdlib. No new gems. Bob's
`git status` shows only `.gitignore`, `handoff/ARCHITECT-BRIEF.md`, and
`lib/tasks/emulatorjs.rake` modified — Gemfile and Gemfile.lock are not
in the changed-files list.

**4. Errors are loud.** Every failure path names the URL or path:

- Non-200 from GitHub API: `"HTTP <code> fetching <url>: <body[0..200]>"`.
- Non-200 during download: `"HTTP <code> downloading <url>"` (see Should
  Fix — body not included; not blocking).
- Redirect with no Location header: names the URL.
- `tar` non-zero exit: includes path, exit code, stderr, and stdout.
- Unexpected wrapper layout: lists actual entries (`#{entries.inspect}`).
- Missing `tag_name` / `tarball_url`: explicit raise before downstream
  use.
- JSON parse failure on release lookup: includes URL and underlying error.

No silent rescues. The two `rescue` blocks (one for `JSON::ParserError` at
rake:20, none in the rake bodies themselves) re-raise with context.

**5. Idempotency.** `FileUtils.rm_rf(dest)` then `FileUtils.mkdir_p(dest)`
then `move_contents(wrapper, dest)` (rake:128-130). Full destruction-and-
replace, no diff/merge logic. Also covers partial-failure recovery: a
half-extracted directory from a previous failed run gets blown away on the
next attempt. Bob's verification run \#5 confirms re-install after clean
produces the same 16 entries.

**6. `Dir.mktmpdir` block form.** `Dir.mktmpdir("emulatorjs-install-") do
|tmpdir| ... end` (rake:113). Tarball + extraction sandbox auto-cleaned on
success and on exception.

**7. Project convention match.** Mirrors `lib/tasks/pokemon_data.rake`
shape: top-level `require`s, helper module, `namespace :name do ... end`
with `desc` + `task` blocks. The helper module uses `module_function`
where `pokemon_data.rake` uses explicit `self.method`s — minor stylistic
difference, both valid Ruby idioms; neither breaks the convention. Bob
deliberately omitted `task install: :environment` because the task touches
no DB/models — explicitly called out in the brief and the implementation
note. Reasonable.

**8. Verification claims.**

- Full test suite passing 131/131 is plausible — the rake task touches no
  app code, no autoload, no DB. Step 2 baseline preserved (no new tests
  added, none broken).
- `.gitignore` line 46 is `/public/emulatorjs/` with the leading slash
  (root-anchored). Correct semantics — won't accidentally match a nested
  `public/emulatorjs/` somewhere else in the tree. Placed appropriately
  beneath `/public/assets` (line 43) with a one-line header comment
  (line 45) explaining provenance.
- Bob's `git status` output confirms no entries from inside
  `public/emulatorjs/` leak as untracked.

**9. Definition of Done.** All 9 boxes verifiable from REVIEW-REQUEST and
the actual files:

- [x] Rake file exists with `install` and `clean` under `emulatorjs:`
      namespace (rake:98-153).
- [x] `.gitignore` includes `/public/emulatorjs/` (line 46).
- [x] `rake emulatorjs:install` runs successfully against live GitHub API
      (resolved to `v4.2.3`).
- [x] Populated correctly — `data/loader.js`, `data/emulator.css`,
      `data/cores/`, `data/version.json` all confirmed present.
- [x] Fully gitignored — `git status` shows no inside entries.
- [x] `rake emulatorjs:clean` removes the directory (verified twice — once
      with directory present, once already absent).
- [x] Idempotency — re-install after clean produces the same 16 entries.
- [x] Full suite passes (131/131).
- [x] REVIEW-REQUEST contains the directory listing + `tag_name: v4.2.3`.

**10. No scope creep.** Modified set is exactly `lib/tasks/emulatorjs.rake`
(new), `.gitignore` (one block added), and `handoff/ARCHITECT-BRIEF.md`
(Builder Plan section appended per directive). No app code, no controllers,
no routes, no views, no migrations, no Step 5 wiring leaked in.

**Architect ruling honored.** Full-tarball install (16 top-level entries
including LICENSE, .github/, docs/, etc.) accepted per the standing GPL-
attribution ruling. Bob's Open Question \#1 raises the question politely;
the decision stands and is not flagged as an issue.

Step 3 is clear.

VERDICT: PASS_WITH_OBSERVATIONS
