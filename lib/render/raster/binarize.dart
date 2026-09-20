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
/// [strictThreshold] 决定「笔画主体」的取法，默认 [kStrictThreshold]；档位与
/// 开发者模式可以改它，但宽松阈值与游程长度是保护机制的内部定义，不对外开放。
///
/// [protectStructureLines] 打开时，对「宽松阈值下、严格阈值外」的像素做水平游程判定，
/// 游程不短于 [kStructureRunLength] 的整段强制变黑——用于救回被抗锯齿抹掉的分数线。
///
/// 已知限制（P2 实测，待 P3 校准定夺）：保护只判水平走向，救不回**细竖画**。
/// 例如行内公式 `\frac{x}{2}+\frac{1}{x}` 的加号，横画是纯黑 0（16 点长），
/// 竖画整列恒为灰度 164、水平游程仅 2 点，严格阈值下被整条丢弃，肉眼读成减号。
/// 而 CJK 文字的竖画同样落在 164，任何一种能救回它的方案都会让全图墨量涨约 29%
/// （迟滞阈值取 170 时 100% 救回，代价见计划 §5.3），故默认不启用。
List<List<bool>> binarize(
  RawCapture cap, {
  bool protectStructureLines = false,
  int strictThreshold = kStrictThreshold,
}) {
  final Uint8List lum = luminanceOf(cap);
  final int w = cap.width;
  final int h = cap.height;

  final List<List<bool>> black = List<List<bool>>.generate(
    h,
    (int y) =>
        List<bool>.generate(w, (int x) => lum[y * w + x] < strictThreshold),
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

/// 最长水平黑游程（点数），用于判定结构线是否连通、无断点。
int longestDarkRun(List<List<bool>> black) {
  int longest = 0;
  for (final List<bool> row in black) {
    int run = 0;
    for (final bool v in row) {
      run = v ? run + 1 : 0;
      if (run > longest) longest = run;
    }
  }
  return longest;
}