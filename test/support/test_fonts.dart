import 'package:flutter/services.dart';
import 'package:mistake_print/calibration/calibration_figures.dart';

/// flutter_math_fork 自带的 KaTeX 字体族与文件。
const List<(String, String)> _katexFonts = [
  ('KaTeX_Main', 'KaTeX_Main-Regular.ttf'),
  ('KaTeX_Math', 'KaTeX_Math-Italic.ttf'),
  ('KaTeX_AMS', 'KaTeX_AMS-Regular.ttf'),
  ('KaTeX_Caligraphic', 'KaTeX_Caligraphic-Regular.ttf'),
  ('KaTeX_Fraktur', 'KaTeX_Fraktur-Regular.ttf'),
  ('KaTeX_SansSerif', 'KaTeX_SansSerif-Regular.ttf'),
  ('KaTeX_Script', 'KaTeX_Script-Regular.ttf'),
  ('KaTeX_Typewriter', 'KaTeX_Typewriter-Regular.ttf'),
  ('KaTeX_Size1', 'KaTeX_Size1-Regular.ttf'),
  ('KaTeX_Size2', 'KaTeX_Size2-Regular.ttf'),
  ('KaTeX_Size3', 'KaTeX_Size3-Regular.ttf'),
  ('KaTeX_Size4', 'KaTeX_Size4-Regular.ttf'),
];

/// 手动注册字体。
///
/// 测试环境不会自动注册 pubspec 里声明的字体，必须用 FontLoader 加载，
/// 否则文本会退化成 Ahem 方块字体，标定图毫无意义。
Future<void> loadTestFonts() async {
  const Map<String, String> ownFonts = {
    kBodyFont: 'assets/fonts/NotoSansSC-VariableFont_wght.ttf',
    kSymbolFont: 'assets/fonts/STIXTwoMath-Regular.ttf',
  };
  for (final MapEntry<String, String> entry in ownFonts.entries) {
    final loader = FontLoader(entry.key)..addFont(rootBundle.load(entry.value));
    await loader.load();
  }

  // 包内字体在测试环境不会自动注册，族名需带 packages/<pkg>/ 前缀，
  // 与 flutter_math_fork 内部 make_symbol.dart 拼出的族名保持一致。
  for (final (String family, String file) in _katexFonts) {
    final loader = FontLoader('packages/flutter_math_fork/$family')
      ..addFont(rootBundle.load('packages/flutter_math_fork/lib/katex_fonts/fonts/$file'));
    await loader.load();
  }
}