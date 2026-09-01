/// 首启模型下载引导页。
///
/// 为什么单独做一页而不是在主界面弹窗:
///   440MB 下载在弱网下可能要十几分钟, 期间需要显示速度、进度、可取消、可重试,
///   还要解释"为什么要下这么大的东西"。塞进弹窗会很挤, 也不好处理中断恢复。
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_info.dart';
import '../core/model_manager.dart';
import 'hero_image.dart';
import 'theme.dart';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({
    super.key,
    required this.manager,
    required this.onReady,
  });

  final ModelManager manager;
  final VoidCallback onReady;

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  StreamSubscription<ModelProgress>? _sub;
  ModelProgress _p = const ModelProgress(ModelStage.idle);
  int _resumeFrom = 0;

  @override
  void initState() {
    super.initState();
    _checkResume();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _checkResume() async {
    final got = await widget.manager.downloadedBytes();
    if (mounted && got > 0) setState(() => _resumeFrom = got);
  }

  void _start() {
    _sub?.cancel();
    setState(() => _p = const ModelProgress(ModelStage.downloading));
    _sub = widget.manager.prepare().listen((p) {
      if (!mounted) return;
      setState(() => _p = p);
      if (p.stage == ModelStage.ready) widget.onReady();
    });
  }

  void _cancel() {
    widget.manager.cancel();
    _sub?.cancel();
    _checkResume();
    setState(() => _p = const ModelProgress(ModelStage.idle, message: '已暂停'));
  }

  static String _mb(int b) => '${(b / 1024 / 1024).toStringAsFixed(1)} MB';

  static String _speed(double bps) {
    if (bps <= 0) return '';
    if (bps > 1024 * 1024) return '${(bps / 1024 / 1024).toStringAsFixed(1)} MB/s';
    return '${(bps / 1024).round()} KB/s';
  }

  @override
  Widget build(BuildContext context) {
    final spec = widget.manager.spec;
    final busy = _p.stage == ModelStage.downloading ||
        _p.stage == ModelStage.verifying ||
        _p.stage == ModelStage.normalizing;

    return Scaffold(
      backgroundColor: T.bgBottom,
      body: Container(
        decoration: const BoxDecoration(gradient: T.pageGradient),
        child: SafeArea(
          child: Stack(
            children: [
              Positioned(
                right: 0,
                left: 0,
                top: 90,
                height: 190,
                child: const HeroImage(fade: HeroFade.header),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(26, 26, 26, 26),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(kAppName,
                        style: TextStyle(
                            fontSize: 27,
                            fontWeight: FontWeight.w700,
                            color: T.textPrimary)),
                    const SizedBox(height: 8),
                    const Text('科技连接世界 · 语言沟通未来',
                        style: TextStyle(fontSize: 13, color: T.textSecondary)),
                    const Spacer(),
                    _card(spec, busy),
                    const SizedBox(height: 18),
                    _buttons(busy),
                    const SizedBox(height: 10),
                    const Text(
                      // 不写"仅发送统计"了 —— 设置页的横幅和版本检查也会联网,
                      // 联网的事一条条写在「关于」里。
                      '模型由腾讯混元开源，本应用免费且不含广告。\n翻译全程在本机完成，不上传原文或译文；\n联网详情见「关于」。',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 11.5, height: 1.6, color: T.textTertiary),
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

  Widget _card(ModelSpec spec, bool busy) {
    final failed = _p.stage == ModelStage.failed;
    return Container(
      decoration: BoxDecoration(
        color: T.cardWhite,
        borderRadius: BorderRadius.circular(T.rCard),
        boxShadow: T.shadowCard,
      ),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF1FD),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.cloud_download_outlined,
                    color: T.blue, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('首次使用需要下载翻译模型',
                        style: TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w600,
                            color: T.textPrimary)),
                    const SizedBox(height: 3),
                    Text('${spec.sizeLabel} · 建议在 Wi-Fi 下下载',
                        style: const TextStyle(
                            fontSize: 12.5, color: T.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
          if (busy || _p.received > 0 || failed) ...[
            const SizedBox(height: 18),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _p.stage == ModelStage.downloading ? _p.fraction : null,
                minHeight: 6,
                backgroundColor: const Color(0xFFE8EEF7),
                valueColor: const AlwaysStoppedAnimation(T.blue),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _statusLine(),
                    style: TextStyle(
                        fontSize: 12.5,
                        color: failed ? const Color(0xFFC0392B) : T.textSecondary),
                  ),
                ),
                if (_p.stage == ModelStage.downloading)
                  Text(_speed(_p.bytesPerSec),
                      style: const TextStyle(fontSize: 12.5, color: T.textTertiary)),
              ],
            ),
          ] else if (_resumeFrom > 0) ...[
            const SizedBox(height: 14),
            Text('已下载 ${_mb(_resumeFrom)}，可继续',
                style: const TextStyle(fontSize: 12.5, color: T.textSecondary)),
          ],
        ],
      ),
    );
  }

  String _statusLine() {
    switch (_p.stage) {
      case ModelStage.downloading:
        final pct = (_p.fraction * 100).toStringAsFixed(1);
        final head = _p.total > 0
            ? '$pct%  ${_mb(_p.received)} / ${_mb(_p.total)}'
            : '正在连接…';
        return _p.message == null ? head : '$head · ${_p.message}';
      case ModelStage.verifying:
        return '正在校验文件完整性…';
      case ModelStage.normalizing:
        return '正在准备模型…';
      case ModelStage.ready:
        return '已就绪';
      case ModelStage.failed:
        return _p.message ?? '下载失败';
      case ModelStage.idle:
        return _p.message ?? '';
    }
  }

  Widget _buttons(bool busy) {
    if (busy) {
      return Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _p.stage == ModelStage.downloading ? _cancel : null,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                shape: const StadiumBorder(),
                foregroundColor: T.textSecondary,
              ),
              child: const Text('暂停'),
            ),
          ),
        ],
      );
    }
    return FilledButton(
      onPressed: _start,
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape: const StadiumBorder(),
        backgroundColor: T.blue,
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
      child: Text(_resumeFrom > 0
          ? '继续下载'
          : (_p.stage == ModelStage.failed ? '重试' : '开始下载')),
    );
  }
}
