#!/usr/bin/env bash
# 断点续传下载 Flutter SDK (国内镜像 storage.flutter-io.cn) 并解压到 D:/flutter
#
# 国内镜像清单 (2026-08 实测):
#   storage.flutter-io.cn  ✅ 官方中国镜像, 有完整 flutter_infra_release
#   mirrors.tuna / mirrors.cloud.tencent  ❌ 已不再镜像该路径
set -uo pipefail

VER="${FLUTTER_VERSION:-3.47.2}"
ARCHIVE="stable/windows/flutter_windows_${VER}-stable.zip"
BASE="https://storage.flutter-io.cn/flutter_infra_release/releases"
ZIP="D:/tilmach/out/flutter_windows_${VER}-stable.zip"
TARGET="D:/flutter"

size_of() { stat -c %s "$1" 2>/dev/null || echo 0; }

WANT="$(curl -sIL --max-time 30 "$BASE/$ARCHIVE" | grep -i '^content-length' | tail -1 | tr -dc '0-9')"
[ -n "$WANT" ] || { echo "拿不到 content-length" >&2; exit 1; }
echo "目标大小: $WANT 字节"

for i in $(seq 1 300); do
  have="$(size_of "$ZIP")"
  [ "$have" -ge "$WANT" ] && break
  echo "[$i] $have / $WANT ($((have * 100 / WANT))%) 续传中..."
  curl -L -C - --max-time 900 --connect-timeout 20 \
       --speed-limit 30000 --speed-time 60 \
       -sS -o "$ZIP" "$BASE/$ARCHIVE" || true
  sleep 2
done

have="$(size_of "$ZIP")"
[ "$have" -eq "$WANT" ] || { echo "下载未完成: $have / $WANT" >&2; exit 1; }
echo "下载完成, 解压到 $TARGET ..."

if [ -d "$TARGET" ]; then
  echo "$TARGET 已存在, 跳过解压"
else
  # 用 PowerShell 解压, Git Bash 的 unzip 未必存在
  powershell -NoProfile -Command \
    "Expand-Archive -LiteralPath '$ZIP' -DestinationPath 'D:/' -Force" || {
      echo "解压失败" >&2; exit 1; }
fi
"$TARGET/bin/flutter" --version 2>&1 | head -5
