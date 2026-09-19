import 'dart:typed_data';

import 'raw_capture.dart';

/// 二值化严格阈值：笔画主体。
const int kStrictThreshold = 128;

/// 二值化宽松阈值：含抗锯齿边缘。
const int kLooseThreshold = 210;

/// 结构线判定的最小水平游程（像素）。
const int kStructureRunLength = 8;

/// 二值化为黑点矩阵（true = 打印黑点）。
///
/// [protectStructureLines] 打开时，对「宽松阈值下、严格阈值外」的像素做水平游程判定，
/// 游程不短于 [kStructureRunLength] 的整段强制变黑——用于救回被抗锯齿抹掉的分数线。
List<List<bool>> binarize(
  RawCapture cap, {
  bool protectStructureLines = false,
}) {
  final Uint8List lum = luminanceOf(cap);
  final int w = cap.width;
  final int h = cap.height;

  final List<List<bool>> black = List<List<bool>>.generate(
    h,
    (int y) => List<bool>.generate(w, (int x) => lum[y * w + x] < kStrictThreshold),
  );

  if (!protectStructureLines) {
    return black;
  }

  bool candidate(int x, int y) =>
      !black[y][x] && lum[y * w + x] < kLooseThreshold;

  for (int y = 0; y < h; y++) {
    int x = 0;
    while (x < w) {
      if (!candidate(x, y)) {
        x++;
        continue;
      }
      int end = x;
      while (end < w && candidate(end, y)) {
        end++;
      }
      if (end - x >= kStructureRunLength) {
        for (int i = x; i < end; i++) {
          black[y][i] = true;
        }
      }
      x = end;
    }
  }
  return black;
}

/// 统计黑点总数。
int countDark(List<List<bool>> black) {
  int dark = 0;
  for (final List<bool> row in black) {
    for (final bool v in row) {
      if (v) dark++;
    }
  }
  return dark;
}