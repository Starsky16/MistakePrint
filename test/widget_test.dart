import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mistake_print/main.dart';

void main() {
  testWidgets('应用可启动并显示标题', (WidgetTester tester) async {
    await tester.pumpWidget(const MistakePrintApp());

    expect(find.text('MistakePrint'), findsOneWidget);
  });

  testWidgets('主题启用 Material Design 3', (WidgetTester tester) async {
    await tester.pumpWidget(const MistakePrintApp());

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.theme?.useMaterial3, isTrue);
  });

  testWidgets('捆绑字体可从 asset 加载', (WidgetTester tester) async {
    const assets = <String>[
      'assets/fonts/NotoSansSC-VariableFont_wght.ttf',
      'assets/fonts/STIXTwoMath-Regular.ttf',
    ];

    for (final asset in assets) {
      final data = await rootBundle.load(asset);
      expect(data.lengthInBytes, greaterThan(0), reason: '$asset 为空');
    }
  });
}