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
    test('只答最小可读字号：只记下限，正文保持档案原值', () {
      final PaperProfile out =
          applyCalibration(base, const CalibrationAnswers(minFontPx: 16));

      expect(out.minFontPx, 16);
      expect(out.bodyFontPx, base.bodyFontPx, reason: '正文由它自己那一项决定');
      expect(out.isCalibrated, isTrue);
    });

    test('两项各自独立：(14, 18) 这种组合能一次产出', () {
      final PaperProfile out = applyCalibration(
        base,
        const CalibrationAnswers(minFontPx: 14, bodyFontPx: 18),
      );

      expect(out.minFontPx, 14);
      expect(out.bodyFontPx, 18);
      expect(out.isCalibrated, isTrue);
    });

    test('正文字号按 D4 夹在 16~24 之间', () {
      expect(resolveBodyFont(12, 0), kBodyFontMinPx);
      expect(resolveBodyFont(20, 0), 20);
      expect(resolveBodyFont(32, 0), kBodyFontMaxPx);

      expect(
        applyCalibration(base, const CalibrationAnswers(bodyFontPx: 12)).bodyFontPx,
        kBodyFontMinPx,
      );
      expect(
        applyCalibration(base, const CalibrationAnswers(bodyFontPx: 30)).bodyFontPx,
        kBodyFontMaxPx,
      );
    });

    test('正文不得小于最小可读字号（与设置页同一条约束）', () {
      expect(resolveBodyFont(18, 22), 22, reason: '下限更高时由下限兜住');
      expect(resolveBodyFont(18, 14), 18, reason: '下限更低时按用户选的来');

      final PaperProfile out = applyCalibration(
        base,
        const CalibrationAnswers(minFontPx: 22, bodyFontPx: 18),
      );
      expect(out.minFontPx, 22);
      expect(out.bodyFontPx, 22);
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
          minFontPx: 20,
          bodyFontPx: 20,
          thinLinePreset: ThinLinePreset.aggressive,
        ),
      );

      final List<String> diff = describeProfileDiff(base, out);

      // 「改前」一侧都按出厂档案的现值拼，避免默认值一改这条就红。
      expect(diff, contains('有效宽度：${base.printableDotsWidth} → 372'));
      expect(diff, contains('最小可读字号：${base.minFontPx.toInt()} → 20'));
      expect(diff, contains('正文字号：${base.bodyFontPx.toInt()} → 20'));
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

    test('正文字号候选升序、都在允许区间内，且包含出厂正文', () {
      for (int i = 1; i < kBodyFontCandidates.length; i++) {
        expect(kBodyFontCandidates[i], greaterThan(kBodyFontCandidates[i - 1]));
      }
      for (final double value in kBodyFontCandidates) {
        expect(value, inInclusiveRange(kBodyFontMinPx, kBodyFontMaxPx));
      }
      expect(kBodyFontCandidates, contains(base.bodyFontPx),
          reason: '出厂的正文档必须是可选之一，否则用户没法在向导里保持它');
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