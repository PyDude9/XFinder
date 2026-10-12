#!/usr/bin/env python3
"""N3 (2026-10-13) — AI agent sessions on the notch: register the feature's strings in the L10n store.

Idempotent: re-running changes nothing. Status keys come from `AgentSessionRules.statusKey` (a model
function — `L10n.t(variable)` at the call site, so the literal sweeps cannot see them; the test
`AgentSessionTests.testEveryStatusKeyIsInTheStore` resolves them instead).
"""

from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
STORE = ROOT / "XFinder/Resources/L10n.strings.json"

ENTRIES: dict[str, tuple[str, str]] = {
    # AgentSessionRules.statusKey — the trailing space on "Đang chạy " is the fragment joined to the tool name
    "Đang suy nghĩ": ("Thinking", "sentence"),
    "Đang chạy ": ("Running ", "fragment"),
    "Đang chờ bạn": ("Waiting for you", "sentence"),
    "Chờ bạn duyệt": ("Needs your approval", "sentence"),
    "Đã kết thúc": ("Ended", "sentence"),
    # settings section (DropTrayDetailView)
    "Agent AI": ("AI agents", "sentence"),
    "Agent AI trên notch": ("AI agents on the notch", "sentence"),
    "Các phiên Claude Code đang chạy trong terminal: đang làm gì, chờ bạn nhập hay chờ bạn duyệt quyền — duyệt ngay tại notch.": ("Your Claude Code sessions running in a terminal: what each is doing, whether it waits for your input or your approval — and approve right at the notch.", "sentence"),
    "Hiện phiên Claude Code ở notch": ("Show Claude Code sessions at the notch", "sentence"),
    "Đọc nhật ký do hook của XFinder ghi: tên sự kiện, công cụ, thư mục. Không đọc nội dung hội thoại, không gọi mạng. Mặc định tắt.": ("Reads the log XFinder's hook writes: event names, tools, folders. Never the conversation itself, never the network. Off by default.", "sentence"),
    "Hook Claude Code: ": ("Claude Code hook: ", "fragment"),
    "Gỡ hook": ("Remove hook", "sentence"),
    "Cài hook vào ~/.claude/settings.json": ("Install hook into ~/.claude/settings.json", "sentence"),
    "Cài hook = thêm các mục \"Managed by XFinder\" vào ~/.claude/settings.json (có bản sao lưu đặt cạnh) và chép một script zsh vào Application Support. Hook của app khác giữ nguyên. Mỗi sự kiện của Claude Code chạy script đó vài mili-giây. Khi Claude Code xin quyền, script chờ bạn bấm Cho phép hoặc Từ chối trên notch; XFinder không chạy thì Claude Code hỏi ở terminal như thường. Chỉ Claude Code trong terminal — app Claude để bàn không chạy hook.": ("Installing the hook adds \"Managed by XFinder\" entries to ~/.claude/settings.json (a backup is written beside it) and copies one zsh script into Application Support. Other apps' hooks are left alone. Every Claude Code event runs that script for a few milliseconds. When Claude Code asks for permission the script waits for you to press Allow or Deny on the notch; with XFinder not running, Claude Code asks in the terminal as usual. Terminal sessions only — the Claude desktop app runs no hooks.", "sentence"),
    "Đã cài": ("Installed", "sentence"),
    "Chưa cài": ("Not installed", "sentence"),
    "Thiếu một phần": ("Partly installed", "sentence"),
    "Không đọc được ~/.claude/settings.json": ("Cannot read ~/.claude/settings.json", "sentence"),
    "Đã cài hook. Phiên Claude Code mới sẽ hiện trên notch.": ("Hook installed. New Claude Code sessions will show at the notch.", "sentence"),
    "Đã gỡ hook.": ("Hook removed.", "sentence"),
    "Không đổi được hook: ": ("Could not change the hook: ", "fragment"),
    # notch page
    "Chưa có phiên Claude Code nào.": ("No Claude Code session yet.", "sentence"),
    "Chưa cài hook — mở Notch & Khay thả để cài.": ("Hook not installed — open Notch & Drop Tray to install it.", "sentence"),
    "Mở terminal": ("Open terminal", "sentence"),
    "Từ chối": ("Deny", "sentence"),
    "Cho phép": ("Allow", "sentence"),
    # N2 — hover-open picker (NotchHoverOpen.labelKey + the settings row)
    "Chỉ xem nhanh": ("Peek only", "sentence"),
    "Theo hoạt động": ("By activity", "sentence"),
    "Trang mở lần cuối": ("Last opened page", "sentence"),
    "Rê chuột vào notch mở": ("Resting on the notch opens", "sentence"),
    "Chỉ xem nhanh: dừng con trỏ hiện tệp đang giữ hoặc bài đang phát; khay trống không mở gì. Các lựa chọn khác mở thẳng trang đó. Theo hoạt động chọn trang theo việc đang diễn ra: agent chờ bạn → Agent AI, nhạc đang phát → Đang phát, có tệp → Khay, còn lại → Clipboard.": ("Peek only: resting the pointer shows the files you hold or the playing track; an empty tray opens nothing. The other choices open that page directly. By activity picks the page for what is going on: an agent waiting for you → AI agents, music playing → Now Playing, files held → Tray, otherwise → Clipboard.", "sentence"),
    # N6 — notch file actions: Sang PDF, OCR, Thu nhỏ (labels, failures, result lines)
    "Sang PDF": ("To PDF", "sentence"),
    "Thu nhỏ ảnh": ("Shrink image", "sentence"),      # NOT "Thu nhỏ": that key is Quick Look's "Zoom out"
    "Thu nhỏ ảnh còn ": ("Shrink image to ", "fragment"),
    "Không có ảnh hay PDF nào để ghép.": ("No image or PDF to combine.", "sentence"),
    "Không đọc được: ": ("Cannot read: ", "fragment"),
    "Không ghi được PDF: ": ("Cannot write the PDF: ", "fragment"),
    "Không thấy chữ nào trong: ": ("No text found in: ", "fragment"),
    "Đã nhận dạng ": ("Recognised ", "fragment"),
    " ký tự, đã sao chép và lưu .txt cạnh ảnh.": (" characters — copied, and saved as .txt beside the image.", "fragment"),
    "Giữ để chọn cỡ hoặc định dạng.": ("Press and hold to pick a size or a format.", "sentence"),
    # N4 — Glance (calendar) page, settings, permissions
    "Lịch": ("Calendar", "sentence"),
    "Lời nhắc": ("Reminders", "sentence"),
    "ÂL": ("lunar", "sentence"),
    "Mở Lịch": ("Open Calendar", "sentence"),
    "Tiếp theo: ": ("Up next: ", "fragment"),
    "trong ": ("in ", "fragment"),
    "Tham gia": ("Join", "sentence"),
    "Hôm nay không còn gì nữa.": ("Nothing more today.", "sentence"),
    "Cả ngày": ("All day", "sentence"),
    "Chào buổi sáng.": ("Good morning.", "sentence"),
    "Chào buổi chiều.": ("Good afternoon.", "sentence"),
    "Chào buổi tối.": ("Good evening.", "sentence"),
    "Chưa có quyền Lịch. Cấp quyền để thấy sự kiện hôm nay.": ("No Calendar access yet. Grant it to see today's events.", "sentence"),
    "Quyền Lịch bị từ chối — mở Cài đặt hệ thống ▸ Quyền riêng tư ▸ Lịch.": ("Calendar access was denied — open System Settings ▸ Privacy ▸ Calendars.", "sentence"),
    "Cấp quyền Lịch": ("Grant Calendar access", "sentence"),
    "Lịch trên notch": ("Calendar on the notch", "sentence"),
    "Hôm nay có gì, việc kế tiếp lúc mấy giờ, link họp để bấm vào — ngay tại notch.": ("What is on today, when the next thing is, a meeting link to click — right at the notch.", "sentence"),
    "Hiện trang Lịch ở notch": ("Show the Calendar page at the notch", "sentence"),
    "Sự kiện và lời nhắc có giờ trong ±5 ngày, đọc từ Lịch của macOS (EventKit). Không mạng, không ghi gì vào lịch của bạn. Cần quyền Lịch — trang sẽ hỏi khi bạn mở.": ("Events and timed reminders within ±5 days, read from the macOS Calendar (EventKit). No network, nothing written to your calendar. Needs Calendar access — the page asks when you open it.", "sentence"),
    "Ẩn sự kiện cả ngày": ("Hide all-day events", "sentence"),
    "Hôm nay có gì, việc kế tiếp và link họp — đọc từ Lịch của macOS, không mạng.": ("What is on today, the next thing and a meeting link — read from the macOS Calendar, no network.", "sentence"),
    "Cho trang Lịch trên notch đọc sự kiện của bạn. Chỉ đọc, không ghi, không mạng.": ("Lets the Calendar page at the notch read your events. Read only, never written, no network.", "sentence"),
    "Cho trang Lịch trên notch hiện lời nhắc có giờ. Chỉ đọc.": ("Lets the Calendar page at the notch show timed reminders. Read only.", "sentence"),
    # N8 — Now Playing shuffle / repeat (NowPlaying.ShuffleMode/RepeatMode labelKey + two menu tooltips)
    "Xáo trộn": ("Shuffle", "sentence"),
    "Lặp lại": ("Repeat", "sentence"),
    "Xáo trộn: tắt": ("Shuffle: off", "sentence"),
    "Xáo trộn album": ("Shuffle albums", "sentence"),
    "Xáo trộn bài hát": ("Shuffle songs", "sentence"),
    "Lặp lại: tắt": ("Repeat: off", "sentence"),
    "Lặp một bài": ("Repeat one", "sentence"),
    "Lặp tất cả": ("Repeat all", "sentence"),
    # feature catalog
    "Phiên Claude Code đang chạy trong terminal: trạng thái và duyệt quyền tại notch; đọc nhật ký hook cục bộ.": ("Claude Code sessions running in a terminal: status and permission approval at the notch; reads a local hook log.", "sentence"),
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
