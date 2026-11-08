# XF-TRANSLATE-AI-BUTTON — "Dịch bằng AI" button on the translate card

Owner (2026-11-08, screenshot of the Trancy-style card): "thêm 1 nút nhỏ (click vào là dùng AI đã có trong settings để dùng dịch
bằng AI) kế bên nút bánh răng". Builder: Gemini/Antigravity on `agent/antigravity-XF-translate` (already fast-forwarded to main).
Boss reviews and installs. Builder does **not** install or launch its own build (BUILDER.md) — the last install from the branch
would have removed the Notch and archive work that is only on main.

## Job sentence

Người dùng bấm nút này để xem bản dịch AI của đúng chữ đang hiện trên thẻ, kể cả khi Dịch AI không bật sẵn trong Cài đặt.

## What already exists (main `fc9e2dd`)

| Piece | Where | Use |
|:--|:--|:--|
| Footer row: copy · sổ từ · bánh răng | `TranslateSelectionView.footerRow` (~L247–305) | Add the new button **between "Sổ từ vựng" (`book.pages`) and the gear**, same style: `Image(systemName: "sparkles")`, size 12, `.secondary`, `.buttonStyle(.plain)`, `.help(L10n.t("Dịch bằng AI"))` |
| One-call entry point | `TranslateSelectionController.analyzeWithAI()` → `startAITranslation(text:)` | Call this. Do not write a second AI path. |
| AI engine + config | `TranslateAssistant.analyze` → `VoiceRefinerFactory.make(tier: .customAPI, provider: …)` (Boss `6dacc0b`) | Uses the provider/key from Chọn thông minh ▸ Dịch ▸ Dịch bằng AI. Never write `voice.refinerTier`. |
| Result UI | `aiSection` / `aiDetailsSection` | Already renders busy / meaning / synonyms / `messageKey` error. |

## The one structural gap

`contentSection` shows `aiSection` **only when `model.showAI`** (the persisted setting `translate.showAI`, default false). A click
with that setting off would run the request and show nothing.

Add a per-card, non-persisted flag on the model, e.g. `var aiRequested = false`:
- button action: `model.aiRequested = true; TranslateSelectionController.shared.analyzeWithAI()`
- `contentSection`: `if model.showAI || model.aiRequested { aiSection }`
- reset `aiRequested = false` wherever a new card starts (`translate(text:sourceApp:anchorRect:)`), so the next selection does not
  inherit it.
- Do **not** flip `translate.showAI` from the button (one key one control — the setting stays the Settings page's).

## Behaviour / failure cases

| Case | Expected |
|:--|:--|
| AI configured, single word | Same `.definition` module as today; result appears under the Google/dictionary sections. |
| Sentence (`model.isSentence`) | Prefer `.silentTranslate` over `.definition` (a definition prompt on a sentence returns junk) — if you change `startAITranslation`, keep `.definition` for words. |
| Click while busy | No second request (button disabled while `assistant.busy \|\| model.isTranslating`). |
| Result already shown | No re-request; button may stay enabled as a no-op or show filled `sparkles` state. |
| No provider / key | Show the existing `messageKey` error inline. The current key text says "Hãy cấu hình AI trong trang Giọng nói…", which is now **wrong** (config lives on Chọn thông minh ▸ Dịch). Add a new key pointing there + a "Mở Cài đặt" button (`openTranslateSettings()`), via an add-only L10n script. |
| Network error / timeout | Error row, card stays open, other sections unaffected. |
| `isTranslating` | Verify it returns to false on success and failure of the AI path (lines ~250, ~618); a stuck spinner is a bug. |
| Privacy | The AI provider receives the selected text — same as the Settings copy already says. No silent call on card open from this button's code. |

## Files

`XFinder/Views/TranslateSelectionView.swift`, `XFinder/Core/Translate/TranslateSelectionController.swift` (model flag + reset,
optional module choice), `XFinder/Core/Translate/TranslateAssistant.swift` (only for the corrected message key),
`scripts/add-translate-ai-button-l10n.py` (add-only), `XFinder/Resources/L10n.strings.json` **only through that script**
(never re-serialize the whole store), `docs/AGENT_WORKLOG.md`.

## Done =

Commit on the branch; `sh scripts/gate-all.sh` with your own `XF_OUT` → paste the result. Report: build · tests · gate · "not
verified live". Boss merges + installs; owner hand test **T-TRANSLATE-AI-BTN**: Dịch AI off in Settings → bôi đen "offers" → ⇧⌘G →
bấm ✨ → bản dịch AI hiện dưới phần từ điển; chọn từ khác → thẻ mới không tự gọi AI.
