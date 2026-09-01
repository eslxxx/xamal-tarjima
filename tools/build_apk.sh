#!/usr/bin/env bash
# 打 release APK。
#
# 三个 dart-define 决定 App 的联网行为, 漏掉任何一个都会**静默**编出一个功能不全
# 的包 (统计不上报 / 横幅只有内置那张 / 更新检查提示"未内置"), 装上去也看不出来。
# 所以把配方写在这里, 不靠人记:
#
#   TILMACH_TELEMETRY_URL   活跃度上报; 留空 = 编一个完全不带统计的版本
#   TILMACH_TELEMETRY_TAG   和 Worker 约定的标识, 从 backend/.secrets.env 读
#   TILMACH_CONFIG_URL      运营横幅 + 版本信息; 留空 = 只显示内置横幅、不查更新
#
# APP_TAG 只存在于这个进程的环境变量里 —— 不 echo, 不写进任何文件, 也不进构建日志。
#
# 用法:
#   tools/build_apk.sh                     打正式包
#   TILMACH_BASE= tools/build_apk.sh       打一个完全不联网的包
#   tools/build_apk.sh --debug             传给 flutter build 的额外参数
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
secrets="$root/backend/.secrets.env"
[ -f "$secrets" ] || { echo "缺 $secrets"; exit 1; }

APP_TAG="$(sed -n 's/^APP_TAG=//p' "$secrets" | tr -d '\r\n')"
[ -n "$APP_TAG" ] || { echo "backend/.secrets.env 里没有 APP_TAG"; exit 1; }

# 后台地址。显式设成空字符串就能打一个不联网的包。
BASE="${TILMACH_BASE-https://lg.xamal.top}"
if [ -n "$BASE" ]; then
  PING="$BASE/v1/ping"
  CONFIG="$BASE/v1/config"
else
  PING=""
  CONFIG=""
fi

# local.properties 里 flutter.sdk 指的是 D:\flutter, 这台机器上还有个 C:\flutter,
# 用错那个 SDK 会连不上 Android 工程配置。
export PATH="/d/flutter/bin:$PATH"

cd "$root/app"
# --target-platform android-arm64: 翻译引擎 libmtcore.so 只编了 arm64 一份
# (STQ1_0 kernel 也只在 arm64 上验证过)。不加这个 flag, Flutter 会把它自己的
# libflutter.so/libapp.so 三份 ABI 全塞进来 —— 包从 24MB 涨到 55MB, 而且在
# armeabi-v7a / x86_64 设备上装完会因为找不到 libmtcore.so 直接崩。
exec flutter build apk --release \
  --target-platform android-arm64 \
  --dart-define=TILMACH_TELEMETRY_URL="$PING" \
  --dart-define=TILMACH_TELEMETRY_TAG="$APP_TAG" \
  --dart-define=TILMACH_CONFIG_URL="$CONFIG" \
  "$@"
