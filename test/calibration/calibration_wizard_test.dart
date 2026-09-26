// P3-4b 校准向导的推导逻辑测试（计划 §5.8「校准项 → 推导」）。
//
// 这里只测纯推导：怎么把六项回答变成一份新档案，以及冲突消解的顺序。出图与页面
// 分别由 test/widget/calibration_strip_test.dart 与
// test/app/calibration_wizard_page_test.dart 覆盖。

import 'package:flutter_test/flutter_test.dart';
import 'package:mistake_print/calibration/calibration_wizard.dart';
import 'package:mistake_print/profiles/paper_profile.dart';
import 'package:mistake_print/profiles/presets.dart';
import 'package:mistake_print/render/raster/binarize.dart';

void main() {
  const PaperProfile base = kPaperangP1Default;

  group('全部跳过', () {
    test('档案一个字段都不变，且不会被标成已校准', () {
      const CalibrationAnswers answers = CalibrationAnswers();

      final PaperProfile out = applyCalibration(base, answers);

      expect(out, base);
      expect(out.isCalibrated, isFalse, reason: '跳过不给「已校准」背书');
    });

    test('只回答灰阶（诊断项）同样不改档案、不标已校准', () {
      const CalibrationAnswers answers = CalibrationAnswers(grayLevels: 6);

      final PaperProfile out = applyCalibration(base, answers);

      expect(out, base);
      expect(out.isCalibrated, isFalse);
    });
  });

  group('宽度', () {
    test('只答宽度：只改 printableDotsWidth，其余原样并标已校准', () {
      const CalibrationAnswers answers =
          CalibrationAnswers(printableDotsWidth: 372);

      final PaperProfile out = applyCalibration(base, answers);

      expect(out.printableDotsWidth, 372);
      expect(out.threshold, base.threshold);
      expect(out.minFontPx, base.minFontPx);
      expect(out.writePhys, base.writePhys);
      expect(out.isCalibrated, isTrue);
    });

    test('答「右边有白边」：只翻转 writePhys，不错动宽度', () {
      const CalibrationAnswers answers =
          CalibrationAnswers(widthEdge: WidthEdgeAnswer.whiteMargin);

      final PaperProfile out = applyCalibration(base, answers);

      expect(out.writePhys, isNot(base.writePhys));
      expect(out.printableDotsWidth, base.printableDotsWidth);
      expect(out.isCalibrated, isTrue);
    });

    test('答「右边被切」：内缩量由宽度项承载，本项不再猜一个量', () {
      final PaperProfile out = applyCalibration(
        base,
        const CalibrationAnswers(
          widthEdge: WidthEdgeAnswer.clipped,
          printableDotsWidth: 366,
        ),
      );

      expect(out.printableDotsWidth, 366);
      expect(out.writePhys, base.writePhys);
    });
  });

  group('细线档位与阈值的冲突消解', () {
    test('选档位后阈值项只覆盖 threshold，保护与游程仍是档位那一套', () {
      final PaperProfile out = applyCalibration(
        base,
        const CalibrationAnswers(
          thinLinePreset: ThinLinePreset.standard,
          threshold: 160,
        ),
      );

      expect(out.threshold, 160, reason: '阈值项覆盖档位展开出来的 $kStrictThreshold');
      expect(out.protectStructureLines, isTrue, reason: '档位展开的保护不能被阈值项改掉');
      expect(out.promoteSubDotStrokes, isTrue, reason: '提升同理，也不该被阈值项改掉');
      expect(
        out.structureRunLength,
        kThinLinePresetTable[ThinLinePreset.standard]!.structureRunLength,
      );
      // 阈值被改后已经不属于任何档位，设置页应显示「自定义」。
      expect(detectThinLinePreset(out), isNull);
    });

    test('只选档位：展开成该档的裸参数，阈值就是表里的值', () {
      for (final ThinLinePreset preset in ThinLinePreset.values) {
        final PaperProfile out = applyCalibration(
          base,
          CalibrationAnswers(thinLinePreset: preset),
        );
        final ThinLinePresetParams expected = kThinLinePresetTable[preset]!;

        expect(out.threshold, expected.threshold, reason: '$preset');
        expect(out.protectStructureLines, expected.protectStructureLines,
            reason: '$preset');
        expect(out.promoteSubDotStrokes, expected.promoteSubDotStrokes,
            reason: '$preset');
        expect(detectThinLinePreset(out), preset, reason: '$preset');
      }
    });

    test('只答阈值：保护方式维持默认（标准档那一套）', () {
      final PaperProfile out = applyCalibration(
        base,
        const CalibrationAnswers(threshold: kAggressiveThreshold),
      );

      expect(out.threshold, kAggressiveThreshold);
      expect(out.protectStructureLines, base.protectStructureLines);
      expect(out.isCalibrated, isTrue);
    });
  });

  group('字号', () {
    test('正文字号按 D4 夹在 16~24 之间', () {
      expect(bodyFontFor(12), kBodyFontMinPx);
      expect(bodyFontFor(20), 20);
      expect(bodyFontFor(32), kBodyFontMaxPx);

      expect(
        applyCalibration(base, const CalibrationAnswers(minFontPx: 12)).bodyFontPx,
        kBodyFontMinPx,
      );
      final PaperProfile mid =
          applyCalibration(base, const CalibrationAnswers(minFontPx: 18));
      expect(mid.minFontPx, 18, reason: '最小可读字号记原始答案，不被夹');
      expect(mid.bodyFontPx, 18);
    });
  });

  group('describeProfileDiff', () {
    test('没改动时为空', () {
      expect(describeProfileDiff(base, base), isEmpty);
    });

    test('只列变了的字段，点数为整数时不显示小数点', () {
      final PaperProfile out = applyCalibration(
        base,
        const CalibrationAnswers(
          printableDotsWidth: 372,
          minFontPx: 18,
          thinLinePreset: ThinLinePreset.aggressive,
        ),
      );

      final List<String> diff = describeProfileDiff(base, out);

      expect(diff, contains('有效宽度：384 → 372'));
      expect(diff, contains('最小可读字号：20 → 18'));
      expect(diff, contains('正文字号：20 → 18'));
      expect(diff, contains('严格阈值：$kStrictThreshold → $kAggressiveThreshold'));
      expect(diff, contains('已校准：否 → 是'));
      expect(
        diff.any((String line) => line.contains('写入 pHYs')),
        isFalse,
        reason: '没变的字段不该出现',
      );
    });
  });

  group('候选集合', () {
    test('宽度候选的第一个就是校准条的出图宽度', () {
      expect(kWidthCandidates.first, kCalibrationStripWidth);
      expect(kWidthCandidates, orderedEquals(<int>[384, 378, 372, 366, 360]));
    });

    test('阈值候选为升序且在 0~255 内', () {
      for (int i = 1; i < kThresholdCandidates.length; i++) {
        expect(kThresholdCandidates[i], greaterThan(kThresholdCandidates[i - 1]));
      }
      for (final int value in kThresholdCandidates) {
        expect(value, inInclusiveRange(0, 255));
      }
    });
  });
}