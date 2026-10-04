// TrueType/OpenType `cmap` 解析（计划 P4 第 3 条「cmap 覆盖断言」）。
//
// 设计约束（见 `d:\code\dev\plans\2026-09-23-mistake-print-p4-impl.md` §7 第 3 条）：
// - **零新依赖**：只用 `dart:typed_data`，不引 `fontTools` 之类的工具；
// - **纯函数**：输入 TTF 字节或路径，输出覆盖集合（`Set<int>`，Unicode 码位）；
// - 需要处理 **format 4**（BMP，platform 3 encoding 1 / platform 0）与
//   **format 12**（UCS-4，含增补平面，platform 3 encoding 10）子表。
//
// 覆盖判定按「码位能映射到非 0 字形」：TrueType 约定 glyph 0 是 `.notdef`，
// cmap 查到 0 即等于该字体没有这个字符（渲染出来是豆腐块）。
//
// 测试环境与构建期脚本都可直接调用，不依赖 Flutter。

import 'dart:io';
import 'dart:typed_data';

/// 一张字体的 cmap 解析结果：码位 → 字形索引。
///
/// 只保留能映射到**非 0** 字形（.notdef）的码位；其余视为缺失。
class FontCmap {
  const FontCmap(this.glyphIds);

  /// 覆盖的码位 → 字形索引（全部 > 0）。
  final Map<int, int> glyphIds;

  /// 覆盖的码位集合。
  Set<int> get covered => glyphIds.keys.toSet();
}

/// 解析 TTF/OTF 字节里的 `cmap`，返回覆盖集合。
///
/// 文件里同时存在 format 4 与 format 12 时以 format 12 为准（超集）。
/// 找不到可用的 cmap 子表时抛 [FormatException]。
FontCmap parseFontCmapFromBytes(Uint8List bytes) {
  final ByteData data = ByteData.sublistView(bytes);

  final Map<String, int> tables = _readTableDirectory(data);
  final int? cmapOffset = tables['cmap'];
  if (cmapOffset == null) {
    throw const FormatException('字体缺少 cmap 表');
  }

  _checkBounds(data, cmapOffset, 4, 'cmap 头');
  final int numTables = data.getUint16(cmapOffset + 2);
  _checkBounds(data, cmapOffset + 4, numTables * 8, 'cmap 编码记录');

  // 选出最佳子表：format 12 优先（覆盖增补平面），其次 format 4。
  int? subtableOffset;
  int bestFormat = -1;
  for (int i = 0; i < numTables; i++) {
    final int record = cmapOffset + 4 + i * 8;
    final int platformId = data.getUint16(record);
    final int encodingId = data.getUint16(record + 2);
    final int offset = data.getUint32(record + 4);
    final int sub = cmapOffset + offset;
    _checkBounds(data, sub, 2, 'cmap 子表头');
    final int format = data.getUint16(sub);

    // Unicode 子表：platform 0（Unicode）；platform 3 只认 encoding 1/10。
    final bool isUnicode = platformId == 0 ||
        (platformId == 3 && (encodingId == 1 || encodingId == 10));
    if (!isUnicode) continue;
    if (format != 4 && format != 12) continue;
    if (format > bestFormat) {
      bestFormat = format;
      subtableOffset = sub;
    }
  }

  if (subtableOffset == null) {
    throw const FormatException('cmap 里没有可用的 format 4 / 12 Unicode 子表');
  }

  final Map<int, int> glyphIds = bestFormat == 12
      ? _parseFormat12(data, subtableOffset)
      : _parseFormat4(data, subtableOffset);
  return FontCmap(glyphIds);
}

/// 解析字体文件（路径）。
FontCmap parseFontCmapFromFile(String path) =>
    parseFontCmapFromBytes(File(path).readAsBytesSync());

/// 读取 sfnt 表目录：tag → 表偏移。
Map<String, int> _readTableDirectory(ByteData data) {
  _checkBounds(data, 0, 12, 'sfnt 头');
  final int version = data.getUint32(0);
  // 0x00010000 = TrueType，0x74727565 ('true')，0x4F54544F ('OTTO')。
  if (version != 0x00010000 && version != 0x74727565 && version != 0x4F54544F) {
    throw FormatException('不是可识别的 sfnt 字体（version=0x${version.toRadixString(16)}）');
  }
  final int numTables = data.getUint16(4);
  _checkBounds(data, 12, numTables * 16, 'sfnt 表目录');
  final Map<String, int> tables = <String, int>{};
  for (int i = 0; i < numTables; i++) {
    final int record = 12 + i * 16;
    final String tag = String.fromCharCodes(
      data.buffer.asUint8List(data.offsetInBytes + record, 4),
    );
    tables[tag] = data.getUint32(record + 8);
  }
  return tables;
}

/// format 4：BMP 区间查表（segment mapping to delta values）。
Map<int, int> _parseFormat4(ByteData data, int table) {
  _checkBounds(data, table, 16, 'format 4 头');
  final int length = data.getUint16(table + 2);
  _checkBounds(data, table, length, 'format 4 表体');
  final int segCountX2 = data.getUint16(table + 6);
  final int segCount = segCountX2 ~/ 2;
  if (segCount == 0) return <int, int>{};

  final int endBase = table + 14;
  final int startBase = endBase + segCountX2 + 2; // 跳过 endCode[] 后的 reservedPad
  final int deltaBase = startBase + segCountX2;
  final int rangeBase = deltaBase + segCountX2;

  _checkBounds(data, endBase, segCountX2 * 4 + 2, 'format 4 映射数组');

  final Map<int, int> result = <int, int>{};
  for (int i = 0; i < segCount; i++) {
    final int end = data.getUint16(endBase + i * 2);
    final int start = data.getUint16(startBase + i * 2);
    final int delta = data.getUint16(deltaBase + i * 2);
    final int rangeOffset = data.getUint16(rangeBase + i * 2);
    if (start > end || start == 0xFFFF) continue;
    // 0xFFFF 是格式 4 的哨兵段，跳过（end == 0xFFFF 且 start == 0xFFFF）。
    for (int code = start; code <= end; code++) {
      if (code > 0xFFFF) break;
      // 代理区不是有效码位。
      if (code >= 0xD800 && code <= 0xDFFF) continue;
      final int glyph = _glyphForFormat4(
        data,
        code: code,
        start: start,
        delta: delta,
        rangeOffset: rangeOffset,
        rangeBase: rangeBase,
        i: i,
      );
      if (glyph > 0) result[code] = glyph;
    }
  }
  return result;
}

int _glyphForFormat4(
  ByteData data, {
  required int code,
  required int start,
  required int delta,
  required int rangeOffset,
  required int rangeBase,
  required int i,
}) {
  if (rangeOffset == 0) {
    return (code + delta) & 0xFFFF;
  }
  // rangeOffset 是相对 rangeOffset 数组本元素的字节偏移；glyphIdArray 以
  // (code - start) 为下标，所以还要减去起始码位的 2 字节/码位偏移。
  final int address = rangeBase + i * 2 + rangeOffset + (code - start) * 2;
  if (address + 2 > data.lengthInBytes) return 0;
  final int glyph = data.getUint16(address);
  if (glyph == 0) return 0;
  return (glyph + delta) & 0xFFFF;
}

/// format 12：UCS-4 分组区间（segmented coverage）。
Map<int, int> _parseFormat12(ByteData data, int table) {
  _checkBounds(data, table, 16, 'format 12 头');
  final int length = data.getUint32(table + 4);
  if (length > 0) _checkBounds(data, table, length, 'format 12 表体');
  final int numGroups = data.getUint32(table + 12);
  _checkBounds(data, table + 16, numGroups * 12, 'format 12 分组');

  final Map<int, int> result = <int, int>{};
  for (int i = 0; i < numGroups; i++) {
    final int group = table + 16 + i * 12;
    final int start = data.getUint32(group);
    final int end = data.getUint32(group + 4);
    final int startGlyph = data.getUint32(group + 8);
    if (start > end) continue;
    // 超出 Unicode 范围直接截断，避免异常数据造成死循环。
    final int last = end > 0x10FFFF ? 0x10FFFF : end;
    for (int code = start; code <= last; code++) {
      if (code >= 0xD800 && code <= 0xDFFF) continue;
      final int glyph = startGlyph + (code - start);
      if (glyph > 0) result[code] = glyph;
    }
  }
  return result;
}

void _checkBounds(ByteData data, int offset, int length, String what) {
  if (offset < 0 || length < 0 || offset + length > data.lengthInBytes) {
    throw FormatException('$what 越界（offset=$offset length=$length total=${data.lengthInBytes}）');
  }
}