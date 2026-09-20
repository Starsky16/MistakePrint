// 标定图 A~E 生成器：开发期离线自检，产物不入库。
//
// 运行：flutter test test/calibration/generate_calibration_test.dart
// 输出：D:\code\temp\calibration\*.png
//
// 两个必须记住的坑：
// 1. toImage() 与 toByteData() 必须都放在 tester.runAsync() 内，放 fake-async 区会永久挂起。
// 2. 测试环境不会自动注册 pubspec 里声明的字体，必须用 FontLoader 手动加载，
//    否则文本会退化成 Ahem 方块字体，标定图毫无意义。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mistake_print/calibration/calibration_figures.dart';
import 'package:mistake_print/render/raster/binarize.dart';
import 'package:mistake_print/render/raster/png_encode.dart';
import 'package:mistake_print/render/raster/raw_capture.dart';

import '../support/png_file.dart';
import '../support/render_capture.dart';
import '../support/test_fonts.dart';

/// 输出目录（仓库外，不入库）。
const String kOutDir = r'D:\code\temp\calibration';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await loadTestFonts();
  });

  testWidgets('出图 A：点阵宽度标尺', (WidgetTester tester) async {
    final RawCapture cap = await renderCapture(tester, figureA());
    _reportSize('A', cap);

    writePng(kOutDir, 'A-width-ruler-1bit-phys.png', encodeBitmap(binarize(cap), withPhys: true));
    writePng(kOutDir, 'A-width-ruler-1bit-nophys.png', encodeBitmap(binarize(cap), withPhys: false));
  });

  testWidgets('出图 B：字号与线宽/灰度阶梯', (WidgetTester tester) async {
    final RawCapture cap = await renderCapture(tester, figureB());
    _reportSize('B', cap);

    writePng(kOutDir, 'B-font-ladder-1bit.png', encodeBitmap(binarize(cap), withPhys: true));
    writePng(kOutDir, 'B-font-ladder-gray.png', encodeGray(cap, withPhys: true));

    // 2× 放大灰度版：判定 App 遇到高分辨率图是缩放还是裁切。
    final RawCapture cap2x = await renderCapture(tester, figureB(), pixelRatio: 2.0);
    _reportSize('B(2x)', cap2x);
    writePng(kOutDir, 'B-font-ladder-2x-gray.png', encodeGray(cap2x, withPhys: true));
  });

  testWidgets('出图 C：细线保真', (WidgetTester tester) async {
    final RawCapture c1 = await renderCapture(tester, figureC1());
    _reportSize('C1', c1);
    writePng(kOutDir, 'C1-fraction-ladder-strict.png', encodeBitmap(binarize(c1), withPhys: true));
    writePng(
      kOutDir,
      'C1-fraction-ladder-protected.png',
      encodeBitmap(binarize(c1, protectStructureLines: true), withPhys: true),
    );
    writePng(kOutDir, 'C1-fraction-ladder-gray.png', encodeGray(c1, withPhys: true));

    final RawCapture c2 = await renderCapture(tester, figureC2());
    _reportSize('C2', c2);
    writePng(kOutDir, 'C2-nested-root-script-1bit.png', encodeBitmap(binarize(c2), withPhys: true));
    writePng(kOutDir, 'C2-nested-root-script-gray.png', encodeGray(c2, withPhys: true));

    final RawCapture c3 = await renderCapture(tester, figureC3());
    _reportSize('C3', c3);
    writePng(kOutDir, 'C3-table-checker-1bit.png', encodeBitmap(binarize(c3), withPhys: true));
    writePng(kOutDir, 'C3-table-checker-gray.png', encodeGray(c3, withPhys: true));
  });

  testWidgets('出图 D：Unicode 覆盖表', (WidgetTester tester) async {
    final RawCapture noto = await renderCapture(
      tester,
      figureD(symbolFont: false, title: '图 D-1 正文通道：Noto Sans SC'),
    );
    _reportSize('D-Noto', noto);
    writePng(kOutDir, 'D-unicode-noto-1bit.png', encodeBitmap(binarize(noto), withPhys: true));

    final RawCapture stix = await renderCapture(
      tester,
      figureD(symbolFont: true, title: '图 D-2 数学通道：STIX Two Math'),
    );
    _reportSize('D-STIX', stix);
    writePng(kOutDir, 'D-unicode-stix-1bit.png', encodeBitmap(binarize(stix), withPhys: true));
  });

  testWidgets('出图 E：App 处理行为探针', (WidgetTester tester) async {
    final RawCapture ladder = await renderCapture(tester, figureEGrayLadder());
    _reportSize('E-gray', ladder);
    writePng(kOutDir, 'E-gray-ladder-1bit.png', encodeBitmap(binarize(ladder), withPhys: true));
    writePng(kOutDir, 'E-gray-ladder-gray.png', encodeGray(ladder, withPhys: true));

    final RawCapture oversize = await renderCapture(
      tester,
      figureEOversize(),
      surface: const Size(1024, 200),
    );
    _reportSize('E-oversize', oversize);
    writePng(kOutDir, 'E-oversize-1024-1bit.png', encodeBitmap(binarize(oversize), withPhys: true));

    final RawCapture tall = await renderCapture(
      tester,
      figureETall(),
      surface: const Size(300, 3100),
    );
    _reportSize('E-tall', tall);
    writePng(kOutDir, 'E-tall-300x3000-1bit.png', encodeBitmap(binarize(tall), withPhys: true));
  });

  testWidgets('出图 C3 抖动探测（独立成图便于对照）', (WidgetTester tester) async {
    final RawCapture probe = await renderCapture(tester, figureC3());
    writePng(kOutDir, 'E-dither-probe-1bit.png', encodeBitmap(binarize(probe), withPhys: true));
    writePng(kOutDir, 'E-dither-probe-gray.png', encodeGray(probe, withPhys: true));
  });

  // 交付前自检：直接在黑点矩阵上断言，避免把空图/坏图打出去浪费纸。
  testWidgets('自检：图的像素特征', (WidgetTester tester) async {
    final List<List<bool>> a = binarize(await renderCapture(tester, figureA()));
    expect(a[0].every((bool v) => v), isTrue, reason: '图 A 顶边应全黑');
    expect(a.last.every((bool v) => v), isTrue, reason: '图 A 底边应全黑');
    expect(a.every((List<bool> r) => r.first), isTrue, reason: '图 A 左边应全黑');
    expect(a.every((List<bool> r) => r.last), isTrue, reason: '图 A 右边应全黑');

    // 棋盘格是 1px 细线最脆弱的地方，黑白应接近 1:1。
    final List<List<bool>> c3 = binarize(await renderCapture(tester, figureC3()));
    int checkerDark = 0;
    for (int y = 120; y < 216; y++) {
      for (int x = 6; x < 102; x++) {
        if (c3[y][x]) checkerDark++;
      }
    }
    final double ratio = checkerDark / (96 * 96);
    debugPrint('[自检] C3 棋盘区黑点比例=${(ratio * 100).toStringAsFixed(1)}%');
    expect(ratio, greaterThan(0.35));
    expect(ratio, lessThan(0.65));

    // 结构线保护必须真的救回像素，否则说明保护没生效。
    final RawCapture c1 = await renderCapture(tester, figureC1());
    final int strictDark = countDark(binarize(c1));
    final int protectedDark = countDark(binarize(c1, protectStructureLines: true));
    debugPrint('[自检] C1 严格图黑点=$strictDark 保护图黑点=$protectedDark');
    expect(protectedDark, greaterThan(strictDark), reason: '结构线保护未生效');
  });
}

void _reportSize(String tag, RawCapture cap) {
  debugPrint('[标定图 $tag] ${cap.width} x ${cap.height}');
}