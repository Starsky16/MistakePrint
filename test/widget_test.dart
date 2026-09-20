import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mistake_print/main.dart';
import 'package:mistake_print/profiles/profile_store.dart';
import 'package:mistake_print/state/profile_controller.dart';

void main() {
  late Directory tempRoot;

  setUp(() {
    tempRoot = Directory.systemTemp.createTempSync('mistake_print_app_test');
  });

  tearDown(() {
    if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
  });

  /// 注入临时目录，免得真的去碰 path_provider 的平台通道。
  Widget app() => MistakePrintApp(
        controller: ProfileController(
          store: ProfileStore(rootProvider: () async => tempRoot),
        ),
      );

  testWidgets('应用可启动并显示标题', (WidgetTester tester) async {
    await tester.pumpWidget(app());

    expect(find.text('MistakePrint'), findsOneWidget);
  });

  testWidgets('主题启用 Material Design 3', (WidgetTester tester) async {
    await tester.pumpWidget(app());

    final MaterialApp materialApp = tester.widget<MaterialApp>(
      find.byType(MaterialApp),
    );
    expect(materialApp.theme?.useMaterial3, isTrue);
  });

  testWidgets('首页带设置入口与生成按钮', (WidgetTester tester) async {
    await tester.pumpWidget(app());

    expect(find.byTooltip('设置'), findsOneWidget);
    expect(find.text('生成图片'), findsOneWidget);
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