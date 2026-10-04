// cmap 覆盖断言（计划 2026-09-19 §4 P4 第 3 条 / 成功标准 3）。
//
// 自写 TTF cmap 解析器（format 4 与 12，见 lib/fonts/cmap.dart），零新依赖。
// 断言两件事：
// 1. 解析器本身正确：能读出两张内置字体的 cmap，且能识别缺失码位；
// 2. 内置字体**实际覆盖**了「语料用到的全部字符」+「计划点名的教材符号清单」，
//    缺失就失败并列出缺失码位（U+XXXX）。
//
// 边界：语料原文永不入库（在仓库外 `d:\code\temp\mistake-corpus\`），目录不存在时
// 语料那条自动跳过；但**教材符号清单**与解析器自检是仓库内固定输入，CI 里永远跑。

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mistake_print/domain/input_preprocess.dart';
import 'package:mistake_print/fonts/cmap.dart';
import 'package:mistake_print/fonts/coverage.dart';

/// 内置正文/符号字体（与 pubspec.yaml 的 fonts 声明逐字一致）。
const String kNotoSansScPath = 'assets/fonts/NotoSansSC-VariableFont_wght.ttf';

/// 内置数学兜底字体。
const String kStixTwoMathPath = 'assets/fonts/STIXTwoMath-Regular.ttf';

const List<String> kBundledFonts = <String>[
  kNotoSansScPath,
  kStixTwoMathPath,
];

/// 计划 §6.4「图 D：Unicode 覆盖表」点名的教材符号清单，逐组列出。
///
/// 这些字符目前**没有做兜底转换**（那是 1.0 之后的独立任务），但它们必须至少
/// 「有字形」——有字形才谈得上后续把渲染通道接过去；缺失会在打印时变豆腐块。
const Map<String, String> kTextbookSymbols = <String, String>{
  '几何与关系': '▱ ▭ △ ▲ ⊙ ≌ ∽ ⌢ ∠ ⊥ ∥',
  '序号': '① ② ③ ④ ⑤ ⑩ ⑴ ⒈',
  '罗马数字': 'Ⅰ Ⅱ Ⅲ Ⅳ Ⅴ',
  '单位': '℃ Ω µ Å ℉ %',
  '分数与上下标': '½ ⅓ ² ³ ₁ ₂ ⁻¹',
  '箭头': '→ ← ↑ ↓ ⇌ ⟶ ⇒',
  '希腊': 'α β γ θ π Δ Σ ω',
  '中文标点': '《》 「」 …… ～ 、；：',
};

/// 一个**预期必然缺失**的码位：Unicode 非字符 U+FFFE（两张内置字体都不可能映射它）。
///
/// 用来验证「缺失列表真的能报出来」。注意不能用 PUA 0xE000：
/// STIX Two Math 实测对 0xE000 有字形（测试环境加载时不能假设 PUA 必缺）。
const int kAlwaysMissingCodePoint = 0xFFFE;
const String kAlwaysMissingLabel = 'U+FFFE';

void main() {
  group('TTF cmap 解析', () {
    test('两张内置字体都能解析出 cmap，且覆盖数非空', () {
      for (final String path in kBundledFonts) {
        final FontCmap cmap = parseFontCmapFromFile(path);
        expect(cmap.covered, isNotEmpty, reason: '$path 应解析出非空 cmap');
        // 所有覆盖码位必须映射到非 0 字形（glyph 0 是 .notdef）。
        expect(
          cmap.glyphIds.values.every((int glyph) => glyph > 0),
          isTrue,
          reason: '$path 的覆盖集合里不应出现 glyph 0（.notdef）',
        );
      }
    });

    test('解析器同时处理 format 4 与 12：能用真实字体判定单个码位', () {
      final FontCmap noto = parseFontCmapFromFile(kNotoSansScPath);
      final FontCmap stix = parseFontCmapFromFile(kStixTwoMathPath);

      // 中日文与序号：Noto Sans SC 有；数学几何符号：STIX Two Math 有。
      expect(noto.glyphIds.containsKey(0x4E2D), isTrue, reason: 'Noto 应覆盖「中」');
      expect(noto.glyphIds.containsKey(0x2460), isTrue, reason: 'Noto 应覆盖「①」');
      expect(stix.glyphIds.containsKey(0x2322), isTrue, reason: 'STIX 应覆盖「⌢」');
      expect(stix.glyphIds.containsKey(0x224C), isTrue, reason: 'STIX 应覆盖「≌」');

      // 反例：STIX 没有 CJK，Noto 没有「⌢」——缺失判定必须为真。
      expect(stix.glyphIds.containsKey(0x4E2D), isFalse, reason: 'STIX 不应覆盖「中」');
      expect(noto.glyphIds.containsKey(0x2322), isFalse, reason: 'Noto 不应覆盖「⌢」');
    });

    test('format 4 的 idRangeOffset 分支按 (code - start) 定位 glyphIdArray', () {
      // 真实内置字体同时带 format 4/12，解析器优先 format 12，因此 format 4 的
      // idRangeOffset 路径不会被真实字体覆盖；这里用一张手工构造的 format 4
      // 字体把该路径钉死（含 start != 0 的 rangeOffset 段）。
      final FontCmap cmap = parseFontCmapFromBytes(_fakeFontWithFormat4());
      expect(cmap.glyphIds[0x0040], 5, reason: "'@' 应映射到 glyph 5");
      expect(cmap.glyphIds[0x0041], 7, reason: "'A' 应映射到 glyph 7");
      expect(cmap.glyphIds.containsKey(0x0042), isFalse,
          reason: "'B' 不在任何段里，必须判为缺失");
    });

    test('非字体字节与截断字体都会抛 FormatException，不静默返回空集', () {
      expect(
        () => parseFontCmapFromBytes(Uint8List.fromList(List<int>.filled(64, 0x41))),
        throwsA(isA<FormatException>()),
        reason: '垃圾字节必须报错，不能当成「零覆盖」',
      );
      // 合法 sfnt 头 + 合法表目录，但 cmap 表被截断。
      final Uint8List truncated = _fakeFontWithTruncatedCmap();
      expect(
        () => parseFontCmapFromBytes(truncated),
        throwsA(isA<FormatException>()),
        reason: '截断 cmap 必须报错',
      );
    });
  });

  group('教材符号覆盖', () {
    test('计划点名的教材符号清单在内置字体里 100% 有字形', () {
      final String allSymbols = kTextbookSymbols.values.join();
      final CoverageReport report = checkCoverage(
        fontPaths: kBundledFonts,
        text: allSymbols,
      );

      expect(
        report.missing,
        isEmpty,
        reason: '教材符号清单有缺失码位：${report.describeMissing()}',
      );
      // 顺带确认清单本身不是空串（防止断言被写空）。
      expect(allSymbols.replaceAll(' ', '').length, greaterThan(50));
    });

    test('逐组报告覆盖来源，缺失时列出码位', () {
      for (final MapEntry<String, String> entry in kTextbookSymbols.entries) {
        final CoverageReport report = checkCoverage(
          fontPaths: kBundledFonts,
          text: entry.value,
        );
        expect(
          report.missing,
          isEmpty,
          reason: '「${entry.key}」组有缺失码位：${report.describeMissing()}',
        );
      }
    });

    test('缺失列表真的能报出码位：非字符必须缺失', () {
      final String probe = '教材符号 ${String.fromCharCode(kAlwaysMissingCodePoint)}';
      final CoverageReport report = checkCoverage(
        fontPaths: kBundledFonts,
        text: probe,
      );
      expect(report.missing, contains(kAlwaysMissingCodePoint));
      expect(report.isComplete, isFalse);
      expect(
        report.describeMissing(),
        kAlwaysMissingLabel,
        reason: '缺失码位应以 U+XXXX 形式列出',
      );
    });

    test('assertFontCoverage 缺失时抛 FormatException，信息里带码位', () {
      final String probe = String.fromCharCode(kAlwaysMissingCodePoint);
      expect(
        () => assertFontCoverage(
          fontPaths: kBundledFonts,
          text: probe,
          label: '单元测试样例',
        ),
        throwsA(
          isA<FormatException>().having(
            (FormatException e) => e.message,
            'message',
            allOf(contains(kAlwaysMissingLabel), contains('单元测试样例')),
          ),
        ),
      );
    });

    test('控制字符与空白不需要字形，不应计入缺失', () {
      final CoverageReport report = checkCoverage(
        fontPaths: kBundledFonts,
        text: '中 文\n\t\r\u3000\u00a0',
      );
      expect(report.missing, isEmpty, reason: '空白/控制字符不该被当成缺字');
    });
  });

  group('语料码点覆盖', () {
    final Directory dir = Directory(corpusDirPath());
    if (!dir.existsSync()) {
      test('语料目录不存在时跳过', () {
        // ignore: avoid_print
        print('[cmap] 目录 ${dir.path} 不存在，跳过语料码点覆盖断言');
      });
      return;
    }

    final List<File> files = dir
        .listSync()
        .whereType<File>()
        .where((File f) => f.path.toLowerCase().endsWith('.txt'))
        .toList()
      ..sort((File a, File b) => a.path.compareTo(b.path));

    test('${files.length} 条语料的全部码位都被内置字体覆盖', () {
      final Set<int> allMissing = <int>{};
      int totalRunes = 0;
      for (final File file in files) {
        // 走真实预处理（同渲染管线），保证断言的是「实际会送去渲染的文本」。
        final PreprocessResult prepared = preprocess(
          file.readAsStringSync(),
          mode: OutputMode.fullText,
        );
        totalRunes += prepared.text.runes.length;
        final CoverageReport report = checkCoverage(
          fontPaths: kBundledFonts,
          text: prepared.text,
        );
        allMissing.addAll(report.missing);
      }

      final List<int> ordered = allMissing.toList()..sort();
      final String listed = ordered
          .map((int cp) => 'U+${cp.toRadixString(16).toUpperCase().padLeft(4, '0')}')
          .join('、');
      // ignore: avoid_print
      print('[cmap] 语料 ${files.length} 条 / $totalRunes 个码位，'
          '缺失 ${ordered.length} 个${ordered.isEmpty ? '' : '：$listed'}');

      expect(
        ordered,
        isEmpty,
        reason: '语料码位有内置字体无法覆盖的：$listed',
      );
    });
  });
}

/// 造一份「sfnt 头合法、表目录合法、cmap 长度字段指向表外」的字体字节。
Uint8List _fakeFontWithTruncatedCmap() {
  final Uint8List bytes = Uint8List(12 + 16 + 12);
  final ByteData data = ByteData.sublistView(bytes);
  data.setUint32(0, 0x00010000); // TrueType sfnt version
  data.setUint16(4, 1); // numTables = 1
  // 表目录记录：tag='cmap'，checksum=0，offset=28，length=8
  bytes.setRange(12, 16, 'cmap'.codeUnits);
  data.setUint32(20, 28);
  data.setUint32(24, 8);
  // cmap 表体：version=0，numTables=1，然后是一条指向表外的子表偏移。
  data.setUint16(28, 0);
  data.setUint16(30, 1);
  data.setUint16(32, 3); // platformID
  data.setUint16(34, 1); // encodingID
  data.setUint32(36, 0xFFFF); // 子表偏移远超表尾 ⇒ 必须抛 FormatException
  return bytes;
}

/// 造一张只含 format 4 子表的合法 TTF，专门覆盖 idRangeOffset 分支。
///
/// 段 0：start=0x0040、end=0x0041（'@'、'A'），idDelta=0，idRangeOffset=4，
/// glyphIdArray=[5,7]；段 1 是 0xFFFF 哨兵。若实现漏掉 `2*(code - start)` 的
/// 减法，两个码位都会落到表外而查不到——正是这个测试要防的回归。
Uint8List _fakeFontWithFormat4() {
  // sfnt 头 12 + 表目录 16 + cmap 头 4 + 编码记录 8 + format 4 表体 36 = 76。
  final Uint8List bytes = Uint8List(76);
  final ByteData d = ByteData.sublistView(bytes);
  d.setUint32(0, 0x00010000); // TrueType sfnt version
  d.setUint16(4, 1); // numTables = 1
  bytes.setRange(12, 16, 'cmap'.codeUnits);
  d.setUint32(20, 28); // cmap 表偏移
  d.setUint32(24, 48); // cmap 表长度（解析器不校验）

  d.setUint16(28, 0); // cmap version
  d.setUint16(30, 1); // numTables
  d.setUint16(32, 3); // platformID
  d.setUint16(34, 1); // encodingID
  d.setUint32(36, 12); // 子表偏移（相对 cmap 起点）

  const int t = 40; // format 4 子表起点
  d.setUint16(t, 4); // format
  d.setUint16(t + 2, 36); // length
  d.setUint16(t + 4, 0); // language
  d.setUint16(t + 6, 4); // segCountX2 = 2 段
  d.setUint16(t + 8, 4); // searchRange
  d.setUint16(t + 10, 1); // entrySelector
  d.setUint16(t + 12, 0); // rangeShift
  d.setUint16(t + 14, 0x0041); // endCode[0]
  d.setUint16(t + 16, 0xFFFF); // endCode[1]
  d.setUint16(t + 18, 0); // reservedPad
  d.setUint16(t + 20, 0x0040); // startCode[0]
  d.setUint16(t + 22, 0xFFFF); // startCode[1]
  d.setUint16(t + 24, 0); // idDelta[0]
  d.setUint16(t + 26, 0); // idDelta[1]
  d.setUint16(t + 28, 4); // idRangeOffset[0]：glyphIdArray 紧跟其后
  d.setUint16(t + 30, 0); // idRangeOffset[1]
  d.setUint16(t + 32, 5); // glyphIdArray[0] → '@'
  d.setUint16(t + 34, 7); // glyphIdArray[1] → 'A'
  return bytes;
}

/// 与 `test/support/document_measure.dart` 相同的语料目录约定。
String corpusDirPath() =>
    Platform.environment['MISTAKE_CORPUS_DIR'] ?? r'd:\code\temp\mistake-corpus';