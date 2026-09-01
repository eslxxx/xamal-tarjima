/// 关于页。
///
/// 这里的措辞要和 App 的实际行为**逐条对得上**。以前写的是"除首次下载模型和匿名
/// 使用统计外不联网", 现在设置页顶部有后台配的横幅、还能主动查新版本, 那句话就不
/// 准确了。宁可把联网的事一条条列出来 —— 用户看得懂"什么时候联网、传了什么",
/// 比一句含糊的"全程离线"可信。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_info.dart';
import '../core/engine.dart';
import '../core/remote_config.dart';
import '../core/telemetry.dart';
import 'theme.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    final info = TranslateEngine.instance.info;
    return Scaffold(
      backgroundColor: T.bgBottom,
      body: Container(
        decoration: const BoxDecoration(gradient: T.pageGradient),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 52,
                child: Stack(
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: IconButton(
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(Icons.arrow_back_rounded,
                            color: T.textPrimary),
                      ),
                    ),
                    const Center(
                      child: Text('关于',
                          style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: T.textPrimary)),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                  children: [
                    _head(),
                    _section('开发者'),
                    _card([_vendor(context)]),
                    _section('联网说明'),
                    _card([_network()]),
                    _section('开源许可'),
                    _card([_credits(info)]),
                    if (Telemetry.endpoint.isNotEmpty) _statsNote(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// App 图标 + 名字 + 版本 + 一句话
  Widget _head() => Container(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
        decoration: BoxDecoration(
          color: T.cardWhite,
          borderRadius: BorderRadius.circular(T.rCard),
          boxShadow: T.shadowCard,
        ),
        child: Column(
          children: [
            Container(
              width: 62,
              height: 62,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF4B8BF5), T.blueDeep],
                ),
                boxShadow: T.shadowButton,
              ),
              child: const Icon(Icons.translate_rounded,
                  size: 34, color: Colors.white),
            ),
            const SizedBox(height: 14),
            const Text(kAppName,
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: T.textPrimary)),
            const SizedBox(height: 4),
            const Text('版本 $kAppVersion',
                style: TextStyle(fontSize: 12.5, color: T.textSecondary)),
            const SizedBox(height: 14),
            const Text(
              '维吾尔语 · 哈萨克语 · 汉语离线互译。\n'
              '本软件完全免费，无网络也能正常翻译。\n'
              '未开放的功能会在下一个版本尽快开发。',
              textAlign: TextAlign.center,
              style:
                  TextStyle(fontSize: 12.5, height: 1.7, color: T.textSecondary),
            ),
          ],
        ),
      );

  /// 联网说明。活跃度统计不在这里露出 —— 按产品决定, 界面上不提。
  /// (采集内容仍然写在 core/telemetry.dart 顶部, 上架时的数据安全表也要照实申报。)
  Widget _network() => Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _item('下载翻译模型',
                '只有首次启动时下载一次（约 440MB）。装好之后翻译再也不需要网络。'),
            if (kConfigUrl.isNotEmpty)
              _item('设置页横幅与新版本信息',
                  '一个不带任何身份标识的普通请求，取回后存在本机；'
                  '没网时显示上次的内容，不会提示失败。'),
            const SizedBox(height: 4),
            const Text('你输入的原文和得到的译文不会上传，只留在这台设备上。',
                style: TextStyle(
                    fontSize: 12.5,
                    height: 1.7,
                    fontWeight: FontWeight.w600,
                    color: T.textPrimary)),
          ],
        ),
      );

  Widget _item(String title, String body) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 5,
                  height: 5,
                  margin: const EdgeInsets.only(right: 8),
                  decoration:
                      const BoxDecoration(color: T.blue, shape: BoxShape.circle),
                ),
                Text(title,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: T.textPrimary)),
              ],
            ),
            const SizedBox(height: 5),
            Padding(
              padding: const EdgeInsets.only(left: 13),
              child: Text(body,
                  style: const TextStyle(
                      fontSize: 12.5, height: 1.7, color: T.textSecondary)),
            ),
          ],
        ),
      );

  Widget _credits(EngineInfo? info) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '翻译模型：腾讯混元 Hy-MT1.5-1.8B（1.25bit Sherry 量化），遵循其开源许可证。\n'
              '推理引擎：llama.cpp（MIT）。\n'
              '维哈文字体：Noto Naskh Arabic（SIL OFL）。',
              style:
                  TextStyle(fontSize: 12.5, height: 1.8, color: T.textSecondary),
            ),
            if (info != null) ...[
              const SizedBox(height: 12),
              // 引擎版本对排查线上问题很关键, 出问题时让用户截这一行就够了
              SelectableText(info.engine,
                  style: const TextStyle(
                      fontSize: 11, height: 1.5, color: T.textTertiary)),
            ],
          ],
        ),
      );

  /// 开发者与联系方式。QQ 号点一下就复制 —— 让用户在手机上手抄一串数字很不友好。
  Widget _vendor(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(kTeam,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: T.textPrimary)),
            const SizedBox(height: 6),
            InkWell(
              onTap: () => _copyQQ(context),
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: const [
                    Text('联系 QQ  ',
                        style:
                            TextStyle(fontSize: 12.5, color: T.textSecondary)),
                    Text(kContactQQ,
                        style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: T.blue)),
                    SizedBox(width: 8),
                    Icon(Icons.copy_rounded, size: 14, color: T.iconGrey),
                  ],
                ),
              ),
            ),
          ],
        ),
      );

  void _copyQQ(BuildContext context) {
    Clipboard.setData(const ClipboardData(text: kContactQQ));
    final m = ScaffoldMessenger.of(context);
    m.hideCurrentSnackBar();
    m.showSnackBar(const SnackBar(
      content: Text('QQ 号已复制'),
      behavior: SnackBarBehavior.floating,
      shape: StadiumBorder(),
      backgroundColor: Color(0xE6202733),
      duration: Duration(milliseconds: 1600),
    ));
  }

  /// 活跃度统计的说明就这一行, 放在整页最底部。
  ///
  /// 为什么不做成一节、也不给开关: 一个「隐私」标题加一个开关摆在那里, 反而暗示
  /// App 在收集什么值得关掉的东西, 而实际采的只是几个计数。
  /// 为什么也不能一个字不写: 上架商店要在数据安全表里申报, 抓个包也看得见 ——
  /// 自己写明比被别人发现好。字号和颜色跟着页面正文走, 不做成看不清的小字。
  Widget _statsNote() => const Padding(
        padding: EdgeInsets.fromLTRB(6, 22, 6, 4),
        child: Text(
          '本软件会匿名统计每天的启动与翻译次数，用于判断是否继续维护；'
          '不含任何文本内容，也不含 IP、位置或手机型号。',
          style: TextStyle(fontSize: 12, height: 1.7, color: T.textSecondary),
        ),
      );

  Widget _section(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 20, 8, 8),
        child: Text(text,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: T.textSecondary)),
      );

  Widget _card(List<Widget> children) => Container(
        decoration: BoxDecoration(
          color: T.cardWhite,
          borderRadius: BorderRadius.circular(18),
          boxShadow: T.shadowCard,
        ),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      );
}
