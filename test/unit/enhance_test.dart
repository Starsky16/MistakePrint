// 增强算子（min-max 归一 + 亮区 CLAHE）的单测（计划 §2 A1）。
//
// 纯 Dart、逐像素，用已知灰度数组断言输出区间与分布，不依赖渲染环境。
// 两项的「参数事实」来自官方逆向报告（§5 V2/V3），实现为自研，见 enhance.dart 注释。

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mistake_print/render/raster/enhance.dart';

/// 用灰度数组构造亮度图（与 [luminanceOf] 的输出同形）。
Uint8List lum(List<int> values) => Uint8List.fromList(values);

void main() {
  group('增强：全关不变', () {
    test('两个开关都关时原样返回同一引用（逐字节一致的前提）', () {
      final Uint8List src = lum(<int>[0, 50, 100, 200, 255]);
      final Uint8List out = enhanceLuminance(src, 5, 1);
      expect(identical(out, src), isTrue);
    });
  });

  group('增强：min-max 归一', () {
    test('线性拉伸到 [0,248]', () {
      final Uint8List out = enhanceLuminance(
        lum(<int>[10, 20, 30, 40]),
        4,
        1,
        normalizeMinMax: true,
      );
      expect(out, <int>[0, 83, 165, 248]);
    });

    test('常量图无对比度可拉，原样返回', () {
      final Uint8List src = lum(<int>[128, 128, 128, 128]);
      final Uint8List out =
          enhanceLuminance(src, 4, 1, normalizeMinMax: true);
      expect(identical(out, src), isTrue);
    });
  });

  group('增强：亮区 CLAHE', () {
    test('亮部占比不超过一半时不触发', () {
      // 全 100：亮部（≥223）占比 0。
      final Uint8List src = lum(List<int>.filled(16, 100));
      final Uint8List out =
          enhanceLuminance(src, 4, 4, brightClahe: true);
      expect(identical(out, src), isTrue);
    });

    test('亮部占比过半时触发，输出长度不变且逐像素落在 [0,255]', () {
      // 64×64：80% 为 240（亮部），20% 为 200（较暗）。
      final List<int> values = List<int>.generate(
        64 * 64,
        (int i) => i < 64 * 64 * 8 ~/ 10 ? 240 : 200,
      );
      final Uint8List src = lum(values);
      final Uint8List out =
          enhanceLuminance(src, 64, 64, brightClahe: true);

      expect(identical(out, src), isFalse);
      expect(out.length, src.length);
      expect(out.every((int v) => v >= 0 && v <= 255), isTrue);
      expect(out, isNot(equals(src)), reason: '触发后至少应有一部分像素被重映射');
    });
  });

  group('增强：两项叠加', () {
    test('归一 + CLAHE 依次施加，接口稳定且结果合法', () {
      final List<int> values = List<int>.generate(
        64 * 64,
        (int i) => i < 64 * 64 * 8 ~/ 10 ? 220 : 30,
      );
      final Uint8List out = enhanceLuminance(
        lum(values),
        64,
        64,
        normalizeMinMax: true,
        brightClahe: true,
      );
      expect(out.length, values.length);
      expect(out.every((int v) => v >= 0 && v <= 255), isTrue);
    });
  });
}
