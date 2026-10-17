import 'dart:async';

import 'package:flutter/material.dart';

import '../profiles/paper_profile.dart';
import '../profiles/presets.dart';
import '../render/raster/binarize.dart';
import '../share/gallery_store.dart';
import '../state/profile_controller.dart';
import 'app_version.dart';
import 'developer_settings_page.dart';
import 'image_store_page.dart';

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
          const _SectionHeader('正文字号'),
          _BodyFontTile(profile: profile, controller: controller),
          const Divider(),
          const _SectionHeader('输出'),
          const _ImageStoreEntryTile(),
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
        return '只做阈值判定：整张图最干净，但分数线可能被二值化抹掉、发丝笔画会断。';
      case ThinLinePreset.standard:
        return '严格阈值 $kStrictThreshold + 长水平游程保护 + 亚点笔画提升：'
            '分数线的横线与不完全占满一个点的细竖画都会被还原成 1 点宽的实线'
            '（出厂默认）。';
      case ThinLinePreset.aggressive:
        return '再把严格阈值抬到 $kAggressiveThreshold：墨更重，'
            '细线更实，代价是小字的内白可能糊在一起。';
      case null:
        return '当前参数由开发者模式自定义，不属于任何一个档位。';
    }
  }
}

/// 正文字号下拉：一级设置项。
///
/// 档位选项是常见字号。如果当前值不在选项里（例如由开发者模式自定义），下拉显示
///「当前值（自定义）」，用户仍可点选一个档位恢复。
class _BodyFontTile extends StatelessWidget {
  const _BodyFontTile({required this.profile, required this.controller});

  final PaperProfile profile;
  final ProfileController controller;

  static const List<double> _options = <double>[16, 18, 20, 22, 24];

  @override
  Widget build(BuildContext context) {
    final double value = profile.bodyFontPx;
    final bool isPreset = _options.contains(value);
    final List<DropdownMenuItem<double>> items = <DropdownMenuItem<double>>[
      for (final double option in _options)
        DropdownMenuItem<double>(
          value: option,
          child: Text('${option.toStringAsFixed(0)} 点'),
        ),
    ];

    return ListTile(
      title: const Text('正文字号'),
      subtitle: Text(
        isPreset
            ? '正文字体大小'
            : '当前 ${value.toStringAsFixed(0)} 点（开发者自定义）',
      ),
      trailing: DropdownButton<double>(
        value: isPreset ? value : null,
        hint: Text('${value.toStringAsFixed(0)} 点'),
        items: items,
        onChanged: (double? newValue) {
          if (newValue == null) return;
          // 正文字号不能小于最小可读字号下限；公式字号跟随正文章同比例缩放。
          final double minFontPx = profile.minFontPx;
          final double mathScale = profile.mathFontPx / profile.bodyFontPx;
          final double nextMinFontPx =
              minFontPx > newValue ? newValue : minFontPx;
          unawaited(controller.update(profile.copyWith(
            bodyFontPx: newValue,
            minFontPx: nextMinFontPx,
            mathFontPx: newValue * mathScale,
          )));
        },
      ),
    );
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

/// 输出图片管理入口；副标题显示当前占用，从管理页返回时刷新一次。
class _ImageStoreEntryTile extends StatefulWidget {
  const _ImageStoreEntryTile();

  @override
  State<_ImageStoreEntryTile> createState() => _ImageStoreEntryTileState();
}

class _ImageStoreEntryTileState extends State<_ImageStoreEntryTile> {
  final GalleryStore _store = const GalleryStore();
  int? _totalSize;

  @override
  void initState() {
    super.initState();
    _querySize();
  }

  /// 静默容错：拿不到相册的环境（如 widget 测试没有平台通道）不报错，
  /// 入口本身照常可用。
  Future<void> _querySize() async {
    try {
      final int size = await _store.totalSize();
      if (!mounted) return;
      setState(() => _totalSize = size);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: const Text('输出图片管理'),
      subtitle: Text(
        _totalSize == null
            ? '查看并清理历史出图'
            : '占用 ${formatBytes(_totalSize!)}',
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () async {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (BuildContext context) => const ImageStorePage(),
          ),
        );
        if (mounted) _querySize();
      },
    );
  }
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
