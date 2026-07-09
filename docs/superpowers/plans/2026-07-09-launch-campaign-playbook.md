# 1-Month Launch Campaign Playbook

Companion to `2026-07-09-video-compressor-app.md` (the build plan). This is operational, not code — work through the checkboxes week by week. Budget: **$500 max** (allocated ~$450). Audience start: **zero**. Anchor: **Product Hunt launch, week 4 Tuesday**.

**Positioning line (iterate, don't bikeshed):**
> Your video, 90% smaller, ready for anywhere — Discord, email, YouTube — in one drag.

**Content rules for the whole month**
- Every post shows a real number: "480 MB → 32 MB" beats any adjective.
- One X post per day minimum (a screenshot of progress counts). 2–3 vertical clips/week to TikTok + Reels + Shorts (same clip, all three).
- Reply to every single comment for the entire month.
- Never post a feature without showing it working.

---

## Week 1 — Foundation (days 1–7)

- [ ] **Day 1:** Choose final product name. Check: domain available, no existing Mac app with the name, App Store + Google search clean, ideally the X/TikTok handles too. Buy domain (~$10, Cloudflare Registrar).
- [ ] **Day 1:** Create accounts: X, TikTok, Buttondown (free tier), Product Hunt (personal maker account — PH weights maker history; start engaging daily now, upvoting and commenting genuinely).
- [ ] **Day 1:** First build-in-public post on X: the problem, the plan, day count. Example: *"Discord's 25MB limit has personally cost me hours of re-exporting. So I'm building a Mac app that fixes it in one drag. Building it in public — day 1 of 30. 🧵"*
- [ ] **Day 2:** Global find/replace the codename in the repo (`project.yml`, Info.plist, landing page `<title>`/copy) per the build plan's Global Constraints. Attach the domain to the Cloudflare Pages site; set the real Buttondown embed URL in `Site/index.html`.
- [ ] **Day 2–3:** Landing page live with waitlist + "35% off at launch" incentive. Post it.
- [ ] **Day 3–7:** Daily X posts from build progress (the build plan's Tasks 1–5 all produce postable moments — the fetch script pulling FFmpeg, the first green test suite, the first compressed fixture).
- [ ] **Day 5:** First vertical clip: screen recording of *anything* compressing, raw and unpolished is fine. Caption pattern: "POV: your screen recording is 480MB and Discord says no." If the redesigned destination-dock UI is ready, prefer one of the two signature demo moments below over a generic recording.
- [ ] **Day 7:** Weekly recap thread on X (what shipped, what's next, waitlist count if ≥25).

**Exit criteria:** name + domain live, landing page collecting emails, 7 straight days of posts, first vertical clip out.

## Week 2 — Audience building (days 8–14)

- [ ] Every completed build task → a demo clip. **The two signature demo moments — the money shots for every short-form clip this month:** (1) **dropping a file onto the Discord dock card** and watching it pick up the ≤25MB preset in one drag (no menus, no settings dialog — the destination-dock IS the pitch), and (2) **the size bar visibly shrinking** in the file row while a real encode runs (the shrink-meter animating down is the single most legible "this app works" visual we have). Also keep target-size mode ("I typed 25 and it just… fits now") in rotation. Make all of these tight (under 20s, big text overlay, real file sizes).
- [ ] **Community seeding — give value first, self-promo later.** Spend 20 min/day answering "how do I make this video smaller" questions in: r/VideoEditing, r/NewTubers, r/Twitch, r/macapps, creator Discords you already use. Recommend existing tools honestly (yes, including HandBrake and Compresto). Mention your app only where rules allow and it's genuinely relevant. You're building the account standing you'll need at launch.
- [ ] **Day 10:** Update landing page with real before/after numbers from actual builds.
- [ ] **Day 12:** Post an honest comparison: your app vs HandBrake on the same file (speed, size, clicks). Fair comparisons get shared; hit pieces don't.
- [ ] **Day 14:** Weekly recap. Checkpoint: **waitlist ≥ 100.** If under 50, diagnose before week 3: is the demo clip weak (most likely), or is distribution weak? Double down on the single best-performing clip format.

**Exit criteria:** waitlist ≥100, at least one clip with meaningful reach (>5k views on any platform), Reddit/Discord accounts with real comment history.

## Week 3 — Beta & proof (days 15–21)

- [ ] **Day 15:** Lemon Squeezy store setup: product, $29 price, $19 launch-discount code (`LAUNCH35`), license keys enabled. Generate a test key and run one real end-to-end activation in the app (build plan Task 10 Step 6).
- [ ] **Day 15:** Email waitlist: "Want the beta?" Send a TestFlight-less direct DMG link (notarized dev build) to repliers. Ask two things only: "what broke?" and "would you pay $19 for this?"
- [ ] **Day 16–20:** Fix beta-reported bugs publicly ("you reported, I fixed" posts perform well and signal responsiveness).
- [ ] **Day 18:** Collect testimonials: ask the 5–10 most enthusiastic beta users for one quotable sentence + permission to use name/handle. Put the best three on the landing page.
- [ ] **Day 18–19:** Prepare ALL Product Hunt assets:
  - Gallery: 5–6 images (hero shot, before/after numbers, preset picker, GIF mode, pricing).
  - 60-second demo video: hook in the first 3 seconds (the file-size number), one full drag→done flow, end on price.
  - Tagline (≤60 chars): e.g. "Make any video fit Discord, email, or anywhere else".
  - Maker's first comment: the personal story (the problem, why existing tools annoyed you, what's different, launch discount). Write it now, not at midnight.
- [ ] **Day 19:** Book the newsletter sponsorship (~$300) for launch week. Pick by audience fit — a Mac-apps newsletter (e.g. MacMenuBar-style roundups) or a creator-economy newsletter. Confirm the send date lands **on or 1 day after** PH launch day.
- [ ] **Day 20:** Schedule the launch: PH launch set for Tuesday 12:01 AM PT. Line up 5–10 friends/beta users who genuinely use the product to be awake for early comments (PH penalizes vote-begging; asking real users to share honest feedback is fine).
- [ ] **Day 21:** Freeze: `Scripts/release.sh 1.0.0`, final notarized DMG, `grep -r REPLACE-AT-LAUNCH` returns nothing, appcast live, checkout link tested with a real card, refund policy page up. Weekly recap post. Checkpoint: **waitlist ≥ 300.**
  - [ ] FFmpeg GPL source links live on the site (source-offer obligation for the bundled GPL build).

**Exit criteria:** shippable 1.0.0 DMG, working checkout, ≥3 testimonials on site, all PH assets done, newsletter booked.

## Week 4 — Launch (days 22–30)

- [ ] **Monday:** Final smoke test on a clean macOS account. Queue the waitlist launch email in Buttondown (send: Tuesday 7 AM PT; content: launch link, `LAUNCH35` code, ask for a PH comment if they use the app). Sleep early.
- [ ] **Tuesday — LAUNCH DAY:**
  - 12:01 AM PT: PH listing live. Maker comment posted immediately.
  - 7:00 AM PT: waitlist email goes out.
  - Morning: X launch thread (best demo clip + personal story + PH link), TikTok/Reels/Shorts launch clip.
  - All day: reply to every PH comment within minutes. This is the whole day's job.
- [ ] **Wednesday:** Show HN post — title format "Show HN: I built a Mac app that makes any video fit Discord's size limit". First comment: technical details (FFmpeg + VideoToolbox, why native, what was hard). HN respects engineering honesty and punishes marketing speak.
- [ ] **Wednesday–Thursday:** Reddit launch posts, only in communities where you built standing (week 2), following each sub's self-promo rules. Personal-story framing, launch discount in comments not title.
- [ ] **Thursday–Friday:** Newsletter sponsorship lands. Run the $100 X ads test: promote the single best organic clip, target lookalikes of video-editor/streamer interests. Kill it if CPM is bad — it's a test, not a bet.
- [ ] **Days 25–30:** Momentum week: milestone posts with real numbers ("214 downloads, 31 licenses, day 3"), fix reported bugs same-day and say so, ship ONE small most-requested feature before day 30 to signal velocity. Personal thank-you email to every buyer (it's <100 people; it's doable and they'll remember).
- [ ] **Day 30:** Retro post (transparent numbers: waitlist, PH rank, sales, revenue). Transparent retros routinely outperform launch posts — it's also the seed content for month 2.

## Success metrics (from spec)

| Metric | Target |
|---|---|
| Waitlist before launch | 300+ |
| Product Hunt rank | Top-10 of the day (stretch: top-5) |
| Licenses, launch week | 50 |
| Social followers, day 30 | 500+ |

## Budget tracker

| Item | Budgeted | Actual |
|---|---|---|
| Domain + misc tools | $50 | |
| Newsletter sponsorship (launch week) | $300 | |
| X ads test | $100 | |
| **Total** | **$450 / $500** | |

## If things slip

- **Build behind at day 18:** cut video→GIF from 1.0 (it's the designated slip feature in the build plan). Do not move launch day — a smaller launch on schedule beats a bigger one late, because the newsletter is booked and momentum decays.
- **Waitlist under 100 at day 21:** launch anyway, but shift the $100 X-ads budget to a second, cheaper newsletter or a micro-influencer shoutout to compensate for the small email list.
- **PH flops (outside top 20):** the retro post and HN are independent shots on goal; the waitlist and Reddit standing don't evaporate. Month 2 = images/PDF features + the audience you now actually have.
