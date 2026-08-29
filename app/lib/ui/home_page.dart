/// 主界面。按设计稿实现: hero 头图 + 语言胶囊 + 输入/译文卡片 + 底部操作区 + 导航栏。
///
/// 未实现的功能 (语音、朗读、拍照、对话、收藏、历史) 保留完整的视觉位置,
/// 点击统一提示「暂时未开放」—— 不做假功能, 也不留空洞。
library;

import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_settings.dart';
import '../core/engine.dart';
import '../core/history_store.dart';
import '../core/model_manager.dart';
import '../core/langs.dart';
import '../core/segmenter.dart';
import '../core/telemetry.dart';
import '../core/translation_cache.dart';
import 'cards.dart';
import 'hero_image.dart';
import 'settings_page.dart';
import 'sheets.dart';
import 'theme.dart';
import 'widgets.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.modelPath,
    required this.reuse,
    required this.manager,
    required this.onModelDeleted,
  });

  /// null 表示还没找到模型文件
  final String? modelPath;

  /// 从历史/收藏里点某条时, 外壳通过它把内容送进来
  final ValueNotifier<TranslationRecord?> reuse;

  final ModelManager manager;
  final VoidCallback onModelDeleted;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final _input = TextEditingController();
  final _engine = TranslateEngine.instance;
  final _cache = TranslationCache.instance;

  late final AnimationController _wave = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat();

  Lang _from = Lang.ug;
  Lang _to = Lang.zh;

  /// 上一次完成的译文。**新一轮翻译期间不清空** —— 用户改个字就白屏是最烦的。
  String _output = '';

  /// 本轮正在产出的译文。非空时优先显示它, 这样从旧结果切到新结果没有空白闪烁。
  String _pending = '';

  /// 当前显示的译文对应的原文, 用于全屏面板里的原文对照
  String _outputSource = '';

  bool _busy = false;
  bool _favorited = false;
  String? _error;
  Timer? _debounce;
  int _runId = 0;

  /// 后台待机计时器。见 didChangeAppLifecycleState 的说明。
  Timer? _idleUnload;


  String get _shown => _pending.isNotEmpty ? _pending : _output;

  /// 有旧结果、且新一轮还没产出任何内容时, 卡片压淡表示"正在更新"
  bool get _stale => _busy && _pending.isEmpty && _output.isNotEmpty;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _input.addListener(_onInputChanged);
    widget.reuse.addListener(_applyReuse);
    _boot();
  }

  /// 从历史/收藏点进来的一条: 恢复语言方向和原文, 译文直接用记录里的,
  /// 不重新跑推理 —— 用户想看的是当时那条结果。
  void _applyReuse() {
    final r = widget.reuse.value;
    if (r == null) return;
    widget.reuse.value = null;
    _debounce?.cancel();
    _engine.stop();
    setState(() {
      _from = r.from;
      _to = r.to;
      _output = r.translation;
      _pending = '';
      _outputSource = r.source;
      _busy = false;
      _favorited = r.favorited;
      _error = null;
    });
    // 直接改 text 会触发 listener 重译, 所以用 value 并手动跳过这一次防抖
    _input.removeListener(_onInputChanged);
    _input.text = r.source;
    _input.addListener(_onInputChanged);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.reuse.removeListener(_applyReuse);
    _idleUnload?.cancel();
    _debounce?.cancel();
    _input.dispose();
    _wave.dispose();
    _cache.flush();
    super.dispose();
  }

  Future<void> _boot() async {
    final path = widget.modelPath;
    if (path == null) {
      setState(() => _error = '未找到模型文件');
      return;
    }
    try {
      await _engine.load(path);
      if (mounted) setState(() => _error = null);
    } on EngineException catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  // ── 翻译流程 ──────────────────────────────────────────────
  //
  // 设计稿里没有「翻译」按钮, 所以走输入停顿后自动翻译。
  // 900ms 的防抖是权衡出来的: CPU 推理一句要 1.6~5s, 抖动太短会白跑很多次;
  // 新输入到来时用 engine 的 cancel 掐掉上一次, 不浪费算力。

  void _onInputChanged() {
    _debounce?.cancel();
    if (_input.text.trim().isEmpty) {
      _engine.stop();
      setState(() {
        _output = '';
        _pending = '';
        _outputSource = '';
        _busy = false;
        _favorited = false;
        _error = null;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 900), _translate);
  }

  Future<void> _translate() async {
    final raw = _input.text.trim();
    if (raw.isEmpty) return;
    // 引擎可能因为后台待机或内存压力被卸掉了, 这里按需重新加载
    if (!_engine.isLoaded && !await _ensureEngine()) return;
    if (!mounted) return;

    if (hasUnsupportedCyrillic(raw)) {
      setState(() {
        _busy = false;
        _error = '请使用阿拉伯字母的哈萨克文（不支持西里尔字母）';
      });
      return;
    }

    final segments = splitForTranslation(raw);

    // 整段全部命中缓存 → 直接出结果, 一次推理都不跑
    final cachedAll = <String>[];
    for (final seg in segments) {
      final hit = _cache.get(_from, _to, seg);
      if (hit == null) break;
      cachedAll.add(hit);
    }
    if (cachedAll.length == segments.length) {
      final result = cachedAll.join(' ');
      Telemetry.instance.recordTranslation();
      _remember(raw, result);
      setState(() {
        _output = result;
        _pending = '';
        _outputSource = raw;
        _busy = false;
        _error = null;
        _favorited = HistoryStore.instance.isFavorited(_from, _to, raw);
      });
      return;
    }

    _engine.stop(); // 掐掉上一次未完成的生成
    final id = ++_runId;
    setState(() {
      _busy = true;
      _pending = '';
      _error = null;
      _favorited = false;
    });

    final done = <String>[];
    try {
      for (final seg in segments) {
        // 句子级缓存: 用户在长文末尾加字时, 前面的句子全部秒出
        final hit = _cache.get(_from, _to, seg);
        if (hit != null) {
          done.add(hit);
          if (id != _runId || !mounted) return;
          setState(() => _pending = done.join(' '));
          continue;
        }

        final buf = StringBuffer();
        final content = buildUserContent(from: _from, to: _to, text: seg);
        await for (final chunk in _engine.translate(content,
            official: AppSettings.instance.officialSampling)) {
          if (id != _runId || !mounted) return; // 已被新一轮取代
          buf.write(chunk);
          setState(() =>
              _pending = [...done, tidyTranslation(buf.toString())].join(' '));
        }
        if (id != _runId || !mounted) return;
        final segResult = tidyTranslation(buf.toString());
        _cache.put(_from, _to, seg, segResult);
        done.add(segResult);
        setState(() => _pending = done.join(' '));
      }
      if (id == _runId && mounted) {
        final result = done.join(' ');
        Telemetry.instance.recordTranslation();
        _remember(raw, result);
        setState(() {
          _output = result;
          _pending = '';
          _outputSource = raw;
          _favorited = HistoryStore.instance.isFavorited(_from, _to, raw);
        });
      }
    } on EngineException catch (e) {
      if (id == _runId && mounted) setState(() => _error = '$e');
    } finally {
      if (id == _runId && mounted) setState(() => _busy = false);
    }
  }

  // ── 内存与生命周期 ────────────────────────────────────────
  //
  // 实测峰值 RSS 569MB (440MB 权重 mmap + KV cache + 运行时)。这个量级在
  // 4GB 内存的机器上, 切到后台之后被 Android LMK 干掉几乎是必然的 —— 与其
  // 让系统在任意时刻强杀 (回来时是冷启动、Activity 重建、体感很差),
  // 不如自己主动让出内存: 后台待够一段时间就卸掉引擎, 回前台再按需重新加载。
  //
  // mmap 加载实测只要 ~550ms, 所以这个来回对用户几乎无感, 却能大幅降低
  // 「切出去看条微信回来 App 重启了」的概率。

  /// 后台待机多久之后卸掉引擎。
  ///
  /// 取 8 秒而不是几分钟, 是因为 Android 14+ 的 cached app freezer 会在进程进入
  /// cached 状态后不久 SIGSTOP 它, 被冻结之后 Dart 的 Timer 根本不会触发 ——
  /// 定时器设得越长, 越可能永远等不到执行, 整个让出内存的机制就形同虚设。
  /// 反过来重新加载只要 ~550ms (mmap), 代价很小, 所以宁可早卸。
  static const _unloadAfter = Duration(seconds: 8);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _idleUnload?.cancel();
        _idleUnload = null;
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        // 顺便把缓存和历史落盘 —— 进程随时可能被杀, 不能等 2 秒防抖
        _cache.flush();
        HistoryStore.instance.flush();
        Telemetry.instance.onPause();
        _idleUnload?.cancel();
        _idleUnload = Timer(_unloadAfter, _unloadEngine);
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  /// 系统报告内存压力时立刻让出 —— 这时候不主动放, 就是被动被杀。
  @override
  void didHaveMemoryPressure() {
    _cache.flush();
    HistoryStore.instance.flush();
    _unloadEngine();
  }

  Future<void> _unloadEngine() async {
    // 正在生成时不动它, 否则用户会看到翻译无声无息地断掉
    if (_busy || !_engine.isLoaded) return;
    developer.log('后台待机, 卸载引擎让出内存', name: 'tilmach.lifecycle');
    await _engine.dispose();
  }

  /// 翻译前确保引擎可用。返回 false 表示加载失败, 错误已写进 _error。
  Future<bool> _ensureEngine() async {
    if (_engine.isLoaded) return true;
    final path = widget.modelPath;
    if (path == null) {
      setState(() => _error = '未找到模型文件');
      return false;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _engine.load(path);
      return true;
    } on EngineException catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _busy = false;
        });
      }
      return false;
    }
  }

  void _remember(String source, String translation) {
    if (!AppSettings.instance.keepHistory) return;
    HistoryStore.instance
        .record(from: _from, to: _to, source: source, translation: translation);
  }

  void _toggleFavorite() {
    final src = _outputSource.isEmpty ? _input.text.trim() : _outputSource;
    if (src.isEmpty || _shown.isEmpty) return;
    final now = HistoryStore.instance.toggleFavorite(
      from: _from,
      to: _to,
      source: src,
      translation: _shown,
    );
    setState(() => _favorited = now);
    final m = ScaffoldMessenger.of(context);
    m.hideCurrentSnackBar();
    m.showSnackBar(SnackBar(
      content: Text(now ? '已收藏' : '已取消收藏'),
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.fromLTRB(110, 0, 110, 96),
      backgroundColor: const Color(0xE6202733),
      shape: const StadiumBorder(),
      duration: const Duration(milliseconds: 1200),
    ));
  }

  void _openSettings() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SettingsPage(
        manager: widget.manager,
        onModelDeleted: widget.onModelDeleted,
      ),
    ));
  }

  void _swap() {
    setState(() {
      final t = _from;
      _from = _to;
      _to = t;
      // 把译文搬到输入框, 这是双向翻译最顺的交互
      final cur = _shown;
      if (cur.isNotEmpty) {
        _output = '';
        _pending = '';
        _outputSource = '';
        _input.text = cur; // 会触发 listener 自动重译
      }
    });
  }

  // ── 3D 面板 ──────────────────────────────────────────────

  Future<void> _openEditor() async {
    await Navigator.of(context).push(route3d(
      InputEditorSheet(lang: _from, controller: _input),
      origin: Alignment.bottomCenter,
    ));
    if (!mounted) return;
    // 关掉输入面板时若译文已经长到卡片装不下, 直接把全文面板翻上来
    if (_shown.characters.length > 110) _openViewer();
  }

  void _openViewer() {
    if (_shown.isEmpty) return;
    Navigator.of(context).push(route3d(
      ResultViewerSheet(
        lang: _to,
        text: _shown,
        sourceText: _outputSource.isEmpty ? _input.text.trim() : _outputSource,
        sourceLang: _from,
      ),
      origin: Alignment.topCenter,
    ));
  }

  // ── 构建 ────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(
            children: [
              _hero(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 26),
                child: LangSwitcher(
                  from: _from,
                  to: _to,
                  enabled: true,
                  onPickFrom: (l) => setState(() => _from = l),
                  onPickTo: (l) {
                    setState(() => _to = l);
                    if (_input.text.trim().isNotEmpty) _translate();
                  },
                  onSwap: _swap,
                ),
              ),
              const SizedBox(height: 14),
              Expanded(
                flex: 4,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: InputCard(
                    lang: _from,
                    controller: _input,
                    onClear: _input.clear,
                    onSpeak: () => showNotYet(context, '朗读'),
                    onTapEdit: _openEditor,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Expanded(
                flex: 5,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: OutputCard(
                    lang: _to,
                    text: _shown,
                    busy: _busy,
                    stale: _stale,
                    favorited: _favorited,
                    onFavorite: _toggleFavorite,
                    onCopy: _copy,
                    onSpeak: () => showNotYet(context, '朗读'),
                    onTapExpand: _openViewer,
                  ),
                ),
              ),
          if (_error != null) _errorBar(),
          _actionRow(),
        ],
      ),
    );
  }

  void _copy() {
    if (_shown.isEmpty) return;
    Clipboard.setData(ClipboardData(text: _shown));
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

  Widget _errorBar() {
    return Padding(
      padding: const EdgeInsets.only(top: 8, left: 22, right: 22),
      child: Text(
        _error!,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 12.5, color: Color(0xFFC0392B)),
      ),
    );
  }

  /// 顶部 hero: 左侧标题, 右侧建筑图渗进背景渐变
  Widget _hero() {
    return SizedBox(
      height: 168,
      child: Stack(
        children: [
          Positioned(
            right: 0,
            left: MediaQuery.sizeOf(context).width * 0.18,
            top: 6,
            bottom: 0,
            child: const HeroImage(fade: HeroFade.header),
          ),
          // 图片底部融进背景, 避免出现硬边
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 44,
            child: IgnorePointer(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x00EDF4FC), Color(0xFFEDF4FC)],
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(26, 22, 18, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('翻译',
                        style: TextStyle(
                            fontSize: 34,
                            fontWeight: FontWeight.w700,
                            height: 1.1,
                            color: T.textPrimary)),
                    const SizedBox(height: 8),
                    Text('科技连接世界 · 语言沟通未来',
                        style: TextStyle(
                            fontSize: 13,
                            color: T.textSecondary.withValues(alpha: 0.95))),
                  ],
                ),
                const Spacer(),
                HexButton(onTap: _openSettings),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 底部操作区: 拍照 / 语音主按钮 / 输入。
  /// 语音和拍照都还没实现, 但保留设计稿的完整视觉重量。
  Widget _actionRow() {
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(width: 18),
          RoundActionButton(
            icon: Icons.photo_camera_outlined,
            label: '拍照翻译',
            dimmed: true,
            onTap: () => showNotYet(context, '拍照翻译'),
          ),
          Expanded(
            child: AnimatedBuilder(
              animation: _wave,
              builder: (_, _) => WaveBars(progress: _wave.value),
            ),
          ),
          _micButton(),
          Expanded(
            child: AnimatedBuilder(
              animation: _wave,
              builder: (_, _) => WaveBars(progress: _wave.value, reversed: true),
            ),
          ),
          RoundActionButton(
            icon: Icons.keyboard_alt_outlined,
            label: '输入翻译',
            onTap: _openEditor,
          ),
          const SizedBox(width: 18),
        ],
      ),
    );
  }

  Widget _micButton() {
    return GestureDetector(
      onTap: () => showNotYet(context, '语音翻译'),
      child: Column(
        children: [
          Container(
            width: 74,
            height: 74,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF4B85F5), T.blueDeep],
              ),
              boxShadow: T.shadowButton,
            ),
            child: const Icon(Icons.mic_none_rounded, size: 34, color: Colors.white),
          ),
          const SizedBox(height: 8),
          const Text('点击语音翻译',
              style: TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w500, color: T.blue)),
        ],
      ),
    );
  }

}
