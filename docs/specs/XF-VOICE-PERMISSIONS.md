# XF-VOICE-PERMISSIONS — dictation asks for one permission at a time and never re-asks a refused one

Boss spec (2026-11-08). Source: the voice half of the unreviewed Codex draft `docs/specs/XF-SETTINGS-VOICE-PERMISSIONS.md`
(worktree `xf-settings-voice`, never built). The audit `docs/specs/XF-MFINDER-GAP-AUDIT.md` §1.5 asked to split the voice fix
into its own task — this is that task. The Settings landing-page half is **not** in scope (see Q-SETTINGS-LANDING).

## Job sentence

Người dùng bấm phím nhập giọng nói để nói thành chữ; khi thiếu quyền, họ cần biết **đúng quyền nào** thiếu và bật nó ở đâu —
không bị hỏi lại thứ đã trả lời, không bấm một nút mà chẳng có gì xảy ra.

## Measured on main `b90e5a6` (source)

| Where | What happens today | Why it is wrong |
|:--|:--|:--|
| `VoiceManager.handleStart` → `checkAndRequestPermissions()` | Any missing permission ⇒ calls `AVAudioApplication.requestRecordPermission()` **and then** `SFSpeechRecognizer.requestAuthorization` on every press, whatever the status | A refused permission is asked again on every press (macOS answers "denied" silently, so the user sees only the generic error) |
| same | Error text "Chưa cấp quyền Micro hoặc Nhận dạng giọng nói" for every case | The user cannot tell which of the two is missing, nor that it was refused |
| `VoiceDetailView` permission rows | "Yêu cầu" on the **Micro** row calls `checkAndRequestPermissions()` ⇒ also raises the Speech prompt | Asking for one permission asks for the other |
| same, permission already refused | "Yêu cầu" calls the request API, which returns at once; nothing opens | A button that visibly does nothing |
| same | Rows read `hasMicrophonePermission` (TCC, not observed) | Returning from System Settings does not refresh the row |

`FeatureHub.request(_:)` already implements the right per-permission behaviour (prompt only while `notDetermined`, otherwise
open the Privacy pane) and `FeatureHub.retain()` bumps `revision` on app activation. The page reuses it — one owner of
"how XFinder asks for a permission".

## Scope

1. Pure `XFinder/Core/Voice/VoicePermissionRules.swift` (Foundation only, symlinked into the test package):
   `decide(microphone:speech:) -> VoiceActivationDecision` = `.start` · `.ask([kinds still undecided], microphone first)` ·
   `.blocked(kind, restricted:)`. A refused/restricted permission wins over an undecided one (asking for the other one is
   pointless while dictation cannot work). `messageKey(for:)` returns the L10n key of the HUD line.
2. `VoiceManager.handleStart`: maps the two TCC statuses, follows the decision. `.ask` asks the undecided permissions **one
   after the other** in that single press (first use stays one press), stops at the first refusal, and then shows either
   "granted — press again" or the refusal line. `.blocked` calls **no** request API. `checkAndRequestPermissions()` is removed.
3. `VoiceDetailView` permission rows: Micro row → `FeatureHub.shared.request(.microphone)`, Speech row →
   `.speechRecognition`; status read through `FeatureHub.shared` (observed `revision`) with `retain()/release()` on
   appear/disappear so the rows refresh after System Settings. A refused row's button says "Mở Cài đặt hệ thống".
4. L10n add-only script `scripts/add-voice-permission-l10n-entries.py`.
5. Mutation harness `scripts/mutation-check-voice.sh` over `VoicePermissionRules.swift`.

Not in scope: Accessibility (unchanged, separate prerequisite), settings keys/defaults (none added or changed), the event tap.

## Failure cases

| Case | Expected |
|:--|:--|
| Both granted | `.start`; no request API is called |
| Micro refused, Speech anything | `.blocked(.microphone)`; HUD names Micro + where to enable it; no prompt |
| Speech refused, Micro undecided | `.blocked(.speechRecognition)`; Micro is **not** prompted (dictation cannot work anyway) |
| Restricted (MDM / Screen Time) | `.blocked(kind, restricted: true)`; text says it is restricted on this Mac, not "go enable it" |
| Micro undecided, Speech granted | `.ask([.microphone])`; only the Micro prompt |
| Both undecided | `.ask([.microphone, .speechRecognition])`; Micro first; if Micro is refused, Speech is not asked |
| Page: Micro row tapped | Only Micro is requested (or its pane opens when already decided) |
| Page: returning from System Settings | Rows show the new state without reopening the page |

## Acceptance

- Test package: decision table complete (16 status pairs), message keys exist in the shipped store, `ask` order is
  microphone → speech, refused beats undecided. Harness `mutation-check-voice.sh` all RED.
- Gate green; build compiles the new file; L10n gates 0; installed bundle `verify-l10n-runtime.py` 0.

## Hand tests (owner)

| Mã | Làm gì | Mong đợi |
|:--|:--|:--|
| T-VOICE-PERM-1 | Cài đặt hệ thống ▸ Quyền riêng tư ▸ Micro: tắt XFinder. Bật Nhập bằng giọng nói, bấm phím kích hoạt 3 lần | Mỗi lần chỉ hiện một dòng báo "Micro đang bị từ chối…"; **không** hộp thoại xin quyền nào |
| T-VOICE-PERM-2 | Trang Nhập bằng giọng nói ▸ Quyền & thử nghiệm ▸ hàng Micro (đang bị từ chối) ▸ "Mở Cài đặt hệ thống" | Mở đúng ô Micro; bật lại rồi quay về XFinder: hàng chuyển "Đã cấp" không cần mở lại trang |
| T-VOICE-PERM-3 | `tccutil reset SpeechRecognition com.xfinder.app`, Micro đã cấp, bấm phím kích hoạt | Chỉ một hộp thoại Nhận dạng giọng nói; sau khi cho phép: "Đã cấp quyền — nhấn phím lần nữa để nói" |
