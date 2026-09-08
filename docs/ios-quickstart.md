# iOS 版本快速参考

## ✅ 可以做！

这个 Flutter 项目已经支持 iOS，主要工作是编译 C++ 引擎。

---

## 📋 我已为你准备的文件

```
xamal-tarjima/
├── tools/
│   ├── build_ios_engine.sh  ← 编译 C++ 引擎（第一步）
│   └── build_ios.sh         ← 构建 Flutter App（第二步）
├── docs/
│   ├── ios-build-guide.md   ← 详细构建指南（80+ 行）
│   └── ios-summary.md       ← 完整技术总结
└── engine/
    └── CMakeLists.txt       ← 已更新支持 iOS
```

---

## 🚀 三步构建（需要 macOS）

### 第一步：编译引擎
```bash
cd xamal-tarjima
./tools/build_ios_engine.sh
```

### 第二步：配置 Xcode
```bash
open app/ios/Runner.xcworkspace
# 在 Xcode 中：
# 1. 添加 Frameworks/libmtcore.dylib
# 2. 设置为 "Embed & Sign"
# 3. 配置签名证书
```

### 第三步：构建 App
```bash
./tools/build_ios.sh
```

---

## 💻 环境要求

**必需：**
- macOS 系统
- Xcode 14.0+
- Flutter SDK
- CMake 3.22+

**可选：**
- Apple Developer Account（发布需要，开发测试可用免费账号）

---

## 📖 详细文档

- **完整指南**：`docs/ios-build-guide.md`
  - 环境配置
  - 逐步构建流程
  - 常见问题解答
  - App Store 提交指南

- **技术总结**：`docs/ios-summary.md`
  - 技术分析
  - iOS vs Android 对比
  - 性能优化建议

---

## 🎯 核心优势

✅ Flutter 跨平台，90% 代码共享  
✅ FFI 绑定已支持 iOS  
✅ llama.cpp 原生支持 iOS  
✅ 离线翻译，隐私保护  
✅ 440MB 模型，一次下载永久使用  

---

## ⚠️ 关键注意

1. **必须在 macOS 上构建**（无法在 Windows/Linux 上完成）
2. **首次编译引擎需要较长时间**（10-30 分钟，取决于机器性能）
3. **测试多代设备**（iPhone 性能差异大）
4. **App Store 审核需说明 440MB 下载**

---

## 🆘 遇到问题？

查看 `docs/ios-build-guide.md` 的"常见问题"章节，包含：
- 编译引擎失败
- 链接错误
- 签名问题
- 运行时崩溃
- FFI 绑定问题

---

## 📱 功能完全一致

iOS 版本和 Android 版本功能 100% 相同：
- 维吾尔语 ⇄ 哈萨克语 ⇄ 汉语
- 完全离线运行
- 智能缓存
- 历史记录
- 自定义阿拉伯文字体

祝开发顺利！🎉
