#!/usr/bin/env bash
# 编译 tilmach 推理核 (libmtcore.so + mt_cli) → Android arm64-v8a
set -euo pipefail

NDK="${ANDROID_NDK:-C:/Users/Administrator/AppData/Local/Android/Sdk/ndk/28.2.13676358}"
NINJA="${NINJA:-C:/Users/Administrator/AppData/Local/Android/Sdk/cmake/3.22.1/bin/ninja.exe}"
ENGINE="$(cd "$(dirname "$0")/.." && pwd)"
API=26

# ARM 目标架构。STQ1_0 的 NEON kernel 里 vdotq_s32 是用 __ARM_FEATURE_DOTPROD
# 编译期开关的 (有非 dotprod 回退路径), 所以这个值直接决定跑哪条路径:
#   ""                    → 基线 armv8-a, 全部 arm64 机型可用, 走慢路径
#   armv8.2-a+dotprod+fp16 → 骁龙 845 / 麒麟 810 / 天玑 全系 (2018 年后) , 走 dotprod 快路径
# 用 ARM_ARCH 环境变量覆盖; 产物目录也跟着变, 方便同时保留两个变体做对比。
ARM_ARCH="${ARM_ARCH:-armv8.2-a+dotprod+fp16}"
VARIANT="${ARM_ARCH:-baseline}"
VARIANT="${VARIANT//+/-}"
BUILD="$ENGINE/build-android-arm64-$VARIANT"
OUTDIR="$ENGINE/../out/android-arm64-$VARIANT"

echo ">>> ARM_ARCH = ${ARM_ARCH:-(baseline armv8-a)}"

CMAKE_ARM_ARG=()
[ -n "$ARM_ARCH" ] && CMAKE_ARM_ARG=(-DGGML_CPU_ARM_ARCH="$ARM_ARCH")

cmake -S "$ENGINE" -B "$BUILD" -G Ninja \
  -DCMAKE_MAKE_PROGRAM="$NINJA" \
  -DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake" \
  -DANDROID_ABI=arm64-v8a \
  -DANDROID_PLATFORM="android-$API" \
  -DCMAKE_BUILD_TYPE=Release \
  "${CMAKE_ARM_ARG[@]}"

cmake --build "$BUILD" -j "$(nproc 2>/dev/null || echo 8)"

STRIP="$NDK/toolchains/llvm/prebuilt/windows-x86_64/bin/llvm-strip.exe"
mkdir -p "$OUTDIR"
for f in libmtcore.so mt_cli; do
  [ -f "$BUILD/$f" ] || continue
  cp "$BUILD/$f" "$OUTDIR/$f"
  "$STRIP" "$OUTDIR/$f" 2>/dev/null || true
done

echo
echo ">>> 产物 ($OUTDIR):"
ls -la "$OUTDIR" | grep -v '^d' | awk '{printf "    %10s  %s\n",$5,$9}'
