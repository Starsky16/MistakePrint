// P3 页面测试（计划 P3 实施笔记 §3 提交 4a）。
//
// 页面本身不做出图：输入页出图交给注入的假渲染器，分享动作已经由
// test/share/share_service_test.dart 覆盖，这里只断言「页面接线对不对」。

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mistake_print/app/developer_settings_page.dart';
import 'package:mistake_print/app/input_page.dart';
import 'package:mistake_print/app/preview_page.dart';
import 'package:mistake_print/app/settings_page.dart';
import 'package:mistake_print/domain/input_preprocess.dart';
import 'package:mistake_print/profiles/paper_profile.dart';
import 'package:mistake_print/profiles/presets.dart';
import 'package:mistake_print/profiles/profile_store.dart';
import 'package:mistake_print/render/offscreen/print_renderer.dart';
import 'package:mistake_print/render/raster/png_encode.dart';
import 'package:mistake_print/state/app_prefs.dart';
import 'package:mistake_print/state/profile_controller.dart';

/// 出图结果的替身。
///
/// PNG 用真实编码器生成一张棋盘格：`Image.memory` 拿到坏字节会抛异常，替身也得
/// 是一张真图。
PrintImage sampleImage() => PrintImage(
      png: encodeBitmap(
        List<List<bool>>.generate(
          151,
          (int y) => List<bool>.generate(384, (int x) => (x + y).isEven),
        ),
        withPhys: true,
      ),
      width: 384,
      height: 151,
      blackDots: 29088,
      elapsed: const Duration(milliseconds: 120),
      layoutPasses: 2,
    );

/// 记录收到的题干并直接返回一张图，不真的跑离屏渲染。
class FakeRenderer extends PrintRenderer {
  FakeRenderer(this.image);

  final PrintImage image;
  final List<String> received = <String>[];

  @override
  Future<PrintImage> render(
    String text,
    PaperProfile profile, {
    RenderProgressCallback? onProgress,
  }) async {
    received.add(text);
    onProgress?.call(0.5, '排版完成');
    return image;
  }
}

/// 只记在内存里的偏好存档。
///
/// `AppPrefsStore` 的落盘是真实文件 IO，在 fake-async 测试区里不会完成；要断言
/// 「切换后确实写回了偏好」，就得把 IO 换成内存。
class FakePrefsStore extends AppPrefsStore {
  FakePrefsStore();

  AppPrefs saved = const AppPrefs();

  @override
  Future<AppPrefs> load() async => saved;

  @override
  Future<void> save(AppPrefs prefs) async => saved = prefs;
}

void main() {
  late Directory tempRoot;

  setUp(() {
    tempRoot = Directory.systemTemp.createTempSync('mistake_print_pages_test');
  });

  tearDown(() {
    if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
  });

  ProfileController controller() => ProfileController(
        store: ProfileStore(rootProvider: () async => tempRoot),
      );

  Widget wrap(ProfileController c, Widget child) => ProfileScope(
        controller: c,
        child: MaterialApp(home: child),
      );

  /// 取某个参数滑杆：参数名被写进了 Slider 的 key，不依赖控件顺序。
  Slider sliderOf(WidgetTester tester, String label) => tester.widget<Slider>(
        find.byKey(ValueKey<String>('dev-param-$label')),
      );

  /// 开发者页比默认的 800×600 测试窗口高得多，懒加载的 ListView 不会构建屏幕外的
  /// 控件，所以先把画布拉大，免得找不到滑杆。
  void useTallSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  group('输入页', () {
    testWidgets('空输入时不能出图，填入样例会解锁', (WidgetTester tester) async {
      await tester.pumpWidget(wrap(
        controller(),
        InputPage(
          renderer: FakeRenderer(sampleImage()),
          prefsStore: AppPrefsStore(rootProvider: () async => tempRoot),
        ),
      ));

      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );

      await tester.tap(find.byTooltip('填入样例'));
      await tester.pump();

      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );
    });

    testWidgets('出图后进入预览页，题干经预处理后传给渲染器', (WidgetTester tester) async {
      final FakeRenderer renderer = FakeRenderer(sampleImage());
      await tester.pumpWidget(wrap(
        controller(),
        InputPage(
          renderer: renderer,
          prefsStore: AppPrefsStore(rootProvider: () async => tempRoot),
        ),
      ));

      await tester.tap(find.byTooltip('填入样例'));
      await tester.pump();
      await tester.tap(find.text('生成图片'));
      await tester.pumpAndSettle();

      // 样例里没有裸 LaTeX，预处理后与原文逐字相同（已有 `$…$` 被保护，不进公式统计）。
      expect(renderer.received, <String>[kSampleText]);
      expect(find.text('预览'), findsOneWidget);
      expect(find.textContaining('384 × 151 点'), findsOneWidget);
    });

    testWidgets('裸 LaTeX 会被预处理层包上定界符', (WidgetTester tester) async {
      final FakeRenderer renderer = FakeRenderer(sampleImage());
      await tester.pumpWidget(wrap(
        controller(),
        InputPage(
          renderer: renderer,
          prefsStore: AppPrefsStore(rootProvider: () async => tempRoot),
        ),
      ));

      await tester.enterText(find.byType(TextField), r'\frac{1}{2} > 0');
      await tester.pump();
      // 输入页要先把识别结果给用户核对，不能等出图才知道认错了。
      expect(find.textContaining('识别到 1 处公式'), findsOneWidget);

      await tester.tap(find.text('生成图片'));
      await tester.pumpAndSettle();

      expect(renderer.received.single, r'$$\frac{1}{2} > 0$$');
      expect(find.textContaining('识别到 1 处公式'), findsOneWidget);
    });

    testWidgets('输出模式写回偏好，并真的用在裁剪上', (WidgetTester tester) async {
      final FakePrefsStore store = FakePrefsStore();
      final FakeRenderer renderer = FakeRenderer(sampleImage());
      await tester.pumpWidget(wrap(
        controller(),
        InputPage(renderer: renderer, prefsStore: store),
      ));

      await tester.tap(find.text(OutputMode.stemOnly.label));
      await tester.pump();
      expect(store.saved.outputMode, OutputMode.stemOnly);

      await tester.enterText(
        find.byType(TextField),
        '求 \\frac{1}{2} 的单调区间。\n\n解：\n\n\\cos x > 0',
      );
      await tester.pump();
      await tester.tap(find.text('生成图片'));
      await tester.pumpAndSettle();

      expect(renderer.received.single, isNot(contains('解：')));
      expect(renderer.received.single, r'求 \(\frac{1}{2}\) 的单调区间。');
    });

    testWidgets('未校准提示条可关掉', (WidgetTester tester) async {
      await tester.pumpWidget(wrap(
        controller(),
        InputPage(
          renderer: FakeRenderer(sampleImage()),
          prefsStore: AppPrefsStore(rootProvider: () async => tempRoot),
        ),
      ));

      expect(find.textContaining('当前用的是默认参数'), findsOneWidget);

      await tester.tap(find.byTooltip('不再提示'));
      await tester.pump();

      expect(find.textContaining('当前用的是默认参数'), findsNothing);
    });

    testWidgets('已校准的档案不再出现提示条', (WidgetTester tester) async {
      final ProfileController c = controller();
      // update 会真的落盘，必须放进 runAsync，否则在 fake-async 区里永久挂起。
      await tester.runAsync(
        () => c.update(kPaperangP1Default.copyWith(isCalibrated: true)),
      );
      await tester.pumpWidget(wrap(
        c,
        InputPage(
          renderer: FakeRenderer(sampleImage()),
          prefsStore: AppPrefsStore(rootProvider: () async => tempRoot),
        ),
      ));

      expect(find.textContaining('当前用的是默认参数'), findsNothing);
    });
  });

  testWidgets('预览页展示出图信息与分享入口', (WidgetTester tester) async {
    await tester.pumpWidget(wrap(
      controller(),
      PreviewPage(image: sampleImage()),
    ));

    expect(find.textContaining('384 × 151 点'), findsOneWidget);
    expect(find.textContaining('排版 2 轮'), findsOneWidget);
    expect(find.text('分享到喵喵机 App'), findsOneWidget);
  });

  testWidgets('设置页选档位会写回档案', (WidgetTester tester) async {
    final ProfileController c = controller();
    await tester.pumpWidget(wrap(c, const SettingsPage()));

    // 默认档案是「标准」档。
    expect(c.thinLinePreset, ThinLinePreset.standard);

    await tester.tap(find.text(ThinLinePreset.off.label));
    await tester.pump();

    expect(c.thinLinePreset, ThinLinePreset.off);
    expect(c.profile.protectStructureLines, isFalse);
    expect(c.profile.promoteSubDotStrokes, isFalse);
    expect(find.textContaining('只做阈值判定'), findsOneWidget);
  });

  testWidgets('设置页有打印校准入口，点进去是校准向导', (WidgetTester tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(wrap(controller(), const SettingsPage()));

    expect(find.text('打印校准'), findsOneWidget);

    await tester.tap(find.text('打印校准'));
    await tester.pumpAndSettle();

    expect(find.text('汇总预览'), findsOneWidget);
    expect(find.text('生成校准条并分享'), findsOneWidget);
  });

  testWidgets('设置页连点版本号 7 次进开发者模式', (WidgetTester tester) async {
    // 设置页多了「校准」分区后版本号落到了默认视口之外，先拉长画布再点。
    useTallSurface(tester);
    await tester.pumpWidget(wrap(controller(), const SettingsPage()));

    for (int i = 0; i < 7; i++) {
      await tester.tap(find.text('MistakePrint'));
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(find.text('开发者模式'), findsOneWidget);
  });

  testWidgets('开发者模式改裸参数后档位变自定义', (WidgetTester tester) async {
    useTallSurface(tester);
    final ProfileController c = controller();
    await tester.pumpWidget(wrap(c, const DeveloperSettingsPage()));

    expect(find.text('标准'), findsOneWidget);

    // 直接把滑杆的回调调起来，比对像素坐标更稳。
    sliderOf(tester, '严格阈值').onChangeEnd!(200);
    await tester.pump();

    expect(c.profile.threshold, 200);
    expect(c.thinLinePreset, isNull);
    expect(find.text('自定义'), findsOneWidget);
  });

  testWidgets('开发者模式可一键重置回默认值', (WidgetTester tester) async {
    useTallSurface(tester);
    final ProfileController c = controller();
    await tester.pumpWidget(wrap(c, const DeveloperSettingsPage()));

    sliderOf(tester, '严格阈值').onChangeEnd!(200);
    await tester.pump();
    await tester.tap(find.byTooltip('重置为默认值'));
    await tester.pump();

    expect(c.profile, kPaperangP1Default);
  });

  group('AppPrefsStore', () {
    test('偏好在注入目录里往返一致', () async {
      final AppPrefsStore store = AppPrefsStore(rootProvider: () async => tempRoot);
      expect((await store.load()).calibrationHintDismissed, isFalse);
      expect((await store.load()).outputMode, OutputMode.fullText);

      await store.save(const AppPrefs(
        calibrationHintDismissed: true,
        outputMode: OutputMode.stemOnly,
      ));

      final AppPrefs loaded = await store.load();
      expect(loaded.calibrationHintDismissed, isTrue);
      expect(loaded.outputMode, OutputMode.stemOnly);
    });

    test('存档坏掉时回落默认值，不抛', () async {
      final AppPrefsStore store = AppPrefsStore(rootProvider: () async => tempRoot);
      await (await store.file()).writeAsString('{ 半个 JSON');

      final AppPrefs loaded = await store.load();
      expect(loaded.calibrationHintDismissed, isFalse);
      expect(loaded.outputMode, OutputMode.fullText);
    });
  });
}