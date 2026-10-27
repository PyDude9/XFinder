#!/usr/bin/env python3
"""Inspector: idempotent ADD-ONLY translations; refuses conflicting existing keys."""
from __future__ import annotations
import json, sys
from pathlib import Path

STORE = Path(__file__).resolve().parent.parent / "XFinder/Resources/L10n.strings.json"
S, F = "sentence", "fragment"
ENTRIES: dict[str, tuple[str, str]] = {'Tệp văn bản trống.': ('Text file is empty.', 'sentence'), 'Nội dung Inspector': ('Inspector content', 'sentence'), 'Tệp văn bản quá lớn để xem trước (tối đa 256 KiB).': ('Text file is too large to preview (256 KiB maximum).', 'sentence'), 'Chỉ xem trước văn bản UTF-8 không chứa dữ liệu nhị phân.': ('Only UTF-8 text without binary data can be previewed.', 'sentence'), 'Không đọc được nội dung tệp.': ('Unable to read file contents.', 'sentence')}

ENTRIES.update({'Thao tác ảnh': ('Image actions', 'sentence'), 'Tạo bản mới, chỉ xử lý khung hình đầu tiên. Lật và thu nhỏ xuất PNG.': ('Creates a copy using only the first frame. Flip and resize export PNG.', 'sentence'), 'Giảm kích thước ảnh': ('Resize smaller', 'sentence'), 'Lật ngang': ('Flip horizontal', 'sentence'), 'Lật dọc': ('Flip vertical', 'sentence'), 'ImageIO trên máy này chưa có bộ ghi WebP.': ('ImageIO on this Mac does not provide a WebP encoder.', 'sentence'), 'Hiện bản ảnh mới': ('Reveal new image', 'sentence'), 'Đang xử lý ảnh khác. Hãy chờ thao tác đó kết thúc.': ('Another image is being processed. Wait for it to finish.', 'sentence'), 'Không thực hiện được thao tác ảnh.': ('Unable to complete the image operation.', 'sentence'), 'Đã tạo bản ảnh mới.': ('Created a new image copy.', 'sentence'), 'Thao tác ảnh quá thời gian cho phép.': ('The image operation timed out.', 'sentence'), 'Không khởi chạy được tiến trình xử lý ảnh.': ('Unable to start the image worker.', 'sentence'), 'Đã hủy thao tác ảnh.': ('Image operation canceled.', 'sentence'), 'Yêu cầu thao tác ảnh không hợp lệ.': ('Invalid image operation request.', 'sentence'), 'Tệp nguồn đã thay đổi. Hãy chọn lại tệp rồi thử lại.': ('The source file changed. Select it again and retry.', 'sentence'), 'Tệp chỉ có trên đám mây — thao tác ảnh không tải tệp về.': ('This file is cloud-only. Image actions do not download it.', 'sentence'), 'Ảnh vượt giới hạn xử lý an toàn (100 MiB hoặc 100 triệu điểm ảnh).': ('Image exceeds safe processing limits (100 MiB or 100 million pixels).', 'sentence'), 'Ảnh không đọc được hoặc vượt giới hạn xử lý an toàn.': ('Image is unreadable or exceeds safe processing limits.', 'sentence'), 'ImageIO trên máy này không có bộ ghi cho định dạng đã chọn.': ('ImageIO on this Mac has no encoder for the selected format.', 'sentence'), 'Kích thước mới phải nhỏ hơn ảnh nguồn.': ('The new size must be smaller than the source image.', 'sentence'), 'Không ghi được bản ảnh mới. Kiểm tra quyền ghi của thư mục.': ('Unable to write the new image. Check folder write permissions.', 'sentence'), 'Có quá nhiều tệp trùng tên trong thư mục.': ('Too many conflicting file names in this folder.', 'sentence')})

ENTRIES.update({'Chuyển đổi': ('Convert', 'sentence'), 'Xem trước': ('Preview', 'sentence')})

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
