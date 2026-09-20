import '../render/raster/binarize.dart';
import 'paper_profile.dart';

/// 细线增强档位（Q14：普通用户只看档位，裸参数只进开发者模式）。
///
/// 三档只做 **1D 水平游程保护** 这一条路线（计划 §5.3、P3 实施笔记 D3）：
/// 「救细竖画」需要 2D 迟滞，实测代价是全图墨量 +29% 起，留到 P4。
/// 本档位的「激进」用抬严格阈值的等价手段达到同一效果，代价同样写在其注释里。
enum ThinLinePreset {
  /// 不做任何结构线保护。
  off('关闭'),

  /// 严格阈值 + 长水平游程保护（实测墨量 +4.0%），出厂的保守默认。
  standard('标准'),

  /// 再把严格阈值抬到 [kAggressiveThreshold]（实测墨量 +29.1%），
  /// 用于用户在校准条上确认「关保护的分数线是断的」之后。
  aggressive('激进');

  const ThinLinePreset(this.label);

  /// 界面上的档位名（Q14 只暴露档位，不暴露裸参数）。
  final String label;
}

/// 一个档位展开成的那组裸参数。
class ThinLinePresetParams {
  const ThinLinePresetParams({
    required this.threshold,
    required this.protectStructureLines,
    required this.structureRunLength,
  });

  final int threshold;
  final bool protectStructureLines;
  final int structureRunLength;
}

/// 档位 ↔ 裸参数的**唯一真相**（计划 §5.8）。
///
/// 档位是「一组裸参数的预设」，因此这里不允许出现第二处映射：用户选档位走
/// [applyThinLinePreset]，开发者改裸参数后靠 [detectThinLinePreset] 反查档位，
/// 两边读的是同一张表。
///
/// 三档的裸参数两两不同（关闭 vs 标准差 [ThinLinePresetParams.protectStructureLines]，
/// 标准 vs 激进差 [ThinLinePresetParams.threshold]），所以反查结果唯一。
///
/// 注意：`minLineWidthPx` 不在表内。它由校准向导的「这条最细的线看得见吗」单项
/// 产出，且当前光栅阶段尚不消费它（游程保护本身已保证结构线 ≥1 点粗），
/// 放进档位只会给出一个界面上看不出差别的假开关。
const Map<ThinLinePreset, ThinLinePresetParams> kThinLinePresetTable =
    <ThinLinePreset, ThinLinePresetParams>{
  ThinLinePreset.off: ThinLinePresetParams(
    threshold: kStrictThreshold,
    protectStructureLines: false,
    structureRunLength: kStructureRunLength,
  ),
  ThinLinePreset.standard: ThinLinePresetParams(
    threshold: kStrictThreshold,
    protectStructureLines: true,
    structureRunLength: kStructureRunLength,
  ),
  ThinLinePreset.aggressive: ThinLinePresetParams(
    threshold: kAggressiveThreshold,
    protectStructureLines: true,
    structureRunLength: kStructureRunLength,
  ),
};

/// 把档位展开到 [base] 上，只改档位管的那几个裸参数，其余字段原样保留。
PaperProfile applyThinLinePreset(PaperProfile base, ThinLinePreset preset) {
  final ThinLinePresetParams params = kThinLinePresetTable[preset]!;
  return base.copyWith(
    threshold: params.threshold,
    protectStructureLines: params.protectStructureLines,
    structureRunLength: params.structureRunLength,
  );
}

/// 反查档案当前对应哪个档位；裸参数被开发者改过则返回 null（界面上显示「自定义」）。
ThinLinePreset? detectThinLinePreset(PaperProfile profile) {
  for (final MapEntry<ThinLinePreset, ThinLinePresetParams> entry
      in kThinLinePresetTable.entries) {
    final ThinLinePresetParams params = entry.value;
    if (profile.threshold == params.threshold &&
        profile.protectStructureLines == params.protectStructureLines &&
        profile.structureRunLength == params.structureRunLength) {
      return entry.key;
    }
  }
  return null;
}