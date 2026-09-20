import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mistake_print/render/raster/raw_capture.dart';

/// 常规图的画面尺寸；够容纳图 D、图 E-tall 这类长图。
const Size kTallSurface = Size(384, 4200);

/// 把 widget 渲染到离屏画布并取回像素。
///
/// 仅供开发期离线自检使用，不进入 App 运行时路径。
Future<RawCapture> renderCapture(
  WidgetTester tester,
  Widget widget, {
  double pixelRatio = 1.0,
  Size surface = kTallSurface,
}) async {
  await tester.binding.setSurfaceSize(surface);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final GlobalKey key = GlobalKey();
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        data: const MediaQueryData(),
        child: Align(
          alignment: Alignment.topLeft,
          child: RepaintBoundary(key: key, child: widget),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  late RawCapture capture;
  // toImage 与 toByteData 都必须在真实事件循环里跑。
  await tester.runAsync(() async {
    final RenderRepaintBoundary boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final ui.Image image = await boundary.toImage(pixelRatio: pixelRatio);
    final ByteData? data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    expect(data, isNotNull, reason: 'toByteData 返回 null');
    capture = RawCapture(data!.buffer.asUint8List(), image.width, image.height);
    image.dispose();
  });
  return capture;
}