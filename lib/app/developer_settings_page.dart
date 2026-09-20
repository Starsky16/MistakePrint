import 'dart:async';

import 'package:flutter/material.dart';

import '../profiles/paper_profile.dart';
import '../profiles/presets.dart';
import '../state/profile_controller.dart';

/// 开发者模式：直接改裸参数（计划 §5.8）。
///
/// 入口在设置页连点版本号 7 次。这里只做「把某个字段改成某个值」这一件事，
/// 档位判定交给 [detectThinLinePreset] —— 改完对不上任何档位就显示「自定义」。
class DeveloperSettingsPage extends StatelessWidget {
  const DeveloperSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final ProfileController controller = ProfileScope.of(context);
    final PaperProfile profile = controller.profile;
    final ThinLinePreset? preset = controller.thinLinePreset;

    void apply(PaperProfile next) => unawaited(controller.update(next));

    return Scaffold(
      appBar: AppBar(
        title: const Text('开发者模式'),
        actions: <Widget>[
          IconButton(
            onPressed: () => unawaited(controller.resetToDefault()),
            icon: const Icon(Icons.restart_alt),
            tooltip: '重置为默认值',
          ),
        ],
      ),
      body: ListView(
        children: <Widget>[
          ListTile(
            title: const Text('当前档位'),
            subtitle: Text(preset?.label ?? '自定义'),
          ),
          ListTile(
            title: const Text('档案'),
            subtitle: Text('${profile.id} · ${profile.name}'),
          ),
          const Divider(),
          _SectionHeader('版式'),
          _ParamSlider(
            label: '点阵宽度',
            unit: '点',
            value: profile.printableDotsWidth.toDouble(),
            min: 300,
            max: 420,
            divisions: 120,
            onChanged: (double v) =>
                apply(profile.copyWith(printableDotsWidth: v.round())),
          ),
          _ParamSlider(
            label: '最小可读字号',
            unit: '点',
            value: profile.minFontPx,
            min: 12,
            max: 32,
            divisions: 20,
            onChanged: (double v) => apply(profile.copyWith(
              minFontPx: v,
              // 正文不得小于最小可读字号，否则版式会突破校准得出的下限。
              bodyFontPx: profile.bodyFontPx < v ? v : profile.bodyFontPx,
            )),
          ),
          _ParamSlider(
            label: '正文字号',
            unit: '点',
            value: profile.bodyFontPx,
            min: 12,
            max: 40,
            divisions: 28,
            onChanged: (double v) => apply(profile.copyWith(bodyFontPx: v)),
          ),
          _ParamSlider(
            label: '公式字号',
            unit: '点',
            value: profile.mathFontPx,
            min: 16,
            max: 40,
            divisions: 24,
            onChanged: (double v) => apply(profile.copyWith(mathFontPx: v)),
          ),
          _ParamSlider(
            label: '行高倍数',
            value: profile.lineHeight,
            min: 1,
            max: 2,
            divisions: 20,
            decimals: 2,
            onChanged: (double v) => apply(profile.copyWith(lineHeight: v)),
          ),
          const Divider(),
          _SectionHeader('二值化'),
          _ParamSlider(
            label: '严格阈值',
            value: profile.threshold.toDouble(),
            min: 1,
            max: 254,
            divisions: 253,
            onChanged: (double v) =>
                apply(profile.copyWith(threshold: v.round())),
          ),
          SwitchListTile(
            title: const Text('水平长游程结构线保护'),
            subtitle: const Text('救回被抗锯齿抹掉的分数线与根号横线'),
            value: profile.protectStructureLines,
            onChanged: (bool value) =>
                apply(profile.copyWith(protectStructureLines: value)),
          ),
          if (profile.protectStructureLines)
            _ParamSlider(
              label: '结构线最小游程',
              unit: '点',
              value: profile.structureRunLength.toDouble(),
              min: 2,
              max: 32,
              divisions: 30,
              onChanged: (double v) =>
                  apply(profile.copyWith(structureRunLength: v.round())),
            ),
          _ParamSlider(
            label: '最小线宽',
            unit: '点',
            value: profile.minLineWidthPx.toDouble(),
            min: 1,
            max: 4,
            divisions: 3,
            onChanged: (double v) =>
                apply(profile.copyWith(minLineWidthPx: v.round())),
          ),
          const Divider(),
          _SectionHeader('输出'),
          SwitchListTile(
            title: const Text('写入 pHYs（打印机分辨率）'),
            value: profile.writePhys,
            onChanged: (bool value) =>
                apply(profile.copyWith(writePhys: value)),
          ),
          ListTile(
            title: const Text('超宽公式策略'),
            subtitle: Text(
              profile.oversizeStrategy == OversizeStrategy.lineBreak
                  ? '先按 TeX 规则断行，仍超宽才整体缩放'
                  : '不尝试断行，直接整体缩放',
            ),
            trailing: DropdownButton<OversizeStrategy>(
              value: profile.oversizeStrategy,
              onChanged: (OversizeStrategy? value) {
                if (value == null) return;
                apply(profile.copyWith(oversizeStrategy: value));
              },
              items: <DropdownMenuItem<OversizeStrategy>>[
                for (final OversizeStrategy value in OversizeStrategy.values)
                  DropdownMenuItem<OversizeStrategy>(
                    value: value,
                    child: Text(value.name),
                  ),
              ],
            ),
          ),
          const Divider(),
          _SectionHeader('校准状态'),
          SwitchListTile(
            title: const Text('标记为已校准'),
            subtitle: const Text('关掉会让首页重新出现「还没校准」提示条'),
            value: profile.isCalibrated,
            onChanged: (bool value) =>
                apply(profile.copyWith(isCalibrated: value)),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
              ),
        ),
      );
}

/// 一行「标签 + 当前值 + 滑杆」。
///
/// 拖动期间只更新本地显示值，松手（[Slider.onChangeEnd]）才写回档案 —— 否则一次
/// 拖动会往存档里写几十次。
class _ParamSlider extends StatefulWidget {
  const _ParamSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
    this.unit = '',
    this.decimals = 0,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;
  final String unit;
  final int decimals;

  @override
  State<_ParamSlider> createState() => _ParamSliderState();
}

class _ParamSliderState extends State<_ParamSlider> {
  double? _dragging;

  String _display(double value) =>
      '${value.toStringAsFixed(widget.decimals)}${widget.unit}';

  @override
  Widget build(BuildContext context) {
    // 档案被改到滑杆量程之外时（例如别的档案写的值）夹回量程，滑杆才画得出来。
    final double value = (_dragging ?? widget.value).clamp(widget.min, widget.max);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: Text(widget.label)),
              Text(_display(value), style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
          Slider(
            // 参数名当 key：页面测试靠它精确定位到某个参数，不依赖控件顺序。
            key: ValueKey<String>('dev-param-${widget.label}'),
            value: value,
            min: widget.min,
            max: widget.max,
            divisions: widget.divisions,
            label: _display(value),
            onChanged: (double v) => setState(() => _dragging = v),
            onChangeEnd: (double v) {
              setState(() => _dragging = null);
              widget.onChanged(v);
            },
          ),
        ],
      ),
    );
  }
}