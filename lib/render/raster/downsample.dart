import 'dart:math' as math;
import 'dart:typed_data';

import 'raw_capture.dart';

/// 超采样倍率上限。
///
/// 1:1 光栅化下笔画覆盖率只有 0.36，硬阈值只能「丢掉整列」或「把 1/3 灰的像素
/// 全算黑」二选一，两条路都到不了能用（计划 §5.4a）。3× 后笔画会变成覆盖率准确
/// 的灰带，再由判决规则规则化成 1 点宽的实线。
const int kSupersampleMaxFactor = 3;

/// 超采样后的**物理像素总数**预算。
///
/// 物理像素数 = `点阵宽 × 点阵高 × S²`，因此 `S ≤ sqrt(预算 / (宽 × 高))`。
/// 3× 配上 12000 点的最大高度时，`ui.Image`、`toByteData`、跨 isolate 拷贝、
/// 灰度缓冲与黑点矩阵逐项相加约 870MB，必然 OOM。按总像素数限流后峰值降到百 MB
/// 量级：384 点宽下 ≤3472 点取 3×、≤7812 点取 2×、更长取 1×。
const int kSupersamplePixelBudget = 12000000;

/// 按总像素预算推出本次出图的超采样倍率。
///
/// 高内容自动降精度（计划 §5.4a 待拍板第 5 项），宁可细线质量回落也不 OOM。
int supersampleFactor({required int widthDots, required int heightDots}) {
  if (widthDots <= 0 || heightDots <= 0) return 1;
  final double raw =
      math.sqrt(kSupersamplePixelBudget / (widthDots * heightDots));
  return raw.floor().clamp(1, kSupersampleMaxFactor);
}

/// 盒式降采样：把 `factor × factor` 的像素块取算术平均。
///
/// 输入输出都是逐行 RGBA；输出尺寸为 `ceil(srcW/factor) × ceil(srcH/factor)`，
/// 右边缘与下边缘不足一个块时按实际像素数取平均。**盒式是唯一可用的核**：
/// `FilterQuality.high`（Catmull-Rom）有振铃与过冲，会在笔画两侧造出假灰边；
/// 高斯核会把 1 点宽线的覆盖率从 1.0 压到 0.44，等于自废超采样。
///
/// [factor] ≤ 1 时原样返回，不做拷贝。
Uint8List boxDownsampleRgba(Uint8List src, int srcW, int srcH, int factor) {
  if (factor <= 1) return src;
  final int dstW = (srcW + factor - 1) ~/ factor;
  final int dstH = (srcH + factor - 1) ~/ factor;
  final Uint8List dst = Uint8List(dstW * dstH * 4);

  for (int dy = 0; dy < dstH; dy++) {
    final int y0 = dy * factor;
    final int y1 = math.min(y0 + factor, srcH);
    for (int dx = 0; dx < dstW; dx++) {
      final int x0 = dx * factor;
      final int x1 = math.min(x0 + factor, srcW);
      int r = 0;
      int g = 0;
      int b = 0;
      int a = 0;
      for (int y = y0; y < y1; y++) {
        int i = (y * srcW + x0) * 4;
        for (int x = x0; x < x1; x++) {
          r += src[i];
          g += src[i + 1];
          b += src[i + 2];
          a += src[i + 3];
          i += 4;
        }
      }
      final int n = (y1 - y0) * (x1 - x0);
      final int o = (dy * dstW + dx) * 4;
      dst[o] = (r + n ~/ 2) ~/ n;
      dst[o + 1] = (g + n ~/ 2) ~/ n;
      dst[o + 2] = (b + n ~/ 2) ~/ n;
      dst[o + 3] = (a + n ~/ 2) ~/ n;
    }
  }
  return dst;
}

/// [RawCapture] 版的盒式降采样，尺寸按上面的取整规则收缩。
RawCapture boxDownsample(RawCapture src, int factor) {
  if (factor <= 1) return src;
  final int w = (src.width + factor - 1) ~/ factor;
  final int h = (src.height + factor - 1) ~/ factor;
  return RawCapture(boxDownsampleRgba(src.rgba, src.width, src.height, factor), w, h);
}
