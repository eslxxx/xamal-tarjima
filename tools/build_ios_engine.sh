#!/usr/bin/env bash
# 为 iOS 编译 mtcore 引擎（需要在 macOS 上运行）
#
# 生成 libmtcore.a 静态库和 framework，供 Flutter iOS 项目使用
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
engine_dir="$root/engine"
build_dir="$root/build/ios"

echo "开始编译 iOS 引擎..."

# 检查是否在 macOS 上
if [[ "$OSTYPE" != "darwin"* ]]; then
  echo "错误：iOS 编译必须在 macOS 上进行"
  exit 1
fi

# 检查 Xcode 是否安装
if ! command -v xcodebuild &> /dev/null; then
  echo "错误：未找到 Xcode，请先安装 Xcode"
  exit 1
fi

mkdir -p "$build_dir"

# ===============================
# 1. 编译 arm64 (真机)
# ===============================
echo "编译 arm64 (iPhone 真机)..."
cmake -S "$engine_dir" -B "$build_dir/arm64" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=12.0 \
  -DCMAKE_INSTALL_PREFIX="$build_dir/arm64/install"

cmake --build "$build_dir/arm64" --config Release -j$(sysctl -n hw.ncpu)

# ===============================
# 2. 编译 x86_64 (模拟器 - 可选)
# ===============================
echo "编译 x86_64 (iOS 模拟器)..."
cmake -S "$engine_dir" -B "$build_dir/x86_64" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_ARCHITECTURES=x86_64 \
  -DCMAKE_OSX_SYSROOT=iphonesimulator \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=12.0 \
  -DCMAKE_INSTALL_PREFIX="$build_dir/x86_64/install"

cmake --build "$build_dir/x86_64" --config Release -j$(sysctl -n hw.ncpu)

# ===============================
# 3. 创建 Universal Binary (可选)
# ===============================
echo "创建 Universal Binary..."
mkdir -p "$build_dir/universal"
lipo -create \
  "$build_dir/arm64/libmtcore.dylib" \
  "$build_dir/x86_64/libmtcore.dylib" \
  -output "$build_dir/universal/libmtcore.dylib"

# ===============================
# 4. 复制到 Flutter iOS 项目
# ===============================
ios_libs="$root/app/ios/Frameworks"
mkdir -p "$ios_libs"

echo "复制库文件到 Flutter iOS 项目..."
cp "$build_dir/universal/libmtcore.dylib" "$ios_libs/"
cp "$engine_dir/include/mt_core.h" "$ios_libs/"

echo ""
echo "✅ iOS 引擎编译完成！"
echo "生成的库文件："
echo "  - arm64:  $build_dir/arm64/libmtcore.dylib"
echo "  - x86_64: $build_dir/x86_64/libmtcore.dylib"
echo "  - 通用版: $build_dir/universal/libmtcore.dylib"
echo ""
echo "已复制到 Flutter 项目："
echo "  - $ios_libs/libmtcore.dylib"
echo "  - $ios_libs/mt_core.h"
echo ""
echo "下一步："
echo "1. 在 Xcode 中打开 ios/Runner.xcworkspace"
echo "2. 将 Frameworks/libmtcore.dylib 添加到项目"
echo "3. 在 Build Phases -> Link Binary With Libraries 中添加该库"
echo "4. 设置 Embed & Sign"
