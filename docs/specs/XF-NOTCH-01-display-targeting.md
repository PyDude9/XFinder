# XF-NOTCH-01 — Display targeting for the Notch surface

Status: execution scope based on the owner's approved Notch refresh plan. This is a staged addition to XFinder's existing surface, not a replacement of its layout or interaction model.

## Goal

Let a user choose which display owns the one interactive Notch surface while preserving XFinder's current automatic behavior by default. Keep existing physical-notch geometry, page sizes, screen-sharing policy, hover rules, and page routing unchanged.

Droppy's extracted constants are comparison data, not XFinder defaults. Do not replace the measured 185 × 32 pt physical cutout geometry, 120 × 24 pt plain-screen pill, page-specific expanded sizes, hover delays, or transition curve in this task.

## User-visible contract

Display target choices, added by the paired UI task:

- **Automatic** (default; preserves current behavior): use the pointer/interaction display while the user is interacting; when idle, prefer the physical-notch display if present, otherwise the main display.
- **Built-in display**: prefer the display with a physical notch; if none is connected, use the main display and report the fallback in Settings.
- **Main display**: use the display macOS currently identifies as main; if unavailable, use the first usable display.
- **Choose display…**: persist the selected display ID. If it disconnects, keep the choice, temporarily show the surface on the main usable display, and show a non-blocking fallback status in Settings. Restore the selected display when it returns.

Only one interactive surface exists in this stage. “All displays” and simultaneous per-display panels are explicitly deferred: they require separate ownership for panel lifecycle, activity routing, drag zones, focus, and duplicate-notification arbitration.

Changing the target while a panel is expanded, a drag is active, a composer is open, or a task is running must not move the panel underneath the pointer or interrupt work. Apply the new target after the surface returns to an idle/collapsed state. An explicit open on a display still in use must stay there for that session. Never move a panel to a display outside its visible frame.

## Existing behavior and constraints

- `NotchSurfaceController` owns one `SurfacePanel`, selects the pointer screen for interaction, and uses the notched display for the collapsed badge when available.
- `NotchSurfaceLayout` derives the real cutout from `auxiliaryTopLeftArea` / `auxiliaryTopRightArea`; a plain display uses XFinder's existing virtual notch.
- The state machine distinguishes notch and pointer anchors; file-drag and shake behavior must remain intact.
- Fullscreen visibility is best-effort and defaults to show. Active expanded work and actionable content remain visible.
- Keep the current setting defaults and never change the meanings of existing UserDefaults keys.

## Scope and allowed files

Core task owner may change only:

- `XFinder/Core/Notch/NotchDisplayTargetRules.swift` (new pure resolver)
- `XFinder/Core/Notch/NotchSurfaceController.swift`
- `XFinder.xcodeproj/project.pbxproj`
- `Tests/XFinderLogicTests/NotchDisplayTargetRulesTests.swift` (new)
- `Tests/XFinderLogicTests/NotchDisplayTargetRules.swift` (new package symlink)
- `docs/AGENT_WORKLOG.md`

Paired Settings UI task may change only:

- `XFinder/Views/Detail/NotchInterfaceDetailView.swift`
- `XFinder/Resources/L10n.strings.json` (add-only)
- `scripts/add-notch-display-target-l10n.py` (add-only helper)
- `docs/AGENT_WORKLOG.md`

The UI must use a new key `notch.displayTarget` with the canonical reader default `automatic`. Supported raw values are `automatic`, `builtIn`, `main`, and `specific`. A selected screen is stored separately as `notch.displayTargetID` (UInt32-compatible integer). Do not store screen names as identity. Do not add a control for “All displays” in this task. The paired UI task owns the feature-default test row.

No other source, settings, archive, permissions, window class, app identity, or distribution files may change.

## Pure resolver contract

Create a Foundation/CoreGraphics-only rules type. Inputs are the configured target, connected display descriptors `(displayID, isMain, hasPhysicalNotch)`, pointer display ID, active surface display ID, and whether the surface is busy. Output is the desired display ID and an explicit fallback reason; it must not mutate preferences.

Resolution rules:

1. Empty display input returns no target; the controller hides/retries when the system reports a display again and does not erase the saved preference.
2. `automatic` while interacting selects the pointer display if connected; otherwise preserve the active surface display; otherwise use the physical-notch display, then main, then first connected display.
3. `builtIn` selects the physical-notch display, then main, then first.
4. `main` selects main, then first.
5. A saved display ID selects that display while connected; otherwise return main/first with a `selectedDisplayUnavailable` reason while retaining the saved ID.
6. While busy, keep the active surface display if it is connected. A display removal is the exception: relocate safely to main/first and report fallback.
7. Resolver output is deterministic for the same inputs and does not inspect private SkyLight/CGS state.

## Failure cases to cover before coding

- No displays reported during reconfiguration; do not force-unwrap or clear the user's preference.
- Preferred display is disconnected, then reconnected with the same ID; fallback is visible and the preference returns automatically.
- Display ID is unknown or stale; deterministic fallback and explanatory Settings state.
- Screen is removed while the surface is open or a task is running; preserve task/state and relocate only because the current display no longer exists.
- Pointer crosses displays during a file drag; do not move the drop target under the drag.
- Target changes during a composer, active task, or actionable activity; defer relocation.
- Physical notch unavailable or external-only setup; use current virtual-notch geometry.
- Fullscreen detection unavailable/uncertain; retain existing conservative show behavior.
- Feature disabled; no visible panel or active monitor is started by the new resolver.

## Acceptance criteria

- Unit tests cover every target mode, no-display and disconnect/reconnect fallback, busy-session stability, and deterministic ordering.
- Existing `NotchSurfaceLayoutTests`, `NotchSurfaceMachineTests`, and `NotchFullscreenRulesTests` continue to pass unchanged.
- Existing hover, click, file drag, shake, explicit page routing, and one-panel lifecycle remain unchanged under `automatic`.
- The Settings choice changes only the target display and does not alter pill dimensions, page dimensions, display geometry, or fullscreen policy.
- Reconnecting a selected display returns the surface there without requiring the user to choose it again.
- Pure tests verify missing/unknown target values fall back to `automatic`; XF-NOTCH-02 owns the single reader/view default agreement row for `notch.displayTarget`. The display ID has no selected-display default.
- Run `sh scripts/mutation-check-notch.sh`, `plutil -lint XFinder.xcodeproj/project.pbxproj`, and `sh scripts/gate-all.sh` in the task worktree. For new files, verify each appears in the build log.
- Report build, tests, mutation and live behavior separately. Builder must report live display/fullscreen behavior as NOT VERIFIED unless tested in the installed app by the owner.

## Not in scope

- Multiple simultaneous panels / “All displays”.
- Copying Droppy's `.screenSaver` level, private CGS blur shim, clipboard polling interval, 120 FPS spectrum, or exact dimensions/animation values.
- New page families, activity-priority redesign, shake-threshold changes, clipboard engine changes, or redesign of Settings sections.
- Claims that `sharingType` excludes the surface from every capture/sharing product.
