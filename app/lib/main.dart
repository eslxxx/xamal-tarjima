// Tilmach — 离线维吾尔语 · 哈萨克语 · 汉语互译
//
// 模型: 腾讯混元 Hy-MT1.5-1.8B 1.25bit (Sherry 三值量化) + llama.cpp STQ1_0 kernel
// 翻译全程在本机 CPU 上完成。首次启动需要下载 440MB 模型;
// 之后只有匿名使用统计会联网 (可在设置里关闭), 原文和译文不出设备。

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'core/app_settings.dart';
import 'core/history_store.dart';
import 'core/model_manager.dart';
import 'core/telemetry.dart';
import 'core/translation_cache.dart';
import 'ui/app_shell.dart';
import 'ui/onboarding_page.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    systemNavigationBarColor: Colors.white,
    systemNavigationBarIconBrightness: Brightness.dark,
  ));

  final support = await getApplicationSupportDirectory();
  final manager = ModelManager(dir: Directory('${support.path}/models'));
  // 译文缓存落盘, 启动时读回来 —— 一句要跑 1.6~5s 推理, 重启后还能命中缓存很值。
  await TranslationCache.instance.load(File('${support.path}/translations.json'));
  await HistoryStore.instance.load(File('${support.path}/history.json'));
  await AppSettings.instance.load(File('${support.path}/settings.json'));

  // 活跃度统计: 只为判断这个免费 App 还值不值得继续维护。
  // 采集内容见 telemetry.dart 顶部说明; 用户可在设置里关闭。
  await Telemetry.instance.init(
    File('${support.path}/telemetry.json'),
    enabled: AppSettings.instance.telemetry,
  );
  Telemetry.instance.recordLaunch();
  // 启动时不立刻上报, 等界面稳定下来再说 —— 首屏要留给模型加载
  Future<void>.delayed(const Duration(seconds: 20), Telemetry.instance.flush);

  runApp(TilmachApp(manager: manager));
}

/// 开发期的模型旁路: external files dir 可以直接 `adb push` 进去,
/// 不用先走完下载流程。
///   adb push model.gguf /sdcard/Android/data/com.tilmach.translate/files/model.gguf
///
/// **只在 debug 构建里启用。** external files dir 是其它应用也能写的位置,
/// release 版如果也认这个路径, 等于允许任何应用往这里放一个精心构造的 GGUF
/// 让 llama.cpp 去解析 —— 那是一个白送的攻击面。正式版只认下载器校验过
/// (sha256 + 架构检查) 并落在应用私有目录里的那份。
Future<String?> _devModelPath() async {
  if (!kDebugMode || !Platform.isAndroid) return null;
  final ext = await getExternalStorageDirectory();
  if (ext == null) return null;
  final f = File('${ext.path}/model.gguf');
  return await f.exists() ? f.path : null;
}

class TilmachApp extends StatelessWidget {
  const TilmachApp({super.key, required this.manager});

  final ModelManager manager;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '翻译',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: T.bgBottom,
        colorScheme: ColorScheme.fromSeed(seedColor: T.blue, surface: T.bgBottom),
        splashFactory: InkSparkle.splashFactory,
      ),
      home: _Boot(manager: manager),
    );
  }
}

/// 决定进下载引导页还是主界面。
class _Boot extends StatefulWidget {
  const _Boot({required this.manager});

  final ModelManager manager;

  @override
  State<_Boot> createState() => _BootState();
}

class _BootState extends State<_Boot> {
  String? _modelPath;
  bool _checked = false;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    final dev = await _devModelPath();
    final path = dev ?? (await widget.manager.isReady() ? widget.manager.file.path : null);
    if (mounted) {
      setState(() {
        _modelPath = path;
        _checked = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_checked) {
      return const Scaffold(
        backgroundColor: T.bgBottom,
        body: Center(child: CircularProgressIndicator(color: T.blue)),
      );
    }
    if (_modelPath == null) {
      return OnboardingPage(
        manager: widget.manager,
        onReady: () => setState(() => _modelPath = widget.manager.file.path),
      );
    }
    return AppShell(
      modelPath: _modelPath!,
      manager: widget.manager,
      // 设置页删掉模型后回到下载引导页
      onModelDeleted: () => setState(() => _modelPath = null),
    );
  }
}
