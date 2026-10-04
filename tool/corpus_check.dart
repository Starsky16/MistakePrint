// 语料回归检查（计划 P4 成功标准 1 + 标准 5/6）。
//
// 语料原文**永不入库**：默认读仓库外目录 `d:\code\temp\mistake-corpus\`（可用环境
// 变量 `MISTAKE_CORPUS_DIR` 覆盖），目录不存在就整组跳过——保证 `flutter test`
// 不硬依赖仓库外文件。
//
// 跑法（不在默认 `test/` 目录下，所以要显式点名）：
//
//   flutter test tool/corpus_check.dart
//
// 断言两层：
// 1. 预处理层——裸 LaTeX 有没有真的被认出来（公式通道 > 0、文本通道零残留命令）；
// 2. 渲染测量层（标准 5/6）——把预处理结果按 P1 档案真实排版一次，逐公式片段量
//    渲染宽度：任何片段都不得超过目标宽度（显式容差见 `kCorpusWidthToleranceDots`），
//    超宽片段必须走「整体缩放」兜底（`degraded`，有告警）而不是被静默裁切。
//
// 为什么靠片段宽度而不是抓图：Flutter 段落对超宽内容静默裁剪，不报异常、像素图也
// 只有目标宽度，详见 test/widget/horizontal_overflow_test.dart 的实测记录。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mistake_print/domain/input_preprocess.dart';
import 'package:mistake_print/domain/token.dart';
import 'package:mistake_print/domain/tokenizer.dart';
import 'package:mistake_print/profiles/paper_profile.dart';

import '../test/support/document_measure.dart';
import '../test/support/test_fonts.dart';

const String _defaultDir = r'd:\code\temp\mistake-corpus';

/// 文本通道里不允许再出现的 LaTeX 命令（`\frac` `\sin` …）。
final RegExp _residualCommand = RegExp(r'\\[a-zA-Z]');

/// 水平溢出的显式容差（点）。与 `test/widget/horizontal_overflow_test.dart` 同口径：
/// 0.5 点用于吸收浮点排版舍入，远小于 1 个打印机点，不会放过真实溢出。
const double kCorpusWidthToleranceDots = 0.5;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final String dirPath =
      Platform.environment['MISTAKE_CORPUS_DIR'] ?? _defaultDir;
  final Directory dir = Directory(dirPath);

  group('语料回归', () {
    if (!dir.existsSync()) {
      test('语料目录不存在时跳过', () {
        stdout.writeln('[语料] 目录 $dirPath 不存在，跳过回归检查');
      });
      return;
    }

    // 字体必须手动注册，否则文本退化成 Ahem 方块，宽度测量失去意义。
    setUpAll(loadTestFonts);

    final List<File> files = dir
        .listSync()
        .whereType<File>()
        .where((File file) => file.path.toLowerCase().endsWith('.txt'))
        .toList()
      ..sort((File a, File b) => a.path.compareTo(b.path));

    for (final File file in files) {
      final String name = file.uri.pathSegments.last;

      test(name, () {
        final String raw = file.readAsStringSync();
        final PreprocessResult full =
            preprocess(raw, mode: OutputMode.fullText);
        final List<Token> tokens = tokenize(full.text);
        final int mathChars = tokens
            .where((Token token) => token.isMath)
            .fold(0, (int sum, Token token) => sum + token.value.length);

        expect(
          mathChars,
          greaterThan(0),
          reason: '公式通道为空：预处理没从这段原文里认出任何公式',
        );

        for (final Token token in tokens.where((Token t) => !t.isMath)) {
          expect(
            _residualCommand.hasMatch(token.value),
            isFalse,
            reason: '文本通道残留 LaTeX 命令：${token.value}',
          );
        }

        final PreprocessResult stem =
            preprocess(raw, mode: OutputMode.stemOnly);
        expect(
          stem.text.length,
          lessThanOrEqualTo(full.text.length),
          reason: '题干模式不该比全文还长',
        );

        stdout.writeln(
          '[语料] $name 原文 ${raw.length} 字符 → '
          '全文 ${full.text.length}（公式 ${full.report.formulasSniffed} 处 / '
          '$mathChars 字符，原有定界符 ${full.report.protectedSpans} 处，'
          '表情 ${full.report.emojiRemoved} 个，warning '
          '${full.report.warnings.length} 条）· 题干 ${stem.text.length} 字符',
        );
      });

      testWidgets('$name · 渲染无水平溢出（标准 5/6）', (WidgetTester tester) async {
        final String raw = file.readAsStringSync();
        final PreprocessResult full =
            preprocess(raw, mode: OutputMode.fullText);
        final DocumentMeasure measured = await measureTokens(
          tester,
          tokenize(full.text),
          profile: kPaperangP1Default,
        );
        final double target = kPaperangP1Default.printableDotsWidth.toDouble();
        final List<FormulaFragment> over =
            measured.overflow(target, tolerance: kCorpusWidthToleranceDots);
        final List<FormulaFragment> silent =
            measured.silentOverflow(target, tolerance: kCorpusWidthToleranceDots);
        final double widest = measured.fragments.isEmpty
            ? 0
            : measured.fragments
                .map((FormulaFragment f) => f.widthDots)
                .reduce((double a, double b) => a > b ? a : b);

        stdout.writeln(
          '[语料·溢出] $name 公式片段 ${measured.fragments.length} 个，'
          '最宽 ${widest.toStringAsFixed(1)} 点（目标 ${target.toInt()} + '
          '容差 $kCorpusWidthToleranceDots），超宽 ${over.length} 个，'
          '其中已缩放兜底 ${over.where((f) => f.degraded).length} 个',
        );

        // 成功标准 5：渲染出的任何公式片段都不得超过目标宽度（容差显式给出）。
        // 唯一允许超宽的情形是「整体缩放兜底」——它会把片段缩到目标宽度内并告警。
        expect(
          silent,
          isEmpty,
          reason: '$name 出现静默裁切（片段超宽却未走缩放兜底）：'
              '${silent.map((f) => f.toString()).join('; ')}',
        );
        // 成功标准 6：超宽样例走既定策略时不得静默裁切，且缩放兜底必须真的发生。
        for (final FormulaFragment f in over) {
          expect(
            f.degraded,
            isTrue,
            reason: '$name 的片段 ${f.label} 宽 ${f.widthDots.toStringAsFixed(1)} 点，'
                '超过目标 ${target.toInt()} 点却未标记整体缩放',
          );
        }
        // 渲染根的宽度仍须精确等于目标宽度（缩放兜底也不许把画布撑宽）。
        expect(measured.widgetSize.width, target,
            reason: '$name 的渲染根宽度应精确等于目标宽度');
        expect(measured.widgetSize.height, greaterThan(0),
            reason: '$name 应渲染出非空内容');
      });
    }
  });
}
