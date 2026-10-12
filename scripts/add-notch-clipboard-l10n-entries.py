#!/usr/bin/env python3
"""D0 — the ⌘⇧V shelf consolidated into the notch: register the page's new strings in the L10n store.

Idempotent: re-running changes nothing. Every string here is a literal that reaches the screen through
`L10n.t("…")` in NotchClipboardView / NotchClipCardView / SettingsDetailView / NotchSurfaceController.
"""

from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
STORE = ROOT / "XFinder/Resources/L10n.strings.json"

ENTRIES: dict[str, tuple[str, str]] = {
    # Settings — one picker, one key
    "⌘⇧V mở ở": ("⌘⇧V opens in", "sentence"),
    "Ở notch": ("At the notch", "sentence"),
    "Khay nổi cũ": ("Old floating shelf", "sentence"),
    "Lịch sử copy mở bằng ⌘⇧V, ở notch hoặc khay nổi.": ("Copy history opens with ⌘⇧V, at the notch or in the floating shelf.", "sentence"),
    "⌘⇧V mở clipboard trên mọi ứng dụng": ("⌘⇧V opens the clipboard over any app", "sentence"),
    "Mở clipboard (⌘⇧V)": ("Open clipboard (⌘⇧V)", "sentence"),
    # Notch page
    "↩ dán · ⇧↩ thuần · Space xem · ⌘P ghim · ⌘⌫ xoá · ⌘1–9 bảng": ("↩ paste · ⇧↩ plain · Space view · ⌘P pin · ⌘⌫ delete · ⌘1–9 boards", "sentence"),
    "Chưa có Trợ năng: ↩ chỉ sao chép, dán bằng ⌘V.": ("No Accessibility yet: ↩ only copies, paste with ⌘V.", "sentence"),
    "Mục này không có tệp để xem nhanh.": ("This item has no file to Quick Look.", "sentence"),
    "Đi tới nguồn": ("Go to source", "sentence"),
    # Card footer age — the existing " phút" fragment means " min LEFT" (the notch timer), so the
    # clip age gets its own unit words, joined to the number by the view.
    "Vừa xong": ("Just now", "sentence"),
    "phút": ("min", "fragment"),
    "giờ": ("h", "fragment"),
    "ngày": ("d", "fragment"),
    # History limit (user: 20 · 100 · 1000)
    "20 mục": ("20 items", "sentence"),
    "100 mục": ("100 items", "sentence"),
    # D0c: plain screens get a virtual notch at the top edge (B7 hung the surfaces under the menu bar)
    "Trên màn hình không có notch, XFinder vẽ một notch ảo: các bề mặt dính mép trên, ở giữa thanh menu, y như ở notch thật; rê chuột vào giữa mép trên để xem các tệp đang giữ.": ("On a screen without a notch XFinder draws a virtual one: the surfaces sit flush with the top edge, centred in the menu bar, exactly as at a real notch; rest the pointer on the middle of the top edge to see the files you are holding.", "sentence"),
    "Màn hình ngoài / iMac: tệp đang giữ, hẹn giờ và bài đang phát hiện trong một viên thuốc nhỏ dính mép trên, giữa thanh menu. Chưa đo trên màn hình thật — chỉ hình học.": ("External display / iMac: held files, the timer and the playing track show in a small pill flush with the top edge, centred in the menu bar. Not measured on a real display yet — geometry only.", "sentence"),
    # D1 quick wins
    "Tạm dừng ghi clipboard": ("Pause clipboard recording", "sentence"),
    "Không ghi gì vào lịch sử cho tới khi bật lại. ⌘⇧V vẫn mở được; trang notch báo đang tạm dừng.": ("Nothing is recorded until you turn this off. ⌘⇧V still opens; the notch page says recording is paused.", "sentence"),
    "Đang tạm dừng ghi clipboard.": ("Clipboard recording is paused.", "sentence"),
    "Âm sao chép": ("Copy sound", "sentence"),
    "Sửa văn bản…": ("Edit text…", "sentence"),
    "Sửa văn bản": ("Edit text", "sentence"),
    "Phát âm": ("Speak", "sentence"),
    "Dừng phát âm": ("Stop speaking", "sentence"),
    "Ghim khay (không đóng khi bấm ra ngoài)": ("Pin the shelf (stays open when you click outside)", "sentence"),
    "Bỏ ghim khay": ("Unpin the shelf", "sentence"),
    # D1 group 2: pages on the notch, accent
    "Các trang trên notch": ("Pages on the notch", "sentence"),
    "Bật, tắt và sắp xếp thứ tự các tab trong hub. Tắt Clipboard thì ⌘⇧V mở khay nổi cũ. Vuốt hai ngón ngang trên dải tab để đổi trang.": ("Turn the hub's tabs on or off and order them. With Clipboard off, ⌘⇧V opens the old floating shelf. Swipe sideways with two fingers over the tab band to change page.", "sentence"),
    "Lên": ("Up", "sentence"),
    "Xuống": ("Down", "sentence"),
    "Màu nhấn": ("Accent colour", "sentence"),
    "Màu của viền chọn, thẻ đang chọn và các điểm nhấn trên notch.": ("The colour of the focus ring, the selected card and the highlights on the notch.", "sentence"),
    "Theo hệ thống": ("System", "sentence"),
    "Xanh dương": ("Blue", "sentence"),
    "Tím": ("Purple", "sentence"),
    "Hồng": ("Pink", "sentence"),
    "Cam": ("Orange", "sentence"),
    "Xanh lá": ("Green", "sentence"),
    "Xanh ngọc": ("Teal", "sentence"),
    # D: ⌘⌥C switch, MCP section
    "Phím ⌘⌥C mở khay nổi cũ": ("⌘⌥C opens the old floating shelf", "sentence"),
    "Tắt mặc định. Bật nếu muốn khay nổi dưới màn hình song song với notch.": ("Off by default. Turn on if you want the floating shelf at the bottom of the screen alongside the notch.", "sentence"),
    "Clipboard MCP cho agent AI": ("Clipboard MCP for AI agents", "sentence"),
    "Claude Code, Cursor, Codex đọc được lịch sử clipboard qua MCP. Chỉ đọc, chỉ văn bản, không bao giờ trả mục từ trình quản lý mật khẩu; tắt công tắc thì mọi lệnh trả lỗi.": ("Claude Code, Cursor and Codex can read the clipboard history over MCP. Read-only, text only, never an item from a password manager; with the switch off every call returns an error.", "sentence"),
    "Cho phép agent đọc clipboard qua MCP": ("Let agents read the clipboard over MCP", "sentence"),
    "Đã sao chép": ("Copied", "sentence"),
    "Dán đoạn này vào cấu hình MCP của agent (Claude Code: ~/.claude.json hoặc .mcp.json). Server chạy khi agent khởi động nó; XFinder không mở cổng mạng nào.": ("Paste this into the agent's MCP configuration (Claude Code: ~/.claude.json or .mcp.json). The server runs when the agent starts it; XFinder opens no network port.", "sentence"),
    # D: .xfinderclip export / import
    "Sao lưu & chuyển máy": ("Backup & move to another Mac", "sentence"),
    "Xuất toàn bộ lịch sử và bảng ghim, kèm ảnh, thành một tệp .xfinderclip. Nhập không ghi đè mục đang có. Mục từ trình quản lý mật khẩu không bao giờ được xuất.": ("Export the whole history and the boards, with images, as one .xfinderclip file. Importing never overwrites existing items. Items from password managers are never exported.", "sentence"),
    "Xuất tệp .xfinderclip…": ("Export .xfinderclip file…", "sentence"),
    "Nhập tệp .xfinderclip…": ("Import .xfinderclip file…", "sentence"),
    " tệp đính kèm": (" attached files", "fragment"),
    " tệp không còn trên đĩa": (" files no longer on disk", "fragment"),
    "bỏ qua ": ("skipped ", "fragment"),
    " mục từ trình quản lý mật khẩu": (" items from password managers", "fragment"),
    " mục trùng": (" duplicates", "fragment"),
    " bảng mới": (" new boards", "fragment"),
    " mục ảnh thiếu tệp": (" image items missing their file", "fragment"),
    "Tệp này không phải tệp .xfinderclip hợp lệ.": ("This is not a valid .xfinderclip file.", "sentence"),
    "Tệp được xuất từ bản XFinder mới hơn. Hãy cập nhật XFinder.": ("This file was exported by a newer XFinder. Update XFinder first.", "sentence"),
    "Không thực hiện được: ": ("Could not finish: ", "fragment"),
}


def main() -> None:
    with open(STORE, "r", encoding="utf-8") as f:
        data = json.load(f)
    entries = data.get("entries", data)
    added = updated = 0
    for vi, (en, scope) in ENTRIES.items():
        cur = entries.get(vi)
        if cur is None:
            entries[vi] = {"en": en, "scope": scope}
            added += 1
        elif cur.get("en") != en or cur.get("scope") != scope:
            cur["en"], cur["scope"] = en, scope
            updated += 1
    with open(STORE, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write("\n")
    print(f"Added {added}, updated {updated} entries. Total in store: {len(entries)}")


if __name__ == "__main__":
    main()
