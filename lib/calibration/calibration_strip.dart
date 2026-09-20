import 'package:flutter/material.dart';

import '../profiles/paper_profile.dart';
import '../profiles/presets.dart';
import '../render/document_view.dart';
import '../render/offscreen/offscreen_canvas.dart';
import '../render/offscreen/print_renderer.dart';
import '../render/raster/binarize.dart';
import '../render/raster/png_encode.dart';
import '../render/raster/raw_capture.dart';
import '../render/text/text_styles.dart';
import 'calibration_figures.dart' show kFontLadder;
import 'calibration_wizard.dart';

/// 主校准条总高的硬上限（点，约 200mm）。
///
/// 省纸是校准向导的第一设计约束（计划 §5.8）：超出必须裁减项，宁可少校一项，
/// 也不能让用户打第二张。裁减顺序见 [kStripFallbackChain]。
const int kMaxStripHeightDots = 1600;

/// 校准条上小节说明文字的字号。
///
/// 取 14 而不是更小：这句话是用户读题的唯一依据，它自己看不清的话整张就白打了。
const double kStripCaptionFontSize = 14;

/// 细线保真区与阈值并列区各自的小样例宽度：384 均分 3 列 / 4 列。
const int kThinLineCellWidth = 128;
const int kThresholdCellWidth = 96;

/// 细线保真区参与对照的字号（计划 §6.3：只取 3 个关键字号，不逐档打印）。
const List<double> kThinLineSampleFontSizes = <double>[14, 20, 28];

/// 阈值并列区的小样例字号。
const double kThresholdSampleFontSize = 18;

/// 细线与阈值对照用的样例公式。
///
/// 选它是因为 `+` 的竖画与两条分数线恰好覆盖两种最脆弱的笔画：竖画（水平游程仅
/// 2 点，长游程保护救不回来，见 `binarize.dart`）与长横画（易被抗锯齿抹成灰）。
const String kThinLineSample = r'$\frac{x}{2}+\frac{1}{x}$';

/// 字号阶梯的两行样例。
///
/// 刻意取短：字号最大的一档是 32，太长的话会在 384 点里折行，阶梯就不再是「一行一档」，
/// 用户没法回答「从哪一档起看不清」。
const String kLadderText = '错题1：△ABC ≌ △DEF';
const String kLadderSymbols = 'x²+y²=r² a/b ①②③';

/// 一小片**已经二值化**的真值位图（true = 打印黑点）。
///
/// 校准条上的阈值区与细线区必须展示真实结果，而不是示意图形。做成位图而不是 PNG
/// 有两个原因：一是画的时候只按行画黑游程，没有图片解码的异步等待，离屏管线
/// （永不排帧）里一次捕获就能画全；二是整条校准条出图时还会再二值化一次，纯黑/纯白
/// 的位图在任意阈值下判定一致（幂等），不会把候选档位糊掉。
class BitmapSample {
  const BitmapSample(this.bits);

  final List<List<bool>> bits;

  int get width => bits.isEmpty ? 0 : bits.first.length;

  int get height => bits.length;
}

/// 校准条上要嵌进去的那些真实结果。
class CalibrationStripSamples {
  const CalibrationStripSamples({
    required this.thinLine,
    required this.threshold,
  });

  /// 字号 → 细线档位 → 该档位二值化后的真实结果。
  final Map<double, Map<ThinLinePreset, BitmapSample>> thinLine;

  /// 阈值 → 该阈值二值化后的真实结果。
  final Map<int, BitmapSample> threshold;
}

/// 校准条的分区开关。
///
/// 宽度区永远保留：它是「有效宽度」这项最重要校准的唯一素材，也是同时判出缩放与
/// 裁边的区。
class CalibrationStripBudget {
  const CalibrationStripBudget({
    this.includeFontLadder = true,
    this.includeThinLine = true,
    this.includeThreshold = true,
    this.includeGray = true,
  });

  final bool includeFontLadder;
  final bool includeThinLine;
  final bool includeThreshold;
  final bool includeGray;

  /// 这一版被省掉的分区名，用于如实告诉用户「这次少校了哪一项」。
  List<String> get droppedSections => <String>[
        if (!includeGray) '灰阶（只作诊断）',
        if (!includeThreshold) '阈值并列',
        if (!includeFontLadder) '字号阶梯',
        if (!includeThinLine) '细线保真',
      ];
}

/// 出图超过 [kMaxStripHeightDots] 时的裁减顺序：先删最不重要的。
///
/// 灰阶只作诊断；阈值并列可由细线档位推出；字号阶梯与细线保真最后才动。
const List<CalibrationStripBudget> kStripFallbackChain =
    <CalibrationStripBudget>[
  CalibrationStripBudget(),
  CalibrationStripBudget(includeGray: false),
  CalibrationStripBudget(includeGray: false, includeThreshold: false),
  CalibrationStripBudget(
    includeGray: false,
    includeThreshold: false,
    includeFontLadder: false,
  ),
];

/// 生成结果：可分享的图 + 实际用了哪一版分区。
class CalibrationStripImage {
  const CalibrationStripImage({required this.image, required this.budget});

  final PrintImage image;

  final CalibrationStripBudget budget;
}

/// 校准条生成器（做成类是为了让页面测试注入假实现，不必真的跑离屏管线）。
class CalibrationStripRenderer {
  const CalibrationStripRenderer({this.canvas = const OffscreenCanvas()});

  final OffscreenCanvas canvas;

  /// 逐版试到装得下为止：正常一版就够（见 [kStripFallbackChain]）。
  Future<CalibrationStripImage> render(
    PaperProfile profile, {
    RenderProgressCallback? onProgress,
  }) async {
    onProgress?.call(0.05, '准备样例');
    final CalibrationStripSamples samples =
        await captureCalibrationSamples(canvas: canvas);
    onProgress?.call(0.45, '样例已二值化');

    CalibrationStripImage result = await _renderOnce(profile, samples,
        kStripFallbackChain.first, onProgress);
    if (result.image.height <= kMaxStripHeightDots) return result;

    for (final CalibrationStripBudget budget
        in kStripFallbackChain.skip(1)) {
      debugPrint(
        '[校准条] ${result.image.height} 点超过上限 $kMaxStripHeightDots，'
        '已省掉：${result.budget.droppedSections.join('、')}',
      );
      result = await _renderOnce(profile, samples, budget, onProgress);
      if (result.image.height <= kMaxStripHeightDots) return result;
    }
    // 走到这里说明连最省的版本也超长：仍然交付，但把真实高度留在日志里。
    debugPrint('[校准条] 已裁到最省仍为 ${result.image.height} 点，超过上限');
    return result;
  }

  Future<CalibrationStripImage> _renderOnce(
    PaperProfile profile,
    CalibrationStripSamples samples,
    CalibrationStripBudget budget,
    RenderProgressCallback? onProgress,
  ) async {
    final Stopwatch watch = Stopwatch()..start();
    onProgress?.call(0.55, '排版校准条');
    final OffscreenCapture shot = await canvas.capture(
      child: buildCalibrationStrip(samples: samples, budget: budget),
      // 恒用标称最大宽度出图，理由见 kCalibrationStripWidth。
      widthDots: kCalibrationStripWidth,
    );

    onProgress?.call(0.85, '二值化与编码');
    // 与用户日常出图用同一套参数，保证「打印出来看到的效果」就是他平时拿到的效果。
    final List<List<bool>> black = binarize(
      shot.raw,
      protectStructureLines: profile.protectStructureLines,
      strictThreshold: profile.threshold,
      structureRunLength: profile.structureRunLength,
    );
    watch.stop();
    return CalibrationStripImage(
      image: PrintImage(
        png: encodeBitmap(black, withPhys: profile.writePhys),
        width: shot.raw.width,
        height: shot.raw.height,
        blackDots: countDark(black),
        elapsed: watch.elapsed,
        layoutPasses: shot.layoutPasses,
      ),
      budget: budget,
    );
  }
}

/// 第一阶段的产物：先离屏出小样例的灰度图，再在各候选阈值 / 各细线档位下二值化。
///
/// 结果与档案无关，所以一版裁剪重试可以复用同一批样例，不必重新出图。
Future<CalibrationStripSamples> captureCalibrationSamples({
  OffscreenCanvas canvas = const OffscreenCanvas(),
}) async {
  final Map<double, Map<ThinLinePreset, BitmapSample>> thinLine =
      <double, Map<ThinLinePreset, BitmapSample>>{};
  for (final double fontSize in kThinLineSampleFontSizes) {
    final RawCapture gray =
        await _captureSample(canvas, kThinLineCellWidth, fontSize);
    thinLine[fontSize] = <ThinLinePreset, BitmapSample>{
      for (final ThinLinePreset preset in ThinLinePreset.values)
        preset: BitmapSample(_binarizeWithPreset(gray, preset)),
    };
  }

  final RawCapture thresholdGray =
      await _captureSample(canvas, kThresholdCellWidth, kThresholdSampleFontSize);
  return CalibrationStripSamples(
    thinLine: thinLine,
    threshold: <int, BitmapSample>{
      for (final int threshold in kThresholdCandidates)
        // 阈值区只看阈值本身的差别，关掉游程保护，免得它把灰边一并拉黑后
        // 四档看起来一样。
        threshold: BitmapSample(
          binarize(thresholdGray, strictThreshold: threshold),
        ),
    },
  );
}

/// 出一小片样例的灰度图：固定小宽度，正文与公式同号（免得正文行距把样例撑高）。
Future<RawCapture> _captureSample(
  OffscreenCanvas canvas,
  int widthDots,
  double fontSize,
) async {
  final PaperProfile sample = kPaperangP1Default.copyWith(
    printableDotsWidth: widthDots,
    bodyFontPx: fontSize,
    mathFontPx: fontSize,
    lineHeight: 1,
  );
  final OffscreenCapture shot = await canvas.capture(
    child: renderDocument(kThinLineSample, sample),
    widthDots: widthDots,
  );
  return shot.raw;
}

List<List<bool>> _binarizeWithPreset(RawCapture gray, ThinLinePreset preset) {
  final ThinLinePresetParams params = kThinLinePresetTable[preset]!;
  return binarize(
    gray,
    protectStructureLines: params.protectStructureLines,
    strictThreshold: params.threshold,
    structureRunLength: params.structureRunLength,
  );
}

// ---------------------------------------------------------------------------
// 版式
// ---------------------------------------------------------------------------

/// 拼出校准条版式（不出图，便于单独断言版式与高度）。
Widget buildCalibrationStrip({
  required CalibrationStripSamples samples,
  CalibrationStripBudget budget = const CalibrationStripBudget(),
}) =>
    SizedBox(
      width: kCalibrationStripWidth.toDouble(),
      // 热敏纸是白底：出图必须自带白背景，否则离屏捕获拿到的是透明像素。
      child: ColoredBox(
        color: const Color(0xFFFFFFFF),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const _Title(),
            const _WidthSection(),
            if (budget.includeFontLadder) const _FontLadderSection(),
            if (budget.includeThinLine) _ThinLineSection(samples.thinLine),
            if (budget.includeThreshold)
              _ThresholdSection(samples.threshold),
            if (budget.includeGray) const _GraySection(),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );

Widget _caption(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(4, 10, 4, 4),
      child: Text(text, style: bodyStyle(kStripCaptionFontSize)),
    );

class _Title extends StatelessWidget {
  const _Title();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text('全能校准条（1 张就够了）', style: bodyStyle(16)),
            const SizedBox(height: 2),
            Text(
              '打印后回到 App → 设置 → 打印校准，逐项点选。每项都能跳过，跳过就用默认值。',
              style: bodyStyle(12),
            ),
          ],
        ),
      );
}

/// 宽度区：一条阶梯状的候选线，每条线的右端标着它的宽度。
///
/// 竖线版本（原 §6.1）在 6 点间距下数字会互相压住，所以改成上下堆叠的横线——
/// 「这条线画到哪儿就是几」，读数不会被相邻候选干扰；右缘另有 3 点粗线代表 384。
class _WidthSection extends StatelessWidget {
  const _WidthSection();

  static const double kHeight = 116;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _caption('① 有效宽度 · ② 宽度异常：右边那条线看得见的最外面一个数字是几？'
              '（右边有白边／被切也看这里）'),
          CustomPaint(
            size: Size(kCalibrationStripWidth.toDouble(), kHeight),
            painter: const _WidthRulerPainter(),
          ),
        ],
      );
}

class _WidthRulerPainter extends CustomPainter {
  const _WidthRulerPainter();

  /// 每条候选线之间的行距：比标签高度略大，保证数字不叠。
  static const double _rowGap = 20;

  /// 第一条候选线的 y。
  static const double _firstRowY = 22;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint line = Paint()
      ..color = kInk
      ..isAntiAlias = false;

    // 上下 1px 边框：判「有没有被缩放」时，横向也得有个满宽参照。
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, 1), line);
    canvas.drawRect(Rect.fromLTWH(0, size.height - 1, size.width, 1), line);
    // 左缘 1px 贴纸边；右缘 3px 粗线代表 384 这条边界。
    canvas.drawRect(Rect.fromLTWH(0, 0, 1, size.height), line);
    canvas.drawRect(Rect.fromLTWH(size.width - 3, 0, 3, size.height), line);

    for (int i = 0; i < kWidthCandidates.length; i++) {
      final int candidate = kWidthCandidates[i];
      final double y = _firstRowY + i * _rowGap;
      // 候选线：从纸左缘画到「宽度为 candidate 时最右一列」。
      canvas.drawRect(Rect.fromLTWH(0, y, candidate - 1, 1), line);

      final TextPainter label = TextPainter(
        text: TextSpan(text: '$candidate', style: bodyStyle(kStripCaptionFontSize)),
        textDirection: TextDirection.ltr,
      )..layout();
      // 数字贴着线尾上方，右对齐到线尾前 3 点，读的就是「这条线到哪儿」。
      label.paint(
        canvas,
        Offset(candidate - 1 - label.width - 3, y - label.height + 3),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WidthRulerPainter oldDelegate) => false;
}

/// 字号阶梯：一档一行（中文 + 符号数字各一行），回答「最小的仍然看得清的是哪一档」。
///
/// 档号单独占一列而不是拼在样例前面：最大档 32 的样例本身已接近 384 点满宽，
/// 档号一并排进去会把样例挤到折行，阶梯就不再是「一行一档」，用户答不出
/// 「从哪一档起看不清」。
class _FontLadderSection extends StatelessWidget {
  const _FontLadderSection();

  /// 档号列宽：够放 12~32 两位数字，又矮于最小档的两行高度，不改变行高。
  static const double _indexWidth = 26;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _caption('③ 最小可读字号：还能看清的最小那一档是几？'),
          for (final double fontSize in kFontLadder)
            Padding(
              // 尺寸不参与判断，但测试要按档位核对「有没有折行」。
              key: ValueKey<String>('ladder-${fontSize.toInt()}'),
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SizedBox(
                    width: _indexWidth,
                    child: Text('${fontSize.toInt()}', style: bodyStyle(12)),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(kLadderText, style: bodyStyle(fontSize)),
                        Text(kLadderSymbols, style: bodyStyle(fontSize)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      );
}

/// 细线保真区：同一段分式，3 档字号 × 3 个档位并排，展示的是**真实二值化结果**。
class _ThinLineSection extends StatelessWidget {
  const _ThinLineSection(this.samples);

  final Map<double, Map<ThinLinePreset, BitmapSample>> samples;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _caption('④ 细线保真：哪一列的分数线是完整的一条？（左→右：'
              '${ThinLinePreset.values.map((ThinLinePreset p) => p.label).join(' / ')}）'),
          Row(
            children: <Widget>[
              for (final ThinLinePreset preset in ThinLinePreset.values)
                SizedBox(
                  width: kThinLineCellWidth.toDouble(),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      preset.label,
                      textAlign: TextAlign.center,
                      style: bodyStyle(12),
                    ),
                  ),
                ),
            ],
          ),
          for (final double fontSize in kThinLineSampleFontSizes) ...<Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 2),
              child: Text('fs=${fontSize.toInt()}', style: bodyStyle(12)),
            ),
            Row(
              children: <Widget>[
                for (final ThinLinePreset preset in ThinLinePreset.values)
                  _BitmapCell(
                    width: kThinLineCellWidth,
                    sample: samples[fontSize]![preset]!,
                  ),
              ],
            ),
          ],
        ],
      );
}

/// 阈值并列区：同一段文字在 4 档阈值下的真实结果。
class _ThresholdSection extends StatelessWidget {
  const _ThresholdSection(this.samples);

  final Map<int, BitmapSample> samples;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _caption('⑤ 阈值档位：哪一档最清楚？（数值越小越干净，越大墨越多）'),
          Row(
            children: <Widget>[
              for (final int threshold in kThresholdCandidates)
                SizedBox(
                  width: kThresholdCellWidth.toDouble(),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      '$threshold',
                      textAlign: TextAlign.center,
                      style: bodyStyle(12),
                    ),
                  ),
                ),
            ],
          ),
          Row(
            children: <Widget>[
              for (final int threshold in kThresholdCandidates)
                _BitmapCell(
                  width: kThresholdCellWidth,
                  sample: samples[threshold]!,
                ),
            ],
          ),
        ],
      );
}

/// 灰阶区：只作诊断，不回写任何参数（P3 实施笔记 D3）。
class _GraySection extends StatelessWidget {
  const _GraySection();

  static const double kHeight = 40;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _caption('⑥ 灰阶：能分辨出几档？（只作诊断，不改参数）'),
          CustomPaint(
            size: Size(kCalibrationStripWidth.toDouble(), kHeight),
            painter: const _GrayLadderPainter(),
          ),
        ],
      );
}

/// 10 档灰度阶梯，每档贴一条 1px 分隔线便于在打印结果上定位。
class _GrayLadderPainter extends CustomPainter {
  const _GrayLadderPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final double step = size.width / 10;
    for (int i = 0; i < 10; i++) {
      final int value = (255 * i / 9).round();
      canvas.drawRect(
        Rect.fromLTWH(step * i, 0, step, size.height),
        Paint()..color = Color.fromARGB(255, value, value, value),
      );
    }
    final Paint line = Paint()
      ..color = kInk
      ..isAntiAlias = false;
    for (int i = 0; i <= 10; i++) {
      canvas.drawRect(Rect.fromLTWH(step * i - (i == 10 ? 1 : 0), 0, 1, size.height), line);
    }
  }

  @override
  bool shouldRepaint(covariant _GrayLadderPainter oldDelegate) => false;
}

/// 一格真实结果位图：列宽固定，样例按原尺寸左对齐摆放（不做任何缩放）。
class _BitmapCell extends StatelessWidget {
  const _BitmapCell({required this.width, required this.sample});

  final int width;
  final BitmapSample sample;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: width.toDouble(),
        child: Align(
          alignment: Alignment.centerLeft,
          child: CustomPaint(
            size: Size(sample.width.toDouble(), sample.height.toDouble()),
            painter: _BitmapPainter(sample.bits),
          ),
        ),
      );
}

/// 把真值位图按行画成黑游程：整数坐标 + 关抗锯齿 → 1:1 下仍是纯黑零灰边。
class _BitmapPainter extends CustomPainter {
  const _BitmapPainter(this.bits);

  final List<List<bool>> bits;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint ink = Paint()
      ..color = kInk
      ..isAntiAlias = false;
    for (int y = 0; y < bits.length; y++) {
      final List<bool> row = bits[y];
      int x = 0;
      while (x < row.length) {
        if (!row[x]) {
          x++;
          continue;
        }
        int end = x;
        while (end < row.length && row[end]) {
          end++;
        }
        canvas.drawRect(
          Rect.fromLTWH(x.toDouble(), y.toDouble(), (end - x).toDouble(), 1),
          ink,
        );
        x = end;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BitmapPainter oldDelegate) =>
      oldDelegate.bits != bits;
}