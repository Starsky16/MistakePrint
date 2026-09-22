// 输入预处理层单测（计划 §5.1a）。
//
// 语料原文不入库，所以这里用**内联摘录**覆盖语料里最刁钻的几行；真实语料的批量
// 回归走 `tool/corpus_check.dart`（默认读仓库外目录，目录不存在时跳过）。

import 'package:flutter_test/flutter_test.dart';
import 'package:mistake_print/domain/input_preprocess.dart';
import 'package:mistake_print/domain/token.dart';
import 'package:mistake_print/domain/tokenizer.dart';

/// 预处理 + 分词，返回 token 列表。
List<Token> tokensOf(String raw, {OutputMode mode = OutputMode.fullText}) =>
    tokenize(preprocess(raw, mode: mode).text);

/// 公式通道的字符总数。
int mathChars(List<Token> tokens) => tokens
    .where((Token token) => token.isMath)
    .fold(0, (int sum, Token token) => sum + token.value.length);

void main() {
  group('工序 0：已有定界符保护', () {
    test(r'成对的 $…$ 原样保留，旁边的裸 LaTeX 单独升级', () {
      final PreprocessResult result = preprocess(
        r'已知 $x$ 满足 \frac{1}{2} 且 x > 0',
        mode: OutputMode.fullText,
      );

      expect(result.report.protectedSpans, 1);
      expect(result.text, contains(r'已知 $x$ 满足'));
      expect(result.text, contains(r'\(\frac{1}{2}\)'));
    });

    test(r'$$…$$ 与 \[…\] 都不会被二次包裹', () {
      final PreprocessResult result = preprocess(
        r'$$a+b$$ 与 \[c+d\]',
        mode: OutputMode.fullText,
      );

      expect(result.report.protectedSpans, 2);
      expect(result.text, r'$$a+b$$ 与 \[c+d\]');
    });

    test('未配对的定界符不算保护对象', () {
      final PreprocessResult result =
          preprocess(r'公式没闭合 $x + 1', mode: OutputMode.fullText);

      expect(result.report.protectedSpans, 0);
      expect(result.text, contains(r'$x + 1'));
    });

    test(r'`$5` 这类价格不被当成公式', () {
      final PreprocessResult result =
          preprocess(r'价格 $5，另一个 $8', mode: OutputMode.fullText);

      expect(result.report.protectedSpans, 0);
      expect(result.text, r'价格 $5，另一个 $8');
    });
  });

  group('工序 1：行级清洗', () {
    test('行首列表标记换成 `· `，层级缩进保留', () {
      final PreprocessResult result = preprocess(
        '-   \\frac{\\pi}{2} + \\frac{\\pi}{3}\n  * \\sin\\theta',
        mode: OutputMode.fullText,
      );

      expect(result.text, contains(r'· \(\frac{\pi}{2} + \frac{\pi}{3}\)'));
      expect(result.text, contains(r'  · \(\sin\theta\)'));
    });

    test('emoji 被删掉并计数', () {
      final PreprocessResult result =
          preprocess('✅ 最终答案：正确 ➡ 继续', mode: OutputMode.fullText);

      expect(result.report.emojiRemoved, 2);
      expect(result.text, ' 最终答案：正确  继续');
    });

    test('连续空行折叠为一个，首尾空行去掉', () {
      final PreprocessResult result =
          preprocess('\n\n第一行\n\n\n\n第二行\n\n', mode: OutputMode.fullText);

      expect(result.text, '第一行\n\n第二行');
    });

    test('全角空格归一为半角', () {
      final PreprocessResult result =
          preprocess('真数\u3000大于 0', mode: OutputMode.fullText);

      expect(result.text, '真数 大于 0');
    });
  });

  group('工序 2：整行公式', () {
    test('不含正文的裸 LaTeX 行包成块级公式', () {
      final PreprocessResult result = preprocess(
        r'  y = \tan\left(2x + \frac{\pi}{4}\right)  ',
        mode: OutputMode.fullText,
      );

      expect(result.report.formulasSniffed, 1);
      expect(
        result.text,
        r'$$y = \tan\left(2x + \frac{\pi}{4}\right)$$',
      );
    });

    test('汉字只出现在 \\text{} 里时仍判为整行公式', () {
      final PreprocessResult result = preprocess(
        r'y = \tan\left(2x + \frac{\pi}{4}\right), \quad \text{其中} \quad t = 2x',
        mode: OutputMode.fullText,
      );

      expect(result.report.formulasSniffed, 1);
      expect(result.text, startsWith(r'$$y = \tan\left(2x'));
    });

    test('英文句子不会被误判成公式', () {
      final PreprocessResult result =
          preprocess('Step-by-step solution', mode: OutputMode.fullText);

      expect(result.report.formulasSniffed, 0);
      expect(result.text, 'Step-by-step solution');
    });
  });

  group('工序 3：行内切分', () {
    test('混合行里的 LaTeX 片段被包成行内公式', () {
      final PreprocessResult result = preprocess(
        r'两边同时加   \frac{\pi}{3}  ：',
        mode: OutputMode.fullText,
      );

      expect(result.text, r'两边同时加   \(\frac{\pi}{3}\)  ：');
    });

    test('孤立数字不升级（防假阳性）', () {
      final PreprocessResult result = preprocess(
        '因为真数必须大于 0，两边乘以 2：',
        mode: OutputMode.fullText,
      );

      expect(result.report.formulasSniffed, 0);
      expect(result.text, '因为真数必须大于 0，两边乘以 2：');
    });

    test('弱运算符要凑够两个、且带数字或强运算符才升级', () {
      // 连字符单词有两个 `-` 但没数字，不进公式通道。
      expect(
        preprocess(r'AB // DE', mode: OutputMode.fullText).text,
        r'AB // DE',
      );
      expect(
        preprocess(r'4kπ + 5π/3', mode: OutputMode.fullText).text,
        r'\(4kπ + 5π/3\)',
      );
      expect(
        preprocess('∠A = 30°，AB', mode: OutputMode.fullText).text,
        '∠A = 30°，AB',
      );
    });
  });

  group('输出模式', () {
    const String text = '求函数 y = \\sin x 的单调区间。\n\n解：\n\n第一步：求导\n\n\\cos x';

    test('题干模式只留解答分界之前的内容', () {
      final PreprocessResult result =
          preprocess(text, mode: OutputMode.stemOnly);

      expect(result.text, contains('求函数'));
      expect(result.text, isNot(contains('第一步')));
      expect(result.report.paragraphsDropped, 3);
    });

    test('全文模式原样通过', () {
      final PreprocessResult result =
          preprocess(text, mode: OutputMode.fullText);

      expect(result.text, contains('第一步'));
      expect(result.report.paragraphsDropped, 0);
    });

    test('找不到分界时退化为全文并给出 warning', () {
      final PreprocessResult result = preprocess(
        r'求 $\frac{AB}{DE}$ 的值。',
        mode: OutputMode.stemOnly,
      );

      expect(result.report.warnings, isNotEmpty);
      expect(result.text, contains(r'$\frac{AB}{DE}$'));
    });

    test('模式名可往返存档，认不出来回落全文', () {
      expect(OutputMode.fromName('stemOnly'), OutputMode.stemOnly);
      expect(OutputMode.fromName('fullText'), OutputMode.fullText);
      expect(OutputMode.fromName('乱七八糟'), OutputMode.fullText);
      expect(OutputMode.fromName(null), OutputMode.fullText);
    });
  });

  // 真实语料的批量回归只走 tool/corpus_check.dart（读仓库外目录），语料原文
  // 永不入库；这里用**合成样例**复刻它的结构特征。
  group('语料结构特征（合成样例）', () {
    const String sample = r'''
我们来一步步求函数

  y = \tan\left(2x + \frac{\pi}{4}\right)  

的单调区间。

第一步：确定定义域

因为正切函数要求   \cos\left(2x + \frac{\pi}{4}\right) \neq 0  ，所以：


2x + \frac{\pi}{4} \neq k\pi + \frac{\pi}{2}

-   \frac{\pi}{2} + \frac{\pi}{4} = \frac{3\pi}{4}  
''';

    test('公式通道不再为空，文本通道不再残留反斜杠命令', () {
      final List<Token> tokens = tokensOf(sample);

      expect(mathChars(tokens), greaterThan(0));
      for (final Token token in tokens.where((Token t) => !t.isMath)) {
        expect(
          RegExp(r'\\[a-zA-Z]').hasMatch(token.value),
          isFalse,
          reason: '文本通道残留了 LaTeX 命令：${token.value}',
        );
      }
    });

    test('题干模式截到「第一步」之前', () {
      final PreprocessResult result =
          preprocess(sample, mode: OutputMode.stemOnly);

      expect(result.text, contains('的单调区间。'));
      expect(result.text, isNot(contains('第一步')));
    });
  });
}
