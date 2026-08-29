// GGUF 归一化的正确性测试。
//
// 这是整条链路里最不能出错的一环: Dart 版归一化写错一个字节, App 就永远加载不了模型。
// 所以直接拿真实的 440MB 官方文件跑一遍, 和 Python 版 (tools/normalize_gguf_stq1.py)
// 产出的已知哈希对比 —— 两个独立实现得出同一个结果才算对。
//
// 本地没有模型文件时自动跳过, 不阻塞 CI。
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tilmach/core/gguf_normalize.dart';

/// 官方原始文件
const _origSha = '93e025c93cc082e73a3f142b757623a8b9cf541c020a8013ca4ee669556860ab';

/// Python 版归一化后的结果
const _normSha = '065f6be66620a07927520a951112da6a7ff0dbae962f0c446e80a5cdf1a9ca7c';

Future<String> _sha256(File f) async =>
    (await sha256.bind(f.openRead()).first).toString();

void main() {
  final orig = File('../models/Hy-MT1.5-1.8B-1.25bit.gguf.orig');

  test('归一化后的字节与 Python 版逐字节一致', () async {
    if (!orig.existsSync()) {
      markTestSkipped('本地没有 ${orig.path}, 跳过');
      return;
    }
    expect(await _sha256(orig), _origSha, reason: '源文件不是预期的官方原始文件');

    final tmp = File('${Directory.systemTemp.path}/tilmach_norm_test.gguf');
    addTearDown(() {
      if (tmp.existsSync()) tmp.deleteSync();
    });
    await orig.copy(tmp.path);

    final r = await normalizeStq1Gguf(tmp);
    expect(r.architecture, 'hunyuan-dense');
    expect(r.changedTensors, 224, reason: '应该改写 224 个权重张量的类型字段');
    expect(r.changedFtype, isTrue, reason: 'general.file_type 应从 41 改成 42');
    expect(await tmp.length(), await orig.length(), reason: '文件大小不能变');
    expect(await _sha256(tmp), _normSha);

    // 幂等: 再跑一次不应该有任何改动
    final again = await normalizeStq1Gguf(tmp);
    expect(again.changedTensors, 0);
    expect(again.changedFtype, isFalse);
    expect(await _sha256(tmp), _normSha);
  }, timeout: const Timeout(Duration(minutes: 10)));
}
