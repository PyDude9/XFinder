# XF-T34 — AppSwitcher keyboard and thumbnail responsiveness

Status: independently reviewed draft; awaiting owner decision. This file is not an implementation task until the owner accepts it and it is added to the Notion Queue — Ready.

## Goal

Make XFinder's existing window switcher predictable for quick `⌘Tab`, add configurable same-app window cycling with `⌘` + grave as the requested default, and reduce measured thumbnail wait without adding a second switcher or a duplicate enable switch.

## Current implementation observed

- `windowPreview.commandTabEnabled` already gates `CommandTabController`'s event tap. When OFF, the tap is torn down; when ON and Accessibility is granted, the switcher consumes `⌘Tab` / `⌘⇧Tab`.
- `WindowPreviewDetailView` already exposes that enable toggle and a `⌘Tab` / `⌥Tab` choice.
- While the switcher is active, keyCode 50 (grave) currently calls `toggleMode()` (one card per app ↔ one card per window), with Command still held. Therefore the new `⌘` + grave chord can only cycle same-app windows while the switcher is hidden; while it is visible, keyCode 50 keeps the current mode-toggle behavior.
- `WindowPreviewStore.fetchThumbnails()` already fetches asynchronously; `ScreenCaptureProvider` already has a two-second freshness window and a 24-entry LRU cache. Optimize only the measured cold path; do not add a second cache or capture provider.
- `CommandTabSwitcherView` has only its declaration in the repository and no references. Remove this dead duplicate renderer if the final branch-wide search still shows no use; the active surface remains `PreviewOverlayWindow`.

## Requirements

1. Preserve one enable preference: `windowPreview.commandTabEnabled`. Verify that a quick `⌘Tab` opens XFinder's switcher only when enabled, and that OFF passes the chord to macOS. Make the Settings copy clear about this behavior; do not add another Bool for the same behavior.
2. Add a configurable same-app window cycling shortcut, default `⌘` + grave, using the existing shortcut recorder/catalog conventions. It is subordinate to `windowPreview.commandTabEnabled`; OFF must pass the chord through. When the switcher is hidden, cycle the frontmost app's eligible windows in the order returned by the existing window-list provider, wrapping at either end; do not claim that order is front-to-back unless it is measured on the supported OS. Changing the binding must update registration without restarting XFinder. A missing first-run preference uses the default; an explicit user clear stores the reserved non-empty sentinel `disabled`; an empty stored string or malformed/unknown data is invalid and falls back to the documented default.
3. While the switcher is visible, keyCode 50 continues to toggle app/window mode regardless of the held Command modifier. Same-app cycling is not invoked from the visible switcher. The new chord must not fire while the user is typing into the switcher's search field or recording a shortcut in Settings.
4. Measure switcher-open-to-first-thumbnail latency before optimization. If needed, prefetch/cache captures without blocking the event tap or main actor; discard stale captures when window identity, app, screen, or feature state changes. Do not continuously capture while the switcher is closed.
5. Use at least 30 paired baseline/final samples for each cold and warm condition under the same display/window/permission setup. A shipped performance change must reduce cold p50 by at least 20% and cold p95 by at least 10%, without increasing warm p95 by more than 5% or causing capture at rest. If it misses those thresholds, revert the optimization and report that the speed target remains unmet.

## Failure cases

- Accessibility permission absent, revoked while enabled, or event tap creation/timeout failure: preserve macOS `⌘Tab`; show the existing truthful status and allow re-arming only while enabled.
- Feature OFF: no switcher or same-app chord interception; no thumbnail prefetch at rest.
- No eligible window, one window, minimized/hidden window, window closing during cycle, app quitting, or AX/window-server identity changing between listing and activation: no crash or activation of a stale/wrong window; wrap only when at least two eligible windows remain.
- Two apps or several windows share titles: identify windows by stable owner/window identity, not title alone.
- Same-app shortcut collides with another XFinder binding: show a localized conflict and do not silently steal another binding. The reserved non-empty `disabled` sentinel means explicitly cleared; a missing first-run key uses the default; an empty stored string or malformed/unknown value is invalid and falls back to the safe documented default.
- Bare grave, search typing, and shortcut recording: retain their existing meanings; do not treat text input as switcher commands.
- Screen Recording permission absent/revoked, window not capturable, capture returns nil, or stale capture completes after selection changes: keep the usable placeholder and never show a thumbnail for a different window.
- Rapid repeated `⌘Tab` / same-app cycling, display changes, or toggling the feature during a capture: coalesce/cancel obsolete work and leave no retained capture queue.

## Expected files and boundaries

Expected implementation touch points, subject to code review before edits:

- `XFinder/Core/CommandTabController.swift`
- `XFinder/Core/WindowPreview/WindowPreviewStore.swift`
- `XFinder/Core/WindowPreview/ScreenCaptureProvider.swift` and/or `XFinder/Core/WindowManager.swift`
- `XFinder/Views/Detail/WindowDetailViews.swift`
- `XFinder/Core/Shortcuts/ShortcutCatalog.swift` and the existing shortcut recording view only if needed
- focused pure rules/tests and their existing package wiring; add-only localized strings if the Settings copy changes
- Remove `CommandTabSwitcherView` only if a final repository-wide reference check confirms it remains unused.

Do not add a second window lister, capture provider, settings page, or persistent key for the existing enable toggle. Do not alter unrelated Dock preview behavior, screen-capture permissions, global macOS shortcuts, or the live thumbnail design without separate evidence and scope.

## Acceptance

- Focused tests cover shortcut parsing/conflicts, explicit clear vs missing/malformed preference, provider-order eligibility/wraparound, OFF behavior, stale window/capture results, and visible-switcher grave vs hidden-switcher `⌘` + grave behavior.
- Remove the dead `CommandTabSwitcherView` implementation after confirming its only reference is its declaration; verify no duplicated active switcher UI path remains.
- Baseline and final `sh scripts/gate-all.sh` are green on the task branch; any added pure file is included in the test package; project file is linted if touched.
- Installed-app checks use physical key presses: quick `⌘Tab` ON/OFF, `⌘⇧Tab`, same-app cycle across multiple windows, setting change/clear, bare-grave mode toggle while open, search typing, permission-denied path, and thumbnail timing. Report physical vs synthetic input and live permission state.
- No install, commit, merge, or Notion task-state change occurs before this draft is reviewed and accepted.

## Explicitly out of scope

Screen/video recording bugs, OCR cold-start performance, Preview RAW trash behavior, and screenshot shortcut/pointer-guide work are separate tasks. The owner's request for “Recording: fix minor bugs” needs the target recording flow and a reproducible symptom before it can receive an acceptance test. Existing project decisions against adding screen/video recording are not changed by that phrase alone.
