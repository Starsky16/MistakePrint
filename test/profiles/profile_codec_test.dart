// P3 Profile 序列化测试（计划 P3 实施笔记 §3 提交 3）。
//
// 存档来自用户手机，可能被截断或被手工改过，所以这里的重点不是「能读回来」，
// 而是「读不回来时绝不抛」。

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mistake_print/profiles/paper_profile.dart';
import 'package:mistake_print/profiles/profile_codec.dart';

/// 一份每个字段都偏离默认值的档案：往返测试只有在这种数据上才有意义。
PaperProfile calibratedProfile() => kPaperangP1Default.copyWith(
      id: 'paperang-p2',
      name: '喵喵机 P2（已校准）',
      dpi: 300,
      paperWidthMm: 53.5,
      printableDotsWidth: 372,
      minFontPx: 22,
      bodyFontPx: 24,
      mathFontPx: 28,
      lineHeight: 1.45,
      threshold: 170,
      protectStructureLines: false,
      structureRunLength: 6,
      minLineWidthPx: 2,
      writePhys: false,
      oversizeStrategy: OversizeStrategy.scale,
      columns: 2,
      isCalibrated: true,
    );

void main() {
  test('往返一致：每个字段都原样回来', () {
    final PaperProfile source = calibratedProfile();
    final PaperProfile? restored = decodeProfileJson(encodeProfileJson(source));

    expect(restored, isNotNull);
    final PaperProfile p = restored!;
    expect(p.id, source.id);
    expect(p.name, source.name);
    expect(p.dpi, source.dpi);
    expect(p.paperWidthMm, source.paperWidthMm);
    expect(p.printableDotsWidth, source.printableDotsWidth);
    expect(p.minFontPx, source.minFontPx);
    expect(p.bodyFontPx, source.bodyFontPx);
    expect(p.mathFontPx, source.mathFontPx);
    expect(p.lineHeight, source.lineHeight);
    expect(p.threshold, source.threshold);
    expect(p.protectStructureLines, source.protectStructureLines);
    expect(p.structureRunLength, source.structureRunLength);
    expect(p.minLineWidthPx, source.minLineWidthPx);
    expect(p.writePhys, source.writePhys);
    expect(p.oversizeStrategy, source.oversizeStrategy);
    expect(p.columns, source.columns);
    expect(p.isCalibrated, source.isCalibrated);
  });

  test('默认档案往返同样一致', () {
    final PaperProfile? restored =
        decodeProfileJson(encodeProfileJson(kPaperangP1Default));
    expect(restored, isNotNull);
    expect(restored!.printableDotsWidth, kPaperangP1Default.printableDotsWidth);
    expect(restored.threshold, kPaperangP1Default.threshold);
    expect(restored.isCalibrated, isFalse);
  });

  test('不是 JSON、不是对象、版本不符：一律返回 null 而不抛', () {
    expect(decodeProfileJson(''), isNull);
    expect(decodeProfileJson(':'), isNull);
    expect(decodeProfileJson('{"version":1'), isNull, reason: '被截断的存档');
    expect(decodeProfileJson('[]'), isNull);
    expect(decodeProfileJson('"paperang-p1"'), isNull);
    expect(
      decodeProfileJson(jsonEncode(<String, Object?>{'version': 99})),
      isNull,
      reason: '别的版本写的存档不能按本版规则解释',
    );
    expect(decodeProfileJson('null'), isNull);
  });

  test('字段缺失或类型不对时逐字段回落到默认值', () {
    final PaperProfile? restored = decodeProfileJson(jsonEncode(<String, Object?>{
      'version': kProfileFormatVersion,
      'printableDotsWidth': '372', // 类型不对
      'bodyFontPx': 24, // 只给了这一个
    }));

    expect(restored, isNotNull, reason: '缺字段不算整份不可用');
    expect(restored!.printableDotsWidth, kPaperangP1Default.printableDotsWidth);
    expect(restored.bodyFontPx, 24);
    expect(restored.id, kPaperangP1Default.id);
  });

  test('整数写成浮点也能读（JSON 不区分 int/double）', () {
    final PaperProfile? restored = decodeProfileJson(jsonEncode(<String, Object?>{
      'version': kProfileFormatVersion,
      'printableDotsWidth': 372.0,
      'threshold': 170.0,
      'columns': 1.0,
    }));

    expect(restored!.printableDotsWidth, 372);
    expect(restored.threshold, 170);
    expect(restored.columns, 1);
  });

  test('不认识的 oversizeStrategy 名回落到默认策略', () {
    final PaperProfile? restored = decodeProfileJson(jsonEncode(<String, Object?>{
      'version': kProfileFormatVersion,
      'oversizeStrategy': 'warp',
    }));

    expect(restored!.oversizeStrategy, kPaperangP1Default.oversizeStrategy);
  });

  test('已知策略名照原样读回', () {
    final PaperProfile? restored = decodeProfileJson(jsonEncode(<String, Object?>{
      'version': kProfileFormatVersion,
      'oversizeStrategy': 'scale',
    }));

    expect(restored!.oversizeStrategy, OversizeStrategy.scale);
  });
}