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
          const _SectionHeader('机型'),
          _ModelTile(profile: profile, controller: controller),
          const Divider(),
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

/// 机型下拉：一级设置项（决策记录 Q5）。
///
/// 选中机型 = 切换到对应内置预设档案并落库；下拉选中态由当前档案的
/// `id` 反查内置表推导（id 随 profile.json 持久化、copyWith 不改 id），
/// 因此跨重启自然恢复，不需要额外的偏好键。
/// 当前档案不属于任何内置机型时下拉空选、副标题显示档案名。
class _ModelTile extends StatelessWidget {
  const _ModelTile({required this.profile, required this.controller});

  final PaperProfile profile;
  final ProfileController controller;

  /// 「添加机型…」占位项的哨兵值：不与任何内置机型 id 冲突。
  static const String _addModelValue = 'add-model';

  /// 下拉显示名（短名；档案 name 供开发者页与持久化用）。
  static const Map<String, String> _labels = <String, String>{
    'paperang-p1': '喵喵机 P1',
    'paperang-p2': '喵喵机 P2',
    'paperang-p2s': '喵喵机 P2S',
  };

  Future<void> _onSelected(BuildContext context, String? value) async {
    if (value == null) return;
    if (value == _addModelValue) {
      // 占位：第二期做自测条向导（决策记录 Q6）。不弹 issue 跳转，
      // 避免为开一个网页引入 url_launcher 依赖。
      await showDialog<void>(
        context: context,
        builder: (BuildContext dialogContext) => AlertDialog(
          title: const Text('添加机型'),
          content: const Text('自定义机型将在后续版本提供。如需适配你的机型，'
              '欢迎到 GitHub 仓库提交「机型适配征集」issue。'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
      return;
    }
    final PaperProfile? target = builtInProfileById(value);
    if (target != null) {
      unawaited(controller.update(target));
    }
  }

  @override
  Widget build(BuildContext context) {
    final PaperProfile? current = builtInProfileById(profile.id);
    return ListTile(
      title: const Text('机型'),
      subtitle: Text(
        current == null ? '当前 ${profile.name}（自定义）' : '选择打印机型号',
      ),
      trailing: DropdownButton<String>(
        value: current?.id,
        hint: const Text('自定义机型'),
        items: <DropdownMenuItem<String>>[
          for (final PaperProfile preset in kBuiltInProfiles)
            DropdownMenuItem<String>(
              value: preset.id,
              child: Text(_labels[preset.id] ?? preset.name),
            ),
          const DropdownMenuItem<String>(
            value: _addModelValue,
            child: Text('添加机型…'),
          ),
        ],
        onChanged: (String? value) => unawaited(_onSelected(context, value)),
      ),
    );
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

  /// 档位选项：P1（203 dpi）上的点数值。其他机型按 dpi 比例缩放后取整，
  /// 保证不同机型上给到的是同一批「物理字号」。
  static const List<double> _p1Options = <double>[16, 18, 20, 22, 24];

  /// P1（203 dpi）上的公式字号下限（见 `PaperProfile.mathFontPx` 注释）。
  static const double _p1MinMathFontPx = 24;

  /// 当前机型的档位选项：按 dpi 比例缩放并取整（P1 上与 [_p1Options] 逐位相同）。
  List<double> get _options => <double>[
        for (final double option in _p1Options)
          (option * profile.dpi / 203).roundToDouble(),
      ];

  /// 当前机型的公式字号下限：与字号同比例缩放（203 dpi 的 24 点 = 300 dpi 的 35 点）。
  double get _minMathFontPx =>
      (_p1MinMathFontPx * profile.dpi / 203).roundToDouble();

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
          // 正文字号不能小于最小可读字号下限；公式字号跟随正文同比例缩放，
          // 但不得低于下限——小字号的分数线会被二值化抹掉。
          final double minFontPx = profile.minFontPx;
          final double mathScale = profile.mathFontPx / profile.bodyFontPx;
          final double nextMinFontPx =
              minFontPx > newValue ? newValue : minFontPx;
          final double nextMathFontPx =
              mathScale * newValue < _minMathFontPx
                  ? _minMathFontPx
                  : mathScale * newValue;
          unawaited(controller.update(profile.copyWith(
            bodyFontPx: newValue,
            minFontPx: nextMinFontPx,
            mathFontPx: nextMathFontPx,
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
