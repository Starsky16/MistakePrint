import 'dart:typed_data';

/// 增强算子的目标拉伸上界：官方 `ImgNormalizeMaxMin(img, 0, 0xF8)` 把灰度拉进
/// [0, 248]（逆向报告 §5 `PrinterImgBinV3`、§8 可复现参数表）。
///
/// 故意不拉到 255：留出 7 级余量，避免最亮处与白纸背景（纯白 255）贴死导致
/// 阈值判决把背景误判进笔画。
const int kNormalizeWhite = 0xF8;

/// 亮区判定阈值：`luminance >= kBrightLevel`（灰度 223）视为「亮部」。
///
/// 官方 `PrinterImgBinV2` 的亮区分支按直方图 bin 0xdf..0xff 统计亮部占比
/// （逆向报告 §5），此处用等价的亮度阈值表述。
const int kBrightLevel = 0xDF;

/// 亮区 CLAHE 的触发占比：亮部像素超过全图 50% 才启用（官方 V2 分支判据）。
const double kClaheBrightRatio = 0.5;

/// 亮区 CLAHE 的对比度限制（官方 `ImgCLAHE(4.0)`，逆向报告 §5/§8）。
const double kClaheClipLimit = 4.0;

/// CLAHE 的分块数（每边）。官方 native 实现未在报告中给出分块参数，这里取
/// 8×8 的标准分块——足够局部，又不至于在 384 点宽的图上切得过碎。
const int kClaheTilesPerAxis = 8;

/// 增强算子总入口：按需在 [luminance] 上依次施加 min-max 归一与亮区 CLAHE。
///
/// [luminance] 逐行排列，长度必须等于 `width * height`（[luminanceOf] 的产物）。
/// 两个开关都关时原样返回入参（引用不变），保证「全关 = 逐字节不变」。
/// 两项都作用于二值化**之前**的灰度、可叠加，参数事实对齐官方 V2/V3 两条增强路径
/// （计划 §2 A1 的重定位：只为我方自家出图质量服务，与官方 native T 无因果）。
Uint8List enhanceLuminance(
  Uint8List luminance,
  int width,
  int height, {
  bool normalizeMinMax = false,
  bool brightClahe = false,
}) {
  if (!normalizeMinMax && !brightClahe) return luminance;
  Uint8List out = luminance;
  if (normalizeMinMax) {
    out = _normalizeMinMax(out);
  }
  if (brightClahe) {
    out = _brightRegionClahe(out, width, height);
  }
  return out;
}

/// min-max 归一：把 [luminance] 线性拉伸到 [0, [kNormalizeWhite]]。
///
/// 对应官方 `ImgNormalizeMaxMin(img, 0, 0xF8)`。常量图（`max == min`，无对比度可
/// 拉）原样返回，避免除零；逐像素四舍五入。
Uint8List _normalizeMinMax(Uint8List luminance) {
  int min = 255;
  int max = 0;
  for (int i = 0; i < luminance.length; i++) {
    final int v = luminance[i];
    if (v < min) min = v;
    if (v > max) max = v;
  }
  if (max == min) return luminance;

  final Uint8List out = Uint8List(luminance.length);
  final int span = max - min;
  for (int i = 0; i < luminance.length; i++) {
    out[i] = (((luminance[i] - min) * kNormalizeWhite) + span ~/ 2) ~/ span;
  }
  return out;
}

/// 亮区 CLAHE：仅当亮部（`>= kBrightLevel`）占比超过 [kClaheBrightRatio] 时才做
/// 限制对比度自适应直方图均衡，否则原样返回。
///
/// 对齐官方 `PrinterImgBinV2` 的亮区分支判据（逆向报告 §5）。CLAHE 本身是标准的
/// 分块均衡 + 双线性插值 + 直方图裁剪（超过 [kClaheClipLimit] 的桶被削平后均摊），
/// 参数事实来自逆向报告，实现为纯 Dart 自研，不搬运任何参考实现代码（计划 §12 R1）。
Uint8List _brightRegionClahe(Uint8List luminance, int width, int height) {
  int bright = 0;
  for (int i = 0; i < luminance.length; i++) {
    if (luminance[i] >= kBrightLevel) bright++;
  }
  if (luminance.isEmpty || bright / luminance.length <= kClaheBrightRatio) {
    return luminance;
  }
  return _clahe(luminance, width, height);
}

/// 标准 CLAHE：把图切成 `kClaheTilesPerAxis × kClaheTilesPerAxis` 块，逐块建直方图、
/// 裁剪并累积成灰度映射曲线，块间用双线性插值取值。
Uint8List _clahe(Uint8List luminance, int width, int height) {
  final int cols = kClaheTilesPerAxis;
  final int rows = kClaheTilesPerAxis;

  // 每块像素数（整除边界，余数归入最后一块），裁剪阈值 = clip × 平均桶高。
  final List<Uint16List> maps = <Uint16List>[];
  for (int ty = 0; ty < rows; ty++) {
    final int y0 = (height * ty) ~/ rows;
    final int y1 = (height * (ty + 1)) ~/ rows;
    for (int tx = 0; tx < cols; tx++) {
      final int x0 = (width * tx) ~/ cols;
      final int x1 = (width * (tx + 1)) ~/ cols;
      maps.add(_tileMap(luminance, width, x0, y0, x1, y1));
    }
  }

  final Uint8List out = Uint8List(luminance.length);
  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      out[y * width + x] = _sampleGrid(
        maps,
        cols,
        rows,
        x,
        y,
        width,
        height,
        luminance[y * width + x],
      );
    }
  }
  return out;
}

/// 单块的直方图均衡映射表：裁剪 → 均摊超额 → 累加成 256 项 LUT。
///
/// 空块返回恒等映射（`lut[i] == i`）。
Uint16List _tileMap(
  Uint8List luminance,
  int width,
  int x0,
  int y0,
  int x1,
  int y1,
) {
  final Uint16List lut = Uint16List(256);
  final int count = (x1 - x0) * (y1 - y0);
  if (count == 0) {
    for (int i = 0; i < 256; i++) {
      lut[i] = i;
    }
    return lut;
  }

  final List<int> hist = List<int>.filled(256, 0);
  for (int y = y0; y < y1; y++) {
    final int rowBase = y * width;
    for (int x = x0; x < x1; x++) {
      hist[luminance[rowBase + x]]++;
    }
  }

  final int limit = (kClaheClipLimit * count / 256).round();
  int excess = 0;
  for (int i = 0; i < 256; i++) {
    if (hist[i] > limit) {
      excess += hist[i] - limit;
      hist[i] = limit;
    }
  }
  final int give = excess ~/ 256;
  final int remainder = excess % 256;
  for (int i = 0; i < 256; i++) {
    hist[i] += give + (i < remainder ? 1 : 0);
  }

  int cum = 0;
  for (int i = 0; i < 256; i++) {
    cum += hist[i];
    lut[i] = ((cum * 255) / count).round().clamp(0, 255);
  }
  return lut;
}

/// 在块网格间做双线性插值取值：横纵坐标先落到「块中心」构成的网格上，
/// 四个邻块的映射曲线各在像素灰度 [value] 处求值后线性混合。
int _sampleGrid(
  List<Uint16List> maps,
  int cols,
  int rows,
  int x,
  int y,
  int width,
  int height,
  int value,
) {
  // 块中心的归一化坐标（以块为单位的连续索引），落在 [0, cols-1]。
  final double gx = (x + 0.5) * cols / width - 0.5;
  final double gy = (y + 0.5) * rows / height - 0.5;

  final int bx = gx.floor();
  final int by = gy.floor();
  final double tx = gx - bx;
  final double ty = gy - by;
  final int x0 = bx.clamp(0, cols - 1);
  final int y0 = by.clamp(0, rows - 1);
  final int x1 = (bx + 1).clamp(0, cols - 1);
  final int y1 = (by + 1).clamp(0, rows - 1);

  final int v = maps[y0 * cols + x0][value];
  final int vx = maps[y0 * cols + x1][value];
  final int vy = maps[y1 * cols + x0][value];
  final int vxy = maps[y1 * cols + x1][value];

  final double top = v + (vx - v) * tx;
  final double bottom = vy + (vxy - vy) * tx;
  return (top + (bottom - top) * ty).round().clamp(0, 255);
}
