// P3 离屏出图管线测试（计划 §5.4(d)、P3 任务第 1~2 条）。
//
// 与 P2 的出图测试一样属于开发期离线自检：产物写到仓库外的 D:\code\temp，不入库。
// 「真机上的长图内存与分享链路」无法在这里验证，见计划 §6 的待验收清单。

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mistake_print/profiles/paper_profile.dart';
import 'package:mistake_print/render/document_view.dart';
import 'package:mistake_print/render/offscreen/offscreen_canvas.dart';
import 'package:mistake_print/render/offscreen/print_renderer.dart';
import 'package:mistake_print/render/raster/raw_capture.dart';

import '../support/png_file.dart';
import '../support/render_capture.dart';
import '../support/test_fonts.dart';

/// 输出目录（仓库外，不入库）。
const String kOutDir = r'D:\code\temp\p3-offscreen';

/// 含行内公式与块级公式的样例。
const String kSample = r'''
已知函数 $f(x)=x^2+2x+1$，求 $f(x)$ 的最小值。

$$\frac{a+b}{2}\geq\sqrt{ab}$$

设 $x$ 为正数，则 $\frac{x}{2}+\frac{1}{x}$ 的最小值为？
''';

/// 极端超宽公式：会走 texBreak 断行，是最容易不收敛的形态。
const String kOversize =
    r'$$a_{1}+a_{2}+a_{3}+a_{4}+a_{5}+a_{6}+a_{7}+a_{8}+a_{9}+a_{10}+a_{11}+a_{12}+a_{13}+a_{14}=S$$';

/// 合成一份约 3000 点高的长内容（每行 20 点正文 × 1.3 行高 ≈ 26 点）。
String longText({int lines = 120}) {
  const String body = r'已知 $f(x)=x^2+2x+1$，求 $\frac{x}{2}+\frac{1}{x}$ 的最小值。';
  return List<String>.generate(
    lines,
    (int i) => '错题 ${i + 1}：$body',
  ).join('\n');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await loadTestFonts();
  });

  testWidgets('离屏出图宽度精确，且与可见树捕获逐像素一致', (WidgetTester tester) async {
    late OffscreenCapture shot;
    await tester.runAsync(() async {
      shot = await const OffscreenCanvas().capture(
        child: renderDocument(kSample, kPaperangP1Default),
        widthDots: kPaperangP1Default.printableDotsWidth,
      );
    });
    debugPrint('[离屏] 画面 ${shot.raw.width}x${shot.raw.height}，'
        '排版 ${shot.layoutPasses} 轮');

    // 宽度精确是硬指标：紧约束 → ceil(384.0 × 1.0) = 384。
    expect(shot.raw.width, kPaperangP1Default.printableDotsWidth);

    final RawCapture visible =
        await renderCapture(tester, renderDocument(kSample, kPaperangP1Default));
    expect(shot.raw.height, visible.height, reason: '离屏与可见树的内容高度应一致');
    expect(
      listEquals(shot.raw.rgba, visible.rgba),
      isTrue,
      reason: '离屏管线必须与可见树渲染出同一张图，否则预览与打印不符',
    );
  });

  testWidgets('出图为 1-bit 灰度 PNG，且同一输入连跑两次字节级一致', (WidgetTester tester) async {
    late PrintImage first;
    late PrintImage second;
    await tester.runAsync(() async {
      const PrintRenderer renderer = PrintRenderer();
      first = await renderer.render(kSample, kPaperangP1Default);
      second = await renderer.render(kSample, kPaperangP1Default);
    });
    debugPrint('[离屏] 出图 ${first.width}x${first.height} 黑点 ${first.blackDots} '
        '(${(first.blackRatio * 100).toStringAsFixed(2)}%) '
        '耗时 ${first.elapsed.inMilliseconds}ms');

    writePng(kOutDir, 'p3-sample-1bit.png', first.png);

    final ByteData ihdr = ByteData.sublistView(first.png);
    expect(ihdr.getUint32(16), kPaperangP1Default.printableDotsWidth,
        reason: 'PNG 宽度应为 printableDotsWidth');
    expect(ihdr.getUint32(20), first.height);
    expect(ihdr.getUint8(24), 1, reason: 'bitDepth 必须为 1');
    expect(ihdr.getUint8(25), 0, reason: 'colorType 必须为 0（灰度）');

    expect(first.blackDots, greaterThan(0), reason: '样例不应出白图');
    expect(listEquals(first.png, second.png), isTrue,
        reason: '同输入的两次出图应逐字节相同');
  });

  testWidgets('超宽公式（走 texBreak）也能收敛，轮数不超过 3', (WidgetTester tester) async {
    final List<String> logs = <String>[];
    final DebugPrintCallback original = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) logs.add(message);
    };

    late PrintImage image;
    try {
      await tester.runAsync(() async {
        image = await const PrintRenderer().render(kOversize, kPaperangP1Default);
      });
    } finally {
      debugPrint = original;
    }
    debugPrint('[离屏] 超宽样例 ${image.width}x${image.height}，排版 ${image.layoutPasses} 轮');

    expect(logs.any((String m) => m.contains('公式超宽')), isTrue,
        reason: '应走 texBreak 断行路径');
    expect(
      logs.any((String m) => m.contains('仍未收敛')),
      isFalse,
      reason: '断行后的二次测量也必须在轮数上限内收敛',
    );
    expect(image.layoutPasses, lessThanOrEqualTo(3));
    expect(image.width, kPaperangP1Default.printableDotsWidth);
    expect(image.height, greaterThan(40), reason: '断行后应占不止一行');
  });

  testWidgets('约 3000 点高的长图能出图，且内存增量受控', (WidgetTester tester) async {
    final int rssBefore = ProcessInfo.currentRss;

    late PrintImage image;
    await tester.runAsync(() async {
      image = await const PrintRenderer().render(longText(), kPaperangP1Default);
    });

    final int rssDelta = ProcessInfo.currentRss - rssBefore;
    debugPrint('[离屏] 长图 ${image.width}x${image.height} 黑点 ${image.blackDots} '
        '耗时 ${image.elapsed.inMilliseconds}ms '
        '排版 ${image.layoutPasses} 轮 RSS 增量 ${rssDelta ~/ 1048576}MB');
    writePng(kOutDir, 'p3-long-1bit.png', image.png);

    expect(image.height, greaterThanOrEqualTo(3000), reason: '样例应达到长图量级');
    expect(image.width, kPaperangP1Default.printableDotsWidth);
    // 只是内存失控的代理指标，不代表真机表现（真机项见计划 §6）。
    expect(rssDelta, lessThan(256 * 1024 * 1024), reason: '长图不应出现数量级的内存膨胀');
  });

  testWidgets('每个 job 恰好释放一次 ui.Image', (WidgetTester tester) async {
    final List<ui.Image> images = <ui.Image>[];
    await tester.runAsync(() async {
      await OffscreenCanvas(debugOnImage: images.add).capture(
        child: renderDocument(kSample, kPaperangP1Default),
        widthDots: kPaperangP1Default.printableDotsWidth,
      );
    });

    expect(images, hasLength(1));
    expect(images.single.debugDisposed, isTrue, reason: '捕获用图必须立即释放');
  });
}