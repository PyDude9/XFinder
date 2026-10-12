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
    # N7 — onboarding + What's New (OnboardingRules keys + window chrome)
    "Có gì mới trong ": ("What's new in ", "fragment"),
    # "Mở trang " already exists ("Open page ") — reused, not redefined
    "Mở": ("Open", "sentence"),
    "Xong": ("Done", "sentence"),
    "Notch mượt hơn": ("A smoother notch", "sentence"),
    "Một cửa sổ cố định cho mọi trạng thái — hub mở ra từ notch, không còn giật khi đổi trang.": ("One fixed window for every state — the hub grows out of the notch, no more jump when the page changes.", "sentence"),
    "Rê chuột vào notch mở gì là tuỳ bạn": ("What a hover opens is your call", "sentence"),
    "Chỉ xem nhanh, theo hoạt động, hay một trang cố định — một picker trong Notch & Khay thả.": ("Peek only, by activity, or a fixed page — one picker in Notch & Drop Tray.", "sentence"),
    "Phiên Claude Code trên notch": ("Claude Code sessions at the notch", "sentence"),
    "Trạng thái từng phiên và nút Cho phép / Từ chối cho yêu cầu quyền, qua hook công khai của Claude Code.": ("Each session's status and Allow / Deny for permission requests, through Claude Code's public hooks.", "sentence"),
    "Trang Lịch": ("The Calendar page", "sentence"),
    "Hôm nay có gì, việc kế tiếp, lịch âm theo giờ Việt Nam, nút Tham gia cho link họp.": ("What is on today, the next thing, the lunar date on Vietnam time, a Join button for meeting links.", "sentence"),
    "Thêm việc cho tệp đang giữ": ("More to do with held files", "sentence"),
    "Sang PDF, OCR, Thu nhỏ ảnh với preset khi giữ chuột — bên cạnh ZIP, Gộp PDF, Tách nền, AirDrop.": ("To PDF, OCR, Shrink image with presets on press-and-hold — beside ZIP, Merge PDFs, Remove background, AirDrop.", "sentence"),
    "Tua, xáo trộn, lặp lại": ("Seek, shuffle, repeat", "sentence"),
    "Kéo thanh tiến trình để tua; xáo trộn và lặp lại trong menu của trang Đang phát.": ("Drag the progress bar to seek; shuffle and repeat in the Now Playing page's menus.", "sentence"),
    "Thư viện Clipboard và bảng khoá": ("Clipboard Library and locked boards", "sentence"),
    "Mọi clip từng copy, lọc theo loại / app / bảng / thời gian; bảng khoá mã hoá bằng Secure Enclave, mở từng thẻ bằng Touch ID.": ("Every clip you ever copied, filtered by type / app / board / time; locked boards encrypted with the Secure Enclave, each card unlocked with Touch ID.", "sentence"),
    # N5a — translate selection (⇧⌘G)
    "Dịch vùng chọn": ("Translate selection", "sentence"),
    "Dịch vùng chọn (⇧⌘G)": ("Translate selection (⇧⌘G)", "sentence"),
    "Bôi đen chữ ở app bất kỳ, bấm ⇧⌘G: bản dịch của Apple ngay trên máy, không mạng.": ("Select text in any app, press ⇧⌘G: Apple's translation, on this Mac, no network.", "sentence"),
    "Bật phím ⇧⌘G dịch vùng chọn": ("Enable ⇧⌘G to translate the selection", "sentence"),
    "Đọc chữ đang bôi đen qua Trợ năng rồi mở hộp dịch của Apple (macOS 15+). Không gửi gì đi; gói ngôn ngữ tải một lần theo cặp. App nào không cho Trợ năng đọc vùng chọn thì panel nói rõ.": ("Reads the selected text through Accessibility and opens Apple's translation popover (macOS 15+). Nothing is sent anywhere; a language pack downloads once per pair. When an app does not expose its selection to Accessibility, the panel says so.", "sentence"),
    "Dịch": ("Translate", "sentence"),
    "Sao chép bản dịch": ("Copy translation", "sentence"),
    "Bản dịch của Apple chạy trên máy; lần đầu mỗi cặp ngôn ngữ macOS sẽ hỏi tải gói ngôn ngữ. Bấm \"Thay thế\" trong hộp dịch để nhận bản dịch về đây.": ("Apple's translation runs on this Mac; the first time for each language pair macOS offers to download its pack. Press \"Replace\" in the popover to bring the translation here.", "sentence"),
    "Dịch tại chỗ cần macOS 15 trở lên (Translation framework của Apple).": ("In-place translation needs macOS 15 or later (Apple's Translation framework).", "sentence"),
    "Chọn ít nhất hai ký tự để dịch.": ("Select at least two characters to translate.", "sentence"),
    "Vùng chọn quá dài để dịch tại chỗ (tối đa 5 000 ký tự).": ("The selection is too long to translate in place (5,000 characters at most).", "sentence"),
    "Không đọc được vùng chọn: app này không cho Trợ năng đọc, hoặc chưa cấp quyền Trợ năng.": ("Could not read the selection: this app does not expose it to Accessibility, or Accessibility is not granted.", "sentence"),
    # D4b — link previews (opt-in network)
    "Xem trước liên kết (mạng)": ("Link previews (network)", "sentence"),
    "Tiêu đề và ảnh cho link đã copy, tải từ chính trang đó; mặc định tắt.": ("Title and image for copied links, fetched from the page itself; off by default.", "sentence"),
    "Tải xem trước liên kết (mạng)": ("Fetch link previews (network)", "sentence"),
    "Với mỗi link bạn copy, XFinder gửi một yêu cầu tới chính trang đó để lấy tiêu đề và ảnh (LinkPresentation của Apple). Đây là lần duy nhất clipboard chạm mạng; mặc định tắt. Không bao giờ tải link tới localhost hay mạng nội bộ.": ("For every link you copy, XFinder sends one request to that page for its title and image (Apple's LinkPresentation). It is the only time the clipboard touches the network; off by default. Links to localhost or a private network are never fetched.", "sentence"),
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
