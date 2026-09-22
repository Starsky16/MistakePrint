// 输入预处理层（计划 §5.1a）。
//
// 定位：夹在「用户粘贴的原文」与 `tokenize()` 之间的一道**纯函数**。AI 生成的解答
// 通常是「裸 LaTeX + Markdown 噪声」——`\frac{1}{2}` 没有 `$`、`- ` 列表标记、
// emoji、`**加粗**`，而 `tokenize()` 只认四种定界符。这一层负责把前者翻译成后者
// 认识的形态，**`tokenize()` 本身一行不改**，两层可各自独立测试。
//
// 不做 IO、不依赖 Flutter，可脱离渲染单独测试。

/// 输出模式：只打印题干，还是连解答一起打。
enum OutputMode {
  /// 只保留题干段（首个「解：」「第一步」这类分界之前的内容）。
  stemOnly,

  /// 原文全文（默认：粘贴 AI 输出即用）。
  fullText;

  String get label => switch (this) {
        OutputMode.stemOnly => '只打印题干',
        OutputMode.fullText => '题干 + 解答',
      };

  /// 从存档里还原；认不出来一律回落 [fullText]（宁可多打，不可漏打）。
  static OutputMode fromName(Object? raw) {
    for (final OutputMode mode in values) {
      if (mode.name == raw) return mode;
    }
    return OutputMode.fullText;
  }
}

/// 一次预处理的产物。
class PreprocessResult {
  const PreprocessResult(this.text, this.report);

  /// 可以直接喂给 `tokenize()` 的文本。
  final String text;

  final PreprocessReport report;
}

/// 预处理过程中的可见改动。
///
/// 「噪声不静默吞掉」是计划 §5.1a 的硬要求：删掉的 emoji、裁掉的行、嗅探出的公式
/// 都要能报出来，让用户有机会发现「识别错了」。
class PreprocessReport {
  const PreprocessReport({
    this.protectedSpans = 0,
    this.emojiRemoved = 0,
    this.formulasSniffed = 0,
    this.paragraphsDropped = 0,
    this.warnings = const <String>[],
  });

  /// 工序 0 里被占位符保护起来的、本来就有定界符的公式数。
  final int protectedSpans;

  /// 工序 1 里删掉的 emoji 字符数。
  final int emojiRemoved;

  /// 工序 2 / 工序 3 里被包上定界符的公式数。
  final int formulasSniffed;

  /// 题干模式下被裁掉的非空行数。
  final int paragraphsDropped;

  /// 需要提醒用户的问题（例如找不到解答分界）。
  final List<String> warnings;

  bool get isEmpty =>
      protectedSpans == 0 &&
      emojiRemoved == 0 &&
      formulasSniffed == 0 &&
      paragraphsDropped == 0 &&
      warnings.isEmpty;

  /// 输入页那一行小结。
  String get summaryLine {
    if (isEmpty) return '未识别到公式，将按纯文本排版';
    return _parts.join(' · ');
  }

  /// 预览页的提示行（含 warning）。
  List<String> get notices => <String>[..._parts, ...warnings];

  List<String> get _parts => <String>[
        if (formulasSniffed > 0) '识别到 $formulasSniffed 处公式',
        if (protectedSpans > 0) '原有 $protectedSpans 处公式保持原样',
        if (emojiRemoved > 0) '已移除 $emojiRemoved 个表情符号',
        if (paragraphsDropped > 0) '已按「只打印题干」裁掉 $paragraphsDropped 行解答',
      ];
}

/// 把用户粘贴的原文清洗成 `tokenize()` 认识的样子。
///
/// 四道工序见计划 §5.1a：① 保护已有定界符 → ② 行级清洗 → ③ 行级分类 →
/// ④ 行内切分。两种模式的裁剪点在 ② 与 ③ 之间。
PreprocessResult preprocess(String raw, {required OutputMode mode}) {
  final _Counters counters = _Counters();

  // 换行归一必须排在保护之前，否则跨行的 `$$…$$` 会把 `\r` 一起带进占位符原文。
  final String normalized =
      raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

  // 工序 0：已有定界符整段抽出，避免「已知 $x$ 满足 \frac{1}{2}」被二次包裹。
  final _Protector protector = _Protector(normalized);
  final String guarded = protector.guard();

  // 工序 1：行级清洗。
  List<String> lines = guarded
      .split('\n')
      .map((String line) => _cleanLine(line, counters))
      .toList();
  lines = _trimBlankEdges(_collapseBlankLines(lines));

  // 两种模式的裁剪点。
  final List<String> warnings = <String>[];
  if (mode == OutputMode.stemOnly) {
    final int cut = _findSolutionStart(lines);
    if (cut > 0) {
      counters.paragraphsDropped =
          lines.skip(cut).where((String line) => line.trim().isNotEmpty).length;
      lines = _trimBlankEdges(lines.sublist(0, cut));
    } else {
      warnings.add('没找到「解：」这类解答分界，已按全文处理');
    }
  }

  // 工序 2 / 工序 3：逐行分类与行内切分。
  final StringBuffer out = StringBuffer();
  for (int i = 0; i < lines.length; i++) {
    if (i > 0) out.write('\n');
    out.write(_processLine(lines[i], counters));
  }

  return PreprocessResult(
    protector.restore(out.toString()),
    PreprocessReport(
      protectedSpans: protector.count,
      emojiRemoved: counters.emojiRemoved,
      formulasSniffed: counters.formulasSniffed,
      paragraphsDropped: counters.paragraphsDropped,
      warnings: warnings,
    ),
  );
}

// ---------------------------------------------------------------------------
// 工序 0：已有定界符保护
// ---------------------------------------------------------------------------

/// 占位符的起止标记：`\u0001<序号>\u0002`。
///
/// 用控制字符而不是 `@@0@@` 之类：粘贴进来的正文里不可能出现它们，撞不上。
const String _guardOpen = '\u0001';
const String _guardClose = '\u0002';

/// 定界符字面量：Dart 里 `$` 要转义，集中放两处省得满屏 `r'$'`。
const String _dollar = r'$';

/// 嗅探出的行内公式用 `\(…\)` 而不是 `$…$`。
///
/// 原因：`tokenize()` 的价格启发式会把「前一字符是空白、后一字符是数字」的 `$`
/// 当成钱，于是 `$0 < \frac{1}{2} < 1$` 整段退化成纯文本。`\(…\)` 没有这层歧义。
const String _inlineOpen = r'\(';
const String _inlineClose = r'\)';

/// 块级公式照旧用 `$$…$$`：`$$` 长定界符优先，不经过价格启发式。
const String _blockDelimiter = r'$$';

/// 把**已经成对**的公式定界符整段换成占位符，处理完再原样还原。
///
/// 未配对的定界符不算保护对象——那是 `tokenize()` lenient 分支的活。
class _Protector {
  _Protector(this._input);

  final String _input;
  final List<String> _spans = <String>[];

  int get count => _spans.length;

  /// 定界符对：`(开始, 结束)`，长的排在前面（`$$` 先于 `$`）。
  static const List<(String, String)> _delimiters = <(String, String)>[
    (r'$$', r'$$'),
    (r'\[', r'\]'),
    (r'\(', r'\)'),
    (r'$', r'$'),
  ];

  String guard() {
    final StringBuffer out = StringBuffer();
    int i = 0;
    while (i < _input.length) {
      final (String, String)? pair = _delimiterAt(i);
      if (pair != null) {
        final String open = pair.$1;
        final String close = pair.$2;
        final int end = _findClose(i + open.length, close);
        if (end >= 0) {
          _spans.add(_input.substring(i, end + close.length));
          out.write('$_guardOpen${_spans.length - 1}$_guardClose');
          i = end + close.length;
          continue;
        }
        // 没配对：原样吐出，交给 tokenize() 的 lenient 分支。
        out.write(open);
        i += open.length;
        continue;
      }
      if (_input[i] == r'\' && i + 1 < _input.length) {
        // 转义对（`\$` `\\` `\{` `\}`）整体跳过，不参与定界符判定。
        out.write(_input.substring(i, i + 2));
        i += 2;
        continue;
      }
      out.write(_input[i]);
      i++;
    }
    return out.toString();
  }

  /// 判断 [i] 处是不是某个定界符的起点；长定界符优先（`$$` 先于 `$`）。
  (String, String)? _delimiterAt(int i) {
    for (final (String, String) pair in _delimiters) {
      if (!_input.startsWith(pair.$1, i)) continue;
      // 价格启发式与 tokenize() 保持一致：`$5` 里的 `$` 是钱不是公式。
      if (pair.$1 == r'$' && _isLiteralDollar(i)) return null;
      return pair;
    }
    return null;
  }

  /// 找配对的结束定界符；返回其起始下标，找不到返回 -1。
  int _findClose(int start, String close) {
    int i = start;
    while (i < _input.length) {
      // 结束定界符优先于转义判定：`\]` 自己就以反斜杠开头，先跳转义会把它整个漏掉。
      if (_input.startsWith(close, i)) {
        if (close == r'$') {
          // 单个 `$` 既不能被 `$$` 的开头骗走，也不能被 `$5` 这种价格骗走。
          if (_input.startsWith(r'$$', i) || _isLiteralDollar(i)) {
            i += 2;
            continue;
          }
        }
        return i;
      }
      if (_input[i] == r'\' && i + 1 < _input.length) {
        i += 2;
        continue;
      }
      i++;
    }
    return -1;
  }

  /// 价格启发式，判定条件与 `tokenize()` 的 `_isLiteralDollar` 逐字一致。
  bool _isLiteralDollar(int i) {
    if (i + 1 >= _input.length) return false;
    final int next = _input.codeUnitAt(i + 1);
    if (next < 0x30 || next > 0x39) return false;
    if (i == 0) return true;
    final int prev = _input.codeUnitAt(i - 1);
    return prev == 0x20 ||
        prev == 0x09 ||
        prev == 0x0A ||
        prev == 0x0D ||
        prev == 0x0C ||
        _isProseChar(prev);
  }

  /// 还原占位符。占位符里的序号一定落在 `_spans` 范围内。
  String restore(String text) {
    if (_spans.isEmpty) return text;
    final RegExp pattern = RegExp('$_guardOpen([0-9]+)$_guardClose');
    return text.replaceAllMapped(
      pattern,
      (Match match) => _spans[int.parse(match.group(1)!)],
    );
  }
}

// ---------------------------------------------------------------------------
// 工序 1：行级清洗
// ---------------------------------------------------------------------------

/// 行首列表标记：`- `/`* `/`+ ` 一律换成 `· `。
///
/// 换成 `· ` 而不是缩进：热敏纸上省宽度，且 `·` 在版式层被当成正文分隔符，
/// 不会被工序 3 误包进公式。
final RegExp _listMarker = RegExp(r'^(\s*)[-*+]\s+');

String _cleanLine(String line, _Counters counters) {
  String s = line.replaceFirstMapped(
    _listMarker,
    (Match match) => '${match.group(1)}· ',
  );
  // Markdown 粗体标记：热敏纸只有黑白，加粗既渲染不出也只会占宽度。
  s = s.replaceAll('**', '').replaceAll('__', '');
  s = _stripEmoji(s, counters);
  // 全角空格归一为半角，免得行内公式两侧被撑开。
  return s.replaceAll('\u3000', ' ');
}

/// 删除 emoji 区码点并计数。
String _stripEmoji(String s, _Counters counters) {
  final StringBuffer out = StringBuffer();
  for (final int rune in s.runes) {
    if (_isEmoji(rune)) {
      counters.emojiRemoved++;
      continue;
    }
    out.writeCharCode(rune);
  }
  return out.toString();
}

bool _isEmoji(int rune) =>
    (rune >= 0x1F000 && rune <= 0x1FAFF) || // 各类 emoji / 补充符号
    (rune >= 0x2600 && rune <= 0x27BF) || // 杂项符号与装饰符号（✅ ✨ ➡ …）
    (rune >= 0x2B00 && rune <= 0x2BFF) || // 杂项符号与箭头
    rune == 0xFE0F || // 变体选择符
    rune == 0x200D || // 零宽连接符
    rune == 0x20E3; // 键帽组合符

/// 连续空行折叠为一个。
///
/// 版式层把每个 `\n` 当段落边界并插半行段距，空行多了会把图撑得很高。
List<String> _collapseBlankLines(List<String> lines) {
  final List<String> out = <String>[];
  bool previousBlank = false;
  for (final String line in lines) {
    final bool blank = line.trim().isEmpty;
    if (blank && previousBlank) continue;
    out.add(blank ? '' : line);
    previousBlank = blank;
  }
  return out;
}

List<String> _trimBlankEdges(List<String> lines) {
  int start = 0;
  int end = lines.length;
  while (start < end && lines[start].trim().isEmpty) {
    start++;
  }
  while (end > start && lines[end - 1].trim().isEmpty) {
    end--;
  }
  return lines.sublist(start, end);
}

// ---------------------------------------------------------------------------
// 两种模式的裁剪点
// ---------------------------------------------------------------------------

/// 解答分界的行首标记。命中即认为「题干到上一行为止」。
const List<String> _solutionMarkers = <String>[
  '解：',
  '解:',
  '解答',
  '解析',
  '解法',
  '证明：',
  '证明:',
  '第一步',
  '步骤一',
  '分析：',
];

/// 找解答段的起始行；返回 -1 表示没找到（退化为全文）。
///
/// 刻意从第 1 行开始找：若第一行就是「解：」，说明压根没有题干，此时退化更安全。
int _findSolutionStart(List<String> lines) {
  for (int i = 1; i < lines.length; i++) {
    final String trimmed = lines[i].trim();
    for (final String marker in _solutionMarkers) {
      if (trimmed.startsWith(marker)) return i;
    }
  }
  return -1;
}

// ---------------------------------------------------------------------------
// 工序 2 / 工序 3
// ---------------------------------------------------------------------------

String _processLine(String line, _Counters counters) {
  if (line.trim().isEmpty) return line;

  // 含占位符的行已经被工序 0 判定过，不再整行包 `$$`——否则跨行的块级公式会被
  // 包成 `$$…$$…$$`。
  if (!line.contains(_guardOpen)) {
    final String trimmed = line.trim();
    if (!_hasDelimiter(trimmed) && _isFormulaLine(trimmed)) {
      counters.formulasSniffed++;
      return _blockDelimiter + trimmed + _blockDelimiter;
    }
  }
  return _wrapInlineRuns(line, counters);
}

/// 片段里是否已经带了公式定界符（含未配对、未被工序 0 保护的那些）。
bool _hasDelimiter(String s) =>
    s.contains(_dollar) ||
    s.contains(r'\(') ||
    s.contains(r'\)') ||
    s.contains(r'\[') ||
    s.contains(r'\]');

/// 整行是不是一条块级公式。
///
/// 判定前先挖空 `\text{…}` 这类命令的花括号内容：`y = \log u, \quad \text{其中}
/// \quad u = \sin(…)` 含汉字但全在 `\text{}` 里，必须仍判为公式。
bool _isFormulaLine(String trimmed) {
  if (_containsProse(_stripTextCommands(trimmed))) return false;
  return _hasCommand(trimmed) ||
      trimmed.contains('^') ||
      trimmed.contains('_') ||
      _hasStrongOperator(trimmed);
}

/// 只对混合行做行内切分：以正文分隔符为切点切出候选片段，逐个过升级门槛。
String _wrapInlineRuns(String line, _Counters counters) {
  final StringBuffer out = StringBuffer();
  int i = 0;
  while (i < line.length) {
    if (_isProseChar(line.codeUnitAt(i))) {
      out.write(line[i]);
      i++;
      continue;
    }
    int j = i;
    while (j < line.length && !_isProseChar(line.codeUnitAt(j))) {
      j++;
    }
    out.write(_maybeWrap(line.substring(i, j), counters));
    i = j;
  }
  return out.toString();
}

String _maybeWrap(String run, _Counters counters) {
  final String core = run.trim();
  if (core.isEmpty) return run;
  // 已经有定界符（占位符）或残留定界符的片段一律不碰，免得包出嵌套定界符。
  if (core.contains(_guardOpen) || _hasDelimiter(core)) return run;
  if (!_shouldWrapInline(core)) return run;

  counters.formulasSniffed++;
  final int lead = run.length - run.trimLeft().length;
  final int tail = run.length - run.trimRight().length;
  return run.substring(0, lead) +
      _inlineOpen +
      core +
      _inlineClose +
      run.substring(run.length - tail);
}

/// 工序 3 的升级门槛（计划 §5.1a，防假阳性）。
///
/// 没有这道门槛，`大于 0，` 里的孤立 `0`、`两边乘以 2：` 里的孤立 `2` 都会变成
/// 单字符公式 token，测量轮次与版式开销白白翻倍。
///
/// 光靠弱运算符还不够：`Step-by-step` 也有两个 `-`。要求同时带数字或强运算符，
/// 才能把 `4k + 5/3` 收进来而把连字符单词挡在外面。
bool _shouldWrapInline(String core) {
  if (_hasCommand(core)) return true;
  if (core.contains('^') || core.contains('_')) return true;
  if (core.length < 3) return false;
  if (_countOperators(core) < 2) return false;
  return _hasStrongOperator(core) || _hasDigit(core);
}

/// 正文分隔符：中日韩文字与全角标点，外加 `·` 列表标记与通用标点（`— “ ” …`）。
bool _isProseChar(int code) =>
    code == 0x00B7 ||
    (code >= 0x2000 && code <= 0x206F) ||
    (code >= 0x2E80 && code <= 0x9FFF) ||
    (code >= 0xF900 && code <= 0xFAFF) ||
    (code >= 0xFF00 && code <= 0xFFEF);

bool _containsProse(String s) {
  for (int i = 0; i < s.length; i++) {
    if (_isProseChar(s.codeUnitAt(i))) return true;
  }
  return false;
}

/// 含反斜杠命令（`\frac` `\sin` `\log` …）。
bool _hasCommand(String s) {
  for (int i = 0; i + 1 < s.length; i++) {
    if (s[i] != r'\') continue;
    final int next = s.codeUnitAt(i + 1);
    if ((next >= 0x41 && next <= 0x5A) || (next >= 0x61 && next <= 0x7A)) {
      return true;
    }
    i++;
  }
  return false;
}

/// 强运算符：单独出现就足以说明「这是数学」。整行判定用它们。
const String _strongOperators = '=<>±×÷≤≥≠≈∈∉∪∩⊂⊆→⇒⇔';

/// 弱运算符：单独两个不足以定性，得配上数字或强运算符（`4kπ + 5π/3`）。
const String _weakOperators = '+-*/';

bool _hasStrongOperator(String s) {
  for (int i = 0; i < s.length; i++) {
    if (_strongOperators.contains(s[i])) return true;
  }
  return false;
}

bool _hasDigit(String s) {
  for (int i = 0; i < s.length; i++) {
    final int code = s.codeUnitAt(i);
    if (code >= 0x30 && code <= 0x39) return true;
  }
  return false;
}

int _countOperators(String s) {
  int count = 0;
  for (int i = 0; i < s.length; i++) {
    final String ch = s[i];
    if (_strongOperators.contains(ch) || _weakOperators.contains(ch)) count++;
  }
  return count;
}

/// 挖空 `\text{…}` / `\mathrm{…}` / `\mbox{…}` 这类命令的配对花括号内容。
String _stripTextCommands(String s) {
  final StringBuffer out = StringBuffer();
  int i = 0;
  while (i < s.length) {
    final int length = _textCommandLengthAt(s, i);
    if (length > 0) {
      i += length;
      if (i < s.length && s[i] == '{') {
        int depth = 0;
        while (i < s.length) {
          final String ch = s[i];
          if (ch == r'\' && i + 1 < s.length) {
            i += 2;
            continue;
          }
          if (ch == '{') {
            depth++;
          } else if (ch == '}') {
            depth--;
            i++;
            if (depth == 0) break;
            continue;
          }
          i++;
        }
      }
      continue;
    }
    out.write(s[i]);
    i++;
  }
  return out.toString();
}

/// 正文类命令：它们的花括号里装的是「人话」而不是数学。
const List<String> _textCommands = <String>[
  r'\text',
  r'\textrm',
  r'\textnormal',
  r'\mathrm',
  r'\mbox',
  r'\operatorname',
];

int _textCommandLengthAt(String s, int i) {
  for (final String command in _textCommands) {
    if (s.startsWith('$command{', i)) return command.length;
  }
  return 0;
}

/// 预处理过程中的计数器。
class _Counters {
  int emojiRemoved = 0;
  int formulasSniffed = 0;
  int paragraphsDropped = 0;
}
