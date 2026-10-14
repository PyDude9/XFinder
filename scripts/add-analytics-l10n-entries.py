#!/usr/bin/env python3
"""Opt-out anonymous analytics (2026-10-14): the About block, the one-time notice, and the privacy copy it changed.

Idempotent, ADD-ONLY: an existing key is never rewritten; a key that exists with different English stops the script
and writes nothing.
"""
from __future__ import annotations
import json, sys
from pathlib import Path

STORE = Path(__file__).resolve().parent.parent / "XFinder/Resources/L10n.strings.json"
S, F = "sentence", "fragment"
ENTRIES: dict[str, tuple[str, str]] = {
    # status lines (AnalyticsRules.statusKeys)
    "Đã từ chối — XFinder không gửi gì.": ("Refused — XFinder sends nothing.", S),
    "Bản này chưa có máy chủ nhận nên chưa gửi gì.": ("This build has no receiver configured, so nothing has been sent.", S),
    "Chưa gửi gì — XFinder sẽ báo cho bạn trước lần gửi đầu.": ("Nothing sent yet — XFinder will tell you before the first send.", S),
    "Chưa gửi gì — lần gửi đầu chờ 24 giờ sau khi bạn thấy thông báo.": ("Nothing sent yet — the first send waits 24 hours after you saw the notice.", S),
    "Đang bật — tối đa một bản mỗi ngày.": ("On — at most one report a day.", S),
    # About block
    "Phân tích ẩn danh": ("Anonymous analytics", S),
    "Để sửa lỗi và nâng cấp app cho đúng nhu cầu của người dùng, mỗi ngày XFinder gửi tối đa một bản thống kê ẩn danh về trải nghiệm: phiên bản app và macOS, loại máy, ngôn ngữ, tính năng đang bật, quyền đã cấp, số lần gặp từng mã lỗi và tóm tắt crash của chính XFinder.":
        ("To fix bugs and improve the app where people need it, XFinder sends at most one anonymous experience report a day: the app and macOS versions, the Mac model, the language, the features that are on, the permissions granted, how often each error code occurred, and summaries of XFinder's own crashes.", S),
    "Không bao giờ có: mã định danh máy hay người dùng, tên tệp, nội dung clipboard, ghi chú, tên cửa sổ, tài khoản. Mỗi lần gửi là một bản rời, không nối được với lần trước. Nơi nhận: TelemetryDeck (máy chủ trong EU, không lưu địa chỉ IP).":
        ("Never included: any identifier for the Mac or the person, file names, clipboard content, notes, window titles, accounts. Each report stands alone and cannot be linked to the previous one. Receiver: TelemetryDeck (servers in the EU, IP addresses not stored).", S),
    "Từ chối gửi phân tích ẩn danh": ("Refuse anonymous analytics", S),
    "Lần gửi gần nhất: ": ("Last sent: ", F),
    "Xem dữ liệu sẽ gửi": ("Show what would be sent", S),
    "Ẩn dữ liệu": ("Hide data", S),
    # one-time notice
    "XFinder gửi thống kê ẩn danh": ("XFinder sends anonymous statistics", S),
    "Để sửa lỗi và nâng cấp app cho đúng nhu cầu, mỗi ngày XFinder gửi tối đa một bản thống kê ẩn danh: phiên bản app và macOS, loại máy, ngôn ngữ, tính năng đang bật, quyền đã cấp, số lần gặp từng mã lỗi và tóm tắt crash của chính XFinder. Không có mã định danh, tên tệp, nội dung clipboard, ghi chú, tên cửa sổ hay tài khoản; mỗi lần gửi là một bản rời. Lần gửi đầu sau 24 giờ. Bạn từ chối được bất cứ lúc nào ở Giới thiệu ▸ Hỗ trợ & báo lỗi.":
        ("To fix bugs and improve the app where it matters, XFinder sends at most one anonymous report a day: the app and macOS versions, the Mac model, the language, the features that are on, the permissions granted, how often each error code occurred, and summaries of XFinder's own crashes. No identifier, file names, clipboard content, notes, window titles or accounts; each report stands alone. The first one is sent after 24 hours. You can refuse at any time in About ▸ Support & bug reports.", S),
    "Đã hiểu": ("Got it", S),
    "Từ chối gửi": ("Don't send", S),
    "Xem dữ liệu…": ("Show the data…", S),
    # privacy copy that is no longer "nothing is ever sent"
    "XFinder kết hợp quản lý clipboard và giám sát hệ thống theo thời gian thực trong một ứng dụng macOS gọn nhẹ. Clipboard, ghi chú và tệp của bạn không bao giờ rời khỏi máy.":
        ("XFinder combines clipboard management and real-time system monitoring in one lightweight macOS app. Your clipboard, notes and files never leave the Mac.", S),
    "Báo cáo lỗi chỉ rời máy khi bạn tự sao chép, lưu hoặc dán nó — sau khi đã đọc toàn bộ.":
        ("A bug report leaves this Mac only when you copy, save or paste it — after reading all of it.", S),
    "Chỉ mã lỗi, phiên bản và crash của chính XFinder — không tên tệp, không nội dung clipboard, không tên cửa sổ hay tài khoản. Nhật ký nằm trên máy; bản thống kê ẩn danh bên dưới chỉ mang số lần gặp từng mã lỗi.":
        ("Only error codes, versions and XFinder's own crashes — no file names, no clipboard content, no window titles or accounts. The log stays on this Mac; the anonymous report below carries only how often each error code occurred.", S),
    "XFinder kết hợp quản lý clipboard và giám sát hệ thống theo thời gian thực trong một ứng dụng macOS gọn nhẹ. Clipboard, ghi chú và tệp của bạn nằm trên máy; chúng chỉ rời máy qua một tính năng bạn tự bật hoặc tự bấm (xem trước liên kết, giọng nói qua API, chia sẻ, kết nối từ xa).":
        ("XFinder combines clipboard management and real-time system monitoring in one lightweight macOS app. Your clipboard, notes and files stay on this Mac; they leave it only through a feature you turn on or press yourself (link previews, voice through an API, sharing, remote connect).", S),
    "Lịch sử clipboard nằm trên máy này và không được tải lên server nào. Xem trước liên kết, nếu bạn bật, chỉ mở chính liên kết đó để lấy tiêu đề và ảnh.":
        ("Clipboard history stays on this Mac and is not uploaded to any server. Link previews, if you turn them on, open only that link to fetch its title and image.", S),
    "Chỉ mã lỗi, phiên bản và crash của chính XFinder — không tên tệp, không nội dung clipboard, không tên cửa sổ hay tài khoản. Nhật ký nằm trên máy. Tắt công tắc này thì bản thống kê ẩn danh bên dưới cũng không mang số lần gặp lỗi hay tóm tắt crash.":
        ("Only error codes, versions and XFinder's own crashes — no file names, no clipboard content, no window titles or accounts. The log stays on this Mac. With this switch off, the anonymous report below carries no error counts and no crash summaries either.", S),
    "Không bao giờ có: mã định danh máy hay người dùng, tên tệp, nội dung clipboard, ghi chú, tên cửa sổ, tài khoản. Mỗi lần gửi là một bản rời, không nối được với lần trước. Nơi nhận: TelemetryDeck — theo chính sách của họ, dữ liệu lưu tại EU và địa chỉ IP không được lưu (như mọi kết nối mạng, máy nhận vẫn thấy IP lúc nhận).":
        ("Never included: any identifier for the Mac or the person, file names, clipboard content, notes, window titles, accounts. Each report stands alone and cannot be linked to the previous one. Receiver: TelemetryDeck — by its own policy, data is stored in the EU and IP addresses are not stored (like any network request, the receiver still sees the IP while receiving).", S),
    "Lịch sử clipboard nằm trên máy này và không bao giờ được gửi lên server.":
        ("Clipboard history stays on this Mac and is never sent to a server.", S),
}

def main() -> int:
    data = json.loads(STORE.read_text(encoding="utf-8"))
    entries = data["entries"]
    conflicts = [k for k, (en, _) in ENTRIES.items() if k in entries and entries[k].get("en") != en]
    if conflicts:
        for k in conflicts:
            print(f"CONFLICT: {k!r} already means {entries[k].get('en')!r}")
        return 1
    added = 0
    for k, (en, scope) in ENTRIES.items():
        if k not in entries:
            entries[k] = {"en": en, "scope": scope}
            added += 1
    STORE.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"added {added}, already present {len(ENTRIES) - added}")
    return 0

if __name__ == "__main__":
    sys.exit(main())
