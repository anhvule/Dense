# Manual QA Checklist — Dense (release pass)

Run this pass by hand on a real Mac before every tagged release. It exists because
the automated suite (`swift test`) covers the compression engine, argument-building,
and state logic — it does not drive the SwiftUI surface, real drag-and-drop, the
Finder, System Settings, notarization/Gatekeeper, or a real Lemon Squeezy store.
Every item below is something a person must actually watch happen. Run on macOS 14+,
in both light and dark appearance.

Use a mix of test clips: at least one small MP4, one large (>500MB) MP4, one MOV,
an image (`.jpg`/`.png`/`.heic`), a `.gif`, a `.pdf`, a genuinely unsupported file
(e.g. a `.txt` or `.zip`), and a folder containing a mix of the above.

Check off each box and write the actual result next to any failure.

---

## 1. Sidebar & destinations

- [ ] All 7 destinations render with vibrancy; budgets right-aligned, monospaced
      (Discord ≤25MB, Slack ≤50MB, Email — strict ≤10MB, Email ≤25MB, Web/Social
      1080p, YouTube quality-oriented, Custom "your rules").
- [ ] Clicking a row (no drag) selects it — highlight moves, VoiceOver label
      changes to include ", selected".
- [ ] **Selection persists across relaunch** — select a non-default destination
      (e.g. Slack), quit the app fully (Cmd-Q), relaunch. Expected: Slack is
      still the selected/highlighted row, and a drop immediately after launch
      uses the Slack preset.
- [ ] **Drop video onto the "Slack" row** → job uses the 50 MB budget, Slack
      becomes selected.
- [ ] **Drop PDF onto "Email — strict"** → output ≤ 10 MB or fails with the
      closest achievable size.

## 2. Queue pane

- [ ] Empty state names the current destination and updates immediately when
      the sidebar selection changes.
- [ ] **Whole pane accepts drops** — files and folders, mixed video/PDF/image/GIF
      in one gesture — not just a specific row or region.
- [ ] **Folder drop (one level)** — drag a folder containing 2–3 videos and one
      non-video file onto the pane. Expected: all supported files inside are
      added to the queue (one level of expansion only — a file nested two
      folders deep should NOT be picked up), unsupported files inside are
      silently skipped, and no rejection banner fires for the folder itself.
- [ ] **Unsupported-type rejection, empty queue** — with no jobs in the queue,
      drop a genuinely unsupported file (e.g. `.txt` or `.zip`). Expected:
      nothing is added to the queue, and the orange banner "That file type
      isn't supported yet." appears (images, GIFs, and PDFs are all supported
      job kinds — that copy must never appear for them).
- [ ] **Unsupported-type rejection, non-empty queue** — with at least one job
      already queued/compressing, drop an unsupported file. Expected: the
      existing queue is undisturbed, the same rejection banner appears.
- [ ] **Mixed drop** — drop a supported file and an unsupported file together in
      one gesture. Expected: the supported file is accepted and queued, the
      unsupported file is silently skipped, and NO rejection banner appears
      (the banner only fires when *nothing* in the drop was usable).
- [ ] **Rows: live progress** — the shrink bar visibly and smoothly shrinks
      left-to-right as a real (non-instant) encode advances, not a static bar
      or a jump-cut at completion; the percentage text updates in step.
- [ ] **Thumbnails on real videos** — each row eventually shows an actual frame
      thumbnail (not the generic placeholder) once resolved; different videos
      show visibly different thumbnails. PDF rows show a document icon; video
      rows show thumbnail + play badge.
- [ ] Clicking a row shows a teal selection ring; savings % shown on completed
      rows.
- [ ] On completion, row shows "input size → output size", the green "−NN%"
      savings figure, and a magnifying-glass button that reveals the output
      file selected in Finder when clicked.
- [ ] A file that's already small/optimized shows the "Already optimized"
      subtitle and is not needlessly recompressed.
- [ ] A failed job shows the failure message in red instead of a size line.
- [ ] **Toolbar** — with an empty queue, only "Dense" shows (no summary line,
      no Cancel/Clear buttons). Cancel All / Clear appear only once jobs exist;
      the batch summary line appears in the subtitle.
- [ ] **Batch summary with a real multi-file batch** — queue 4–5 real files of
      varying sizes and let them all finish. Expected: the summary reads
      "N files · saved X MB (−NN%)" and the saved bytes/percent match manual
      arithmetic on the actual input/output file sizes (spot-check with
      Finder "Get Info" or `ls -la`).
- [ ] **Cancel all mid-encode** — start a batch of several large files, click
      "Cancel all" while at least one job is `running`. Expected: the
      in-progress ffmpeg process is actually killed (check Activity Monitor —
      no orphaned `ffmpeg` process), queued jobs don't start, and rows reflect
      a cancelled/stopped state rather than silently finishing.
- [ ] "Clear" removes finished (done/failed) rows but does not disturb any job
      still queued or running.

## 3. Inspector

- [ ] Row click opens the inspector; the toolbar button toggles it.
- [ ] **Video**: two frames shown side-by-side (original vs. compressed), with
      a size estimate under the Compressed pane.
- [ ] Releasing the target-size slider re-renders the estimate; clicking Apply
      enqueues a job that lands near the chosen target.
- [ ] **PDF**: page shown side-by-side; Good/Balanced/Small re-renders the
      preview; text stays legible at the Good tier.
- [ ] Selecting a corrupt file shows error text, no Apply button, and no
      crash.

## 4. Advanced panel — each option changes real ffmpeg output

Toggle the panel open (slider icon in the toolbar). For every option below,
change it, run a compression, and **verify against the actual output file**
(via `ffprobe`, Finder Get Info, or QuickTime inspector) — not just that the UI
control moved.

- [ ] **Format → MP4 · H.264**: output container is `.mp4`, video stream codec
      is H.264/AVC.
- [ ] **Format → MP4 · HEVC**: output container is `.mp4`, video stream codec is
      HEVC/H.265, and the file actually plays (tag `hvc1` applied correctly for
      QuickTime compatibility).
- [ ] **Format → MOV**: output file extension/container is `.mov`.
- [ ] **Resolution cap**: set each non-default resolution option and confirm
      `ffprobe`-reported output dimensions match (long edge or height per the
      option, not just "smaller than input").
- [ ] **Resolution → Preset default**: leaving this unset lets the selected
      destination's own resolution rule apply (e.g. Web/Social's 1080p) rather
      than forcing a different cap.
- [ ] **Target size (MB)**: set an explicit target (e.g. type "10"), compress a
      file that would otherwise be larger, and confirm the resulting output
      file size is at/under the typed target (within reasonable encoder
      tolerance).
- [ ] **Remove audio**: toggle on, compress, confirm via `ffprobe` that the
      output has no audio stream; toggle off and confirm audio is preserved.
- [ ] **Output → Next to original**: output file lands in the same folder as
      the source.
- [ ] **Output → Custom folder**: pick a folder via "Change…", compress, and
      confirm the output actually lands in that folder, not next to the
      original.
- [ ] **Folder picker live path refresh** — after choosing a folder, the path
      text shown next to "Change…" updates immediately (no stale path, no
      restart required) and truncates sanely for long paths.
- [ ] **Filename suffix**: change the suffix text (e.g. from `-compressed` to
      `-small`), compress, and confirm the output filename actually uses the
      new suffix.
- [ ] **Move originals to Trash — confirm alert appears**: turning the toggle
      on pops the "Move originals to Trash?" alert before it takes effect;
      "Cancel" leaves the toggle off.
- [ ] **Trash alert end-to-end** — confirm the alert, compress a file
      successfully, then: (a) verify the original file is gone from its
      original folder, (b) open Finder's Trash and confirm the original is
      there, (c) right-click → "Put Back" in Trash and confirm it returns to
      its original location intact. This is the full round-trip, not just "the
      toggle stuck."
- [ ] **Trash + failed job**: if a job fails, confirm the original is NOT moved
      to Trash (only successful compressions should trigger it).
- [ ] **GIF mode toggle**: turning on "Convert to GIF" and compressing produces
      an actual `.gif` output (not `.mp4`).
- [ ] **GIF fps stepper affects output** — set a low fps (e.g. 5) vs a high fps
      (e.g. 24), compress the same source both ways, and confirm via `ffprobe`
      or frame-counting that the resulting GIFs have different, matching frame
      rates.
- [ ] **GIF width stepper affects output** — set a narrow width (e.g. 240) vs
      wide (e.g. 800), compress the same source both ways, and confirm the
      output GIF pixel width matches what was set.

## 5. Output handling / engine safety

- [ ] Compressing a file with "Next to original" + default suffix never
      overwrites the source (engine guard: output path must never equal input
      path) — try a scenario likely to collide (empty suffix, same container)
      and confirm the app refuses/adjusts rather than clobbering the original.
- [ ] Re-running compression on an already-compressed output doesn't recurse
      into runaway re-suffixing.
- [ ] **Known limitation (v1.1)**: two same-named files from different source
      folders (e.g. two `clip.mp4` files in different directories) compressed
      simultaneously into one custom output folder can collide on the same
      output path. Avoid same-stem batches into a custom folder for now; this
      is a known limitation, not a regression to chase down before v1.

## 6. Edge cases

- [ ] Junk `.mp4` (e.g. `echo junk > bad.mp4`) → row fails with the
      "corrupted or unsupported" copy, batch continues.
- [ ] A 1-hour clip compressed at the Discord destination fails fast with the
      closest achievable MB rather than hanging or silently missing budget.
- [ ] A vector-only PDF is skipped with "Already optimized".
- [ ] A password-protected PDF shows a failed row; batch continues.
- [ ] **Backgrounded during a batch** — switch to another app mid-batch and let
      it finish. Expected: a completion notification appears (the first time,
      macOS asks for notification permission).
- [ ] **Long encode doesn't sleep the Mac** — during a lengthy real encode,
      the Mac doesn't go to sleep and App Nap doesn't stall progress.
- [ ] Originals are untouched in every scenario above.
- [ ] Trial banner and license gate still render correctly (no regression from
      the single-pane layout).

## 7. HEVC legacy migration

- [ ] **Migration for a user upgrading with legacy `useHEVC=true`** — simulate
      a pre-redesign install by setting
      `defaults write app.dense.mac useHEVC -bool true`
      and leaving `containerRaw` unset (or `mp4`), then launch the current
      build. Expected: the one-time migration folds this into
      `containerRaw = "mp4-hevc"`, the Format picker shows "MP4 · HEVC"
      selected on first launch, and this migration does not re-fire (and does
      not fight a user who deliberately picks MP4 · H.264 afterward) on
      subsequent launches.

## 8. Licensing / trial

- [ ] Fresh install shows the 7-day trial banner with days-remaining that
      counts down correctly.
- [ ] **Trial gate with an aged `trialStart`** — manually back-date the stored
      `trialStart` value (e.g. via `defaults write` on the app's bundle ID) to
      more than 7 days ago, relaunch, and confirm the License Gate view
      appears and blocks compression until a valid key is activated.
- [ ] License Gate's "Buy License" link opens the correct Lemon Squeezy
      checkout URL (confirm the placeholder `REPLACE-AT-LAUNCH` domain has been
      swapped for the real store before shipping).
- [ ] **Real Lemon Squeezy activation** — using an actual store-issued license
      key (not a mock), paste it into the License Gate, click Activate, and
      confirm activation succeeds and the gate is dismissed. *(Needs the store
      live — defer to campaign week 3 per the launch plan.)*
- [ ] Activation failure (bad key / no network) shows the inline error message
      and does not silently unlock the app.

## 9. Sparkle updates

- [ ] App checks for updates on schedule / via manual "Check for Updates…" and
      the appcast reflects the current shipped version.
- [ ] Update flow downloads, verifies signature, and installs without manual
      Gatekeeper workarounds.
- [ ] **Sparkle placeholder-feed hang regression** — with the shipped/dev
      build's `Info.plist` `SUFeedURL` still containing the
      `REPLACE-AT-LAUNCH` placeholder (the normal state until the real feed
      is set at launch), launch the app and confirm it does **not** hang or
      show a blocking "Unable to Check For Updates" alert — the window
      appears normally and the app stays fully interactive.
- [ ] **"Check for Updates…" is a safe no-op on a placeholder build** — with
      the placeholder feed still in place, select Check for Updates… from
      the menu (it should appear disabled). Confirm nothing crashes or hangs
      even if triggered.
- [ ] **Sparkle end-to-end update dry run** — see
      `docs/superpowers/plans/2026-07-14-production-readiness.md`, Task 9
      Step 3: host the appcast, build a throwaway `1.0.0-rc1` pointed at it,
      cut `1.0.0-rc2`, and confirm rc1's "Check for Updates" finds, verifies,
      downloads, and installs rc2, relaunching as rc2. Requires an actual
      release-candidate pair; run this once per release cycle rather than on
      every tagged build.

## 10. Gatekeeper / first run

- [ ] **Gatekeeper first-run on a clean machine** — see
      `docs/superpowers/plans/2026-07-14-production-readiness.md`, Task 8
      Step 3: copy the signed, notarized DMG to a Mac (or fresh macOS VM /
      second user account with cleared quarantine state) that has never run
      Dense, mount, drag to /Applications, launch. Expected: the standard
      "downloaded from the internet" first-run dialog, **no** "unidentified
      developer" block, and the app reaches the main window and compresses a
      fixture clip. Requires a signed/notarized release build; run once per
      release candidate.

## 11. Watched folders

- [ ] **Add a watched folder** via Advanced → Watched folders → "Add folder…",
      then copy a video into it. Expected: after a ~2s debounce (plus a 1s
      size-stability wait), the file is auto-enqueued and a `-compressed`
      output appears next to it. The output itself must NOT be re-enqueued
      (no compress loop).
- [ ] **Pre-existing files are ignored** — files already in the folder when
      watching starts are never compressed; only new arrivals are.
- [ ] **Relaunch fresh-seeding is designed behavior, not a bug** — files
      added to a watched folder *while the app was closed* are NOT
      auto-compressed on the next launch (deliberate: prevents surprise
      mass-compression of a backlog). Do not file this as a failure.
- [ ] **Per-folder preset** — set a watched folder to Small File, drop a clip
      in, and confirm the output reflects that preset while the sidebar's
      selected destination is unchanged.
- [ ] **Editing one folder doesn't disturb another** — while a file is mid-copy
      into folder A, toggle/edit folder B; the folder-A file must still be
      picked up and compressed once its copy completes.
- [ ] **Missing folder** — delete a watched folder on disk, reopen the panel:
      row shows a warning icon, watching is skipped, no crash.

## 12. Floating drop zone & completion confetti

- [ ] **Show/hide the drop zone** — click the drop-zone header icon. Expected:
      a small circular always-on-top panel appears near the top-right of the
      screen the first time (and wherever it was last dragged, on subsequent
      toggles); clicking again hides it.
- [ ] **Drop zone stays on top of other apps** — with the panel visible,
      switch to a different app (including a full-screen one on another
      Space) and confirm the circle is still visible and still accepts a
      drop.
- [ ] **Dropping onto the zone queues a real job** — drag a file onto the
      circle. Expected: it's added to the queue using the currently selected
      destination, identical to a drop onto the main window.
- [ ] **Position persists** — drag the panel to a new spot, quit and relaunch
      Dense, re-show the drop zone. Expected: it reappears at the dragged
      position, not the default corner.
- [ ] **Closing the main window doesn't close the drop zone** — with the
      panel visible, close Dense's main window. Expected: the floating panel
      stays visible and still accepts drops.
- [ ] **Confetti fires on a successful batch** — queue one or more files and
      let them finish successfully. Expected: once the whole batch goes
      idle, a confetti burst plays (only when at least one job in that batch
      succeeded — a batch that only failed/skipped must NOT trigger it).
- [ ] **Confetti respects Reduce Motion** — enable "Reduce motion" in System
      Settings → Accessibility → Display, then repeat a successful batch.
      Expected: no confetti burst fires.
- [ ] **Confetti doesn't double-fire mid-batch** — queue several files that
      finish at different times within the same batch. Expected: exactly one
      burst when the whole batch goes idle, not one per completed file.

## 13. Deep links (`dense://`)

- [ ] A `dense://` deep link enqueues into the queue pane the same as a
      manual drop would.

## 14. Local HTTP API

- [ ] **Off by default** — on a fresh install, confirm the Advanced panel's
      "Local API" toggle is off and `curl http://127.0.0.1:4499/v1/jobs`
      fails to connect.
- [ ] **Enabling starts the listener** — flip the toggle on. Expected: a port
      field (default 4499) and a bearer token appear; the token also gets
      written to `~/Library/Application Support/Dense/api-token` with
      `0600` permissions (`ls -l` to confirm) readable only by the current
      user.
- [ ] **Loopback only** — confirm (e.g. via `lsof -i -P | grep Dense` or
      attempting a connection from another machine on the LAN using the
      Mac's LAN IP) that the listener is bound to `127.0.0.1` only, never
      reachable from another host.
- [ ] **Auth required** — `curl -s -o /dev/null -w '%{http_code}'` a request
      to `/v1/compress` or `/v1/jobs` with no `Authorization` header, and
      again with a wrong token. Expected: `401` both times, and an unknown
      route with a wrong token is still `401` (never a `404` that would leak
      route existence to an unauthenticated caller).
- [ ] **POST /v1/compress end-to-end** — with the real token, POST a JSON
      body with a valid absolute path and a preset. Expected: `202`, the
      file appears in the app's queue and actually compresses; the response
      JSON's `accepted` count matches.
- [ ] **Skipped paths reported, not silently dropped** — include a
      nonexistent path and a directory path in the same request. Expected:
      both show up in the response's `skipped` array, the valid path(s)
      still get accepted.
- [ ] **Path traversal rejected** — POST a path containing a `..` component.
      Expected: `400 Bad Request`, nothing enqueued.
- [ ] **GET /v1/jobs reflects real state** — after queueing a mix of jobs,
      GET this endpoint and confirm the JSON list's statuses (`queued`,
      `running`, `done`, `failed: …`) match what the app UI shows.
- [ ] **Token rotates on restart** — toggle the API off then on again (or
      quit/relaunch with it enabled). Expected: the displayed token changes,
      and the *old* token is rejected (401) on a subsequent request.
- [ ] **Token file lifecycle** — quit the app (or toggle the API off) while
      it's enabled. Expected: the `api-token` file at
      `~/Library/Application Support/Dense/api-token` is removed; it must
      not linger for a process that isn't actually listening.
- [ ] **API-triggered compress never changes the default preset** — note the
      currently selected destination, fire an API compress with a different
      preset, then do a manual drop with no destination change. Expected:
      the manual drop still uses the *original* default destination, not the
      one the API call used.

## 15. Raycast extension

Manual flow — the extension itself has no `swift test` coverage (it's a
separate TypeScript project in `integrations/raycast/`); this section is the
substitute end-to-end check.

- [ ] **Install and build** — `cd integrations/raycast && npm install && npx
      ray build -e dist` succeeds with no errors (or run via `npx ray
      develop` for a live dev session in Raycast).
- [ ] **"Compress with Dense" with a Finder selection** — select one or more
      supported files in Finder, run the command from Raycast, pick a
      preset. Expected: Dense launches (or comes forward) and the selected
      files appear in the queue using the chosen preset.
- [ ] **"Compress with Dense" with no Finder selection** — run the command
      with nothing selected in Finder. Expected: a "No Finder Selection"
      toast, nothing sent to Dense.
- [ ] **Mixed selection with unsupported files** — select a mix of supported
      and unsupported files, run the command. Expected: supported files are
      sent and queued in Dense; the HUD/toast notes how many were skipped as
      unsupported rather than failing the whole action.
- [ ] **"Compress Clipboard File"** — copy a single supported file (or its
      path/`file://` URL) to the clipboard, run the command with a preset.
      Expected: that one file is sent to Dense and queued.
- [ ] **Dense not installed / not found** — (if feasible to simulate, e.g. on
      a clean VM) running either command should show a "Dense Isn't
      Installed" toast with a link, not a silent failure or a crash.

## 16. Smart rename

- [ ] **Off by default** — on a fresh install, confirm "Smart names for
      images" in the Advanced panel is off, and the caption "Uses on-device
      image recognition — nothing leaves your Mac." is visible under it.
- [ ] **Enabled: output gets renamed** — turn the toggle on, compress a
      recognizable photo (e.g. a beach, a dog, a car). Expected: the output
      file's name changes to a `<label>-<label>-yyyy-MM-dd.<ext>` pattern
      (confirm in Finder or via the file row's filename label and "reveal in
      Finder" button — both must point at the renamed file, not the old
      name).
- [ ] **Original is never touched** — after the above, confirm the *input*
      file's name and location are completely unchanged.
- [ ] **Low-confidence / unclassifiable image** — compress a blank/abstract
      image Vision can't confidently label. Expected: the output keeps its
      normal `-compressed`-suffixed name; no error, no banner, job still
      shows as done.
- [ ] **Collision handling** — compress two different images that would
      classify to the same label pair on the same day, into the same folder.
      Expected: the second one lands as `<stem>-2.<ext>` rather than
      overwriting the first.
- [ ] **Toggle only affects `.image` jobs** — with smart rename on, compress
      a video and a PDF. Expected: neither output is renamed (the feature
      only applies to image compression outputs).

## 17. Cross-cutting persistence (relaunch)

Change every setting below in one session, fully quit (Cmd-Q), relaunch, and
confirm each one is exactly as left:

- [ ] Selected destination
- [ ] Format (H.264 / HEVC / MOV)
- [ ] Resolution cap
- [ ] Target size MB text
- [ ] Remove audio toggle
- [ ] Output folder mode (next-to-original vs custom) and the stored custom
      path
- [ ] Filename suffix text
- [ ] Move-originals-to-Trash toggle
- [ ] GIF mode toggle, fps, and width steppers
- [ ] Watched folders list (paths, per-folder presets, enable toggles)

---

## Pass criteria

Every box above checked with the *actual* observed result matching the
*expected* result, on a real macOS machine, with real (not mocked) ffmpeg
encodes and a real Finder/Trash. `swift test` and the Release build passing is
a prerequisite, not a substitute, for this pass.
