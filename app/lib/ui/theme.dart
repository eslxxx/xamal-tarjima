/// 视觉规范。取自设计稿: 浅蓝渐变、大圆角、柔和阴影。
library;

import 'package:flutter/material.dart';

class T {
  // ── 颜色 ────────────────────────────────────────────────
  /// 主蓝, 用于强调文字、图标、主按钮
  static const blue = Color(0xFF2B6FF0);
  static const blueDeep = Color(0xFF1B5AD6);

  /// 页面背景渐变 (上 → 下)
  static const bgTop = Color(0xFFDCE9F8);
  static const bgMid = Color(0xFFEDF4FC);
  static const bgBottom = Color(0xFFF7FAFE);

  /// 卡片
  static const cardWhite = Colors.white;
  /// 译文卡片的浅蓝底
  static const cardBlue = Color(0xFFDDEAFB);

  static const textPrimary = Color(0xFF1A1D22);
  static const textSecondary = Color(0xFF8A93A0);
  static const textTertiary = Color(0xFFAAB3BF);
  static const iconGrey = Color(0xFF9AA4B2);

  // ── 圆角 ────────────────────────────────────────────────
  static const rCard = 22.0;
  static const rPill = 999.0;

  // ── 阴影 ────────────────────────────────────────────────
  /// 卡片阴影: 大范围低透明度, 做出「悬浮在渐变背景上」的感觉
  static const shadowCard = <BoxShadow>[
    BoxShadow(color: Color(0x14374A6B), blurRadius: 24, offset: Offset(0, 8)),
    BoxShadow(color: Color(0x0A374A6B), blurRadius: 4, offset: Offset(0, 1)),
  ];

  static const shadowPill = <BoxShadow>[
    BoxShadow(color: Color(0x1A374A6B), blurRadius: 20, offset: Offset(0, 6)),
  ];

  static const shadowButton = <BoxShadow>[
    BoxShadow(color: Color(0x552B6FF0), blurRadius: 20, offset: Offset(0, 8)),
  ];

  /// 页面背景
  static const pageGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [bgTop, bgMid, bgBottom],
    stops: [0.0, 0.28, 0.6],
  );
}
