import 'dart:async';

import 'package:flutter/material.dart';

import '../domain/input_preprocess.dart';
import '../profiles/paper_profile.dart';
import '../render/offscreen/offscreen_canvas.dart';
import '../render/offscreen/print_renderer.dart';
import '../state/app_prefs.dart';
import '../state/profile_controller.dart';
import 'app_version.dart';
import 'preview_page.dart';
import 'settings_page.dart';

/// 出错时展示给用户的兜底样例（点一下就能出图，省得对着空输入框发呆）。
const String kSampleText =
    r'错题 1：已知 △ABC ≌ △DEF，∠A = 30°，AB // DE。'
    r'求 $\frac{AB}{DE}$ 的值。';

/// 首页：粘贴题干 → 出图 → 进预览页分享。
///
/// 计划 §5.8「不做强制引导」：首页不弹向导，用默认参数就能直接出图；只在没校准过
/// 的时候挂一条可永久关掉的提示条，把向导放在设置里等人来。
class InputPage extends StatefulWidget {
  const InputPage({
    super.key,
    this.renderer = const PrintRenderer(),
    this.prefsStore = const AppPrefsStore(),
  });

  /// 出图器，测试注入假实现以免真的跑离屏渲染。
  final PrintRenderer renderer;

  final AppPrefsStore prefsStore;

  @override
  State<InputPage> createState() => _InputPageState();
}

class _InputPageState extends State<InputPage> {
  final TextEditingController _text = TextEditingController();

  bool _rendering = false;
  double _progress = 0;
  String _stage = '';
  String? _error;

  /// 界面偏好：提示条开关与输出模式，改哪一项都整份写回。
  AppPrefs _prefs = const AppPrefs();

  /// 输入框里是否有内容（只关心「空↔非空」这一次翻转，不必每次按键都重建）。
  bool _hasText = false;

  /// 预处理小结（「识别到 N 处公式」）。只在文字真的变了时才重建页面。
  String _summary = '';

  @override
  void initState() {
    super.initState();
    _text.addListener(_refreshSummary);
    unawaited(_loadPrefs());
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  /// 重算预处理小结；小结文字没变就不重建。
  void _refreshSummary() {
    final String text = _text.text.trim();
    final bool hasText = text.isNotEmpty;
    final String summary = hasText
        ? preprocess(text, mode: _prefs.outputMode).report.summaryLine
        : '';
    if (hasText == _hasText && summary == _summary) return;
    setState(() {
      _hasText = hasText;
      _summary = summary;
    });
  }

  Future<void> _loadPrefs() async {
    final AppPrefs prefs = await widget.prefsStore.load();
    if (!mounted) return;
    setState(() => _prefs = prefs);
    _refreshSummary();
  }

  /// 偏好只有一个来源：本页。
  Future<void> _savePrefs(AppPrefs next) async {
    setState(() => _prefs = next);
    await widget.prefsStore.save(next);
  }

  Future<void> _dismissHint() =>
      _savePrefs(_prefs.copyWith(calibrationHintDismissed: true));

  Future<void> _setMode(OutputMode mode) async {
    if (mode == _prefs.outputMode) return;
    await _savePrefs(_prefs.copyWith(outputMode: mode));
    _refreshSummary();
  }

  Future<void> _render() async {
    final String text = _text.text.trim();
    if (text.isEmpty || _rendering) return;

    final PaperProfile profile = ProfileScope.of(context).profile;
    // 预处理层是「粘贴原文」与「分词器」之间唯一的一道转换，出图前先过它。
    final PreprocessResult prepared = preprocess(text, mode: _prefs.outputMode);
    setState(() {
      _rendering = true;
      _error = null;
      _progress = 0;
      _stage = '准备';
    });

    try {
      final PrintImage image = await widget.renderer.render(
        prepared.text,
        profile,
        onProgress: (double progress, String stage) {
          if (!mounted) return;
          setState(() {
            _progress = progress;
            _stage = stage;
          });
        },
      );
      if (!mounted) return;
      setState(() => _rendering = false);
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (BuildContext context) => PreviewPage(
            image: image,
            notices: prepared.report.notices,
          ),
        ),
      );
    } on OffscreenRenderException catch (error) {
      _fail(error.message);
    } catch (error) {
      _fail('$error');
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _rendering = false;
      _error = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final ProfileController controller = ProfileScope.of(context);
    final PaperProfile profile = controller.profile;
    final bool showHint =
        !profile.isCalibrated && !_prefs.calibrationHintDismissed;

    return Scaffold(
      appBar: AppBar(
        title: const Text(kAppName),
        actions: <Widget>[
          IconButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (BuildContext context) => const SettingsPage(),
              ),
            ),
            icon: const Icon(Icons.settings_outlined),
            tooltip: '设置',
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          if (showHint)
            _CalibrationHint(
              onDismiss: () => unawaited(_dismissHint()),
              onOpenSettings: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (BuildContext context) => const SettingsPage(),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: SegmentedButton<OutputMode>(
              segments: OutputMode.values
                  .map(
                    (OutputMode mode) => ButtonSegment<OutputMode>(
                      value: mode,
                      label: Text(mode.label),
                    ),
                  )
                  .toList(),
              selected: <OutputMode>{_prefs.outputMode},
              showSelectedIcon: false,
              onSelectionChanged: (Set<OutputMode> selection) =>
                  unawaited(_setMode(selection.first)),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: TextField(
                controller: _text,
                // 题干是多行的，输入框撑满剩余空间比给个固定高度好用。
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                keyboardType: TextInputType.multiline,
                enabled: !_rendering,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  alignLabelWithHint: true,
                  labelText: '题干（直接粘贴 AI 解答即可，裸 LaTeX 会自动识别）',
                  hintText: kSampleText,
                  suffixIcon: IconButton(
                    onPressed:
                        _rendering ? null : () => _text.text = kSampleText,
                    icon: const Icon(Icons.auto_awesome_outlined),
                    tooltip: '填入样例',
                  ),
                ),
              ),
            ),
          ),
          _StatusPanel(
            rendering: _rendering,
            progress: _progress,
            stage: _stage,
            error: _error,
            summary: _summary,
            widthDots: profile.printableDotsWidth,
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _rendering || !_hasText
                      ? null
                      : () => unawaited(_render()),
                  icon: const Icon(Icons.print_outlined),
                  label: Text(_rendering ? '正在出图…' : '生成图片'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 未校准提示条（可永久关闭）。
class _CalibrationHint extends StatelessWidget {
  const _CalibrationHint({required this.onDismiss, required this.onOpenSettings});

  final VoidCallback onDismiss;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(
          children: <Widget>[
            Icon(Icons.info_outline, size: 20, color: colors.onSecondaryContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '当前用的是默认参数。打一张校准条就能把宽度、字号、细线调到这台机器上最好的状态。',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: colors.onSecondaryContainer),
              ),
            ),
            TextButton(onPressed: onOpenSettings, child: const Text('去设置')),
            IconButton(
              onPressed: onDismiss,
              icon: const Icon(Icons.close, size: 18),
              tooltip: '不再提示',
            ),
          ],
        ),
      ),
    );
  }
}

/// 出图进度 / 错误 / 预处理小结 / 当前宽度。
class _StatusPanel extends StatelessWidget {
  const _StatusPanel({
    required this.rendering,
    required this.progress,
    required this.stage,
    required this.error,
    required this.summary,
    required this.widthDots,
  });

  final bool rendering;
  final double progress;
  final String stage;
  final String? error;

  /// 预处理小结，空串表示还没输入内容。
  final String summary;

  final int widthDots;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (rendering) ...<Widget>[
            LinearProgressIndicator(value: progress == 0 ? null : progress),
            const SizedBox(height: 4),
            Text(
              '${(progress * 100).round()}% · $stage',
              style: theme.textTheme.bodySmall,
            ),
          ] else if (error != null)
            Row(
              children: <Widget>[
                Icon(Icons.error_outline, size: 18, color: theme.colorScheme.error),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    error!,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.error),
                  ),
                ),
              ],
            )
          else ...<Widget>[
            if (summary.isNotEmpty)
              Text(summary, style: theme.textTheme.bodySmall),
            Text(
              '输出宽度 $widthDots 点（1:1，不做缩放）',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}