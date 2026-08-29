#!/usr/bin/env bash
# 把编译好的 libmtcore.so 同步到 Flutter 工程的 jniLibs 目录。
#
# 为什么用 jniLibs 而不是让 Gradle 跑 externalNativeBuild:
#   llama.cpp 完整编译要好几分钟, 而原生层改动频率远低于 Dart 层。
#   预编译 + jniLibs 让 `flutter run` 保持秒级热重载。
#   原生层改了就重跑 build_engine_android.sh 再跑本脚本。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# 默认用 dotprod 变体 (骁龙 845 / 麒麟 810 及以后, 实测比基线快 1.74 倍)
VARIANT="${VARIANT:-armv8.2-a-dotprod-fp16}"
SRC="$ROOT/out/android-arm64-$VARIANT/libmtcore.so"
DST="$ROOT/app/android/app/src/main/jniLibs/arm64-v8a"

[ -f "$SRC" ] || {
  echo "找不到 $SRC" >&2
  echo "先跑: ARM_ARCH=\"${VARIANT//-/+}\" bash engine/scripts/build_engine_android.sh" >&2
  exit 1
}

mkdir -p "$DST"
cp "$SRC" "$DST/libmtcore.so"
echo "已同步 ($VARIANT):"
ls -la "$DST/libmtcore.so" | awk '{printf "  %s bytes  %s\n", $5, $9}'
