/// 带 3D 透视的展开面板: 大输入框 与 全文译文查看。
///
/// 为什么需要:
///   卡片式布局在小屏上留给正文的高度有限, 长文本会被截得只剩两三行。
///   点开一个占满屏幕的面板专门写/读, 比在卡片里挤着滚动舒服得多。
///
/// 3D 效果用 Matrix4 的透视项 (setEntry(3,2,...)) 加 rotateX 实现 ——
/// 面板像一张卡片从下方朝用户翻起来, 而不是普通的上下滑入。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/langs.dart';
import 'cards.dart' show kMaxInputChars;
import 'theme.dart';

/// 3D 翻起转场。[origin] 决定绕哪条轴翻 —— 从输入卡片弹出就用 bottomCenter,
/// 从译文卡片弹出就用 topCenter, 视觉上是「就地展开」而不是凭空出现。
Route<R> route3d<R>(Widget page, {Alignment origin = Alignment.bottomCenter}) {
  return PageRouteBuilder<R>(
    opaque: false,
    barrierColor: const Color(0x40101A2B),
    barrierDismissible: true,
    transitionDuration: const Duration(milliseconds: 420),
    reverseTransitionDuration: const Duration(milliseconds: 300),
    pageBuilder: (_, _, _) => page,
    transitionsBuilder: (_, anim, _, child) {
      final curved = CurvedAnimation(
        parent: anim,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return AnimatedBuilder(
        animation: curved,
        builder: (_, _) {
          final v = curved.value;
          return Opacity(
            opacity: v.clamp(0.0, 1.0),
            child: Transform(
              alignment: origin,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.0013) // 透视强度
                ..rotateX((1 - v) * 0.62)
                ..translateByDouble(0.0, (1 - v) * 48, 0.0, 1.0)
                ..scaleByDouble(0.84 + 0.16 * v, 0.84 + 0.16 * v, 1.0, 1.0),
              child: child,
            ),
          );
        },
        child: child,
      );
    },
  );
}

/// 占满屏幕的大输入面板。
///
/// 直接编辑外面那个 TextEditingController, 不走「返回值」——
/// 这样在面板里打字时后台的自动翻译照常跑, 关掉面板时译文往往已经好了。
class InputEditorSheet extends StatelessWidget {
  const InputEditorSheet({
    super.key,
    required this.lang,
    required this.controller,
  });

  final Lang lang;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final spec = specOf(lang);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Container(
            decoration: BoxDecoration(
              color: T.cardWhite,
              borderRadius: BorderRadius.circular(26),
              boxShadow: T.shadowCard,
            ),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Text(spec.zhName,
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: T.blue)),
                    const Spacer(),
                    TextButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      style: TextButton.styleFrom(
                        foregroundColor: T.blue,
                        textStyle: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      child: const Text('完成'),
                    ),
                  ],
                ),
                const Divider(height: 12, color: Color(0xFFEFF3F8)),
                Expanded(
                  child: Directionality(
                    textDirection:
                        spec.rtl ? TextDirection.rtl : TextDirection.ltr,
                    child: TextField(
                      controller: controller,
                      autofocus: true,
                      maxLines: null,
                      expands: true,
                      maxLength: kMaxInputChars,
                      textAlignVertical: TextAlignVertical.top,
                      style: TextStyle(
                          fontSize: 20,
                          height: 1.7,
                          fontFamily: spec.fontFamily,
                          color: T.textPrimary),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        isCollapsed: true,
                        counterText: '',
                        hintText: '输入${spec.zhName}…',
                        hintStyle: const TextStyle(color: T.textTertiary),
                      ),
                    ),
                  ),
                ),
                Row(
                  children: [
                    GestureDetector(
                      onTap: controller.clear,
                      behavior: HitTestBehavior.opaque,
                      child: const Padding(
                        padding: EdgeInsets.all(6),
                        child: Row(children: [
                          Icon(Icons.delete_outline_rounded,
                              size: 20, color: T.iconGrey),
                          SizedBox(width: 4),
                          Text('清空',
                              style: TextStyle(fontSize: 13, color: T.iconGrey)),
                        ]),
                      ),
                    ),
                    const Spacer(),
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: controller,
                      builder: (_, v, _) => Text(
                        '${v.text.characters.length}/$kMaxInputChars',
                        style:
                            const TextStyle(fontSize: 13, color: T.textTertiary),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 占满屏幕的译文查看面板。长文在这里滚动看, 不用在卡片里挤。
class ResultViewerSheet extends StatelessWidget {
  const ResultViewerSheet({
    super.key,
    required this.lang,
    required this.text,
    required this.sourceText,
    required this.sourceLang,
  });

  final Lang lang;
  final String text;
  final String sourceText;
  final Lang sourceLang;

  @override
  Widget build(BuildContext context) {
    final spec = specOf(lang);
    final srcSpec = specOf(sourceLang);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Container(
            decoration: BoxDecoration(
              color: T.cardBlue,
              borderRadius: BorderRadius.circular(26),
              boxShadow: T.shadowCard,
            ),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Text(spec.zhName,
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: T.blue)),
                    const Spacer(),
                    IconButton(
                      onPressed: () => _copy(context),
                      icon: const Icon(Icons.copy_rounded,
                          size: 22, color: Color(0xFF56616F)),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.close_rounded,
                          size: 24, color: Color(0xFF56616F)),
                    ),
                  ],
                ),
                const Divider(height: 12, color: Color(0x33FFFFFF)),
                Expanded(child: _scrollBody(srcSpec)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _copy(BuildContext context) {
    Clipboard.setData(ClipboardData(text: text));
    final m = ScaffoldMessenger.of(context);
    m.hideCurrentSnackBar();
    m.showSnackBar(const SnackBar(
      content: Text('已复制'),
      behavior: SnackBarBehavior.floating,
      shape: StadiumBorder(),
      backgroundColor: Color(0xE6202733),
      duration: Duration(milliseconds: 1200),
    ));
  }

  Widget _scrollBody(LangSpec srcSpec) {
    final spec = specOf(lang);
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Directionality(
            textDirection: spec.rtl ? TextDirection.rtl : TextDirection.ltr,
            child: SelectableText(
              text,
              style: TextStyle(
                  fontSize: 21,
                  height: 1.8,
                  fontWeight: FontWeight.w600,
                  fontFamily: spec.fontFamily,
                  color: T.textPrimary),
            ),
          ),
          // 对照原文放在下面 —— 长文校对时来回切面板很烦
          if (sourceText.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text('原文 · ${srcSpec.zhName}',
                style: const TextStyle(fontSize: 12.5, color: Color(0xFF7A8694))),
            const SizedBox(height: 6),
            Directionality(
              textDirection: srcSpec.rtl ? TextDirection.rtl : TextDirection.ltr,
              child: SelectableText(
                sourceText,
                style: TextStyle(
                    fontSize: 15,
                    height: 1.7,
                    fontFamily: srcSpec.fontFamily,
                    color: const Color(0xFF5C6773)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
