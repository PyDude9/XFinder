#!/usr/bin/env python3
"""XF-T30 W7 builder "w7g" — Get Info parity (General additions, More Info by kind, Open With, read-only banner)
and Volume Get Info (2026-10-25). ADD-ONLY: a key already present with another meaning is a CONFLICT. Builders
append the keys their views need to ENTRIES (one key, one meaning).

Integrator note: "Codec:" is a same-by-design identical translation (Vietnamese tech vocabulary borrows the word
as-is) — also add "Codec:" to XFinder/Resources/L10n.allowlist.json's sameByDesign list, or
check-l10n-coverage.py will flag it as a missing translation."""
from __future__ import annotations
import json, sys
from pathlib import Path
STORE = Path(__file__).resolve().parent.parent / "XFinder/Resources/L10n.strings.json"
S = "sentence"
F = "fragment"
ENTRIES = {
    # GetInfoRootView — foldable section titles (verifier fix: "Chung"/"Mở bằng"/"Chia sẻ & Quyền" were used via
    # L10n.t() but never added here — audit-l10n-literals.py flagged all three as wrapped-but-untranslated)
    "Chung": ("General", S),
    "Mở bằng": ("Open With", S),
    "Chia sẻ & Quyền": ("Sharing & Permissions", S),
    # FileInfoRules.Row.labelKey — General/More Info sections (XF-T28 rows that were never localized, plus this
    # builder's own General/More Info additions)
    "Kích thước:": ("Size:", F),
    "Dung lượng trên đĩa:": ("On disk:", F),
    "Nơi lưu:": ("Where:", F),
    "Ngày tạo:": ("Created:", F),
    "Ngày sửa đổi:": ("Modified:", F),
    "Mở lần cuối:": ("Last opened:", F),
    "Phiên bản:": ("Version:", F),
    "Khoá:": ("Locked:", F),
    "Trạng thái đám mây:": ("Cloud status:", F),
    "Kích thước ảnh:": ("Dimensions:", F),
    "Không gian màu:": ("Color space:", F),
    "Máy ảnh:": ("Camera:", F),
    "Thời lượng:": ("Duration:", F),
    "Codec:": ("Codec:", F),
    "Số trang:": ("Pages:", F),
    "Có": ("Yes", S),
    # FileInfoRules.cloudStatusValueKey
    "Đã đồng bộ": ("Synced", S),
    "Chỉ trên đám mây": ("Only in the cloud", S),
    "Đang tải xuống": ("Downloading", S),
    "Đang tải lên": ("Uploading", S),
    "Tải xuống lỗi": ("Download failed", S),
    "Tải lên lỗi": ("Upload failed", S),
    # GetInfoWindow.swift — read-only banner, More Info empty state, Open With section, permissions "(Tôi)"
    "Chỉ đọc — mục này đến từ kết quả tìm kiếm.": ("Read-only — this item came from a search result.", S),
    "Hiện trong thư mục chứa": ("Show in Enclosing Folder", S),
    "Không có thêm thông tin cho loại tệp này.": ("No more info for this kind of file.", S),
    "Không tìm thấy ứng dụng mở được tệp này.": ("No app found that can open this file.", S),
    "(Tôi)": ("(Me)", S),
    # VolumeInfoWindow.swift
    "Định dạng:": ("Format:", F),
    "Dung lượng:": ("Capacity:", F),
    "Đã dùng:": ("Used:", F),
    "Còn trống:": ("Available:", F),
    "Không lấy được (ổ mạng không phản hồi)": ("Unavailable (network volume didn't respond)", S),
    "Có thể giải phóng:": ("Purgeable:", F),
    "Điểm gắn:": ("Mount point:", F),
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
