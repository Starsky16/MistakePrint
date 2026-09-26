// 盒式降采样与超采样限流的单测（计划 §5.4a）。
//
// 用合成 RGBA 断言，不依赖渲染环境：降采样的取整与边界规则、限流公式的档位
// 边界都是明确常量，合成数据能把它们钉死。

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mistake_print/render/raster/downsample.dart';
import 'package:mistake_print/render/raster/raw_capture.dart';

/// 用灰度矩阵构造 RGBA：R=G=B=灰度值、A=255。
Uint8List grayRgba(List<List<int>> gray) {
  final int h = gray.length;
  final int w = gray.first.length;
  final Uint8List rgba = Uint8List(w * h * 4);
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      final int v = gray[y][x];
      final int i = (y * w + x) * 4;
      rgba[i] = v;
      rgba[i + 1] = v;
      rgba[i + 2] = v;
      rgba[i + 3] = 255;
    }
  }
  return rgba;
}

int grayAt(Uint8List rgba, int w, int x, int y) => rgba[(y * w + x) * 4];

void main() {
  group('盒式降采样', () {
    test('factor = 1 时原样返回，不做拷贝', () {
      final Uint8List src = grayRgba(<List<int>>[
        <int>[0, 255],
        <int>[255, 0],
      ]);
      expect(identical(boxDownsampleRgba(src, 2, 2, 1), src), isTrue);
    });

    test('factor = 2 时取 2×2 块算术平均', () {
      final Uint8List src = grayRgba(<List<int>>[
        <int>[0, 0, 255, 255],
        <int>[0, 0, 255, 255],
        <int>[255, 255, 0, 0],
        <int>[255, 255, 0, 0],
      ]);
      final Uint8List dst = boxDownsampleRgba(src, 4, 4, 2);

      expect(grayAt(dst, 2, 0, 0), 0);
      expect(grayAt(dst, 2, 1, 0), 255);
      expect(grayAt(dst, 2, 0, 1), 255);
      expect(grayAt(dst, 2, 1, 1), 0);
    });

    test('平均值四舍五入，1 与 2 的平均取 2', () {
      final Uint8List src = grayRgba(<List<int>>[
        <int>[1, 2],
        <int>[1, 2],
      ]);
      expect(grayAt(boxDownsampleRgba(src, 2, 2, 2), 1, 0, 0), 2);
    });

    test('尺寸不能整除时右/下边缘按实际像素数取平均', () {
      // 3×3 输入、factor 2 → 2×2 输出，右下块只有 1 个像素。
      final Uint8List src = grayRgba(<List<int>>[
        <int>[10, 20, 30],
        <int>[40, 50, 60],
        <int>[70, 80, 90],
      ]);
      final Uint8List dst = boxDownsampleRgba(src, 3, 3, 2);

      expect(grayAt(dst, 2, 0, 0), 30, reason: '(10+20+40+50)/4');
      expect(grayAt(dst, 2, 1, 0), 45, reason: '(30+60)/2');
      expect(grayAt(dst, 2, 0, 1), 75, reason: '(70+80)/2');
      expect(grayAt(dst, 2, 1, 1), 90, reason: '只剩一个像素');
    });

    test('alpha 与颜色通道一起取平均', () {
      // 2×1 的两点：alpha 0 与 255 → 平均 128。
      final Uint8List src = Uint8List.fromList(<int>[
        0, 0, 0, 0, //
        255, 255, 255, 255,
      ]);
      final Uint8List dst = boxDownsampleRgba(src, 2, 1, 2);
      expect(dst[3], 128);
    });

    test('RawCapture 版按同一取整规则收缩尺寸', () {
      final RawCapture cap = RawCapture(
        grayRgba(<List<int>>[
          <int>[0, 0, 0, 0, 0],
          <int>[0, 0, 0, 0, 0],
          <int>[0, 0, 0, 0, 0],
        ]),
        5,
        3,
      );
      final RawCapture out = boxDownsample(cap, 2);
      expect(out.width, 3, reason: 'ceil(5/2)');
      expect(out.height, 2, reason: 'ceil(3/2)');
      expect(out.rgba.length, 3 * 2 * 4);
    });
  });

  group('超采样限流', () {
    test('档位边界：384 点宽下 3472 点取 3×、7812 点取 2×、12000 点取 1×', () {
      expect(supersampleFactor(widthDots: 384, heightDots: 3472), 3);
      expect(supersampleFactor(widthDots: 384, heightDots: 3473), 2);
      expect(supersampleFactor(widthDots: 384, heightDots: 7812), 2);
      expect(supersampleFactor(widthDots: 384, heightDots: 7813), 1);
      expect(supersampleFactor(widthDots: 384, heightDots: 12000), 1);
    });

    test('短内容恒取上限 3×，不越界', () {
      expect(supersampleFactor(widthDots: 384, heightDots: 1), 3);
      expect(supersampleFactor(widthDots: 384, heightDots: 100), 3);
    });

    test('宽高非正时回落到 1，不抛异常', () {
      expect(supersampleFactor(widthDots: 0, heightDots: 100), 1);
      expect(supersampleFactor(widthDots: 384, heightDots: 0), 1);
    });
  });
}
