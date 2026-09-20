// P3 Profile 持久化与状态共享测试（计划 P3 实施笔记 §3 提交 3）。
//
// 全程注入临时目录，不碰 path_provider 的平台通道：这些用例要能在
// `flutter test` 里直接跑，不需要 Android 环境。

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mistake_print/profiles/paper_profile.dart';
import 'package:mistake_print/profiles/presets.dart';
import 'package:mistake_print/profiles/profile_store.dart';
import 'package:mistake_print/render/raster/binarize.dart';
import 'package:mistake_print/state/profile_controller.dart';

void main() {
  late Directory tempRoot;

  setUp(() {
    tempRoot = Directory.systemTemp.createTempSync('mistake_print_profile_test');
  });

  tearDown(() {
    if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
  });

  ProfileStore store() => ProfileStore(rootProvider: () async => tempRoot);

  group('ProfileStore', () {
    test('存档写在注入目录下的 profile.json', () async {
      final File file = await store().file();
      expect(
        file.path,
        '${tempRoot.path}${Platform.pathSeparator}${ProfileStore.kFileName}',
      );

      await store().save(kPaperangP1Default);
      expect(file.existsSync(), isTrue);
    });

    test('写进去什么就读出什么', () async {
      final PaperProfile saved = kPaperangP1Default.copyWith(
        printableDotsWidth: 372,
        bodyFontPx: 24,
        isCalibrated: true,
      );
      await store().save(saved);

      final PaperProfile loaded = await store().load();
      expect(loaded.printableDotsWidth, 372);
      expect(loaded.bodyFontPx, 24);
      expect(loaded.isCalibrated, isTrue);
    });

    test('存档不存在或内容坏掉时回落到默认档案，不抛', () async {
      expect((await store().load()).printableDotsWidth,
          kPaperangP1Default.printableDotsWidth);

      await (await store().file()).writeAsString('{ 半个 JSON');
      expect((await store().load()).threshold, kPaperangP1Default.threshold);
    });
  });

  group('ProfileController', () {
    test('load 前是默认值，load 后是存档值', () async {
      await store().save(kPaperangP1Default.copyWith(threshold: 170));
      final ProfileController controller = ProfileController(store: store());

      expect(controller.isLoaded, isFalse);
      expect(controller.profile, kPaperangP1Default);

      await controller.load();
      expect(controller.isLoaded, isTrue);
      expect(controller.profile.threshold, 170);
    });

    test('选档位会同时改内存态与存档，并通知监听者', () async {
      final ProfileController controller = ProfileController(store: store());
      int notifications = 0;
      controller.addListener(() => notifications++);

      await controller.setThinLinePreset(ThinLinePreset.off);

      expect(notifications, 1);
      expect(controller.thinLinePreset, ThinLinePreset.off);
      expect(controller.profile.protectStructureLines, isFalse);
      expect(controller.profile.threshold, kStrictThreshold);
      // 落盘的内容就是内存里那一份（重开 App 后档位不丢）。
      expect((await store().load()).protectStructureLines, isFalse);
      expect(detectThinLinePreset(await store().load()), ThinLinePreset.off);
    });

    test('重置回默认值', () async {
      final ProfileController controller = ProfileController(store: store());
      await controller.load();
      await controller.setThinLinePreset(ThinLinePreset.aggressive);
      await controller.resetToDefault();

      expect(controller.profile, kPaperangP1Default);
      expect((await store().load()).threshold, kPaperangP1Default.threshold);
    });
  });

  testWidgets('ProfileScope 把档案共享给子树，并在变更后重建', (WidgetTester tester) async {
    final ProfileController controller = ProfileController(store: store());

    Widget build() => ProfileScope(
          controller: controller,
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Builder(
              builder: (BuildContext context) => Text(
                '${ProfileScope.of(context).profile.printableDotsWidth}',
              ),
            ),
          ),
        );

    await tester.pumpWidget(build());
    expect(find.text('384'), findsOneWidget);

    // update 会真的落盘，而 testWidgets 默认跑在 fake-async 区里，等真实文件 IO
    // 会永久挂起（与 `toImage()` 同一个坑），所以这一段必须放进 runAsync。
    await tester.runAsync(
      () => controller.update(kPaperangP1Default.copyWith(printableDotsWidth: 372)),
    );
    await tester.pump();
    expect(find.text('372'), findsOneWidget);
  });
}