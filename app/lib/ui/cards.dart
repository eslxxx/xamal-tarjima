/// 输入卡片 / 译文卡片。
library;

import 'package:flutter/material.dart';

import '../core/langs.dart';
import 'hero_image.dart';
import 'theme.dart';

const int kMaxInputChars = 500;

class InputCard extends StatelessWidget {
  const InputCard({
    super.key,
    required this.lang,
    required this.controller,
    required this.onClear,
    required this.onSpeak,
    required this.onTapEdit,
  });

  final Lang lang;
  final TextEditingController controller;
  final VoidCallback onClear;
  final VoidCallback onSpeak;

  /// 点卡片正文区 → 打开占满屏幕的大输入面板。
  /// 卡片里不直接编辑: 小屏上留给正文的高度只有百来像素, 长文在这里打字看不见几行。
  final VoidCallback onTapEdit;

  @override
  Widget build(BuildContext context) {
    final spec = specOf(lang);
    return Container(
      decoration: BoxDecoration(
        color: T.cardWhite,
        borderRadius: BorderRadius.circular(T.rCard),
        boxShadow: T.shadowCard,
      ),
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _CardLangLabel(spec.zhName),
              const Spacer(),
              GestureDetector(
                onTap: onClear,
                behavior: HitTestBehavior.opaque,
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.close_rounded, size: 22, color: T.iconGrey),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Expanded(
            child: GestureDetector(
              onTap: onTapEdit,
              behavior: HitTestBehavior.opaque,
              child: ValueListenableBuilder<TextEditingValue>(
                valueListenable: controller,
                builder: (_, v, _) {
                  final empty = v.text.trim().isEmpty;
                  return Directionality(
                    textDirection:
                        spec.rtl ? TextDirection.rtl : TextDirection.ltr,
                    child: SingleChildScrollView(
                      physics: const NeverScrollableScrollPhysics(),
                      child: Text(
                        empty ? '点这里输入${spec.zhName}' : v.text,
                        style: TextStyle(
                          fontSize: 19,
                          height: 1.6,
                          fontFamily: spec.fontFamily,
                          color: empty ? T.textTertiary : T.textPrimary,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              GestureDetector(
                onTap: onSpeak,
                behavior: HitTestBehavior.opaque,
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.volume_up_rounded, size: 24, color: T.blue),
                ),
              ),
              const Spacer(),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: controller,
                builder: (_, v, _) => Text(
                  '${v.text.characters.length}/$kMaxInputChars',
                  style: const TextStyle(fontSize: 13, color: T.textTertiary),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CardLangLabel extends StatelessWidget {
  const _CardLangLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(text,
            style: const TextStyle(
                fontSize: 15, fontWeight: FontWeight.w600, color: T.blue)),
        const SizedBox(width: 2),
        const Icon(Icons.expand_more, size: 17, color: T.blue),
      ],
    );
  }
}

class OutputCard extends StatelessWidget {
  const OutputCard({
    super.key,
    required this.lang,
    required this.text,
    required this.busy,
    required this.onFavorite,
    required this.onCopy,
    required this.onSpeak,
    required this.onTapExpand,
    this.stale = false,
    this.favorited = false,
  });

  final Lang lang;
  final String text;
  final bool busy;
  final VoidCallback onFavorite;
  final VoidCallback onCopy;
  final VoidCallback onSpeak;

  /// 点卡片 → 打开占满屏幕的译文面板 (可滚动看全文)
  final VoidCallback onTapExpand;

  /// true 表示这是上一次的译文, 新一轮翻译正在跑。
  /// 压低透明度提示"正在更新"—— 但**不清空**, 清空会让用户以为结果丢了。
  final bool stale;
  final bool favorited;

  @override
  Widget build(BuildContext context) {
    final spec = specOf(lang);
    return ClipRRect(
      borderRadius: BorderRadius.circular(T.rCard),
      child: Container(
        decoration: BoxDecoration(
          color: T.cardBlue,
          borderRadius: BorderRadius.circular(T.rCard),
        ),
        child: Stack(
          children: [
            // 卡片底部的淡建筑图, 和顶部 hero 呼应
            const Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 138,
              child: HeroImage(fade: HeroFade.card, opacity: 0.62),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      _CardLangLabel(spec.zhName),
                      const Spacer(),
                      _act(favorited ? Icons.star_rounded : Icons.star_border_rounded,
                          onFavorite,
                          active: favorited),
                      const SizedBox(width: 14),
                      _act(Icons.copy_rounded, onCopy),
                      const SizedBox(width: 14),
                      _act(Icons.volume_up_rounded, onSpeak, active: true),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: GestureDetector(
                      onTap: text.isEmpty ? null : onTapExpand,
                      behavior: HitTestBehavior.opaque,
                      child: AnimatedOpacity(
                        // 上一轮译文在新一轮跑的时候压淡, 但不清空
                        opacity: stale ? 0.42 : 1.0,
                        duration: const Duration(milliseconds: 180),
                        child: SingleChildScrollView(
                          physics: const NeverScrollableScrollPhysics(),
                          child: Directionality(
                            textDirection:
                                spec.rtl ? TextDirection.rtl : TextDirection.ltr,
                            child: _body(spec),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(LangSpec spec) {
    if (text.isEmpty && busy) {
      return const Align(
        alignment: Alignment.topLeft,
        child: _TypingDots(),
      );
    }
    // 卡片里用 Text 而不是 SelectableText: SelectableText 会吃掉点击手势,
    // 导致点卡片展开全文失效。选中复制在全屏面板里做。
    return Text.rich(
      TextSpan(children: [
        TextSpan(
          text: text,
          style: TextStyle(
              fontSize: 21,
              height: 1.7,
              fontWeight: FontWeight.w600,
              fontFamily: spec.fontFamily,
              color: T.textPrimary),
        ),
        // 生成中在末尾挂一个方块光标, 让「正在出字」看得见
        if (busy)
          const WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: _Caret(),
          ),
      ]),
    );
  }

  Widget _act(IconData icon, VoidCallback onTap, {bool active = false}) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Icon(icon, size: 23, color: active ? T.blue : const Color(0xFF6C7787)),
    );
  }
}

/// 生成中的方块光标。CPU 推理一句要几秒, 没有这个反馈用户会以为卡死了。
class _Caret extends StatefulWidget {
  const _Caret();

  @override
  State<_Caret> createState() => _CaretState();
}

class _CaretState extends State<_Caret> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _c.drive(Tween(begin: 0.15, end: 1.0)),
      child: Container(
        width: 9,
        height: 20,
        margin: const EdgeInsets.only(left: 2),
        decoration: BoxDecoration(
          color: T.blue,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

/// 第一个 token 还没到时的三点等待动画
class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 3; i++) ...[
            Opacity(
              opacity: 0.25 +
                  0.75 * (1 - (((_c.value + i * 0.22) % 1.0) - 0.5).abs() * 2),
              child: Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(color: T.blue, shape: BoxShape.circle),
              ),
            ),
            if (i != 2) const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }
}
