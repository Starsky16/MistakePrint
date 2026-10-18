// P3 档位映射测试（计划 P3 实施笔记 §3 提交 3）。
//
// 锁死「档位 ↔ 裸参数」只有一处真相：表里的每一档反查得回自己，表外的组合一律
// 判为自定义，且展开档位不动档位以外的任何字段。

import 'package:flutter_test/flutter_test.dart';
import 'package:mistake_print/profiles/paper_profile.dart';
import 'package:mistake_print/profiles/presets.dart';
import 'package:mistake_print/render/raster/binarize.dart';

void main() {
  test('每个档位都在表里，且展开后能反查回自己', () {
    for (final ThinLinePreset preset in ThinLinePreset.values) {
      expect(
        kThinLinePresetTable.containsKey(preset),
        isTrue,
        reason: '档位 ${preset.name} 缺少裸参数，界面会展开成空操作',
      );
      expect(
        detectThinLinePreset(applyThinLinePreset(kPaperangP1Default, preset)),
        preset,
      );
    }
  });

  test('三档的裸参数两两不同，反查结果才唯一', () {
    // 用集合去重：若任意两档展开成同一组裸参数，反查就会出现歧义。
    final Set<String> signatures = <String>{};
    for (final ThinLinePreset preset in ThinLinePreset.values) {
      final ThinLinePresetParams p = kThinLinePresetTable[preset]!;
      signatures.add(
        '${p.threshold}|${p.protectStructureLines}|${p.structureRunLength}'
        '|${p.promoteSubDotStrokes}',
      );
    }
    expect(signatures.length, ThinLinePreset.values.length);
  });

  test('关闭档既不保护结构线也不做提升，标准档两项都做，激进档再抬严格阈值', () {
    final ThinLinePresetParams off = kThinLinePresetTable[ThinLinePreset.off]!;
    final ThinLinePresetParams standard =
        kThinLinePresetTable[ThinLinePreset.standard]!;
    final ThinLinePresetParams aggressive =
        kThinLinePresetTable[ThinLinePreset.aggressive]!;

    expect(off.protectStructureLines, isFalse);
    expect(off.promoteSubDotStrokes, isFalse);
    expect(off.threshold, kStrictThreshold);

    expect(standard.protectStructureLines, isTrue);
    expect(standard.promoteSubDotStrokes, isTrue);
    expect(standard.threshold, kStrictThreshold);

    // 激进档救的是灰度 164 的细竖画（计划 §5.3），阈值必须过 164。
    expect(aggressive.protectStructureLines, isTrue);
    expect(aggressive.promoteSubDotStrokes, isTrue);
    expect(aggressive.threshold, kAggressiveThreshold);
    expect(aggressive.threshold, greaterThan(164));
  });

  test('出厂默认档案就是「标准」档', () {
    expect(detectThinLinePreset(kPaperangP1Default), ThinLinePreset.standard);
  });

  test('展开档位只动档位管的那几个裸参数', () {
    final PaperProfile base = kPaperangP1Default.copyWith(
      printableDotsWidth: 372,
      bodyFontPx: 22,
      minFontPx: 22,
      writePhys: false,
      isCalibrated: true,
    );
    final PaperProfile applied =
        applyThinLinePreset(base, ThinLinePreset.aggressive);

    expect(applied.threshold, kAggressiveThreshold);
    expect(applied.promoteSubDotStrokes, isTrue);
    expect(applied.id, base.id);
    expect(applied.name, base.name);
    expect(applied.printableDotsWidth, 372);
    expect(applied.bodyFontPx, 22);
    expect(applied.mathFontPx, base.mathFontPx);
    expect(applied.writePhys, isFalse);
    expect(applied.isCalibrated, isTrue);
    expect(applied.oversizeStrategy, base.oversizeStrategy);
  });

  test('开发者改过裸参数后反查为 null（界面显示「自定义」），改回一整档仍能认出', () {
    expect(
      detectThinLinePreset(kPaperangP1Default.copyWith(threshold: 200)),
      isNull,
    );
    expect(
      detectThinLinePreset(
        kPaperangP1Default.copyWith(structureRunLength: 4),
      ),
      isNull,
    );
    expect(
      detectThinLinePreset(
        kPaperangP1Default.copyWith(protectStructureLines: false),
      ),
      isNull,
      reason: '只关保护、仍开着提升，不属于任何档位（关闭档两项都不做）',
    );
    expect(
      detectThinLinePreset(
        kPaperangP1Default.copyWith(
          protectStructureLines: false,
          promoteSubDotStrokes: false,
        ),
      ),
      ThinLinePreset.off,
      reason: '保护与提升都关掉正好落回「关闭」档，应当被认出来',
    );
  });

  group('P2/P2S 内置预设', () {
    test('P2 预设字段值（576 点 / 300 dpi，字号按 300/203 比例取整）', () {
      expect(kPaperangP2Default.id, 'paperang-p2');
      expect(kPaperangP2Default.name, '喵喵机 P2（出厂默认）');
      expect(kPaperangP2Default.dpi, 300);
      expect(kPaperangP2Default.paperWidthMm, 57);
      expect(kPaperangP2Default.printableDotsWidth, 576);
      expect(kPaperangP2Default.minFontPx, 21);
      expect(kPaperangP2Default.bodyFontPx, 27);
      expect(kPaperangP2Default.mathFontPx, 35);
      expect(kPaperangP2Default.lineHeight, 1.3);
      expect(kPaperangP2Default.threshold, kStrictThreshold);
      expect(kPaperangP2Default.protectStructureLines, isTrue);
      expect(kPaperangP2Default.structureRunLength, kStructureRunLength,
          reason: '档位表唯一真相约束：偏离表值会让细线增强对 P2 失效');
      expect(kPaperangP2Default.promoteSubDotStrokes, isTrue);
      expect(kPaperangP2Default.enhanceMinMax, isFalse);
      expect(kPaperangP2Default.enhanceClahe, isFalse);
      expect(kPaperangP2Default.minLineWidthPx, 1);
      expect(kPaperangP2Default.writePhys, isTrue);
      expect(kPaperangP2Default.oversizeStrategy, OversizeStrategy.lineBreak);
      expect(kPaperangP2Default.columns, 1);
      expect(kPaperangP2Default.isCalibrated, isFalse);
    });

    test('P2S 与 P2 除 id/name 外逐字段一致（同硬件两代，数值单源）', () {
      expect(kPaperangP2SDefault.id, 'paperang-p2s');
      expect(kPaperangP2SDefault.name, '喵喵机 P2S（出厂默认）');
      expect(kPaperangP2SDefault.dpi, kPaperangP2Default.dpi);
      expect(kPaperangP2SDefault.paperWidthMm, kPaperangP2Default.paperWidthMm);
      expect(
          kPaperangP2SDefault.printableDotsWidth,
          kPaperangP2Default.printableDotsWidth);
      expect(kPaperangP2SDefault.minFontPx, kPaperangP2Default.minFontPx);
      expect(kPaperangP2SDefault.bodyFontPx, kPaperangP2Default.bodyFontPx);
      expect(kPaperangP2SDefault.mathFontPx, kPaperangP2Default.mathFontPx);
      expect(kPaperangP2SDefault.lineHeight, kPaperangP2Default.lineHeight);
      expect(kPaperangP2SDefault.threshold, kPaperangP2Default.threshold);
      expect(kPaperangP2SDefault.protectStructureLines,
          kPaperangP2Default.protectStructureLines);
      expect(kPaperangP2SDefault.structureRunLength,
          kPaperangP2Default.structureRunLength);
      expect(kPaperangP2SDefault.promoteSubDotStrokes,
          kPaperangP2Default.promoteSubDotStrokes);
      expect(kPaperangP2SDefault.enhanceMinMax,
          kPaperangP2Default.enhanceMinMax);
      expect(kPaperangP2SDefault.enhanceClahe, kPaperangP2Default.enhanceClahe);
      expect(kPaperangP2SDefault.minLineWidthPx,
          kPaperangP2Default.minLineWidthPx);
      expect(kPaperangP2SDefault.writePhys, kPaperangP2Default.writePhys);
      expect(kPaperangP2SDefault.oversizeStrategy,
          kPaperangP2Default.oversizeStrategy);
      expect(kPaperangP2SDefault.columns, kPaperangP2Default.columns);
      expect(kPaperangP2SDefault.isCalibrated, kPaperangP2Default.isCalibrated);
    });

    test('两张 P2 预设也都落在「标准」细线档（设置页分段按钮正常点亮）', () {
      expect(detectThinLinePreset(kPaperangP2Default), ThinLinePreset.standard);
      expect(
          detectThinLinePreset(kPaperangP2SDefault), ThinLinePreset.standard);
    });

    test('内置机型表按 P1/P2/P2S 排列，按 id 查表命中，未知 id 返回 null', () {
      expect(
        kBuiltInProfiles.map((PaperProfile p) => p.id),
        <String>['paperang-p1', 'paperang-p2', 'paperang-p2s'],
      );
      expect(builtInProfileById('paperang-p2'), same(kPaperangP2Default));
      expect(builtInProfileById('paperang-p2s'), same(kPaperangP2SDefault));
      expect(builtInProfileById('custom-xxx'), isNull);
    });
  });
}

