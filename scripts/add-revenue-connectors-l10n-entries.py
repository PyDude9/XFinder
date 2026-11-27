#!/usr/bin/env python3
"""Add-only L10n entries for the Revenue read-only connector Settings UI."""

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
STORE = ROOT / "XFinder/Resources/L10n.strings.json"

NEW_ENTRIES = {
    "Kết nối Doanh thu bán app (chỉ đọc)": {
        "en": "App Revenue connections (read-only)",
        "scope": "sentence",
    },
    "Khóa chỉ đọc được lưu riêng theo tài khoản trong Keychain và chỉ gửi tới máy chủ chính thức api.stripe.com hoặc *.myshopify.com. Ứng dụng mặc định ở trạng thái ngắt kết nối.": {
        "en": "Read-only keys are stored per account in Keychain and sent only to official api.stripe.com or *.myshopify.com hosts. The app starts disconnected by default.",
        "scope": "sentence",
    },
    "Stripe (Balance Transactions — chỉ đọc)": {
        "en": "Stripe (Balance Transactions — read-only)",
        "scope": "sentence",
    },
    "Mã tài khoản Stripe (vd: acct_main)": {
        "en": "Stripe account ID (e.g. acct_main)",
        "scope": "sentence",
    },
    "Nhãn hiển thị": {
        "en": "Display label",
        "scope": "sentence",
    },
    "Khóa chỉ đọc Stripe (rk_...)": {
        "en": "Stripe restricted read-only key (rk_...)",
        "scope": "sentence",
    },
    "Lưu kết nối Stripe": {
        "en": "Save Stripe connection",
        "scope": "sentence",
    },
    "Ngắt kết nối Stripe": {
        "en": "Disconnect Stripe",
        "scope": "sentence",
    },
    "Shopify (Admin GraphQL — chỉ đọc)": {
        "en": "Shopify (Admin GraphQL — read-only)",
        "scope": "sentence",
    },
    "Tên miền cửa hàng (*.myshopify.com)": {
        "en": "Store domain (*.myshopify.com)",
        "scope": "sentence",
    },
    "Token Admin API chỉ đọc": {
        "en": "Read-only Admin API token",
        "scope": "sentence",
    },
    "Bật quyền payout Shopify Payments (read_shopify_payments_payouts)": {
        "en": "Enable Shopify Payments payout scope (read_shopify_payments_payouts)",
        "scope": "sentence",
    },
    "Lưu kết nối Shopify": {
        "en": "Save Shopify connection",
        "scope": "sentence",
    },
    "Ngắt kết nối Shopify": {
        "en": "Disconnect Shopify",
        "scope": "sentence",
    },
    "Nhập mã tài khoản Stripe hợp lệ.": {
        "en": "Enter a valid Stripe account ID.",
        "scope": "sentence",
    },
    "Cần nhập khóa chỉ đọc Stripe để lưu kết nối.": {
        "en": "A Stripe read-only key is required to save the connection.",
        "scope": "sentence",
    },
    "Tên miền Shopify phải có dạng ten-cua-hang.myshopify.com.": {
        "en": "Shopify domain must use the form your-store.myshopify.com.",
        "scope": "sentence",
    },
    "Cần nhập token Admin API chỉ đọc để lưu kết nối.": {
        "en": "A read-only Admin API token is required to save the connection.",
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
    print(f"Added {added} Revenue connector L10n entries (total {len(entries)}).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
