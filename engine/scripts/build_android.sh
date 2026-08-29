#!/usr/bin/env bash
# 交叉编译 llama.cpp (STQ1_0 分支) 为 Android arm64-v8a 静态库 + 测试用可执行文件
#
# 产物:
#   build-android-arm64/  下的 libllama.a / libggml*.a  → 供 mt_core 静态链接
#   bin/llama-bench, bin/llama-cli                      → push 到真机跑基准
#
# 说明:
#   - STQ1_0 kernel 只有 ARM NEON 实现 + 通用标量 fallback, 无 GPU kernel, 所以纯 CPU
#   - 只出 arm64-v8a: kernel 用 vqtbl2q_u8 等 aarch64-only intrinsics, 32 位无意义
set -euo pipefail

NDK="${ANDROID_NDK:-C:/Users/Administrator/AppData/Local/Android/Sdk/ndk/28.2.13676358}"
NINJA="${NINJA:-C:/Users/Administrator/AppData/Local/Android/Sdk/cmake/3.22.1/bin/ninja.exe}"
SRC="$(cd "$(dirname "$0")/.." && pwd)/third_party/llama.cpp"
BUILD="$SRC/build-android-arm64"

# minSdk 26 (Android 8.0): 覆盖率足够, 且避免老 API 的 libc 缺函数问题
API=26

[ -d "$NDK" ]   || { echo "找不到 NDK: $NDK" >&2; exit 1; }
[ -f "$NINJA" ] || { echo "找不到 ninja: $NINJA" >&2; exit 1; }
[ -d "$SRC" ]   || { echo "找不到 llama.cpp 源码: $SRC" >&2; exit 1; }

echo ">>> NDK   : $NDK"
echo ">>> 源码  : $SRC"
echo ">>> HEAD  : $(cd "$SRC" && git log --oneline -1)"

cmake -S "$SRC" -B "$BUILD" -G Ninja \
  -DCMAKE_MAKE_PROGRAM="$NINJA" \
  -DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake" \
  -DANDROID_ABI=arm64-v8a \
  -DANDROID_PLATFORM="android-$API" \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_SHARED_LIBS=OFF \
  -DGGML_OPENMP=OFF \
  -DGGML_LLAMAFILE=OFF \
  -DLLAMA_CURL=OFF \
  -DLLAMA_BUILD_TESTS=OFF \
  -DLLAMA_BUILD_EXAMPLES=OFF \
  -DLLAMA_BUILD_SERVER=OFF \
  -DLLAMA_BUILD_TOOLS=ON

# 只构建需要的 target。
# 不构建 all: llama.cpp 的统一 `app/llama` target 在 LLAMA_BUILD_SERVER=OFF 时
# 仍会去链接 llama-server-impl / llama-cli-impl，必然失败，而我们并不需要它。
cmake --build "$BUILD" --config Release -j "$(nproc 2>/dev/null || echo 8)" \
  --target llama ggml ggml-cpu ggml-base llama-bench llama-completion

STRIP="$NDK/toolchains/llvm/prebuilt/windows-x86_64/bin/llvm-strip.exe"
mkdir -p "$BUILD/bin-stripped"
for f in llama-bench llama-completion; do
  if [ -f "$BUILD/bin/$f" ]; then
    cp "$BUILD/bin/$f" "$BUILD/bin-stripped/$f"
    "$STRIP" "$BUILD/bin-stripped/$f" 2>/dev/null || true
  fi
done

echo
echo ">>> 静态库:"
find "$BUILD" -name "*.a" -printf "%10s  %f\n" 2>/dev/null | sed 's/^/    /'
echo ">>> 可执行文件 (已 strip, 用于 adb push):"
ls -la "$BUILD/bin-stripped" 2>/dev/null | grep -v '^d' | awk '{printf "    %10s  %s\n",$5,$9}'
