# Manual QA Checklist — Compress (destination-dock redesign)

Run this pass by hand on a real Mac before every tagged release. It exists because
the automated suite (`swift test`, currently 45/45) covers the compression engine,
argument-building, and state logic — it does not drive the SwiftUI surface, real
drag-and-drop, the Finder, System Settings, or a real Lemon Squeezy store. Every
item below is something a person must actually watch happen.

Use a mix of test clips: at least one small MP4, one large (>500MB) MP4, one MOV,
one non-video file (e.g. a `.png` and a `.pdf`), and a folder containing a couple
of videos plus a non-video file.

Check off each box and write the actual result next to any failure.

---

## 1. Drop paths

- [ ] **Drop onto the Discord dock card** with the queue empty. Expected: file is
      accepted, added to the queue, and compresses using the Discord preset
      (≤25MB target) — confirm by checking the Advanced panel shows Discord's
      settings were applied (or by inspecting the output file size).
- [ ] **Drop onto the Email dock card.** Expected: same as above, using the Email
      preset (≤25MB target).
- [ ] **Drop onto the YouTube dock card.** Expected: accepted, compresses using
      the YouTube preset (quality-oriented, not size-capped).
- [ ] **Drop onto the Web/Social dock card.** Expected: accepted, compresses
      using the Web/Social preset (1080p cap).
- [ ] **Drop onto the Custom dock card.** Expected: accepted, uses whatever the
      Advanced panel currently has configured (Balanced/custom preset).
- [ ] **Dropping onto a dock card also selects it** — after the drop, the card
      shows the "selected" highlight (accent border/fill) and stays selected for
      the *next* drop/click, not just for that one job.
- [ ] **Global drop** — drag a video onto the main window background (not onto
      any dock card). Expected: file is accepted using whatever preset is
      currently selected (the highlighted dock card), and processing starts.
- [ ] **Folder drop (one level)** — drag a folder containing 2–3 videos and one
      non-video file onto the window. Expected: all videos inside are added to
      the queue (one level of expansion only — a video nested two folders deep
      should NOT be picked up), the non-video file inside is silently skipped,
      and no rejection banner fires for the folder itself.
- [ ] **Non-video rejection, empty queue** — with no jobs in the queue, drop a
      `.png` (or other non-video file). Expected: nothing is added to the queue,
      and the orange banner "Images & PDFs coming soon — v1 is all about video."
      appears.
- [ ] **Non-video rejection, non-empty queue** — with at least one video already
      queued/compressing, drop a `.png`. Expected: the existing queue is
      undisturbed, the same rejection banner appears (it must still show even
      though the empty-state placeholder isn't visible).
- [ ] **Mixed drop** — drop a video and a `.png` together in one gesture.
      Expected: the video is accepted and queued, the `.png` is silently
      skipped, and NO rejection banner appears. (Deliberate rule: the banner
      only appears when *nothing* in the drop was usable — if at least one
      video was accepted, the drop counts as a success and stays silent.)

## 2. Destination dock

- [ ] All five cards render with correct icon, title, and subtitle (Discord
      "≤25MB", Email "≤25MB", YouTube "Quality", Web/Social "1080p", Custom
      "Your rules").
- [ ] Clicking a card (no drag) selects it — highlight moves, VoiceOver label
      changes to include ", selected".
- [ ] **Preset persists across relaunch** — select a non-default card (e.g.
      YouTube), quit the app fully (Cmd-Q), relaunch. Expected: YouTube is still
      the selected/highlighted card, and a global drop immediately after launch
      uses the YouTube preset.

## 3. File rows / shrink-meter bars

- [ ] **Shrink-bar animation during a real encode** — queue a large real video
      (not an instant no-op) and watch the row while it's `running`. Expected:
      the bar visibly and smoothly shrinks left-to-right as progress advances
      (not a static bar, not a jump-cut at completion), and the percentage text
      next to the row updates in step.
- [ ] **Thumbnails on real videos** — queue several different real video files.
      Expected: each row eventually shows an actual frame thumbnail (not the
      generic film-icon placeholder) once `ThumbnailLoader` resolves; different
      videos show visibly different thumbnails.
- [ ] Row shows correct "waiting" state (bar full, "Waiting…" subtitle) before
      its turn.
- [ ] On completion, row shows "input size → output size", the green "−NN%"
      savings figure, and a magnifying-glass button that reveals the output file
      selected in Finder when clicked.
- [ ] A file that's already small/optimized shows the "Already optimized"
      subtitle and is not needlessly recompressed.
- [ ] A failed job shows the failure message in red instead of a size line.

## 4. Batch header

- [ ] With an empty queue, header shows just "Compress" (no summary line, no
      Cancel/Clear buttons).
- [ ] **Batch summary with a real multi-file batch** — queue 4–5 real files of
      varying sizes and let them all finish. Expected: the header line reads
      "N files · saved X MB (−NN%)" and the saved bytes/percent match manual
      arithmetic on the actual input/output file sizes (spot-check with Finder
      "Get Info" or `ls -la`).
- [ ] **Cancel all mid-encode** — start a batch of several large files, click
      "Cancel all" while at least one job is `running`. Expected: the
      in-progress ffmpeg process is actually killed (check Activity Monitor —
      no orphaned `ffmpeg` process), queued jobs don't start, and rows reflect
      a cancelled/stopped state rather than silently finishing.
- [ ] "Clear" removes finished (done/failed) rows but does not disturb any job
      still queued or running.

## 5. Advanced panel — each option changes real ffmpeg output

Toggle the panel open (slider icon in the header). For every option below,
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
- [ ] **Resolution → Preset default**: leaving this unset lets the selected dock
      preset's own resolution rule apply (e.g. Web/Social's 1080p) rather than
      forcing a different cap.
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

## 6. Output handling / engine safety

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

## 7. Licensing / trial

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

## 8. HEVC legacy migration

- [ ] **Migration for a user upgrading with legacy `useHEVC=true`** — simulate
      a pre-redesign install by setting `defaults write <bundle-id> useHEVC -bool true`
      and leaving `containerRaw` unset (or `mp4`), then launch the redesigned
      build. Expected: the one-time migration folds this into
      `containerRaw = "mp4-hevc"`, the Format picker shows "MP4 · HEVC"
      selected on first launch, and this migration does not re-fire (and does
      not fight a user who deliberately picks MP4 · H.264 afterward) on
      subsequent launches.

## 9. Sparkle updates

- [ ] App checks for updates on schedule / via manual "Check for Updates…" and
      the appcast reflects the current shipped version.
- [ ] Update flow downloads, verifies signature, and installs without manual
      Gatekeeper workarounds.
- [ ] **Real 1.0.0 → 1.0.1 upgrade via a local appcast** — serve `Site/` locally
      (e.g. `python3 -m http.server` from `Site/`), point a locally-built
      1.0.0 install's `SUFeedURL` at it, then bump both `MARKETING_VERSION`
      and `CURRENT_PROJECT_VERSION`/`sparkle:version` to a 1.0.1 build and
      re-serve the updated appcast. Confirm Sparkle detects, downloads,
      verifies, and installs the update, and that About shows 1.0.1 afterward.

## 10. Cross-cutting persistence (relaunch)

Change every setting below in one session, fully quit (Cmd-Q), relaunch, and
confirm each one is exactly as left:

- [ ] Selected dock preset
- [ ] Format (H.264 / HEVC / MOV)
- [ ] Resolution cap
- [ ] Target size MB text
- [ ] Remove audio toggle
- [ ] Output folder mode (next-to-original vs custom) and the stored custom
      path
- [ ] Filename suffix text
- [ ] Move-originals-to-Trash toggle
- [ ] GIF mode toggle, fps, and width steppers

---

## Pass criteria

Every box above checked with the *actual* observed result matching the
*expected* result, on a real macOS machine, with real (not mocked) ffmpeg
encodes and a real Finder/Trash. `swift test` and the Release build passing is
a prerequisite, not a substitute, for this pass.
