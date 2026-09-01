/// 运营位横幅 + 版本更新检查。
///
/// ## 为什么 App 要联网拉这个
/// 设置页顶部有一块横幅位, 内容由后台决定 (见 backend/src/banners.ts)。图片本体
/// 是一整张图, App 只负责圆角裁剪、轮播和点击 —— 后台换样式不用改 App。
///
/// ## 离线优先
/// 这是个离线翻译 App, 联网必须是"锦上添花"而不是前置条件:
///   - 拉配置失败 → 用磁盘上一次的; 磁盘也没有 → 用内置的那张 (画出来的, 不是图片文件)
///   - 图片按 id 存在磁盘上, id 变了才会重新下载 (后台换图 = 换 id, 所以不用管失效)
///   - 整个过程不阻塞界面, 也不弹任何错误
///
/// ## 不采集
/// 这个请求是纯 GET, 不带 install_id、不带任何查询参数, 服务端也不记 IP。
/// 它和 telemetry.dart 是两条独立的路 —— 关掉统计不影响横幅, 反之也一样。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// 后台地址。和统计用同一个域名, 但走 /v1/config。
/// 留空 = 不联网拉配置, 只显示内置横幅 (编一个完全不联网的版本时用)。
const String kConfigUrl = String.fromEnvironment(
  'TILMACH_CONFIG_URL',
  defaultValue: '',
);

/// 一条横幅。
class BannerItem {
  BannerItem({required this.id, required this.img, this.link});

  final String id;

  /// 远端图片地址
  final String img;

  /// 点击跳转; null = 整块不可点
  final String? link;

  /// 磁盘上缓存好的文件; null = 还没下载下来
  File? file;

  static BannerItem? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final img = raw['img'];
    if (id is! String || img is! String || id.isEmpty || img.isEmpty) return null;
    // id 同时是磁盘文件名, 必须挡住 ../ 这类
    if (!RegExp(r'^[A-Za-z0-9_-]{8,40}$').hasMatch(id)) return null;
    final link = raw['link'];
    return BannerItem(
      id: id,
      img: img,
      link: link is String && link.startsWith('http') ? link : null,
    );
  }

  Map<String, Object?> toJson() => {'id': id, 'img': img, 'link': link};
}

/// 后台发布的最新版本。
class ReleaseInfo {
  const ReleaseInfo({required this.version, this.notes, this.url});

  final String version;
  final String? notes;
  final String? url;

  static ReleaseInfo? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final v = raw['version'];
    if (v is! String || !RegExp(r'^\d+(\.\d+){0,3}$').hasMatch(v)) return null;
    final notes = raw['notes'];
    final url = raw['url'];
    return ReleaseInfo(
      version: v,
      notes: notes is String && notes.trim().isNotEmpty ? notes.trim() : null,
      url: url is String && url.startsWith('http') ? url : null,
    );
  }

  Map<String, Object?> toJson() => {'version': version, 'notes': notes, 'url': url};

  /// 逐段比较版本号。`1.0.10` 要大于 `1.0.9` —— 字符串比较会搞错这个。
  bool isNewerThan(String current) {
    final a = version.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final b = current.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    for (var i = 0; i < (a.length > b.length ? a.length : b.length); i++) {
      final x = i < a.length ? a[i] : 0;
      final y = i < b.length ? b[i] : 0;
      if (x != y) return x > y;
    }
    return false;
  }
}

class RemoteConfig extends ChangeNotifier {
  RemoteConfig._();

  static final RemoteConfig instance = RemoteConfig._();

  Directory? _dir;
  File? _jsonFile;

  List<BannerItem> _banners = const [];
  ReleaseInfo? _latest;
  bool _fetching = false;
  DateTime? _lastFetch;

  /// 后台配的横幅。空列表 = 界面显示内置的那张。
  List<BannerItem> get banners => _banners;

  ReleaseInfo? get latest => _latest;

  /// 上一次**成功**拿到响应的时刻; null = 从来没拉成功过。
  /// 「检查更新」靠它区分"确实是最新版"和"根本没连上"。
  DateTime? get lastFetchAt => _lastFetch;

  bool get configured => kConfigUrl.isNotEmpty;

  /// 两次拉取之间的最小间隔, 和服务端的 cache-control 对齐
  static const _minInterval = Duration(minutes: 30);

  // ── 启动 ────────────────────────────────────────────────

  /// 先读磁盘 (瞬间完成, 界面立刻有东西), 再在后台悄悄拉一次新的。
  Future<void> init(Directory dir) async {
    _dir = dir;
    _jsonFile = File('${dir.path}/config.json');
    await _loadDisk();
    // 不 await —— 拉不到就拉不到, 不能让设置页等网络
    if (configured) refresh();
  }

  Future<void> _loadDisk() async {
    final f = _jsonFile;
    if (f == null) return;
    try {
      if (!await f.exists()) return;
      _apply(jsonDecode(await f.readAsString()), fromDisk: true);
    } catch (_) {
      // 缓存坏了当没有
    }
  }

  Future<void> _saveDisk() async {
    final f = _jsonFile;
    if (f == null) return;
    try {
      await f.parent.create(recursive: true);
      await f.writeAsString(jsonEncode({
        'banners': [for (final b in _banners) b.toJson()],
        'latest': _latest?.toJson(),
      }));
    } catch (_) {}
  }

  // ── 拉取 ────────────────────────────────────────────────

  /// [force] 用于用户手动点「更新版本」, 跳过最小间隔。
  Future<void> refresh({bool force = false}) async {
    if (!configured || _fetching) return;
    if (!force && _lastFetch != null &&
        DateTime.now().difference(_lastFetch!) < _minInterval) {
      return;
    }
    _fetching = true;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final req = await client.getUrl(Uri.parse(kConfigUrl));
      final resp = await req.close().timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) return;
      // 后台最多 20 条横幅, 正常几 KB; 设个上限免得异常响应把内存吃掉
      final text = await resp
          .transform(utf8.decoder)
          .fold<StringBuffer>(StringBuffer(), (b, s) {
            if (b.length < 64 * 1024) b.write(s);
            return b;
          })
          .then((b) => b.toString());
      _lastFetch = DateTime.now();
      _apply(jsonDecode(text), fromDisk: false);
      await _saveDisk();
      await _fetchImages();
    } catch (_) {
      // 没网、超时、服务端挂了 —— 都不是错误, 磁盘上那份继续用
    } finally {
      client.close(force: true);
      _fetching = false;
    }
  }

  void _apply(Object? raw, {required bool fromDisk}) {
    if (raw is! Map) return;
    final list = raw['banners'];
    final next = <BannerItem>[];
    if (list is List) {
      for (final e in list) {
        final b = BannerItem.fromJson(e);
        if (b != null) next.add(b);
      }
    }
    _banners = next;
    _latest = ReleaseInfo.fromJson(raw['latest']);
    // 从磁盘恢复时把已经下载好的图片接上
    if (fromDisk) _linkCachedFiles();
    notifyListeners();
  }

  // ── 图片缓存 ────────────────────────────────────────────
  //
  // 后台换图一定会换 id (见 banners.ts 的 createBanner), 所以"文件存在"就等于
  // "内容是对的", 不需要 etag / 过期时间这套东西。

  File _imgFile(String id) => File('${_dir!.path}/banner_$id');

  void _linkCachedFiles() {
    if (_dir == null) return;
    for (final b in _banners) {
      final f = _imgFile(b.id);
      if (f.existsSync()) b.file = f;
    }
  }

  Future<void> _fetchImages() async {
    if (_dir == null) return;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      for (final b in _banners) {
        final f = _imgFile(b.id);
        if (await f.exists()) {
          b.file = f;
          continue;
        }
        try {
          final req = await client.getUrl(Uri.parse(b.img));
          final resp = await req.close().timeout(const Duration(seconds: 30));
          if (resp.statusCode != 200) continue;
          final bytes = await consolidateHttpClientResponseBytes(resp);
          // 后台限制单张 2MB, 这里留一点余量
          if (bytes.length > 3 * 1024 * 1024) continue;
          await f.parent.create(recursive: true);
          // 先写临时文件再改名 —— 中途断网不会留下一个半张图
          final tmp = File('${f.path}.part');
          await tmp.writeAsBytes(bytes, flush: true);
          await tmp.rename(f.path);
          b.file = f;
          notifyListeners();
        } catch (_) {
          // 这一张拉不到就算了, 继续下一张
        }
      }
      await _pruneImages();
    } finally {
      client.close(force: true);
    }
  }

  /// 删掉已经不在配置里的旧图, 免得越积越多。
  Future<void> _pruneImages() async {
    final dir = _dir;
    if (dir == null) return;
    try {
      final keep = {for (final b in _banners) 'banner_${b.id}'};
      await for (final e in dir.list()) {
        if (e is! File) continue;
        final name = e.uri.pathSegments.last;
        if (name.startsWith('banner_') && !keep.contains(name)) {
          await e.delete().catchError((_) => e);
        }
      }
    } catch (_) {}
  }
}
