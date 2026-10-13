#!/usr/bin/env python3
"""E5 (2026-10-13) — Smart Selection: register the page, badge, panel and catalog strings in the L10n store.

Idempotent, ADD-ONLY: an existing key is never rewritten (the N6/N7 lesson — an "updated 1" from an entry script was
a silent rewrite of someone else's key). If a key exists with a different English text the script stops and prints
it, instead of overwriting. Notice keys come from `SmartSelectionRules.NoticeKey` (they reach the screen through
`L10n.t(variable)`; `SmartSelectionRulesTests.testEveryNoticeKeyIsTranslated` resolves them).
"""
from __future__ import annotations
import json, sys
from pathlib import Path

STORE = Path(__file__).resolve().parent.parent / "XFinder/Resources/L10n.strings.json"
S, F = "sentence", "fragment"
ENTRIES: dict[str, tuple[str, str]] = {
    # catalog + sidebar + page header
    "Chọn văn bản thông minh": ("Smart Selection", S),
    "Bôi đen chữ ở app khác: nút nhỏ đổi đơn vị, đổi múi giờ, tính, thêm vào Lịch, dịch.":
        ("Select text in another app: a small button converts units and time zones, calculates, adds to Calendar, translates.", S),
    "Bôi đen chữ ở app khác: một nút nhỏ hiện cạnh đó để đổi đơn vị, đổi múi giờ, tính, thêm vào Lịch hoặc dịch.":
        ("Select text in another app: a small button appears beside it to convert units or time zones, calculate, add to Calendar or translate.", S),
    # page — the button
    "Nút trên vùng chọn": ("Button on the selection", S),
    "Chỉ hiện khi bạn bôi đen bằng chuột và vùng chọn đã đứng yên.":
        ("Appears only when you select with the mouse and the selection has stopped changing.", S),
    "Hiện nút khi bôi đen chữ": ("Show a button when text is selected", S),
    "Đọc vùng chọn của app đang dùng qua Trợ năng. Không ghi lại, không gửi đi; chữ chỉ được giữ tới lần bôi đen kế tiếp.":
        ("Reads the frontmost app's selection through Accessibility. Nothing is recorded or sent; the text is kept only until the next selection.", S),
    "Cần quyền Trợ năng để đọc vùng chọn của app khác.": ("Accessibility permission is needed to read other apps' selections.", S),
    "Cấp quyền Trợ năng": ("Grant Accessibility", S),
    "Độ dài tối thiểu (ký tự)": ("Minimum length (characters)", S),
    "Bỏ qua vùng chọn ngắn hơn để nút không hiện khi bấm nhầm.":
        ("Shorter selections are ignored so a stray click does not show the button.", S),
    "Vùng chọn bằng bàn phím không hiện nút vì không biết nó nằm đâu trên màn hình — dùng ⇧⌘G. Một số app không cho Trợ năng đọc vùng chọn; khi đó nút không hiện.":
        ("A keyboard selection does not show the button because its place on screen is unknown — use ⇧⌘G. Some apps do not let Accessibility read their selection; there the button does not appear.", S),
    # page — excluded apps
    "Không hiện trong các app này": ("Never in these apps", S),
    "Trình chỉnh ảnh, bảng vẽ, game — nơi kéo chuột không phải là bôi đen chữ. Trình quản lý mật khẩu luôn bị bỏ qua.":
        ("Image editors, canvases, games — where dragging is not selecting text. Password managers are always skipped.", S),
    "Chưa loại trừ app nào.": ("No apps excluded.", S),
    "Bỏ": ("Remove", S),
    "Thêm app đang chạy": ("Add a running app", S),
    # page — what it does
    "Nút làm được gì": ("What the button does", S),
    "Chỉ hiện những việc hợp với chữ đã chọn, việc cụ thể nhất lên đầu.": ("Only what fits the selected text, the most specific first.", S),
    "Đổi đơn vị": ("Convert units", S),
    "Đổi múi giờ": ("Convert time zones", S),
    "Tính": ("Calculate", S),
    "Thêm vào Lịch": ("Add to Calendar", S),
    "Họp nhóm thứ Sáu 9 giờ": ("Team meeting Friday 9am", S),
    "macOS 15 trở lên, ngay trên máy": ("macOS 15 or later, on device", S),
    "Múi giờ viết tắt có nhiều nghĩa (CST, IST, BST…) bị bỏ qua thay vì đoán. EST, PST… dùng đúng định nghĩa; nếu vùng đó đang dùng giờ mùa hè, panel ghi chú. Thêm vào Lịch chỉ ghi khi bạn bấm nút, và hỏi quyền Lịch lần đầu.":
        ("Ambiguous time-zone abbreviations (CST, IST, BST…) are skipped instead of guessed. EST, PST… use their definition; when that region is on daylight time, the panel says so. Add to Calendar writes only when you press the button, and asks for Calendar access the first time.", S),
    # badge + panel
    "Việc XFinder làm được với vùng chọn này": ("What XFinder can do with this selection", S),
    "Vùng chọn": ("Selection", S),
    "Sự kiện mới": ("New event", S),
    "Dịch bằng bản dịch của Apple, ngay trên máy": ("Translate with Apple's on-device translation", S),
    "Dịch…": ("Translate…", S),
    "Cần macOS 15": ("Needs macOS 15", S),
    # fragments joined to runtime values (clock, city, offset, date)
    " · giờ máy ": (" · your time ", F),
    "Lưu ý: ": ("Note: ", F),
    " hiện dùng ": (" is on ", F),
    " lúc này.": (" right now.", F),
    " hôm sau": (" next day", F),
    " hôm trước": (" previous day", F),
    " (cả ngày)": (" (all day)", F),
    # SmartSelectionRules.NoticeKey (copied: "Đã sao chép." already exists)
    "XFinder chưa được phép ghi vào Lịch.": ("XFinder is not allowed to write to Calendar.", S),
    "Không tìm thấy lịch mặc định để ghi.": ("No default calendar to write to.", S),
    "Đã thêm vào Lịch.": ("Added to Calendar.", S),
    "Không thêm được vào Lịch.": ("Could not add to Calendar.", S),
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
