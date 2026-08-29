/// 历史记录与收藏。
///
/// 两者共用一份存储: 一条记录就是一次翻译, `favorited` 标记它是否被收藏。
/// 这样"先看到历史里某条、再点星收藏"不需要复制数据, 也不会出现两边不一致。
///
/// 落盘用 JSON 文件, 和 [TranslationCache] 同一套做法 —— 几百条短文本, 上 sqlite
/// 是杀鸡用牛刀, 而且能少一个带原生代码的依赖。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'langs.dart';

class TranslationRecord {
  TranslationRecord({
    required this.from,
    required this.to,
    required this.source,
    required this.translation,
    required this.at,
    this.favorited = false,
  });

  final Lang from;
  final Lang to;
  final String source;
  final String translation;
  final DateTime at;
  bool favorited;

  /// 同一方向 + 同一原文视为同一条, 重复翻译只更新时间和译文而不新增。
  String get key => '${specOf(from).code}>${specOf(to).code} ${source.trim()}';

  Map<String, dynamic> toJson() => {
        'f': specOf(from).code,
        't': specOf(to).code,
        's': source,
        'r': translation,
        'at': at.millisecondsSinceEpoch,
        if (favorited) 'fav': true,
      };

  static Lang? _lang(String? code) {
    for (final l in Lang.values) {
      if (specOf(l).code == code) return l;
    }
    return null;
  }

  static TranslationRecord? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final from = _lang(raw['f'] as String?);
    final to = _lang(raw['t'] as String?);
    final s = raw['s'], r = raw['r'], at = raw['at'];
    if (from == null || to == null || s is! String || r is! String) return null;
    return TranslationRecord(
      from: from,
      to: to,
      source: s,
      translation: r,
      at: DateTime.fromMillisecondsSinceEpoch(at is int ? at : 0),
      favorited: raw['fav'] == true,
    );
  }
}

class HistoryStore extends ChangeNotifier {
  HistoryStore._();

  static final HistoryStore instance = HistoryStore._();

  /// 新的在前
  final _records = <TranslationRecord>[];

  /// 未收藏的历史条数上限。收藏过的永不自动清除 —— 用户主动标过的东西
  /// 不能因为「攒够 300 条」就消失。
  static const _maxUnfavorited = 300;

  File? _file;
  Timer? _flushTimer;
  bool _dirty = false;

  List<TranslationRecord> get all => List.unmodifiable(_records);
  List<TranslationRecord> get favorites =>
      _records.where((e) => e.favorited).toList(growable: false);

  int get count => _records.length;
  int get favoriteCount => _records.where((e) => e.favorited).length;

  TranslationRecord? find(Lang from, Lang to, String source) {
    final k = '${specOf(from).code}>${specOf(to).code} ${source.trim()}';
    for (final r in _records) {
      if (r.key == k) return r;
    }
    return null;
  }

  bool isFavorited(Lang from, Lang to, String source) =>
      find(from, to, source)?.favorited ?? false;

  /// 记一次翻译。同一方向同一原文只更新, 不重复堆积。
  void record({
    required Lang from,
    required Lang to,
    required String source,
    required String translation,
  }) {
    final src = source.trim();
    if (src.isEmpty || translation.trim().isEmpty) return;

    final existing = find(from, to, src);
    if (existing != null) {
      _records.remove(existing);
      _records.insert(
          0,
          TranslationRecord(
            from: from,
            to: to,
            source: src,
            translation: translation,
            at: DateTime.now(),
            favorited: existing.favorited,
          ));
    } else {
      _records.insert(
          0,
          TranslationRecord(
            from: from,
            to: to,
            source: src,
            translation: translation,
            at: DateTime.now(),
          ));
    }
    _trim();
    _changed();
  }

  /// 切换收藏。返回切换后的状态。
  bool toggleFavorite({
    required Lang from,
    required Lang to,
    required String source,
    required String translation,
  }) {
    var r = find(from, to, source);
    if (r == null) {
      // 还没入过历史 (比如缓存命中直接出结果) → 先补一条
      record(from: from, to: to, source: source, translation: translation);
      r = find(from, to, source);
      if (r == null) return false;
    }
    r.favorited = !r.favorited;
    _trim();
    _changed();
    return r.favorited;
  }

  void remove(TranslationRecord r) {
    _records.remove(r);
    _changed();
  }

  /// 只清历史, 保留收藏 —— 这是用户点「清空历史」时的预期
  void clearHistoryKeepFavorites() {
    _records.removeWhere((e) => !e.favorited);
    _changed();
  }

  void clearAll() {
    _records.clear();
    _changed();
  }

  void _trim() {
    var unfav = 0;
    _records.removeWhere((r) {
      if (r.favorited) return false;
      return ++unfav > _maxUnfavorited;
    });
  }

  void _changed() {
    _dirty = true;
    notifyListeners();
    _flushTimer?.cancel();
    _flushTimer = Timer(const Duration(seconds: 2), flush);
  }

  // ── 落盘 ────────────────────────────────────────────────

  Future<void> load(File file) async {
    _file = file;
    try {
      if (!await file.exists()) return;
      final raw = jsonDecode(await file.readAsString());
      if (raw is! List) return;
      _records
        ..clear()
        ..addAll(raw.map(TranslationRecord.fromJson).whereType<TranslationRecord>());
      _trim();
      notifyListeners();
    } catch (_) {
      // 记录坏了不该让 App 起不来
      _records.clear();
    }
  }

  Future<void> flush() async {
    final f = _file;
    if (f == null || !_dirty) return;
    _dirty = false;
    try {
      await f.parent.create(recursive: true);
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(jsonEncode(_records.map((e) => e.toJson()).toList()));
      await tmp.rename(f.path);
    } catch (_) {
      // 落盘失败只影响下次启动, 不影响本次使用
    }
  }
}
