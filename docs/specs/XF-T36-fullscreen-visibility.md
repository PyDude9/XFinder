# XF-T36B — Notch visibility in fullscreen apps

## Goal
Add the fullscreen visibility choice requested by the notch specification while keeping active user actions reachable and avoiding a guessed fullscreen state.

## Files
- `XFinder/Core/Notch/NotchFullscreenRules.swift` — pure policy and conservative display-frame matching.
- `XFinder/Core/Notch/NotchSurfaceController.swift` — inspect the frontmost app's on-screen window on the notch display and react to app/Space/display notifications.
- `XFinder/Views/Detail/NotchInterfaceDetailView.swift` — localized Settings picker.
- `XFinder/Resources/L10n.strings.json` and `scripts/add-xf-t36-fullscreen-l10n-entries.py` — add-only strings.
- `XFinder.xcodeproj/project.pbxproj` and `Tests/XFinderLogicTests/NotchFullscreenRules.swift` — register/source-link the new pure policy.
- `Tests/XFinderLogicTests/NotchFullscreenRulesTests.swift`, `FeatureKeyDefaultsTests.swift` — policy and default coverage.
- `docs/MFINDER_XFINDER_NOTCH_COVERAGE.md`, `docs/MFINDER_XFINDER_ROADMAP.md`, `docs/AGENT_WORKLOG.md` — update gap map and report.

## User behavior
- `show` (default): keep the existing notch behavior.
- `hideInFullscreen`: hide only when an on-screen layer-0 window owned by the frontmost app conservatively matches the display containing the notch.
- `hideForFullscreenMedia`: hide only when that same frontmost fullscreen window belongs to the app identified by a live, playing Now Playing snapshot with a matching PID.
- If the OS window list, display identity, frontmost PID, or media PID is unavailable, show the notch. This is a best-effort geometry check, not a claim of native fullscreen API certainty.
- Keep the notch visible while a NotchTask is running, an agent needs an explicit response, an agent/windowless composer is active, or a current activity has actionable buttons.
- Refresh visibility on app activation, active Space change, screen parameter change, and existing surface renders. No polling timer.
- The setting controls notch visibility only; it does not hide the notch from screenshots or change screen capture/privacy settings.

## Failure and recovery cases
- Unknown preference: parse as `show`.
- Window list unavailable or incomplete: show.
- Frontmost app has a large borderless window but its bounds do not match the target display: show.
- Display cannot be mapped to a CoreGraphics display ID: show.
- Fullscreen app is on another display: do not hide the notch on this display.
- Media is paused, its helper is not live, belongs to another PID, or has no PID: do not apply media-only hiding.
- User enters/leaves fullscreen without switching apps: refresh on active Space/display notifications; mouse activity also re-evaluates.
- Active task, approval, composer, or actionable activity: keep visible regardless of selected hide policy.
- Feature disabled: preserve preference, stop observers with the rest of the surface, and keep the surface hidden as before.

## Acceptance
- Pure tests cover all policy modes, unknown values, display-frame tolerance, mismatched PID, stale/paused media, missing inspection data, and visibility required by active actions.
- Feature-key test confirms Settings and controller defaults agree.
- Add-only localization, build, targeted tests, full gate, and `plutil -lint` pass.
- Live fullscreen transitions across displays and VoiceOver are explicitly unverified until checked in the installed app.

## Boss review 2026-11-07 (measured)
- Probe on the notched 1728×1117 built-in display (safe-area top 32), own window via `CGWindowListCopyWindowInfo`:
  windowed (218, 585, 400, 332); zoomed to `visibleFrame` (0, 33, 1728, 1022); native fullscreen (0, 33, 1728, 1084).
  A native fullscreen window sits **below the camera housing**, so the original whole-display match never fired on the
  notched screen — the only screen where the notch shows.
- The menu-bar window (`Window Server:Menubar`, layer 24) stays in the on-screen list in fullscreen: not a discriminator.
- `AXFullScreen` on the window: false windowed, false zoomed, true fullscreen (`AXIsProcessTrusted` = true in the probe).
- Rule now (`NotchFullscreenRules.isFullscreenFrame`): whole-display frame ⇒ fullscreen (zoomed windows never cover the
  menu bar); below-housing frame ⇒ fullscreen only with `AXFullScreen == true` (a Fill window with the Dock hidden has
  that frame); no AX answer (not trusted, or no reply within 0.25 s) ⇒ show.
- Also fixed: a surface the user opened (`expanded`: click, hotkey, URL) stays visible under any hide policy.
- Unverified: third-party fullscreen video (browser HTML5 fullscreen, players that opt into the housing area), external
  displays, Stage Manager.
