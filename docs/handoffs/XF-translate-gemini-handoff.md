# Gemini handoff — XFinder Translate window overlap and AI fields

Date: 2026-10-29 (Asia/Ho_Chi_Minh)

Repository: `/Users/wolong/orca/workspaces/XFinder/GPT-Minion`
Branch: `agent/codex-translate-wordbook`
Base commit: `1a65d07` (includes `f03b3b1` core and `f171449` prompt validation)
Installed app: `/Applications/XFinder.app`, build at `/tmp/xfinder-wordbook-final/out/XFinder.app`

## Owner's latest report

The attached screenshots show two problems:

1. On a browser Article page, Apple's Translate popover sits over XFinder's floating Translate panel. The host panel, its Translate action/help text and the popover occupy the same region. This is a stacking/layout/focus problem. The owner reports that after Translate they have to click outside more than once to dismiss the remaining UI.
2. In Voice settings, API address/key/model fields are visible, but the owner cannot enter/configure the LLM model. The screenshot shows custom endpoint selected, address `https://bedrock.viber.vn/v1`, a masked existing key and model `deepseek-v4.1-flash`; connection reports configuration failure. Do not expose, print, replace, clear or transmit the saved credential. Diagnose independently whether this is keyboard focus stolen by the floating Translate panel, a field/editing issue, persistence issue or simply provider test failure. Use a harmless local QA marker for field persistence and revert it; don't send a request using the owner's existing key unless the owner expressly asks.

## Relevant implementation

- `XFinder/Core/Translate/TranslateSelectionController.swift`: creates a 520×300 floating `SurfacePanel`, calls `show(anchor: .spotlight)`, presents the native Translation popover from its SwiftUI child; suppresses outside click while `model.nativePresented`.
- `XFinder/Views/TranslateSelectionView.swift`: `.translationPresentation`, binding/request generation, native-close callback, selection-to-Wordbook action. Existing host-dismiss core fix is commit `3944f0a`; native popover close/Replace behavior was not successfully GUI-verified in that session.
- `XFinder/Core/Surface/SurfacePanel.swift`: shared floating interactive NSPanel and paired global/local click-outside monitor. Inspect window ordering, monitor ownership and focus before changing common surface semantics.
- `XFinder/Views/Detail/VoiceDetailView.swift`: `apiBaseURL` uses `@AppStorage`; `apiModel` uses `@State`, persists in `.onChange`, reloads on provider changes. Never log the API key or copy a key into the handoff.
- `XFinder/Core/Voice/VoiceSettingsKeys.swift`: reads configured fields. Key itself lives in macOS Keychain. `TranslateAssistant.swift` uses `VoiceRefinerFactory` and already showed the honest “Configure AI in Voice settings” message when no provider was configured on the QA run.

## Current evidence and QA

- Clean arm64 build passed. New feature source files compiled. Installed and build dylib hashes matched: `2d8a36af3cac52349c8a8c8fd331fbce93197ee4ade3317dbb870822e0462d76`.
- Full suite: 2,894 tests, 0 failures. L10n, UI token and all other gate audits green. Mutation changing Again to Easy made targeted SM-2 test fail 5 assertions; exact source restored.
- Installed GUI verified local Wordbook save/edit/review/JSON export/relaunch persistence; owned QA card and prompt edits were removed/reset afterwards. AI action honestly reports provider not configured in active test environment.
- Screenshot/native popover issue remains **unverified/failing per owner report**. Don't count source reasoning or the old asynchronous dismissal test as live acceptance.
- Installed app was opened after relaunch; settings page showed owner-managed excluded apps. Preserve all user settings and user data.
- Commits before handoff: `3944f0a`, `f03b3b1`, `f171449`, `1a65d07`. No push. No credential or API value belongs in logs.

## Required work

1. Reproduce the owner's two-window state in the installed app/real browser using GUI interaction. Inspect screenshots/AX and actual window frames/levels while the native popover opens, is dismissed, and Replace is selected. Don't rely on synthetic Carbon hotkey delivery (previous session found it unreliable).
2. Fix the Translate presentation lifecycle/layout so the Apple translation UI and XFinder host don't obscure one another or strand an interactive floating panel. Preserve Apple's Replace/Copy behavior. Clicking X, clicking outside, switching apps, closing the owner window and opening another XFinder settings page must each have a clear outcome. Do not solve overlap by breaking the native presentation binding or leaving an invisible panel catching keyboard input.
3. Reproduce typing/editing and persistence for endpoint and model fields in Voice settings. Distinguish app focus/window z-order from validation or endpoint failure. Test with a disposable URL/model marker only; restore the exact prior defaults afterwards. Never inspect/display the secret value. Explain that connection errors may be independent of editable fields.
4. Add/adjust focused regression coverage for deterministic lifecycle/field-reader behavior as appropriate. Run build and all gates. Install and verify the actual visible flows: open native Translate, dismiss once, switch to Voice settings, edit URL/model with harmless values, navigate away/back, confirm values, restore prior nonsensitive settings, confirm no stale overlay. Do not call a real provider with the owner's API key.
5. Record build/tests/live evidence separately. Commit only on a dedicated continuation branch, never push. Keep previous three Wordbook commits intact.

## Owner acceptance target

One click on native Translate must not leave a second XFinder translation surface covering unrelated settings. Voice settings must accept text reliably and persist the entered endpoint/model. Any model connection error should remain a visible, separate provider error after the fields are editable.
