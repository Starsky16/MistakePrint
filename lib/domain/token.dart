/// 词法单元类型（计划 §5.1）。
enum TokenKind {
  /// 普通文本（其中可能含 `\n` 段落换行）。
  text,

  /// 行内公式（`$…$` 或 `\(…\)`）。
  inlineMath,

  /// 块级公式（`$$…$$` 或 `\[…\]`）。
  blockMath,
}

/// 分词结果中的一个单元。
///
/// 纯数据，不持有任何渲染资源：分词器可脱离 Flutter 单独测试。
class Token {
  const Token(this.kind, this.value, {this.warning});

  final TokenKind kind;

  /// [TokenKind.text] 时是字面量文本；公式时是**不含定界符**的 TeX 源码。
  final String value;

  /// 需要提醒用户的问题（例如公式未闭合），正常为 null。
  final String? warning;

  /// 是否为公式通道（行内或块级）。
  bool get isMath => kind != TokenKind.text;

  @override
  String toString() => 'Token(${kind.name}, $value)';
}