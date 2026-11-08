> **Boss 2026-11-08 — superseded, kept for the record.** Codex draft from worktree `xf-settings-voice` (2026-11-07), never
> reviewed or built. Split as `docs/specs/XF-MFINDER-GAP-AUDIT.md` §1.5 asked: the voice half is
> `docs/specs/XF-VOICE-PERMISSIONS.md` (built); the Settings landing page is **Q-SETTINGS-LANDING** in
> `docs/PENDING_TESTS_AND_DECISIONS.md` (default: not built — the MFinder audit found no separate Settings chapter, the
> sidebar already has page search, and `settingsGeneral` was removed as a catch-all that duplicated owner pages).

# XF-SETTINGS-VOICE-PERMISSIONS

## Goal

Make XFinder's settings easier to scan through one compact settings directory inspired by the supplied MFinder/Notch specification, and stop Voice to Text from re-triggering permission requests on every activation. Keep all existing feature behavior, setting keys, defaults, and control ownership unchanged.

## Scope

- Add a Settings landing page that groups links to the existing setting-owning pages: General & appearance; Notch & pages; Clipboard & agents; Translation & selection; Capture & recording; Files & archive; Calendar & tasks; Focus & system; Windows & shortcuts; Permissions & app information.
- Links navigate to the existing owner page. Do not duplicate controls or change `UserDefaults` keys/defaults. Existing deep links and the Clipboard settings page remain available.
- Present the landing page in compact grouped rows/cards with search over category and destination titles. Search filters only links; clearing search restores all groups.
- Voice permission requests become independent for Microphone and Speech Recognition. Ask macOS only while the corresponding permission is undetermined. If denied/restricted, show the relevant System Settings destination and do not retry a prompt from a hotkey activation. Starting voice without either permission must fail with an actionable message and preserve the user's configured language/provider.
- Preserve Accessibility as a separate prerequisite; do not combine its request with microphone or speech authorization.

## Failure cases

- Permission already granted: activation starts without requesting again.
- Permission denied/restricted: activation does not call the authorization request; show recovery guidance and let the user open the corresponding System Settings pane.
- Permission undetermined: only the missing permission's explicit Settings action requests it; requesting Microphone must not request Speech and vice versa.
- Accessibility unavailable: voice activation remains blocked with its existing accessibility recovery path; it does not ask for unrelated permissions.
- Search has no matches: show an empty result with a clear-search action; no settings are changed.
- A destination or integration is unavailable: its existing owner page remains responsible for explaining the unavailable state.

## Expected files

- `XFinder/Models/SidebarDestination.swift` — add the Settings landing destination and compact Settings grouping.
- `XFinder/Views/RootView.swift` and `XFinder/Views/Detail/SettingsDetailView.swift` — route the landing page and preserve existing Clipboard settings.
- `XFinder/Core/Voice/VoiceManager.swift` and `XFinder/Views/Detail/VoiceDetailView.swift` — split permission state/request/recovery behavior.
- `XFinder/Resources/L10n.strings.json` — add-only localized labels/help text.
- `docs/AGENT_WORKLOG.md` — report scope and verification accurately.

## Acceptance

1. Settings landing page shows grouped, searchable links; selecting a row opens the existing page that owns those settings.
2. Existing Clipboard settings remain reachable and retain values after navigation/relaunch.
3. With both voice permissions granted, activating dictation does not invoke authorization requests.
4. With either permission denied, repeated activation shows recovery guidance and does not invoke another authorization request; the matching Settings action opens the proper System Settings pane.
5. With one permission undetermined, explicitly requesting it does not request the other permission.
6. Existing voice configuration, translations, and feature defaults remain unchanged.

## Verification boundaries

Build and static source checks may be performed. System prompt behavior, TCC persistence, actual System Settings navigation, and Settings layout/VoiceOver must be reported as not live-verified unless exercised in the installed app.
