import 'token.dart';

/// 可转义字符：`\$` `\\` `\{` `\}` 输出字面量，不改变状态（计划 §5.1）。
const Set<String> _escapable = <String>{r'$', r'\', '{', '}'};

/// 把题干文本切成 `text` / `inlineMath` / `blockMath` 三类单元。
///
/// 纯函数：不做 IO、不依赖 Flutter，可脱离渲染单独测试。
///
/// [strict] 为 false（默认）时按 lenient 处理未闭合公式：整段退化为纯文本并带上
/// [Token.warning]；为 true 时直接抛 [FormatException]。
List<Token> tokenize(String input, {bool strict = false}) {
  final List<Token> tokens = <Token>[];
  final StringBuffer plain = StringBuffer();

  void flush({String? warning}) {
    if (plain.isEmpty) return;
    tokens.add(Token(TokenKind.text, plain.toString(), warning: warning));
    plain.clear();
  }

  /// 未闭合的公式：lenient 下把定界符与剩余内容整体当纯文本。
  void unclosed(int start, String delimiter) {
    if (strict) {
      throw FormatException('未闭合的公式定界符 $delimiter（起始于 $start）');
    }
    plain.write(input.substring(start));
    flush(warning: '未闭合的公式定界符 $delimiter，已按纯文本输出');
  }

  int i = 0;
  while (i < input.length) {
    final String ch = input[i];

    // 1) 转义：优先于一切定界符判断。
    if (ch == r'\' &&
        i + 1 < input.length &&
        _escapable.contains(input[i + 1])) {
      plain.write(input[i + 1]);
      i += 2;
      continue;
    }

    // 2) 定界符：长定界符优先（`$$` 先于 `$`）。
    if (input.startsWith(r'$$', i)) {
      final int end = _findClose(input, i + 2, r'$$');
      if (end < 0) {
        unclosed(i, r'$$');
        i = input.length;
        continue;
      }
      flush();
      tokens.add(Token(TokenKind.blockMath, input.substring(i + 2, end)));
      i = end + 2;
      continue;
    }
    if (input.startsWith(r'\[', i)) {
      final int end = _findClose(input, i + 2, r'\]');
      if (end < 0) {
        unclosed(i, r'\[…\]');
        i = input.length;
        continue;
      }
      flush();
      tokens.add(Token(TokenKind.blockMath, input.substring(i + 2, end)));
      i = end + 2;
      continue;
    }
    if (input.startsWith(r'\(', i)) {
      final int end = _findClose(input, i + 2, r'\)');
      if (end < 0) {
        unclosed(i, r'\(…\)');
        i = input.length;
        continue;
      }
      flush();
      tokens.add(Token(TokenKind.inlineMath, input.substring(i + 2, end)));
      i = end + 2;
      continue;
    }
    if (ch == r'$') {
      // 价格启发式：`$` 后紧跟数字、且前一字符是空白或中日韩文字时视为字面量。
      if (_isLiteralDollar(input, i)) {
        plain.write(ch);
        i++;
        continue;
      }
      final int end = _findClose(input, i + 1, r'$');
      if (end < 0) {
        unclosed(i, r'$');
        i = input.length;
        continue;
      }
      flush();
      tokens.add(Token(TokenKind.inlineMath, input.substring(i + 1, end)));
      i = end + 1;
      continue;
    }

    // 3) 其余字符原样进入文本通道（含 `\n`，段落切分交给版式层）。
    plain.write(ch);
    i++;
  }

  flush();
  return tokens;
}

/// 在 [start] 起寻找 [close] 定界符；`{…}` 内部不匹配，以保护 `\text{…}` 里的 `$`。
///
/// 返回定界符起始下标；未找到返回 -1。公式不嵌套：公式内出现的同种定界符即结束。
int _findClose(String input, int start, String close) {
  int depth = 0;
  int i = start;
  while (i < input.length) {
    final String ch = input[i];
    if (ch == r'\' &&
        i + 1 < input.length &&
        (input[i + 1] == '{' || input[i + 1] == '}')) {
      // 转义括号不计入深度，也不触发结束。
      i += 2;
      continue;
    }
    if (ch == '{') {
      depth++;
      i++;
      continue;
    }
    if (ch == '}') {
      if (depth > 0) depth--;
      i++;
      continue;
    }
    if (depth == 0 && input.startsWith(close, i)) {
      return i;
    }
    i++;
  }
  return -1;
}

/// 价格启发式：避免「价格 $5，另一个 $8」被当成公式。
///
/// 触发条件收紧为「`$` 后紧跟数字 且 前一字符是空白或中日韩文字」，
/// 这样 `设 $x$ 为正数` 这类常见写法仍能正常进入公式通道。
bool _isLiteralDollar(String input, int i) {
  if (i + 1 >= input.length) return false;
  final int next = input.codeUnitAt(i + 1);
  if (next < 0x30 || next > 0x39) return false;
  if (i == 0) return true;
  final String prev = input[i - 1];
  return _isWhitespace(prev) || _isCjk(prev);
}

bool _isWhitespace(String ch) {
  final int c = ch.codeUnitAt(0);
  return c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D || c == 0x0C;
}

/// 中日韩文字与全角符号（含 CJK 标点、全角形式）。
bool _isCjk(String ch) {
  final int c = ch.codeUnitAt(0);
  return (c >= 0x2E80 && c <= 0x9FFF) ||
      (c >= 0xF900 && c <= 0xFAFF) ||
      (c >= 0xFF00 && c <= 0xFFEF);
}