/// 超宽公式的处理策略（计划 §5.5 / Q9）。
enum OversizeStrategy {
  /// 先用 TeX 规则断行，仍超宽才整体缩放。
  lineBreak,

  /// 不尝试断行，直接整体缩放到点阵宽度以内。
  scale,
}

/// 机型档案：宽度与阈值相关的**唯一真相**（计划 §5.5）。
///
/// 所有长度以「打印机点」为单位，不用 mm、不用逻辑像素。
/// 新增机型 = 新增档案 + 在 App 内跑一次校准向导，不改代码。
class PaperProfile {
  const PaperProfile({
    required this.id,
    required this.name,
    required this.dpi,
    required this.paperWidthMm,
    required this.printableDotsWidth,
    required this.minFontPx,
    required this.bodyFontPx,
    required this.mathFontPx,
    required this.lineHeight,
    required this.threshold,
    required this.minLineWidthPx,
    required this.writePhys,
    required this.oversizeStrategy,
    required this.columns,
    required this.isCalibrated,
  });

  final String id;
  final String name;

  /// 打印机物理分辨率（喵喵机 P1 = 203）。
  final int dpi;

  /// 纸张标称宽度（mm）。
  final double paperWidthMm;

  /// 有效打印点阵宽度：版式与输出图的宽度都必须精确等于它。
  final int printableDotsWidth;

  /// 最小可读字号下限，由校准向导得出。
  final double minFontPx;

  /// 正文 CJK 字号。
  final double bodyFontPx;

  /// 公式基准字号（不得低于 24，见计划 §5.3：小字号分数线会被二值化抹掉）。
  final double mathFontPx;

  /// 行高倍数。
  final double lineHeight;

  /// 二值化严格阈值。
  final int threshold;

  /// 结构线最小线宽（点）。
  final int minLineWidthPx;

  /// 是否在 PNG 里写 pHYs 块。
  final bool writePhys;

  final OversizeStrategy oversizeStrategy;

  /// 选项排布列数（首期恒为 1，含公式时必然单列）。
  final int columns;

  /// 是否已由用户校准；false 表示仍是保守默认值（experimental）。
  final bool isCalibrated;
}

/// 喵喵机 P1 的保守默认档案。
///
/// 零标定路线（Q13）下这些值不会在开发期被实机验证，一律取「不会更差」的一侧
/// （计划 §2.3），并保证都能被校准向导改掉。
const PaperProfile kPaperangP1Default = PaperProfile(
  id: 'paperang-p1',
  name: '作业帮喵喵机 P1（默认值，未校准）',
  dpi: 203,
  paperWidthMm: 57,
  printableDotsWidth: 384,
  minFontPx: 20,
  bodyFontPx: 20,
  mathFontPx: 24,
  lineHeight: 1.3,
  threshold: 128,
  minLineWidthPx: 1,
  writePhys: true,
  oversizeStrategy: OversizeStrategy.lineBreak,
  columns: 1,
  isCalibrated: false,
);