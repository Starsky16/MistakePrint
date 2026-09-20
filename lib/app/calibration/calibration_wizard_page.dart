import 'dart:async';

import 'package:flutter/material.dart';

import '../../calibration/calibration_figures.dart' show kFontLadder;
import '../../calibration/calibration_strip.dart';
import '../../calibration/calibration_wizard.dart';
import '../../profiles/paper_profile.dart';
import '../../profiles/presets.dart';
import '../../render/offscreen/print_renderer.dart';
import '../../state/profile_controller.dart';
import '../input_page.dart' show kSampleText;
import '../preview_page.dart';

/// 校准向导（计划 §5.8 的交互动线）。
///
/// 只有「生成校准条」与「用新参数出样例」两处需要出图，其余全是点选；每一项都能
/// 跳过，跳过就用默认值。不做强制引导，默认档案本来就能直接出图。
class CalibrationWizardPage extends StatefulWidget {
  const CalibrationWizardPage({
    super.key,
    this.stripRenderer = const CalibrationStripRenderer(),
    this.renderer = const PrintRenderer(),
  });

  /// 校准条出图器，测试注入假实现以免真的跑离屏管线。
  final CalibrationStripRenderer stripRenderer;

  /// 汇总预览用的出图器（同一份出图实现，只是换一组参数）。
  final PrintRenderer renderer;

  @override
  State<CalibrationWizardPage> createState() => _CalibrationWizardPageState();
}

class _CalibrationWizardPageState extends State<CalibrationWizardPage> {
  // 六项答案，null = 跳过。
  int? _width;
  WidthEdgeAnswer? _edge;
  double? _minFontPx;
  ThinLinePreset? _thinLinePreset;
  int? _threshold;
  int? _grayLevels;

  // 出图进度（生成校准条与出样例共用一套）。
  bool _busy = false;
  double _progress = 0;
  String _stage = '';
  String? _error;

  CalibrationStripImage? _strip;
  String? _message;

  CalibrationAnswers get _answers => CalibrationAnswers(
        printableDotsWidth: _width,
        widthEdge: _edge,
        minFontPx: _minFontPx,
        thinLinePreset: _thinLinePreset,
        threshold: _threshold,
        grayLevels: _grayLevels,
      );

  // -------------------------------------------------------------------------
  // 出图
  // -------------------------------------------------------------------------

  Future<void> _generateStrip() async {
    if (_busy) return;
    // profile 必须在 await 之前取，免得跨过异步点再用 context。
    final PaperProfile profile = ProfileScope.of(context).profile;
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
      _progress = 0;
      _stage = '准备';
    });
    try {
      final CalibrationStripImage strip = await widget.stripRenderer.render(
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
      setState(() {
        _busy = false;
        _strip = strip;
      });
      await _openPreview(strip.image);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$error';
      });
    }
  }

  Future<void> _renderSample(PaperProfile derived) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
      _progress = 0;
      _stage = '准备';
    });
    try {
      final PrintImage image = await widget.renderer.render(
        kSampleText,
        derived,
        onProgress: (double progress, String stage) {
          if (!mounted) return;
          setState(() {
            _progress = progress;
            _stage = stage;
          });
        },
      );
      if (!mounted) return;
      setState(() => _busy = false);
      await _openPreview(image);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$error';
      });
    }
  }

  Future<void> _openPreview(PrintImage image) => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (BuildContext context) => PreviewPage(image: image),
        ),
      );

  // -------------------------------------------------------------------------
  // 保存
  // -------------------------------------------------------------------------

  void _save(PaperProfile derived) {
    final ProfileController controller = ProfileScope.of(context);
    setState(() => _message = '已保存到档案，可以直接出图了');
    // 落盘是尽力而为：内存里的档案已经更新，界面不必等它。
    unawaited(controller.update(derived));
  }

  void _reset() {
    final ProfileController controller = ProfileScope.of(context);
    setState(() => _message = '已恢复出厂默认值');
    unawaited(controller.update(kPaperangP1Default));
  }

  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final ProfileController controller = ProfileScope.of(context);
    final PaperProfile current = controller.profile;
    final PaperProfile derived = applyCalibration(current, _answers);
    final List<String> diff = describeProfileDiff(current, derived);
    final CalibrationStripImage? strip = _strip;

    return Scaffold(
      appBar: AppBar(title: const Text('打印校准')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: <Widget>[
          const _PaperNote(),
          _StripSection(
            busy: _busy,
            progress: _progress,
            stage: _stage,
            error: _error,
            strip: strip,
            onGenerate: () => unawaited(_generateStrip()),
            onReopen: strip == null
                ? null
                : () => unawaited(_openPreview(strip.image)),
          ),
          const Divider(),
          _ChoiceTile<int>(
            id: 'width',
            title: '① 有效宽度',
            hint: '校准条右边那条线里，看得见的最外面一个数字是几？',
            options: <(int, String)>[
              for (final int value in kWidthCandidates) (value, '$value'),
            ],
            value: _width,
            onChanged: (int? value) => setState(() => _width = value),
          ),
          _ChoiceTile<WidthEdgeAnswer>(
            id: 'edge',
            title: '② 宽度异常',
            hint: '右边留了白边说明打印 App 把图缩小了，会自动切一下 pHYs。',
            options: <(WidthEdgeAnswer, String)>[
              for (final WidthEdgeAnswer value in WidthEdgeAnswer.values)
                (value, value.label),
            ],
            value: _edge,
            onChanged: (WidthEdgeAnswer? value) => setState(() => _edge = value),
          ),
          _ChoiceTile<double>(
            id: 'font',
            title: '③ 最小可读字号',
            hint: '最小的、仍然看得清的是哪一档？正文会按它取，夹在 '
                '${kBodyFontMinPx.toInt()}~${kBodyFontMaxPx.toInt()} 点之间。',
            options: <(double, String)>[
              for (final double value in kFontLadder) (value, '${value.toInt()}'),
            ],
            value: _minFontPx,
            onChanged: (double? value) => setState(() => _minFontPx = value),
          ),
          _ChoiceTile<ThinLinePreset>(
            id: 'thin',
            title: '④ 细线保真',
            hint: '哪一列的分数线是完整的一条？',
            options: <(ThinLinePreset, String)>[
              for (final ThinLinePreset value in ThinLinePreset.values)
                (value, value.label),
            ],
            value: _thinLinePreset,
            onChanged: (ThinLinePreset? value) =>
                setState(() => _thinLinePreset = value),
          ),
          _ChoiceTile<int>(
            id: 'threshold',
            title: '⑤ 阈值档位',
            hint: '哪一档最清楚？它只覆盖严格阈值，不动上面选的细线档位里的其他参数。',
            options: <(int, String)>[
              for (final int value in kThresholdCandidates) (value, '$value'),
            ],
            value: _threshold,
            onChanged: (int? value) => setState(() => _threshold = value),
          ),
          _ChoiceTile<int>(
            id: 'gray',
            title: '⑥ 灰阶（只作诊断）',
            hint: '能分辨出几档？这一项不改任何参数。',
            options: <(int, String)>[
              for (final int value in kGrayLevelCandidates) (value, '$value'),
            ],
            value: _grayLevels,
            onChanged: (int? value) => setState(() => _grayLevels = value),
          ),
          const Divider(),
          _SummarySection(
            diff: diff,
            grayLevels: _grayLevels,
            busy: _busy,
            onPreviewSample: () => unawaited(_renderSample(derived)),
            onSave: () => _save(derived),
            onReset: _reset,
            message: _message,
          ),
        ],
      ),
    );
  }
}

/// 用纸说明：让用户事先知道要花多少纸（计划 §5.8 的硬指标要写进 UI 文案）。
class _PaperNote extends StatelessWidget {
  const _PaperNote();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Text(
          '用纸：主校准条 1 张（约 200mm），一次打印回答全部问题，'
          '不需要「打了再打」。每一项都能跳过，跳过就用默认值。',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
}

/// 生成校准条 + 进度 + 结果。
class _StripSection extends StatelessWidget {
  const _StripSection({
    required this.busy,
    required this.progress,
    required this.stage,
    required this.error,
    required this.strip,
    required this.onGenerate,
    required this.onReopen,
  });

  final bool busy;
  final double progress;
  final String stage;
  final String? error;
  final CalibrationStripImage? strip;
  final VoidCallback onGenerate;
  final VoidCallback? onReopen;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<String> dropped = strip?.budget.droppedSections ?? const <String>[];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: FilledButton.icon(
                  onPressed: busy ? null : onGenerate,
                  icon: const Icon(Icons.print_outlined),
                  label: Text(busy ? '正在出图…' : '生成校准条并分享'),
                ),
              ),
              if (onReopen != null) ...<Widget>[
                const SizedBox(width: 8),
                OutlinedButton(onPressed: onReopen, child: const Text('再看一次')),
              ],
            ],
          ),
          if (busy) ...<Widget>[
            const SizedBox(height: 8),
            LinearProgressIndicator(value: progress == 0 ? null : progress),
            const SizedBox(height: 4),
            Text('${(progress * 100).round()}% · $stage',
                style: theme.textTheme.bodySmall),
          ] else if (error != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(error!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error)),
          ] else if (strip != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              '校准条 ${strip!.image.width} × ${strip!.image.height} 点已生成，'
              '在预览页分享打印。',
              style: theme.textTheme.bodySmall,
            ),
            if (dropped.isNotEmpty)
              Text(
                '纸长所限这一版省掉了：${dropped.join('、')}；这几项留用原值。',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error),
              ),
          ],
        ],
      ),
    );
  }
}

/// 一个校准项：标题 + 提示 + 一排候选（含「跳过」）。
class _ChoiceTile<T> extends StatelessWidget {
  const _ChoiceTile({
    required this.id,
    required this.title,
    required this.hint,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  /// 用于给每个候选做稳定的 key，测试按 key 点选。
  final String id;

  final String title;
  final String hint;
  final List<(T, String)> options;
  final T? value;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: theme.textTheme.titleSmall),
          const SizedBox(height: 2),
          Text(hint, style: theme.textTheme.bodySmall),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: <Widget>[
              for (final (T option, String label) in options)
                ChoiceChip(
                  key: ValueKey<String>('cal-$id-$label'),
                  label: Text(label),
                  selected: value == option,
                  // 再点一次已选中的就回到「跳过」，与点「跳过」等价。
                  onSelected: (bool selected) =>
                      onChanged(selected ? option : null),
                ),
              ChoiceChip(
                key: ValueKey<String>('cal-$id-skip'),
                label: const Text('跳过'),
                selected: value == null,
                onSelected: (bool selected) {
                  if (selected) onChanged(null);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 汇总预览：用新参数渲染一段样例让用户确认，然后保存。
class _SummarySection extends StatelessWidget {
  const _SummarySection({
    required this.diff,
    required this.grayLevels,
    required this.busy,
    required this.onPreviewSample,
    required this.onSave,
    required this.onReset,
    required this.message,
  });

  final List<String> diff;
  final int? grayLevels;
  final bool busy;
  final VoidCallback onPreviewSample;
  final VoidCallback onSave;
  final VoidCallback onReset;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('汇总预览', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          if (diff.isEmpty)
            Text(
              '所有项都跳过了：档案保持原样，用默认值照样能出图。',
              style: theme.textTheme.bodySmall,
            )
          else
            for (final String line in diff)
              Text('· $line', style: theme.textTheme.bodySmall),
          if (grayLevels != null) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              '灰阶只作诊断：能分辨 $grayLevels 档，不影响参数。',
              style: theme.textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: busy ? null : onPreviewSample,
            icon: const Icon(Icons.visibility_outlined),
            label: const Text('用新参数出一张样例'),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onSave,
              child: const Text('保存到档案'),
            ),
          ),
          TextButton(onPressed: onReset, child: const Text('重置为出厂默认值')),
          if (message != null) ...<Widget>[
            const SizedBox(height: 4),
            Text(message!, style: theme.textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}