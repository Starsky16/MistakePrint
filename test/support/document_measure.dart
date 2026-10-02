import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mistake_print/domain/input_preprocess.dart';
import 'package:mistake_print/domain/token.dart';
import 'package:mistake_print/domain/tokenizer.dart';
import 'package:mistake_print/profiles/paper_profile.dart';
import 'package:mistake_print/render/document_view.dart';
import 'package:mistake_print/render/math/flutter_math_renderer.dart';
import 'package:mistake_print/render/math/math_renderer.dart';

/// 一次公式片段的渲染测量。
class FormulaFragment {
  const FormulaFragment({
    required this.tex,
    required this.label,
    required this.widthDots,
    required this.oversize,
    required this.degraded,
  });

  /// 原始 TeX（断行前的整段公式）。
  final String tex;

  /// `whole` 或 `part i/N`。
  final String label;

  /// 该片段按目标宽度渲染时的自然宽度（点）。
  final double widthDots;

  /// 整段公式是否超过目标宽度。
  final bool oversize;

  /// 是否走到「整体缩放」兜底（`FittedBox(scaleDown)`），即片段本身仍超宽。
  final bool degraded;

  @override
  String toString() => 'FormulaFragment($label, ${widthDots.toStringAsFixed(1)} 点, '
      'oversize=$oversize, degraded=$degraded, tex=${tex.length > 40 ? '${tex.substring(0, 40)}…' : tex})';
}

/// 一次「按目标宽度测量」的结果。
class DocumentMeasure {
  const DocumentMeasure(this.fragments, this.widgetSize);

  /// 本次渲染上报的全部公式片段。
  final List<FormulaFragment> fragments;

  /// 渲染根的尺寸（宽度应精确等于目标宽度）。
  final Size widgetSize;

  /// 超过 [printableWidth] 的片段（容差已由断言侧显式给出）。
  List<FormulaFragment> overflow(double printableWidth, {double tolerance = 0.0}) =>
      fragments.where((FormulaFragment f) => f.widthDots > printableWidth + tolerance).toList();

  /// 未被显式缩放兜底、却超过目标宽度的片段——这些就是「静默裁切」的候选。
  List<FormulaFragment> silentOverflow(double printableWidth, {double tolerance = 0.0}) =>
      overflow(printableWidth, tolerance: tolerance)
          .where((FormulaFragment f) => !f.degraded)
          .toList();
}

/// 把文档按目标宽度渲染一次，收集公式片段宽度与渲染根尺寸。
///
/// 为什么这样测：Flutter 的 `RenderParagraph` 对超宽内容**静默裁剪**，不会抛
/// overflow 异常，`getBoxesForSelection` 也会把 `box.right` 钳在约束内。因此
/// 「有没有水平溢出」只能量**片段自身的自然宽度**（`debugFormulaSink`），再用
/// 「是否走了缩放兜底」区分「明确缩到 384」和「被悄悄切掉」。
///
/// 调用方需自行保证已 `TestWidgetsFlutterBinding.ensureInitialized()`，并在 `setUpAll`
/// 里 `await loadTestFonts()`（字体不注册的话文本会退化成 Ahem 方块）。
Future<DocumentMeasure> measureAtPrintableWidth(
  WidgetTester tester,
  String rawText, {
  required PaperProfile profile,
  OutputMode mode = OutputMode.fullText,
  MathRenderer renderer = const FlutterMathRenderer(),
  Size surface = const Size(384, 20000),
}) async {
  final PreprocessResult prepared = preprocess(rawText, mode: mode);
  return measureTokens(tester, tokenize(prepared.text), profile: profile, renderer: renderer, surface: surface);
}

/// [measureAtPrintableWidth] 的分词入口，便于调用方复用已预处理的结果。
Future<DocumentMeasure> measureTokens(
  WidgetTester tester,
  List<Token> tokens, {
  required PaperProfile profile,
  MathRenderer renderer = const FlutterMathRenderer(),
  Size surface = const Size(384, 20000),
}) async {
  final List<FormulaFragment> fragments = <FormulaFragment>[];
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
          child: SizedBox(
            key: key,
            width: profile.printableDotsWidth.toDouble(),
            child: DocumentView(
              tokens: tokens,
              profile: profile,
              renderer: renderer,
              debugFormulaSink: (
                String tex,
                String label,
                double width,
                bool oversize,
                bool degraded,
              ) {
                fragments.add(FormulaFragment(
                  tex: tex,
                  label: label,
                  widthDots: width,
                  oversize: oversize,
                  degraded: degraded,
                ));
              },
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final Size size = tester.getSize(find.byKey(key));
  return DocumentMeasure(fragments, size);
}

/// 仓库内打包字体路径（供 cmap 覆盖断言使用）。
const String kNotoSansScPath = 'assets/fonts/NotoSansSC-VariableFont_wght.ttf';

/// 仓库内数学兜底字体路径。
const String kStixTwoMathPath = 'assets/fonts/STIXTwoMath-Regular.ttf';

/// 默认语料目录：**原文永不入库**，目录不存在时调用方应整组跳过。
///
/// 与 `tool/corpus_check.dart` 保持同一约定（`MISTAKE_CORPUS_DIR` 可覆盖）。
String corpusDirPath() =>
    Platform.environment['MISTAKE_CORPUS_DIR'] ?? r'd:\code\temp\mistake-corpus';

/// 列出语料目录里的 `.txt`（按路径排序）；目录不存在时返回空表。
List<File> corpusFiles({String? dirPath}) {
  final Directory dir = Directory(dirPath ?? corpusDirPath());
  if (!dir.existsSync()) return <File>[];
  return dir
      .listSync()
      .whereType<File>()
      .where((File f) => f.path.toLowerCase().endsWith('.txt'))
      .toList()
    ..sort((File a, File b) => a.path.compareTo(b.path));
}