## 2026-11-06 — Codex — XF-T36 notch opening behavior (direct owner request)

Branch: `agent/codex-XF-T36`, based on `a48e274`. Spec: `docs/specs/XF-T36-notch-opening-page.md`. Notion search found no XF-T36 task; this is recorded as a direct-request handoff, not as a claimed Queue task.

Implemented a separate deliberate-open rule (`notch.clickOpens`) in addition to the existing hover rule. Users can choose any visible fixed page, last-used page, or current activity; unknown settings and hidden pages fall back safely. Activity priority is waiting agent → playing track → held files → Clipboard. Explicit page routes still take precedence. Default is Files, preserving existing XFinder behavior. Added a Settings picker and 4 L10n entries. Updated the 28-group Notch/Dynamic Island comparison and roadmap.

| Check | Result |
|:--|:--|
| `swift test --package-path Tests --filter 'NotchHoverOpenTests|FeatureKeyDefaultsTests'` | 17 tests, 0 failures (includes final explicit-destination test) |
| `XF_OUT=/tmp/xfinder-t36-notch-build sh scripts/build-and-check.sh` | `** BUILD SUCCEEDED **`, arm64; isolated output, not installed |
| `plutil -lint XFinder.xcodeproj/project.pbxproj` | OK (no project file added) |
| L10n coverage / duplicates / literal / sidebar / gesture / interpolation / UI token audits | All zero problems; coverage 3785 entries |
| `git diff --check` | OK |
| `sh scripts/gate-all.sh` | RED only because `AgentCodexTests.testTheShippedHookTagsCodexAndDropsAnswersAndToolOutput` expects no ancestor named `codex`; same environment-sensitive failure seen in the preceding gate attempt. Build passed; 2909 tests, 1 failure. Do not repeat a third time. Full stdout: `/var/folders/xq/xzqwntyx0yx4stl6d6x3t7h00000gp/T/xfinder-gate.MwtW7w` |
| Live behavior | NOT VERIFIED; no install or launch |

Remaining core notch gaps for Claude to review: display-target policy, fullscreen visibility policy, gesture-zone preview, robust return-to-origin/child-popover focus and activity priority/history. The 28-group coverage file records other feature-family gaps. Build/gate review and any live UI validation remain with Claude.

CHỜ REVIEW (nhánh `agent/codex-XF-T36`).

# XF-T36 — Notch deliberate-open page rule

## Goal
Bring the notch's deliberate open action into line with the supplied Notch/Dynamic Island specification. Users can choose a fixed visible page, the last page they used, or the page most relevant to current activity.

## Files
- `XFinder/Core/Notch/NotchHoverOpen.swift` — pure open-page policy and routing rules.
- `XFinder/Core/Notch/NotchSurfaceController.swift` — read the preference for generic open intents.
- `XFinder/Views/Detail/NotchInterfaceDetailView.swift` — user-facing preference.
- `XFinder/Resources/L10n.strings.json` — localized setting copy.
- `Tests/XFinderLogicTests/NotchHoverOpenTests.swift` and `FeatureKeyDefaultsTests.swift` — behavior/default coverage.
- `docs/MFINDER_XFINDER_NOTCH_COVERAGE.md`, `MFINDER_XFINDER_ROADMAP.md`, and `AGENT_WORKLOG.md` — audit and handoff.

## Scope
- Keep hover behavior (`notch.hoverOpens`) independent and unchanged.
- Add `notch.clickOpens`, defaulting to `files` to preserve existing XFinder behavior.
- Apply the rule only when `reveal()` is called without an explicit page. Explicit page requests (page button, URL route, agent/media wing) must keep their destination.
- Fixed hidden pages resolve to the first visible page. Last-page falls back to the first visible page. Activity priority: agent waiting for the user, playing track, non-empty file tray, then Clipboard; hidden candidates are skipped. If no pages are configured, use `NotchPages`' existing non-empty default.
- Add a dedicated Settings picker with localized labels and explanatory text.

## Out of scope
Display targeting, fullscreen visibility policy, simulated-notch geometry, gestures and activity presentation priority. These need separate runtime/device validation and are not changed by this task.

## Failure/recovery cases
- Unknown stored setting: parse as `files`.
- Requested fixed page hidden: open first visible page.
- Last page unavailable or hidden: open first visible page.
- Activity candidate hidden: continue to the next candidate; if none applies, use Clipboard or first visible page.
- Explicit destination supplied: preserve that page even when click preference differs.
- Explicit destination is hidden: keep the existing first-visible-page fallback.
- Notch disabled: existing controller behavior remains authoritative; settings remain saved.

## Acceptance
- Unit tests cover defaults, parsing, fixed-page selection, hidden-page fallback, last-page fallback, activity priority and hidden candidates.
- UI picker labels all seven existing pages plus last-used and activity policies.
- Feature-key default audit confirms the Settings default and runtime reader agree.
- Localization coverage/duplicate checks pass.
- No live display/fullscreen behavior is claimed as verified.
