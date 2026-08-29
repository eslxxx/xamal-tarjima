/// GGUF 类型号归一化 —— `tools/normalize_gguf_stq1.py` 的 Dart 版, 跑在 App 里。
///
/// 官方在 HuggingFace 发布的 1.25bit GGUF 是用**早期版本**的 llama.cpp PR #22836
/// 量化的, 那时 STQ1_0 的 ggml 类型号是 42、file_type 是 41。此后上游主线占用了
/// 41 (Q1_0) 和 42 (Q2_0), PR rebase 后 STQ1_0 顺移到 43、ftype 到 42。
///
/// 用当前引擎加载官方文件, 那 224 个权重张量会被当成 Q2_0 解析, block 尺寸对不上
/// → 加载失败。已核对官方文件的实际布局是 42 字节/256 元素, 与当前 PR 的
/// `block_stq1_0` 逐字节一致 —— 差别**只有枚举编号**。
///
/// 所以选择改文件而不是改引擎: 只重写张量信息表里的 u32 类型字段和一个 KV,
/// 数据段一个字节都不碰。引擎保持跟上游 PR 一致, 将来 PR 合并进主线可以直接切。
/// 这样用户下载的仍然是官方原始文件, 校验用官方文件的 sha256。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

const int _oldType = 42, _newType = 43; // GGML_TYPE_STQ1_0
const int _oldFtype = 41, _newFtype = 42; // LLAMA_FTYPE_MOSTLY_STQ1_0

/// GGUF 的值类型编号
const int _tUint8 = 0,
    _tInt8 = 1,
    _tUint16 = 2,
    _tInt16 = 3,
    _tUint32 = 4,
    _tInt32 = 5,
    _tFloat32 = 6,
    _tBool = 7,
    _tString = 8,
    _tArray = 9,
    _tUint64 = 10,
    _tInt64 = 11,
    _tFloat64 = 12;

int _scalarSize(int t) => switch (t) {
      _tUint8 || _tInt8 || _tBool => 1,
      _tUint16 || _tInt16 => 2,
      _tUint32 || _tInt32 || _tFloat32 => 4,
      _tUint64 || _tInt64 || _tFloat64 => 8,
      _ => throw const FormatException('未知的 GGUF 值类型'),
    };

class GgufNormalizeResult {
  const GgufNormalizeResult({
    required this.changedTensors,
    required this.changedFtype,
    required this.architecture,
  });

  final int changedTensors;
  final bool changedFtype;
  final String? architecture;

  bool get didWork => changedTensors > 0 || changedFtype;
}

/// 顺序读 GGUF 头部的小工具。只走一遍元数据段, 不碰几百 MB 的数据段。
class _Cursor {
  _Cursor(this._f);

  final RandomAccessFile _f;
  int pos = 0;

  Uint8List read(int n) {
    final b = _f.readSync(n);
    if (b.length != n) throw const FormatException('GGUF 在元数据段就结束了');
    pos += n;
    return b;
  }

  int u32() => ByteData.sublistView(read(4)).getUint32(0, Endian.little);
  int u64() => ByteData.sublistView(read(8)).getUint64(0, Endian.little);

  String str() => utf8.decode(read(u64()), allowMalformed: true);

  /// 跳过一个值, 只在需要时返回它 (字符串才需要)
  String? skipValue(int type) {
    if (type == _tString) return str();
    if (type == _tArray) {
      final et = u32();
      final n = u64();
      if (et == _tString) {
        for (var i = 0; i < n; i++) {
          str();
        }
      } else if (et == _tArray) {
        for (var i = 0; i < n; i++) {
          skipValue(_tArray);
        }
      } else {
        read(_scalarSize(et) * n);
      }
      return null;
    }
    read(_scalarSize(type));
    return null;
  }
}

/// 就地把官方 GGUF 的 STQ1_0 类型号从 42 改成 43 (以及 file_type 41→42)。
///
/// 幂等: 已经归一化过、或官方将来重新上传了新编号的版本, 都会返回
/// `changedTensors == 0` 而不做任何写入。
///
/// 只对 `general.architecture == "hunyuan-dense"` 的文件动手, 免得误伤别的 GGUF。
Future<GgufNormalizeResult> normalizeStq1Gguf(File file) async {
  final f = await file.open(mode: FileMode.append); // 读 + 写, 不截断
  try {
    final c = _Cursor(f);
    await f.setPosition(0);
    c.pos = 0;

    if (String.fromCharCodes(c.read(4)) != 'GGUF') {
      throw const FormatException('不是 GGUF 文件');
    }
    c.u32(); // version
    final nTensors = c.u64();
    final nKv = c.u64();

    String? arch;
    int? ftypePos;
    for (var i = 0; i < nKv; i++) {
      final key = c.str();
      final vtype = c.u32();
      if (key == 'general.file_type') ftypePos = c.pos;
      final sv = c.skipValue(vtype);
      if (key == 'general.architecture') arch = sv;
    }

    if (arch != 'hunyuan-dense') {
      return GgufNormalizeResult(
          changedTensors: 0, changedFtype: false, architecture: arch);
    }

    // 张量信息表: name(str) + n_dims(u32) + dims(u64 每维) + type(u32) + offset(u64)
    final typePositions = <int>[];
    for (var i = 0; i < nTensors; i++) {
      c.str();
      final nd = c.u32();
      for (var d = 0; d < nd; d++) {
        c.u64();
      }
      final tPos = c.pos;
      final tType = c.u32();
      c.u64();
      if (tType == _oldType) typePositions.add(tPos);
    }

    if (typePositions.isEmpty) {
      return GgufNormalizeResult(
          changedTensors: 0, changedFtype: false, architecture: arch);
    }

    final buf = Uint8List(4);
    var changedFtype = false;

    if (ftypePos != null) {
      await f.setPosition(ftypePos);
      final cur = ByteData.sublistView(f.readSync(4)).getUint32(0, Endian.little);
      if (cur == _oldFtype) {
        ByteData.sublistView(buf).setUint32(0, _newFtype, Endian.little);
        await f.setPosition(ftypePos);
        f.writeFromSync(buf);
        changedFtype = true;
      }
    }

    ByteData.sublistView(buf).setUint32(0, _newType, Endian.little);
    for (final p in typePositions) {
      await f.setPosition(p);
      f.writeFromSync(buf);
    }
    await f.flush();

    return GgufNormalizeResult(
      changedTensors: typePositions.length,
      changedFtype: changedFtype,
      architecture: arch,
    );
  } finally {
    await f.close();
  }
}
