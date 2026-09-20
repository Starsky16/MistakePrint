import 'package:flutter/widgets.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import 'math_renderer.dart';

/// 基于 `flutter_math_fork` 的实现（精确钉版 0.7.4）。
class FlutterMathRenderer implements MathRenderer {
  const FlutterMathRenderer();

  /// 解析设置保持默认：`maxExpand` = 1000，不要放宽（计划 §5.7 宏展开炸弹防护）。
  static const TexParserSettings _settings = TexParserSettings();

  @override
  Widget render(
    String tex, {
    required double fontSize,
    required Color color,
    bool display = false,
  }) =>
      _math(tex, fontSize: fontSize, color: color, display: display);

  @override
  MathBreakResult breakLine(
    String tex, {
    required double fontSize,
    required Color color,
    bool display = false,
  }) {
    final math = _math(tex, fontSize: fontSize, color: color, display: display);
    final broken = math.texBreak();
    return MathBreakResult(broken.parts, broken.penalties);
  }

  Math _math(
    String tex, {
    required double fontSize,
    required Color color,
    required bool display,
  }) =>
      Math.tex(
        tex,
        settings: _settings,
        options: MathOptions(
          style: display ? MathStyle.display : MathStyle.text,
          fontSize: fontSize,
          color: color,
        ),
      );
}