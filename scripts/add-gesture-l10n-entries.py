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
    # --- Button names ---------------------------------------------------------
    # Buttons are numbered by macOS's own button number. The three every mouse
    # shares carry a short factual note; the rest are the plain number so no
    # invented anatomy ("hông sau", "bắn tỉa", "DPI") can reach the screen again.
    "Nút 1 (chuột trái)": ("Button 1 (left click)", "sentence"),
    "Nút 2 (chuột phải)": ("Button 2 (right click)", "sentence"),
    "Nút 3 (bấm con lăn xuống)": ("Button 3 (press the wheel down)", "sentence"),
    "Nút :number": ("Button :number", "sentence"),
    "Nút ": ("Button ", "fragment"),

    # --- Direction headings ---------------------------------------------------
    # Each heading names the held button, because a bare arrow does not.
    # The hint half is a fragment: `title(trigger:)` joins it to the button name.
    "kéo lên": ("pull up", "fragment"),
    "kéo xuống": ("pull down", "fragment"),
    "kéo sang trái": ("pull left", "fragment"),
    "kéo sang phải": ("pull right", "fragment"),
    "Nút 3: kéo lên": ("Button 3: pull up", "sentence"),
    "Nút 3: kéo xuống": ("Button 3: pull down", "sentence"),
    "Nút 3: kéo sang trái": ("Button 3: pull left", "sentence"),
    "Nút 3: kéo sang phải": ("Button 3: pull right", "sentence"),

    # --- Tilt honesty ---------------------------------------------------------
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
        ("Each arrow is one move: hold the button printed on the arrow and pull in that "
         "direction. Click it to see the keys it sends, and change them if you want.", "sentence"),
    "là nút bạn giữ để bắt đầu mọi cử chỉ — số trên mỗi mũi tên là nút đó":
        ("is the button you hold to start any gesture — the number on every arrow is that button",
         "sentence"),
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
