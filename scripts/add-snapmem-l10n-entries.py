#!/usr/bin/env python3
"""SNAPMEM (2026-10-18) — window-layout memory for the snap zones. ADD-ONLY: an existing key is never rewritten
(a key that already exists may mean something else — CONFLICT and exit 1). Model keys (SnapMemory.Layout/Outcome,
FeatureCatalog row) and the settings section's strings."""
from __future__ import annotations
import json, sys
from pathlib import Path
STORE = Path(__file__).resolve().parent.parent / "XFinder/Resources/L10n.strings.json"
S, F = "sentence", "fragment"
ENTRIES = {
    # SnapMemory.Layout / Outcome (variable-passed keys — SnapMemoryTests resolves every one of them)
    "Toàn màn hình (Space riêng)": ("Full screen (its own Space)", S),
    "Vị trí tự kéo": ("Hand-placed frame", S),
    "Đã áp": ("Applied", S),
    "Thiếu quyền Trợ năng": ("Accessibility permission missing", S),
    "Không thấy cửa sổ": ("No window found", S),
    "App không cho đặt toàn màn hình qua Trợ năng": ("The app does not allow full screen through Accessibility", S),
    "Không đặt được": ("Could not set", S),
    "App chưa chạy": ("App not running", S),
    # FeatureCatalog row
    "Nhớ bố cục cửa sổ": ("Remember window layouts", S),
    "Đưa app về đúng chỗ đã bắt dính khi nó mở lại hoặc khi đổi bộ màn hình.":
        ("Puts an app back where you snapped it when it opens again or when the set of displays changes.", S),
    # Settings section "Nhớ bố cục" (SnapZonesDetailView.section5Memory)
    "Nhớ bố cục": ("Remember layouts", S),
    "Nhớ theo từng bộ màn hình đang cắm và theo từng app. Toàn màn hình được nhớ qua Trợ năng; macOS không có API công khai cho biết cửa sổ ở Space thường nào, nên XFinder không phân biệt các Space thường. Hai màn hình cùng model có thể bị coi là một.":
        ("Remembered per set of connected displays and per app. Full screen is remembered through Accessibility; macOS has no public API for which regular Space a window is on, so XFinder does not distinguish regular Spaces. Two monitors of the same model may be treated as one.", S),
    "Nhớ bố cục theo bộ màn hình": ("Remember layouts per set of displays", S),
    "Một app vào danh sách này ngay lần đầu bạn bắt dính nó bằng XFinder. Lần sau app đó mở, hoặc khi bộ màn hình thay đổi, XFinder tự đặt lại đúng chỗ.":
        ("An app enters this list the first time you snap it with XFinder. The next time it opens, or when the set of displays changes, XFinder puts it back in the same place.", S),
    "Nhớ cả vị trí tự kéo": ("Also remember hand-dragged positions", S),
    "Tắt thì chỉ nhớ các ô bắt dính của XFinder và toàn màn hình. Bật thì nhớ cả khung bạn tự kéo bằng tay.":
        ("Off: only XFinder's own snap zones and full screen are remembered. On: a frame you drag by hand is remembered too.", S),
    "Bộ màn hình hiện tại: ": ("Current set of displays: ", F),
    "Chưa có luật nào — bắt dính một cửa sổ bằng XFinder để bắt đầu.": ("No rules yet — snap a window with XFinder to get started.", S),
    "Áp lại ngay": ("Reapply now", S),
    "Xoá tất cả": ("Delete all", S),
    "Xoá luật này": ("Delete this rule", S),
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
