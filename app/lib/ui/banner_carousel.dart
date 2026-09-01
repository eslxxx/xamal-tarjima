/// 设置页顶部的运营位横幅。
///
/// 后台给的一条横幅就是**一整张图** + 一个可选跳转链接 (见 backend/src/banners.ts),
/// 所以这里不排版任何文字, 只做: 圆角裁剪 → 轮播 → 点击跳浏览器。
///
/// 没有横幅可显示时 (没联网过 / 后台没配 / 图还没下完) 画一张内置的。内置那张是
/// 画出来的而不是打包一张 PNG: 任何分辨率都清晰, 也不会让 APK 变大。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/remote_config.dart';
import 'theme.dart';

/// 设计稿里横幅约 845×415, 保持这个比例
const double _kAspect = 2.04;

class BannerCarousel extends StatefulWidget {
  const BannerCarousel({super.key});

  @override
  State<BannerCarousel> createState() => _BannerCarouselState();
}

class _BannerCarouselState extends State<BannerCarousel> {
  final _config = RemoteConfig.instance;
  final _pager = PageController();
  Timer? _timer;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _config.addListener(_onConfig);
    // 磁盘上的横幅在 main() 里就读好了, 这里可能一上来就有多张 —— 不能只等
    // notifyListeners 才开始轮播。
    _restartTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _config.removeListener(_onConfig);
    _pager.dispose();
    super.dispose();
  }

  void _onConfig() {
    if (mounted) setState(_restartTimer);
  }

  /// 只轮播已经下载好图的那些 —— 半张图或者空白格子比少一张更难看
  List<BannerItem> get _ready =>
      [for (final b in _config.banners) if (b.file != null) b];

  void _restartTimer() {
    _timer?.cancel();
    if (_ready.length < 2) return;
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted) return;
      final n = _ready.length;
      if (n < 2) return;
      _pager.animateToPage(
        (_index + 1) % n,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
      );
    });
  }

  Future<void> _open(BannerItem b) async {
    final link = b.link;
    if (link == null) return;
    final uri = Uri.tryParse(link);
    if (uri == null) return;
    // 外部浏览器打开: 不在 App 里内嵌 WebView —— 那等于替后台的页面背书,
    // 而且用户看不到自己到了哪个域名。
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final items = _ready;
    return AspectRatio(
      aspectRatio: _kAspect,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: items.isEmpty
            ? const _BuiltinBanner()
            : Stack(
                children: [
                  PageView.builder(
                    controller: _pager,
                    itemCount: items.length,
                    onPageChanged: (i) => setState(() => _index = i),
                    itemBuilder: (_, i) {
                      final b = items[i];
                      return GestureDetector(
                        onTap: b.link == null ? null : () => _open(b),
                        child: Image.file(
                          b.file!,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          // 文件被删/损坏时不要留一个红色报错块
                          errorBuilder: (_, _, _) => const _BuiltinBanner(),
                        ),
                      );
                    },
                  ),
                  if (items.length > 1)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 12,
                      // 后台删掉一张时 items 会变短, _index 可能还停在旧位置
                      child: _Dots(
                          count: items.length,
                          active: _index.clamp(0, items.length - 1)),
                    ),
                ],
              ),
      ),
    );
  }
}

/// 轮播小圆点。当前页那颗是白的、稍大。
class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.active});

  final int count;
  final int active;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          Container(
            width: i == active ? 7 : 6,
            height: i == active ? 7 : 6,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: i == active ? 0.95 : 0.5),
            ),
          ),
      ],
    );
  }
}

/// 拉不到后台横幅时显示的那张。
///
/// 文案只说这个 App 确实做到的事, 不写「全新体验升级」这类没有内容的话 ——
/// 离线、免费、原文不出设备本来就是它最值得说的三件事。
class _BuiltinBanner extends StatelessWidget {
  const _BuiltinBanner();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF4B8BF5), T.blueDeep],
        ),
      ),
      child: Stack(
        children: [
          // 右侧的大字符水印, 被卡片边缘裁掉一部分 —— 当装饰用
          Positioned(
            right: -18,
            bottom: -34,
            child: Icon(
              Icons.translate_rounded,
              size: 150,
              color: Colors.white.withValues(alpha: 0.13),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 0, 130, 0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '完全离线翻译',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '维吾尔语 · 哈萨克语 · 汉语\n原文和译文不会离开这台手机',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.5,
                    color: Colors.white.withValues(alpha: 0.88),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
