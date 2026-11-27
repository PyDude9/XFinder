#!/usr/bin/env python3
"""Add-only L10n entries for Stocks/Crypto watchlist Settings, 24/7 session, and change basis labels."""

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
STORE = ROOT / "XFinder/Resources/L10n.strings.json"

NEW_ENTRIES = {
    "Tiền số 24/7": {
        "en": "Crypto 24/7",
        "scope": "sentence",
    },
    "So với đóng phiên trước": {
        "en": "vs. previous close",
        "scope": "sentence",
    },
    "So với 24 giờ trước": {
        "en": "vs. 24h ago",
        "scope": "sentence",
    },
    "So với 00:00 UTC": {
        "en": "vs. 00:00 UTC",
        "scope": "sentence",
    },
    "Chưa rõ mốc so sánh": {
        "en": "Comparison basis unknown",
        "scope": "sentence",
    },
    "Danh sách theo dõi Chứng khoán & BTC/USD": {
        "en": "Stocks & BTC/USD Watchlist",
        "scope": "sentence",
    },
    "Quản lý mã theo dõi ngay cả khi chưa cấu hình nguồn giá. Danh sách bạn lưu (kể cả danh sách trống) được giữ nguyên; Bitcoin (BTC/USD) dùng phiên 24/7 và mốc so sánh riêng.": {
        "en": "Manage watched symbols even before a quote source is configured. Your saved list (including an empty list) is preserved; Bitcoin (BTC/USD) uses a 24/7 session and its own change basis.",
        "scope": "sentence",
    },
    "Tìm mã để thêm (S&P 500, AAPL, NVDA, CROX, BTC/USD...)": {
        "en": "Search symbols to add (S&P 500, AAPL, NVDA, CROX, BTC/USD...)",
        "scope": "sentence",
    },
    "Đã có": {
        "en": "Added",
        "scope": "sentence",
    },
    "Danh sách theo dõi đang trống — lựa chọn trống này được giữ lại.": {
        "en": "Watchlist is empty — this empty choice is preserved.",
        "scope": "sentence",
    },
    "Khôi phục danh sách mặc định": {
        "en": "Restore default watchlist",
        "scope": "sentence",
    },
}


def main() -> int:
    data = json.loads(STORE.read_text(encoding="utf-8"))
    entries = data["entries"]
    added = 0
    for key, val in NEW_ENTRIES.items():
        if key in entries:
            continue
        entries[key] = val
        added += 1
    STORE.write_text(
        json.dumps(data, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"Added {added} Stocks watchlist L10n entries (total {len(entries)}).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
