#!/usr/bin/env python3
"""XF-T29 Free/Pro (2026-10-24). ADD-ONLY: a key already present with another meaning is a CONFLICT."""
from __future__ import annotations
import json, sys
from pathlib import Path
STORE = Path(__file__).resolve().parent.parent / "XFinder/Resources/L10n.strings.json"
S = "sentence"
F = "fragment"
ENTRIES = {
    "XFinder Pro": ("XFinder Pro", S),
    "Pro": ("Pro", S),
    "Bản miễn phí đủ dùng hằng ngày; Pro mở giới hạn cho việc nặng — quy mô, tự động hoá, bảo mật, AI agent.":
        ("The free version covers everyday use; Pro lifts the limits for heavy work — scale, automation, security, AI agents.", S),
    "Bản phát triển: luôn đầy đủ": ("Development build: always full", S),
    "Khoá giấy phép": ("Licence key", S),
    "Khoá được kiểm ngay trên máy, không cần mạng và không cần tài khoản.": ("The key is checked on this Mac — no network, no account.", S),
    "Đã kích hoạt cho ": ("Activated for ", F),
    "Gỡ khoá": ("Remove key", S),
    "Dán khoá XF1-…": ("Paste an XF1-… key", S),
    "Kích hoạt": ("Activate", S),
    "Khoá không hợp lệ.": ("This key is not valid.", S),
    "Bản miễn phí": ("Free version", S),
    "Lịch sử ảnh chụp": ("Capture history", S),
    " ảnh": (" captures", F),
    "Ngăn trong trình duyệt tệp": ("Panes in the file browser", S),
    " ngăn": (" panes", F),
    "Liên kết Chia sẻ nhanh cùng lúc": ("Quick Share links at a time", S),
    " liên kết": (" links", F),
    "Vượt giới hạn thì phần cũ hơn bị ẩn, không bị xoá — mở Pro là thấy lại.":
        ("Beyond a limit the older part is hidden, never deleted — Pro shows it again.", S),
    "Pro thêm gì": ("What Pro adds", S),
    "Thử giới hạn (bản phát triển)": ("Try the limits (development build)", S),
    "Bản phát triển luôn đầy đủ; chọn một bậc ở đây để thử các cổng giới hạn.":
        ("A development build is always full; pick a tier here to try the gates.", S),
    "Không giả lập": ("Not simulating", S),
    "Miễn phí": ("Free", S),
    "Dùng thử": ("Trial", S),
    "Dùng thử Pro — còn ": ("Pro trial — ", F),
    "Cần XFinder Pro": ("Needs XFinder Pro", S),
    "Cần XFinder Pro — bấm để xem": ("Needs XFinder Pro — click to see", S),
    # ProFeature.titleKey (through L10n.t(variable) — ProEntitlementTests walks them)
    "Lịch sử Clipboard không giới hạn": ("Unlimited clipboard history", S),
    "Lịch sử ảnh chụp không giới hạn": ("Unlimited capture history", S),
    "Bảng khoá Clipboard": ("Locked clipboard board", S),
    "Máy chủ MCP Clipboard cho AI agent": ("Clipboard MCP server for AI agents", S),
    "Trình duyệt tệp tới 16 ngăn": ("Up to 16 panes in the file browser", S),
    "Shelf trong trình duyệt tệp": ("Shelf in the file browser", S),
    "Workspace có tên": ("Named workspaces", S),
    "Hàng đợi nhiều thao tác chép": ("A queue of copy operations", S),
    "Tải về và gỡ đám mây hàng loạt": ("Download and remove cloud files in bulk", S),
    "Phiên agent không cửa sổ": ("Windowless agent sessions", S),
    "Chuyển phiên agent": ("Agent handoff", S),
    "Khoá thư mục": ("Folder Lock", S),
    "Chia sẻ nhanh không giới hạn liên kết": ("Quick Share with unlimited links", S),
    "Tinh chỉnh giọng nói bằng AI": ("AI voice refinement", S),
}
def main() -> int:
    data = json.loads(STORE.read_text(encoding="utf-8")); e = data["entries"]
    bad = [k for k, (en, _) in ENTRIES.items() if k in e and e[k].get("en") != en]
    for k in bad: print(f"CONFLICT: {k!r} = {e[k].get('en')!r}")
    if bad: return 1
    added = sum(1 for k in ENTRIES if k not in e)
    for k, (en, sc) in ENTRIES.items(): e.setdefault(k, {"en": en, "scope": sc})
    STORE.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"added {added}, already present {len(ENTRIES) - added}"); return 0
if __name__ == "__main__": sys.exit(main())
