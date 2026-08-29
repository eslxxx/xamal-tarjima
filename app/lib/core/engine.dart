/// 推理引擎: 在独立 isolate 里持有 mt_ctx, 向 UI 流式回吐译文。
///
/// 为什么必须放 isolate:
///   一句短句在骁龙 8s Gen 3 上要 ~4.5s, 长句 20s。放主 isolate 会直接卡死 UI。
///
/// 为什么能用普通的 Pointer.fromFunction 做流式回调 (而不是 NativeCallable):
///   mt_translate 是在 worker isolate 的线程上同步调用的, C 侧的回调也在同一个
///   线程上同步触发, 所以回调里可以直接跑 Dart 代码、直接 SendPort.send。
library;

import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import 'ffi/mt_bindings.dart';

// ---------------------------------------------------------------- 消息类型
class _Load {
  const _Load(this.reply, this.modelPath, this.threads, this.nCtx);
  final SendPort reply;
  final String modelPath;
  final int threads;
  final int nCtx;
}

class _Translate {
  const _Translate(this.reply, this.userContent, this.cancelAddr, this.official);
  final SendPort reply;
  final String userContent;
  final int cancelAddr;
  final bool official;
}

class _Dispose {
  const _Dispose(this.reply);
  final SendPort reply;
}

class _Chunk {
  const _Chunk(this.text);
  final String text;
}

class _Done {
  const _Done(this.rc);
  final int rc;
}

class _Failed {
  const _Failed(this.message);
  final String message;
}

/// 模型加载后的运行时信息, 用于「关于」页和排错。
class EngineInfo {
  const EngineInfo({
    required this.engine,
    required this.nCtx,
    required this.threads,
    required this.templateOk,
    required this.loadMillis,
  });

  final String engine;
  final int nCtx;
  final int threads;

  /// false 表示 GGUF 的 chat 模板和硬编码假设不符, 译文可能不对
  final bool templateOk;
  final int loadMillis;

  @override
  String toString() => '$engine; n_ctx=$nCtx; threads=$threads; '
      'template=${templateOk ? "ok" : "MISMATCH"}; load=${loadMillis}ms';
}

// ---------------------------------------------------------------- worker 侧
// 这些是 worker isolate 的局部全局量。isolate 之间内存隔离, 所以这里不会串。
SendPort? _chunkSink;
Pointer<Void> _ctx = nullptr;

/// C 回调。返回非 0 会让 mt_translate 立即停下来。
int _onChunk(Pointer<Char> utf8, Pointer<Void> _) {
  final sink = _chunkSink;
  if (sink == null) return 1;
  sink.send(_Chunk(utf8.cast<Utf8>().toDartString()));
  return 0;
}

void _workerMain(SendPort bootstrap) {
  final rx = ReceivePort();
  bootstrap.send(rx.sendPort);

  rx.listen((msg) {
    final lib = MtLib.instance;

    if (msg is _Load) {
      if (_ctx != nullptr) {
        lib.mtFree(_ctx);
        _ctx = nullptr;
      }
      final sw = Stopwatch()..start();
      final path = msg.modelPath.toNativeUtf8();
      try {
        _ctx = lib.mtInit(path.cast(), msg.threads, msg.nCtx);
      } finally {
        calloc.free(path);
      }
      if (_ctx == nullptr) {
        msg.reply.send(_Failed(lib.mtLastError(nullptr).cast<Utf8>().toDartString()));
        return;
      }
      msg.reply.send(EngineInfo(
        engine: lib.mtEngineInfo().cast<Utf8>().toDartString(),
        nCtx: lib.mtNCtx(_ctx),
        threads: lib.mtNThreads(_ctx),
        templateOk: lib.mtTemplateOk(_ctx) == 1,
        loadMillis: sw.elapsedMilliseconds,
      ));
      return;
    }

    if (msg is _Translate) {
      if (_ctx == nullptr) {
        msg.reply.send(const _Failed('模型尚未加载'));
        return;
      }
      _chunkSink = msg.reply;
      final content = msg.userContent.toNativeUtf8();
      final params = calloc<MtParams>();
      fillDefaultParams(params, official: msg.official);
      try {
        final rc = lib.mtTranslate(
          _ctx,
          content.cast(),
          params,
          Pointer.fromFunction<Int Function(Pointer<Char>, Pointer<Void>)>(_onChunk, 1),
          nullptr,
          Pointer<Int32>.fromAddress(msg.cancelAddr),
        );
        if (!MtResult.hasOutput(rc)) {
          msg.reply.send(_Failed(
              '${MtResult.describe(rc)}: ${lib.mtLastError(_ctx).cast<Utf8>().toDartString()}'));
        } else {
          msg.reply.send(_Done(rc));
        }
      } finally {
        calloc.free(content);
        calloc.free(params);
        _chunkSink = null;
      }
      return;
    }

    if (msg is _Dispose) {
      if (_ctx != nullptr) {
        lib.mtFree(_ctx);
        _ctx = nullptr;
      }
      msg.reply.send(const _Done(MtResult.ok));
      rx.close();
    }
  });
}

// ---------------------------------------------------------------- UI 侧门面
class EngineException implements Exception {
  EngineException(this.message);
  final String message;
  @override
  String toString() => message;
}

class TranslateEngine {
  TranslateEngine._();

  static final TranslateEngine instance = TranslateEngine._();

  Isolate? _iso;
  SendPort? _tx;
  EngineInfo? _info;

  /// 取消标志放在原生内存里, 两个 isolate 共享同一块地址 ——
  /// UI 侧写 1, worker 里的生成循环每步读一次。
  final Pointer<Int32> _cancel = calloc<Int32>();

  bool get isLoaded => _info != null;
  EngineInfo? get info => _info;

  Future<void> _ensureWorker() async {
    if (_tx != null) return;
    final boot = ReceivePort();
    _iso = await Isolate.spawn(_workerMain, boot.sendPort);
    _tx = await boot.first as SendPort;
    boot.close();
  }

  /// 加载模型。重复调用会先释放旧的再加载。
  Future<EngineInfo> load(String modelPath, {int threads = 0, int nCtx = 0}) async {
    await _ensureWorker();
    final rx = ReceivePort();
    _tx!.send(_Load(rx.sendPort, modelPath, threads, nCtx));
    final res = await rx.first;
    rx.close();
    if (res is _Failed) throw EngineException(res.message);
    _info = res as EngineInfo;
    return _info!;
  }

  /// 翻译一段已拼好的用户消息正文, 流式返回增量文本。
  ///
  /// 调用方 listen 这个 Stream; 想中途停就 cancel 订阅, 或者调 [stop]。
  Stream<String> translate(String userContent, {bool official = false}) {
    if (_tx == null || _info == null) {
      return Stream.error(EngineException('模型尚未加载'));
    }
    _cancel.value = 0;
    final rx = ReceivePort();
    final out = StreamController<String>();

    rx.listen((msg) {
      if (msg is _Chunk) {
        out.add(msg.text);
      } else if (msg is _Done) {
        rx.close();
        out.close();
      } else if (msg is _Failed) {
        rx.close();
        out.addError(EngineException(msg.message));
        out.close();
      }
    });

    out.onCancel = () {
      _cancel.value = 1;
    };

    _tx!.send(_Translate(rx.sendPort, userContent, _cancel.address, official));
    return out.stream;
  }

  /// 请求停止当前这次生成。
  void stop() => _cancel.value = 1;

  Future<void> dispose() async {
    if (_tx != null) {
      final rx = ReceivePort();
      _tx!.send(_Dispose(rx.sendPort));
      await rx.first.timeout(const Duration(seconds: 5), onTimeout: () => null);
      rx.close();
    }
    _iso?.kill(priority: Isolate.immediate);
    _iso = null;
    _tx = null;
    _info = null;
  }
}
