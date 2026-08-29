/// hero 建筑图。
///
/// 图片本身是不透明的浅蓝底位图, 直接贴上去会露出生硬的矩形边。
/// 这里用 ShaderMask + dstIn 给左边和上下做羽化, 让它自然溶进页面渐变里。
library;

import 'package:flutter/material.dart';

/// 建筑图的贴法。
enum HeroFade {
  /// 顶部 hero 用: 左侧和下方羽化 (右侧贴边)
  header,

  /// 译文卡片底部用: 上方和左右都羽化
  card,
}

class HeroImage extends StatelessWidget {
  const HeroImage({
    super.key,
    required this.fade,
    this.opacity = 1.0,
    this.alignment = Alignment.bottomRight,
  });

  final HeroFade fade;
  final double opacity;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    final image = Opacity(
      opacity: opacity,
      child: Image.asset(
        'assets/images/hero.png',
        fit: BoxFit.cover,
        alignment: alignment,
        // 淡色插画, 低分辨率下缩放会有摩尔纹, 用 medium 质量足够且省
        filterQuality: FilterQuality.medium,
      ),
    );

    return IgnorePointer(
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (rect) => switch (fade) {
          // 左→右 逐渐显现, 右侧完全实心
          HeroFade.header => const LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [Color(0x00FFFFFF), Color(0x66FFFFFF), Color(0xFFFFFFFF)],
              stops: [0.0, 0.30, 0.62],
            ).createShader(rect),
          // 上→下 逐渐显现, 底部实心
          HeroFade.card => const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x00FFFFFF), Color(0x80FFFFFF), Color(0xFFFFFFFF)],
              stops: [0.0, 0.45, 1.0],
            ).createShader(rect),
        },
        child: image,
      ),
    );
  }
}
