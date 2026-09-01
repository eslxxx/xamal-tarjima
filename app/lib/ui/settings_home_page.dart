/// 设置入口页。
///
/// 二级结构: 这一层只有横幅位和三个入口, 真正的开关都在「设置」里面
/// (settings_page.dart)。这么分是因为顶部要放一块后台可控的运营位, 而在一屏开关
/// 上面压一张图很难看, 也会把第一眼的注意力从开关上引开。
library;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_info.dart';
import '../core/model_manager.dart';
import '../core/remote_config.dart';
import 'about_page.dart';
import 'banner_carousel.dart';
import 'settings_page.dart';
import 'theme.dart';

class SettingsHomePage extends StatefulWidget {
  const SettingsHomePage({
    super.key,
    required this.manager,
    required this.onModelDeleted,
  });

  final ModelManager manager;

  /// 删除模型后要回到下载引导页, 由外层处理
  final VoidCallback onModelDeleted;

  @override
  State<SettingsHomePage> createState() => _SettingsHomePageState();
}

class _SettingsHomePageState extends State<SettingsHomePage> {
  final _config = RemoteConfig.instance;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _config.addListener(_onConfig);
    // 进来顺手刷一次。有 30 分钟最小间隔, 所以不是每次进设置都真的发请求。
    _config.refresh();
  }

  @override
  void dispose() {
    _config.removeListener(_onConfig);
    super.dispose();
  }

  void _onConfig() {
    if (mounted) setState(() {});
  }

  bool get _hasUpdate {
    final l = _config.latest;
    return l != null && l.isNewerThan(kAppVersion);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: T.bgBottom,
      body: Container(
        decoration: const BoxDecoration(gradient: T.pageGradient),
        child: SafeArea(
          child: Column(
            children: [
              _header(),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                  children: [
                    const BannerCarousel(),
                    const SizedBox(height: 18),
                    _entry(
                      icon: Icons.settings_rounded,
                      label: '设置',
                      onTap: _openSettings,
                    ),
                    const SizedBox(height: 12),
                    _entry(
                      icon: Icons.info_rounded,
                      label: '关于',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const AboutPage()),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _entry(
                      icon: Icons.arrow_circle_up_rounded,
                      label: '更新版本',
                      note: _hasUpdate ? '有新版本 ${_config.latest!.version}' : null,
                      busy: _checking,
                      onTap: _checkUpdate,
                    ),
                    // 列表最下方的署名
                    const Padding(
                      padding: EdgeInsets.only(top: 28),
                      child: Text('$kVendor 开发',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12, color: T.textTertiary)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 标题居中 (照设计稿), 返回箭头压在左边
  Widget _header() => SizedBox(
        height: 52,
        child: Stack(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back_rounded, color: T.textPrimary),
              ),
            ),
            const Center(
              child: Text('设置',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: T.textPrimary)),
            ),
          ],
        ),
      );

  Widget _entry({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    String? note,
    bool busy = false,
  }) {
    final radius = BorderRadius.circular(T.rCard);
    return Container(
      decoration: BoxDecoration(
        color: T.cardWhite,
        borderRadius: radius,
        boxShadow: T.shadowCard,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          onTap: busy ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                      color: Color(0xFFE9F1FE), shape: BoxShape.circle),
                  child: Icon(icon, size: 24, color: T.blue),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label,
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: T.textPrimary)),
                      if (note != null) ...[
                        const SizedBox(height: 3),
                        Text(note,
                            style: const TextStyle(fontSize: 12, color: T.blue)),
                      ],
                    ],
                  ),
                ),
                busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: T.iconGrey))
                    : const Icon(Icons.chevron_right_rounded,
                        color: T.textTertiary, size: 26),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openSettings() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SettingsPage(
        manager: widget.manager,
        onModelDeleted: widget.onModelDeleted,
      ),
    ));
  }

  // ── 检查更新 ────────────────────────────────────────────

  /// 这里必须能区分三种结果, 否则「已经是最新版本」会在没网的时候骗人:
  ///   没内置后台地址 / 没连上 / 真的是最新版。
  Future<void> _checkUpdate() async {
    if (!_config.configured) {
      _toast('此版本未内置更新检查');
      return;
    }
    final before = _config.lastFetchAt;
    setState(() => _checking = true);
    await _config.refresh(force: true);
    if (!mounted) return;
    setState(() => _checking = false);

    if (_config.lastFetchAt == before) {
      _toast('检查失败，请确认网络后重试');
      return;
    }
    final latest = _config.latest;
    if (latest == null || !latest.isNewerThan(kAppVersion)) {
      _toast('已经是最新版本 $kAppVersion');
      return;
    }
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('发现新版本 ${latest.version}'),
        content: Text(latest.notes ?? '建议更新到最新版本。',
            style: const TextStyle(fontSize: 13.5, height: 1.6)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              style: TextButton.styleFrom(foregroundColor: T.textSecondary),
              child: const Text('以后再说')),
          if (latest.url != null)
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('去下载')),
        ],
      ),
    );
    if (go != true) return;
    final uri = Uri.tryParse(latest.url!);
    // 浏览器里下载: App 自己下 APK 还要装, 那要请求安装未知应用的权限, 不值得
    if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _toast(String text) {
    final m = ScaffoldMessenger.of(context);
    m.hideCurrentSnackBar();
    m.showSnackBar(SnackBar(
      content: Text(text),
      behavior: SnackBarBehavior.floating,
      shape: const StadiumBorder(),
      backgroundColor: const Color(0xE6202733),
      duration: const Duration(milliseconds: 1800),
    ));
  }
}
