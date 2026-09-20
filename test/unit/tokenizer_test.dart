import 'package:flutter_test/flutter_test.dart';
import 'package:mistake_print/domain/token.dart';
import 'package:mistake_print/domain/tokenizer.dart';

void main() {
  group('分词：定界符', () {
    test(r'$…$ 切出行内公式', () {
      final List<Token> tokens = tokenize(r'设 $x$ 为正数');
      expect(
        tokens.map((Token t) => t.kind),
        <TokenKind>[TokenKind.text, TokenKind.inlineMath, TokenKind.text],
      );
      expect(tokens[0].value, '设 ');
      expect(tokens[1].value, 'x');
      expect(tokens[2].value, ' 为正数');
    });

    test(r'$$…$$ 切出块级公式，且长定界符优先', () {
      final List<Token> tokens = tokenize(r'$$\frac{a}{b}$$');
      expect(tokens.length, 1);
      expect(tokens.single.kind, TokenKind.blockMath);
      expect(tokens.single.value, r'\frac{a}{b}');
    });

    test(r'\[…\] 等价块级，\(…\) 等价行内', () {
      final List<Token> block = tokenize(r'\[a+b\]');
      expect(block.single.kind, TokenKind.blockMath);
      expect(block.single.value, 'a+b');

      final List<Token> inline = tokenize(r'\(a+b\)');
      expect(inline.single.kind, TokenKind.inlineMath);
      expect(inline.single.value, 'a+b');
    });

    test('公式内不嵌套：公式内的定界符即结束', () {
      final List<Token> tokens = tokenize(r'$$a$b$$');
      expect(tokens.single.kind, TokenKind.blockMath);
      expect(tokens.single.value, r'a$b');
    });

    test(r'\text{…} 内的 $ 不结束公式', () {
      final List<Token> tokens = tokenize(r'$\text{价格 $5}$');
      expect(tokens.single.kind, TokenKind.inlineMath);
      expect(tokens.single.value, r'\text{价格 $5}');
    });

    test(r'花括号内的 @ 与转义括号不影响结束判定', () {
      final List<Token> tokens = tokenize(r'$a\{b\}c$ 后续');
      expect(tokens.first.kind, TokenKind.inlineMath);
      expect(tokens.first.value, r'a\{b\}c');
      expect(tokens.last.value, ' 后续');
    });

    test(r'花括号未闭合时不会误判为结束', () {
      final List<Token> tokens = tokenize(r'$\frac{a}{b}$x');
      expect(tokens.first.kind, TokenKind.inlineMath);
      expect(tokens.first.value, r'\frac{a}{b}');
      expect(tokens.last.value, 'x');
    });
  });

  group('分词：转义与字面量', () {
    test(r'\$ 输出字面量且不进入公式', () {
      final List<Token> tokens = tokenize(r'价格 \$100');
      expect(tokens.single.kind, TokenKind.text);
      expect(tokens.single.value, r'价格 $100');
    });

    test(r'\\ \{ \} 输出字面量', () {
      final List<Token> tokens = tokenize(r'a\\b\{c\}');
      expect(tokens.single.value, r'a\b{c}');
    });

    test(r'价格启发式：$ 后紧跟数字且前一字符是空白/中文 → 字面量', () {
      final List<Token> tokens = tokenize(r'价格为 $5，另一个 $8');
      expect(tokens.single.kind, TokenKind.text);
      expect(tokens.single.value, r'价格为 $5，另一个 $8');
    });

    test(r'开头即 $ 加数字按字面量处理', () {
      final List<Token> tokens = tokenize(r'$5 元');
      expect(tokens.single.kind, TokenKind.text);
    });

    test(r'$ 后是字母时不触发价格启发式', () {
      final List<Token> tokens = tokenize(r'设$x$为正数');
      expect(tokens[1].kind, TokenKind.inlineMath);
      expect(tokens[1].value, 'x');
    });

    test('全角与半角原样保留', () {
      final List<Token> tokens = tokenize('ＡＢＣ abc');
      expect(tokens.single.value, 'ＡＢＣ abc');
    });
  });

  group('分词：未闭合', () {
    test('lenient：退化为纯文本并带 warning', () {
      final List<Token> tokens = tokenize(r'未闭合 $x');
      expect(tokens.single.kind, TokenKind.text);
      expect(tokens.single.value, r'未闭合 $x');
      expect(tokens.single.warning, isNotNull);
    });

    test('strict：抛 FormatException', () {
      expect(() => tokenize(r'未闭合 $x', strict: true), throwsFormatException);
    });
  });

  group('分词：结构', () {
    test('文本 token 保留 \\n，段落切分交给版式层', () {
      final List<Token> tokens = tokenize('第一行\n第二行');
      expect(tokens.single.value, '第一行\n第二行');
    });

    test('空输入返回空列表', () {
      expect(tokenize(''), isEmpty);
    });

    test('多段混排顺序正确', () {
      final List<Token> tokens = tokenize(r'前 $a$ 中 $$b$$ 后');
      expect(
        tokens.map((Token t) => t.kind),
        <TokenKind>[
          TokenKind.text,
          TokenKind.inlineMath,
          TokenKind.text,
          TokenKind.blockMath,
          TokenKind.text,
        ],
      );
    });
  });
}