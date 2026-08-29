/// 模型下载与就绪检查。
///
/// 设计取舍:
///   - **不自建 CDN**。这是个免费不商业化的 App, 440MB × 用户数的流量费不可持续。
///     所以直接用公共镜像, 按顺序回退。
///   - 校验用的是**官方原始文件**的 sha256。下载校验通过后再做 GGUF 类型号归一化
///     (见 gguf_normalize.dart), 归一化会改变文件哈希, 所以用一个 `.ready` 标记文件
///     记下"这份文件已校验且已归一化", 避免每次启动重算 440MB 的哈希。
///   - 断点续传是必须的: hf-mirror 会 302 到 AWS CDN, 那一段实测经常中途断流。
library;

import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'gguf_normalize.dart';

class ModelSpec {
  const ModelSpec({
    required this.fileName,
    required this.sizeBytes,
    required this.sha256Hex,
    required this.mirrors,
  });

  final String fileName;
  final int sizeBytes;

  /// 官方原始文件的 sha256 (归一化之前)
  final String sha256Hex;

  /// 按顺序尝试的下载源
  final List<String> mirrors;

  String get sizeLabel => '${(sizeBytes / 1024 / 1024).round()} MB';
}

/// Hy-MT1.5-1.8B 1.25bit (Sherry 三值量化 STQ1_0)
const kModelSpec = ModelSpec(
  fileName: 'Hy-MT1.5-1.8B-1.25bit.gguf',
  sizeBytes: 461860704,
  sha256Hex: '93e025c93cc082e73a3f142b757623a8b9cf541c020a8013ca4ee669556860ab',
  mirrors: [
    // hf-mirror 在国内可达且快 (实测 huggingface.co 常不可达)
    'https://hf-mirror.com/tencent/Hy-MT1.5-1.8B-1.25bit-GGUF/resolve/main/Hy-MT1.5-1.8B-1.25bit.gguf',
    'https://huggingface.co/tencent/Hy-MT1.5-1.8B-1.25bit-GGUF/resolve/main/Hy-MT1.5-1.8B-1.25bit.gguf',
  ],
);

enum ModelStage { idle, downloading, verifying, normalizing, ready, failed }

class ModelProgress {
  const ModelProgress(this.stage,
      {this.received = 0, this.total = 0, this.message, this.bytesPerSec = 0});

  final ModelStage stage;
  final int received;
  final int total;
  final String? message;
  final double bytesPerSec;

  double get fraction => total > 0 ? (received / total).clamp(0.0, 1.0) : 0.0;
}

class ModelManager {
  ModelManager({required this.dir, this.spec = kModelSpec});

  /// 模型落地目录 (Application Support 下, 应用私有)
  final Directory dir;
  final ModelSpec spec;

  File get file => File('${dir.path}/${spec.fileName}');
  File get _partFile => File('${file.path}.part');
  File get _readyMarker => File('${file.path}.ready');

  bool _cancelled = false;
  void cancel() => _cancelled = true;

  /// 文件是否已经下载 + 校验 + 归一化完毕, 可以直接喂给引擎。
  Future<bool> isReady() async {
    if (!await file.exists()) return false;
    if (await file.length() != spec.sizeBytes) return false;
    if (!await _readyMarker.exists()) return false;
    // 标记文件里存的是官方原始文件的 sha256, 用来识别"这个标记是不是给这份模型的"
    return (await _readyMarker.readAsString()).trim() == spec.sha256Hex;
  }

  /// 已下载的字节数 (用于续传提示)
  Future<int> downloadedBytes() async =>
      await _partFile.exists() ? _partFile.length() : 0;

  /// 完整流程: 下载 → 校验 → 归一化 → 打标记。
  /// 每一步都往返回的 Stream 里报进度。
  Stream<ModelProgress> prepare() {
    final out = StreamController<ModelProgress>();
    _run(out).whenComplete(out.close);
    return out.stream;
  }

  Future<void> _run(StreamController<ModelProgress> out) async {
    _cancelled = false;
    try {
      if (await isReady()) {
        out.add(const ModelProgress(ModelStage.ready));
        return;
      }
      await dir.create(recursive: true);

      // 文件已在但没有 ready 标记 → 可能是上次校验/归一化没走完, 从校验开始重来
      if (await file.exists() && await file.length() == spec.sizeBytes) {
        if (await _verifyAndFinalize(out)) return;
        await file.delete();
      }

      await _download(out);
      if (_cancelled) {
        out.add(const ModelProgress(ModelStage.idle, message: '已取消'));
        return;
      }
      await _partFile.rename(file.path);
      if (await _verifyAndFinalize(out)) return;
      out.add(const ModelProgress(ModelStage.failed,
          message: '文件校验失败，请删除后重新下载'));
    } catch (e) {
      out.add(ModelProgress(ModelStage.failed, message: _friendly(e)));
    }
  }

  static String _friendly(Object e) {
    if (e is SocketException) return '网络连接失败，请检查网络后重试';
    if (e is HttpException) return '下载中断：${e.message}';
    if (e is FileSystemException) {
      return '写入文件失败：${e.osError?.message ?? e.message}';
    }
    return '$e';
  }

  // ── 下载 ────────────────────────────────────────────────
  //
  // 用 dart:io 的 HttpClient 而不是引第三方库: 需要的只是 Range 头和流式写盘,
  // 标准库够用, 少一个依赖少一份构建风险。
  //
  // 断点续传按镜像轮转重试: hf-mirror 会 302 到 AWS CDN, 那段常见
  // "连接被重置", 单纯 retry 同一个源不一定好, 换源往往立刻通。

  Future<void> _download(StreamController<ModelProgress> out) async {
    const maxAttempts = 40;
    Object? lastError;

    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      if (_cancelled) return;
      final already = await downloadedBytes();
      if (already >= spec.sizeBytes) return;

      final url = spec.mirrors[attempt % spec.mirrors.length];
      try {
        await _downloadOnce(url, already, out);
        if (await downloadedBytes() >= spec.sizeBytes) return;
      } catch (e) {
        lastError = e;
        final got = await downloadedBytes();
        out.add(ModelProgress(
          ModelStage.downloading,
          received: got,
          total: spec.sizeBytes,
          message: '连接中断，正在重试（第 ${attempt + 1} 次）',
        ));
        await Future<void>.delayed(const Duration(seconds: 2));
      }
    }
    throw lastError ?? const HttpException('重试次数过多');
  }

  Future<void> _downloadOnce(
      String url, int from, StreamController<ModelProgress> out) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20)
      ..idleTimeout = const Duration(seconds: 30)
      ..userAgent = 'Tilmach/1.0';
    try {
      final req = await client.getUrl(Uri.parse(url));
      if (from > 0) req.headers.set(HttpHeaders.rangeHeader, 'bytes=$from-');
      final resp = await req.close();

      // 服务端不支持 Range 就从头下 (206 = 部分内容, 200 = 全量)
      var received = from;
      if (from > 0 && resp.statusCode == HttpStatus.ok) {
        received = 0;
        if (await _partFile.exists()) await _partFile.delete();
      } else if (resp.statusCode != HttpStatus.ok &&
          resp.statusCode != HttpStatus.partialContent) {
        throw HttpException('HTTP ${resp.statusCode}', uri: Uri.parse(url));
      }

      final sink = await _partFile.open(
          mode: received > 0 ? FileMode.append : FileMode.write);
      final sw = Stopwatch()..start();
      var sinceTick = 0;
      var lastEmit = 0;
      try {
        await for (final chunk in resp) {
          if (_cancelled) break;
          sink.writeFromSync(chunk);
          received += chunk.length;
          sinceTick += chunk.length;
          // 200ms 节流, 否则 setState 会被刷爆
          if (sw.elapsedMilliseconds - lastEmit >= 200) {
            final dt = (sw.elapsedMilliseconds - lastEmit) / 1000.0;
            out.add(ModelProgress(
              ModelStage.downloading,
              received: received,
              total: spec.sizeBytes,
              bytesPerSec: dt > 0 ? sinceTick / dt : 0,
            ));
            lastEmit = sw.elapsedMilliseconds;
            sinceTick = 0;
          }
        }
      } finally {
        await sink.flush();
        await sink.close();
      }
    } finally {
      client.close(force: true);
    }
  }

  // ── 校验 + 归一化 ────────────────────────────────────────

  /// 返回 true 表示校验通过并已完成归一化和打标记。
  Future<bool> _verifyAndFinalize(StreamController<ModelProgress> out) async {
    out.add(ModelProgress(ModelStage.verifying,
        received: spec.sizeBytes, total: spec.sizeBytes, message: '正在校验文件完整性'));

    final hex = await _sha256OfFile(file);
    if (hex != spec.sha256Hex) return false;

    out.add(ModelProgress(ModelStage.normalizing,
        received: spec.sizeBytes, total: spec.sizeBytes, message: '正在准备模型'));
    final r = await normalizeStq1Gguf(file);
    if (r.architecture != 'hunyuan-dense') {
      out.add(const ModelProgress(ModelStage.failed, message: '模型文件不是预期的架构'));
      return true; // 已给出结论, 不要再往下走下载流程
    }

    await _readyMarker.writeAsString(spec.sha256Hex);
    out.add(ModelProgress(ModelStage.ready,
        received: spec.sizeBytes, total: spec.sizeBytes));
    return true;
  }

  /// 流式算哈希 —— 440MB 不能整块读进内存。
  static Future<String> _sha256OfFile(File f) async {
    final digest = await sha256.bind(f.openRead()).first;
    return digest.toString();
  }

  /// 删除已下载的模型 (设置页里的「删除模型」)
  Future<void> deleteAll() async {
    for (final f in [file, _partFile, _readyMarker]) {
      if (await f.exists()) await f.delete();
    }
  }

  /// 从本地文件导入 —— 网络环境差的用户可以自己下好再导进来, 零流量成本。
  /// 会做同样的 sha256 校验和归一化。
  Stream<ModelProgress> importFrom(File src) {
    final out = StreamController<ModelProgress>();
    Future(() async {
      try {
        if (await src.length() != spec.sizeBytes) {
          out.add(ModelProgress(ModelStage.failed,
              message: '文件大小不对，应为 ${spec.sizeLabel}'));
          return;
        }
        await dir.create(recursive: true);
        out.add(const ModelProgress(ModelStage.downloading, message: '正在复制文件'));
        await src.copy(file.path);
        if (!await _verifyAndFinalize(out)) {
          out.add(const ModelProgress(ModelStage.failed, message: '文件校验失败'));
        }
      } catch (e) {
        out.add(ModelProgress(ModelStage.failed, message: _friendly(e)));
      }
    }).whenComplete(out.close);
    return out.stream;
  }
}

