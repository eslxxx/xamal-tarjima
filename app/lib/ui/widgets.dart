/// 通用小组件: 未开放提示、六边形设置按钮、语言切换胶囊、圆形图标按钮。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/langs.dart';
import 'theme.dart';

/// 尚未实现的功能统一用这个提示, 不做假功能骗用户。
void showNotYet(BuildContext context, String feature) {
  final m = ScaffoldMessenger.of(context);
  m.hideCurrentSnackBar();
  m.showSnackBar(SnackBar(
    content: Text('$feature 暂时未开放'),
    behavior: SnackBarBehavior.floating,
    margin: const EdgeInsets.fromLTRB(48, 0, 48, 96),
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
    backgroundColor: const Color(0xE6202733),
    shape: const StadiumBorder(),
    duration: const Duration(milliseconds: 1600),
  ));
}

/// 右上角的六边形设置按钮 (设计稿里那个描边六边形)
class HexButton extends StatelessWidget {
  const HexButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 44,
        height: 44,
        child: CustomPaint(painter: _HexPainter()),
      ),
    );
  }
}

class _HexPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width * 0.36;
    final path = Path();
    for (var i = 0; i < 6; i++) {
      // 从 -90° 起, 画「尖角朝上」的正六边形
      final a = (-90 + i * 60) * math.pi / 180;
      final p = c + Offset(r * math.cos(a), r * math.sin(a));
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    path.close();
    canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xFF3C4654)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..strokeJoin = StrokeJoin.round);
    canvas.drawCircle(
        c,
        r * 0.30,
        Paint()
          ..color = const Color(0xFF3C4654)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6);
  }

  @override
  bool shouldRepaint(_HexPainter oldDelegate) => false;
}

/// 顶部语言切换胶囊。左右各是「中文名 + 自称」两行, 中间是交换按钮。
class LangSwitcher extends StatelessWidget {
  const LangSwitcher({
    super.key,
    required this.from,
    required this.to,
    required this.onPickFrom,
    required this.onPickTo,
    required this.onSwap,
    this.enabled = true,
  });

  final Lang from;
  final Lang to;
  final ValueChanged<Lang> onPickFrom;
  final ValueChanged<Lang> onPickTo;
  final VoidCallback onSwap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 68,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(T.rPill),
        boxShadow: T.shadowPill,
      ),
      child: Row(
        children: [
          Expanded(child: _side(context, from, onPickFrom)),
          _swapButton(),
          Expanded(child: _side(context, to, onPickTo)),
        ],
      ),
    );
  }

  Widget _side(BuildContext context, Lang lang, ValueChanged<Lang> onPick) {
    final spec = specOf(lang);
    return InkWell(
      borderRadius: BorderRadius.circular(T.rPill),
      onTap: enabled ? () => _pick(context, lang, onPick) : null,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(spec.zhName,
                  style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: T.textPrimary)),
              const SizedBox(width: 2),
              const Icon(Icons.expand_more, size: 17, color: T.iconGrey),
            ],
          ),
          Text(spec.nativeName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 12,
                  fontFamily: spec.fontFamily,
                  color: T.textTertiary)),
        ],
      ),
    );
  }

  Widget _swapButton() {
    return GestureDetector(
      onTap: enabled ? onSwap : null,
      child: Container(
        width: 40,
        height: 40,
        decoration: const BoxDecoration(
          color: Color(0xFFF0F4FA),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.swap_horiz_rounded, size: 21, color: Color(0xFF4A5462)),
      ),
    );
  }

  Future<void> _pick(
      BuildContext context, Lang current, ValueChanged<Lang> onPick) async {
    final picked = await showModalBottomSheet<Lang>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFE1E6EE),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 8),
            for (final l in Lang.values)
              ListTile(
                title: Text(specOf(l).zhName,
                    style: const TextStyle(fontWeight: FontWeight.w500)),
                subtitle: Text(specOf(l).nativeName,
                    style: TextStyle(fontFamily: specOf(l).fontFamily)),
                trailing: l == current
                    ? const Icon(Icons.check_rounded, color: T.blue)
                    : null,
                onTap: () => Navigator.pop(ctx, l),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked != null) onPick(picked);
  }
}

/// 底部那排大按钮里左右两个小圆按钮 (拍照翻译 / 输入翻译)
class RoundActionButton extends StatelessWidget {
  const RoundActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.dimmed = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// 未开放的功能压低对比度, 但保留位置和视觉重量
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: dimmed ? 0.7 : 0.95),
              shape: BoxShape.circle,
              boxShadow: T.shadowCard,
            ),
            child: Icon(icon,
                size: 24,
                color: dimmed ? T.textTertiary : const Color(0xFF3C4654)),
          ),
          const SizedBox(height: 8),
          Text(label,
              style: TextStyle(
                  fontSize: 12,
                  color: dimmed ? T.textTertiary : T.textSecondary)),
        ],
      ),
    );
  }
}

/// 主按钮两侧的声波条 (纯装饰, 呼吸动画)
class WaveBars extends StatelessWidget {
  const WaveBars({super.key, required this.progress, this.reversed = false});

  /// 0..1 循环, 由外部 AnimationController 驱动
  final double progress;
  final bool reversed;

  @override
  Widget build(BuildContext context) {
    const heights = [10.0, 18.0, 26.0, 16.0];
    final bars = reversed ? heights.reversed.toList() : heights;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        for (var i = 0; i < bars.length; i++) ...[
          Container(
            width: 3,
            height: bars[i] *
                (0.55 + 0.45 * (1 - ((progress + i * 0.18) % 1.0 - 0.5).abs() * 2)),
            decoration: BoxDecoration(
              color: T.blue.withValues(alpha: 0.28),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          if (i != bars.length - 1) const SizedBox(width: 5),
        ],
      ],
    );
  }
}
