import '../render/raster/binarize.dart';
import 'paper_profile.dart';

/// 细线增强档位（Q14：普通用户只看档位，裸参数只进开发者模式）。
///
/// 三档都在「超采样 + 严格阈值」之上做文章（计划 §5.4a）：
/// 关闭只看阈值本身，标准额外做长游程保护与亚点笔画提升，激进再把阈值抬高。
/// 原「救细竖画要靠 2D 迟滞」的路线已作废：亚点笔画提升以更小代价达到同一目的，
/// 而迟滞会向邻域扩散、糊掉小字内白，在 203dpi 上不可逆。
enum ThinLinePreset {
  /// 只做阈值判定，救结构线、救亚点笔画一概不做。
  off('关闭'),

  /// 严格阈值 + 长游程保护 + 亚点笔画提升，出厂的默认档。
  standard('标准'),

  /// 再把严格阈值抬到 [kAggressiveThreshold]（墨量进一步上升），
  /// 用于用户在校准条上确认「标准档的细线还是发虚」之后。
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
    required this.promoteSubDotStrokes,
  });

  final int threshold;
  final bool protectStructureLines;
  final int structureRunLength;
  final bool promoteSubDotStrokes;
}

/// 档位 ↔ 裸参数的**唯一真相**（计划 §5.8）。
///
/// 档位是「一组裸参数的预设」，因此这里不允许出现第二处映射：用户选档位走
/// [applyThinLinePreset]，开发者改裸参数后靠 [detectThinLinePreset] 反查档位，
/// 两边读的是同一张表。
///
/// 三档的裸参数两两不同（关闭 vs 标准差 [ThinLinePresetParams.protectStructureLines]
/// 与 [ThinLinePresetParams.promoteSubDotStrokes]，标准 vs 激进差
/// [ThinLinePresetParams.threshold]），所以反查结果唯一。
///
/// 注意：`minLineWidthPx` 不在表内。它由校准向导的「这条最细的线看得见吗」单项
/// 产出，且当前光栅阶段尚不消费它（游程保护与亚点笔画提升本身已保证结构线 ≥1 点粗），
/// 放进档位只会给出一个界面上看不出差别的假开关。
const Map<ThinLinePreset, ThinLinePresetParams> kThinLinePresetTable =
    <ThinLinePreset, ThinLinePresetParams>{
  ThinLinePreset.off: ThinLinePresetParams(
    threshold: kStrictThreshold,
    protectStructureLines: false,
    structureRunLength: kStructureRunLength,
    promoteSubDotStrokes: false,
  ),
  ThinLinePreset.standard: ThinLinePresetParams(
    threshold: kStrictThreshold,
    protectStructureLines: true,
    structureRunLength: kStructureRunLength,
    promoteSubDotStrokes: true,
  ),
  ThinLinePreset.aggressive: ThinLinePresetParams(
    threshold: kAggressiveThreshold,
    protectStructureLines: true,
    structureRunLength: kStructureRunLength,
    promoteSubDotStrokes: true,
  ),
};

/// 把档位展开到 [base] 上，只改档位管的那几个裸参数，其余字段原样保留。
PaperProfile applyThinLinePreset(PaperProfile base, ThinLinePreset preset) {
  final ThinLinePresetParams params = kThinLinePresetTable[preset]!;
  return base.copyWith(
    threshold: params.threshold,
    protectStructureLines: params.protectStructureLines,
    structureRunLength: params.structureRunLength,
    promoteSubDotStrokes: params.promoteSubDotStrokes,
  );
}

/// 反查档案当前对应哪个档位；裸参数被开发者改过则返回 null（界面上显示「自定义」）。
ThinLinePreset? detectThinLinePreset(PaperProfile profile) {
  for (final MapEntry<ThinLinePreset, ThinLinePresetParams> entry
      in kThinLinePresetTable.entries) {
    final ThinLinePresetParams params = entry.value;
    if (profile.threshold == params.threshold &&
        profile.protectStructureLines == params.protectStructureLines &&
        profile.structureRunLength == params.structureRunLength &&
        profile.promoteSubDotStrokes == params.promoteSubDotStrokes) {
      return entry.key;
    }
  }
  return null;
}
