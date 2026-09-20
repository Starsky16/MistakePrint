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
        '${p.threshold}|${p.protectStructureLines}|${p.structureRunLength}',
      );
    }
    expect(signatures.length, ThinLinePreset.values.length);
  });

  test('关闭档不保护结构线，标准档保护，激进档同时抬高严格阈值', () {
    final ThinLinePresetParams off = kThinLinePresetTable[ThinLinePreset.off]!;
    final ThinLinePresetParams standard =
        kThinLinePresetTable[ThinLinePreset.standard]!;
    final ThinLinePresetParams aggressive =
        kThinLinePresetTable[ThinLinePreset.aggressive]!;

    expect(off.protectStructureLines, isFalse);
    expect(off.threshold, kStrictThreshold);

    expect(standard.protectStructureLines, isTrue);
    expect(standard.threshold, kStrictThreshold);

    // 激进档救的是灰度 164 的细竖画（计划 §5.3），阈值必须过 164。
    expect(aggressive.protectStructureLines, isTrue);
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
    expect(applied.id, base.id);
    expect(applied.name, base.name);
    expect(applied.printableDotsWidth, 372);
    expect(applied.bodyFontPx, 22);
    expect(applied.mathFontPx, base.mathFontPx);
    expect(applied.writePhys, isFalse);
    expect(applied.isCalibrated, isTrue);
    expect(applied.oversizeStrategy, base.oversizeStrategy);
  });

  test('开发者改过裸参数后反查为 null（界面显示「自定义」）', () {
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
      ThinLinePreset.off,
      reason: '只关保护正好落回「关闭」档，应当被认出来',
    );
  });
}

