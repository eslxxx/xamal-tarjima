// 纯逻辑单测: 分句、译文清理、prompt 构造、语言识别。
// 这几块不依赖原生库, 可以在电脑上直接 `flutter test` 跑。
import 'package:flutter_test/flutter_test.dart';
import 'package:tilmach/core/langs.dart';
import 'package:tilmach/core/segmenter.dart';

void main() {
  group('prompt 构造', () {
    test('涉及中文的方向用中文指令 + 中文语言全名', () {
      final p = buildUserContent(from: Lang.zh, to: Lang.ug, text: '你好');
      expect(p, startsWith('将以下文本翻译为维吾尔语，'));
      expect(p, endsWith('你好'));
    });

    test('维->汉 也算涉及中文', () {
      final p = buildUserContent(from: Lang.ug, to: Lang.zh, text: 'سالام');
      expect(p, startsWith('将以下文本翻译为中文，'));
    });

    test('维<->哈 不涉及中文, 用英文指令 + 英文语言全名', () {
      final p = buildUserContent(from: Lang.ug, to: Lang.kk, text: 'سالام');
      expect(p, startsWith('Translate the following segment into Kazakh,'));
    });
  });

  group('语言识别', () {
    test('汉字判为中文', () {
      expect(guessLang('今天天气很好'), Lang.zh);
    });

    test('维文样本判为维语', () {
      expect(guessLang('بۈگۈن ھاۋا بەك ياخشى، بىز باغقا سەيلە قىلىپ چىقايلى'), Lang.ug);
    });

    test('新疆哈文样本判为哈语', () {
      expect(guessLang('بۇگىن اۋا رايى وتە جاقسى، بىز باقشاعا بارىپ سەيىلدەيمىز'), Lang.kk);
    });

    test('西里尔被标记为不支持', () {
      expect(hasUnsupportedCyrillic('Бүгін ауа өте жақсы'), isTrue);
      expect(hasUnsupportedCyrillic('今天天气很好'), isFalse);
    });

    test('纯拉丁返回 null, 由界面沿用上次选择', () {
      expect(guessLang('hello world'), isNull);
    });
  });

  group('分句', () {
    test('按句末标点切分, 标点留在前一段', () {
      final s = splitForTranslation('今天天气很好。我们去公园散步吧！');
      expect(s, ['今天天气很好。', '我们去公园散步吧！']);
    });

    test('换行是硬边界', () {
      expect(splitForTranslation('第一行\n\n第二行'), ['第一行', '第二行']);
    });

    test('阿拉伯文标点也认', () {
      final s = splitForTranslation('ھاۋا ياخشى۔ قانداق ئەھۋالىڭىز؟');
      expect(s.length, 2);
    });

    test('超长单句退到逗号处切', () {
      final long = '${'甲乙丙丁' * 20}，${'戊己庚辛' * 20}。';
      final s = splitForTranslation(long, maxChars: 100);
      expect(s.length, greaterThan(1));
      expect(s.every((e) => e.length <= 100), isTrue);
    });

    test('没有任何标点的长串也要被硬切开', () {
      final s = splitForTranslation('阿' * 300, maxChars: 120);
      expect(s.every((e) => e.length <= 120), isTrue);
      expect(s.join().length, 300);
    });
  });

  group('译文清理', () {
    test('删掉标点前的多余空格, 保留标点后的', () {
      expect(tidyTranslation('ھاۋا ياخشى ، بىز باغچىغا بېرىپ سەيلە قىلايلى .'),
          'ھاۋا ياخشى، بىز باغچىغا بېرىپ سەيلە قىلايلى.');
    });

    test('合并多余空格', () {
      expect(tidyTranslation('a    b'), 'a b');
    });
  });
}
