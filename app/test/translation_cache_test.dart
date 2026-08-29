// 译文缓存的行为测试。
//
// 缓存是"改一个字不用重翻整段"的基础, 逻辑错了用户会看到过期或错配的译文,
// 而这种 bug 在 UI 上很难发现 —— 所以这里把边界都钉住。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tilmach/core/langs.dart';
import 'package:tilmach/core/translation_cache.dart';

void main() {
  final c = TranslationCache.instance;

  setUp(c.clear);

  test('按 语言对 + 原文 命中', () {
    c.put(Lang.zh, Lang.ug, '你好', 'ياخشىمۇسىز');
    expect(c.get(Lang.zh, Lang.ug, '你好'), 'ياخشىمۇسىز');
  });

  test('语言方向不同不能串味', () {
    c.put(Lang.zh, Lang.ug, '你好', 'A');
    expect(c.get(Lang.zh, Lang.kk, '你好'), isNull, reason: '目标语言不同');
    expect(c.get(Lang.ug, Lang.zh, '你好'), isNull, reason: '方向相反');
  });

  test('前后空白不影响命中 —— 用户复制粘贴常带空格', () {
    c.put(Lang.zh, Lang.ug, '你好', 'A');
    expect(c.get(Lang.zh, Lang.ug, '  你好\n'), 'A');
  });

  test('空原文或空译文不入缓存', () {
    c.put(Lang.zh, Lang.ug, '  ', 'A');
    c.put(Lang.zh, Lang.ug, '你好', '   ');
    expect(c.size, 0);
  });

  test('重复 put 同一条不会让缓存膨胀', () {
    for (var i = 0; i < 5; i++) {
      c.put(Lang.zh, Lang.ug, '你好', '第$i版');
    }
    expect(c.size, 1);
    expect(c.get(Lang.zh, Lang.ug, '你好'), '第4版', reason: '应保留最后一次');
  });

  test('落盘后能读回来 —— 重启 App 仍然命中', () async {
    final f = File('${Directory.systemTemp.path}/tilmach_cache_test.json');
    addTearDown(() {
      if (f.existsSync()) f.deleteSync();
    });
    if (f.existsSync()) f.deleteSync();

    await c.load(f);
    c.clear();
    c.put(Lang.zh, Lang.ug, '今天天气很好', 'بۈگۈن ھاۋا ياخشى');
    await c.flush();
    expect(f.existsSync(), isTrue);

    c.clear();
    expect(c.get(Lang.zh, Lang.ug, '今天天气很好'), isNull);
    await c.load(f);
    expect(c.get(Lang.zh, Lang.ug, '今天天气很好'), 'بۈگۈن ھاۋا ياخشى');
  });

  test('缓存文件坏掉时不能让 App 起不来', () async {
    final f = File('${Directory.systemTemp.path}/tilmach_cache_broken.json');
    addTearDown(() {
      if (f.existsSync()) f.deleteSync();
    });
    await f.writeAsString('{ 这不是合法 JSON ');
    await c.load(f); // 不应抛异常
    expect(c.size, 0);
  });
}
