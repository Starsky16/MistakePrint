// P2 出图测试：版式 MVP 的五条成功标准（计划 §4 P2）。
//
// 与标定图生成器一样属于开发期离线自检，产物写到仓库外的 D:\code\temp，不入库。
// 注意事项见 test/calibration/generate_calibration_test.dart 顶部。

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mistake_print/profiles/paper_profile.dart';
import 'package:mistake_print/render/document_view.dart';
import 'package:mistake_print/render/raster/binarize.dart';
import 'package:mistake_print/render/raster/png_encode.dart';
import 'package:mistake_print/render/raster/raw_capture.dart';

import '../support/png_file.dart';
import '../support/render_capture.dart';
import '../support/test_fonts.dart';

/// 输出目录（仓库外，不入库）。
const String kOutDir = r'D:\code\temp\p2-doc';

/// 成功标准 1 的样例：一句话里同时含行内公式与块级公式。
const String kSample = r'''
已知函数 $f(x)=x^2+2x+1$，求 $f(x)$ 的最小值。

$$\frac{a+b}{2}\geq\sqrt{ab}$$

设 $x$ 为正数，则 $\frac{x}{2}+\frac{1}{x}$ 的最小值为？
''';

/// 分式样例：用于成功标准 5 的分数线连通断言。
const String kFraction = r'$$\frac{a+b}{2}\geq\sqrt{ab}$$';

/// 极端超宽公式：Q9 应先在加号处断行。
const String kOversize =
    r'$$a_{1}+a_{2}+a_{3}+a_{4}+a_{5}+a_{6}+a_{7}+a_{8}+a_{9}+a_{10}+a_{11}+a_{12}+a_{13}+a_{14}=S$$';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await loadTestFonts();
  });

  testWidgets('成功标准 1/2/4：样例能出图，宽度精确等于 printableDotsWidth，且为 1-bit 灰度', (WidgetTester tester) async {
    final RawCapture cap = await renderCapture(
      tester,
      renderDocument(kSample, kPaperangP1Default),
    );
    debugPrint('[P2 样例] 画面 ${cap.width}x${cap.height}');

    // 成功标准 2：像素级精确，不是「约等于」。
    expect(cap.width, kPaperangP1Default.printableDotsWidth);

    final List<List<bool>> black = binarize(cap, protectStructureLines: true);
    expect(countDark(black), greaterThan(0), reason: '样例不应出白图');

    final Uint8List png =
        encodeBitmap(black, withPhys: kPaperangP1Default.writePhys);
    writePng(kOutDir, 'p2-sample-1bit.png', png);
    writePng(kOutDir, 'p2-sample-gray.png', encodeGray(cap, withPhys: kPaperangP1Default.writePhys));

    // 成功标准 4：直接读 IHDR 字节，不靠解码回读。
    final ByteData ihdr = ByteData.sublistView(png);
    expect(ihdr.getUint32(16), kPaperangP1Default.printableDotsWidth,
        reason: 'PNG 宽度应为 printableDotsWidth');
    expect(ihdr.getUint32(20), cap.height);
    expect(ihdr.getUint8(24), 1, reason: 'bitDepth 必须为 1');
    expect(ihdr.getUint8(25), 0, reason: 'colorType 必须为 0（灰度）');
  });

  testWidgets('成功标准 3：同一输入连跑两次，输出字节级一致', (WidgetTester tester) async {
    Future<Uint8List> encodeOnce() async {
      final RawCapture cap = await renderCapture(
        tester,
        renderDocument(kSample, kPaperangP1Default),
      );
      return encodeBitmap(
        binarize(cap, protectStructureLines: true),
        withPhys: kPaperangP1Default.writePhys,
      );
    }

    final Uint8List first = await encodeOnce();
    final Uint8List second = await encodeOnce();

    expect(second.length, first.length);
    expect(listEquals(first, second), isTrue, reason: '同输入的两次出图应逐字节相同');
  });

  testWidgets('成功标准 5：分式分数线在保护后整行连通、无断点', (WidgetTester tester) async {
    final RawCapture cap = await renderCapture(
      tester,
      renderDocument(kFraction, kPaperangP1Default),
    );

    final List<List<bool>> strict = binarize(cap);
    final List<List<bool>> protectedBlack = binarize(cap, protectStructureLines: true);
    debugPrint(
      '[P2 分式] 最长水平黑游程 ${longestDarkRun(strict)} → ${longestDarkRun(protectedBlack)}，'
      '黑点 ${countDark(strict)} → ${countDark(protectedBlack)}',
    );

    writePng(kOutDir, 'p2-fraction-1bit.png',
        encodeBitmap(protectedBlack, withPhys: kPaperangP1Default.writePhys));

    // 分数线（\frac{a+b}{2} 的横线）与根号上划线都远长于 16 点；
    // longestDarkRun 取的是连续无断点的一段，因此该断言等价于「整行连通」。
    expect(longestDarkRun(protectedBlack), greaterThanOrEqualTo(16),
        reason: '保护后应存在一条连通的结构线');
    expect(countDark(protectedBlack), greaterThanOrEqualTo(countDark(strict)),
        reason: '保护只会加黑点，不会抹掉墨水');
  });

  testWidgets('超宽公式按 Q9 断行，宽度仍精确等于 printableDotsWidth', (WidgetTester tester) async {
    final List<String> logs = <String>[];
    final DebugPrintCallback original = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) logs.add(message);
    };
    addTearDown(() => debugPrint = original);

    final RawCapture cap = await renderCapture(
      tester,
      renderDocument(kOversize, kPaperangP1Default),
    );
    debugPrint = original;

    debugPrint('[P2 超宽] 画面 ${cap.width}x${cap.height}');
    writePng(kOutDir, 'p2-oversize-1bit.png',
        encodeBitmap(binarize(cap, protectStructureLines: true), withPhys: kPaperangP1Default.writePhys));

    expect(cap.width, kPaperangP1Default.printableDotsWidth);
    expect(
      logs.any((String m) => m.contains('公式超宽')),
      isTrue,
      reason: '应走 texBreak 断行路径',
    );
    expect(
      logs.any((String m) => m.contains('已整体缩放')),
      isFalse,
      reason: '断行应生效，不应退到整体缩放',
    );
    expect(cap.height, greaterThan(40), reason: '断行后应占不止一行');
  });

  testWidgets('公式放不下时整体缩放的兜底路径（OversizeStrategy.scale）', (WidgetTester tester) async {
    final PaperProfile scaleProfile = PaperProfile(
      id: 'test-scale',
      name: '兜底策略测试档案',
      dpi: 203,
      paperWidthMm: 57,
      printableDotsWidth: kPaperangP1Default.printableDotsWidth,
      minFontPx: 20,
      bodyFontPx: 20,
      mathFontPx: 24,
      lineHeight: 1.3,
      threshold: 128,
      protectStructureLines: true,
      structureRunLength: kStructureRunLength,
      minLineWidthPx: 1,
      writePhys: true,
      oversizeStrategy: OversizeStrategy.scale,
      columns: 1,
      isCalibrated: false,
    );

    final RawCapture cap = await renderCapture(
      tester,
      renderDocument(kOversize, scaleProfile),
    );

    expect(cap.width, scaleProfile.printableDotsWidth, reason: '缩放兜底后宽度仍须精确');
  });
}