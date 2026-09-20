import 'package:flutter/widgets.dart';

/// 公式断行结果。
///
/// [parts] 是若干可各自独立渲染的片段；[penalties] 与之一一对应，表示该片段**右端**
/// 的断点罚值（10000 表示其后不可断）。
class MathBreakResult {
  const MathBreakResult(this.parts, this.penalties);

  final List<Widget> parts;
  final List<int> penalties;

  /// 是否真的断成了多段。
  bool get isSplittable => parts.length > 1;
}

/// 公式渲染接口（计划 §5.4(f)）。
///
/// 业务层只依赖它，不直接依赖 `flutter_math_fork`：公式库是可替换的实现细节。
abstract class MathRenderer {
  /// 渲染一个完整公式（不拆行）。
  Widget render(
    String tex, {
    required double fontSize,
    required Color color,
    bool display = false,
  });

  /// 按 TeX 规则断行；断点落在公式单元之间或顶层关系符处（计划 §5.5）。
  MathBreakResult breakLine(
    String tex, {
    required double fontSize,
    required Color color,
    bool display = false,
  });
}