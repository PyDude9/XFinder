# XF-MB-GENERAL-01 — Minimal menu bar popover

## Goal

Keep the menu bar popover for general entry points only: File Browser, Uninstall Apps, and Settings. Remove controls and tools already available from Notch tabs. Dismiss the popover on every click outside it.

## Files

- `XFinder/Views/MenubarPanelView.swift`: replace tabbed feature dashboard with a compact general-actions panel.
- `XFinder/App/MenubarController.swift`: reliably close the transient popover on outside clicks while preserving status-item toggle behavior.
- `XFinder/Core/MenubarPanelRules.swift`: set compact panel dimensions. The popover no longer reads the previous tab preference.
- Relevant tests under `Tests/XFinderLogicTests/` if pure rules change.
- `XFinder/Resources/L10n.strings.json` only if existing strings do not cover labels.

## Failure cases

- File Browser disabled: omit its action; remaining actions stay usable.
- Uninstall destination unavailable: navigation remains through the existing `.uninstaller` destination.
- Settings action: closes the popover before opening settings.
- Empty/unknown persisted tab preference: no tab preference is read or required.
- Click outside in another app: close through the global event monitor.
- Click outside inside XFinder: close through the paired local event monitor.
- Click within the popover: keep it open.
- Click XFinder status icon while open: close once; do not immediately reopen.
- Popover closes while monitor callbacks are queued: teardown monitors idempotently.
- Popover closes: remove both event monitors. Process exit releases any remaining registrations.

## Acceptance

- Dropdown shows only File Browser (when enabled), Uninstall Apps, and Settings.
- No Notch module tabs or repeated quick controls remain.
- Outside click dismisses; inside click does not.
- Run relevant tests and `sh scripts/gate-all.sh` with a private `XF_OUT`.
- Live visual verification only through Atlas helper; report if helper permission prevents it.

## Out of scope

Notch content, full Settings navigation, menu-bar icon/readout preferences, and Notch tab ordering.
