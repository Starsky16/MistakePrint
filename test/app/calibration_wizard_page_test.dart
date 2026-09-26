// P3-4b 校准向导页测试：只断言接线（出图交给注入的假实现，不跑离屏管线）。
//
// 两条硬要求在这里落地：
// 1. 六项全都跳过时保存不改档案，且保存后照样能出图（计划 §5.8「不做强制引导」）；
// 2. 答过的项按 applyCalibration 的规则写回档案。

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mistake_print/app/calibration/calibration_wizard_page.dart';
import 'package:mistake_print/app/input_page.dart';
import 'package:mistake_print/calibration/calibration_strip.dart';
import 'package:mistake_print/profiles/paper_profile.dart';
import 'package:mistake_print/profiles/presets.dart';
import 'package:mistake_print/profiles/profile_store.dart';
import 'package:mistake_print/render/offscreen/print_renderer.dart';
import 'package:mistake_print/render/raster/binarize.dart';
import 'package:mistake_print/render/raster/png_encode.dart';
import 'package:mistake_print/state/app_prefs.dart';
import 'package:mistake_print/state/profile_controller.dart';

/// 真 PNG：PreviewPage 用 Image.memory 展示，坏字节会让它抛异常。
PrintImage sampleImage({int height = 1200}) => PrintImage(
      png: encodeBitmap(
        List<List<bool>>.generate(
          height,
          (int y) => List<bool>.generate(384, (int x) => (x + y) % 3 == 0),
        ),
        withPhys: true,
      ),
      width: 384,
      height: height,
      blackDots: 384 * height ~/ 3,
      elapsed: const Duration(milliseconds: 300),
      layoutPasses: 2,
    );

/// 记录收到的档案并直接返回一张图，不真的跑离屏管线。
class FakeStripRenderer extends CalibrationStripRenderer {
  FakeStripRenderer(this.strip);

  final CalibrationStripImage strip;
  final List<PaperProfile> received = <PaperProfile>[];

  @override
  Future<CalibrationStripImage> render(
    PaperProfile profile, {
    RenderProgressCallback? onProgress,
  }) async {
    received.add(profile);
    onProgress?.call(1, '完成');
    return strip;
  }
}

/// 汇总预览里的「用新参数出一张样例」用到的假出图器。
class FakeRenderer extends PrintRenderer {
  FakeRenderer(this.image);

  final PrintImage image;
  final List<(String, PaperProfile)> received = <(String, PaperProfile)>[];

  @override
  Future<PrintImage> render(
    String text,
    PaperProfile profile, {
    RenderProgressCallback? onProgress,
  }) async {
    received.add((text, profile));
    onProgress?.call(1, '完成');
    return image;
  }
}

void main() {
  late Directory tempRoot;

  setUp(() {
    tempRoot = Directory.systemTemp.createTempSync('mistake_print_wizard_test');
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

  /// 向导页比默认视口高得多，懒加载的 ListView 不会构建屏幕外的控件。
  void useTallSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1000, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Finder chip(String id, String label) =>
      find.byKey(ValueKey<String>('cal-$id-$label'));

  testWidgets('生成校准条：按当前档案出图，并直接进预览页', (WidgetTester tester) async {
    useTallSurface(tester);
    final FakeStripRenderer strip = FakeStripRenderer(
      CalibrationStripImage(
        image: sampleImage(),
        budget: const CalibrationStripBudget(),
      ),
    );
    await tester.pumpWidget(wrap(
      controller(),
      CalibrationWizardPage(stripRenderer: strip),
    ));

    await tester.tap(find.text('生成校准条并分享'));
    await tester.pumpAndSettle();

    expect(strip.received, <PaperProfile>[kPaperangP1Default]);
    expect(find.text('预览'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();

    // 回到向导页：把出图结果如实告诉用户（尺寸 + 有没有裁减）。
    expect(find.textContaining('384 × 1200 点已生成'), findsOneWidget);
    expect(find.text('再看一次'), findsOneWidget);
  });

  testWidgets('六项全跳过：保存不改档案，且保存后照样能出图', (WidgetTester tester) async {
    useTallSurface(tester);
    final ProfileController c = controller();
    await tester.pumpWidget(wrap(c, const CalibrationWizardPage()));

    expect(find.textContaining('所有项都跳过了'), findsOneWidget);

    await tester.tap(find.text('保存到档案'));
    await tester.pump();

    expect(c.profile, kPaperangP1Default, reason: '跳过就是保留原值');
    expect(c.profile.isCalibrated, isFalse, reason: '不校准就不该标成已校准');
    expect(find.textContaining('已保存到档案'), findsOneWidget);

    // 「跳过也能用」必须是真的能用：换成首页，用默认档案出图。
    final FakeRenderer renderer = FakeRenderer(sampleImage(height: 151));
    await tester.pumpWidget(wrap(
      c,
      InputPage(
        renderer: renderer,
        prefsStore: AppPrefsStore(rootProvider: () async => tempRoot),
      ),
    ));
    await tester.tap(find.byTooltip('填入样例'));
    await tester.pump();
    await tester.tap(find.text('生成图片'));
    await tester.pumpAndSettle();

    expect(renderer.received.single.$2, c.profile);
    expect(find.text('预览'), findsOneWidget);
  });

  testWidgets('答过的项按规则写回档案，汇总预览如实列出差异', (WidgetTester tester) async {
    useTallSurface(tester);
    final ProfileController c = controller();
    await tester.pumpWidget(wrap(c, const CalibrationWizardPage()));

    await tester.tap(chip('width', '372'));
    await tester.pump();
    // 细线档位先展开，阈值项只覆盖 threshold：这里选激进档 + 阈值 160（与默认档不同，
    // 也与激进档的 $kAggressiveThreshold 不同，改完就不再属于任何档位）。
    await tester.tap(chip('thin', ThinLinePreset.aggressive.label));
    await tester.pump();
    await tester.tap(chip('threshold', '160'));
    await tester.pump();

    expect(find.text('· 有效宽度：384 → 372'), findsOneWidget);
    expect(find.text('· 严格阈值：$kStrictThreshold → 160'), findsOneWidget);

    await tester.tap(find.text('保存到档案'));
    await tester.pump();

    expect(c.profile.printableDotsWidth, 372);
    expect(c.profile.threshold, 160);
    expect(c.profile.protectStructureLines, isTrue, reason: '激进档的保护不能被阈值项改掉');
    expect(c.profile.isCalibrated, isTrue);
    expect(c.thinLinePreset, isNull, reason: '阈值被单独改过，已不属于任何档位');
  });

  testWidgets('灰阶只作诊断：说清不改参数，也不让档案变成已校准', (WidgetTester tester) async {
    useTallSurface(tester);
    final ProfileController c = controller();
    await tester.pumpWidget(wrap(c, const CalibrationWizardPage()));

    await tester.tap(chip('gray', '6'));
    await tester.pump();

    expect(find.textContaining('能分辨 6 档，不影响参数'), findsOneWidget);
    expect(find.textContaining('所有项都跳过了'), findsOneWidget);

    await tester.tap(find.text('保存到档案'));
    await tester.pump();

    expect(c.profile, kPaperangP1Default);
  });

  testWidgets('汇总预览能用新参数出一张样例', (WidgetTester tester) async {
    useTallSurface(tester);
    final FakeRenderer renderer = FakeRenderer(sampleImage(height: 151));
    await tester.pumpWidget(wrap(
      controller(),
      CalibrationWizardPage(renderer: renderer),
    ));

    await tester.tap(chip('width', '360'));
    await tester.pump();
    await tester.tap(find.text('用新参数出一张样例'));
    await tester.pumpAndSettle();

    expect(renderer.received.single.$1, kSampleText);
    expect(renderer.received.single.$2.printableDotsWidth, 360);
    expect(find.text('预览'), findsOneWidget);
  });

  testWidgets('重置为出厂默认值', (WidgetTester tester) async {
    useTallSurface(tester);
    final ProfileController c = controller();
    await tester.pumpWidget(wrap(c, const CalibrationWizardPage()));

    await tester.tap(chip('width', '360'));
    await tester.pump();
    await tester.tap(find.text('保存到档案'));
    await tester.pump();
    expect(c.profile.printableDotsWidth, 360);

    await tester.tap(find.text('重置为出厂默认值'));
    await tester.pump();

    expect(c.profile, kPaperangP1Default);
    expect(find.textContaining('已恢复出厂默认值'), findsOneWidget);
  });
}