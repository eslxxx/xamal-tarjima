/// libmtcore.so 的 dart:ffi 绑定。
///
/// 对应的 C 头文件是 engine/include/mt_core.h —— 两边改动必须同步。
library;

import 'dart:ffi';
import 'dart:io';

/// 与 C 侧 `mt_params` 结构体逐字段对应。全部是 4 字节字段, 无对齐坑。
final class MtParams extends Struct {
  @Float()
  external double temperature;

  @Float()
  external double topP;

  @Int32()
  external int topK;

  @Float()
  external double repeatPenalty;

  @Int32()
  external int repeatLastN;

  @Uint32()
  external int seed;

  /// <=0 表示交给 C 侧算 (输入 token 数 * 4 + 128)
  @Int32()
  external int maxTokens;

  /// n-gram 复读检测长度; <=0 关闭
  @Int32()
  external int noRepeatNgram;
}

/// mt_translate 的返回码, 与 mt_core.h 里的 MT_* 枚举一致。
class MtResult {
  static const ok = 0;
  static const errArg = -1;
  static const errTokenize = -2;
  static const errCtxFull = -3;
  static const errDecode = -4;
  static const cancelled = -5;
  static const stoppedLimit = -6;
  static const stoppedRepeat = -7;

  /// 是否是「有译文产出」的结束方式。撞上限和复读截断都算有产出, 只是可能不完整。
  static bool hasOutput(int rc) =>
      rc == ok || rc == stoppedLimit || rc == stoppedRepeat || rc == cancelled;

  static String describe(int rc) {
    switch (rc) {
      case ok:
        return '完成';
      case cancelled:
        return '已取消';
      case stoppedLimit:
        return '译文过长被截断';
      case stoppedRepeat:
        return '检测到重复输出，已截断';
      case errCtxFull:
        return '这段文字太长，请分句后再试';
      case errTokenize:
        return '分词失败';
      case errDecode:
        return '推理失败';
      case errArg:
        return '参数错误';
      default:
        return '未知错误 ($rc)';
    }
  }
}

typedef MtTokenCb = Int Function(Pointer<Char>, Pointer<Void>);

typedef MtInitNative = Pointer<Void> Function(Pointer<Char>, Int32, Int32);
typedef MtInitDart = Pointer<Void> Function(Pointer<Char>, int, int);

typedef MtTranslateNative = Int32 Function(Pointer<Void>, Pointer<Char>,
    Pointer<MtParams>, Pointer<NativeFunction<MtTokenCb>>, Pointer<Void>, Pointer<Int32>);
typedef MtTranslateDart = int Function(Pointer<Void>, Pointer<Char>,
    Pointer<MtParams>, Pointer<NativeFunction<MtTokenCb>>, Pointer<Void>, Pointer<Int32>);

/// 打开原生库并绑定符号。
///
/// 安卓: libmtcore.so 通过 jniLibs 打进 APK, 用文件名 open 即可。
/// iOS  : 静态链进主二进制, 走 DynamicLibrary.process()。
class MtLib {
  MtLib._(DynamicLibrary lib)
      : mtInit = lib
            .lookup<NativeFunction<MtInitNative>>('mt_init')
            .asFunction<MtInitDart>(),
        mtTranslate = lib
            .lookup<NativeFunction<MtTranslateNative>>('mt_translate')
            .asFunction<MtTranslateDart>(),
        mtFree = lib
            .lookup<NativeFunction<Void Function(Pointer<Void>)>>('mt_free')
            .asFunction<void Function(Pointer<Void>)>(),
        mtLastError = lib
            .lookup<NativeFunction<Pointer<Char> Function(Pointer<Void>)>>('mt_last_error')
            .asFunction<Pointer<Char> Function(Pointer<Void>)>(),
        mtEngineInfo = lib
            .lookup<NativeFunction<Pointer<Char> Function()>>('mt_engine_info')
            .asFunction<Pointer<Char> Function()>(),
        mtNCtx = lib
            .lookup<NativeFunction<Int32 Function(Pointer<Void>)>>('mt_n_ctx')
            .asFunction<int Function(Pointer<Void>)>(),
        mtNThreads = lib
            .lookup<NativeFunction<Int32 Function(Pointer<Void>)>>('mt_n_threads')
            .asFunction<int Function(Pointer<Void>)>(),
        mtTemplateOk = lib
            .lookup<NativeFunction<Int32 Function(Pointer<Void>)>>(
                'mt_uses_embedded_template')
            .asFunction<int Function(Pointer<Void>)>();

  static MtLib? _instance;

  static MtLib get instance => _instance ??= MtLib._(_open());

  static DynamicLibrary _open() {
    if (Platform.isAndroid) return DynamicLibrary.open('libmtcore.so');
    if (Platform.isIOS || Platform.isMacOS) return DynamicLibrary.process();
    if (Platform.isWindows) return DynamicLibrary.open('mtcore.dll');
    return DynamicLibrary.open('libmtcore.so');
  }

  final MtInitDart mtInit;
  final MtTranslateDart mtTranslate;
  final void Function(Pointer<Void>) mtFree;
  final Pointer<Char> Function(Pointer<Void>) mtLastError;
  final Pointer<Char> Function() mtEngineInfo;
  final int Function(Pointer<Void>) mtNCtx;
  final int Function(Pointer<Void>) mtNThreads;
  final int Function(Pointer<Void>) mtTemplateOk;
}

/// 按 C 侧 mt_params_default() 的同一组默认值填充。
///
/// 故意不绑定 mt_params_default() —— 按值返回结构体在 FFI 里的内存归属比较绕,
/// 而这几个默认值本来就该在 Dart 侧可见可调。改动时记得和 mt_core.cpp 对齐。
///
/// temperature = 0 是刻意的: 官方推荐 0.7 / top_p 0.6 / top_k 20, 但翻译任务
/// 贪心解码更稳、可复现、也更快, 而 1.25bit 模型在随机采样下更容易跑偏。
void fillDefaultParams(Pointer<MtParams> p, {bool official = false}) {
  final r = p.ref;
  r.temperature = official ? 0.7 : 0.0;
  r.topP = 0.6;
  r.topK = 20;
  r.repeatPenalty = 1.05;
  r.repeatLastN = 64;
  r.seed = 0xC0FFEE;
  r.maxTokens = 0;
  r.noRepeatNgram = 6;
}
