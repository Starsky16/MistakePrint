// 语料回归检查（计划 P4 成功标准 1）。
//
// 语料原文**永不入库**：默认读仓库外目录 `d:\code\temp\mistake-corpus\`（可用环境
// 变量 `MISTAKE_CORPUS_DIR` 覆盖），目录不存在就整组跳过——保证 `flutter test`
// 不硬依赖仓库外文件。
//
// 跑法（不在默认 `test/` 目录下，所以要显式点名）：
//
//   flutter test tool/corpus_check.dart
//
// 断言的是「预处理有没有真的把裸 LaTeX 认出来」，不涉及渲染；出图高度与墨量靠
// 人工看预览页，不在这里卡。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mistake_print/domain/input_preprocess.dart';
import 'package:mistake_print/domain/token.dart';
import 'package:mistake_print/domain/tokenizer.dart';

const String _defaultDir = r'd:\code\temp\mistake-corpus';

/// 文本通道里不允许再出现的 LaTeX 命令（`\frac` `\sin` …）。
final RegExp _residualCommand = RegExp(r'\\[a-zA-Z]');

void main() {
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
    }
  });
}
