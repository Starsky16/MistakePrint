import 'dart:async';

import 'package:flutter/material.dart';

import '../profiles/paper_profile.dart';
import '../profiles/presets.dart';
import '../render/raster/binarize.dart';
import '../state/profile_controller.dart';
import 'app_version.dart';
import 'developer_settings_page.dart';

/// 设置页（Q14：这里只出现档位，裸参数进开发者模式）。
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final ProfileController controller = ProfileScope.of(context);
    final PaperProfile profile = controller.profile;
    final ThinLinePreset? preset = controller.thinLinePreset;

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: <Widget>[
          const _SectionHeader('细线增强'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<ThinLinePreset>(
              segments: <ButtonSegment<ThinLinePreset>>[
                for (final ThinLinePreset value in ThinLinePreset.values)
                  ButtonSegment<ThinLinePreset>(
                    value: value,
                    label: Text(value.label),
                  ),
              ],
              selected: <ThinLinePreset>{?preset},
              // 裸参数被开发者改过时不属于任何档位，允许空选才是诚实的显示。
              emptySelectionAllowed: true,
              onSelectionChanged: (Set<ThinLinePreset> selection) {
                if (selection.isEmpty) return;
                unawaited(controller.setThinLinePreset(selection.first));
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Text(
              _presetExplanation(preset),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const Divider(),
          const _SectionHeader('输出'),
          ListTile(
            title: const Text('点阵宽度'),
            subtitle: Text(
              '${profile.printableDotsWidth} 点 · '
              '${profile.isCalibrated ? '已校准' : '默认值，尚未校准'}',
            ),
          ),
          SwitchListTile(
            title: const Text('写入打印机分辨率元数据'),
            subtitle: const Text('打出来偏大或偏小就切一下这一项（影响 PNG 的 pHYs 块）'),
            value: profile.writePhys,
            onChanged: (bool value) => unawaited(
              controller.update(profile.copyWith(writePhys: value)),
            ),
          ),
          const Divider(),
          const _SectionHeader('关于'),
          const _AboutTile(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  /// 档位说明：让用户在设置页里就能明白档位之间差在哪，不必去翻开发者模式。
  static String _presetExplanation(ThinLinePreset? preset) {
    switch (preset) {
      case ThinLinePreset.off:
        return '不做结构线保护：整张图最干净，但分数线的横线可能被二值化抹掉。';
      case ThinLinePreset.standard:
        return '严格阈值 + 长水平游程保护：救回被抗锯齿抹掉的分数线，'
            '全图墨量约 +4%（出厂默认）。';
      case ThinLinePreset.aggressive:
        return '再把严格阈值抬到 $kAggressiveThreshold：连细竖画一起救回'
            '（如 \$\\frac{x}{2}+\\frac{1}{x}\$ 的加号），代价是全图墨量约 +29%，'
            '小字内白可能糊。';
      case null:
        return '当前参数由开发者模式自定义，不属于任何一个档位。';
    }
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
              ),
        ),
      );
}

/// 版本号一行；连点 7 次进开发者模式（计划 §5.8 的入口约定）。
class _AboutTile extends StatefulWidget {
  const _AboutTile();

  static const int kTapsToUnlock = 7;

  @override
  State<_AboutTile> createState() => _AboutTileState();
}

class _AboutTileState extends State<_AboutTile> {
  int _taps = 0;

  void _onTap() {
    _taps++;
    if (_taps >= _AboutTile.kTapsToUnlock) {
      _taps = 0;
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (BuildContext context) => const DeveloperSettingsPage(),
        ),
      );
      return;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) => ListTile(
        onTap: _onTap,
        title: const Text(kAppName),
        subtitle: Text(
          _taps < 3
              ? '版本 $kAppVersion'
              : '版本 $kAppVersion · 再点 ${_AboutTile.kTapsToUnlock - _taps} 次进入开发者模式',
        ),
      );
}