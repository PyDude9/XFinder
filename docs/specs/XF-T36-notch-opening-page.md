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
