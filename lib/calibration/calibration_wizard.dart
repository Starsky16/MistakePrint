import '../profiles/paper_profile.dart';
import '../profiles/presets.dart';

/// 校准条恒定的出图宽度（点）。
///
/// 校准条**不跟随档案里的当前宽度**：它的任务就是量出真实有效宽度，若按当前宽度
/// 出图，「图偏窄」到底是图上本来就这么窄还是被裁掉了就分不清了。所以一律以标称
/// 最大值出图，把候选线画在绝对位置上。
const int kCalibrationStripWidth = 384;

/// 宽度候选（点）：校准条上画的几条内缩线，也就是用户能选的那几个答案。
const List<int> kWidthCandidates = <int>[384, 378, 372, 366, 360];

/// 阈值候选：校准条上「阈值并列区」并排的四档，同时也是用户能选的答案。
///
/// 窗口取自 v0.1.0 实机结论（128 那两档在纸上「字都没了」）与 v0.1.1 的超采样改动：
/// 超采样把覆盖率还原准了之后，可用区间整体上移到 150 附近，因此候选改成
/// 140~170，不再保留 110 / 128 这类已知打不出来的档位。
const List<int> kThresholdCandidates = <int>[140, 150, 160, 170];

/// 灰阶诊断项的候选答案（能分辨出几档）。
const List<int> kGrayLevelCandidates = <int>[2, 4, 6, 8, 10];

/// 正文字号的下限与上限（P3 实施笔记 D4）。
///
/// 下限防比例失衡（正文比最小可读字号还小，细线会加剧糊掉），上限防误选大档导致
/// 行数暴涨、一张纸装不下几道题。
const double kBodyFontMinPx = 16;
const double kBodyFontMaxPx = 24;

/// 「宽度异常判定」这一项的现象。
///
/// 它和「有效宽度」靠同一条候选线同时判出来，不需要额外打印（计划 §5.8）。
enum WidthEdgeAnswer {
  /// 右边最外面那条线就在纸边附近，打印正常。
  lineVisible('右边有线（刚好贴边）'),

  /// 右边留了白边，说明打印 App 按 mm 把图缩小了。
  whiteMargin('右边有白边（图偏小）'),

  /// 右边被切掉，需要按实际边界内缩宽度。
  clipped('右边被切（图偏大）'),

  /// 看不出来或不想判。
  unsure('不确定');

  const WidthEdgeAnswer(this.label);

  final String label;
}

/// 校准向导收集到的答案：**每一项都可以是 null（跳过）**。
///
/// 跳过的项保留档案里的原值，也不会让档案变成「已校准」——「跳过后仍能用默认值出图」
/// 是硬要求（计划 §5.8「不做强制引导」）。
class CalibrationAnswers {
  const CalibrationAnswers({
    this.printableDotsWidth,
    this.widthEdge,
    this.minFontPx,
    this.thinLinePreset,
    this.threshold,
    this.grayLevels,
  });

  /// 有效宽度：用户选中的那条候选线。
  final int? printableDotsWidth;

  final WidthEdgeAnswer? widthEdge;

  /// 用户选中的「最小的仍然看得清」的字号。
  final double? minFontPx;

  /// 细线保真：用户选中的细线增强档位。
  final ThinLinePreset? thinLinePreset;

  /// 阈值档位：用户选中「哪一档最清楚」。
  final int? threshold;

  /// 灰阶可分辨档数：纯诊断项，**不回写档案**。
  final int? grayLevels;

  /// 是否有任何一项能推导出参数（灰阶不算，它只作诊断）。
  bool get hasDerivableAnswer =>
      printableDotsWidth != null ||
      widthEdge != null ||
      minFontPx != null ||
      thinLinePreset != null ||
      threshold != null;
}

/// 把答案推导成新档案（计划 §5.8「校准项 → 推导」的**单一实现**）。
///
/// 顺序即冲突消解规则，两处都不能改成别样：
/// 1. 细线档位**先展开**成裸参数（阈值 + 是否保护 + 游程）；
/// 2. 阈值项**只覆盖 `threshold`**：用户对「哪一档最清楚」的回答比档位表更具体，
///    但它不该把游程保护一起改掉；
/// 3. 宽度、`writePhys`、字号各自独立，互不干涉。
///
/// 灰阶项只作诊断，不进这个函数。
PaperProfile applyCalibration(PaperProfile base, CalibrationAnswers answers) {
  PaperProfile p = base;

  final ThinLinePreset? preset = answers.thinLinePreset;
  if (preset != null) {
    p = applyThinLinePreset(p, preset);
  }
  if (answers.threshold != null) {
    p = p.copyWith(threshold: answers.threshold);
  }
  if (answers.printableDotsWidth != null) {
    p = p.copyWith(printableDotsWidth: answers.printableDotsWidth);
  }
  if (answers.widthEdge == WidthEdgeAnswer.whiteMargin) {
    // 图偏小说明打印 App 按 mm 缩放，切一下 pHYs 元数据即可（计划 §5.8）。
    p = p.copyWith(writePhys: !p.writePhys);
  }
  if (answers.minFontPx != null) {
    p = p.copyWith(
      minFontPx: answers.minFontPx,
      bodyFontPx: bodyFontFor(answers.minFontPx!),
    );
  }
  // 「右边被切」的内缩量已经由「有效宽度」那一项承载（用户选中的线就是实际边界），
  // 这里不再猜一个量出来。
  if (answers.hasDerivableAnswer) {
    p = p.copyWith(isCalibrated: true);
  }
  return p;
}

/// D4：正文按所选最小可读字号取，夹在 [kBodyFontMinPx] 与 [kBodyFontMaxPx] 之间。
double bodyFontFor(double minFontPx) =>
    minFontPx.clamp(kBodyFontMinPx, kBodyFontMaxPx).toDouble();

/// 两份档案之间的差异，用于汇总预览。
///
/// 只列会改变出图结果的字段；没变的不列，全部跳过时返回空表。
List<String> describeProfileDiff(PaperProfile from, PaperProfile to) {
  final List<String> diff = <String>[];

  void add(String label, Object? before, Object? after) {
    if (before != after) diff.add('$label：$before → $after');
  }

  add('有效宽度', from.printableDotsWidth, to.printableDotsWidth);
  add('最小可读字号', _pretty(from.minFontPx), _pretty(to.minFontPx));
  add('正文字号', _pretty(from.bodyFontPx), _pretty(to.bodyFontPx));
  add('严格阈值', from.threshold, to.threshold);
  add(
    '结构线保护',
    from.protectStructureLines ? '开' : '关',
    to.protectStructureLines ? '开' : '关',
  );
  add(
    '亚点笔画提升',
    from.promoteSubDotStrokes ? '开' : '关',
    to.promoteSubDotStrokes ? '开' : '关',
  );
  add('写入 pHYs', from.writePhys ? '是' : '否', to.writePhys ? '是' : '否');
  add('已校准', from.isCalibrated ? '是' : '否', to.isCalibrated ? '是' : '否');
  return diff;
}

/// 整数点数不要显示成 `20.0`。
String _pretty(num value) =>
    value == value.roundToDouble() ? value.toInt().toString() : '$value';