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
    test('档位边界（纯像素预算，纹理放开）：384 点宽下 3472 点取 3×、7812 点取 2×、12000 点取 1×', () {
      // 传超大纹理放开约束，隔离出预算公式的档位边界；默认兜底 4096 的纹理
      // 行为由下面几条专项用例覆盖。
      final int tex = 1 << 30;
      expect(
        supersampleFactor(widthDots: 384, heightDots: 3472, maxTextureSize: tex),
        3,
      );
      expect(
        supersampleFactor(widthDots: 384, heightDots: 3473, maxTextureSize: tex),
        2,
      );
      expect(
        supersampleFactor(widthDots: 384, heightDots: 7812, maxTextureSize: tex),
        2,
      );
      expect(
        supersampleFactor(widthDots: 384, heightDots: 7813, maxTextureSize: tex),
        1,
      );
      expect(
        supersampleFactor(widthDots: 384, heightDots: 12000, maxTextureSize: tex),
        1,
      );
    });

    test('短内容恒取上限 3×，不越界', () {
      expect(supersampleFactor(widthDots: 384, heightDots: 1), 3);
      expect(supersampleFactor(widthDots: 384, heightDots: 100), 3);
    });

    test('宽高非正时回落到 1，不抛异常', () {
      expect(supersampleFactor(widthDots: 0, heightDots: 100), 1);
      expect(supersampleFactor(widthDots: 384, heightDots: 0), 1);
    });

    test('纹理上限收紧档位：1732 点高在 4096 上限下从 3× 降到 2×', () {
      // 真机 bug 复算：1732 点高按预算给 3×，物理高 5196 超过纹理上限 4096，
      // 引擎静默等比缩小（1152→908）炸出图断言；现在档位必须先被收紧。
      expect(
        supersampleFactor(
          widthDots: 384,
          heightDots: 1732,
          maxTextureSize: 4096,
        ),
        2,
      );
    });

    test('1× 也放不下纹理时返回 1，由调用方给出拆题报错', () {
      expect(
        supersampleFactor(
          widthDots: 384,
          heightDots: 5000,
          maxTextureSize: 4096,
        ),
        1,
      );
    });

    test('不传 maxTextureSize 时用兜底常数 4096 约束', () {
      // 4200 点高兜底下只能 1×（物理高 4200 仍超限，报错交给调用方）。
      expect(supersampleFactor(widthDots: 384, heightDots: 4200), 1);
      // 1732 点高兜底下与真值 4096 相同，取 2×。
      expect(supersampleFactor(widthDots: 384, heightDots: 1732), 2);
    });

    test('宽度也受纹理约束，但不越过像素预算档', () {
      // 宽度约束：2048 点宽在 4096 上限下最多 2×。
      expect(
        supersampleFactor(
          widthDots: 2048,
          heightDots: 100,
          maxTextureSize: 4096,
        ),
        2,
      );
      // 大纹理不放大档位：预算给 2× 时即便上限 8192 也仍是 2×。
      expect(
        supersampleFactor(
          widthDots: 384,
          heightDots: 3473,
          maxTextureSize: 8192,
        ),
        2,
      );
    });
  });
}
