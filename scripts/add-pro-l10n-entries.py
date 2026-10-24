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
    # Clipboard Free-tier gate (XF-T29 §2/§4: history panel, ⌘⇧V shelf, notch page, Library)
    " mục cũ hơn — mở bằng Pro.": (" older items — unlock with Pro.", F),
    "Xem Pro": ("View Pro", S),
    "Khoá bảng này… (Cần Pro)": ("Lock this board… (Pro required)", S),
    " · PRO": (" · PRO", F),
    # Pro gates in clipboard/capture/tools/voice (2026-10-24)
    'Bản Free chỉ chia sẻ 1 liên kết cùng lúc — thu hồi liên kết cũ hoặc nâng cấp để chia sẻ thêm.': ('The free version shares 1 link at a time — revoke the old link or upgrade to share more.', S),
    'Bản Free giữ nguyên mọi cặp đồng bộ nhưng không tự chạy, kể cả “Đồng bộ ngay” — cần XFinder Pro để chạy đồng bộ.': ('The free version keeps every sync pair but does not run them, “Sync Now” included — syncing needs XFinder Pro.', S),
    'Chụp cuộn cần XFinder Pro': ('Scrolling capture needs XFinder Pro', S),
    'Các ảnh cũ hơn mục Free hiện được sẽ chuyển vào Thùng rác — vẫn khôi phục được.': ('Captures older than the free version shows go to the Trash — still restorable.', S),
    'Cần XFinder Pro để chạy đồng bộ. Cặp đồng bộ vẫn được giữ nguyên.': ('Syncing needs XFinder Pro. Your sync pairs are kept as they are.', S),
    'Cần XFinder Pro để tút văn bản bằng AI — XFinder sẽ chèn nguyên văn bạn nói thay vì chế độ này.': ('AI polishing needs XFinder Pro — XFinder inserts exactly what you said instead of this mode.', S),
    'Cần XFinder Pro để tút văn bản bằng AI — đã chèn nguyên văn.': ('AI polishing needs XFinder Pro — inserted your words as spoken.', S),
    'Cần XFinder Pro để tạo vault mới. Vault đã có vẫn mở khóa và dùng được bình thường.': ('Creating a new vault needs XFinder Pro. Existing vaults still unlock and work normally.', S),
    'Cần XFinder Pro để tải lên. Danh sách kết nối và Kiểm tra kết nối vẫn dùng được ở bản Free.': ('Uploading needs XFinder Pro. The connection list and Test Connection still work in the free version.', S),
    'Cần XFinder Pro để tải lên. Danh sách kết nối vẫn được giữ nguyên.': ('Uploading needs XFinder Pro. Your connection list is kept as it is.', S),
    'Cần XFinder Pro để tự đặt lại bố cục. Luật đã ghi vẫn được giữ, chỉ không tự áp dụng ở bản Free.': ('Restoring layouts automatically needs XFinder Pro. Recorded rules are kept, just not applied in the free version.', S),
    'Dọn vào Thùng rác': ('Move to Trash', S),
    'Dọn ảnh cũ vào Thùng rác': ('Move older captures to the Trash', S),
    'Dọn ảnh cũ vào Thùng rác?': ('Move older captures to the Trash?', S),
    'Tắt công tắc này chỉ dừng các lượt tự động; nút “Đồng bộ ngay” cần XFinder Pro để chạy ở cả hai trường hợp.': ('Turning this off only stops the automatic runs; “Sync Now” needs XFinder Pro either way.', S),
    'Vault đã tạo vẫn mở khóa và dùng bình thường ở bản Free — chỉ tạo vault MỚI cần XFinder Pro.': ('Vaults you already made still unlock and work in the free version — only creating a NEW vault needs XFinder Pro.', S),
    'Điều khiển các lượt Khi thay đổi và Hằng ngày.': ('Controls the On change and Daily runs.', S),
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
