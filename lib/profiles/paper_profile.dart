// 细线保护的默认游程长度直接取二值化模块的常量，避免同一份真相写两处。
import '../render/raster/binarize.dart';

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
    required this.protectStructureLines,
    required this.structureRunLength,
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

  /// 是否启用水平长游程结构线保护，用于救回被抗锯齿抹掉的分数线（计划 §5.3）。
  final bool protectStructureLines;

  /// 结构线保护的最小水平游程（点）。
  final int structureRunLength;

  /// 结构线最小线宽（点）。
  final int minLineWidthPx;

  /// 是否在 PNG 里写 pHYs 块。
  final bool writePhys;

  final OversizeStrategy oversizeStrategy;

  /// 选项排布列数（首期恒为 1，含公式时必然单列）。
  final int columns;

  /// 是否已由用户校准；false 表示仍是保守默认值（experimental）。
  final bool isCalibrated;

  /// 逐字段派生一份新档案（校准向导与档位展开都靠它落地）。
  PaperProfile copyWith({
    String? id,
    String? name,
    int? dpi,
    double? paperWidthMm,
    int? printableDotsWidth,
    double? minFontPx,
    double? bodyFontPx,
    double? mathFontPx,
    double? lineHeight,
    int? threshold,
    bool? protectStructureLines,
    int? structureRunLength,
    int? minLineWidthPx,
    bool? writePhys,
    OversizeStrategy? oversizeStrategy,
    int? columns,
    bool? isCalibrated,
  }) =>
      PaperProfile(
        id: id ?? this.id,
        name: name ?? this.name,
        dpi: dpi ?? this.dpi,
        paperWidthMm: paperWidthMm ?? this.paperWidthMm,
        printableDotsWidth: printableDotsWidth ?? this.printableDotsWidth,
        minFontPx: minFontPx ?? this.minFontPx,
        bodyFontPx: bodyFontPx ?? this.bodyFontPx,
        mathFontPx: mathFontPx ?? this.mathFontPx,
        lineHeight: lineHeight ?? this.lineHeight,
        threshold: threshold ?? this.threshold,
        protectStructureLines: protectStructureLines ?? this.protectStructureLines,
        structureRunLength: structureRunLength ?? this.structureRunLength,
        minLineWidthPx: minLineWidthPx ?? this.minLineWidthPx,
        writePhys: writePhys ?? this.writePhys,
        oversizeStrategy: oversizeStrategy ?? this.oversizeStrategy,
        columns: columns ?? this.columns,
        isCalibrated: isCalibrated ?? this.isCalibrated,
      );
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
  protectStructureLines: true,
  structureRunLength: kStructureRunLength,
  minLineWidthPx: 1,
  writePhys: true,
  oversizeStrategy: OversizeStrategy.lineBreak,
  columns: 1,
  isCalibrated: false,
);