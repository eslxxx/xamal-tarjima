/// 译文缓存。
///
/// 为什么值得做: CPU 推理一句要 1.6~5s。用户在长文末尾加一个字, 如果整段重翻,
/// 前面每句都要重新等一遍 —— 这是最常见的编辑动作, 也是体感最差的地方。
///
/// 所以缓存粒度是**句子**而不是整段: 编辑末尾时前面的句子全部命中缓存秒出,
/// 只有真正改动的那句才跑推理。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'langs.dart';

class TranslationCache {
  TranslationCache._();

  static final TranslationCache instance = TranslationCache._();

  /// LRU: Dart 的 Map 保持插入顺序, 命中时删掉再插回队尾即可。
  final _map = <String, String>{};
  static const _maxEntries = 600;

  File? _file;
  Timer? _flushTimer;
  bool _dirty = false;

  static String _key(Lang from, Lang to, String text) =>
      '${specOf(from).code}>${specOf(to).code} ${text.trim()}';

  String? get(Lang from, Lang to, String text) {
    final k = _key(from, to, text);
    final v = _map.remove(k);
    if (v == null) return null;
    _map[k] = v; // 提到队尾
    return v;
  }

  void put(Lang from, Lang to, String text, String translation) {
    if (text.trim().isEmpty || translation.trim().isEmpty) return;
    final k = _key(from, to, text);
    _map.remove(k);
    _map[k] = translation;
    while (_map.length > _maxEntries) {
      _map.remove(_map.keys.first);
    }
    _dirty = true;
    _scheduleFlush();
  }

  int get size => _map.length;

  void clear() {
    _map.clear();
    _dirty = true;
    _scheduleFlush();
  }

  // ── 落盘 ────────────────────────────────────────────────
  //
  // 存成一个 JSON 文件就够了: 几百条短字符串, 体积在几十 KB 量级,
  // 上 sqlite 是杀鸡用牛刀。写入做 2s 防抖, 避免边打字边频繁写盘。

  Future<void> load(File file) async {
    _file = file;
    try {
      if (!await file.exists()) return;
      final raw = jsonDecode(await file.readAsString());
      if (raw is! Map) return;
      for (final e in raw.entries) {
        if (e.key is String && e.value is String) {
          _map[e.key as String] = e.value as String;
        }
      }
      while (_map.length > _maxEntries) {
        _map.remove(_map.keys.first);
      }
    } catch (_) {
      // 缓存坏了不是错误, 丢掉重来即可 —— 绝不能因为它让 App 起不来
      _map.clear();
    }
  }

  void _scheduleFlush() {
    _flushTimer?.cancel();
    _flushTimer = Timer(const Duration(seconds: 2), flush);
  }

  Future<void> flush() async {
    final f = _file;
    if (f == null || !_dirty) return;
    _dirty = false;
    try {
      await f.parent.create(recursive: true);
      // 先写临时文件再改名, 避免写一半被杀留下坏 JSON
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(jsonEncode(_map));
      await tmp.rename(f.path);
    } catch (_) {
      // 落盘失败只影响下次启动的命中率, 不影响本次使用
    }
  }
}
