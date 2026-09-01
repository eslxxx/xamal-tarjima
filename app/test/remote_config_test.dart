// 后台配置的解析与版本比较。
//
// 这两块都是"错了不会崩、只会静默出错"的类型: 版本比较写错就会漏提示或者反复提示
// 已经装上的版本; 校验写松了, 后台 (或者任何能改那个响应的人) 就能拿 id 当文件名
// 往磁盘上写别的路径。所以单独测。
import 'package:flutter_test/flutter_test.dart';
import 'package:tilmach/core/remote_config.dart';

void main() {
  group('版本比较', () {
    ReleaseInfo v(String s) => ReleaseInfo(version: s);

    test('逐段比数字, 不是按字符串比', () {
      // 字符串比较会认为 '1.0.9' > '1.0.10'
      expect(v('1.0.10').isNewerThan('1.0.9'), isTrue);
      expect(v('1.0.9').isNewerThan('1.0.10'), isFalse);
    });

    test('同版本不算新版本', () {
      expect(v('1.0.0').isNewerThan('1.0.0'), isFalse);
    });

    test('段数不一样时缺的段当 0', () {
      expect(v('1.1').isNewerThan('1.0.0'), isTrue);
      expect(v('1.0').isNewerThan('1.0.0'), isFalse);
      expect(v('1.0.0.1').isNewerThan('1.0.0'), isTrue);
    });
  });

  group('ReleaseInfo.fromJson', () {
    test('版本号格式不对就整条丢掉', () {
      expect(ReleaseInfo.fromJson({'version': '1.0.0-beta'}), isNull);
      expect(ReleaseInfo.fromJson({'version': 'latest'}), isNull);
      expect(ReleaseInfo.fromJson({'version': 2}), isNull);
      expect(ReleaseInfo.fromJson(null), isNull);
    });

    test('只接受 http(s) 的下载地址', () {
      expect(ReleaseInfo.fromJson({'version': '1.1', 'url': 'https://a.b/x'})!.url,
          'https://a.b/x');
      // 别的 scheme 会被 url_launcher 交给系统, 那是个不该开的口子
      expect(
          ReleaseInfo.fromJson({'version': '1.1', 'url': 'intent://x'})!.url, isNull);
    });

    test('空白的更新说明当没有', () {
      expect(ReleaseInfo.fromJson({'version': '1.1', 'notes': '   '})!.notes, isNull);
      expect(ReleaseInfo.fromJson({'version': '1.1', 'notes': ' 修好了 '})!.notes, '修好了');
    });
  });

  group('BannerItem.fromJson', () {
    test('正常一条', () {
      final b = BannerItem.fromJson(
          {'id': 'abcdefgh12345678', 'img': 'https://x/img/abcdefgh12345678'});
      expect(b, isNotNull);
      expect(b!.file, isNull);
    });

    test('id 会当文件名用, 带路径分隔符的必须挡住', () {
      for (final bad in ['../../etc/passwd', 'a/b/c/dddddddd', 'short', '']) {
        expect(BannerItem.fromJson({'id': bad, 'img': 'https://x/y'}), isNull,
            reason: 'id="$bad" 不该通过');
      }
    });

    test('缺字段或类型不对就丢掉', () {
      expect(BannerItem.fromJson({'id': 'abcdefgh12345678'}), isNull);
      expect(BannerItem.fromJson({'img': 'https://x/y'}), isNull);
      expect(BannerItem.fromJson('abcdefgh12345678'), isNull);
    });

    test('非 http 的跳转链接降级成不可点, 而不是丢掉整条横幅', () {
      final b = BannerItem.fromJson({
        'id': 'abcdefgh12345678',
        'img': 'https://x/y',
        'link': 'javascript:alert(1)',
      });
      expect(b, isNotNull);
      expect(b!.link, isNull);
    });
  });
}
