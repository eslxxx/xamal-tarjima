# iOS 版本构建指南

本文档说明如何为 Tilmach 构建 iOS 版本。

## 前提条件

### 硬件和软件要求
- **macOS** 系统（必须）
- **Xcode** 14.0 或更高版本
- **Flutter** SDK（与 Android 版本使用的相同）
- **CMake** 3.22 或更高版本
- **Apple Developer Account**（用于签名和发布）

### 检查环境
```bash
# 检查 Xcode
xcodebuild -version

# 检查 Flutter
flutter doctor

# 检查 CMake
cmake --version
```

## 构建步骤

### 第一步：编译 C++ 引擎

iOS 需要单独编译 C++ 引擎库。项目中已提供构建脚本：

```bash
# 必须在 macOS 上执行
cd xamal-tarjima
chmod +x tools/build_ios_engine.sh
./tools/build_ios_engine.sh
```

这个脚本会：
1. 编译 arm64 版本（iPhone 真机）
2. 编译 x86_64 版本（iOS 模拟器）
3. 创建 Universal Binary
4. 将库文件复制到 Flutter iOS 项目中

### 第二步：配置 Xcode 项目

1. **打开 Xcode 项目**
   ```bash
   cd app/ios
   open Runner.xcworkspace
   ```

2. **添加引擎库**
   - 在 Xcode 左侧项目导航器中，右键点击 `Runner` 项目
   - 选择 "Add Files to Runner..."
   - 导航到 `ios/Frameworks/` 目录
   - 选择 `libmtcore.dylib` 并添加

3. **配置链接设置**
   - 选择 `Runner` 项目
   - 选择 `Runner` Target
   - 切换到 "Build Phases" 标签
   - 在 "Link Binary With Libraries" 中确认 `libmtcore.dylib` 已添加
   - 在 "Embed Frameworks" 中添加 `libmtcore.dylib`，设置为 "Embed & Sign"

4. **配置签名**
   - 切换到 "Signing & Capabilities" 标签
   - 选择你的 Team
   - 修改 Bundle Identifier（如果需要）
   - 确保 "Automatically manage signing" 已勾选

### 第三步：配置后端服务（可选）

如果需要联网功能（统计、横幅、版本检查），需要配置 `backend/.secrets.env`：

```bash
# backend/.secrets.env
APP_TAG=your_secret_tag_here
```

### 第四步：构建 iOS App

使用提供的构建脚本：

```bash
# 构建正式版本（带统计和网络功能）
chmod +x tools/build_ios.sh
./tools/build_ios.sh

# 或构建完全离线版本（不联网）
TILMACH_BASE= ./tools/build_ios.sh
```

或者手动使用 Flutter 命令：

```bash
cd app
flutter build ios --release \
  --dart-define=TILMACH_TELEMETRY_URL="https://lg.xamal.top/v1/ping" \
  --dart-define=TILMACH_TELEMETRY_TAG="your_tag" \
  --dart-define=TILMACH_CONFIG_URL="https://lg.xamal.top/v1/config"
```

### 第五步：打包和发布

#### 方法 1：通过 Xcode Archive

1. 在 Xcode 中选择 "Product" > "Archive"
2. 等待 Archive 完成
3. 在 Organizer 窗口中选择刚创建的 Archive
4. 点击 "Distribute App"
5. 选择发布方式：
   - **App Store Connect**: 上传到 App Store
   - **Ad Hoc**: 用于内部测试
   - **Enterprise**: 企业分发
   - **Development**: 开发测试

#### 方法 2：命令行导出 IPA

```bash
# 先 Archive
xcodebuild -workspace ios/Runner.xcworkspace \
  -scheme Runner \
  -configuration Release \
  -archivePath build/Runner.xcarchive \
  archive

# 导出 IPA
xcodebuild -exportArchive \
  -archivePath build/Runner.xcarchive \
  -exportPath build/ios/ipa \
  -exportOptionsPlist ios/ExportOptions.plist
```

## 模型文件配置

iOS 版本和 Android 版本一样，首次启动需要下载 440MB 的模型文件。模型会存储在：

```
Application Support/models/model.gguf
```

### 开发时使用本地模型

代码中有开发模式的旁路，但**仅在 Android 上有效**。iOS 开发时如果要跳过下载：

1. 修改 `app/lib/main.dart` 中的 `_devModelPath()` 函数
2. 或者通过 iTunes/Finder 文件共享手动放入模型文件

## 常见问题

### 1. 编译引擎失败

**问题**: CMake 找不到 iOS SDK
```
CMake Error: Could not find iOS SDK
```

**解决**: 确保 Xcode Command Line Tools 已安装
```bash
xcode-select --install
xcode-select -p  # 应该显示 Xcode 路径
```

### 2. 链接错误

**问题**: 链接时找不到 `mt_init` 等符号

**解决**: 
1. 确认 `libmtcore.dylib` 已添加到 "Link Binary With Libraries"
2. 检查库文件是否正确编译（文件大小应该在几十 MB）
3. 尝试清理并重新构建：
   ```bash
   flutter clean
   rm -rf ios/Pods ios/.symlinks
   cd ios && pod install
   ```

### 3. 签名问题

**问题**: 代码签名失败

**解决**:
1. 确保你有有效的 Apple Developer Account
2. 在 Xcode 中正确选择 Team
3. 如果是免费账号，需要修改 Bundle Identifier 为唯一值
4. 检查 Provisioning Profile 是否过期

### 4. 运行时崩溃

**问题**: App 启动时崩溃，日志显示找不到库

**解决**:
1. 确保 `libmtcore.dylib` 设置为 "Embed & Sign"
2. 检查 "Build Phases" > "Embed Frameworks" 中是否包含该库
3. 在设备上测试前，先在模拟器上测试

### 5. Flutter 找不到 FFI 绑定

**问题**: `DynamicLibrary.open()` 失败

**解决**:
检查 `app/lib/core/ffi/mt_bindings.dart` 中的库加载逻辑，确保 iOS 路径正确：
```dart
// 应该类似这样
final lib = Platform.isIOS
    ? DynamicLibrary.process()  // 或者 DynamicLibrary.open('mtcore.framework/mtcore')
    : DynamicLibrary.open('libmtcore.so');
```

## 性能优化建议

1. **确保使用 Release 模式**：Debug 模式性能差很多
2. **测试不同设备**：在旧款和新款 iPhone 上都要测试
3. **监控内存使用**：模型加载会占用大量内存（~2GB）
4. **优化线程数**：iOS 设备的 CPU 核心配置与 Android 不同

## App Store 提交注意事项

### 隐私声明

App 收集的数据（如果启用统计功能）：
- 匿名使用数据（启动次数、翻译次数）
- 不收集个人信息、IP、位置、用户输入内容

在 App Store Connect 中正确填写隐私声明。

### 审核准备

1. 准备截图（至少 5.5" 和 6.5" 尺寸）
2. 准备应用描述（支持维吾尔语、哈萨克语的离线翻译）
3. 强调隐私保护特性（完全离线、数据不出设备）
4. 说明首次启动需要下载模型（440MB）

### 出口合规

由于使用加密技术（HTTPS），需要声明出口合规。通常选择：
- "使用标准加密"
- "仅用于应用内通信"

## 维护和更新

### 更新模型

如果需要更新翻译模型：
1. 更新 `models/` 目录中的模型文件
2. 更新模型下载 URL（在代码中配置）
3. 更新版本号
4. 提交 App 更新

### 更新依赖

定期更新 Flutter 和依赖：
```bash
flutter pub upgrade
cd ios && pod update
```

## 参考资料

- [Flutter iOS 部署文档](https://docs.flutter.dev/deployment/ios)
- [Xcode 用户指南](https://developer.apple.com/documentation/xcode)
- [App Store 审核指南](https://developer.apple.com/app-store/review/guidelines/)
- [llama.cpp iOS 集成](https://github.com/ggerganov/llama.cpp/tree/master/examples/llama.ios)
