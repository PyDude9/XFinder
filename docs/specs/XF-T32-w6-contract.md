# XF-T32 W6 — owner-requested continuation, 2026-10-28

Implements remaining Settings and Downloads tray from XF-T32-tilde-direction.md Q-T32-8/9/10. Learn and pane focus already exist; preserve those implementations and all existing settings.

## Step 1 — browser Settings

Replace the seven-item top toolbar with a left navigation sidebar, preserving tab raw values and all existing pages. Add Appearance and move existing window-chrome/pane-focus controls there. Add `fileBrowser.showLearnButton` (new key, default true) to Appearance and the browser root; existing Learn tabs/progress remain intact when hidden. Keep dormant License absent. No global app-settings redesign.

Files: BrowserSettingsWindow.swift, BrowserSettings.swift, BrowserRootView.swift, FeatureKeyDefaultsTests.swift, add-only L10n script/store.

Failure cases: missing preference uses true consistently; OFF hides only the launcher; already-open Learn stays usable; multiple windows observe changes; opening Settings with an explicit existing tab still works; long labels and small windows scroll rather than truncate; no permission or filesystem writes beyond preferences.

## Step 2 — Downloads tray

Add a toolbar popover showing up to 20 newest non-hidden entries in the user's Downloads folder, ordered by modification date with stable path ties. Subscribe to DirectoryLoadCoordinator only while visible, sharing its listing/watcher and releasing on close. Open file with native workspace; folder in browser. Reveal and Open Downloads remain reachable. Empty/loading/error states are localized. No thumbnail decoding, recursive scan, download progress claims or automatic cloud download.

Add an opt-in global Carbon shortcut with a catalog entry, default OFF; report registration conflict in Settings instead of claiming success. Global invocation opens a small Downloads panel, reusing the same content/controller; never show two Downloads surfaces simultaneously. Closing either surface cancels listing delivery and prevents stale updates. Default chord must be checked against ShortcutCatalog. No polling timers.

Files: new BrowserDownloadsRules.swift + BrowserDownloadsController.swift (+ four project entries each, pure rules test symlink/tests), BrowserToolbar.swift, BrowserSettingsWindow.swift, BrowserSettings.swift, ShortcutCatalog.swift, app startup wiring, L10n script/store. Existing filesystem-operation engines/signing scripts are unchanged.

Failure cases: Downloads missing/denied/unmounted; empty directory; rapid open/close/reopen; files deleted after listing; cloud-only file (no bytes read by tray); hidden entries and more than 20; conflicting global key; shortcut OFF unregisters immediately; background-app invocation; multi-window toolbar invocation; no watcher while hidden.

## Acceptance per step

Relevant tests and deliberate mutation RED then restored GREEN. Full detached gate with private XF_OUT, plutil when project changes, named new-file compile checks, diff check. Install through existing script and compare installed/build dylib hashes. Verify live Settings navigation and Learn toggle across windows for step 1; toolbar/global tray, empty/error/dismissal and scratch-only open/reveal for step 2. Record build/tests/live separately in Notion Run; no push. Report any unverified edge case.
