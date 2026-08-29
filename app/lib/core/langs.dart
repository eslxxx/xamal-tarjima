/// 语言表与 prompt 构造。
///
/// prompt 文案严格照官方 Hy-MT 规则:
///   - 涉及中文的方向 (ZH<=>XX) → 中文指令 + 中文语言全名
///   - 不涉及中文的方向 (XX<=>XX) → 英文指令 + 英文语言全名
/// 这条规则放在 Dart 层是为了方便改文案和写单测; C++ 侧只负责套 chat 模板。
library;

enum Lang { zh, ug, kk }

class LangSpec {
  const LangSpec({
    required this.code,
    required this.zhName,
    required this.enName,
    required this.nativeName,
    required this.rtl,
  });

  /// ISO 639-1
  final String code;

  /// 中文指令模板里用的中文全名
  final String zhName;

  /// 英文指令模板里用的英文全名
  final String enName;

  /// 界面上给母语者看的自称
  final String nativeName;

  /// 是否从右往左排版
  final bool rtl;

  /// 渲染这种语言应该用的字体族。
  ///
  /// 维文/哈文必须走内置的 Noto Naskh Arabic: 系统字体在不少机型上对阿拉伯字母的
  /// 字形连写处理是错的 (字母不连、或用了波斯语/阿拉伯语的错误变体形), 母语者一眼
  /// 就能看出不对。中文/拉丁返回 null, 交给系统字体。
  String? get fontFamily => rtl ? 'NotoNaskhArabic' : null;
}

const Map<Lang, LangSpec> kLangs = {
  Lang.zh: LangSpec(
    code: 'zh',
    zhName: '中文',
    enName: 'Chinese',
    // 语言胶囊上第二行显示自称。中文写「简体中文」而不是重复「中文」,
    // 否则会出现「中文 / 中文」这种看着像 bug 的重复。
    nativeName: '简体中文',
    rtl: false,
  ),
  Lang.ug: LangSpec(
    code: 'ug',
    zhName: '维吾尔语',
    enName: 'Uyghur',
    nativeName: 'ئۇيغۇرچە',
    rtl: true,
  ),
  Lang.kk: LangSpec(
    code: 'kk',
    zhName: '哈萨克语',
    enName: 'Kazakh',
    // 新疆哈萨克文 (阿拉伯字母)。已实测确认模型原生输出的就是这一套,
    // 不需要任何转写层。
    nativeName: 'قازاقشا',
    rtl: true,
  ),
};

LangSpec specOf(Lang l) => kLangs[l]!;

/// 拼出交给 mt_translate 的**用户消息正文**(不含 chat 模板的特殊 token)。
String buildUserContent({
  required Lang from,
  required Lang to,
  required String text,
}) {
  final src = text.trim();
  final involvesChinese = from == Lang.zh || to == Lang.zh;
  if (involvesChinese) {
    return '将以下文本翻译为${specOf(to).zhName}，注意只需要输出翻译后的结果，不要额外解释：\n\n$src';
  }
  return 'Translate the following segment into ${specOf(to).enName}, '
      'without additional explanation.\n\n$src';
}

// ---------------------------------------------------------------- 文字识别
//
// 维文和新疆哈文都用阿拉伯字母, 光看 Unicode 区间分不开。下面的判别字符是从
// 模型真机输出的真实样本里挑出来的:
//
//   维文  بۈگۈن ھاۋا بەك ياخشى، بىز باغچىغا بېرىپ سەيلە قىلايلى
//   哈文  بۇگىن اۋا رايى وتە جاقسى، بىز باقشاعا بارىپ سەيىلدەيمىز
//
// 差异明显的几个:
//   维文专有: ئ (U+0626, 元音载体, 高频) / ې (U+06D0) / ۈ (U+06C8) / غ (U+063A)
//   哈文专有: ع (U+0639, 对应 ғ) / ٴ (U+0674, 高位 hamza)
//
// 注意: 模型只认阿拉伯字母的哈萨克语。西里尔哈萨克语喂进去会胡说或原样返回
// (实测 "Бүгін ауа өте жақсы" → 原样返回), 所以西里尔一律判为不支持,
// 而不是判成 kk 再送进死路。

final _reCjk = RegExp(r'[一-鿿㐀-䶿]');
final _reCyrillic = RegExp(r'[Ѐ-ԯ]');
final _reArabic = RegExp(r'[؀-ۿݐ-ݿࢠ-ࣿﭐ-﷿ﹰ-﻿]');

int _count(RegExp re, String s) => re.allMatches(s).length;

/// 猜源语言。信息不足或是不支持的文字时返回 null, 由界面沿用用户上次的选择。
///
/// 只作为界面提示用。短文本上自动识别不可靠, 真正的源语言以用户选择为准 ——
/// 不要拿它做静默决策。
Lang? guessLang(String text) {
  if (text.trim().isEmpty) return null;
  final cjk = _count(_reCjk, text);
  final arb = _count(_reArabic, text);
  if (cjk == 0 && arb == 0) return null; // 纯拉丁 / 纯西里尔 → 不支持
  if (cjk >= arb) return Lang.zh;

  // 阿拉伯字母: 区分维文 / 新疆哈文
  final ugHits = _count(RegExp(r'[ئېۈغ]'), text);
  final kkHits = _count(RegExp(r'[عٴ]'), text);
  if (ugHits != kkHits) return ugHits > kkHits ? Lang.ug : Lang.kk;
  // 打平时倾向维文 —— 使用者基数更大, 且 ئ 在维文里几乎必现, 打平通常意味着两者都没出现
  return Lang.ug;
}

/// 文本是否含本 App 不支持的西里尔字母 (哈萨克斯坦那套哈文)。
/// 界面据此提示「请使用阿拉伯字母的哈萨克文」, 而不是默默给出错误译文。
bool hasUnsupportedCyrillic(String text) {
  final cyr = _count(_reCyrillic, text);
  return cyr > 0 && cyr >= _count(_reArabic, text) && cyr >= _count(_reCjk, text);
}
