import 'dart:typed_data';

import 'raw_capture.dart';

/// 二值化严格阈值：笔画主体。
///
/// 1:1 光栅化下笔画覆盖率只有 0.36（灰度约 163），128 会把整条笔画丢掉；超采样把
/// 覆盖率还原准了之后，阈值取 150 才既能收住笔画主体、又不至于把边缘灰一起算黑
/// （计划 §5.4a）。
const int kStrictThreshold = 150;

/// 二值化宽松阈值：含抗锯齿边缘。
const int kLooseThreshold = 210;

/// 结构线判定的最小水平游程（像素）。
const int kStructureRunLength = 6;

/// 细线增强「激进」档使用的严格阈值。
///
/// 比 [kStrictThreshold] 再高 15：用于用户在实机上确认「标准档的细线还是发虚」之后。
/// 旧值 170 是 1:1 光栅化时代「把整列 1/3 灰的像素全算黑」的等价手段，那条路已被
/// v0.1.0 实机推翻（笔画糊、边缘全是台阶），见计划 §5.4a。
const int kAggressiveThreshold = 165;

/// 亚点笔画提升所需的最小墨量（点当量，1.0 = 整点全覆盖）。
///
/// T1 离线量测（S=3、阈值 150、有保护）：0.28 与 0.34、0.40 三档相比，0.28 的中文图
/// 与公式图的「孤立黑点占比 / 1 点游程占比」都最低；再往下就会把噪声级灰点也提升成
/// 黑点。
const double kPromoteMinMass = 0.28;

/// 亚点笔画提升允许的最大水平游程（像素）。
///
/// 只提升「窄灰带」：游程更长的灰带属于结构线，交给 [kStructureRunLength] 那条路，
/// 否则会把长横线的抗锯齿拖尾一点一点提升成断续的点。
const int kPromoteMaxRunLength = 2;

/// 二值化为黑点矩阵（true = 打印黑点）。
///
/// [strictThreshold] 决定「笔画主体」的取法，默认 [kStrictThreshold]；档位与
/// 开发者模式可以改它，但宽松阈值是保护机制的内部定义，不对外开放。
///
/// [protectStructureLines] 打开时，对「宽松阈值下、严格阈值外」的像素做水平游程判定，
/// 游程不短于 [structureRunLength] 的整段强制变黑——用于救回被抗锯齿抹掉的分数线。
///
/// [promoteSubDotStrokes] 打开时做**亚点笔画提升**：把「比严格阈值浅、但墨量够
/// [kPromoteMinMass] 个点」的窄灰带（游程不超过 [kPromoteMaxRunLength]）规则化成
/// **1 点宽**的实线。超采样后细竖画仍是覆盖率约 0.4 的灰带，只抬阈值救不回来
/// （覆盖率 0.4 的像素灰度约 153，落在 150 之外），提升把它按位置还原成实心笔画，
/// 而不是丢掉或糊成台阶（计划 §5.4a）。
List<List<bool>> binarize(
  RawCapture cap, {
  bool protectStructureLines = false,
  int strictThreshold = kStrictThreshold,
  int structureRunLength = kStructureRunLength,
  bool promoteSubDotStrokes = false,
}) {
  final Uint8List lum = luminanceOf(cap);
  final int w = cap.width;
  final int h = cap.height;

  final List<List<bool>> black = List<List<bool>>.generate(
    h,
    (int y) =>
        List<bool>.generate(w, (int x) => lum[y * w + x] < strictThreshold),
  );

  if (protectStructureLines) {
    _forEachGrayRun(lum, black, w, h, (int y, int start, int end) {
      if (end - start >= structureRunLength) {
        for (int i = start; i < end; i++) {
          black[y][i] = true;
        }
      }
    });
  }

  if (promoteSubDotStrokes) {
    _forEachGrayRun(lum, black, w, h, (int y, int start, int end) {
      if (end - start > kPromoteMaxRunLength) return;
      double mass = 0;
      int darkest = start;
      int darkestInk = -1;
      for (int i = start; i < end; i++) {
        final int ink = 255 - lum[y * w + i];
        mass += ink / 255;
        if (ink > darkestInk) {
          darkestInk = ink;
          darkest = i;
        }
      }
      if (mass >= kPromoteMinMass) {
        black[y][darkest] = true;
      }
    });
  }
  return black;
}

/// 逐行扫描「非黑、但在宽松阈值以内」的灰像素游程，逐个交给 [onRun]。
///
/// 结构线保护与亚点笔画提升用的是同一套游程定义，放一处保证两者的「游程」含义
/// 不会漂开。
void _forEachGrayRun(
  Uint8List lum,
  List<List<bool>> black,
  int w,
  int h,
  void Function(int y, int start, int end) onRun,
) {
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
      onRun(y, x, end);
      x = end;
    }
  }
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
