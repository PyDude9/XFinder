# OneNotch (Huy Tran) — Web Research Report

Bundle id `com.huyt.OneNotch`, v2.0.5 build 67, site tryonenotch.com, appcast
`https://releases.tryonenotch.com/appcast.xml`, support support@tryonenotch.com.
The app's own UI claims "OneNotch is open-source" with a GitHub link in its About tab.
**This claim could not be corroborated anywhere on the public web — see §2.**

---

## 1. Official website — features, pricing, requirements

Source: https://www.tryonenotch.com/ (fetched 2026-10-13; note the bare `tryonenotch.com`
without `www` 404s or fails URL validation — use the `www` host).

### Feature list, grouped as the site groups them

**Clipboard** ("Everything you copy. Right in your notch.")
- Search text, links, images, code; organize into Boards; one-click paste
- Pin items to boards with number-shortcut (⌘1–9 style) pasting
- Filtered search via `@image`, `@link`, `@text` tokens
- **Copy Stack** — double-press ⌘ to collect a stack, ⌘V pastes every item in order
- AI-agent clipboard search via **MCP**, works with Claude Code, Cursor, Codex, described
  as running "locally on your Mac"
- Right-click actions: Go to Source, Transform, Annotate, Copy Text from Image (OCR)

**Smart Selection**
- Inline translation of selected text
- Currency conversion, weight/time conversions "in place"

**Small tasks from the notch** (capture/replay tools)
- Capture & markup: arrows, numbers, magnify, measure, erase, canvas extend, drag image out
- Drop files (Smart File Actions per changelog: resize/convert/compress/remove background/
  OCR/video→MP4/audio extraction/PDF merge/unzip/AirDrop)
- Arrange windows (Snap Zones)

**With or without a notch**
- Notch layouts, and a **Pill mode** for external/non-notch displays — shows music, AirPods,
  volume, agent updates, low-battery alerts

**Calendar and timers**
- Calendar at a glance (events/reminders; tidy completed/all-day items)
- Timers: Task, Reminder, Break types; a Focus Timer that persists even when the notch closed

**AI Agents**
- Live stream of agent activity, permission/approval requests, task details, quota/cost/token
  usage, completion status — for Claude Code and Codex running in a terminal (not desktop apps)

**Full feature list ("Compact outside. Complete inside.")**
Clipboard history, Copy Stack, Locked boards (stated as AES-GCM encryption), iCloud sync,
Export & import (`.onenotchclip` format), Lyrics (word-synced, Apple Music/NetEase), OCR,
AI translation, Quick conversions, Window layouts, Pill mode, Customization.

Source: https://www.tryonenotch.com/

### Pricing

| Tier | Price | Included |
|:--|:--|:--|
| **Free** | $0/forever | 50 clipboard items (24 h retention) + 1 Pin board; screenshot & markup; OCR; capture history; music/lyrics/Live Activities; AI-agent following/approval (Claude Code & Codex); Quick Translate (⌘⇧G); Calendar — today only |
| **Pro** | "~~$9.99~~ $6.99 one-time" with code `LAUNCH30`, stated to apply "until 19 Nov 2026" | 1,000 clipboard items (indefinite retention if desired); 20 boards × 200 items; iCloud sync across Macs; Pro capture tools (scrolling capture, background removal, auto-redact, translate-in-image); Calendar for any day; full dictionary (phonetics, unlimited pronunciation, replace selection); more window layouts (quarters, thirds, Focus); covers **2 Macs** |
| **Supporter** | $24.99 one-time | Everything in Pro + **5 Macs** + "Supporter badge" |

Refund policy: "within 7 days of purchase," via email to support.
Purchase page (LemonSqueezy) confirms the $9.99–$24.99 range but doesn't itemize further:
https://onenotch.lemonsqueezy.com/

Sources: https://www.tryonenotch.com/ , https://onenotch.lemonsqueezy.com/

### macOS requirement

**macOS 15 (Sequoia) or later, Apple Silicon only** — stated plainly on the homepage and
repeated in every third-party summary found ("OneNotch supports Apple silicon Macs running
macOS 15 or later"). No Intel support, no support for macOS 13/14.

Sources: https://www.tryonenotch.com/ ; corroborated by https://notchy.dev/alternatives/onenotch/
and https://notchy.dev/best-mac-notch-apps/

### Author

"Created in Vietnam by Huy Tran." Site footer/signature: "Built with 💙 by huytran2706."
No separate company name beyond the OneNotch product itself.

Source: https://www.tryonenotch.com/ (via search snippet) and page fetch.

---

## 2. GitHub repository — **NOT FOUND**

**Could not find a GitHub repository for OneNotch anywhere on the public web**, despite:
- Direct fetch of the OneNotch homepage (www.tryonenotch.com) — no GitHub link in nav,
  footer, body content, or JSON-LD structured data.
- A fetch attempt at a plausible `/about` path (https://tryonenotch.com/about) returned
  HTTP 404.
- Multiple targeted web searches: `OneNotch Huy Tran GitHub repository open source`,
  `site:github.com OneNotch huytran OR "com.huyt.OneNotch"`, `"OneNotch" "open source"
  github.com`, `huytran2706 twitter OR x.com`. None surfaced a matching repo. The only
  GitHub hit for the username variant was an empty, inactive gist profile
  (https://gist.github.com/huytran46, 0 followers, 0 public gists, unrelated to this app).
- Independent third-party roundup articles **explicitly state OneNotch is proprietary/closed
  source**, in direct contradiction of the in-app claim:
  - "it is not open source" — https://notchy.dev/alternatives/onenotch/
  - OneNotch listed as NOT open source, contrasted with Boring Notch and Atoll which "are
    open source" — found via search snippet of https://www.tryonenotch.com/blog/best-free-notch-apps-for-mac
    (ironically the OneNotch's *own* blog post draws this distinction for competitors, while
    describing OneNotch itself without an open-source label)
  - Ranking page lists Boring Notch's pro as "free and open-source," "active GitHub project,"
    with no equivalent claim for OneNotch — https://notchy.dev/best-mac-notch-apps/

**Conclusion: the in-app "OneNotch is open-source" string and its About-tab GitHub link
could not be verified. No public repository, commit history, license, star count, or
language breakdown exists to report.** This is a direct discrepancy worth flagging back to
whoever is auditing/comparing against it — either the link points to a private/placeholder
repo, a repo that is unindexed or very obscure, or the claim is simply inaccurate marketing
copy carried over from a template.

LICENSE / stars / last commit / language: **could not find** (no repo located).

---

## 3. Changelog / release notes for 2.0.x

Source for full version history: https://www.tryonenotch.com/changelog (fetched 2026-10-13)
Source for XML-native structured appcast entries: https://releases.tryonenotch.com/appcast.xml

### Feature explanations (author's own words, aggregated across 2.0.x notes)

- **Smart Text / Smart Select** — in-place recognition over selected/copied text: dates,
  prices/currency, measurements/units, colors; triggers inline translation and unit/currency
  conversion without leaving the current app. Described as "redesigned" in 2.0.5 and
  "smarter... date/translation handling" in 2.0.4.
- **Pick Color** (new in 2.0.5, shortcut ⇧⌘1) — an on-screen color picker with HEX/RGB/HSL/HSB
  format support, surfaced from the notch.
- **AI agents / Claude Code / Codex integration** — tracks agent sessions running **in a
  terminal** (explicitly not desktop apps per the Alcove comparison post), showing live
  step/model/tool/working-folder/git-branch details (per the 2.0.0 note: "Live AI agent
  previews now show the model, current step, tools used, working folder and Git branch"),
  cost/token/quota usage, and lets the user approve/deny agent actions from the notch.
  2.0.5 fixed status-accuracy bugs (Codex showing "finished" while subagents still ran;
  Claude leaving stale approval prompts).
- **Mirror** — **could not find** any OneNotch feature, changelog entry, or marketing copy
  using the word "mirror" (e.g. webcam/display mirroring). Not mentioned anywhere found in
  this research. (Note: a *different* app, NotchNest, has a "camera mirror" feature — not
  to be confused with OneNotch.)
- **Lock screen** — **no explicit "lock screen" feature is advertised on tryonenotch.com or
  in the appcast for OneNotch itself.** The only "lock screen" reference found is in
  OneNotch's own comparison blog post about a *competitor*: "Alcove... one of few apps
  extending to the Mac lock screen" with "lock-screen widget support." OneNotch is not
  described as having lock-screen integration anywhere found. (Flagging as a gap/negative
  finding, not a confirmed absence — could not find enough coverage to be fully certain.)
- **HUD replacement** — part of "Live Activities": described (in the Alcove comparison, which
  describes OneNotch's own features for contrast) as replacing "standard macOS HUDs (volume,
  brightness)... with notch-centered" indicators; OneNotch's own site lists Live Activities
  covering volume/brightness, charging/battery, Bluetooth, Caps Lock, no-internet, and
  calendar-meeting alerts with one-click Join.
- **Glance** — **could not find** any feature literally named "Glance" in OneNotch's own
  materials. The closest matching language is the generic tagline "Calendar at a glance."
  No feature called "Glance" as a proper noun was found.
- **Pill (mode)** — confirmed, introduced in v2.0.0 "Major 2.0 release bringing 'Pill mode'
  support to notch-less Macs" (appcast). Renders a pill-shaped HUD-equivalent on external
  displays or Macs without a physical notch, showing music, AirPods, volume, agent updates,
  low-battery alerts (per homepage copy).
- **File Tray** — OneNotch does **not** have a persistent file shelf/tray by design; multiple
  sources state this explicitly: "No persistent file shelf — the article concedes, 'if a
  holding area is what you want, NotchNook is still the better fit'"
  (https://www.tryonenotch.com/blog/onenotch-vs-notchnook, OneNotch's own post). Instead
  OneNotch offers "Smart File Actions" (since v2.0): act on a dropped file immediately
  (resize/convert/compress/background-removal/OCR/video-to-MP4/PDF merge/unzip/AirDrop)
  rather than holding it in a shelf. "File Tray" as a named feature belongs to the
  competitor **NotchNook**, not OneNotch.
- **Snap Zones** — window-tiling via dragging to/near the notch; introduced v2.0.0, expanded
  in v2.0.1 with "10 selectable Snap Zones layouts (3 slots Free, 6 Pro)."
- **Clipboard boards / board lock** — "Boards" organize saved clips with shortcuts (e.g. ⌘1);
  "Locked boards" introduced in v2.0.0 as "passcode-locked Clipboard Boards," and the full
  feature list states they use "AES-GCM encryption." (Compare with XFinder's own D4 Secure
  Enclave/HPKE board-lock design — OneNotch's is passcode-based per the marketing copy, not
  described as hardware-backed/biometric anywhere found.)
- **MCP for agents** — "Clipboard MCP" rolled out incrementally:
  - v2.0.1 (build 55, 2026-10-03): "Clipboard MCP integration for Claude Code, Cursor, and
    Codex" — lets those tools interact with clipboard data "under user permission," explicitly
    excluding password managers and locked Boards.
  - v2.0.2 (build 57, 2026-10-04): MCP extended so agents can "list/read Boards and let agents
    pin/unpin items" (locked Boards still excluded).
  No version/build names an actual tool schema or transport in the public changelog text.

### Last ~8 releases (dates + summaries) — from the appcast (authoritative, dated)

1. **2.0.5 (67)** — Mon 12 Oct 2026. "Smarter clipboard, Pick Color and importing from other
   apps." New: imports from Paste/PastePal/PasteNow/Maccy/CopyClip; video previews in
   clipboard; Pick Color tool (⇧⌘1, HEX/RGB/HSL/HSB); Apple Music next-track preview; new AI
   agent loading indicators. Improved: faster/more compact OCR, "Copy and close"/"Paste and
   close," better image-format handling, selective history deletion (15 min/1h/24h/7 days),
   redesigned Smart Select, adjustable Calendar height, haptic feedback on page swipes,
   customizable media controls, more Pomodoro sounds, improved onboarding. Fixed: Codex/Claude
   agent status accuracy, Low Power Mode crash, Mission Control conflict with file drag,
   duplicate app instances on restart, screenshot/OCR/Pick Color reliability.
2. **2.0.4 (62)** — Thu 08 Oct 2026. "Multi-item drag and keyboard page switching." New:
   multi-select/drag clipboard items (⌘-click, ⇧-click); Tab/Shift-Tab page switching; "Edges
   open their own page" option; new sort options (By App, Name A–Z); renamable Pin Board;
   Floating Panel Preview toggle. Improved: Smart Select date/translation handling, clipboard
   preview, redesigned prompts, Copy Stack refinements, smoother drag-and-drop/screenshot
   animation, consolidated feedback/support flow. Fixed: freezing during copy/paste and track
   changes, frozen appearance after update checks, video/tab playback bugs in Chrome, link
   preview metadata loss, dark-panel text contrast, battery-ring label centering, translation
   fix in 15 languages.
3. **2.0.3 (59)** — Mon 05 Oct 2026. New: click music artwork to open the source browser tab.
   Improved: streamlined screenshot shortcuts, Dock-icon persistence during onboarding,
   Spotlight/Finder reopening behavior, **menu bar icon handling on macOS 27** (changelog page
   states menu-bar icon hiding is disabled on macOS 27 "for compatibility reasons" — i.e. they
   hit the same macOS 27 menu-bar wall XFinder's own CLAUDE.md documents at length). Fixed:
   external-display-disconnect notch bug, macOS 26.0.0 crashes, notch spacing on taller-notch
   displays, Facebook/YouTube artwork mix-up, lyrics tint consistency, Screenshot menu
   interaction issues.
4. **2.0.2 (57)** — Sun 04 Oct 2026. New: Clipboard MCP can list/read Boards and let agents
   pin/unpin items; horizontal swipe over notch header for page switching. Improved: compact
   drag-chip UI, new Codex mascot animation, removed intro animation, improved lyrics
   player-switching behavior. Fixed: Board interaction crash, freezes during
   screenshot/notification-sound playback, premature "Task done" notifications, music-source
   selection logic, lyrics search status, AI Usage layout near the physical notch.
5. **2.0.1 (55)** — Sat 03 Oct 2026. New: Clipboard MCP integration for Claude Code, Cursor,
   and Codex; 10 selectable Snap Zones layouts (3 Free, 6 Pro). Improved: clipboard card
   preview, smoother screenshot annotation/zoom, player-switching via track title/artist
   click, ~23 MB smaller download. Fixed: first-OCR freeze, Photos-app copy format issue,
   false "Task done" notifications during Claude sessions, layout conflicts near the physical
   notch, floating panel dragging on macOS 27 (regression fix).
6. **2.0.0 (52)** — Wed 30 Sep 2026. Major release: "Pill mode" for notch-less Macs. New:
   passcode-locked Clipboard Boards, drag-and-drop file processing (resize/convert/
   background-removal/PDF-merge/ZIP-extraction), Snap Zones, persistent Focus Timer, Smart
   Select for prices/measurements/dates/colors, new Supporter plan, Reminders creation,
   clipboard preview panel, in-app feedback with screenshots. Improved: rebuilt clipboard
   grid, expanded Pro limits (20 boards × 200 items, 1,000 history items), enlarged
   item/zoom/OCR viewing in Library, detailed AI Usage stats, live agent previews, synced
   lyrics highlighting, cross-page music controls, enhanced annotation tools, currency
   conversion caching, customizable default notch page.
7. **2.0.0 (51)** — Wed 30 Sep 2026, ~1 hour earlier than build 52. Same feature set/notes
   (same release, prior build number).
8. **1.2.2 (40)** — Thu 03 Sep 2026. New: dedicated Calendar notch page (month grid, event
   indicators, create/edit/delete events), customizable notch toolbar, Pin Board creation from
   notch, swipe-to-skip-track gesture. Fixed: Clipboard Library history cap removed (was
   capped at 80 items); "clearing history" moved to Settings. Improved: full-screen panel
   visibility (**"panels remain available above other apps in full-screen mode" — a window-
   level/layering claim**), clearer AI Agent setup states, usage-data sharing toggle, lyrics/
   notch/Calendar/Screenshot permission fixes, reduced memory usage, smaller package size.

Sources: https://releases.tryonenotch.com/appcast.xml and https://www.tryonenotch.com/changelog
(the changelog page extends further back to v1.0.0, 27 Jun 2026, if earlier history is needed;
full table reproduced in the fetch above, omitted here per the "~5 releases" scope request).

---

## 4. Appcast XML — last 5 releases (dates + summaries)

(Duplicated from §3 for direct appcast traceability; this IS the appcast content.)

| Version (build) | Date | One-line summary (title/summary field) |
|:--|:--|:--|
| 2.0.5 (67) | Mon, 12 Oct 2026 23:12:47 +0700 | "2.0.5: Smarter clipboard, Pick Color and importing from other apps" |
| 2.0.4 (62) | Thu, 08 Oct 2026 00:03:37 +0700 | "2.0.4: Multi-item drag and keyboard page switching" |
| 2.0.3 (59) | Mon, 05 Oct 2026 21:44:25 +0700 | (no short summary field fetched; see full notes §3) |
| 2.0.2 (57) | Sun, 04 Oct 2026 19:12:00 +0700 | (no short summary field fetched; see full notes §3) |
| 2.0.1 (55) | Sat, 03 Oct 2026 00:33:54 +0700 | (no short summary field fetched; see full notes §3) |

Full per-release New/Improved/Fixed bullet breakdowns are in §3 above (identical source).
Source: https://releases.tryonenotch.com/appcast.xml

---

## 5. Public technical write-ups by the author — **largely NOT FOUND**

Searched extensively for: author blog posts, Reddit threads, X/Twitter posts, Hacker News
submissions, under the author's name/handle (Huy Tran, huytran2706, huytran46) and under
"OneNotch" combined with technical terms (window level, Liquid Glass, MediaRemote adapter,
lock-screen SkyLight, MCP unix socket, MBAssessmentMode).

**Found:**
- The app's **own blog** (hosted at tryonenotch.com/blog/) carries several
  comparison/marketing posts (vs Alcove, vs NotchNook, vs TopNotch, "best free notch apps",
  "best Mac notch apps 2026") that are vendor-authored, not independent technical write-ups.
  These contain only high-level performance claims, not implementation details:
  - "OneNotch was profiled with Apple's own tools [powermetrics is named in one post] ...
    roughly 0% CPU at idle and under 1% while playing music, with an Energy Impact in the
    single digits" — per one search-snippet summary of tryonenotch.com copy.
  - A separate comparison post (vs NotchNook) instead states "Roughly 7–10% CPU idle" and
    "about 200MB of memory," attributed to "July testing" — **this directly contradicts the
    ~0%-idle claim found elsewhere on the same domain.** Flagging as an internal
    inconsistency in the vendor's own marketing between different blog posts/pages, not
    resolved by any independent measurement found.
    Sources: https://www.tryonenotch.com/blog/onenotch-vs-notchnook ,
    https://www.tryonenotch.com/blog/onenotch-vs-alcove , and homepage performance-claim
    search snippet.
  - No window-level, animation-engine specifics, Liquid Glass fallback behavior, MediaRemote
    adapter design, or lock-screen SkyLight technique is described in ANY of these posts
    beyond the single changelog line "panels remain available above other apps in full-screen
    mode" (v1.2.2) — which hints at a window-level choice but does not name an API.
- **No MCP transport/socket details found.** None of the OneNotch changelog entries,
  blog posts, or the homepage name a Unix socket path (e.g.
  `~/Library/Application Support/OneNotch/mcp.sock`), a tool-name list, or any JSON-RPC/
  stdio/socket transport mechanism. The feature is described only functionally ("Clipboard
  MCP... lets Claude Code, Cursor, and Codex interact with clipboard data under user
  permission").

**Could not find:**
- Any Reddit thread (r/macapps or otherwise) discussing OneNotch.
- Any Hacker News submission or comment thread about OneNotch.
- Any X/Twitter post by "huytran2706" or any other handle clearly tied to this author/app.
- Any independent developer blog post, conference talk, or write-up describing OneNotch's
  internals (by the author or by a third party).
- Any public disclosure of a MediaRemote adapter technique, a lock-screen SkyLight technique,
  or a Liquid Glass fallback strategy specifically for OneNotch.

This is a strikingly low public footprint for an app with 18 shipped versions since
2026-06-27 and daily-cadence releases in its 2.0.x line — all of its technical self-reporting
lives in its own changelog/appcast and marketing blog, with no corroborating or elaborating
external source located.

---

## 6. Independent reviews / comparisons

**No fully independent (non-vendor, non-competitor-vendor) review of OneNotch was found.**
Every comparison located is one of:
(a) OneNotch's own blog comparing itself to a competitor (promotional by definition), or
(b) a competitor's own "alternatives" page comparing itself favorably against OneNotch
    (equally promotional, in the opposite direction).

### (a) OneNotch's own comparison posts

**OneNotch vs NotchNook** — https://www.tryonenotch.com/blog/onenotch-vs-notchnook
- OneNotch claimed strengths: Copy Stack, Smart Boards, a "Cursor Panel" (clipboard summoned
  at the mouse), "Go to Source" tracking, 15 built-in text-transform tools, instant Google
  search of clipboard items; AI-agent tracking ("one of the few notch apps that shows live
  status for AI agents like Claude and Codex, and NotchNook is not one of them"); Smart File
  Actions since v2.0; Snap Zones; persistent Focus Timer; Pill mode; pricing ($9.99 lifetime
  or $6.99 w/ `LAUNCH30`, 2 Macs, "No subscriptions, no hidden fees").
- Conceded weaknesses: **no persistent file shelf** ("if a holding area is what you want,
  NotchNook is still the better fit"); Pro tier covers only 2 Macs vs NotchNook's 5.
- NotchNook's features per this post: File Tray (drag-and-drop holding shelf), built-in
  AirDrop drop box, a "Nook" dropdown (media controls, calendar events, webcam mirror),
  Shortcuts integration, timers/to-do list, "highly modular interface," "the longest-
  established paid notch app," $25 one-time (5 Macs) or $3/month (2 Macs) with a trial.
  NotchNook has no published performance data ("Not published; check Activity Monitor," per
  this same post).

**OneNotch vs Alcove** — https://www.tryonenotch.com/blog/onenotch-vs-alcove
- Alcove's claimed strengths (per OneNotch's own post, so a rare case of a vendor praising a
  competitor): Live Activities/widgets replacing "standard macOS HUDs (volume, brightness)...
  with sleek, notch-centered animations"; **lock-screen widget support** ("one of few apps
  extending to the Mac lock screen"); swipe gestures between active tasks; native Swift,
  "light/fast"; $14.99 one-time after a 72-hour trial, no free tier.
- OneNotch's claimed strengths in the same post: clipboard (Copy Stack, Boards, Cursor
  Panel); AI-agent integration (no MCP named explicitly here, just "status" tracking); Live
  Activities (volume/brightness HUD replacement, battery/Bluetooth/Caps-Lock/no-internet
  alerts, calendar Join button, persistent Focus Timer, Apple Music lyrics, **a lock-screen
  player** is listed here for OneNotch itself); File actions and Snap Zones (briefly).
  Performance: "roughly 7–10% CPU when idle," "about 200MB memory," "under 1% CPU" during
  music with the default waveform (profiled with `powermetrics`); opt-in live audio
  visualizer costs more, "6–9% CPU."

### (b) Competitor "alternatives" pages about OneNotch

**notchy.dev/alternatives/onenotch/** — https://notchy.dev/alternatives/onenotch/
- Summary: "a newer notch hub with clipboard boards, media controls with a visualiser, live
  activities, AI agent status, calendar and reminders, screenshot annotation with OCR,
  translation and a dictionary."
- Explicit criticism: **"it is not open source"**; **"does not keep a persistent file shelf"**;
  platform-exclusive to Apple Silicon + macOS 15 ("can't run on Intel Macs or pre-Sequoia
  systems," unlike Notchy's own macOS 13+ Intel+Apple-Silicon support); **Face Unlock** is
  called out as a feature "OneNotch doesn't list."
- Verdict given: "OneNotch is a capable, well-priced newcomer for Apple silicon on Sequoia."

**notchy.dev/best-mac-notch-apps/** (15-app ranked roundup) — https://notchy.dev/best-mac-notch-apps/
- **OneNotch ranked #14 of 15** (Notchy itself ranks the list and places itself #1 — treat
  the ranking as self-serving).
- Pros listed: "Clipboard boards and dictionary lookup"; "Low-cost lifetime Pro."
- Cons listed: "Requires macOS 15 and Apple silicon"; "Pro tier at $9.99."
- Ranked below Boring Notch (#4), Atoll (#5), and NotchNook (#3); no direct head-to-head
  prose vs those three is given beyond rank position — OneNotch is excluded from the page's
  detailed feature-comparison table (only Notchy, Alcove, NotchNook, Boring Notch,
  DynamicLake, and MediaMate are compared feature-by-feature there).
- Notable contrast drawn for *other* apps, implicitly highlighting what's absent from
  OneNotch's own listing: Boring Notch described as "free and open-source," "active GitHub
  project" — no such language is used for OneNotch anywhere on this page.

### What reviewers/vendors praise about OneNotch (aggregated)
- Clipboard manager depth (Copy Stack, Boards, Cursor Panel, text transforms, Go-to-Source).
- Being "the only" (or "one of the few") notch apps with live AI-coding-agent status
  (Claude Code / Codex) — called out favorably in every comparison found.
- Price positioning: $9.99 lifetime (or $6.99 promo) undercuts Alcove ($14.99) and NotchNook
  ($25 lifetime / $3-month).
- Generous free tier relative to some competitors (50 items/24h + full AI-agent tracking
  free).

### What reviewers/vendors criticize about OneNotch (aggregated)
- **Not open source** (despite the in-app claim — see §2).
- No persistent file shelf/tray (by design, per OneNotch's own admission).
- Narrowest platform support among compared apps: macOS 15+ and Apple Silicon only (no Intel,
  no macOS 13/14), stricter than Notchy, Boring Notch, Atoll, and NotchNook.
- No Face Unlock / lock-screen feature parity flagged (per notchy.dev) — though OneNotch's own
  Alcove-comparison post does claim "a lock-screen player" for itself, so this point is
  contested between sources, not settled.
- Self-reported idle CPU numbers are **inconsistent across the vendor's own pages** (near-0%
  on one page vs 7–10% on another) — no independent benchmark exists to resolve this.

---

## Summary of "could not find" items (explicit)

- GitHub repository URL, license (SPDX), star count, last commit date, language breakdown —
  **not found**; strong evidence (multiple independent sources) that OneNotch is actually
  closed-source, contradicting its own in-app "open-source" claim and About-tab GitHub link.
- Any feature literally named **"Mirror"** or **"Glance"** — not found in any OneNotch
  material surveyed.
- A confirmed, singular answer on whether OneNotch has lock-screen integration — sources
  disagree/are silent (OneNotch's Alcove post claims "a lock-screen player" for itself;
  notchy.dev calls out the *absence* of Face-Unlock/lock-screen-adjacent capability).
- Any author interview, blog post, or technical talk explaining HOW the notch UI, Liquid
  Glass fallback, MediaRemote adapter, lock-screen SkyLight technique, or MCP transport
  (unix socket path, tool names) are implemented — not found anywhere public.
- Any Reddit, Hacker News, or X/Twitter discussion thread about OneNotch — not found despite
  multiple query variants.
- Exact per-tier breakdown on the LemonSqueezy purchase page beyond the $9.99–$24.99 range
  (the page itself doesn't itemize; the homepage's pricing table was used instead).
