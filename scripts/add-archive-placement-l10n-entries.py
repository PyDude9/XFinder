#!/usr/bin/env python3
"""XF-MFGAP-03 stage 03C — register the review/merge/source-delete sentences in the L10n store.

ADD-ONLY, like add-archive-safety-l10n-entries.py: an existing key is never rewritten; a key that
exists with a different English text stops the script (CONFLICT, nothing written).
"""
from __future__ import annotations
import json, sys
from pathlib import Path

STORE = Path(__file__).resolve().parent.parent / "XFinder/Resources/L10n.strings.json"
S, F = "sentence", "fragment"
ENTRIES: dict[str, tuple[str, str]] = {
    "Chưa kiểm tra được dung lượng trống của thư mục đích nên chưa giải nén gì.":
        ("The free space on the destination could not be read, so nothing was extracted.", S),
    "Kiểm tra trước khi giải nén":
        ("Check before extracting", S),
    "Kiểm tra":
        ("Check", S),
    " mục · đã khai báo ":
        (" items · declared ", F),
    "Trùng tên: ":
        ("Same name: ", F),
    "Không đủ dung lượng, còn thiếu ":
        ("Not enough free space, short by ", F),
    "Chưa đọc được dung lượng trống của thư mục đích.":
        ("The destination's free space could not be read.", S),
    "Tệp nén không an toàn nên sẽ không giải nén: ":
        ("This archive is not safe, so it will not be extracted: ", F),
    "Lựa chọn hoặc thư mục đích đã thay đổi — hãy bấm Kiểm tra lại trước khi giải nén.":
        ("The selection or destination changed — run the check again before extracting.", S),
    "Chưa chọn thư mục đích: hãy chọn một thư mục trước khi giải nén.":
        ("No destination folder chosen: choose a folder before extracting.", S),
    "Chưa kiểm tra xong nên chưa giải nén gì.":
        ("The check has not finished, so nothing was extracted.", S),
    "Cần ":
        ("Needs ", F),
    " · chưa đọc được dung lượng trống":
        (" · free space could not be read", F),
    " · còn trống ":
        (" · available ", F),
    "Đã xoá file nén gốc":
        ("Original archives deleted", S),
    "Sẽ giữ cả hai với tên: ":
        ("Both will be kept, as: ", F),
    "Kiểm tra xong: có tệp nén không giải nén được.":
        ("Check finished: at least one archive cannot be extracted.", S),
    "Huỷ":
        ("Cancel", S),
    "Giải nén":
        ("Extract", S),
    "Thay thế (bản cũ vào Thùng rác)":
        ("Replace (old copy to the Trash)", S),
    "Đã thay tệp nén cũ (bản cũ vào Thùng rác): ":
        ("Replaced the old archive (previous copy moved to the Trash): ", F),
    "Giữ cả hai, đã đánh số: ":
        ("Kept both, numbered: ", F),
    "Chỉ giải được một phần ":
        ("Only partly extracted ", F),
    "Đã đặt: ":
        ("Placed: ", F),
    "Chưa đặt được: ":
        ("Not placed: ", F),
    "Phần còn lại giữ ở: ":
        ("The rest is kept at: ", F),
    "Đã giải → ":
        ("Extracted → ", F),
    "Chưa có tệp nén nào giải xong trong lần này.":
        ("No archive finished extracting in this run.", S),
    " tệp nén gốc sẽ vào Thùng rác.":
        (" original archives will go to the Trash.", F),
    "Đưa vào Thùng rác":
        ("Move to the Trash", S),
    "Đã đưa vào Thùng rác: ":
        ("Moved to the Trash: ", F),
    "Không đưa được vào Thùng rác: ":
        ("Could not move to the Trash: ", F),
    "Gộp thư mục, giữ cả hai file trùng":
        ("Merge folders, keep both copies of same-named files", S),
    "Gộp thư mục, giữ cả hai file trùng: thư mục được gộp vào nhau, file trùng tên được đánh số (\"Report 2.pdf\") nên không file nào bị thay. Khi nén: tệp nén cũ không bao giờ bị ghi thêm, bản mới được giữ cả hai.":
        ("Merge folders, keep both copies of same-named files: folders combine and same-named files are numbered (\"Report 2.pdf\"), so nothing is replaced. When compressing: the old archive is never appended to; both copies are kept.", S),
    "Hiện hộp thoại trước khi ghi: giữ cả hai, gộp thư mục hoặc huỷ. Mặc định là Huỷ.":
        ("Show a dialog before writing: keep both, merge folders or cancel. The default is Cancel.", S),
    "Huỷ":
        ("Cancel", S),
    "Đã huỷ.":
        ("Cancelled.", S),
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
