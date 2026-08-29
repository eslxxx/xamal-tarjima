/// 底部导航外壳: 翻译 / 对话翻译 / 收藏 / 历史记录。
///
/// 用 IndexedStack 而不是每次重建页面 —— 翻译页里有已加载的模型和正在进行的
/// 生成流, 切到收藏再切回来不能把它们重置掉。
library;

import 'package:flutter/material.dart';

import '../core/history_store.dart';
import '../core/model_manager.dart';
import 'home_page.dart';
import 'records_page.dart';
import 'theme.dart';
import 'widgets.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.modelPath,
    required this.manager,
    required this.onModelDeleted,
  });

  final String modelPath;
  final ModelManager manager;
  final VoidCallback onModelDeleted;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _tab = 0;

  /// 从历史/收藏里点某条时, 通过它把内容送回翻译页。
  /// 用 ValueNotifier 而不是把输入框状态提到外壳里 —— 翻译页的状态机比较重
  /// (防抖、取消、分段流式), 拆散反而更容易出错。
  final _reuse = ValueNotifier<TranslationRecord?>(null);

  @override
  void dispose() {
    _reuse.dispose();
    super.dispose();
  }

  void _onReuse(TranslationRecord r) {
    _reuse.value = r;
    setState(() => _tab = 0);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      backgroundColor: T.bgBottom,
      body: Container(
        decoration: const BoxDecoration(gradient: T.pageGradient),
        child: Column(
          children: [
            Expanded(
              child: IndexedStack(
                index: _childFor(_tab),
                children: [
                  HomePage(
                    modelPath: widget.modelPath,
                    reuse: _reuse,
                    manager: widget.manager,
                    onModelDeleted: widget.onModelDeleted,
                  ),
                  SafeArea(
                    bottom: false,
                    child: RecordsPage(onlyFavorites: true, onReuse: _onReuse),
                  ),
                  SafeArea(
                    bottom: false,
                    child: RecordsPage(onlyFavorites: false, onReuse: _onReuse),
                  ),
                ],
              ),
            ),
            _nav(),
          ],
        ),
      ),
    );
  }

  /// 导航栏有 4 项但只有 3 个页面 (对话翻译未实现), 这里做映射。
  static int _childFor(int tab) => switch (tab) {
        2 => 1, // 收藏
        3 => 2, // 历史记录
        _ => 0, // 翻译 (对话翻译也停在这里)
      };

  Widget _nav() {
    const items = [
      (Icons.home_rounded, '翻译'),
      (Icons.chat_bubble_outline_rounded, '对话翻译'),
      (Icons.star_border_rounded, '收藏'),
      (Icons.access_time_rounded, '历史记录'),
    ];
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 4, 10, 0),
      padding: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        boxShadow: T.shadowCard,
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            for (var i = 0; i < items.length; i++)
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    // 对话翻译还没做, 保留位置但明确告知
                    if (i == 1) {
                      showNotYet(context, items[i].$2);
                      return;
                    }
                    setState(() => _tab = i);
                  },
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          i == _tab && i != 1
                              ? _activeIcon(items[i].$1)
                              : items[i].$1,
                          size: 24,
                          color: i == _tab && i != 1
                              ? T.blue
                              : const Color(0xFFA9B2BF),
                        ),
                        const SizedBox(height: 3),
                        Text(items[i].$2,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: i == _tab && i != 1
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              color: i == _tab && i != 1
                                  ? T.blue
                                  : const Color(0xFFA9B2BF),
                            )),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 选中态用实心图标, 视觉上更明确
  static IconData _activeIcon(IconData outline) => switch (outline) {
        Icons.star_border_rounded => Icons.star_rounded,
        _ => outline,
      };
}
