import 'dart:convert';

import 'paper_profile.dart';

/// Profile JSON 的格式版本。
///
/// 这是一份落在用户手机上的持久化数据，版本号必须显式写进文件，否则以后加字段
/// 就没法区分「老版本缺字段」与「内容被改坏」。不匹配时一律当作不可用，
/// 由调用方回落到默认档案。
const int kProfileFormatVersion = 1;

/// 档案 → JSON 文本。
String encodeProfileJson(PaperProfile profile) => jsonEncode(<String, Object?>{
      'version': kProfileFormatVersion,
      'id': profile.id,
      'name': profile.name,
      'dpi': profile.dpi,
      'paperWidthMm': profile.paperWidthMm,
      'printableDotsWidth': profile.printableDotsWidth,
      'minFontPx': profile.minFontPx,
      'bodyFontPx': profile.bodyFontPx,
      'mathFontPx': profile.mathFontPx,
      'lineHeight': profile.lineHeight,
      'threshold': profile.threshold,
      'protectStructureLines': profile.protectStructureLines,
      'structureRunLength': profile.structureRunLength,
      'minLineWidthPx': profile.minLineWidthPx,
      'writePhys': profile.writePhys,
      'oversizeStrategy': profile.oversizeStrategy.name,
      'columns': profile.columns,
      'isCalibrated': profile.isCalibrated,
    });

/// JSON 文本 → 档案；内容不可用时返回 null，**任何情况下都不抛**。
///
/// 存档来自用户手机，可能被截断、被手工改过、或是别的版本写的，所以这里对
/// 「字段缺失 / 类型不对 / 枚举名不认识」一律取默认档案的值，只有三种情况算整份
/// 不可用：不是 JSON、不是对象、版本号不是 [kProfileFormatVersion]。
PaperProfile? decodeProfileJson(String source) {
  final Object? raw;
  try {
    raw = jsonDecode(source);
  } on FormatException {
    return null;
  }
  if (raw is! Map) return null;
  if (raw['version'] != kProfileFormatVersion) return null;

  const PaperProfile fallback = kPaperangP1Default;
  return PaperProfile(
    id: _string(raw['id'], fallback.id),
    name: _string(raw['name'], fallback.name),
    dpi: _int(raw['dpi'], fallback.dpi),
    paperWidthMm: _double(raw['paperWidthMm'], fallback.paperWidthMm),
    printableDotsWidth:
        _int(raw['printableDotsWidth'], fallback.printableDotsWidth),
    minFontPx: _double(raw['minFontPx'], fallback.minFontPx),
    bodyFontPx: _double(raw['bodyFontPx'], fallback.bodyFontPx),
    mathFontPx: _double(raw['mathFontPx'], fallback.mathFontPx),
    lineHeight: _double(raw['lineHeight'], fallback.lineHeight),
    threshold: _int(raw['threshold'], fallback.threshold),
    protectStructureLines: _bool(
      raw['protectStructureLines'],
      fallback.protectStructureLines,
    ),
    structureRunLength:
        _int(raw['structureRunLength'], fallback.structureRunLength),
    minLineWidthPx: _int(raw['minLineWidthPx'], fallback.minLineWidthPx),
    writePhys: _bool(raw['writePhys'], fallback.writePhys),
    oversizeStrategy: _oversizeStrategy(raw['oversizeStrategy'], fallback),
    columns: _int(raw['columns'], fallback.columns),
    isCalibrated: _bool(raw['isCalibrated'], fallback.isCalibrated),
  );
}

String _string(Object? value, String fallback) =>
    value is String ? value : fallback;

/// 兼容 JSON 里把整数写成浮点（`128.0`）的情况。
int _int(Object? value, int fallback) =>
    value is num ? value.toInt() : fallback;

double _double(Object? value, double fallback) =>
    value is num ? value.toDouble() : fallback;

bool _bool(Object? value, bool fallback) =>
    value is bool ? value : fallback;

OversizeStrategy _oversizeStrategy(Object? value, PaperProfile fallback) {
  for (final OversizeStrategy strategy in OversizeStrategy.values) {
    if (strategy.name == value) return strategy;
  }
  return fallback.oversizeStrategy;
}