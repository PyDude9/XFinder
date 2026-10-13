#!/usr/bin/env python3
"""F4 (2026-10-13) — Chụp & chú thích: register the page, card, editor, flyout, model and catalog strings.

Idempotent, ADD-ONLY (same contract as add-smartselect-l10n-entries.py): an existing key is never rewritten; a key that
exists with different English stops the script. Model keys (CaptureMode / CaptureAfter / AnnotationTool / StrokeWidth
titles) reach the screen through `L10n.t(variable)`; CaptureRulesTests / AnnotationTests resolve them against the store.
"""
from __future__ import annotations
import json, sys
from pathlib import Path

STORE = Path(__file__).resolve().parent.parent / "XFinder/Resources/L10n.strings.json"
S, F = "sentence", "fragment"
ENTRIES: dict[str, tuple[str, str]] = {
    # catalog, sidebar, page header
    "Chụp & chú thích": ("Capture & Annotate", S),
    "Phím tắt chụp, thẻ xem trước nổi và trình chú thích.": ("Capture shortcuts, a floating preview card and an annotation editor.", S),
    "Chụp một vùng, cửa sổ hoặc cả màn hình; ảnh vào clipboard ngay, rồi chú thích, lưu hoặc ghim lên màn hình.":
        ("Capture an area, a window or the whole screen; it lands on the clipboard at once — then annotate it, save it or pin it to the screen.", S),
    "Chưa có quyền Ghi màn hình — ảnh chụp sẽ chỉ có hình nền.": ("No Screen Recording permission yet — captures will show only the wallpaper.", S),
    # capture modes (model keys)
    "Chụp vùng": ("Capture Area", S),
    "Chụp cửa sổ đang mở": ("Capture Focused Window", S),
    "Chụp toàn màn hình": ("Capture Full Screen", S),
    "Chụp vùng rồi chú thích": ("Capture Area and Annotate", S),
    "Kéo khoanh phần màn hình bạn muốn lấy": ("Drag out the part of the screen you want", S),
    "Chụp đúng cửa sổ đang được chọn, không cần khoanh vùng": ("Takes the window that has focus — nothing to select", S),
    "Chụp toàn bộ màn hình đang dùng": ("Takes the whole display you are on", S),
    "Khoanh vùng rồi mở ngay cửa sổ chú thích": ("Select an area and open it straight in the editor", S),
    "Nhận diện và sao chép chữ trong vùng bạn chọn": ("Recognises and copies the text in the area you select", S),
    "Lấy mã màu tại điểm bạn trỏ tới": ("Copies the colour of the pixel you click", S),
    "Sao chép và hiện thẻ xem trước — mặc định": ("Copy and show the preview card — default", S),
    "Chỉ sao chép": ("Copy only", S),
    "Mở chú thích ngay": ("Open the editor right away", S),
    # page
    "Chụp": ("Capture", S),
    "Không có phím tắt mặc định — ⇧⌘3, ⇧⌘4, ⇧⌘5 vẫn là của macOS.": ("No default shortcuts — ⇧⌘3, ⇧⌘4 and ⇧⌘5 still belong to macOS.", S),
    "Bật phím tắt chụp": ("Enable capture shortcuts", S),
    "Dùng bộ phím giống OneNotch": ("Use OneNotch-style shortcuts", S),
    "⇧⌘ + số: 4 vùng · 3 toàn màn hình · 9 cửa sổ · 2 chép chữ · 1 lấy màu. Muốn dùng ⇧⌘3 và ⇧⌘4, hãy tắt hai phím đó của macOS trong Cài đặt hệ thống ▸ Bàn phím ▸ Phím tắt ▸ Ảnh màn hình.":
        ("⇧⌘ + digit: 4 area · 3 full screen · 9 window · 2 copy text · 1 pick colour. To use ⇧⌘3 and ⇧⌘4, first turn off macOS's own in System Settings ▸ Keyboard ▸ Keyboard Shortcuts ▸ Screenshots.", S),
    "Mở Phím tắt bàn phím": ("Open Keyboard Shortcuts", S),
    "Nhấn tổ hợp phím… (Esc để huỷ)": ("Press a key combination… (Esc to cancel)", S),
    "Gán phím": ("Set Shortcut", S),
    "Trùng với ": ("Same as ", F),
    " — macOS có thể giành trước.": (" — macOS may take it first.", F),
    " đã giữ tổ hợp này rồi.": (" already uses this shortcut.", F),
    "Sau khi chụp": ("After capture", S),
    "Thẻ xem trước tự đóng sau": ("Preview card closes after", S),
    "Dừng đếm khi trỏ vào thẻ": ("Hold the countdown while pointing at the card", S),
    "Vuốt hai ngón để đóng thẻ": ("Swipe with two fingers to dismiss the card", S),
    "Âm thanh khi chụp": ("Capture sound", S),
    "Không tự đóng": ("Never", S),
    " giây": (" sec", F),
    "Thư mục lưu": ("Save folder", S),
    "Màu mặc định": ("Default colour", S),
    "Độ dày nét": ("Stroke width", S),
    "Giữ lịch sử ảnh chụp": ("Keep capture history", S),
    "Tối đa 50 ảnh, trong thư mục của XFinder trên máy này.": ("Up to 50 images, in XFinder's own folder on this Mac.", S),
    "Chưa có ảnh chụp nào.": ("No captures yet.", S),
    "Xoá lịch sử": ("Clear History", S),
    "Ghim lên màn hình": ("Pin to Screen", S),
    "Chép chữ": ("Copy Text", S),
    "Chú thích": ("Annotate", S),
    # macOS's own screenshot shortcuts (CaptureRules.systemReserved nameKey, shown in a clash warning)
    "macOS Chụp toàn màn hình": ("macOS Capture Full Screen", S),
    "macOS Chụp vùng": ("macOS Capture Area", S),
    "macOS Sao chép toàn màn hình": ("macOS Copy Full Screen", S),
    "macOS Sao chép vùng": ("macOS Copy Area", S),
    "macOS Tùy chọn chụp và ghi màn hình": ("macOS Screenshot & Recording Options", S),
    # controller notices
    "Cần quyền Ghi màn hình để chụp ảnh.": ("Screen Recording permission is needed to capture.", S),
    "Không chạy được công cụ chụp màn hình.": ("Couldn't run the screenshot tool.", S),
    "Không lưu được ảnh chụp.": ("Couldn't save the capture.", S),
    "Không đọc được ảnh chụp.": ("Couldn't read the capture.", S),
    "Không mã hoá được ảnh chụp.": ("Couldn't encode the capture.", S),
    "Ảnh chụp": ("Screenshot", F),
    " lúc ": (" at ", F),
    # editor
    "Ảnh chụp ": ("Screenshot ", F),
    "Lưu…": ("Save…", S),
    "Kéo ra để lưu vào nơi khác": ("Drag out to put it somewhere else", S),
    " dấu": (" marks", F),
    "Mũi tên": ("Arrow", S),
    "Khung": ("Rectangle", S),
    "Chữ": ("Text", S),
    "Số thứ tự": ("Counter", S),
    "Làm mờ": ("Blur", S),
    "Tô sáng": ("Highlighter", S),
    "Cắt": ("Crop", S),
    "Mảnh": ("Thin", S),
    "Dày": ("Thick", S),
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
