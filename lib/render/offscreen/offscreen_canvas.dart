import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../layout/math_metrics.dart';
import '../raster/downsample.dart';
import '../raster/raw_capture.dart';

/// 离屏出图的阶段回调：本 job 的进度比例（0..1）+ 阶段说明。
typedef OffscreenStageCallback = void Function(double progress, String stage);

/// 每轮「布局 → 同步取公式宽度 → 重建」的最大轮数。
///
/// 正常内容 2 轮即收敛（见 [RenderMathMetricsProbe.reportNow]）；留到 5 轮是为了
/// 容忍多层嵌套与断行后的二次测量，同时保证循环一定有界。
const int kMaxOffscreenLayoutPasses = 5;

/// 出图高度的硬上限（点）。
///
/// 超长内容会让图层与像素缓冲一起膨胀，宁可明确报错并请用户拆题，也不要把进程
/// 拖到 OOM。约合 1.2 万点 / 60mm×203dpi 的十余倍长度。
const int kMaxOutputHeightDots = 12000;

/// 离屏出图失败。
class OffscreenRenderException implements Exception {
  const OffscreenRenderException(this.message);

  final String message;

  @override
  String toString() => 'OffscreenRenderException: $message';
}

/// 一次离屏捕获的结果。
class OffscreenCapture {
  const OffscreenCapture(this.raw, {required this.layoutPasses});

  final RawCapture raw;

  /// 实际执行的「布局 + 取宽度」轮数，用于诊断收敛情况。
  final int layoutPasses;
}

/// 完全离屏的渲染管线（计划 §5.4(d)）。
///
/// 为什么不用「可见树 + `Offstage` / `Opacity(0)`」：`Offstage` 不绘制、
/// `Opacity(0)` 与屏幕外布局仍参与绘制，几千点高的长图需要超大画布，还受裁剪与
/// 滚动复用干扰，批量时反复挂载拆卸。离屏则固定宽度、高度由内容决定、
/// `pixelRatio` 取超采样倍率 S，天然支持批量与长图。
///
/// **超采样封死在本类内部**（计划 §5.4a）：内部按 [supersampleFactor] 用 `pixelRatio: S`
/// 光栅化，再用盒式降采样回到点阵宽度，因此对外的 [RawCapture] 语义仍是
/// 「1 像素 = 1 打印点」，调用方无需知道 S 的存在。
///
/// 关键点：`PipelineOwner` 不传任何回调时 `requestVisualUpdate()` 是空操作，
/// **永不排帧**，所以这里不能等帧。公式宽度改用
/// [RenderMathMetricsProbe.reportNow] 在同一轮里同步取数，取宽度前后不 `await`，
/// 真实帧不可能插进来。唯一的 `await` 是绘制前的内嵌矢量图预热
/// （见 [_preloadVectorGraphics]）：它发生在取宽度之前，且离屏树挂在自定义的
/// `BuildOwner` / `PipelineOwner` 上，真实帧不会重建它。
///
/// 生命周期每个 job 一套、用完即毁：`RenderView.prepareInitialFrame()` 只能调一次，
/// 因此不做复用。
class OffscreenCanvas {
  const OffscreenCanvas({this.debugOnImage});

  /// 每次捕获得到的 `ui.Image`；仅供测试断言「恰好释放一次」。
  @visibleForTesting
  final void Function(ui.Image image)? debugOnImage;

  /// 把 [child] 渲染成 [widthDots] 点宽的位图并取回像素。
  ///
  /// 注意：渲染必须在主 isolate —— 光栅化走引擎原生 `Scene::toImage`，后台
  /// isolate 没有 `RootIsolateToken`，装不下这条链路。
  Future<OffscreenCapture> capture({
    required Widget child,
    required int widthDots,
    OffscreenStageCallback? onStage,
  }) async {
    final ui.FlutterView? view =
        WidgetsBinding.instance.platformDispatcher.implicitView;
    if (view == null) {
      throw const OffscreenRenderException('当前环境没有可用的 FlutterView，无法离屏出图');
    }
    final double width = widthDots.toDouble();

    onStage?.call(0, '准备渲染管线');
    final PipelineOwner pipelineOwner = PipelineOwner();
    final BuildOwner buildOwner = BuildOwner(focusManager: FocusManager());
    final RenderView renderView = RenderView(
      view: view,
      configuration: ViewConfiguration(
        // 宽度必须是紧约束：出图宽度的精确性由它保证，内容溢出也不会变宽。
        logicalConstraints: BoxConstraints.tightFor(width: width),
        physicalConstraints: BoxConstraints.tightFor(width: width),
        // 1.0 让 ViewConfiguration.toMatrix() 退化为单位矩阵，1 逻辑点 = 1 打印机点。
        devicePixelRatio: 1.0,
      ),
    );
    // rootNode 的 setter 内部会先 detach 旧根再 attach，不需要手动 attach。
    pipelineOwner.rootNode = renderView;
    // 建立根 layer 并把根入队布局；只能调一次。
    renderView.prepareInitialFrame();

    final RenderObjectToWidgetAdapter<RenderBox> adapter =
        RenderObjectToWidgetAdapter<RenderBox>(
      container: renderView,
      child: _stage(child),
    );
    final RenderObjectToWidgetElement<RenderBox> element =
        adapter.attachToRenderTree(buildOwner);

    try {
      int layoutPasses = 0;
      for (; layoutPasses < kMaxOffscreenLayoutPasses; layoutPasses++) {
        buildOwner.buildScope(element);
        pipelineOwner.flushLayout();
        pipelineOwner.flushCompositingBits();

        // 首轮排版已把 SvgPicture 挂上树，此刻把内嵌矢量图解码落地再重建一次，
        // 否则首帧会缺字形（见 [_preloadVectorGraphics]）。
        if (layoutPasses == 0 && await _preloadVectorGraphics(element)) {
          buildOwner.buildScope(element);
          pipelineOwner.flushLayout();
          pipelineOwner.flushCompositingBits();
        }

        final RenderMathMetricsProbe? probe = _findProbe(renderView);
        if (probe == null) {
          layoutPasses++;
          break;
        }
        probe
          ..suppressPostFrameReport = true
          ..reportNow();
      }
      if (_findProbe(renderView) != null) {
        debugPrint('[离屏] 公式宽度经 $layoutPasses 轮仍未收敛，按当前状态出图');
      }

      // 绘制前必须让布局干净：RenderBox.paint 内断言 !_needsLayout，
      // 而每次 layout() 结尾都会 markNeedsPaint()。
      pipelineOwner.flushLayout();
      pipelineOwner.flushCompositingBits();
      pipelineOwner.flushPaint();
      onStage?.call(0.5, '排版完成');

      final RenderRepaintBoundary? captured = _findBoundary(renderView);
      if (captured == null) {
        throw const OffscreenRenderException('未找到用于捕获的 RepaintBoundary');
      }

      // 目标高度必须**先于**光栅化定下来：超采样倍率由「像素总数预算」推出，而超高
      // 的内容要在分配像素缓冲之前就报错（否则内存先爆）。
      final int heightDots = captured.size.height.ceil();
      if (heightDots > kMaxOutputHeightDots) {
        throw OffscreenRenderException(
          '内容高度 $heightDots 点超过上限 $kMaxOutputHeightDots 点，请拆分题目',
        );
      }
      final int factor =
          supersampleFactor(widthDots: widthDots, heightDots: heightDots);
      onStage?.call(0.6, factor > 1 ? '光栅化（$factor× 超采样）' : '光栅化');

      // 超采样只改 pixelRatio：`ViewConfiguration` 一个字都不动（计划 §5.4a）。
      final ui.Image image = await captured.toImage(pixelRatio: factor.toDouble());
      debugOnImage?.call(image);
      try {
        final ByteData? data =
            await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        if (data == null) {
          throw const OffscreenRenderException('toByteData 返回 null');
        }
        // 第一层：超采样出图的宽度必须是点阵宽度的整数倍。
        if (image.width != widthDots * factor) {
          throw OffscreenRenderException(
            '超采样出图宽度 ${image.width} 点不等于 ${widthDots * factor} 点',
          );
        }

        onStage?.call(0.9, '降采样');
        final RawCapture raw = boxDownsample(
          RawCapture(data.buffer.asUint8List(), image.width, image.height),
          factor,
        );
        // 第二层：降采样后必须回到「1 像素 = 1 打印点」的语义。
        if (raw.width != widthDots) {
          throw OffscreenRenderException(
            '出图宽度 ${raw.width} 点不等于目标 $widthDots 点',
          );
        }
        // 第三层：高度用的恒等式 ceil(ceil(S·H)/S) == ceil(H)，H 取布局后的真实高度。
        if (raw.height != heightDots) {
          throw OffscreenRenderException(
            '降采样后高度 ${raw.height} 点与目标 $heightDots 点不一致',
          );
        }
        onStage?.call(1, '光栅化完成');
        return OffscreenCapture(raw, layoutPasses: layoutPasses);
      } finally {
        // 串行单张：任何时候最多一个 ui.Image 存活。
        image.dispose();
      }
    } finally {
      _detach(element, buildOwner, pipelineOwner, renderView);
    }
  }

  /// 绘制前把树里的内嵌矢量图解码落地，返回树上是否有这类图。
  ///
  /// 根号、箭头、花括号这些符号（`flutter_math_fork` 的 `\sqrt` 等）不是字体字形，
  /// 而是渲染成 SVG 路径后交给 flutter_svg 加载的，**加载是异步的**：release（AOT）
  /// 下 SVG 编码走 `compute()`（真实 isolate），结果只能通过 `setState` 回到 widget；
  /// 而未解码时它画的是 vector_graphics 的空白占位方盒（位置照占、内容全空）。
  /// 本管线「排版 → 绘制 → toImage」全程同步、不排帧，首帧就必然只拿到那个空盒——
  /// 这正是「首次生成根号不渲染、重试即恢复」的原因：重试时 flutter_svg 的全局
  /// `svg.cache` 已命中 ByteData，加载退化成同步。
  ///
  /// 这里把树上每个 [SvgPicture] 的 loader 都 `await` 一遍再让调用方重建：同一个
  /// cache key 的加载在 `svg.cache` 里共享同一个 Future，所以等到的就是 widget 自己
  /// 那条链，不必重开一份；落地之后重建，首帧即与「重试帧」一致。
  Future<bool> _preloadVectorGraphics(Element root) async {
    final Map<BytesLoader, BuildContext> loaders = <BytesLoader, BuildContext>{};
    void visit(Element node) {
      final Widget widget = node.widget;
      if (widget is SvgPicture) loaders[widget.bytesLoader] = node;
      node.visitChildren(visit);
    }

    visit(root);
    if (loaders.isEmpty) return false;
    await Future.wait<void>(loaders.entries.map(
      (MapEntry<BytesLoader, BuildContext> entry) =>
          entry.key.loadBytes(entry.value),
    ));
    return true;
  }

  /// 离屏树的固定外壳。
  ///
  /// `Directionality` 是硬需求；`MediaQuery` 用空数据（与可见树的测试路径一致），
  /// 让 `MediaQuery.textScalerOf` 这类查询拿到明确的默认值而不是走兜底。
  ///
  /// 这里**不能用 GlobalKey 去取捕获面**：`GlobalKey._currentElement` 查的是
  /// `WidgetsBinding.instance.buildOwner` 的注册表（framework.dart:173），而离屏树
  /// 挂在自定义 BuildOwner 上，注册表对不上，`currentContext` 恒为 null。
  Widget _stage(Widget child) => Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: const MediaQueryData(),
          child: RepaintBoundary(child: child),
        ),
      );

  /// 深度优先找最外层的捕获面。
  ///
  /// 离屏树的顶层就是我们的 [RepaintBoundary]，因此 DFS 遇到的第一个即是它。
  RenderRepaintBoundary? _findBoundary(RenderObject root) {
    RenderRepaintBoundary? found;
    void visit(RenderObject node) {
      if (found != null) return;
      if (node is RenderRepaintBoundary) {
        found = node;
        return;
      }
      node.visitChildren(visit);
    }

    visit(root);
    return found;
  }

  /// 深度优先找当前的测量探针；找不到说明宽度已经全部量到、不需要再重排。
  RenderMathMetricsProbe? _findProbe(RenderObject root) {
    RenderMathMetricsProbe? found;
    void visit(RenderObject node) {
      if (found != null) return;
      if (node is RenderMathMetricsProbe) {
        found = node;
        return;
      }
      node.visitChildren(visit);
    }

    visit(root);
    return found;
  }

  /// 卸载整棵树：先用「child 为 null」的新 adapter 触发一次更新把子树摘掉，
  /// 再让 BuildOwner 走完卸载与 finalize，最后把渲染管线与根解绑。
  void _detach(
    RenderObjectToWidgetElement<RenderBox> element,
    BuildOwner buildOwner,
    PipelineOwner pipelineOwner,
    RenderView renderView,
  ) {
    RenderObjectToWidgetAdapter<RenderBox>(container: renderView)
        .attachToRenderTree(buildOwner, element);
    buildOwner
      ..buildScope(element)
      ..finalizeTree();
    pipelineOwner.rootNode = null;
  }
}