import 'package:flutter/material.dart';

import '../domain/token.dart';
import '../domain/tokenizer.dart';
import '../profiles/paper_profile.dart';
import 'layout/math_metrics.dart';
import 'math/flutter_math_renderer.dart';
import 'math/math_renderer.dart';
import 'text/text_styles.dart';

/// 纸张底色（打印目标永远是白纸黑字）。
const Color _paperWhite = Color(0xFFFFFFFF);

/// 库入口（计划 §5.6）：题干文本 + 机型档案 → 一份宽度精确等于
/// `profile.printableDotsWidth` 的排版结果。
Widget renderDocument(
  String text,
  PaperProfile profile, {
  MathRenderer renderer = const FlutterMathRenderer(),
}) =>
    DocumentView(tokens: tokenize(text), profile: profile, renderer: renderer);

/// 把分词结果按 [profile] 的约束排成固定点阵宽度的列。
///
/// 版式规则（计划 §5.5）：
/// - 一切尺寸以「点」为单位，宽度唯一真相是 `profile.printableDotsWidth`；
/// - 行内公式与文本按基线对齐（由 `WidgetSpan` 的 baseline 对齐保证）；
/// - 公式放不下时先按 TeX 规则断行（`texBreak`），断出的片段仍超宽才整体缩放并告警；
/// - 正文换行由文本引擎按 384 点宽自动折行，不人工切字。
///
/// 实现说明：公式宽度必须先量后断行，因此首帧对未知宽度的公式出零尺寸占位并挂上
/// [MathMetricsProbe]，帧末拿到宽度后重建一次。离屏出图时需至少 pump 两帧。
class DocumentView extends StatefulWidget {
  const DocumentView({
    super.key,
    required this.tokens,
    required this.profile,
    this.renderer = const FlutterMathRenderer(),
  });

  final List<Token> tokens;
  final PaperProfile profile;
  final MathRenderer renderer;

  @override
  State<DocumentView> createState() => _DocumentViewState();
}

class _DocumentViewState extends State<DocumentView> {
  /// 本视图内已量到的公式宽度。
  ///
  /// 键里含字号与风格，所以换档案后旧值依然有效，不需要失效清理。
  final MathMetrics _metrics = MathMetrics();

  /// 本帧需要探测的公式：缓存键 → 待测 widget。
  final Map<String, Widget> _pending = <String, Widget>{};

  @override
  Widget build(BuildContext context) {
    _pending.clear();
    final List<Widget> children = _buildBlocks();
    if (_pending.isNotEmpty) {
      children.add(
        MathMetricsProbe(
          keys: _pending.keys.toList(growable: false),
          items: _pending.values.toList(growable: false),
          onMeasured: _onMeasured,
        ),
      );
    }

    return SizedBox(
      width: widget.profile.printableDotsWidth.toDouble(),
      // 热敏纸是白底：出图必须自带白背景，否则离屏捕获拿到的是透明像素，
      // 二值化后整张图会变成全黑。
      child: ColoredBox(
        color: _paperWhite,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: children,
        ),
      ),
    );
  }

  void _onMeasured(Map<String, double> widths) {
    bool changed = false;
    widths.forEach((String key, double width) {
      if (_metrics.record(key, width)) changed = true;
    });
    if (changed && mounted) {
      setState(() {});
    }
  }

  // -------------------------------------------------------------------------
  // 分块：段落与块级公式
  // -------------------------------------------------------------------------

  List<Widget> _buildBlocks() {
    final List<Widget> blocks = <Widget>[];
    List<InlineSpan> paragraph = <InlineSpan>[];

    void flush() {
      if (paragraph.isEmpty) return;
      blocks.add(_paragraph(paragraph));
      paragraph = <InlineSpan>[];
    }

    for (final Token token in widget.tokens) {
      switch (token.kind) {
        case TokenKind.blockMath:
          flush();
          blocks.add(_paragraph(_mathSpans(token.value, display: true), align: TextAlign.center));
        case TokenKind.inlineMath:
          paragraph.addAll(_mathSpans(token.value, display: false));
        case TokenKind.text:
          final List<String> lines = token.value.split('\n');
          for (int i = 0; i < lines.length; i++) {
            // 空行只起到分段作用，不额外占高度（段间距已由 gap 提供）。
            if (i > 0) flush();
            if (lines[i].isNotEmpty) {
              paragraph.add(_textSpan(lines[i]));
            }
          }
      }
    }
    flush();
    return _withGaps(blocks);
  }

  /// 段间距：半个正文行高，取整以避免亚像素错位。
  List<Widget> _withGaps(List<Widget> blocks) {
    if (blocks.length < 2) return blocks;
    final double gap = (widget.profile.bodyFontPx * 0.5).roundToDouble();
    final List<Widget> result = <Widget>[];
    for (int i = 0; i < blocks.length; i++) {
      if (i > 0) result.add(SizedBox(height: gap));
      result.add(blocks[i]);
    }
    return result;
  }

  // -------------------------------------------------------------------------
  // 行内元素
  // -------------------------------------------------------------------------

  InlineSpan _textSpan(String text) => TextSpan(
        text: text,
        style: bodyStyle(
          widget.profile.bodyFontPx,
          height: widget.profile.lineHeight,
        ),
      );

  /// 公式 → 若干行内 span。
  List<InlineSpan> _mathSpans(String tex, {required bool display}) {
    final PaperProfile profile = widget.profile;
    final double fontSize = profile.mathFontPx;
    final double maxWidth = profile.printableDotsWidth.toDouble();

    final String wholeKey =
        mathMetricsKey(tex, fontSize: fontSize, display: display);
    final double? wholeWidth = _metrics.widthOf(wholeKey);
    final Widget whole = widget.renderer.render(
      tex,
      fontSize: fontSize,
      color: kInk,
      display: display,
    );

    if (wholeWidth == null) {
      _pending[wholeKey] = whole;
      return <InlineSpan>[_placeholder];
    }

    final bool needBreak = wholeWidth > maxWidth &&
        profile.oversizeStrategy == OversizeStrategy.lineBreak;
    if (!needBreak) {
      return <InlineSpan>[
        _mathSpan(whole, measuredWidth: wholeWidth, maxWidth: maxWidth),
      ];
    }

    // 超宽：在公式单元之间/顶层关系符处断开，让文本引擎在片段之间自然折行。
    final MathBreakResult broken = widget.renderer.breakLine(
      tex,
      fontSize: fontSize,
      color: kInk,
      display: display,
    );
    debugPrint(
      '[版式] 公式超宽（${wholeWidth.toStringAsFixed(1)} > ${maxWidth.toInt()}），'
      '按 TeX 规则断为 ${broken.parts.length} 段：$tex',
    );

    final List<InlineSpan> spans = <InlineSpan>[];
    for (int i = 0; i < broken.parts.length; i++) {
      final Widget part = broken.parts[i];
      final String key = mathMetricsKey(
        tex,
        fontSize: fontSize,
        display: display,
        partIndex: i,
      );
      final double? width = _metrics.widthOf(key);
      if (width == null) {
        _pending[key] = part;
        spans.add(_placeholder);
        continue;
      }
      spans.add(_mathSpan(part, measuredWidth: width, maxWidth: maxWidth));
    }
    return spans;
  }

  InlineSpan _mathSpan(
    Widget math, {
    required double measuredWidth,
    required double maxWidth,
  }) {
    if (measuredWidth > maxWidth) {
      // Q9 的兜底：断行也放不下时整体缩放，并明确告警（不做静默裁切）。
      debugPrint(
        '[版式] 公式片段仍超宽（${measuredWidth.toStringAsFixed(1)} > '
        '${maxWidth.toInt()}），已整体缩放，建议改写该题',
      );
      return WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: SizedBox(
          width: maxWidth,
          // 用 FittedBox 而不是 Transform.scale：它会给公式无界宽度布局，
          // 公式按自然尺寸成形后再缩到 384 内，不会触发 RenderLine 溢出。
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: math,
          ),
        ),
      );
    }
    return WidgetSpan(
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      child: math,
    );
  }

  /// 宽度未测出时的零尺寸占位。
  InlineSpan get _placeholder => const WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: SizedBox.shrink(),
      );

  Widget _paragraph(List<InlineSpan> spans, {TextAlign align = TextAlign.start}) =>
      Text.rich(
        TextSpan(children: spans),
        style: bodyStyle(
          widget.profile.bodyFontPx,
          height: widget.profile.lineHeight,
        ),
        strutStyle: StrutStyle(
          fontFamily: kBodyFont,
          fontSize: widget.profile.bodyFontPx,
          height: widget.profile.lineHeight,
        ),
        textAlign: align,
        // 版式必须可复现：不受系统字号缩放影响。
        textScaler: TextScaler.noScaling,
        softWrap: true,
      );
}