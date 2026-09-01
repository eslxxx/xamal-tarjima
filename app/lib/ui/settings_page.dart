/// 设置页 —— 真正的开关都在这里。
///
/// 这是二级页, 上一层是 settings_home_page.dart 的入口页 (横幅 + 设置/关于/更新版本)。
/// 「关于」的内容搬去了 about_page.dart。
///
/// 只放真的有用的项 —— 不做占位开关。每一项都对应一个能观察到的行为变化。
library;

import 'package:flutter/material.dart';

import '../core/app_settings.dart';
import '../core/engine.dart';
import '../core/history_store.dart';
import '../core/model_manager.dart';
import '../core/translation_cache.dart';
import 'theme.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.manager,
    required this.onModelDeleted,
  });

  final ModelManager manager;

  /// 删除模型后要回到下载引导页, 由外层处理
  final VoidCallback onModelDeleted;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _settings = AppSettings.instance;
  final _cache = TranslationCache.instance;
  final _history = HistoryStore.instance;

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
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 18, 6),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.arrow_back_rounded,
                          color: T.textPrimary),
                    ),
                    const Text('设置',
                        style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: T.textPrimary)),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                  children: [
                    _section('翻译'),
                    _card([
                      _switchTile(
                        title: '使用官方推荐采样参数',
                        subtitle: _settings.officialSampling
                            ? '措辞更灵活，但同一句每次结果可能不同'
                            : '当前为贪心解码：结果稳定可复现，速度略快',
                        value: _settings.officialSampling,
                        onChanged: (v) =>
                            setState(() => _settings.officialSampling = v),
                      ),
                      _divider(),
                      _switchTile(
                        title: '记录翻译历史',
                        subtitle: '关闭后不再新增记录，已有记录不受影响',
                        value: _settings.keepHistory,
                        onChanged: (v) => setState(() => _settings.keepHistory = v),
                      ),
                    ]),
                    _section('存储'),
                    _card([
                      _actionTile(
                        title: '译文缓存',
                        subtitle: '${_cache.size} 条 · 命中缓存的句子无需重新推理',
                        actionLabel: '清空',
                        onTap: () => setState(_cache.clear),
                      ),
                      _divider(),
                      _actionTile(
                        title: '历史与收藏',
                        subtitle: '${_history.count} 条记录，其中 ${_history.favoriteCount} 条已收藏',
                        actionLabel: '清空历史',
                        onTap: () => setState(_history.clearHistoryKeepFavorites),
                      ),
                    ]),
                    _section('模型'),
                    _card([_modelTile(info)]),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── 小组件 ──────────────────────────────────────────────

  Widget _section(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 18, 8, 8),
        child: Text(text,
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600, color: T.textSecondary)),
      );

  Widget _card(List<Widget> children) => Container(
        decoration: BoxDecoration(
          color: T.cardWhite,
          borderRadius: BorderRadius.circular(18),
          boxShadow: T.shadowCard,
        ),
        child: Column(children: children),
      );

  Widget _divider() => const Divider(
      height: 1, thickness: 1, indent: 16, endIndent: 16, color: Color(0xFFF1F4F9));

  Widget _switchTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool>? onChanged,
  }) =>
      SwitchListTile(
        value: value,
        onChanged: onChanged,
        activeThumbColor: Colors.white,
        activeTrackColor: T.blue,
        contentPadding: const EdgeInsets.fromLTRB(16, 6, 10, 6),
        title: Text(title,
            style: const TextStyle(fontSize: 15, color: T.textPrimary)),
        subtitle: Text(subtitle,
            style: const TextStyle(fontSize: 12.5, color: T.textSecondary)),
      );

  Widget _actionTile({
    required String title,
    required String subtitle,
    required String actionLabel,
    required VoidCallback onTap,
  }) =>
      ListTile(
        contentPadding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
        title:
            Text(title, style: const TextStyle(fontSize: 15, color: T.textPrimary)),
        subtitle: Text(subtitle,
            style: const TextStyle(fontSize: 12.5, color: T.textSecondary)),
        trailing: TextButton(
          onPressed: onTap,
          style: TextButton.styleFrom(foregroundColor: T.blue),
          child: Text(actionLabel),
        ),
      );

  Widget _modelTile(EngineInfo? info) {
    final spec = widget.manager.spec;
    return ListTile(
      contentPadding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      title: Text('Hy-MT1.5-1.8B · 1.25bit',
          style: const TextStyle(fontSize: 15, color: T.textPrimary)),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          info == null
              ? '${spec.sizeLabel} · 尚未加载'
              : '${spec.sizeLabel} · ${info.threads} 线程 · n_ctx ${info.nCtx}'
                  '${info.templateOk ? "" : "\n⚠ chat 模板与预期不符，译文可能不准"}',
          style: const TextStyle(fontSize: 12.5, height: 1.5, color: T.textSecondary),
        ),
      ),
      trailing: TextButton(
        onPressed: _confirmDeleteModel,
        style: TextButton.styleFrom(foregroundColor: const Color(0xFFC0392B)),
        child: const Text('删除'),
      ),
    );
  }

  Future<void> _confirmDeleteModel() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除翻译模型'),
        content: Text('会释放约 ${widget.manager.spec.sizeLabel} 空间。'
            '删除后需要重新下载才能继续翻译。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(foregroundColor: const Color(0xFFC0392B)),
              child: const Text('删除')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    // 先卸掉引擎再删文件 —— 模型是 mmap 进来的, 文件还被映射着就删会出问题
    await TranslateEngine.instance.dispose();
    await widget.manager.deleteAll();
    if (!mounted) return;
    // popUntil 而不是 pop: 设置现在是两级 (入口页 → 设置), 只 pop 一层会把入口页
    // 留在下载引导页上面。
    Navigator.of(context).popUntil((r) => r.isFirst);
    widget.onModelDeleted();
  }
}
