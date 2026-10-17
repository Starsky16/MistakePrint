// 语料批量出图（真机测试辅助工具，2026-10-17）。
//
// 语料原文**永不入库**：读仓库外语料目录（默认 `~/code/temp/mistake-corpus`
// 【LINUX】/ `d:\code\temp\mistake-corpus`【WIN】，可用环境变量
// `MISTAKE_CORPUS_DIR` 覆盖），目录不存在就整组跳过——保证 `flutter test`
// 不硬依赖仓库外文件。
//
// 跑法（不在默认 `test/` 目录下，所以要显式点名）：
//
//   flutter test tool/corpus_render.dart
//
// 产出：384 宽 1-bit PNG 写入语料同级的 `mistake-corpus-png/`（可用环境变量
// `MISTAKE_CORPUS_PNG_DIR` 覆盖）。文件名规则：
//   - 每条语料出一张「增强全关」基准图：`q01.png`；
//   - q02 / q05 额外出两张 A1 变体：`<名>_minmax.png`（仅 min-max 归一）、
//     `<名>_both.png`（min-max + 亮区 CLAHE 全开），供真机 A1 开关对比。
//
// 每张图在 stdout 打印耗时与黑点占比，q04 的耗时即长图观察项数据。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mistake_print/profiles/paper_profile.dart';
import 'package:mistake_print/render/offscreen/print_renderer.dart';

import '../test/support/test_fonts.dart';

/// 需要出 A1 变体（min-max / 两项全开）的语料名（不带扩展名）。
const Set<String> _enhanceVariants = {'q02', 'q05'};

String _defaultCorpusDir() {
  if (Platform.isWindows) return r'd:\code\temp\mistake-corpus';
  final String? home = Platform.environment['HOME'];
  return home == null ? 'mistake-corpus' : '$home/code/temp/mistake-corpus';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final String corpusPath =
      Platform.environment['MISTAKE_CORPUS_DIR'] ?? _defaultCorpusDir();
  final Directory corpusDir = Directory(corpusPath);

  group('语料出图', () {
    if (!corpusDir.existsSync()) {
      test('语料目录不存在时跳过', () {
        stdout.writeln('[出图] 目录 $corpusPath 不存在，跳过');
      });
      return;
    }

    // 字体必须手动注册，否则文本退化成 Ahem 方块，出图无意义。
    setUpAll(loadTestFonts);

    final String outPath = Platform.environment['MISTAKE_CORPUS_PNG_DIR'] ??
        '${corpusDir.parent.path}/mistake-corpus-png';
    final Directory outDir = Directory(outPath);
    if (!outDir.existsSync()) outDir.createSync(recursive: true);

    final List<File> files = corpusDir
        .listSync()
        .whereType<File>()
        .where((File file) => file.path.toLowerCase().endsWith('.txt'))
        .toList()
      ..sort((File a, File b) => a.path.compareTo(b.path));

    final PrintRenderer renderer = const PrintRenderer();

    for (final File file in files) {
      final String stem =
          file.uri.pathSegments.last.replaceFirst(RegExp(r'\.txt$', caseSensitive: false), '');
      final String raw = file.readAsStringSync();

      final List<(String suffix, PaperProfile profile)> variants = <(String, PaperProfile)>[
        ('', kPaperangP1Default),
        if (_enhanceVariants.contains(stem)) ...<(String, PaperProfile)>[
          ('_minmax', kPaperangP1Default.copyWith(enhanceMinMax: true)),
          (
            '_both',
            kPaperangP1Default.copyWith(enhanceMinMax: true, enhanceClahe: true),
          ),
        ],
      ];

      for (final (String suffix, PaperProfile profile) in variants) {
        testWidgets('$stem${suffix}_渲染并落盘', (WidgetTester tester) async {
          // 渲染走引擎真实异步（Scene::toImage），必须放 runAsync 里，
          // 否则 fake-async 区永远等不到引擎回调而卡死（与 offscreen_render_test 同口径）。
          final PrintImage image = (await tester.runAsync(
            () => renderer.render(raw, profile),
          ))!;
          final String pngPath = '${outDir.path}/$stem$suffix.png';
          File(pngPath).writeAsBytesSync(image.png, flush: true);

          stdout.writeln(
            '[出图] $stem$suffix.png ${image.width}×${image.height} 点 · '
            '黑点 ${(image.blackRatio * 100).toStringAsFixed(2)}% · '
            '排版 ${image.layoutPasses} 轮 · 耗时 ${image.elapsed.inMilliseconds} ms'
            '（profile: minmax=${profile.enhanceMinMax}, clahe=${profile.enhanceClahe}）',
          );
          expect(image.png, isNotEmpty);
          expect(image.width, profile.printableDotsWidth);
          expect(image.height, greaterThan(0));
        });
      }
    }
  });
}
