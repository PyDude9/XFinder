#!/bin/zsh
# dev-setup.sh — build + ký + cài + mở XFinder và tự NHẮC QUYỀN một lệnh.
#
# Giải quyết nỗi đau "mỗi lần build lại phải cấp lại quyền Trợ năng/Ghi màn
# hình" bằng cách dùng MỘT chứng chỉ codesigning ổn định (tạo tự động nếu
# chưa có). macOS gán quyền theo *danh tính code* (designated requirement =
# identifier + chứng chỉ), nên một chứng chỉ cố định + identifier cố định =>
# quyền giữ nguyên qua mọi lần rebuild.
#
# Dùng:    ./scripts/dev-setup.sh            # build + cài + tự nhắc quyền
#          ./scripts/dev-setup.sh --sign-only  # chỉ ký bản build/ hiện có
#
# Sau khi chạy, trong System Settings → Privacy & Security, Chỉ cần TICK:
#   Trợ năng (Accessibility) → XFinder
#   Ghi màn hình (Screen Recording) → XFinder
# (Hộp thoại tự hiện do app nhận đối số --grant-permissions; tick là xong.)
set -euo pipefail

CERT_NAME="XFinder Dev"
APP_ID="com.xfinder.app"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$REPO/build/XFinder.app"
DEST="/Applications/XFinder.app"
SIGN_ONLY=false
[[ "${1:-}" == "--sign-only" ]] && SIGN_ONLY=true

# 1) Chứng chỉ ổn định (one-time). Nếu chưa có → tự tạo non-interactive.
if security find-certificate -c "$CERT_NAME" >/dev/null 2>&1; then
  echo "✓ Chứng chỉ '$CERT_NAME' đã có."
  STABLE=1
else
  echo "◦ Tạo chứng chỉ '$CERT_NAME' tự động (self-signed, codeSigning)…"
  TMP="$(mktemp -d)"
  openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -days 3650 \
    -subj "/CN=$CERT_NAME" \
    -addext "extendedKeyUsage=codeSigning" -addext "keyUsage=digitalSignature" \
    >/dev/null 2>&1
  openssl pkcs12 -export -out "$TMP/id.p12" -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -passout pass: >/dev/null 2>&1
  if security import "$TMP/id.p12" -k "$HOME/Library/Keychains/login.keychain-db" \
      -P "" -T /usr/bin/codesign -T /usr/bin/security -T /usr/bin/ld \
      >/dev/null 2>&1; then
    echo "✓ Đã tạo + import chứng chỉ (nhớ sau này xoá bằng: security delete-certificate -c \"$CERT_NAME\")."
    STABLE=1
  else
    echo "⚠ Không tự tạo được chứng chỉ (Keychain khoá?). Fallback ký ad-hoc —"
    echo "  quyền SẼ bị reset mỗi build. Tạo thủ công theo scripts/sign-dev.sh."
    STABLE=0
  fi
  rm -rf "$TMP"
fi

# 2) Build (trừ khi --sign-only).
if $SIGN_ONLY; then
  [[ -d "$BUILD" ]] || { echo "✗ Chưa có build/XFinder.app — build trước." >&2; exit 1; }
  echo "◦ Bỏ qua build (--sign-only)."
else
  echo "◦ Build (Debug)…"
  xcodebuild -project "$REPO/XFinder.xcodeproj" -scheme XFinder \
    -configuration Debug build 2>&1 \
    | grep -E "error:|BUILD (SUCCEEDED|FAILED)" | grep -v "DVTPlugIn\|CoreSimulator" || true
  [[ -d "$BUILD" ]] || { echo "✗ Build thất bại, không thấy $BUILD." >&2; exit 1; }
fi

# 3) Dừng bản đang chạy để thay bundle được.
if pgrep -x XFinder >/dev/null; then pkill -x XFinder || true; sleep 1; fi

# 4) Ký.
if [[ "$STABLE" == "1" ]]; then
  echo "◦ Ký bằng '$CERT_NAME'…"
  codesign --force --deep --sign "$CERT_NAME" --identifier "$APP_ID" "$BUILD" 2>/dev/null \
    || codesign --force --deep --sign "$CERT_NAME" --identifier "$APP_ID" --options runtime "$BUILD"
else
  echo "◦ Ký ad-hoc…"
  codesign --force --deep --sign - --identifier "$APP_ID" "$BUILD"
fi

# 5) Cài vào đường dẫn cố định để quyền khỏi lệch theo path.
echo "◦ Cài vào $DEST…"
rm -rf "$DEST"
cp -R "$BUILD" "$DEST"

# 6) Mở + tự nhắc quyền.
echo "◦ Mở và tự nhắc quyền…"
open "$DEST" --args --grant-permissions

cat <<'EOF'

────────────────────────────────────────────────────────────
 XFINDER DEV SETUP XONG. Còn đúng một thao tác tay:
   1) Trợ năng (Accessibility)      → tick XFinder
   2) Ghi màn hình (Screen Recording) → tick XFinder
 (hộp thoại đã tự hiện; tick là xong, các lần build sau không phải làm lại
  vì đã dùng chứng chỉ ổn định '$CERT_NAME'.)
────────────────────────────────────────────────────────────
EOF
