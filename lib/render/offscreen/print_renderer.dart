import 'package:flutter/foundation.dart';

import '../../profiles/paper_profile.dart';
import '../document_view.dart';
import '../raster/binarize.dart';
import '../raster/png_encode.dart';
import '../raster/raw_capture.dart';
import 'offscreen_canvas.dart';

/// 出图进度回调：总进度比例（0..1）+ 阶段说明。
typedef RenderProgressCallback = void Function(double progress, String stage);

/// 一次出图的结果。
class PrintImage {
  const PrintImage({
    required this.png,
    required this.width,
    required this.height,
    required this.blackDots,
    required this.elapsed,
    required this.layoutPasses,
  });

  /// 1-bit 灰度 PNG（`bitDepth=1 / colorType=0`），可直接分享或落盘。
  final Uint8List png;

  final int width;
  final int height;

  /// 黑点总数，用于观察墨量。
  final int blackDots;

  final Duration elapsed;

  /// 实际排版轮数，用于诊断收敛情况。
  final int layoutPasses;

  /// 黑点占比。
  double get blackRatio =>
      width * height == 0 ? 0 : blackDots / (width * height);
}

/// 题干 → 可打印位图（计划 §5.4(d) / §5.6 主交付形态）。
///
/// 渲染留在主 isolate：光栅化是引擎原生调用（`Scene::toImage`），后台 isolate
/// 没有 `RootIsolateToken`，装不下这条链路。只有纯 Dart 的「二值化 + 1-bit PNG
/// 编码」下沉到 `compute()`，避免长图把 UI 卡住。
class PrintRenderer {
  const PrintRenderer({this.canvas = const OffscreenCanvas()});

  final OffscreenCanvas canvas;

  Future<PrintImage> render(
    String text,
    PaperProfile profile, {
    RenderProgressCallback? onProgress,
  }) async {
    final Stopwatch watch = Stopwatch()..start();
    onProgress?.call(0.05, '准备');

    // 排版权重较大（0.10~0.75），光栅化在引擎侧异步完成。
    final OffscreenCapture shot = await canvas.capture(
      child: renderDocument(text, profile),
      widthDots: profile.printableDotsWidth,
      onStage: (double progress, String stage) =>
          onProgress?.call(0.10 + progress * 0.65, stage),
    );

    onProgress?.call(0.80, '二值化与编码');
    final (Uint8List png, int blackDots) = await compute(
      _binarizeAndEncode,
      _EncodeRequest(
        rgba: shot.raw.rgba,
        width: shot.raw.width,
        height: shot.raw.height,
        strictThreshold: profile.threshold,
        protectStructureLines: profile.protectStructureLines,
        structureRunLength: profile.structureRunLength,
        withPhys: profile.writePhys,
      ),
    );

    onProgress?.call(1, '完成');
    watch.stop();
    return PrintImage(
      png: png,
      width: shot.raw.width,
      height: shot.raw.height,
      blackDots: blackDots,
      elapsed: watch.elapsed,
      layoutPasses: shot.layoutPasses,
    );
  }
}

/// `compute()` 的入参：只含可跨 isolate 传递的纯数据。
class _EncodeRequest {
  const _EncodeRequest({
    required this.rgba,
    required this.width,
    required this.height,
    required this.strictThreshold,
    required this.protectStructureLines,
    required this.structureRunLength,
    required this.withPhys,
  });

  final Uint8List rgba;
  final int width;
  final int height;
  final int strictThreshold;
  final bool protectStructureLines;
  final int structureRunLength;
  final bool withPhys;
}

/// 二值化 + 1-bit PNG 编码。
///
/// 纯 Dart、不碰 `dart:ui`，因此可以整体下沉到后台 isolate。
/// 返回 (PNG 字节, 黑点数)。
(Uint8List, int) _binarizeAndEncode(_EncodeRequest req) {
  final List<List<bool>> black = binarize(
    RawCapture(req.rgba, req.width, req.height),
    protectStructureLines: req.protectStructureLines,
    strictThreshold: req.strictThreshold,
    structureRunLength: req.structureRunLength,
  );
  return (encodeBitmap(black, withPhys: req.withPhys), countDark(black));
}