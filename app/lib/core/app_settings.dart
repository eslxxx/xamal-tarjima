/// 用户可调的设置项。
///
/// 用 JSON 文件而不是 shared_preferences: 项目里已经有两处 JSON 落盘的同类代码,
/// 保持一致, 也少一个带原生实现的依赖。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

class AppSettings extends ChangeNotifier {
  AppSettings._();

  static final AppSettings instance = AppSettings._();

  File? _file;

  /// 采样模式。
  ///
  /// false (默认) = 贪心解码: 同一句永远得到同一结果, 速度也略快。
  /// true = 官方推荐参数 (temperature 0.7 / top_p 0.6 / top_k 20): 措辞更灵活,
  ///        但同一句每次结果可能不同, 而 1.25bit 模型在随机采样下更容易跑偏。
  bool _officialSampling = false;
  bool get officialSampling => _officialSampling;
  set officialSampling(bool v) {
    if (_officialSampling == v) return;
    _officialSampling = v;
    notifyListeners();
    _save();
  }

  /// 是否把翻译记进历史。关掉之后不再新增记录 (已有的不动)。
  bool _keepHistory = true;
  bool get keepHistory => _keepHistory;
  set keepHistory(bool v) {
    if (_keepHistory == v) return;
    _keepHistory = v;
    notifyListeners();
    _save();
  }

  /// 是否上传匿名活跃度统计。
  ///
  /// 采集内容仅限: 随机安装 ID、每天的启动/翻译次数、app 版本。
  /// 不含 IP、位置、硬件标识, 也不含任何原文或译文。
  bool _telemetry = true;
  bool get telemetry => _telemetry;
  set telemetry(bool v) {
    if (_telemetry == v) return;
    _telemetry = v;
    notifyListeners();
    _save();
  }

  Future<void> load(File file) async {
    _file = file;
    try {
      if (!await file.exists()) return;
      final raw = jsonDecode(await file.readAsString());
      if (raw is! Map) return;
      _officialSampling = raw['officialSampling'] == true;
      _keepHistory = raw['keepHistory'] != false; // 缺省为 true
      _telemetry = raw['telemetry'] != false;       // 缺省为 true
      notifyListeners();
    } catch (_) {
      // 设置坏了用默认值, 不该让 App 起不来
    }
  }

  Future<void> _save() async {
    final f = _file;
    if (f == null) return;
    try {
      await f.parent.create(recursive: true);
      await f.writeAsString(jsonEncode({
        'officialSampling': _officialSampling,
        'keepHistory': _keepHistory,
        'telemetry': _telemetry,
      }));
    } catch (_) {}
  }
}
