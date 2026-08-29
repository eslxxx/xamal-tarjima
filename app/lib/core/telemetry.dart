/// 活跃度统计。
///
/// 目的只有一个: 让作者判断这个免费 App 还值不值得继续维护 —— 有多少人装了、
/// 还有多少人在用、用得频不频繁。除此之外一个字节都不多采。
///
/// ## 采什么
///   - 安装 ID: 首启生成的随机 UUIDv4, **不含任何硬件信息**。
///     清除应用数据或重装会变成新 ID, 所以统计的是"安装"而不是"人", 这点是诚实的。
///   - 每天的启动次数、翻译次数
///   - app 版本 (用来看新版本的升级情况)
///
/// ## 不采什么
///   原文、译文、剪贴板、任何文本内容;
///   IP 地址 (公网 IP 离线时本来也拿不到, 局域网 IP 对统计毫无意义);
///   IMEI / Android ID / 任何硬件标识;
///   地理位置、机型、系统版本 —— 用户基数小的时候这些组合起来能反推到个人。
///
/// ## 为什么不做事件队列
///   客户端只保留一个「最近 60 天的按天计数」窗口, 每次上报把这些天的**绝对值**
///   整体发给服务端 upsert。于是:
///     - 离线一周再联网, 一次补齐 7 天
///     - 重复上报无副作用 (幂等), 不需要 ack、不需要"已上传"标记
///     - 网络失败就下次再说, 数据一直在本地, 不会丢
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// 本地保留多少天的计数。超出的丢弃 —— 服务端已经有了, 客户端不需要留档。
const int _retainDays = 60;

/// 两次上报之间的最小间隔, 避免频繁切前后台时反复打服务器。
const Duration _minInterval = Duration(minutes: 30);

class _DayCount {
  _DayCount({this.launches = 0, this.translations = 0});

  int launches;
  int translations;

  Map<String, int> toJson() => {'l': launches, 't': translations};

  static _DayCount fromJson(Object? raw) {
    if (raw is! Map) return _DayCount();
    return _DayCount(
      launches: (raw['l'] as num?)?.toInt() ?? 0,
      translations: (raw['t'] as num?)?.toInt() ?? 0,
    );
  }
}

class Telemetry {
  Telemetry._();

  static final Telemetry instance = Telemetry._();

  /// 上报地址。部署好 Cloudflare Worker 后把域名填进来。
  /// 留空 = 整个统计功能静默关闭 (本地也不再记), 方便自己编一个不带统计的版本。
  static const String endpoint = String.fromEnvironment(
    'TILMACH_TELEMETRY_URL',
    defaultValue: '',
  );

  /// 和 Worker 约定的一个共享标识, 用来过滤掉扫端口的无关流量。
  /// **这不是安全措施** —— APK 可以被反编译出来。只是省点无效写入。
  static const String appTag = String.fromEnvironment(
    'TILMACH_TELEMETRY_TAG',
    defaultValue: 'tilmach',
  );

  File? _file;
  String? _installId;
  final _days = <String, _DayCount>{};
  DateTime? _lastFlush;
  bool _flushing = false;

  /// 由 AppSettings 控制; 用户关掉之后既不上报也不再本地累加。
  bool enabled = true;

  String get installId => _installId ?? '';

  bool get _configured => endpoint.isNotEmpty;

  static String _today() {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-'
        '${n.day.toString().padLeft(2, '0')}';
  }

  /// UUIDv4。用 Random.secure() 而不是普通 Random —— 安装 ID 不该可预测,
  /// 否则别人能伪造别人的 ID 往后台灌数据。
  static String _uuidV4() {
    final r = Random.secure();
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40; // version 4
    b[8] = (b[8] & 0x3f) | 0x80; // variant 10
    String hex(int start, int end) =>
        b.sublist(start, end).map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
  }

  // ── 本地状态 ────────────────────────────────────────────

  Future<void> init(File file, {required bool enabled}) async {
    _file = file;
    this.enabled = enabled;
    try {
      if (await file.exists()) {
        final raw = jsonDecode(await file.readAsString());
        if (raw is Map) {
          _installId = raw['id'] as String?;
          final days = raw['days'];
          if (days is Map) {
            days.forEach((k, v) {
              if (k is String) _days[k] = _DayCount.fromJson(v);
            });
          }
        }
      }
    } catch (_) {
      // 统计文件坏了绝不能影响 App 启动
      _days.clear();
    }
    _installId ??= _uuidV4();
    _prune();
    await _save();
  }

  void recordLaunch() {
    if (!enabled || !_configured) return;
    (_days[_today()] ??= _DayCount()).launches++;
    _save();
  }

  void recordTranslation() {
    if (!enabled || !_configured) return;
    (_days[_today()] ??= _DayCount()).translations++;
    // 翻译很频繁, 不每次写盘; 靠 flush / 生命周期 pause 时落盘
  }

  void _prune() {
    if (_days.length <= _retainDays) return;
    final keys = _days.keys.toList()..sort();
    for (final k in keys.take(_days.length - _retainDays)) {
      _days.remove(k);
    }
  }

  Future<void> _save() async {
    final f = _file;
    if (f == null) return;
    try {
      await f.parent.create(recursive: true);
      await f.writeAsString(jsonEncode({
        'id': _installId,
        'days': {for (final e in _days.entries) e.key: e.value.toJson()},
      }));
    } catch (_) {}
  }

  /// 用户在设置里关掉统计: 停止累加, 并清掉本地已攒的数据。
  Future<void> disableAndPurge() async {
    enabled = false;
    _days.clear();
    await _save();
  }

  // ── 上报 ────────────────────────────────────────────────
  //
  // 每次把本地保留的所有天数的**绝对值**整体发过去, 服务端 upsert。
  // 所以重复上报没有副作用, 失败了也不用记账 —— 下次连上网自然补齐。

  /// [force] 用于「立即上报」这类手动触发, 跳过最小间隔限制。
  Future<bool> flush({bool force = false}) async {
    if (!enabled || !_configured || _flushing) return false;
    if (_days.isEmpty) return false;
    if (!force && _lastFlush != null &&
        DateTime.now().difference(_lastFlush!) < _minInterval) {
      return false;
    }

    _flushing = true;
    await _save(); // 先落盘, 万一上报过程中进程被杀也不丢
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10)
      ..userAgent = 'Tilmach/$_appVersion';
    try {
      final body = jsonEncode({
        'tag': appTag,
        'install_id': _installId,
        'app_version': _appVersion,
        'days': [
          for (final e in _days.entries)
            {'day': e.key, 'launches': e.value.launches, 'translations': e.value.translations},
        ],
      });
      final req = await client.postUrl(Uri.parse(endpoint));
      req.headers.contentType = ContentType.json;
      req.write(body);
      final resp = await req.close().timeout(const Duration(seconds: 20));
      await resp.drain<void>();
      final ok = resp.statusCode >= 200 && resp.statusCode < 300;
      if (ok) _lastFlush = DateTime.now();
      return ok;
    } catch (_) {
      // 没网、超时、服务端挂了 —— 都不是错误, 数据还在本地, 下次再来
      return false;
    } finally {
      client.close(force: true);
      _flushing = false;
    }
  }

  /// 版本号。与 pubspec 的 version 保持一致; 改版本时记得同步。
  static const String _appVersion = '1.0.0';

  /// 设置页展示用: 本地还有多少天的数据、最近一次上报成功是什么时候。
  int get pendingDays => _days.length;
  DateTime? get lastFlushAt => _lastFlush;

  /// 当天计数, 给设置页显示"你今天用了几次"。
  ({int launches, int translations}) get today {
    final d = _days[_today()] ?? _DayCount();
    return (launches: d.launches, translations: d.translations);
  }

  /// 生命周期 pause 时调用: 落盘 + 顺手尝试上报。
  Future<void> onPause() async {
    await _save();
    await flush();
  }
}


