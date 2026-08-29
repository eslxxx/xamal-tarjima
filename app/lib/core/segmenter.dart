/// 长文本分句 与 译文清理。
///
/// 为什么必须分句 (两个独立原因, 都是实测出来的):
///   1. 速度: 骁龙 8s Gen 3 上一段 70 字的中文要 20s 才出完整译文。切成句子逐句
///      出结果, 用户 3~5s 就能看到第一句, 体感完全不同。
///   2. 正确性: 这份 GGUF 的 hunyuan-dense.rope.freq_base 被烘成了静态的 11158840
///      (原始 HF config 是 dynamic NTK / theta=10000), 长 prompt 上位置编码会偏。
///      短句范围内没问题。
library;

/// 句末标点: 中文、拉丁、阿拉伯文书写体系三套都要认。
const _sentenceEnd = {
  '。', '！', '？', '；', '…',
  '.', '!', '?', ';',
  '؟', '۔', '؛', // 阿拉伯问号 / 句点 / 分号
};

/// 次级切分点 —— 只有单句仍然过长时才用, 因为在逗号处切会丢子句上下文,
/// 译文质量会下降。
const _clauseBreak = {'，', ',', '、', '،', '：', ':'};

/// 一段的软上限 (字符数)。超过就继续往下切。
/// 按实测的 token 消耗估的: 中文 ~1 token/字, 维/哈文阿拉伯字母 ~1.2 token/字,
/// n_ctx = 1024 要同时容纳 prompt 和译文, 留足余量。
const int kMaxSegmentChars = 120;

/// 把长文本切成适合逐段翻译的片段。
///
/// 保留原文中的换行结构: 换行本身是硬边界, 不跨行合并。
List<String> splitForTranslation(String text, {int maxChars = kMaxSegmentChars}) {
  final out = <String>[];
  for (final line in text.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    out.addAll(_splitLine(trimmed, maxChars));
  }
  return out;
}

List<String> _splitLine(String line, int maxChars) {
  final sentences = _breakAt(line, _sentenceEnd);
  final out = <String>[];
  for (final s in sentences) {
    if (s.length <= maxChars) {
      out.add(s);
      continue;
    }
    // 单句超长: 退一步在逗号处切
    final clauses = _breakAt(s, _clauseBreak);
    var buf = StringBuffer();
    for (final c in clauses) {
      if (buf.isNotEmpty && buf.length + c.length > maxChars) {
        out.add(buf.toString().trim());
        buf = StringBuffer();
      }
      buf.write(c);
      // 逗号切完还是超长 (比如没有标点的长串), 只能硬切
      while (buf.length > maxChars) {
        final s2 = buf.toString();
        out.add(s2.substring(0, maxChars).trim());
        buf = StringBuffer(s2.substring(maxChars));
      }
    }
    if (buf.isNotEmpty) out.add(buf.toString().trim());
  }
  return out.where((e) => e.isNotEmpty).toList();
}

/// 在指定标点后切开, 标点跟在前一段末尾。
List<String> _breakAt(String s, Set<String> marks) {
  final out = <String>[];
  var start = 0;
  for (var i = 0; i < s.length; i++) {
    if (marks.contains(s[i])) {
      // 连续标点 (如 "?!" 或 "。」") 一并吃掉
      var j = i;
      while (j + 1 < s.length && marks.contains(s[j + 1])) {
        j++;
      }
      final piece = s.substring(start, j + 1).trim();
      if (piece.isNotEmpty) out.add(piece);
      start = j + 1;
      i = j;
    }
  }
  final tail = s.substring(start).trim();
  if (tail.isNotEmpty) out.add(tail);
  return out;
}

// ---------------------------------------------------------------- 译文清理
//
// 模型输出里标点前会带多余空格, 实测样例:
//   "ھاۋا ناھايىتى ياخشى ، بىز باغچىغا ..."   ← 逗号前有空格
//   "... قىلايلى ."                            ← 句点前有空格
// 这是稳定出现的输出风格, 属于展示层该收拾的事, 不在推理核里动。
//
// 注意只删标点**前**的空格, 不动标点后的 —— 阿拉伯文书写里标点后是要留空格的。

final _spaceBeforePunct = RegExp(r'\s+([،؛؟۔.,;:!?%）)\]】」』])');
final _spaceAfterOpen = RegExp(r'([（(\[【「『])\s+');
final _multiSpace = RegExp(r'[ \t]{2,}');

/// 清理模型译文里的排版噪声。纯字符串处理, 可单测。
String tidyTranslation(String s) {
  var r = s.trim();
  r = r.replaceAllMapped(_spaceBeforePunct, (m) => m.group(1)!);
  r = r.replaceAllMapped(_spaceAfterOpen, (m) => m.group(1)!);
  r = r.replaceAll(_multiSpace, ' ');
  return r.trim();
}
