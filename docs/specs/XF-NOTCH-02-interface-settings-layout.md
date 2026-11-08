# XF-NOTCH-02 — Make Notch settings easier to scan

Status: paired, UI-only task for the Notch refresh. Preserve behavior and all existing preference values. The display-target selector from XF-NOTCH-01 is a separate follow-up and must not be added by this task.

## Goal

Restructure the existing “Giao diện notch” Settings page so users can quickly understand activation, opening behavior, display appearance/privacy, fullscreen behavior, page visibility/order, and accent. Keep every current control and its live effect. This is an information hierarchy and explanatory-copy task, not a settings redesign across the app.

## Required layout

Keep the current page title and master switch. Group controls in this reading order:

1. **Bật/tắt** — master switch and a concise explanation that disabling the surface hides Notch UI while unrelated app features remain available.
2. **Cách mở** — hover on/off, hover destination, hover speed, and click destination. Explain that hover and click are independent and explicit deep links/hotkeys keep their requested page.
3. **Hiển thị** — physical notch vs. virtual pill; fullscreen visibility; screen-capture visibility. Place the caveat directly beside capture privacy: behavior depends on the capture path and is not a universal guarantee.
4. **Trang và màu** — page visibility/order, restore defaults, accent.

Use the existing settings components, spacing tokens, and menu pickers. Keep the page compact and scannable; avoid adding nested cards, decorative pills, new previews that do not reflect actual behavior, or controls without a real reader.

## Exact behavior to preserve

- Keep all existing keys and defaults: `dropTray.notchEnabled=true`, `dropTray.hoverEnabled=true`, `notch.hoverOpens="peek"`, `notch.hoverSpeed="medium"`, `notch.clickOpens="files"`, `notch.pillOnPlainScreens=true`, `notch.hideFromCapture=false`, `notch.fullscreenVisibility="show"`, `notch.pages="files,clipboard,nowPlaying,agents,calendar,timer,aiUsage"`, `notch.accent="system"`.
- Keep page ordering/toggle restrictions and the guarantee that at least one page remains visible.
- Keep calls to `NotchSurfaceController.shared.applySettings()` for settings that require immediate application.
- Do not add, remove, rename, migrate, or change the meaning of a UserDefaults key.
- Do not change the `sharingType` implementation or claim universal capture exclusion. Correct the current UI copy if it overstates that guarantee, but do not change the setting's effect.
- Every new user-facing string uses `L10n.t` and add-only entries in `L10n.strings.json`.

## Allowed files

- `XFinder/Views/Detail/NotchInterfaceDetailView.swift`
- `XFinder/Resources/L10n.strings.json` (add-only)
- `scripts/add-notch-settings-copy-l10n.py` (add-only helper)
- `docs/AGENT_WORKLOG.md`

Do not edit core logic, page models, project file, defaults tests, or other settings pages.

## Failure cases / review requirements

- Master switch off: dependent controls are disabled with a clear explanation; no setting is reset.
- Hover off: drag/drop and shake behavior remain available according to their own settings.
- Hover destination hidden: existing fallback remains; UI must not promise a hidden page will open.
- Only one page visible: user cannot turn it off.
- Unknown stored picker value: existing parsers/defaults remain safe; the page must not overwrite it merely by opening Settings.
- Fullscreen detection uncertain: retain the existing conservative visible behavior.
- Capture privacy: copy must accurately say the preference controls the Notch window's sharing state; external capture tools may differ.
- Restore defaults changes only the existing page-order key as it does today; it must not reset unrelated choices.

## Acceptance criteria

- A reviewer can find the hover, click, fullscreen, capture-visibility, page-order, and appearance controls by scanning the four named groups.
- All existing controls remain reachable by mouse and keyboard with visible labels/help and no hover-only action.
- Toggling each control has the same effect and persistence as before; no new setting key is introduced.
- New/edited localization passes coverage, duplicate, literal, and interpolation audits.
- Run targeted notch/settings tests and `sh scripts/gate-all.sh`; report build/tests/gates separately. No app install or launch.
