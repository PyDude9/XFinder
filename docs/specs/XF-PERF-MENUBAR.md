# XF-PERF-MENUBAR — Menu bar & Notch responsiveness + legacy tab cleanup

## Goal

1. Reduce avoidable main-thread work in XFinder's idle mouse-move path, Notch tab-switch/expanded render path, and repeated menu-bar popover opens based on live sampling and code inspection.
2. Remove provably unreachable legacy menu-bar tab views and tab-parsing rules left behind after `283ba1f`, while preserving all shared presets/formatters, the native right-click menu, File Browser, Uninstall Apps, Settings, Notch, and Full Settings.
3. Keep performance fixes and dead-code cleanup in separate commits on `agent/antigravity-XF-PERF-MENUBAR`.

## Baseline measurements (read-only on running `/Applications/XFinder.app`, PID 98431)

- Idle `top -l 5 -s 1 -pid 98431` (steady state, Notch and dropdown closed): `0.2%–1.0%` CPU, `136` idle wakeups (`IDLEW`), `~10–25` CSW/s, `7` threads, `236M` mem. (An earlier burst during initial check showed `12.7%–22.6%` CPU across 10–17 threads before settling.)
- 3-second `sample 98431 3` main-thread XFinder hotspots:
  - `NotchSurfaceController.handle(_:)` → `tick()` active on mouse movement: calls `collapsedProjection` (allocating `Set(visibleDestinations)`, `clockSuite.collapsedBadge(at: Date())`), then calls `badgeShown` which recomputes `collapsedProjection` a second time, plus `hoverZone`/`wingItems`/`agentEdgeRect` even when collapsed and the pointer is far below the top menu bar.
  - `FinderKeyboardController.handle(type:event:)` (6 samples in 3s): calls `NSWorkspace.shared.frontmostApplication?.bundleIdentifier` (`_LSCopyApplicationInformation`) on every global keyDown. **Out of scope** for this pass (event-tap controller requiring live Accessibility verification; logged as follow-up).
  - `LocalAppUsageTracker.handleSampleTick()` → `persistStore()` (2 samples in 3s): synchronous JSON encode + atomic write on main thread every 15s when active. **Out of scope** for this pass (logged as follow-up).
- Unmeasured live paths (Builder does not install/relaunch or send clicks/keys):
  - Dropdown first vs repeated open latency.
  - Notch tab switch latency in the installed app.

## Files to change

### Commit 1 — Performance fixes
- `XFinder/Core/Notch/NotchSurfaceLayout.swift`: add pure `mayHitCollapsedHover(point:screen:notch:metrics:)` fast-path predicate.
- `XFinder/Core/Notch/NotchSurfaceController.swift`:
  - In `tick()`: early-return when collapsed, not on surface, no dwell active, and `!mayHitCollapsedHover(...)` (clearing `pointerOnAgentEdge = false`); reuse `wingProj.isVisible` instead of calling `badgeShown` (eliminates duplicate `collapsedProjection` per hover tick).
  - In `render()`: compute `collapsedProjection` only when `machine.state == .collapsed` (avoids wasted work on every expanded render / Notch tab switch).
- `XFinder/App/MenubarController.swift`:
  - Lazily reuse a single `NSPopover` + `NSHostingController<MenubarPanelView>`, refreshing `rootView` on open so `BrowserSettings.isEnabled` and `L10n` stay current without reallocating the popover/hosting controller on every open.
  - Cache `AppIcon.icns` once in `applyIcon()` to avoid re-reading from disk on every voice-state idle callback.
- `Tests/XFinderLogicTests/NotchSurfaceLayoutTests.swift`: add unit tests for `mayHitCollapsedHover` (notched screen, plain screen with pill, below hover band, exact boundary).

### Commit 2 — Legacy menu-bar tab cleanup (provably unreachable)
- Delete `XFinder/Views/Menubar/MenubarUnsleepTab.swift`, `XFinder/Views/Menubar/MenubarMonitorTabs.swift`, `XFinder/Views/Menubar/MenubarToolsTabs.swift` (0 callers in `XFinder/`).
- `XFinder.xcodeproj/project.pbxproj`: remove the 12 entries (4 per deleted file).
- `XFinder/Core/MenubarPanelRules.swift`: remove unused `MenubarPanelTab` enum and `parseTab(_:)`. Preserve `panelWidth`, `panelHeight`, `UnsleepPreset`, `unsleepPresets`, `formatRemaining`, `parseCollapsedHeaders`, `encodeCollapsedHeaders`, `formatTemp`, `formatBatteryRemaining`, `formatRateKBs`, `formatBytes`.
- `XFinder/Views/MenubarPanelView.swift`: remove unused `MenubarPanelCardModifier` and `View.menubarPanelCard(padding:)`.
- `Tests/XFinderLogicTests/MenubarPanelRulesTests.swift`: remove tests for deleted `MenubarPanelTab` / `parseTab`; keep all shared preset/formatter tests.
- `Tests/XFinderLogicTests/FeatureKeyDefaultsTests.swift`: remove deleted `XFinder/Views/Menubar/MenubarUnsleepTab.swift` from `caffeine.keepDisplayOn` views list (retaining `XFinder/Views/Detail/SystemControlsPanel.swift`).

## Failure cases (`AGENT_QUICKSTART.md` rule 11)

- **Permission missing:** Accessibility or Screen Recording denied — none of these changes require new permissions; outside-click monitors and Notch hover monitors keep existing behavior.
- **Device/OS cannot do it:** Notch-less external display (virtual notch `height == 0`) with or without pill shown — `mayHitCollapsedHover` uses `max(notch.height, m.pillHeight, 8)` so plain-screen pill hover and 8pt top-edge hover still trigger.
- **Boundary values / empty lists:** `point.y` exactly at `screen.maxY - hoverBand` or `screen.maxY` must return `true` (inclusive `>=`). Empty `visibleDestinations` or `itemCount == 0` stays safe.
- **Context changes mid-action:**
  - Pointer leaves hover zone during dwell (`zoneEnteredAt != nil`) — fast-path is gated on `zoneEnteredAt == nil`, so leaving the zone still cancels `dwellWork` and clears `zoneEnteredAt`.
  - Drag active (`pressedMouseButtons & 1 == 1` or `isDragOutActive` / `isDropTargeted` / `isDropImporting`) — drag branch runs BEFORE the collapsed hover fast-path, so file-drag-to-notch and shake-to-open are untouched.
  - Popover closed by clicking outside, clicking status icon, right-clicking status icon, or hiding own icon — `popoverDidClose` and `closePopover` remove both local and global outside-click monitors idempotently.
  - `BrowserSettings.isEnabled` toggled in Settings between popover opens — `togglePopover` updates `hostingController.rootView` on every open, so File Browser row appears/disappears immediately.
  - `menubar.icon` changed in Settings — `applyIcon()` only uses `cachedAppIcon` when `raw == "xfinder"`; switching to SF Symbol choices still works.
- **Stale cached value:** `cachedAppIcon` is immutable bundle resource `AppIcon.icns`, never changes during process lifetime. Reused `NSPopover` refreshes `rootView` and `contentSize` on each open.
- **Each switch OFF:** `notch.enabled == false` (monitors not installed), `menubar.hideOwnIcon == true` (popover closed, status item hidden), `fileBrowser.enabled == false` (File Browser row omitted). No control promises unimplemented behavior.

## Acceptance

- Separate commits for performance fixes and legacy cleanup on `agent/antigravity-XF-PERF-MENUBAR`.
- `plutil -lint XFinder.xcodeproj/project.pbxproj` passes.
- `XF_ROOT="$(git rev-parse --show-toplevel)" XF_OUT="/tmp/xf-XF-PERF-MENUBAR" sh scripts/gate-all.sh` ends with `GATE: green`.
- Zero references to deleted `MenubarPanelTab`, `parseTab`, `menubarPanelCard`, or `Menubar*Tab*.swift` remain.
- Worklog recorded in `docs/AGENT_WORKLOG.md`.

## Out of scope

- Removing `L10n.strings.json` entries (add-only policy).
- Modifying `FinderKeyboardController` event tap or `LocalAppUsageTracker` persistence semantics.
- Removing product features (native right-click menu, menu-bar readouts, Notch modules, Full Settings).
- Installing, launching, pushing, or merging.
