# iOS 版本开发总结

## ✅ 结论：**可以做 iOS 版本**

这个项目使用 Flutter 跨平台框架开发，已经包含了 iOS 的基础支持。主要工作是编译 C++ 引擎并配置 Xcode 项目。

---

## 📋 已完成的工作

我已经为你准备了以下文件和脚本：

### 1. **iOS 引擎编译脚本**
- 📄 `tools/build_ios_engine.sh` - 编译 C++ 引擎（arm64 + x86_64）

### 2. **iOS App 构建脚本**  
- 📄 `tools/build_ios.sh` - 构建 Flutter iOS 应用

### 3. **完整构建指南**
- 📄 `docs/ios-build-guide.md` - 详细的 iOS 构建文档（80+ 行）

### 4. **CMakeLists.txt 更新**
- ✅ 修改了 `engine/CMakeLists.txt`，添加了 iOS 特定配置
- 支持生成 iOS Framework
- 正确处理符号导出

---

## 🎯 已具备的条件

### Flutter 层面
✅ **跨平台支持**：Flutter 天然支持 iOS  
✅ **iOS 项目结构**：`app/ios/` 目录完整（包含 Xcode 项目）  
✅ **依赖兼容**：所有依赖都是跨平台的
- `ffi: ^2.1.4` - FFI 支持
- `path_provider: ^2.1.5` - 文件路径
- `crypto: ^3.0.6` - 哈希校验
- `url_launcher: 6.3.2` - URL 跳转

### C++ 引擎层面
✅ **llama.cpp 支持 iOS**：底层推理引擎原生支持 iOS  
✅ **FFI 绑定已支持 iOS**：`mt_bindings.dart` 中已处理 iOS 平台
```dart
if (Platform.isIOS || Platform.isMacOS) return DynamicLibrary.process();
```

### 应用配置
✅ **Info.plist 已配置**：包含应用名称、权限等  
✅ **资源文件就绪**：字体、图片等已配置在 pubspec.yaml

---

## 🛠️ 需要完成的工作

### 1. **编译 C++ 引擎** ⭐ 最关键
```bash
# 必须在 macOS 上执行
cd xamal-tarjima
chmod +x tools/build_ios_engine.sh
./tools/build_ios_engine.sh
```

这会生成：
- `libmtcore.dylib` (arm64 - iPhone 真机)
- `libmtcore.dylib` (x86_64 - iOS 模拟器)
- Universal Binary (两者合并)

### 2. **配置 Xcode 项目**
1. 打开 `app/ios/Runner.xcworkspace`
2. 添加编译好的 `libmtcore.dylib` 到项目
3. 设置为 "Embed & Sign"
4. 配置签名证书（需要 Apple Developer Account）

### 3. **构建 iOS App**
```bash
chmod +x tools/build_ios.sh
./tools/build_ios.sh
```

### 4. **打包发布**
- 通过 Xcode Archive 生成 IPA
- 上传到 App Store Connect
- 或用于 TestFlight 测试

---

## 💻 环境要求

### 必需条件
- ✅ **macOS 系统**（无法在 Windows/Linux 上构建 iOS）
- ✅ **Xcode 14.0+**
- ✅ **Flutter SDK**（已有 Android 开发环境）
- ✅ **CMake 3.22+**
- ✅ **Apple Developer Account**（发布到 App Store 需要，开发测试可用免费账号）

### 检查命令
```bash
xcodebuild -version        # 检查 Xcode
flutter doctor             # 检查 Flutter
cmake --version            # 检查 CMake
```

---

## 🔥 核心差异：iOS vs Android

| 方面 | Android | iOS |
|------|---------|-----|
| **引擎打包** | `.so` 动态库，通过 jniLibs | `.dylib` 或 Framework，静态链接 |
| **FFI 加载** | `DynamicLibrary.open('libmtcore.so')` | `DynamicLibrary.process()` |
| **模型存储** | `getFilesDir()` | `Application Support` |
| **线程策略** | 大小核探测（针对骁龙等） | 统一核心架构（A 系列芯片）|
| **构建工具** | Gradle + NDK | Xcode + CMake |
| **签名** | 可选（调试不需要） | 必需（即使开发也要签名）|

---

## ⚠️ 注意事项

### 1. **性能差异**
- iOS 设备（A 系列芯片）架构与 Android（骁龙等）不同
- 可能需要调整线程数配置
- 建议在不同代际 iPhone 上测试（iPhone 12, 13, 14, 15）

### 2. **内存管理**
- iOS 内存管理更严格
- 模型加载约 2GB 内存，确保在老设备上也能运行
- 注意后台时的内存清理

### 3. **App Store 审核**
- **隐私声明**：明确说明数据采集范围（如果启用统计）
- **首次下载**：440MB 模型需在描述中说明
- **离线特性**：强调隐私保护优势
- **出口合规**：声明使用标准加密

### 4. **代码签名**
- 开发测试：可用免费 Apple ID，但每 7 天需重新签名
- 正式发布：需要付费开发者账号（$99/年）

---

## 📱 功能对比

以下功能在 iOS 和 Android 上完全一致：

✅ **核心翻译功能**：维吾尔语 ⇄ 哈萨克语 ⇄ 汉语  
✅ **完全离线**：所有推理在本地完成  
✅ **隐私保护**：数据不出设备  
✅ **智能缓存**：译文缓存复用  
✅ **历史记录**：本地存储  
✅ **自定义字体**：内置阿拉伯文字体  

可选功能（可通过编译选项禁用）：
- 📊 匿名使用统计
- 🎨 运营横幅
- 🔄 版本更新检查

---

## 🚀 快速开始（假设你有 macOS）

```bash
# 1. 克隆项目（已完成）
cd xamal-tarjima

# 2. 编译 iOS 引擎
chmod +x tools/build_ios_engine.sh
./tools/build_ios_engine.sh

# 3. 配置后端密钥（如果需要联网功能）
# 编辑 backend/.secrets.env，添加 APP_TAG

# 4. 构建 iOS App
chmod +x tools/build_ios.sh
./tools/build_ios.sh

# 5. 在 Xcode 中打开项目
open app/ios/Runner.xcworkspace

# 6. 配置签名并运行
# 在 Xcode 中选择 Team、连接设备、点击 Run
```

---

## 📚 相关文档

- **详细构建指南**：`docs/ios-build-guide.md`（已创建）
- **Flutter iOS 部署**：https://docs.flutter.dev/deployment/ios
- **llama.cpp iOS**：https://github.com/ggerganov/llama.cpp/tree/master/examples/llama.ios

---

## 🤝 后续支持

如果在构建过程中遇到问题，可以：
1. 查看 `docs/ios-build-guide.md` 的"常见问题"部分
2. 检查 Flutter 环境：`flutter doctor -v`
3. 清理并重新构建：
   ```bash
   flutter clean
   rm -rf ios/Pods ios/.symlinks
   cd ios && pod install
   ```

---

## ✨ 总结

**这个项目完全可以做 iOS 版本**，而且大部分跨平台工作已经完成。主要任务是：

1. ✅ **在 macOS 上编译 C++ 引擎**（已提供脚本）
2. ✅ **在 Xcode 中配置项目**（标准流程）
3. ✅ **构建和签名**（已提供脚本）

技术栈选择（Flutter + llama.cpp）天然支持 iOS，代码质量也很高，iOS 版本的开发难度不大。

如果你现在没有 macOS 环境，可以考虑：
- 使用 macOS 虚拟机（需要高配电脑）
- 租用云端 macOS 服务器
- 借用/购买 Mac mini 等设备

祝开发顺利！🎉
