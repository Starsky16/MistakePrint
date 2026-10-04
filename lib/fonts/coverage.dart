// 字形覆盖断言的计算层（计划 P4 第 3 条「cmap 覆盖断言」）。
//
// 与 `cmap.dart` 分工：`cmap.dart` 只解析单张字体的 cmap；本文件负责「多张字体
// 合起来的覆盖集合 / 缺失列表」，是一个**纯函数**（输入字体路径 + 文本，输出
// 覆盖集合与缺失码位），构建期脚本与单元测试都可直接调用，不依赖 Flutter。

import 'dart:io';

import 'cmap.dart';

/// 一张字体的覆盖结果。
class FontCoverage {
  const FontCoverage(this.path, this.covered);

  /// 字体文件路径（诊断输出用）。
  final String path;

  /// 该字体覆盖的码位（只含能映射到非 0 字形的码位）。
  final Set<int> covered;
}

/// 多张字体合并后的覆盖报告。
class CoverageReport {
  const CoverageReport({required this.covered, required this.missing});

  /// 全部字体合起来的覆盖集合。
  final Set<int> covered;

  /// 抽样文本里没有被任何字体覆盖的码位（升序、去重）。
  final List<int> missing;

  bool get isComplete => missing.isEmpty;

  /// 把缺失码位排成可读的一行（`U+2322` 这类），便于失败信息直接贴出来。
  String describeMissing() => missing
      .map((int cp) => 'U+${cp.toRadixString(16).toUpperCase().padLeft(4, '0')}')
      .join('、');
}

/// 需要字形覆盖的码位判定：跳过控制字符、空白与代理区。
///
/// 换行/制表/空格由排版引擎处理，不需要字形；代理区不是合法码位。
bool needsGlyph(int cp) {
  if (cp < 0x20 || cp == 0x7F) return false; // C0 控制字符 + DEL
  if (cp >= 0x80 && cp <= 0x9F) return false; // C1 控制字符
  if (cp >= 0xD800 && cp <= 0xDFFF) return false; // 代理区
  if (cp == 0x20 || cp == 0x3000 || cp == 0x00A0) return false; // 空格类
  if (cp > 0x10FFFF) return false;
  return true;
}

/// 解析字体文件，返回合并覆盖集合。
///
/// 输入是 `File` 列表或路径列表均可；只读文件，不缓存。
Set<int> coveredCodePoints(Iterable<String> fontPaths) {
  final Set<int> covered = <int>{};
  for (final String path in fontPaths) {
    final FontCmap cmap = parseFontCmapFromBytes(File(path).readAsBytesSync());
    covered.addAll(cmap.covered);
  }
  return covered;
}

/// 计算 [text] 的码位覆盖情况并**在缺失时抛错**：缺失码位会逐个列在异常信息里。
///
/// 这是给「构建期 / debug 期断言」用的入口；只想拿报告不想抛错时用
/// [checkCoverage]。
CoverageReport assertFontCoverage({
  required Iterable<String> fontPaths,
  required String text,
  String? label,
}) {
  final CoverageReport report = checkCoverage(fontPaths: fontPaths, text: text);
  if (report.missing.isNotEmpty) {
    throw FormatException(
      '${label ?? '文本'} 有 ${report.missing.length} 个码位没有任何内置字体覆盖：'
      '${report.describeMissing()}',
    );
  }
  return report;
}

/// 计算 [text] 的码位覆盖情况：[fontPaths] 里任意一张字体覆盖到即算覆盖。
///
/// 纯函数：只读字体文件，无全局状态、无 Flutter 依赖。
CoverageReport checkCoverage({
  required Iterable<String> fontPaths,
  required String text,
}) {
  final Set<int> covered = coveredCodePoints(fontPaths);
  final Set<int> missing = <int>{};
  for (final int cp in text.runes) {
    if (!needsGlyph(cp)) continue;
    if (!covered.contains(cp)) missing.add(cp);
  }
  final List<int> ordered = missing.toList()..sort();
  return CoverageReport(covered: covered, missing: ordered);
}