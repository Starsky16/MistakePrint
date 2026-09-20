import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import 'binarize.dart';
import 'raw_capture.dart';

/// 默认 dpi（喵喵机 P1 为 203 → 8 点/mm），用于写入 PNG 的 pHYs 块。
const int kDpi = 203;

/// 把黑点矩阵编码成 1-bit 灰度 PNG（bitDepth=1 / colorType=0）。
Uint8List encodeBitmap(List<List<bool>> black, {required bool withPhys}) {
  final int h = black.length;
  final int w = black.first.length;
  final img.Image out = img.Image(
    width: w,
    height: h,
    numChannels: 1,
    format: img.Format.uint1,
  );
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      final int v = black[y][x] ? 0 : 255;
      out.setPixelRgb(x, y, v, v, v);
    }
  }
  final int dark = countDark(black);
  debugPrint(
    '[矩阵] ${w}x$h black=$dark (${(dark * 100 / (w * h)).toStringAsFixed(2)}%)',
  );
  return _pngEncoder(withPhys).encode(out);
}

/// 把捕获结果编码成 8-bit 灰度 PNG，用于观察 App 是否做抖动。
Uint8List encodeGray(RawCapture cap, {required bool withPhys}) {
  final Uint8List lum = luminanceOf(cap);
  final img.Image out = img.Image(
    width: cap.width,
    height: cap.height,
    numChannels: 1,
    format: img.Format.uint8,
  );
  for (int y = 0; y < cap.height; y++) {
    for (int x = 0; x < cap.width; x++) {
      final int v = lum[y * cap.width + x];
      out.setPixelRgb(x, y, v, v, v);
    }
  }
  return _pngEncoder(withPhys).encode(out);
}

/// 顶层 encodePng() 不接受 pixelDimensions，写 pHYs 必须直接构造 PngEncoder。
img.PngEncoder _pngEncoder(bool withPhys) => img.PngEncoder(
      filter: img.PngFilter.none,
      level: 6,
      pixelDimensions: withPhys ? img.PngPhysicalPixelDimensions.dpi(kDpi) : null,
    );