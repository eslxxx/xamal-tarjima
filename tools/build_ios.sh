#!/usr/bin/env bash
# 构建 iOS 版本
#
# 和 Android 版一样，需要三个配置项：
#   TILMACH_TELEMETRY_URL   活跃度上报
#   TILMACH_TELEMETRY_TAG   标识符
#   TILMACH_CONFIG_URL      运营配置
#
# 用法:
#   tools/build_ios.sh              打正式包
#   TILMACH_BASE= tools/build_ios.sh 打完全离线版本
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
secrets="$root/backend/.secrets.env"
[ -f "$secrets" ] || { echo "缺 $secrets"; exit 1; }

APP_TAG="$(sed -n 's/^APP_TAG=//p' "$secrets" | tr -d '\r\n')"
[ -n "$APP_TAG" ] || { echo "backend/.secrets.env 里没有 APP_TAG"; exit 1; }

BASE="${TILMACH_BASE-https://lg.xamal.top}"
if [ -n "$BASE" ]; then
  PING="$BASE/v1/ping"
  CONFIG="$BASE/v1/config"
else
  PING=""
  CONFIG=""
fi

cd "$root/app"

# iOS 构建 - 需要 macOS + Xcode
echo "开始构建 iOS 版本..."
echo "注意：iOS 构建需要在 macOS 上运行，且需要配置签名证书"

# 构建 iOS App
flutter build ios --release \
  --dart-define=TILMACH_TELEMETRY_URL="$PING" \
  --dart-define=TILMACH_TELEMETRY_TAG="$APP_TAG" \
  --dart-define=TILMACH_CONFIG_URL="$CONFIG" \
  "$@"

echo ""
echo "构建完成！"
echo "生成的 .app 文件位于: build/ios/iphoneos/Runner.app"
echo ""
echo "下一步："
echo "1. 在 Xcode 中打开 ios/Runner.xcworkspace"
echo "2. 配置签名证书和 provisioning profile"
echo "3. Archive 并上传到 App Store 或导出 IPA"
