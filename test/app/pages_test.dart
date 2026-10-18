// P3 页面测试（计划 P3 实施笔记 §3 提交 4a）。
//
// 页面本身不做出图：输入页出图交给注入的假渲染器，分享动作已经由
// test/share/share_service_test.dart 覆盖，这里只断言「页面接线对不对」。

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

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
import 'package:mistake_print/render/raster/binarize.dart';
import 'package:mistake_print/render/raster/png_encode.dart';
import 'package:mistake_print/share/gallery_store.dart';
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
        dpi: 203,
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

/// 内存假相册：save 立即返回一条记录，不碰平台通道。
class FakeGalleryStore extends GalleryStore {
  FakeGalleryStore();

  int savedCount = 0;

  @override
  Future<GalleryImage> save(Uint8List png, {required String name}) async {
    savedCount++;
    return GalleryImage(
      id: '$savedCount',
      uri: 'content://media/external/images/media/$savedCount',
      name: name,
      size: png.length,
      date: DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  @override
  Future<List<GalleryImage>> list() async => const <GalleryImage>[];

  @override
  Future<Uint8List> readBytes(String uri) async => Uint8List(0);

  @override
  Future<void> delete(String uri) async {}

  @override
  Future<void> deleteAll() async {}
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

    testWidgets('未闭合公式按纯文本降级，并把告警带到预览页', (WidgetTester tester) async {
      final FakeRenderer renderer = FakeRenderer(sampleImage());
      await tester.pumpWidget(wrap(
        controller(),
        InputPage(
          renderer: renderer,
          prefsStore: AppPrefsStore(rootProvider: () async => tempRoot),
        ),
      ));

      // 少一个 `$`：分词器 lenient 分支把整段当纯文本（不抛异常），但必须告诉用户。
      await tester.enterText(find.byType(TextField), r'求 $\frac{1}{2} 的值');
      await tester.pump();
      await tester.tap(find.text('生成图片'));
      await tester.pumpAndSettle();

      expect(find.text('预览'), findsOneWidget);
      expect(find.textContaining('未闭合的公式定界符'), findsOneWidget);
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
  });

  testWidgets('预览页展示出图信息与分享入口', (WidgetTester tester) async {
    final FakeGalleryStore store = FakeGalleryStore();
    await tester.pumpWidget(wrap(
      controller(),
      PreviewPage(image: sampleImage(), galleryStore: store),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('384 × 151 点'), findsOneWidget);
    expect(find.textContaining('排版 2 轮'), findsOneWidget);
    expect(find.text('分享 / 发送图片'), findsOneWidget);
    expect(store.savedCount, 1, reason: '进入预览页即写入相册');
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

  testWidgets('设置页可选正文字号并写回档案', (WidgetTester tester) async {
    useTallSurface(tester);
    final ProfileController c = controller();
    await tester.pumpWidget(wrap(c, const SettingsPage()));

    expect(c.profile.bodyFontPx, kPaperangP1Default.bodyFontPx);

    // 点击 DropdownButton 展开，然后选「20 点」
    await tester.tap(find.byType(DropdownButton<double>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('20 点'));
    await tester.pumpAndSettle();

    expect(c.profile.bodyFontPx, 20.0);
    // 公式字号跟随正文同比例缩放：20 × (24/18) ≈ 26.7。
    expect(c.profile.mathFontPx, closeTo(20 * 24 / 18, 0.01));

    // 选 16 点时缩放结果 21.3 会跌破公式字号下限，必须被夹到 24。
    await tester.tap(find.byType(DropdownButton<double>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('16 点'));
    await tester.pumpAndSettle();

    expect(c.profile.bodyFontPx, 16.0);
    expect(c.profile.mathFontPx, 24.0);
  });

  testWidgets('设置页有输出图片管理入口', (WidgetTester tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(wrap(controller(), const SettingsPage()));

    expect(find.text('输出图片管理'), findsOneWidget);
    // 测试环境拿不到目录，占用查询静默失败，副标题回落到默认文案。
    expect(find.text('查看并清理历史出图'), findsOneWidget);
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

  testWidgets('开发者模式重置：P2 用户重置后仍是 P2 内置预设', (WidgetTester tester) async {
    useTallSurface(tester);
    final ProfileController c = controller();
    await tester.pumpWidget(wrap(c, const DeveloperSettingsPage()));

    // 先切到 P2，再调乱一个裸参数。
    unawaited(c.update(kPaperangP2Default));
    await tester.pump();
    sliderOf(tester, '严格阈值').onChangeEnd!(200);
    await tester.pump();
    expect(c.profile.threshold, 200);

    await tester.tap(find.byTooltip('重置为默认值'));
    await tester.pump();

    expect(c.profile.id, 'paperang-p2');
    expect(c.profile.printableDotsWidth, 576);
    expect(c.profile.threshold, kStrictThreshold);
  });

  group('机型下拉', () {
    testWidgets('默认选中 P1', (WidgetTester tester) async {
      useTallSurface(tester);
      final ProfileController c = controller();
      await tester.pumpWidget(wrap(c, const SettingsPage()));

      expect(
        tester.widget<DropdownButton<String>>(
          find.byType(DropdownButton<String>),
        ).value,
        'paperang-p1',
      );
      expect(find.text('作业帮喵喵机 P1'), findsOneWidget);
    });

    testWidgets('选喵喵机 P2 会切换到对应预设并落库', (WidgetTester tester) async {
      useTallSurface(tester);
      final ProfileController c = controller();
      await tester.pumpWidget(wrap(c, const SettingsPage()));

      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('喵喵机 P2').last);
      await tester.pumpAndSettle();

      expect(c.profile.id, 'paperang-p2');
      expect(c.profile.printableDotsWidth, 576);
      expect(c.profile.dpi, 300);
      expect(c.profile.bodyFontPx, 27);
      // 落库与跨重启恢复是 store 级语义（id 随 JSON 持久化），在
      // profile_store_test 里验证；fake-async 区页面 fire-and-forget 的
      // 真实 IO 完成事件不投递，widget 测试够不到那一步。
    });

    testWidgets('「添加机型…」只弹占位提示，不改档案', (WidgetTester tester) async {
      useTallSurface(tester);
      final ProfileController c = controller();
      await tester.pumpWidget(wrap(c, const SettingsPage()));

      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('添加机型…').last);
      await tester.pumpAndSettle();

      expect(find.text('添加机型'), findsOneWidget);
      expect(find.textContaining('后续版本'), findsOneWidget);
      expect(c.profile.id, 'paperang-p1');

      await tester.tap(find.text('知道了'));
      await tester.pumpAndSettle();
    });
  });

  testWidgets('P2 档下正文字号选项按 dpi 缩放（24/27/30/33/35 点）', (WidgetTester tester) async {
    useTallSurface(tester);
    final ProfileController c = controller();
    await tester.pumpWidget(wrap(c, const SettingsPage()));

    unawaited(c.update(kPaperangP2Default));
    await tester.pump();

    await tester.tap(find.byType(DropdownButton<double>).first);
    await tester.pumpAndSettle();

    // P1 选项 16/18/20/22/24 × 300/203 取整。
    expect(find.text('24 点'), findsWidgets);
    expect(find.text('27 点'), findsWidgets);
    expect(find.text('30 点'), findsWidgets);
    expect(find.text('33 点'), findsWidgets);
    expect(find.text('35 点'), findsWidgets);
    expect(find.text('16 点'), findsNothing);
    expect(find.text('18 点'), findsNothing);

    await tester.tap(find.text('24 点').last);
    await tester.pumpAndSettle();

    expect(c.profile.bodyFontPx, 24.0);
    // 数学缩放比 35/27，24×35/27 ≈ 31.1 跌破 P2 的公式下限 35（=24×300/203），被夹住。
    expect(c.profile.mathFontPx, 35.0);
  });

  group('AppPrefsStore', () {
    test('偏好在注入目录里往返一致', () async {
      final AppPrefsStore store = AppPrefsStore(rootProvider: () async => tempRoot);
      expect((await store.load()).outputMode, OutputMode.fullText);

      await store.save(const AppPrefs(outputMode: OutputMode.stemOnly));

      final AppPrefs loaded = await store.load();
      expect(loaded.outputMode, OutputMode.stemOnly);
    });

    test('存档坏掉时回落默认值，不抛', () async {
      final AppPrefsStore store = AppPrefsStore(rootProvider: () async => tempRoot);
      await (await store.file()).writeAsString('{ 半个 JSON');

      final AppPrefs loaded = await store.load();
      expect(loaded.outputMode, OutputMode.fullText);
    });
  });
}