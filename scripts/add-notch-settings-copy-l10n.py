#!/usr/bin/env python3
"""XF-NOTCH-02 (2026-11-08) — copy for the rebuilt "Giao diện notch" Settings page.

The page was regrouped into the five sections of
docs/specs/XF-NOTCH-02-interface-settings-layout.md and gained the display-target controls defined by
XF-NOTCH-01. Existing keys keep their translations untouched.

Idempotent, ADD-ONLY (same contract as add-notch-p2-l10n-entries.py): an existing key is never rewritten;
a key that already exists with different English stops the script.
"""
from __future__ import annotations
import json, sys
from pathlib import Path

STORE = Path(__file__).resolve().parent.parent / "XFinder/Resources/L10n.strings.json"
S, F = "sentence", "fragment"
ENTRIES: dict[str, tuple[str, str]] = {
    # page header
    "Bật tắt notch, chọn cách nó mở, màn hình đích, hình dạng và quyền riêng tư, cùng các trang nó hiện.":
        ("Turn the notch on or off, choose how it opens, its target display, its shape and privacy, and the pages it shows.", S),
    # 1 — Bật/tắt
    "Bật/tắt": ("On/Off", S),
    "Đây là công tắc chính của toàn bộ bề mặt notch; các nhóm bên dưới chỉ chỉnh cách nó hiện và cách nó mở.":
        ("This is the master switch for the whole notch surface; the groups below only change how it looks and how it opens.", S),
    "Bật notch": ("Turn the notch on", S),
    "Tắt thì notch và các trang của nó biến mất khỏi màn hình. Những tính năng khác của XFinder — clipboard, chụp màn hình, sắp xếp cửa sổ, chuột và cử chỉ — vẫn chạy bình thường.":
        ("Off, the notch and its pages disappear from the screen. XFinder's other features — clipboard, screen capture, window snapping, mouse and gestures — keep working as usual.", S),
    "Notch đang tắt. Các nhóm còn lại bị khoá để thấy rõ chúng không có tác dụng; bật lại notch để chỉnh tiếp — không giá trị nào bị đặt lại.":
        ("The notch is off. The other groups are locked so it is clear they do nothing; turn the notch back on to keep adjusting — no value has been reset.", S),
    # 2 — Cách mở
    "Cách mở": ("How it opens", S),
    "Rê chuột và bấm là hai đường độc lập. Lối mở trang cụ thể — liên kết sâu, phím tắt, URL xfinder:// — luôn giữ đúng trang được yêu cầu. Trang đích đang bị tắt ở nhóm Trang và màu sẽ được thay bằng trang đang hiện.":
        ("Hover and click are two independent routes. An explicit page open — deep link, shortcut, xfinder:// URL — always keeps the page it asks for. A destination hidden in the Pages and colour group falls back to a page that is shown.", S),
    "Chọn một trang cố định, trang dùng lần cuối hoặc trang phù hợp hoạt động hiện tại. Áp dụng khi bấm huy hiệu hoặc dải xem nhanh.":
        ("Choose a fixed page, the last-used page, or the page that best fits current activity. Applies when clicking the badge or the peek strip.", S),
    # 3 — Màn hình đích
    "Màn hình đích": ("Target display", S),
    "Tự động giữ cách chạy hiện tại: theo con trỏ khi bạn đang thao tác, khi rảnh thì ở màn hình có notch cứng, không có thì ở màn hình chính. Màn hình tích hợp: không có notch cứng thì dùng màn hình chính và vẽ notch ảo. Màn hình chính: theo màn hình macOS đang đặt là chính, không xác định được thì dùng màn hình đầu tiên.":
        ("Automatic keeps today's behaviour: follows the pointer while you interact, and when idle uses the display with a physical notch, otherwise the main display. Built-in display: with no physical notch it uses the main display and draws the virtual notch. Main display: follows the display macOS currently treats as main, or the first one if that cannot be determined.", S),
    "Notch hiện trên": ("Show the notch on", S),
    "Tự động, màn hình có notch cứng, màn hình chính, hay một màn hình cụ thể.":
        ("Automatic, the display with a physical notch, the main display, or one specific display.", S),
    "Tự động": ("Automatic", S),
    "Màn hình tích hợp": ("Built-in display", S),
    "Màn hình chính": ("Main display", S),
    "Chọn màn hình…": ("Choose display…", S),
    "Giá trị đã lưu không nhận ra: ": ("Unrecognised saved value: ", F),
    "Màn hình đã chọn": ("Selected display", S),
    "Danh sách chỉ có màn hình đang kết nối. ID màn hình được giữ nguyên khi rút ra rồi cắm lại, và notch tự quay lại màn hình đó.":
        ("The list holds only connected displays. The display ID is kept when the display is unplugged and plugged back in, and the notch returns to it on its own.", S),
    "Chưa chọn màn hình": ("No display selected", S),
    "không kết nối": ("not connected", F),
    "Màn hình notch dùng khi rảnh": ("Display used while idle", S),
    "macOS chưa báo màn hình nào. Notch tạm ẩn và tự hiện lại khi có màn hình; lựa chọn đã lưu không bị xoá.":
        ("macOS reports no displays. The notch stays hidden and comes back when a display does; the saved choice is not cleared.", S),
    "Máy này không có màn hình với notch cứng. Notch dùng màn hình chính (hoặc màn hình dùng được đầu tiên) và vẽ notch ảo.":
        ("This Mac has no display with a physical notch. The notch uses the main display (or the first usable one) and draws the virtual notch.", S),
    "macOS chưa xác định được màn hình chính. Notch dùng màn hình dùng được đầu tiên.":
        ("macOS has not identified a main display. The notch uses the first usable display.", S),
    "Chưa chọn màn hình nào. Notch dùng màn hình chính (hoặc màn hình dùng được đầu tiên) cho tới khi bạn chọn một màn hình.":
        ("No display is selected yet. The notch uses the main display (or the first usable one) until you pick one.", S),
    "Màn hình đã chọn hiện không kết nối. Notch tạm dùng màn hình chính (hoặc màn hình dùng được đầu tiên); ID vẫn được giữ và notch tự quay lại khi màn hình kết nối lại.":
        ("The selected display is not connected. The notch temporarily uses the main display (or the first usable one); the ID is kept and the notch returns when that display reconnects.", S),
    # 4 — Hiển thị và quyền riêng tư
    "Hiển thị và quyền riêng tư": ("Display and privacy", S),
    "Bật thì cửa sổ notch đặt sharingType = none, nên macOS không đưa cửa sổ đó vào luồng chia sẻ (đo được kCGWindowSharingState = 0).":
        ("On, the notch window sets sharingType = none, so macOS leaves that window out of the sharing stream (measured: kCGWindowSharingState = 0).", S),
    "Đây là trạng thái chia sẻ của riêng cửa sổ notch, không phải bảo đảm cho mọi cách chụp: công cụ chụp khác, bản macOS khác hoặc cách chia sẻ khác có thể vẫn thấy notch.":
        ("This is the notch window's own sharing state, not a guarantee for every capture path: other capture tools, other macOS versions or other sharing methods may still show the notch.", S),
    # 5 — Trang và màu
    "Trang và màu": ("Pages and colour", S),
}


def main() -> None:
    data = json.loads(STORE.read_text(encoding="utf-8"))
    entries = data.get("entries", data)
    added, conflicts = 0, []
    for vi, (en, scope) in ENTRIES.items():
        cur = entries.get(vi)
        if cur is None:
            entries[vi] = {"en": en, "scope": scope}
            added += 1
        elif cur.get("en") != en or cur.get("scope") != scope:
            conflicts.append((vi, cur, en, scope))
    if conflicts:
        for vi, cur, en, scope in conflicts:
            print(f"CONFLICT {vi!r}: store has {cur!r}, script wants {{'en': {en!r}, 'scope': {scope!r}}}")
        print("Nothing written."); sys.exit(1)
    STORE.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Added {added} entries (0 rewritten). Total in store: {len(entries)}")


if __name__ == "__main__":
    main()
