// 二值化与长游程线宽保护的单测（计划 §5.3）。
//
// 用合成灰度图断言，不依赖渲染环境：保护机制的阈值与游程长度都是明确常量，
// 合成图能把「救回 / 不救回」的边界钉死。

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mistake_print/render/raster/binarize.dart';
import 'package:mistake_print/render/raster/raw_capture.dart';

/// 用灰度矩阵构造一次「捕获结果」：R=G=B=灰度值，A=255。
RawCapture grayCapture(List<List<int>> gray) {
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
  return RawCapture(rgba, w, h);
}

/// 单行全白打底，[start, end) 区间填 [value]。
List<List<int>> oneRow(
  int width, {
  required int value,
  required int start,
  required int end,
}) {
  final List<int> row = List<int>.filled(width, 255);
  for (int x = start; x < end; x++) {
    row[x] = value;
  }
  return <List<int>>[row];
}

void main() {
  group('二值化：阈值', () {
    test('严格阈值 150：低于它才是黑', () {
      expect(
        binarize(grayCapture(
                oneRow(10, value: kStrictThreshold - 1, start: 0, end: 10)))
            .single
            .every((bool v) => v),
        isTrue,
      );
      expect(
        binarize(grayCapture(oneRow(10, value: kStrictThreshold, start: 0, end: 10)))
            .single
            .any((bool v) => v),
        isFalse,
      );
    });

    test('strictThreshold 可调：抬高后原灰度值直接入黑', () {
      final RawCapture cap = grayCapture(oneRow(10, value: 150, start: 0, end: 10));
      expect(countDark(binarize(cap)), 0);
      expect(countDark(binarize(cap, strictThreshold: 160)), 10);
    });

    test('未开保护时浅灰不参与判定', () {
      final RawCapture cap = grayCapture(oneRow(20, value: 180, start: 2, end: 12));
      expect(countDark(binarize(cap)), 0);
    });
  });

  group('二值化：长游程线宽保护', () {
    test('长度 ≥kStructureRunLength 的浅灰游程被整段救回，游程外不受影响', () {
      final RawCapture cap = grayCapture(oneRow(20, value: 180, start: 2, end: 12));
      final List<List<bool>> protectedBlack = binarize(cap, protectStructureLines: true);

      expect(countDark(protectedBlack), 10);
      expect(longestDarkRun(protectedBlack), 10, reason: '救回后应是连通的一段');
      expect(protectedBlack.single[0], isFalse);
      expect(protectedBlack.single[19], isFalse);
    });

    test('长度不足 kStructureRunLength 的浅灰游程不救回（避免糊字）', () {
      final int shortRun = kStructureRunLength - 1;
      final RawCapture cap =
          grayCapture(oneRow(20, value: 180, start: 2, end: 2 + shortRun));
      expect(countDark(binarize(cap, protectStructureLines: true)), 0);
    });

    test('长度恰为 kStructureRunLength 是边界，应被救回', () {
      final RawCapture cap = grayCapture(
          oneRow(20, value: 180, start: 2, end: 2 + kStructureRunLength));
      expect(
        countDark(binarize(cap, protectStructureLines: true)),
        kStructureRunLength,
      );
    });

    test('宽松阈值 210：209 入选，210 及以上不入选', () {
      final RawCapture inside = grayCapture(oneRow(20, value: 209, start: 2, end: 20));
      expect(countDark(binarize(inside, protectStructureLines: true)), 18);

      final RawCapture outside = grayCapture(oneRow(20, value: 210, start: 2, end: 20));
      expect(countDark(binarize(outside, protectStructureLines: true)), 0);
    });

    test('纯黑点会打断游程判定，不会把整行连成一片', () {
      final List<int> row = List<int>.filled(20, 255);
      row[0] = 0;
      for (int x = 1; x < 6; x++) {
        row[x] = 180;
      }
      final List<List<bool>> black =
          binarize(grayCapture(<List<int>>[row]), protectStructureLines: true);

      expect(countDark(black), 1, reason: '只有那个纯黑像素');
      expect(longestDarkRun(black), 1);
    });

    test('已黑的核心 + 一侧浅灰长边缘 → 保护后整段连通', () {
      // 模拟分数线：中间是实心黑线，右侧是抗锯齿拖尾。
      final List<int> row = List<int>.filled(40, 255);
      for (int x = 3; x < 8; x++) {
        row[x] = 190; // 左边缘 5 点，短于阈值，不救回
      }
      for (int x = 8; x < 28; x++) {
        row[x] = 100; // 核心 20 点，本来就黑
      }
      for (int x = 28; x < 38; x++) {
        row[x] = 190; // 右边缘 10 点，救回后与核心连成 30 点
      }

      final List<List<bool>> black =
          binarize(grayCapture(<List<int>>[row]), protectStructureLines: true);

      expect(longestDarkRun(black), 30, reason: '核心 20 点 + 右边缘 10 点应连通');
      expect(black.single[7], isFalse, reason: '左边缘过短，不应被救回');
      expect(black.single[37], isTrue);
      expect(black.single[38], isFalse);
    });
  });

  group('二值化：亚点笔画提升', () {
    test('窄灰带墨量够时被提升成 1 点宽的实线', () {
      // 灰度 160 比严格阈值浅，只靠阈值一个黑点都没有。
      final RawCapture cap = grayCapture(oneRow(20, value: 160, start: 5, end: 7));
      expect(countDark(binarize(cap)), 0, reason: '未开提升时不该有黑点');

      final List<List<bool>> promoted =
          binarize(cap, promoteSubDotStrokes: true);
      expect(countDark(promoted), 1, reason: '只提升成 1 点，不整段涂黑');
      expect(longestDarkRun(promoted), 1);
    });

    test('游程超过 kPromoteMaxRunLength 的灰带不提升（交给长游程保护那条路）', () {
      final RawCapture cap = grayCapture(
          oneRow(20, value: 160, start: 5, end: 5 + kPromoteMaxRunLength + 1));
      expect(countDark(binarize(cap, promoteSubDotStrokes: true)), 0);
    });

    test('墨量不足 kPromoteMinMass 的浅灰点不提升，避免把噪声变黑点', () {
      // 灰度 205 的 1 点墨量 0.196，低于 0.28。
      final RawCapture cap = grayCapture(oneRow(20, value: 205, start: 5, end: 6));
      expect(countDark(binarize(cap, promoteSubDotStrokes: true)), 0);
    });

    test('提升落在游程里最深的那一个像素上', () {
      final List<int> row = List<int>.filled(20, 255);
      row[5] = 205;
      row[6] = 170; // 更深，应被选中
      final List<List<bool>> promoted = binarize(
        grayCapture(<List<int>>[row]),
        promoteSubDotStrokes: true,
      );

      expect(promoted.single[6], isTrue);
      expect(promoted.single[5], isFalse);
      expect(countDark(promoted), 1);
    });
  });

  group('二值化：统计工具', () {
    test('countDark 与 longestDarkRun 在多行上取值正确', () {
      final List<List<int>> gray = <List<int>>[
        <int>[0, 0, 255, 0],
        <int>[255, 255, 255, 255],
        <int>[0, 0, 0, 0],
      ];
      final List<List<bool>> black = binarize(grayCapture(gray));

      expect(countDark(black), 7);
      expect(longestDarkRun(black), 4);
    });
  });
}