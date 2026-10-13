#!/usr/bin/env python3
"""P3 (2026-10-13) — the OneNotch-style settings shell: the NOTCH sidebar group and its six pages (Giao diện notch,
Khay thả, Đang phát, Agent AI, Lịch & lời nhắc, Hoạt động trực tiếp), the Phím tắt page and its shortcut catalog, the
feature pages that now link to it, and the notch master relabelled in the Features hub.

Idempotent, ADD-ONLY (same contract as add-smartselect-l10n-entries.py): an existing key is never rewritten; a key that
exists with different English stops the script and writes nothing.
"""
from __future__ import annotations
import json, sys
from pathlib import Path

STORE = Path(__file__).resolve().parent.parent / "XFinder/Resources/L10n.strings.json"
S, F = "sentence", "fragment"
ENTRIES: dict[str, tuple[str, str]] = {
    # sidebar + page titles (identical-by-design ones are on L10n.allowlist.json)
    "NOTCH": ("NOTCH", S),
    "Giao diện notch": ("Notch Interface", S),
    "Lịch & lời nhắc": ("Calendar & Reminders", S),
    "Hoạt động trực tiếp": ("Live Activities", S),
    # Features hub: dropTray.notchEnabled switches the WHOLE notch off
    "Notch": ("Notch", S),
    "Khay, Clipboard, Đang phát, Agent AI và Lịch ở notch. Tắt là tắt cả notch.":
        ("Tray, Clipboard, Now Playing, AI agents and Calendar at the notch. Off turns the whole notch off.", S),
    # What's New (the old note named the "Notch & Khay thả" page)
    "Chỉ xem nhanh, theo hoạt động, hay một trang cố định — một picker trong Giao diện notch.":
        ("Peek only, by activity, or a fixed page — one picker in Notch Interface.", S),
    # Giao diện notch
    "Bật tắt notch, chỉnh cách rê chuột mở nó, hình dạng trên từng loại màn hình và các trang nó hiện.":
        ("Turn the notch on or off, tune what a hover does, how it looks on each kind of screen, and which pages it shows.", S),
    "Rê chuột vào notch": ("Hover on the notch", S),
    "Nút chính của mọi hiệu ứng rê chuột trên notch. Tắt thì kéo file vào notch hoặc lắc khi đang kéo file vẫn mở được khay — chỉ riêng việc dừng con trỏ ở notch là không còn phản ứng.":
        ("The master switch for every notch hover effect. Off, a file drag into the notch or a shake while dragging still opens the tray — only resting the pointer on the notch stops reacting.", S),
    "Hình dạng": ("Shape", S),
    # Khay thả
    "Mở khay": ("Open the tray", S),
    "Notch đang tắt": ("The notch is off", S),
    "Khay sẽ không hiện ở notch cho tới khi bạn bật lại ở Giao diện notch.":
        ("The tray will not appear at the notch until you turn it back on in Notch Interface.", S),
    # Agent AI / Lịch & lời nhắc
    # review fixes: the notch-off banner on the split pages, the agent copy that matches what the hook logs
    "Mục này không hiện ở notch cho tới khi bạn bật lại notch ở Giao diện notch.":
        ("This does not appear at the notch until you turn the notch back on in Notch Interface.", S),
    "Đọc nhật ký do hook của XFinder ghi: tên sự kiện, công cụ, thư mục, câu lệnh bạn gõ và tóm tắt việc công cụ làm (lệnh, đường dẫn tệp) để hiện trên notch. Không đọc câu trả lời của Claude, không gọi mạng. Mặc định tắt.":
        ("Reads the log XFinder's hook writes: event name, tool, folder, the prompt you type and a summary of what the tool does (command, file path), to show at the notch. Never reads Claude's replies, never uses the network. Off by default.", S),
    "Chưa cài hook — mở trang Agent AI để cài.": ("Hook not installed — open the AI agents page to install it.", S),
    "Phiên Claude Code": ("Claude Code sessions", S),
    "Hạn mức Claude": ("Claude usage limit", S),
    "Trên notch": ("On the notch", S),
    "Báo trước cuộc họp": ("Meeting alerts", S),
    "Quyền truy cập": ("Access", S),
    # feature pages that now link to Phím tắt
    "Đổi phím tắt trong Phím tắt": ("Change shortcut in Shortcuts", S),
    "Xem trong Phím tắt": ("View in Shortcuts", S),
    "Màu mặc định cho lần sau": ("Default color for next time", S),
    "Độ dày nét cho lần sau": ("Stroke width for next time", S),
    "Khi bật, ⇧⌘G sẽ thay thế \"Find Next\" (tìm tiếp) trong mọi ứng dụng khác trên máy.":
        ("When on, ⇧⌘G replaces \"Find Next\" in every other app on this Mac.", S),
    "Chỉ hoạt động khi XFinder đang ở phía trước.": ("Only works while XFinder is in front.", S),
    # Phím tắt page
    "Xem mọi phím tắt XFinder đang dùng, đổi những phím đổi được, và phát hiện trùng lặp.":
        ("See every shortcut XFinder uses, change the ones that can change, and spot clashes.", S),
    "Chụp màn hình đang tắt.": ("Screen capture is off.", S),
    "Không có phím tắt mặc định — ⇧⌘3, ⇧⌘4, ⇧⌘5 vẫn là của macOS. Muốn dùng ⇧⌘3 và ⇧⌘4, hãy tắt hai phím đó của macOS trong Cài đặt hệ thống ▸ Bàn phím ▸ Phím tắt ▸ Ảnh màn hình.":
        ("No default shortcuts — ⇧⌘3, ⇧⌘4, ⇧⌘5 still belong to macOS. To use ⇧⌘3 and ⇧⌘4, turn those off in System Settings ▸ Keyboard ▸ Keyboard Shortcuts ▸ Screenshots.", S),
    "Mở trang Chụp & chú thích": ("Open the Capture & Annotate page", S),
    "Sau khi chụp, lưu file, định dạng, lịch sử": ("What happens after a capture, where files are saved, format, history", S),
    "Bảng lệnh đang tắt.": ("The command palette is off.", S),
    "Bảng lệnh toàn cục + ô tìm nhanh trong trang Tìm kiếm": ("Global command palette + the quick-search box on the Search page", S),
    "Phím tắt cố định": ("Fixed shortcuts", S),
    "Một phím tắt khác của XFinder": ("Another XFinder shortcut", S),
    "Trùng với quy ước ": ("Collides with the convention ", F),
    " — có thể làm hỏng phím đó ở app khác.": (" — may break that shortcut in other apps.", F),
    " — đổi phím khác để tránh xung đột.": (" — pick a different key to avoid the clash.", F),
    "Mọi lúc, trên toàn hệ thống": ("Anytime, system-wide", S),
    "Chỉ khi XFinder ở phía trước": ("Only while XFinder is in front", S),
    "Chỉ trong Finder": ("Only in Finder", S),
    "Cử chỉ chuột": ("Mouse gestures", S),
    "Giữ một nút chuột rồi kéo — không phải phím bàn phím": ("Hold a mouse button and drag — not a keyboard chord", S),
    "Phím kích hoạt giọng nói": ("Voice activation key", S),
    "Một phím modifier giữ hoặc bấm để nói — không phải một tổ hợp phím": ("A modifier key held or tapped to talk — not a key combination", S),
    # ShortcutCatalog entry titles (variable-passed: ShortcutCatalogTests resolves every one against this store)
    "Mở Clipboard ở notch hoặc khay nổi (theo Cài đặt Clipboard)":
        ("Open Clipboard at the notch or the floating shelf (per Clipboard Settings)", S),
    "Mở khay Clipboard nổi": ("Open the floating Clipboard shelf", S),
    "Xếp hàng Paste Stack từ 10 mục gần nhất rồi mở khay nổi":
        ("Queue the Paste Stack from the 10 most recent items, then open the floating shelf", S),
    "Dịch vùng chọn đang có trên màn hình": ("Translate the current on-screen selection", S),
    "Bắt dính nửa trái": ("Snap to the left half", S),
    "Bắt dính nửa phải": ("Snap to the right half", S),
    "Bắt dính toàn màn hình": ("Snap to fill the screen", S),
    "Bắt dính nửa dưới": ("Snap to the bottom half", S),
    "Bắt dính giữa màn hình": ("Snap to the centre", S),
    "Bắt dính một phần ba trái": ("Snap to the left third", S),
    "Bắt dính một phần ba giữa": ("Snap to the centre third", S),
    "Bắt dính một phần ba phải": ("Snap to the right third", S),
    "Giữ ⌘Q khoảng 1 giây để thoát": ("Hold ⌘Q for about 1 second to quit", S),
    "Chuyển đổi ứng dụng kèm xem trước cửa sổ": ("Switch apps with a window preview", S),
    "Cắt rồi dán trong Finder (⌘X sau đó ⌘V)": ("Cut then paste in Finder (⌘X then ⌘V)", S),
    "Delete chuyển vào Thùng rác trong Finder": ("Delete moves to the Trash in Finder", S),
    "Return mở mục đang chọn trong Finder": ("Return opens the selected item in Finder", S),
    "Mở trang Ghi chú": ("Open the Notes page", S),
    "Ghim hoặc bỏ ghim ghi chú đầu danh sách (chưa lưu trữ)": ("Pin or unpin the first note in the list (not archived)", S),
    "Spotlight của macOS": ("macOS Spotlight", S),
    "Find Next (quy ước Sửa ▸ Tìm ▸ Tìm tiếp của macOS/Cocoa)": ("Find Next (the macOS Edit ▸ Find ▸ Find Next convention)", S),
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
