#!/bin/zsh
# Ký lại bản build vừa xong bằng chứng chỉ ổn định "XFinder Dev" để macOS
# KHÔNG reset quyền Trợ năng / Ghi màn hình mỗi lần build.
#
# Dùng khi bạn build nhiều lần (xcodebuild / Xcode) và không cần cài lại vào
# /Applications — chỉ muốn quyền dính lại trên build/XFinder.app.
#
# ONE-TIME SETUP (xem dev-install.sh, cần GUI vì tạo chứng chỉ không tự động):
#   Keychain Access ▸ Certificate Assistant ▸ Create a Certificate…
#   Name: XFinder Dev · Identity Type: Self Signed Root · Certificate Type: Code Signing
# Sau đó: ./scripts/sign-dev.sh → grant Accessibility/Screen Recording MỘT lần.
#
# Không có chứng chỉ (= ad-hoc): mỗi build đổi cdhash, macOS coi như app mới.
set -euo pipefail

CERT_NAME="XFinder Dev"
cd "$(dirname "$0")/.."
APP="build/XFinder.app"

if [[ ! -d "$APP" ]]; then
  echo "✗ Không thấy $APP — hãy build trước." >&2
  exit 1
fi

if security find-certificate -c "$CERT_NAME" >/dev/null 2>&1; then
  echo "▸ Ký bằng '$CERT_NAME' (identity ổn định — quyền không bị reset)…"
  codesign --force --deep --sign "$CERT_NAME" --identifier com.xfinder.app "$APP"
else
  echo "⚠ Chưa có chứng chỉ '$CERT_NAME' — vẫn ký ad-hoc nên quyền SẼ reset."
  echo "  Tạo chứng chỉ theo hướng dẫn đầu file rồi chạy lại."
  codesign --force --deep --sign - --identifier com.xfinder.app "$APP"
fi
echo "▸ Xong. Mở lại app nếu đang chạy:"
pkill -x XFinder 2>/dev/null || true
open "$APP"
