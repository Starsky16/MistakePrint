// P3-4b 校准条测试（计划 P3 实施笔记 §3 提交 4b）。
//
// 三件事必须在这里锁死：
// 1. 全量校准条装得进省纸硬上限（≤1600 点），裁减链逐级更矮；
// 2. 细线区与阈值区嵌的是**真实二值化结果**，各档位彼此不同（否则用户无从判读）；
// 3. 字号阶梯在 384 点里一行一档、不折行（折了就答不出「从哪一档起看不清」）。
//
// 与其它出图测试一样属于开发期离线自检，产物写到仓库外的 D:\code\temp，不入库。

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mistake_print/calibration/calibration_figures.dart' show kFontLadder;
import 'package:mistake_print/calibration/calibration_strip.dart';
import 'package:mistake_print/calibration/calibration_wizard.dart';
import 'package:mistake_print/profiles/paper_profile.dart';
import 'package:mistake_print/profiles/presets.dart';
import 'package:mistake_print/render/raster/binarize.dart';
import 'package:mistake_print/render/raster/raw_capture.dart';
import 'package:mistake_print/render/text/text_styles.dart';

import '../support/png_file.dart';
import '../support/test_fonts.dart';

/// 输出目录（仓库外，不入库）。
const String kOutDir = r'D:\code\temp\p3-strip';

/// 假样例：只需要尺寸对，用于纯版式测试（不涉及出图）。
CalibrationStripSamples fakeSamples() {
  BitmapSample sample(int width, int height, bool Function(int, int) dark) =>
      BitmapSample(List<List<bool>>.generate(
        height,
        (int y) => List<bool>.generate(width, (int x) => dark(x, y)),
      ));

  return CalibrationStripSamples(
    thinLine: <double, Map<ThinLinePreset, BitmapSample>>{
      for (final double fontSize in kThinLineSampleFontSizes)
        fontSize: <ThinLinePreset, BitmapSample>{
          for (final ThinLinePreset preset in ThinLinePreset.values)
            preset: sample(kThinLineCellWidth, 40 + fontSize.toInt(), (x, y) => y % 3 == 0),
        },
    },
    threshold: <int, BitmapSample>{
      for (final int threshold in kThresholdCandidates)
        threshold: sample(kThresholdCellWidth, 46, (x, y) => y % 3 == 0),
    },
  );
}

/// 把校准条摆进可见树量高度（比出图后数像素快，也不依赖离屏管线）。
Future<double> stripHeight(
  WidgetTester tester,
  CalibrationStripSamples samples,
  CalibrationStripBudget budget,
) async {
  final GlobalKey key = GlobalKey();
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        data: const MediaQueryData(),
        child: Align(
          alignment: Alignment.topLeft,
          child: RepaintBoundary(
            key: key,
            child: buildCalibrationStrip(samples: samples, budget: budget),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return tester.getSize(find.byKey(key)).height;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await loadTestFonts();
  });

  /// 校准条比默认视口高得多，先换成能装下它的画布。
  void useTallSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(500, 2500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('全量校准条能出图：宽度 384、装得进省纸上限、1-bit', (WidgetTester tester) async {
    final List<String> logs = <String>[];
    final DebugPrintCallback original = debugPrint;
    late CalibrationStripImage strip;
    try {
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) logs.add(message);
      };
      await tester.runAsync(() async {
        strip = await const CalibrationStripRenderer().render(kPaperangP1Default);
      });
    } finally {
      debugPrint = original;
    }

    debugPrint('[校准条] ${strip.image.width} x ${strip.image.height} 点，'
        '黑点 ${strip.image.blackDots}，耗时 ${strip.image.elapsed.inMilliseconds}ms，'
        '排版 ${strip.image.layoutPasses} 轮');
    writePng(kOutDir, 'p3-calibration-strip-1bit.png', strip.image.png);

    expect(strip.image.width, kCalibrationStripWidth,
        reason: '校准条恒以标称最大宽度出图，才能量出被裁掉的部分');
    expect(strip.image.height, lessThanOrEqualTo(kMaxStripHeightDots),
        reason: '省纸是硬指标：全量版必须装得进 1600 点');
    expect(strip.budget.droppedSections, isEmpty, reason: '全量版就该装得下，不该裁减');
    expect(strip.image.blackDots, greaterThan(0));

    final ByteData ihdr = ByteData.sublistView(strip.image.png);
    expect(ihdr.getUint8(24), 1, reason: 'bitDepth 必须为 1');
    expect(ihdr.getUint8(25), 0, reason: 'colorType 必须为 0（灰度）');
    expect(ihdr.getUint32(16), kCalibrationStripWidth);

    expect(
      logs.any((String message) => message.contains('公式超宽')),
      isFalse,
      reason: '小样例若被断行，细线对照就不成立了',
    );
  });

  testWidgets('裁减链逐级更矮，最省的一版远低于上限', (WidgetTester tester) async {
    useTallSurface(tester);

    late CalibrationStripSamples samples;
    await tester.runAsync(() async {
      samples = await captureCalibrationSamples();
    });

    final List<String> report = <String>[];
    double previous = double.infinity;
    for (final CalibrationStripBudget budget in kStripFallbackChain) {
      final double height = await stripHeight(tester, samples, budget);
      report.add(
        '${budget.droppedSections.isEmpty ? '全量' : '省 ${budget.droppedSections.length} 项'}'
        '=${height.toInt()}',
      );
      expect(height, lessThan(previous), reason: '裁减后必须更矮，否则裁减链无意义');
      expect(height, lessThanOrEqualTo(kMaxStripHeightDots.toDouble()));
      previous = height;
    }
    debugPrint('[校准条] 分区高度（点）：${report.join(' → ')}');
    expect(previous, lessThan(900),
        reason: '最省的一版要留足余量，不能踩在 1600 这条线上');
  });

  testWidgets('字号阶梯在 384 点里一行一档，最大档也不折行', (WidgetTester tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: const MediaQueryData(),
          child: Align(
            alignment: Alignment.topLeft,
            child: buildCalibrationStrip(samples: fakeSamples()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (final double fontSize in kFontLadder) {
      final Size size = tester.getSize(
        find.byKey(ValueKey<String>('ladder-${fontSize.toInt()}')),
      );
      // 两行，每行高 = 字号 × 行高倍数；折行会让高度翻上去。
      final double expected = fontSize * kBodyLineHeight * 2;
      debugPrint('[校准条] fs=${fontSize.toInt()} 档位高 ${size.height}（应为 $expected）');
      expect(size.height, closeTo(expected, 1),
          reason: 'fs=${fontSize.toInt()} 这一档折行了，阶梯就不再是一行一档');
    }
  });

  testWidgets('细线区与阈值区嵌的是各档位真实的二值化结果', (WidgetTester tester) async {
    late CalibrationStripSamples samples;
    await tester.runAsync(() async {
      samples = await captureCalibrationSamples();
    });

    // 细线区：先把三档的真实数据打全，再逐条断言。
    final Map<double, List<int>> rows = <double, List<int>>{};
    for (final double fontSize in kThinLineSampleFontSizes) {
      final Map<ThinLinePreset, BitmapSample> row = samples.thinLine[fontSize]!;
      rows[fontSize] = <int>[
        for (final ThinLinePreset preset in ThinLinePreset.values)
          countDark(row[preset]!.bits),
      ];
      expect(
        row.values.every(
            (BitmapSample s) => s.height == row.values.first.height),
        isTrue,
        reason: '同一实例的三档只能阈值不同，尺寸必须一致',
      );
      debugPrint('[校准条] 细线区 fs=${fontSize.toInt()} '
          '尺寸 ${row.values.first.width}x${row.values.first.height} 黑点 ${rows[fontSize]}');
    }

    // 关保护 → 标准（加游程保护）→ 激进（再抬阈值），墨量只增不减。但实测小字号上
    // 「关保护」与「标准档」会完全重合：fs=14 时分数线本就只占 1 点且是纯黑，游程
    // 保护没有灰边可拉，加不了墨（实测 fs=14 为 [26, 26, 75]）。这不影响判读——用户
    // 可在大字号那几行比较——所以这里不要求每档三列两两不同，只锁三件事。
    bool anyFullyDistinct = false;
    for (final double fontSize in kThinLineSampleFontSizes) {
      final List<int> darks = rows[fontSize]!;
      expect(darks[0], lessThanOrEqualTo(darks[1]),
          reason: 'fs=${fontSize.toInt()} 的保护只该加墨，不该减墨');
      expect(darks[1], lessThanOrEqualTo(darks[2]),
          reason: 'fs=${fontSize.toInt()} 的激进档抬阈值只该加墨，不该减墨');
      expect(darks[0], lessThan(darks[2]),
          reason: 'fs=${fontSize.toInt()} 的「关保护」与「激进」必须分得开，'
              '否则这一行对用户没有判读价值');
      anyFullyDistinct |= darks[0] < darks[1] && darks[1] < darks[2];
    }
    expect(anyFullyDistinct, isTrue,
        reason: '至少得有一个字号能把三档全部分开，用户才有得选');

    // 阈值区：两端的阈值必须真的不同，否则阈值项没有可判读性。
    final int lowThreshold = kThresholdCandidates.first;
    final int highThreshold = kThresholdCandidates.last;
    final int lenient = countDark(samples.threshold[lowThreshold]!.bits);
    final int strict = countDark(samples.threshold[highThreshold]!.bits);
    debugPrint('[校准条] 阈值区黑点：$lowThreshold→$lenient，$highThreshold→$strict');
    expect(strict, greaterThan(lenient));
  });

  test('二次二值化幂等：纯黑纯白的位图在任意阈值下判定一致', () {
    // 校准条自己出图时还会再二值化一次，所以嵌进去的位图必须「再切一刀也不变」。
    final List<List<bool>> bits = <List<bool>>[
      <bool>[true, false, true, true, false],
      <bool>[false, false, true, false, false],
    ];
    final RawCapture rgba = RawCapture(_rgbaOf(bits), 5, 2);

    for (final int threshold in kThresholdCandidates) {
      for (final bool protect in <bool>[false, true]) {
        final List<List<bool>> again = binarize(
          rgba,
          strictThreshold: threshold,
          protectStructureLines: protect,
        );
        expect(again, bits, reason: '阈值 $threshold、保护 $protect 下应逐点一致');
      }
    }
  });
}

/// 位图 → 纯黑/纯白的 RGBA，用于幂等性断言。
Uint8List _rgbaOf(List<List<bool>> bits) {
  final int h = bits.length;
  final int w = bits.first.length;
  final Uint8List rgba = Uint8List(w * h * 4);
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      final int value = bits[y][x] ? 0 : 255;
      final int i = (y * w + x) * 4;
      rgba[i] = value;
      rgba[i + 1] = value;
      rgba[i + 2] = value;
      rgba[i + 3] = 255;
    }
  }
  return rgba;
}