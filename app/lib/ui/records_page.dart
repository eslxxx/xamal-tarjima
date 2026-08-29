/// 历史记录 / 收藏 列表页。两者共用同一份存储, 只差一个过滤条件。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/history_store.dart';
import '../core/langs.dart';
import 'theme.dart';

class RecordsPage extends StatefulWidget {
  const RecordsPage({
    super.key,
    required this.onlyFavorites,
    required this.onReuse,
  });

  final bool onlyFavorites;

  /// 点某条 → 把它填回主界面的输入框
  final void Function(TranslationRecord) onReuse;

  @override
  State<RecordsPage> createState() => _RecordsPageState();
}

class _RecordsPageState extends State<RecordsPage> {
  final _store = HistoryStore.instance;

  @override
  void initState() {
    super.initState();
    _store.addListener(_onChanged);
  }

  @override
  void dispose() {
    _store.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.onlyFavorites ? _store.favorites : _store.all;
    final title = widget.onlyFavorites ? '收藏' : '历史记录';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(26, 18, 18, 10),
          child: Row(
            children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: T.textPrimary)),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('${items.length}',
                    style: const TextStyle(fontSize: 14, color: T.textTertiary)),
              ),
              const Spacer(),
              if (items.isNotEmpty && !widget.onlyFavorites)
                TextButton(
                  onPressed: _confirmClear,
                  style: TextButton.styleFrom(foregroundColor: T.textSecondary),
                  child: const Text('清空'),
                ),
            ],
          ),
        ),
        Expanded(
          child: items.isEmpty
              ? _empty()
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _tile(items[i]),
                ),
        ),
      ],
    );
  }

  Widget _empty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            widget.onlyFavorites
                ? Icons.star_border_rounded
                : Icons.access_time_rounded,
            size: 56,
            color: const Color(0xFFC6D2E0),
          ),
          const SizedBox(height: 12),
          Text(
            widget.onlyFavorites ? '还没有收藏的译文' : '还没有翻译记录',
            style: const TextStyle(fontSize: 14, color: T.textTertiary),
          ),
          const SizedBox(height: 6),
          Text(
            widget.onlyFavorites ? '在译文卡片上点 ☆ 就能收藏' : '翻译过的内容会出现在这里',
            style: const TextStyle(fontSize: 12.5, color: T.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _tile(TranslationRecord r) {
    final srcSpec = specOf(r.from);
    final dstSpec = specOf(r.to);
    return Dismissible(
      key: ValueKey('${r.key}|${r.at.millisecondsSinceEpoch}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: const Color(0xFFFBE4E2),
          borderRadius: BorderRadius.circular(T.rCard),
        ),
        child: const Icon(Icons.delete_outline_rounded, color: Color(0xFFC0392B)),
      ),
      onDismissed: (_) => _store.remove(r),
      child: GestureDetector(
        onTap: () => widget.onReuse(r),
        child: Container(
          decoration: BoxDecoration(
            color: T.cardWhite,
            borderRadius: BorderRadius.circular(T.rCard),
            boxShadow: T.shadowCard,
          ),
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text('${srcSpec.zhName} → ${dstSpec.zhName}',
                      style: const TextStyle(fontSize: 12, color: T.blue)),
                  const SizedBox(width: 8),
                  Text(_when(r.at),
                      style:
                          const TextStyle(fontSize: 11.5, color: T.textTertiary)),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => _store.toggleFavorite(
                      from: r.from,
                      to: r.to,
                      source: r.source,
                      translation: r.translation,
                    ),
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        r.favorited
                            ? Icons.star_rounded
                            : Icons.star_border_rounded,
                        size: 21,
                        color: r.favorited ? T.blue : const Color(0xFFB2BCC9),
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => _copy(r.translation),
                    behavior: HitTestBehavior.opaque,
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.copy_rounded,
                          size: 19, color: Color(0xFFB2BCC9)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Directionality(
                textDirection:
                    dstSpec.rtl ? TextDirection.rtl : TextDirection.ltr,
                child: Text(r.translation,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 17,
                        height: 1.5,
                        fontWeight: FontWeight.w600,
                        fontFamily: dstSpec.fontFamily,
                        color: T.textPrimary)),
              ),
              const SizedBox(height: 4),
              Directionality(
                textDirection:
                    srcSpec.rtl ? TextDirection.rtl : TextDirection.ltr,
                child: Text(r.source,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 13,
                        height: 1.5,
                        fontFamily: srcSpec.fontFamily,
                        color: T.textSecondary)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _when(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return '刚刚';
    if (d.inHours < 1) return '${d.inMinutes} 分钟前';
    if (d.inDays < 1) return '${d.inHours} 小时前';
    if (d.inDays < 30) return '${d.inDays} 天前';
    return '${t.year}-${t.month.toString().padLeft(2, '0')}-'
        '${t.day.toString().padLeft(2, '0')}';
  }

  void _copy(String text) {
    Clipboard.setData(ClipboardData(text: text));
    final m = ScaffoldMessenger.of(context);
    m.hideCurrentSnackBar();
    m.showSnackBar(const SnackBar(
      content: Text('已复制'),
      behavior: SnackBarBehavior.floating,
      margin: EdgeInsets.fromLTRB(120, 0, 120, 96),
      backgroundColor: Color(0xE6202733),
      shape: StadiumBorder(),
      duration: Duration(milliseconds: 1200),
    ));
  }

  Future<void> _confirmClear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空历史记录'),
        // 说清楚收藏会被保留 —— 否则用户不敢点
        content: const Text('收藏的内容会保留，只清除未收藏的记录。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(foregroundColor: const Color(0xFFC0392B)),
              child: const Text('清空')),
        ],
      ),
    );
    if (ok == true) _store.clearHistoryKeepFavorites();
  }
}
