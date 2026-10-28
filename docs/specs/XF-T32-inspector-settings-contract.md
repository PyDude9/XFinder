# XF-T32 — Inspector settings completion, owner continuation 2026-10-28

W6 design reference names an Inspector settings page. The browser settings sidebar currently has no Inspector destination, although global Preview and Show More preferences already exist.

Add an Inspector destination to BrowserSettingsWindowController.Tab, preserving all existing raw values/pages. Expose the existing fileBrowser.showPreview and fileBrowser.previewShowMore keys (both default false, matching BrowserSettings and their current views). Explain that Show More applies to the Information tab; disable that control while Preview is OFF without clearing its saved value. Existing per-pane Preview/Information selection remains local. No new preferences, no default changes, no decoding/scanning controls, no filesystem writes.

Files: BrowserSettingsWindow.swift; FeatureKeyDefaultsTests.swift; add-browser-w6-l10n-entries.py; L10n.strings.json. No new compiled app files or project entries.

Failure cases: no selected item still displays the existing empty Inspector; Preview OFF frees pane space everywhere; toggling ON restores Inspector without altering the file selection; Show More state remains saved while disabled; same setting propagates across browser windows; long/localized labels fit; reopened Settings keeps the selected Inspector page. No dependency on permissions or file format support.

Acceptance: source/default tests include the new bindings; mutate a binding default and observe RED, restore GREEN; complete detached gate in private XF_OUT; install via existing script and compare dylib hashes; live navigation, OFF/ON, selection preservation and Show More persistence where GUI access permits. Report build/tests/mutation/live separately. No push.

## Owner correction — consolidate settings

The owner explicitly requests Browser Settings become one page inside XFinder Settings, because separate settings windows are confusing. Replace the standalone window with navigation to the existing File Browser destination. Embed browser categories in that page with a menu picker, preserving existing controls and selected category. Remove the redundant button that opened separate settings and update shortcut guidance. Existing callers (browser command/⌘,) must navigate the same main XFinder window. No second sidebar or duplicate preference controls. Verify command entry and direct sidebar navigation, category switching, reopening, existing Inspector toggles and selection preservation.

Additional file: XFinder/Views/Detail/FileBrowserDetailView.swift. Keep routing compatibility in the existing BrowserSettingsWindowController entry point; it no longer owns a window. No new files in XFinder, no preference migrations.

Live finding: the static SwiftUI app Settings menu can handle ⌘, before the browser window dispatcher, especially on first opening main Settings. Include XFinder/App/XFinderApp.swift: its Settings action routes a key BrowserWindow to the same File Browser destination; other contexts retain Features & Permissions.
