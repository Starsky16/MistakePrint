import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// 探测公式宽度时的上限约束（点）。
///
/// 取一个远大于任何真实公式的有限值：既不让公式被约束挤扁，又避免无限大约束。
const double kProbeMaxWidth = 4096;

/// 公式宽度缓存的键：同一公式在相同字号与风格下宽度稳定，与颜色无关。
String mathMetricsKey(
  String tex, {
  required double fontSize,
  required bool display,
  int partIndex = -1,
}) =>
    '${display ? 'D' : 'T'}|$fontSize|$partIndex|$tex';

/// 已探测到的公式宽度（单位：点）。
class MathMetrics {
  final Map<String, double> _widths = <String, double>{};

  double? widthOf(String key) => _widths[key];

  /// 记录一次测量；返回是否发生变化（调用方据此避免无谓重建）。
  bool record(String key, double width) {
    if (_widths[key] == width) return false;
    _widths[key] = width;
    return true;
  }
}

/// 零尺寸测量宿主：借一帧把 [items] 量出来，帧末通过 [onMeasured] 上报宽度。
///
/// 公式宽度只有真实布局才知道，而断行判断必须早于布局，因此这里采用「先量一帧、
/// 再按量到的宽度重排」的两遍方式。调用方必须在收到新宽度后重建（见 DocumentView）。
class MathMetricsProbe extends MultiChildRenderObjectWidget {
  const MathMetricsProbe({
    super.key,
    required this.keys,
    required List<Widget> items,
    required this.onMeasured,
  }) : super(children: items);

  /// 与 children 一一对应的缓存键。
  final List<String> keys;

  final void Function(Map<String, double> widths) onMeasured;

  @override
  RenderMathMetricsProbe createRenderObject(BuildContext context) =>
      RenderMathMetricsProbe(keys, onMeasured);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderMathMetricsProbe renderObject,
  ) {
    renderObject
      ..keys = keys
      ..onMeasured = onMeasured;
  }
}

/// 测量用的渲染对象：自身占 0 尺寸，不绘制任何内容。
class RenderMathMetricsProbe extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, MultiChildLayoutParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, MultiChildLayoutParentData> {
  RenderMathMetricsProbe(this.keys, this.onMeasured);

  List<String> keys;
  void Function(Map<String, double> widths) onMeasured;

  /// 是否抑制帧末上报。
  ///
  /// 离屏出图管线不产生帧（`PipelineOwner` 不传回调时 `requestVisualUpdate()`
  /// 是空操作，永不排帧），帧末回调只会落在真实窗口的帧上，既不可控也可能永不
  /// 触发。离屏路径把它置为 true，改用 [reportNow] 在同一轮里同步取数。
  bool suppressPostFrameReport = false;

  bool _reportScheduled = false;

  /// 同步读取各子级宽度并上报；全部量到返回 true。
  ///
  /// 供离屏管线在 `flushLayout()` 之后直接取数，完全不依赖帧回调。
  bool reportNow() {
    final Map<String, double> widths = _collectWidths();
    if (widths.length != keys.length) return false;
    onMeasured(widths);
    return true;
  }

  Map<String, double> _collectWidths() {
    final Map<String, double> widths = <String, double>{};
    RenderBox? child = firstChild;
    int index = 0;
    while (child != null && index < keys.length) {
      if (child.hasSize) widths[keys[index]] = child.size.width;
      child = childAfter(child);
      index++;
    }
    return widths;
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! MultiChildLayoutParentData) {
      child.parentData = MultiChildLayoutParentData();
    }
  }

  @override
  void performLayout() {
    // 不占版面，只为测量。
    size = constraints.constrain(Size.zero);

    RenderBox? child = firstChild;
    while (child != null) {
      // 尺寸在帧末要读回来上报，所以必须声明 parentUsesSize。
      child.layout(
        const BoxConstraints(maxWidth: kProbeMaxWidth),
        parentUsesSize: true,
      );
      child = childAfter(child);
    }
    _scheduleReport();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    // 探针不绘制。
  }

  void _scheduleReport() {
    if (suppressPostFrameReport || _reportScheduled) return;
    _reportScheduled = true;
    // 布局阶段不能重建，尺寸留到帧末上报。
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _reportScheduled = false;
      if (suppressPostFrameReport || !attached) return;
      final Map<String, double> widths = _collectWidths();
      if (widths.length == keys.length) onMeasured(widths);
    });
  }
}