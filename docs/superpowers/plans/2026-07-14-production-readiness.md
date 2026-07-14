# Dense 1.0.0 Production Readiness Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Tasks marked **[USER]** require human accounts/hardware and cannot be delegated to an agent — agents may prep them but a person executes.

**Goal:** Take Dense from "code complete on origin/main" (all 8 PRs merged, 179/179 engine tests green) to a signed, notarized, purchasable 1.0.0 with working auto-updates and the launch campaign live.

**Architecture:** No new product code. This plan closes the gap between the merged codebase and production: repo hygiene, CI, supply-chain pinning, license compliance, QA-checklist consolidation, then the user-gated release chain (Apple signing → Sparkle keys → release.sh → clean-machine QA → commerce → placeholder resolution → launch).

**Tech Stack:** Swift 5.9 / SwiftUI (macOS 14+), SwiftPM (DenseCore), xcodegen, bundled universal ffmpeg/ffprobe, Sparkle 2, Lemon Squeezy licensing, Cloudflare Pages (Site/), GitHub Actions (new).

## Global Constraints

- macOS deployment target **14.0**; binary must be **universal (arm64 + x86_64)** — `release.sh` already hard-gates this.
- Originals never modified; outputs suffixed `-compressed` (product invariant — QA verifies, no code change).
- Zero-warning Release builds (standard maintained across all 9 redesign tasks).
- All launch placeholders share the greppable prefix `REPLACE-AT-LAUNCH` (plus `LICENSE-TERMS-TBD`, `REFUND-POLICY-TBD`); the ship gate is `git grep` returning **nothing** (Task 12).
- Pricing per launch plan: **$29, LAUNCH35 coupon → $19** (playbook: PH Tuesday anchor, <$500 budget).
- Truthfulness whitelist for all campaign copy: only measured numbers, "up to" hedges.

## Current State (verified 2026-07-14)

- `origin/main` @ `ab6d741`: full app — video/PDF/image/GIF compression, sidebar destinations, preview inspector, licensing gate, Sparkle wiring, 16-page site, Raycast extension, hardened `Scripts/release.sh`.
- PR #8 (single-pane redesign) merged 2026-07-14; final whole-branch review verdict "Ready to merge: With fixes" — both fixes landed (`8817c7a`).
- Outstanding placeholders on origin/main: 43× `REPLACE-AT-LAUNCH`, 4× `REPLACE-AT-LAUNCH-EDKEY`, 1× `REPLACE-AT-LAUNCH-EDSIGNATURE`, 4× `LICENSE-TERMS-TBD`, 3× `REFUND-POLICY-TBD`. `Site/demo.gif` is a placeholder recording.
- No CI of any kind (`.github/` absent).
- `docs/qa-checklist.md` still tests the **retired dock-card UI**; the current-UI checklist lives separately in `docs/superpowers/plans/2026-07-13-redesign-qa.md`.
- `Scripts/fetch-ffmpeg.sh` downloads unpinned binaries (evermeet.cx URL is "latest", no checksums).
- README says "Screenshots will be updated after the single-pane redesign" — redesign is done, screenshots aren't.
- Local repo: `main` is 5+ commits behind `origin/main`; working tree holds untracked copies of `Dense.xcodeproj/`, `DenseCore/`, `Fixtures/`, `Tools/`, `integrations/`; branches `build-v1` and `redesign-single-pane` are merged but not deleted.
- On this machine: `security find-identity -v -p codesigning` shows **no** Developer ID cert; no `dense-notary` keychain profile (per release.sh's own doc block).

## Phase map

| Phase | Tasks | Owner | Wall time |
|---|---|---|---|
| 0. Repo hygiene | 1 | agent | 10 min |
| 1. Engineering gaps | 2–5 | agent | 1 session |
| 2. Release engineering | 6–9 | **user** (+agent QA prep) | ~half day once Apple account exists |
| 3. Commerce, site, placeholders | 10–12 | **user** (+agent edits) | ~half day |
| 4. Launch & post-launch | 13–14 | user, agent-assisted | 4 weeks (playbook) |

Order: 1 → (2,3,4,5 in any order) → 6 → 7 → 8 → 9 → 10 → 11 → 12 → 13 → 14. Tasks 2–5 can run while the user does 6–7.

---

### Task 1: Sync local repo to post-merge reality

**Files:**
- No source changes. Git state only.

**Interfaces:**
- Produces: local `main` == `origin/main` (`ab6d741`+), clean `git status`, merged branches deleted. Every later task assumes this.

- [ ] **Step 1: Confirm the untracked working files match origin/main before pulling**

The untracked `Dense.xcodeproj/`, `DenseCore/`, etc. in the working tree are leftovers from branch work. A pull onto `main` will fail if any untracked file collides with an incoming tracked file that differs.

```bash
cd "/Users/jale/Documents/Obsidian Vault/Compress"
git fetch origin
git checkout main
git pull origin main
```

Expected: either a clean fast-forward, or `error: The following untracked working tree files would be overwritten by merge`. If the error appears, the colliding files are stale local copies — verify no local-only edits you care about (`diff -rq DenseCore <(git show ...)` for anything suspicious), then move them aside and re-pull:

```bash
mkdir -p /tmp/dense-stale && for d in Dense.xcodeproj DenseCore Fixtures Tools integrations; do [ -e "$d" ] && mv "$d" /tmp/dense-stale/; done
git pull origin main
```

- [ ] **Step 2: Verify clean state**

```bash
git status --short && git log --oneline -1
```

Expected: only `.DS_Store` noise (add to `.gitignore` if not present); HEAD at `ab6d741` or newer.

- [ ] **Step 3: Delete merged branches**

```bash
git branch -d build-v1 redesign-single-pane
git push origin --delete build-v1 redesign-single-pane
```

Expected: both delete without `-D` (they are fully merged; PRs #7 and #8 confirm). If `-d` refuses, STOP and investigate — do not force.

- [ ] **Step 4: Rebuild local tooling and verify the suite on main**

```bash
bash Scripts/fetch-ffmpeg.sh   # only if Tools/bin was moved aside in Step 1
cd DenseCore && swift test 2>&1 | tail -3
```

Expected: `Test Suite 'All tests' passed` — 179 tests.

---

### Task 2: CI — test + release-build gate on every PR

**Files:**
- Create: `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: `Scripts/fetch-ffmpeg.sh`, `DenseCore/Package.swift`, `project.yml`.
- Produces: a required status check `ci / test-and-build` for future PRs.

- [ ] **Step 1: Write the workflow**

```yaml
# .github/workflows/ci.yml
name: ci
on:
  pull_request:
  push:
    branches: [main]
jobs:
  test-and-build:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4
      - name: Cache ffmpeg universal binaries
        id: ffmpeg-cache
        uses: actions/cache@v4
        with:
          path: Tools/bin
          key: ffmpeg-${{ hashFiles('Scripts/fetch-ffmpeg.sh') }}
      - name: Fetch ffmpeg
        if: steps.ffmpeg-cache.outputs.cache-hit != 'true'
        run: bash Scripts/fetch-ffmpeg.sh
      - name: Engine tests
        run: swift test --package-path DenseCore
      - name: Release build (unsigned)
        run: |
          brew install xcodegen
          xcodegen generate
          xcodebuild -project Dense.xcodeproj -scheme Dense -configuration Release \
            -destination "generic/platform=macOS" \
            CODE_SIGNING_ALLOWED=NO build
```

- [ ] **Step 2: Push on a branch and verify the run**

```bash
git checkout -b ci-setup && git add .github/workflows/ci.yml
git commit -m "ci: engine tests + unsigned Release build on every PR"
git push -u origin ci-setup && gh pr create --fill
gh run watch
```

Expected: green run — 179 tests pass, `BUILD SUCCEEDED`. If the ffmpeg mirror URLs fail on the runner, that is exactly the fragility Task 3 fixes — land Task 3 first in that case.

- [ ] **Step 3: Merge and mark the check required**

```bash
gh pr merge --squash --delete-branch
gh api -X PUT repos/anhvule/Dense/branches/main/protection/required_status_checks/contexts -f "contexts[]=ci / test-and-build" 2>/dev/null || echo "set branch protection in repo Settings > Branches"
```

Expected: merged; `main` protected by the check (web UI fallback is fine).

---

### Task 3: Pin ffmpeg downloads (supply chain)

**Files:**
- Modify: `Scripts/fetch-ffmpeg.sh`

**Interfaces:**
- Consumes: current script (unpinned `osxexperts.net` + evermeet.cx "getrelease" latest).
- Produces: same output contract — universal `Tools/bin/ffmpeg`, `Tools/bin/ffprobe` — but from **versioned URLs verified against pinned SHA-256 hashes**. Was on the deferred backlog ("ffmpeg download checksums"); shipping a paid app whose encoder binary is fetched unpinned is a launch blocker, not a polish item.

- [ ] **Step 1: Capture today's artifacts and their hashes**

evermeet.cx serves versioned zips; `getrelease` is a moving target. Resolve the current version once, then pin it:

```bash
curl -sL "https://evermeet.cx/ffmpeg/info/ffmpeg/release" | python3 -c "import json,sys; print(json.load(sys.stdin)['version'])"
# → e.g. 7.1 — note it, then for each of the 4 zips (ffmpeg/ffprobe × arm64/x86):
curl -L --fail -o /tmp/pin.zip "<versioned-url>" && shasum -a 256 /tmp/pin.zip
```

Record the four `(url, sha256)` pairs.

- [ ] **Step 2: Rewrite the script with pinned URLs + verification**

```bash
#!/bin/bash
# Scripts/fetch-ffmpeg.sh — download PINNED static ffmpeg/ffprobe for both arches, verify, lipo universal.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p Tools/bin Tools/tmp

# Pinned 2026-07-14. To bump: update URL+SHA together (see docs block below).
declare -A URLS=(
  [ffmpeg-arm64]="https://www.osxexperts.net/ffmpeg71arm.zip"
  [ffprobe-arm64]="https://www.osxexperts.net/ffprobe71arm.zip"
  [ffmpeg-x86]="<versioned evermeet URL from Step 1>"
  [ffprobe-x86]="<versioned evermeet URL from Step 1>"
)
declare -A SHAS=(
  [ffmpeg-arm64]="<sha256 from Step 1>"
  [ffprobe-arm64]="<sha256 from Step 1>"
  [ffmpeg-x86]="<sha256 from Step 1>"
  [ffprobe-x86]="<sha256 from Step 1>"
)

for key in ffmpeg-arm64 ffprobe-arm64 ffmpeg-x86 ffprobe-x86; do
  curl -L --fail -o "Tools/tmp/${key}.zip" "${URLS[$key]}"
  echo "${SHAS[$key]}  Tools/tmp/${key}.zip" | shasum -a 256 -c - \
    || { echo "ERROR: checksum mismatch for ${key} — upstream changed, re-pin deliberately" >&2; exit 1; }
  unzip -o "Tools/tmp/${key}.zip" -d "Tools/tmp/${key}"
done
for tool in ffmpeg ffprobe; do
  lipo -create "Tools/tmp/${tool}-arm64/${tool}" "Tools/tmp/${tool}-x86/${tool}" -output "Tools/bin/${tool}"
  chmod +x "Tools/bin/${tool}"
done
rm -rf Tools/tmp
echo "Universal binaries ready:" && lipo -archs Tools/bin/ffmpeg
```

(The `<...>` values are filled from Step 1's recorded pairs at edit time — they cannot be known before downloading. Everything else lands verbatim.)

- [ ] **Step 3: Verify both success and tamper paths**

```bash
rm -rf Tools/bin && bash Scripts/fetch-ffmpeg.sh
```
Expected: `Universal binaries ready: x86_64 arm64`.

Then flip one hash digit in the script, re-run, expect `ERROR: checksum mismatch` and exit 1. Flip it back.

- [ ] **Step 4: Confirm the engine still passes and commit**

```bash
cd DenseCore && swift test 2>&1 | tail -3 && cd ..
git add Scripts/fetch-ffmpeg.sh
git commit -m "build: pin ffmpeg/ffprobe downloads to versioned URLs with SHA-256 verification"
```

Expected: 179 tests pass.

---

### Task 4: FFmpeg license compliance (attribution + source links)

**Files:**
- Modify: `App/SettingsView.swift` (About/credits area — locate the existing about section; if none, add a "Credits" footer in Settings)
- Modify: `Site/index.html` (footer)
- Create: `Site/licenses.html`

**Interfaces:**
- Consumes: nothing from other tasks.
- Produces: user-visible FFmpeg attribution + a hosted licenses page linking the FFmpeg source. Dense invokes ffmpeg/ffprobe as **separate processes** (`FFmpegRunner` spawns the bundled binary — mere aggregation, the standard defensible posture for closed-source apps), but (L)GPL distribution still obliges: ship the license text, state the version, link to the exact corresponding source. The old backlog item "arm64 source link on site" folds in here.

- [ ] **Step 1: Determine what the pinned builds are (GPL vs LGPL) and their exact version**

```bash
Tools/bin/ffmpeg -version | head -2
```

Expected output includes the version and `--enable-gpl` (or not) in the configuration line. Record both. (evermeet.cx and osxexperts builds are typically GPL-enabled — assume GPL wording unless the flag is absent.)

- [ ] **Step 2: Create `Site/licenses.html`**

Content requirements (match the existing Site page shell — copy the header/footer from `Site/changelog.html`):
- "Dense bundles FFmpeg <version> (<url to ffmpeg.org>), licensed under the GPL v2+ [or LGPL v2.1+ per Step 1]."
- Link to the full license text (`https://www.gnu.org/licenses/old-licenses/gpl-2.0.html` or the LGPL equivalent).
- Links to the exact source for **both** bundled builds: the evermeet.cx source page for the x86_64 build and the osxexperts source/upstream tag for the arm64 build (this is the written offer for corresponding source).
- One line: "FFmpeg is a trademark of Fabrice Bellard. Dense is not affiliated with the FFmpeg project."

- [ ] **Step 3: Add in-app attribution**

In the Settings/About area, add a static footer:

```swift
Text("Powered by FFmpeg — see dense.app/licenses")  // final domain per Task 10
    .font(.footnote).foregroundStyle(.secondary)
```

(Adjust to the file's existing style; keep copy identical.)

- [ ] **Step 4: Link the licenses page from the site footer, build, verify, commit**

Add `<a href="/licenses.html">Licenses</a>` to `Site/index.html` footer nav.

```bash
xcodegen generate && xcodebuild -project Dense.xcodeproj -scheme Dense -configuration Debug build 2>&1 | tail -2
git add Site/licenses.html Site/index.html App/SettingsView.swift
git commit -m "compliance: FFmpeg attribution in-app and licenses page with source links"
```

Expected: `BUILD SUCCEEDED`, zero new warnings.

---

### Task 5: One canonical release QA checklist + README screenshots

**Files:**
- Modify: `docs/qa-checklist.md` (rewrite for the shipped single-pane UI)
- Modify: `README.md` (screenshots)
- Delete: nothing (leave `docs/superpowers/plans/2026-07-13-redesign-qa.md` as the historical plan artifact)

**Interfaces:**
- Consumes: `docs/qa-checklist.md` (dock-card era, 11 sections — the *structure* and the non-UI sections are still good), `docs/superpowers/plans/2026-07-13-redesign-qa.md` (current UI, 26 checks + carried items).
- Produces: a single `docs/qa-checklist.md` that Task 9's human pass executes top-to-bottom. This is the most launch-critical artifact — it currently instructs testers to drop files on dock cards that no longer exist.

- [ ] **Step 1: Rewrite `docs/qa-checklist.md`**

Merge rules:
- Replace every dock-card drop path (§1 of the old file) with the sidebar-row / queue-pane / inspector flows from the redesign checklist, verbatim where possible.
- Keep the old file's non-UI sections that the redesign checklist lacks: output-file verification via ffprobe/Get Info, migration check (`defaults write app.dense.mac useHEVC -bool true` with `containerRaw` unset → redesigned app respects it), watched folders, deep links (`dense://`), Raycast, local HTTP API, license gate + Lemon Squeezy activation, Sparkle update check.
- Fold in the redesign checklist's carried manual items: sidebar vibrancy, selection persistence across relaunch, drop-on-row.
- Add two checks that exist in neither: **Gatekeeper first-run on a clean machine** (Task 8 Step 4) and the **Sparkle end-to-end update dry run** (Task 9 Step 3) — reference those steps rather than duplicating them.
- Keep the header's fixture list (small MP4, >500MB MP4, MOV, jpg/png/heic, gif, pdf, txt/zip junk, mixed folder).

- [ ] **Step 2: Update README screenshots**

Take 2–3 screenshots of the shipped UI (sidebar + queue + inspector, light and dark), save as `docs/img/queue.png`, `docs/img/inspector.png`, embed in README's Features section, delete the "Screenshots will be updated after the single-pane redesign" note. (Screenshots need the app running — fold into the same session as Task 9's QA pass if more convenient; the README must not ship stale.)

- [ ] **Step 3: Commit**

```bash
git add docs/qa-checklist.md README.md docs/img/
git commit -m "docs: consolidate release QA checklist for single-pane UI; refresh README screenshots"
```

---

### Task 6 [USER]: Apple signing prerequisites

**Files:** none (accounts + keychain).

**Interfaces:**
- Produces: a "Developer ID Application" identity in the login keychain and a `dense-notary` notarytool profile — exactly what `Scripts/release.sh` line 6 and the `--keychain-profile dense-notary` call expect. release.sh's own doc block (lines ~95–120) walks every step.

- [ ] **Step 1:** Enroll in the Apple Developer Program ($99/yr) if not already active.
- [ ] **Step 2:** Create a **Developer ID Application** certificate — Xcode → Settings → Accounts → Manage Certificates → "+", or developer.apple.com → Certificates. Verify:

```bash
security find-identity -v -p codesigning
```
Expected: a line containing `Developer ID Application: <name> (<TEAMID>)`.

- [ ] **Step 3:** Create an App Store Connect API key (Users and Access → Integrations → App Store Connect API) and store it:

```bash
xcrun notarytool store-credentials dense-notary --key <AuthKey_XXXX.p8> --key-id <KEYID> --issuer <ISSUER-UUID>
xcrun notarytool history --keychain-profile dense-notary
```
Expected: `history` returns (an empty list is fine) — proves the profile authenticates.

---

### Task 7 [USER]: Sparkle update keys

**Files:**
- Modify: `project.yml` (replace `REPLACE-AT-LAUNCH-EDKEY` — 4 occurrences repo-wide, the authoritative one is in project.yml; `xcodegen generate` propagates to Info.plist)

**Interfaces:**
- Consumes: Sparkle's `generate_keys` (in the SPM checkout under `build/dd/SourcePackages`, same discovery trick release.sh uses for `sign_update`).
- Produces: the public EdDSA key in `SUPublicEDKey`; the private key stays in the login keychain. `DenseApp.swift`'s placeholder sentinel guard (added after the launch-hang bug bit three verification runs) stops skipping the updater once the real key and feed URL are in.

- [ ] **Step 1: Generate keys**

```bash
GENERATE_KEYS=$(find build/dd/SourcePackages -type f -name generate_keys -perm +111 | head -1)
"$GENERATE_KEYS"
```
Expected: prints a public key; private key stored in the keychain. **Immediately** note the printed backup instructions — losing the private key orphans every shipped install off the update channel. Export/back it up per Sparkle's docs.

- [ ] **Step 2: Replace the placeholder and regenerate**

Replace `REPLACE-AT-LAUNCH-EDKEY` in `project.yml` with the public key; run `xcodegen generate`; confirm:

```bash
git grep -c "REPLACE-AT-LAUNCH-EDKEY" -- project.yml App/Info.plist || echo "edkey clear"
```
Expected: `edkey clear` (appcast/docs occurrences remain until Task 12). Commit.

*Note: `SUFeedURL` (`https://REPLACE-AT-LAUNCH.example/appcast.xml`) stays a placeholder until the domain exists — Task 12 sets it, and a second `release.sh` run rebuilds with it. Plan for the final DMG to be cut **after** Task 12.*

---

### Task 8 [USER]: Cut and verify the release candidate

**Files:**
- Runs: `Scripts/release.sh` (no edits expected)

**Interfaces:**
- Consumes: Tasks 6–7 (cert, notary profile, EdDSA key), Task 3 (pinned ffmpeg in `Tools/bin`).
- Produces: `build/Dense-1.0.0-rc1.dmg` — signed, notarized, stapled — for the QA pass. (Cut as an RC; the *final* 1.0.0 is re-cut in Task 12 once the feed URL and site links are real.)

- [ ] **Step 1:** `bash Scripts/release.sh 1.0.0-rc1`
Expected: universal-arch check passes, notarytool reports `status: Accepted`, staple succeeds, script prints the appcast `edSignature` attrs and `DONE:` line. First notarization can take up to an hour; subsequent ones minutes.
- [ ] **Step 2:** Verify signatures locally:

```bash
spctl -a -t open --context context:primary-signature -v build/Dense-1.0.0-rc1.dmg
codesign --verify --deep --strict --verbose=2 build/Dense.xcarchive/Products/Applications/Dense.app
```
Expected: `accepted` / `source=Notarized Developer ID`; codesign silent success.
- [ ] **Step 3:** **Clean-machine Gatekeeper test** — copy the DMG to a Mac (or fresh macOS VM / second user account with cleared quarantine state) that has never run Dense, mount, drag to /Applications, launch. Expected: standard "downloaded from the internet" first-run dialog, **no** "unidentified developer" block, app reaches the main window and compresses a fixture clip.
- [ ] **Step 4:** Record the real `demo.gif` while you're here — dock-drop + shrinking size bar (the playbook's two signature moments) — replacing `Site/demo.gif` (lands with Task 12's commit).

---

### Task 9 [USER]: Full manual QA pass + Sparkle end-to-end dry run

**Files:**
- Executes: `docs/qa-checklist.md` (Task 5's consolidated version)

**Interfaces:**
- Consumes: Task 8's RC build.
- Produces: a checked-off checklist with actual-result notes on failures; go/no-go. Any Important failure loops back to a fix commit and a new RC.

- [ ] **Step 1:** Run every section of `docs/qa-checklist.md` on the RC, on real hardware, light + dark appearance. Write the observed result next to any failure.
- [ ] **Step 2:** License gate end-to-end deferred to Task 11 Step 3 (needs the live store) — mark it "pending Task 11" rather than skipping silently.
- [ ] **Step 3:** **Sparkle dry run** (the update channel must be proven before v1.0.1 needs it):
  1. Host `Site/appcast.xml` anywhere reachable (final host, or a temporary Pages deploy).
  2. Build a throwaway `1.0.0-rc1` install pointing `SUFeedURL` at it; launch.
  3. Cut `1.0.0-rc2` with release.sh, add its enclosure (URL + `sparkle:edSignature` + real `length`) to the appcast.
  4. In the rc1 install: Check for Updates → Expected: rc2 offered, downloads, signature validates, installs, relaunches as rc2.

---

### Task 10 [USER]: Domain, site deploy, waitlist

**Interfaces:**
- Consumes: Site/ (16 pages, ready), campaign playbook day-1 checklist.
- Produces: live site at the real domain; Buttondown embed capturing emails. Blocks Tasks 11–12 (checkout link and all URLs need the domain).

- [ ] **Step 1:** Clear the name first (playbook day 1): trademark search, App Store search, social-handle availability for "Dense". If it fails, the rename decision happens **now**, before any URL is printed on anything.
- [ ] **Step 2:** Buy the domain; deploy `Site/` to Cloudflare Pages (connect the GitHub repo, root = `Site/`, no build step — static HTML). Expected: all 16 pages render at the production URL.
- [ ] **Step 3:** Create the Buttondown list, replace the waitlist form placeholder embed in `Site/index.html`, test one real signup end-to-end (email arrives).

---

### Task 11 [USER]: Lemon Squeezy store + licensing end-to-end

**Files:**
- Modify: `App/LicenseGateView.swift:14` (real checkout URL)
- Modify: `Site/*` pages carrying `LICENSE-TERMS-TBD` (4) and `REFUND-POLICY-TBD` (3)

**Interfaces:**
- Consumes: `DenseCore/LicenseClient.swift` (already pointed at `api.lemonsqueezy.com/v1/licenses/` — activate/validate), Task 10's domain.
- Produces: a purchasable product and a proven activation path.

- [ ] **Step 1:** Create the Lemon Squeezy store + product: $29, license keys enabled, **decide seat count** (resolves `LICENSE-TERMS-TBD` ×4) and **refund policy** (resolves `REFUND-POLICY-TBD` ×2 on site + 1 in docs); create the `LAUNCH35` 35%-off coupon.
- [ ] **Step 2:** Put the real checkout URL into `LicenseGateView.swift:14` and the site's buy buttons.
- [ ] **Step 3:** **One real end-to-end test with real money:** buy with a real card (self-refund after), receive the license key email, activate inside Dense. Expected: gate unlocks and persists across relaunch; then validate the refund flow you just promised in the policy. This also closes Task 9 Step 2's pending item.

---

### Task 12 [USER, agent-assisted]: Resolve every placeholder, cut final 1.0.0, tag

**Files:**
- Modify: `App/Info.plist` (SUFeedURL), `Site/appcast.xml` (enclosure URL, edSignature, length), `Site/index.html` + 15 doc/guide pages (download links), `Site/changelog.html` (1.0.0 entry), `App/LicenseGateView.swift` (if not done in Task 11)

**Interfaces:**
- Consumes: real domain (T10), store (T11), signing chain (T6–8).
- Produces: zero placeholders; `Dense-1.0.0.dmg` live at the download URL; git tag + GitHub release.

- [ ] **Step 1:** Agent sweep: replace every remaining `REPLACE-AT-LAUNCH` token with the real value (domain, appcast URL, download URL, checkout URL). The final `release.sh 1.0.0` run prints the `edSignature`/`length` pair — paste into `Site/appcast.xml`.
- [ ] **Step 2:** Re-cut the **final** DMG now that `SUFeedURL` is real: `bash Scripts/release.sh 1.0.0`. Upload the DMG to the download host; re-verify the download link + Gatekeeper on the clean machine once more (it's a different binary than rc1).
- [ ] **Step 3: The ship gate** —

```bash
git grep -n "REPLACE-AT-LAUNCH\|LICENSE-TERMS-TBD\|REFUND-POLICY-TBD" -- . ':!docs/superpowers' && echo "BLOCKED" || echo "CLEAR TO SHIP"
```
Expected: `CLEAR TO SHIP` (historical plan docs exempted; `DenseApp.swift`'s sentinel *constant* is the guard itself — keep it, it compares against the prefix and simply never matches again. If the grep flags that one line, tighten the pathspec, don't delete the guard).
- [ ] **Step 4:**

```bash
git tag -a v1.0.0 -m "Dense 1.0.0" && git push origin v1.0.0
gh release create v1.0.0 build/Dense-1.0.0.dmg --title "Dense 1.0.0" --notes-file <(sed -n '/1.0.0/,/<\/section>/p' Site/changelog.html | textutil -stdin -stdout -convert txt -format html 2>/dev/null || echo "See changelog: <site>/changelog.html")
```

---

### Task 13 [USER]: Raycast extension store submission

**Interfaces:**
- Consumes: `integrations/raycast/README.md` (its own submission checklist), live app (deep links must resolve for reviewers).
- Produces: extension in the Raycast store — a distribution channel the playbook leans on.

- [ ] **Step 1:** Work through `integrations/raycast/README.md`'s checklist; submit via `npm run publish` from `integrations/raycast/` (Raycast's PR-based flow). Expected review turnaround: days — start this **before** launch week so it lands during it.

---

### Task 14 [USER, agent-drafted]: Launch campaign + post-launch operations

**Interfaces:**
- Consumes: `docs/superpowers/plans/2026-07-09-launch-campaign-playbook.md` — execute as written (4 weeks, <$500, PH Tuesday anchor).
- Produces: the launch, plus the operational loop that keeps 1.0.0 healthy.

- [ ] **Step 1:** Run the playbook. Agents draft (posts, HandBrake benchmark, PH assets); you post. Every number in copy obeys the truthfulness whitelist (measured, "up to" hedged).
- [ ] **Step 2:** Stand up the support loop before the PH post goes live: support@ alias on the domain → your inbox; add the address to the site footer and the Lemon Squeezy receipt email. (Dense ships no crash reporter or analytics by design — privacy is a selling point; the support address and Sparkle update stats are the feedback channel. If launch volume proves the need, evaluate an opt-in crash reporter as a v1.1 decision, not a launch patch.)
- [ ] **Step 3:** Hold the playbook's kill criterion honestly: **<10 licenses AND <500 visits at week 4 → iterate positioning/demos for 4 weeks; do not panic-build features.**
- [ ] **Step 4:** Schedule the **v1.0.1 polish release** (~2 weeks post-launch) from the triaged deferred backlog — write it up as its own plan when scheduled (`docs/superpowers/plans/`), it is deliberately out of scope here:
  - short-clip preview seek clamp; toolbar `.accessibilityLabel`s; `selectedJob` `jobs.last` fallback; PDF-search coverage gaps (middle-rung-wins, all-not-smaller); loose test assertions; DiskSpace exact-boundary test; advanced-toolbar chevron state; savings ledger stat; per-file remove button; output-path collision uniquing; LicenseClient mocked tests; generic probeFailed copy for pdf/image.
  - v1.0.1 doubles as the first real proof of the Sparkle channel to actual users.

---

## Self-Review Notes

- **Spec coverage:** Every open item from the 2026-07-11 launch plan (§B release engineering, §C commerce, §D campaign) maps to Tasks 6–14. New gaps not in any prior doc: repo sync (T1), CI (T2), ffmpeg pinning promoted from backlog to blocker (T3), license compliance (T4), stale QA checklist merge (T5), Sparkle end-to-end dry run (T9), support channel (T14).
- **Sequencing risk called out:** the DMG must be cut twice (rc for QA, final after placeholder resolution) because `SUFeedURL` bakes into the bundle — Tasks 7/8/12 all note it.
- **Unpinnable values:** SHA-256 hashes (T3) and Sparkle keys (T7) are generated at execution time; those steps contain the exact command that produces the value, which is the strongest possible specification.
