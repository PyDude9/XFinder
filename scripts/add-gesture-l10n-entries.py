#!/usr/bin/env python3
"""Add/replace the Mouse & Gestures strings in the L10n store.

Written as a script, not a hand edit, because the store is generated and
`check-l10n-reachability` reasons about `scope` — a wrong `scope` makes the whole
checker lie. Each entry here is declared with the scope it actually has at the
call site, and the script is idempotent: running it twice changes nothing.
"""

from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
STORE = ROOT / "XFinder/Resources/L10n.strings.json"

# Vietnamese key -> (English, scope)
ENTRIES: dict[str, tuple[str, str]] = {
    # --- System actions --------------------------------------------------------
    # Added 2026-09-22 with `GestureAction.systemAction`, extended 2026-09-23 when the
    # dispatch mechanism changed. The Global preset used to send `⌃↑`/`⌃↓`/`⌃←`/`⌃→` from a
    # constant, and the machine it ran on listened for none of them, so the arms were
    # recognised and did nothing. Mission Control / App Exposé / Show Desktop / the two Space
    # moves are now resolved from the user's own `com.apple.symbolichotkeys` and posted as a
    # real chord, so the page must NAME them (and the resolved keys beside them) — which is
    # what these strings are for.
    #
    # The four *caption* strings below were **missing before this pass** and therefore leaked
    # Vietnamese into the English page: `GestureSystemAction.captionKey` is passed to
    # `L10n.t` through a variable, so neither the `L10n.t("...")` sweep nor the literal audit
    # (which skips `GestureModel.swift`) could see them. Found by asking the store directly.
    "Mission Control": ("Mission Control", "sentence"),
    "App Exposé": ("App Exposé", "sentence"),
    "Hiện màn hình nền": ("Show Desktop", "sentence"),
    "Space trước": ("Previous Space", "sentence"),
    "Space kế tiếp": ("Next Space", "sentence"),

    # --- Unbound system actions ----------------------------------------------
    # A system action this Mac has no shortcut for sends nothing, and saying so is the whole
    # point: the alternative (inventing a key) is the bug this pass fixes.
    "Chưa gán trong macOS": ("No shortcut set in macOS", "sentence"),
    "chưa gán trong macOS": ("not set in macOS", "sentence"),
    "chưa có phím tắt trong macOS": ("no shortcut set in macOS", "sentence"),
    "Hành động hệ thống này chưa được gán phím trong macOS":
        ("This system action has no shortcut set in macOS", "sentence"),
    "Hướng này chưa gán nên không gửi gì":
        ("This direction is unassigned, so nothing was sent", "sentence"),
    "macOS chưa gán phím tắt cho hành động này, nên hướng này chưa gửi được gì":
        ("macOS has no shortcut set for this action, so this direction sends nothing",
         "sentence"),
    "macOS trên máy này chưa gán phím tắt cho hành động này, nên cử chỉ sẽ không gửi gì. Mở Bàn phím → Phím tắt để gán, hoặc chọn một hành động khác.":
        ("This Mac has no shortcut set for this action, so the gesture sends nothing. Open "
         "Keyboard → Keyboard Shortcuts to set one, or pick a different action.", "sentence"),
    "Đây là hành động hệ thống của macOS, nhưng máy này chưa gán phím tắt cho nó. XFinder gửi đúng phím bạn gán trong Bàn phím → Phím tắt, nên hãy gán ở đó hoặc chọn hành động khác.":
        ("This is a macOS system action, but this Mac has no shortcut set for it. XFinder "
         "sends exactly the keys you set in Keyboard → Keyboard Shortcuts, so set one there "
         "or pick a different action.", "sentence"),
    "Mở Phím tắt trong Cài đặt": ("Open Keyboard Shortcuts settings", "sentence"),
    # Also missing before this pass: the screenshot intent's name reaches the picker through
    # `L10n.t(kind.labelKey)`, so it rendered "Chụp màn hình" in an English UI. The new
    # model-vocabulary assertion in `L10nTests` is what found it.
    "Chụp màn hình": ("Screenshot", "sentence"),

    # --- The system-shortcut readout on the page -----------------------------
    "Phím hệ thống trên máy này": ("System shortcuts on this Mac", "sentence"),
    "Mở Phím tắt": ("Open Keyboard settings", "sentence"),
    "XFinder gửi đúng phím bạn gán trong Bàn phím → Phím tắt, nên bốn hướng của bảng Toàn cục chạy đúng như bàn phím của bạn.":
        ("XFinder sends exactly the keys you set in Keyboard → Keyboard Shortcuts, so the "
         "Global table's four directions act like your own keyboard.", "sentence"),
    # --- Button names ---------------------------------------------------------
    # Keyed by the **macOS** button number (0 = left, 1 = right, 2 = wheel, 3+ = side),
    # while the user-facing number is macOS's plus one. Description notes name *where
    # the button is*, because that is what the user asked; a side button gets no
    # nickname at all (no API can confirm its position) but does get a hedged hint.
    #
    # These were Vietnamese sentences declared "language-neutral" in
    # `L10n.LanguageNeutralKeys` and therefore returned verbatim in the English UI.
    # They are ordinary translatable sentences now, and the only neutral keys left
    # are the modifier glyphs.
    "Nút trái": ("Left click", "sentence"),
    "Nút phải": ("Right click", "sentence"),
    "Bấm con lăn xuống": ("Middle click", "sentence"),
    "Nút :number": ("Button :number", "sentence"),
    "Nút ": ("Button ", "fragment"),
    "thường là nút hông trên (gần con lăn)":
        ("usually the upper side button (near the wheel)", "sentence"),
    "thường là nút hông dưới (ngón cái)":
        ("usually the lower side button (under your thumb)", "sentence"),
    " — ": (" — ", "fragment"),

    # --- Direction headings ---------------------------------------------------
    # Two separate keys per direction, and the split is load-bearing:
    #
    #   * `titleKey`      — the heading on its own. No button, because the button is
    #                       the same for all four arms and printing it four times
    #                       read as "all four buttons are Button 3".
    #   * `motionKey`     — the physical motion, shown beside the diagram.
    #   * `motionHintKey` — the bare motion, joined to the held button's name by
    #                       `GestureDirectionDisplay.title(_:trigger:)`.
    "Kéo lên": ("Pull up", "sentence"),
    "Kéo xuống": ("Pull down", "sentence"),
    "Kéo sang trái": ("Pull left", "sentence"),
    "Kéo sang phải": ("Pull right", "sentence"),
    "kéo lên": ("pull up", "fragment"),
    "kéo xuống": ("pull down", "fragment"),
    "kéo sang trái": ("pull left", "fragment"),
    "kéo sang phải": ("pull right", "fragment"),
    "nghiêng con lăn trái": ("tilt the wheel left", "fragment"),
    "nghiêng con lăn phải": ("tilt the wheel right", "fragment"),

    # --- Device-capability wording --------------------------------------------
    # A single word, used on a disabled arm and inside the tooltip sentence.
    "Giữ": ("Hold", "fragment"),
    "Không hỗ trợ": ("Not supported", "sentence"),
    "Không hỗ trợ bởi chuột này": ("not supported by this mouse", "sentence"),
    "chưa dò được chuột nào": ("no mouse detected yet", "sentence"),
    "Không hỗ trợ bởi chuột này — ": ("Not supported by this mouse — ", "fragment"),
    "Đã nhận diện": ("Detected", "sentence"),
    "Bạn tự đặt": ("You set this", "sentence"),
    "Chuột đang kết nối": ("Connected mouse", "sentence"),
    "Chưa nhận diện được chuột — đang dùng bảng nút chung.":
        ("No mouse detected — falling back to the generic button table.", "sentence"),
    "Chưa nhận diện được chuột": ("No mouse detected", "sentence"),
    "Đang dò thiết bị…": ("Detecting device…", "sentence"),
    "Thiết bị do bạn chọn": ("Device you picked", "sentence"),
    "nút.": ("buttons.", "fragment"),
    "XFinder đọc trực tiếp mô tả HID của chuột: ":
        ("XFinder reads your mouse's HID descriptor directly: ", "fragment"),
    "XFinder đang đọc mô tả HID của chuột bạn.":
        ("XFinder is reading your mouse's HID descriptor.", "sentence"),
    "Không đọc được mô tả chuột nào. Sơ đồ vẫn dùng được với các nút cơ bản.":
        ("No mouse descriptor could be read. The diagram still works with the basic "
         "buttons.", "sentence"),
    "Không đọc được mô tả chuột vì thiếu quyền. Sơ đồ vẫn dùng được — chỉ là XFinder chưa biết chuột bạn có nút nào.":
        ("The mouse descriptor could not be read because a permission is missing. The "
         "diagram still works — XFinder just does not know which buttons your mouse "
         "has.", "sentence"),
    "Thiết bị này không khai đủ mã định danh, nên XFinder chỉ biết chắc những nút nó khai. Hướng nào chưa chắc thì để trống chứ không báo là không hỗ trợ.":
        ("This device does not declare complete identifiers, so XFinder only knows the "
         "buttons it does declare. A direction it cannot confirm is left plain rather "
         "than reported as unsupported.", "sentence"),

    # --- Runtime status keys --------------------------------------------------
    # These live in `Core/` and are L10n *keys*. They are Vietnamese literals only
    # because that is what the store is keyed by; the view resolves them.
    "Đã tắt": ("Off", "sentence"),
    "Đang hoạt động": ("Running", "sentence"),
    "Không mở được Event Tap — kiểm tra quyền Trợ năng":
        ("Could not open the Event Tap — check Accessibility permission", "sentence"),
    "Event Tap đã khôi phục; cử chỉ cũ đã hủy":
        ("The Event Tap recovered; the gesture in progress was cancelled", "sentence"),
    "Không tạo được vòng lặp cử chỉ": ("Could not create the gesture run loop", "sentence"),

    # --- Changed copy ---------------------------------------------------------
    "Hiện hai hướng nghiêng con lăn": ("Show the two wheel-tilt directions", "sentence"),
    "Chỉ dùng cho chuột có con lăn nghiêng được và có driver gửi cuộn ngang rời rạc — ví dụ Logitech MX Master với Logi Options. Đo trên máy này: Razer Basilisk và Magic Mouse đều báo cuộn liên tục, nên hai hướng đó sẽ không bao giờ chạy; tắt để sơ đồ khỏi vẽ thừa. XFinder không thể tự dò ra phần cứng của bạn.":
        ("Only for a mouse whose wheel tilts left/right and whose driver sends discrete "
         "horizontal scroll — a Logitech MX Master on Logi Options, for example. Measured "
         "on this machine: the Razer Basilisk and the Magic Mouse both report continuous "
         "scrolling, so those two directions can never fire; leave this off so the diagram "
         "does not draw them. XFinder cannot detect your hardware by itself.", "sentence"),
    "Ứng dụng đang dùng": ("App in front", "sentence"),

    # --- Changed copy ---------------------------------------------------------
    "Mỗi mũi tên là một động tác: giữ nút ghi trên mũi tên rồi kéo theo hướng đó. Bấm vào để xem nó gửi phím gì, và đổi nếu bạn muốn.":
        ("Each arrow is one move: hold the button shown on the mouse and pull in that "
         "direction. Click it to see the keys it sends, and change them if you want.", "sentence"),
    "là nút bạn giữ để bắt đầu mọi cử chỉ — cùng một nút cho cả bốn hướng":
        ("is the button you hold to start any gesture — the same button for all four "
         "directions", "sentence"),
    "Preset của ứng dụng này cố ý để trống hướng này, nên không rơi về bảng Toàn cục.":
        ("This app's preset deliberately leaves this direction empty, so it does not fall "
         "back to the Global table.", "sentence"),
    "Ứng dụng này không có preset riêng, và bảng Toàn cục cũng chưa gán hướng này. Bấm “Đổi phím tắt” để tự đặt.":
        ("This app has no preset of its own, and the Global table has nothing for this "
         "direction either. Click “Change shortcut” to set one.", "sentence"),
    "Mặc định = preset dựng sẵn · Tự đặt = bạn đã đổi hướng đó · Chưa gán = cố ý không gửi phím. Chưa gán trên ứng dụng đã có preset sẽ không rơi về bảng toàn cục. Biểu tượng ⇄ nhỏ trên mũi tên nghiêng nghĩa là hướng đó chuyển tiếp cuộn ngang nguyên bản của chuột.":
        ("Preset = shipped default · Yours = you changed that direction · Unassigned = "
         "deliberately sends nothing. Unassigned on an app that has a preset never falls "
         "back to the Global table. The small ⇄ badge on a tilt arrow means that direction "
         "passes the mouse's own horizontal scroll straight through.", "sentence"),

    # --- Action vocabulary ----------------------------------------------------
    # The **intents**. These are the words the page uses to describe what a gesture is
    # for, and they are separate from the keystroke on purpose: the same intent is a
    # different shortcut in different apps, and a shortcut on its own (`⌘⇧]`) tells a
    # user nothing about what it will do.
    "Lùi": ("Back", "sentence"),
    "Tiến": ("Forward", "sentence"),
    "Tab kế tiếp": ("Next tab", "sentence"),
    "Tab trước": ("Previous tab", "sentence"),
    "Mở lại tab vừa đóng": ("Reopen last closed tab", "sentence"),
    "Trang kế tiếp": ("Next page", "sentence"),
    "Trang trước": ("Previous page", "sentence"),
    "Mục kế tiếp": ("Next item", "sentence"),
    "Mục trước": ("Previous item", "sentence"),
    "Phóng to": ("Zoom in", "sentence"),
    "Thu nhỏ": ("Zoom out", "sentence"),
    "Vừa khung": ("Fit to window", "sentence"),
    # --- Action groups ---
    "Điều hướng": ("Navigation", "sentence"),
    "Soạn thảo": ("Editing", "sentence"),

    # --- Where a binding came from -------------------------------------------
    "Quy ước chung của macOS": ("Standard macOS convention", "sentence"),
    "Quy ước chung của macOS, hầu hết ứng dụng đều hiểu.":
        ("A standard macOS convention — most applications understand it.", "sentence"),
    "Phím tắt riêng của ứng dụng": ("This app's own shortcut", "sentence"),
    "Phím tắt riêng của ứng dụng này — có sẵn, không cần cấu hình gì.":
        ("This application's own shortcut — already set up, nothing to configure.", "sentence"),
    "Phím bạn tự ghi": ("a shortcut you recorded", "sentence"),
    "Bạn đã tự đặt phím cho hướng này. Bấm mũi tên quay lại để trả về preset.":
        ("You set the shortcut for this direction. Click the back arrow to return it to the "
         "preset.", "sentence"),
    "Ứng dụng này không có preset riêng, và bảng Toàn cục cũng chưa gán hướng này.":
        ("This app has no preset of its own, and the Global table has nothing for this "
         "direction either.", "sentence"),
    "Đưa hướng này về preset — không đụng các hướng khác":
        ("Return this direction to its preset — leaves the others alone", "sentence"),
    "Đổi hành động cho hướng này": ("Change what this direction does", "sentence"),
    "Hành động": ("Action", "sentence"),
    "Ghi phím tắt…": ("Record a shortcut…", "sentence"),
    "XFinder gửi đúng phím này. Việc phím đó có làm đúng hành động hay không còn tuỳ phím tắt riêng của ứng dụng — macOS cho phép đổi gần như mọi phím tắt.":
        ("XFinder sends exactly these keys. Whether they still perform the name shown "
         "depends on the application's own shortcut settings — macOS lets almost any "
         "shortcut be rebound.", "sentence"),

    # --- Arm tooltips (device capability) ------------------------------------
    "Chuột này không có phần cứng cho hướng đó":
        ("This mouse has no hardware for that direction", "sentence"),
    "Chưa đọc được mô tả chuột, nên chưa rõ hướng này có chạy được không":
        ("The mouse's descriptor could not be read, so it is not yet known whether this "
         "direction can run", "sentence"),
    "chuyển tiếp cuộn ngang của chuột": ("passes the mouse's horizontal scroll through", "sentence"),
    "Chưa rõ": ("Unknown", "sentence"),

    # --- Device switches ------------------------------------------------------
    "Nút giữ và cuộn": ("Hold button and scrolling", "sentence"),
    "Nút giữ bắt đầu mọi cử chỉ. Nút cuộn là tuỳ chọn riêng, mặc định tắt.":
        ("The hold button starts every gesture. The scroll button is a separate option, "
         "off by default.", "sentence"),
    "Nút giữ": ("Hold button", "sentence"),
    "Giữ nút này rồi kéo bốn hướng. Mặc định là nút hông — con số tuỳ chuột, nên hãy ghi lại nếu bạn muốn nút khác.":
        ("Hold this button and pull in one of four directions. The default is a side "
         "button — the number depends on your mouse, so record it if you want another "
         "one.", "sentence"),
    "Ghi nút": ("Record button", "sentence"),
    "Nút cuộn": ("Scroll button", "sentence"),
    "Giữ nút cuộn rồi kéo để cuộn": ("Hold the scroll button and drag to scroll", "sentence"),
    "Dành cho ứng dụng cần cuộn nhiều như Photoshop hay CapCut: giữ một nút hông rồi kéo là cuộn, không cần nhấc tay khỏi chuột. Nút đó vẫn bấm bình thường khi bạn không kéo. Mặc định tắt vì nó chiếm một nút bạn có thể đang dùng cho việc khác.":
        ("For applications you scroll a lot in, such as Photoshop or CapCut: hold a side "
         "button and drag to scroll without lifting your hand off the mouse. That button "
         "still clicks normally when you do not drag. Off by default because it takes "
         "over a button you may be using for something else.", "sentence"),
    "đang ghi…": ("recording…", "fragment"),
    "bấm để đổi": ("click to change", "fragment"),
    "Nút bạn giữ để bắt đầu mọi cử chỉ. Bấm để ghi nút khác.":
        ("The button you hold to start any gesture. Click to record a different one.", "sentence"),

    # --- Measured activity ----------------------------------------------------
    "XFinder đã nhận gì": ("What XFinder received", "sentence"),
    "Dòng đo thật từ engine — không phải hướng dẫn. Giữ nút rồi kéo để thấy nó ghi lại.":
        ("Real measurements from the engine, not instructions. Hold the button and drag "
         "to see it record them.", "sentence"),
    "Event Tap chưa mở nên chưa có gì để hiện. Kiểm tra quyền Trợ năng ở trên.":
        ("The event tap is not open, so there is nothing to show yet. Check the "
         "Accessibility permission above.", "sentence"),
    "Bật ghi nhật ký để xem XFinder nhận được nút nào và gửi phím gì. Mặc định tắt để không tốn CPU khi rảnh.":
        ("Turn on logging to see which button XFinder received and which keys it sent. Off "
         "by default so an idle app costs no CPU.", "sentence"),
    "Bật ghi nhật ký": ("Turn on logging", "sentence"),
    "Chưa có cử chỉ nào. Giữ nút trên sơ đồ rồi kéo một hướng — dòng đo sẽ hiện ở đây.":
        ("No gestures yet. Hold the button on the diagram and pull in one direction — the "
         "measurement will appear here.", "sentence"),
    "Nút giữ đã được nhấn": ("Hold button pressed", "sentence"),
    "Đã khoá hướng": ("Direction locked", "sentence"),
    "Đã gửi phím tắt": ("Shortcut sent", "sentence"),
    "Không vượt ngưỡng — đã phát lại click bình thường":
        ("Under the threshold — the normal click was replayed", "sentence"),
    "Quay về vùng chết trước khi thả — đã huỷ":
        ("Came back inside the deadzone before release — cancelled", "sentence"),
    "Đọc được nghiêng con lăn rời rạc": ("Read a discrete wheel tilt", "sentence"),
    "Giữ nút cuộn và kéo → cuộn": ("Held the scroll button and dragged → scrolled", "sentence"),
    "Nút được theo dõi nhưng không phải nút giữ":
        ("Button observed, but it is not the hold button", "sentence"),
    "Nút bạn vừa bấm: ": ("The button you just pressed: ", "fragment"),
    "Đây là con số XFinder nhận được từ chuột. Bấm “Ghi nút” rồi bấm đúng nút đó để đặt nó làm nút giữ.":
        ("This is the number XFinder received from your mouse. Click “Record button” and "
         "press that same button to make it the hold button.", "sentence"),

    # --- Page copy, revised for the measured-activity panel -------------------
    "Sẵn sàng — các ứng dụng bên dưới đã có phím tắt sẵn, không cần cấu hình thêm.":
        ("Ready — the applications below already have shortcuts, with nothing further to "
         "configure.", "sentence"),
    "Cử chỉ đang tắt. Bật công tắc ở góc trên để dùng; sơ đồ bên dưới đã có sẵn phím tắt.":
        ("Gestures are off. Turn on the switch at the top to use them; the diagram below "
         "already has shortcuts.", "sentence"),
    "Chọn một mũi tên để xem nó gửi gì. Số trên thân chuột là nút bạn giữ — bấm vào đó để đổi.":
        ("Pick an arrow to see what it sends. The number on the mouse body is the button "
         "you hold — click it to change.", "sentence"),
    "Mỗi mũi tên là một động tác: giữ nút trên thân chuột rồi kéo theo hướng đó. Bấm vào mũi tên để xem và đổi phím nó gửi.":
        ("Each arrow is one motion: hold the button on the mouse body and pull in that "
         "direction. Click an arrow to see and change the keys it sends.", "sentence"),
    "Ba bước: giữ nút → kéo quá ngưỡng → thả. Kéo chưa đủ xa thì XFinder phát lại click bình thường, nên không mất thao tác nào.":
        ("Three steps: hold the button → pull past the threshold → release. A pull that is "
         "too short replays the normal click, so no action is ever lost.", "sentence"),
    "Mặc định = preset dựng sẵn · Tự đặt = bạn đã đổi hướng đó · Chưa gán = cố ý không gửi phím. Chưa gán trên ứng dụng đã có preset sẽ không rơi về bảng toàn cục. Biểu tượng ⇄ nhỏ nghĩa là hướng đó chuyển tiếp cuộn ngang nguyên bản của chuột.":
        ("Preset = shipped default · Yours = you changed that direction · Unassigned = "
         "deliberately sends nothing. Unassigned on an app that has a preset never falls "
         "back to the Global table. The small ⇄ badge means that direction passes the "
         "mouse's own horizontal scroll straight through.", "sentence"),

    # --- Acceptance section (page head) ----------------------------------------
    # The two causes of "the gesture did not fire", stated as measurements. The wheel
    # warning is deliberately blunt because `mouseButton(2)` is what the shipped default
    # held, and it is a hold no hand can perform.
    "Kiểm tra nhanh": ("Quick check", "sentence"),
    "Hai nguyên nhân duy nhất khiến cử chỉ không chạy: nút giữ chưa đúng, hoặc XFinder đang là ứng dụng phía trước.":
        ("The only two reasons a gesture does not fire: the hold button is not the one you "
         "think, or XFinder is the app in front.", "sentence"),
    "Ghi lại nút giữ": ("Re-record hold button", "sentence"),
    "Đây là nút bấm con lăn. Giữ con lăn rồi kéo là thao tác tay không làm được — cử chỉ sẽ như không chạy. Bấm “Ghi lại nút giữ” rồi bấm một nút hông.":
        ("This is the wheel click. Holding the wheel while pulling cannot be done with a "
         "hand, so the gesture reads as dead. Click “Re-record hold button” and press a "
         "side button.", "sentence"),
    "Giữ nút này rồi kéo một trong bốn hướng. Con số là con số XFinder nhận được từ chuột, không phải tên cố định — mỗi chuột một khác.":
        ("Hold this button and pull in one of four directions. The number is the number "
         "XFinder receives from the mouse, not a fixed name — it differs per mouse.", "sentence"),
    "Đang dùng phím bổ trợ làm nút giữ. Giữ phím đó rồi kéo chuột để bắt đầu cử chỉ.":
        ("A modifier key is the hold trigger. Hold that key and move the mouse to start a "
         "gesture.", "sentence"),
    "Bạn vừa bấm": ("You just pressed", "fragment"),
    "Đặt nút này làm nút giữ?": ("Set it as the hold button?", "sentence"),
    "Đặt làm nút giữ": ("Use as hold button", "sentence"),
    "Cử chỉ sẽ gửi tới": ("Gestures will be sent to", "fragment"),
    "chưa xác định": ("not determined", "sentence"),
    "XFinder đang là ứng dụng phía trước, nên cử chỉ được tra theo chính XFinder. Hãy chuyển sang ứng dụng bạn muốn dùng (Zed, Chrome, Excel…) rồi thử lại — đây là lý do nhật ký bên dưới chỉ hiện com.xfinder.app.":
        ("XFinder is the app in front, so the gesture is resolved for XFinder itself. "
         "Switch to the app you mean to use (Zed, Chrome, Excel…) and try again — this is "
         "why the log below shows only com.xfinder.app.", "sentence"),
    "Bấm “Xem” ở mục dưới để mở đúng bảng của ứng dụng này.":
        ("Click “View” below to open this app's own table.", "sentence"),

    # --- Strings that are gone from the source ---------------------------------
    # Removed so a future sweep cannot silently re-introduce them, and so the
    # reachability audit does not report them as orphaned.
}

REMOVED = [
    "Nút trái (Button 0)",
    "Nút phải (Button 1)",
    "Nút giữa / bấm con lăn (Button 2)",
    "Nút hông sau — nút 4 (Button 3)",
    "Nút hông trước — nút 5 (Button 4)",
    "Nút chuột số ",
    " (Button ",
    "Giữ nút rồi kéo LÊN",
    "Giữ nút rồi kéo XUỐNG",
    "Giữ nút rồi kéo SANG TRÁI",
    "Giữ nút rồi kéo SANG PHẢI",
    "Nghiêng con lăn sang TRÁI (không giữ nút)",
    "Nghiêng con lăn sang PHẢI (không giữ nút)",
    # Superseded button notes. They mixed the *display* number with a physical
    # description, which is what made the table impossible to reason about, and they
    # were declared language-neutral so they leaked into the English UI.
    "Nút 1 (chuột trái)",
    "Nút 2 (chuột phải)",
    "Nút 3 (bấm con lăn xuống)",
    # Superseded 2026-09-23: the system actions no longer post an `NSEvent.systemDefined`
    # event (that keytype did not exist), so this row's copy is gone with the mechanism.
    # Removed rather than merely unused, so a future sweep cannot quietly re-introduce it.
    "gửi sự kiện hệ thống",
]


def main() -> int:
    doc = json.loads(STORE.read_text(encoding="utf-8"))
    entries = doc["entries"]
    before = len(entries)

    added = replaced = removed = 0
    for key, (en, scope) in ENTRIES.items():
        if key in entries:
            if entries[key].get("en") != en or entries[key].get("scope") != scope:
                entries[key] = {"en": en, "scope": scope}
                replaced += 1
        else:
            entries[key] = {"en": en, "scope": scope}
            added += 1

    for key in REMOVED:
        if key in entries:
            del entries[key]
            removed += 1

    doc["entries"] = dict(sorted(entries.items()))
    STORE.write_text(json.dumps(doc, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"entries {before} -> {len(doc['entries'])}  (added {added}, replaced {replaced}, removed {removed})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
