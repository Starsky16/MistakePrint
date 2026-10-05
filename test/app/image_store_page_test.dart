// 输出图片管理页测试（设计 2026-10-05）。
//
// 只断言「页面接线对不对」：列表渲染、单删/全清的确认交互、空态。
// fake-async 测试区里真实异步 IO 的完成事件不会投递（pages_test 的
// FakePrefsStore 注释同理），所以：
// ① store 用 SyncFakeStore——与真实现同逻辑、全同步 IO 的替身，同步调用在
//    假时钟里不会挂起，且仍然打真盘，删除/清空的磁盘效果照常断言；
// ② 准备文件放进 tester.runAsync。

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mistake_print/app/image_store_page.dart';
import 'package:mistake_print/share/png_file_store.dart';

/// 与 [PngFileStore] 同逻辑、但全用同步 IO 的替身：fake-async 测试区里同步
/// 调用不会挂起（真实异步 IO 事件不会在假时钟里投递）。仍然打真盘。
class SyncFakeStore extends PngFileStore {
  SyncFakeStore(this.root) : super(rootProvider: () async => root);

  final Directory root;

  Directory get _dir => Directory(
        '${root.path}${Platform.pathSeparator}${PngFileStore.kSubDirName}',
      );

  @override
  Future<List<File>> list() async {
    if (!_dir.existsSync()) return <File>[];
    final List<File> files = _dir
        .listSync()
        .whereType<File>()
        .where((File file) => file.path.toLowerCase().endsWith('.png'))
        .toList()
      ..sort(
        (File a, File b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()),
      );
    return files;
  }

  @override
  Future<int> totalSize() async {
    if (!_dir.existsSync()) return 0;
    return _dir
        .listSync()
        .whereType<File>()
        .fold<int>(0, (int sum, File file) => sum + file.lengthSync());
  }

  @override
  Future<void> delete(File file) async {
    if (file.existsSync()) file.deleteSync();
  }

  @override
  Future<void> deleteAll() async {
    if (!_dir.existsSync()) return;
    for (final FileSystemEntity entity in _dir.listSync()) {
      entity.deleteSync(recursive: true);
    }
  }

  @override
  Future<void> deleteSharePlusCache() async {
    final Directory dir =
        Directory('${root.path}${Platform.pathSeparator}share_plus');
    if (!dir.existsSync()) return;
    for (final FileSystemEntity entity in dir.listSync()) {
      entity.deleteSync(recursive: true);
    }
  }
}

void main() {
  late Directory tempRoot;

  setUp(() {
    tempRoot =
        Directory.systemTemp.createTempSync('mistake_print_img_page_test');
  });

  tearDown(() {
    if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
  });

  SyncFakeStore store() => SyncFakeStore(tempRoot);

  /// 手写一张假 PNG；modified 钉死不同时刻，列表排序才可断言。
  /// 必须在 tester.runAsync 里调用（真实文件 IO）。
  Future<File> writePng(String name, {DateTime? modified}) async {
    final Directory dir = Directory(
      '${tempRoot.path}${Platform.pathSeparator}${PngFileStore.kSubDirName}',
    );
    await dir.create(recursive: true);
    final File file = File('${dir.path}${Platform.pathSeparator}$name');
    await file.writeAsBytes(List<int>.filled(8, 1), flush: true);
    if (modified != null) file.setLastModifiedSync(modified);
    return file;
  }

  /// 在 runAsync 里准备出图文件，再灌进页面。
  Future<void> preparePngs(
    WidgetTester tester,
    Map<String, DateTime?> names,
  ) async {
    await tester.runAsync(() async {
      for (final MapEntry<String, DateTime?> entry in names.entries) {
        await writePng(entry.key, modified: entry.value);
      }
    });
  }

  Future<void> openPage(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(home: ImageStorePage(store: store())));
    await tester.pumpAndSettle();
  }

  testWidgets('空态：没有出图时给提示，不出现清空入口', (WidgetTester tester) async {
    await openPage(tester);

    expect(find.text('还没有输出图片'), findsOneWidget);
    expect(find.text('全部清空'), findsNothing);
  });

  testWidgets('列表展示文件名、占用汇总与清空入口', (WidgetTester tester) async {
    await preparePngs(tester, <String, DateTime?>{
      'mistake_20261005-120000-384x151.png': null,
      'mistake_20261005-120001-384x7910.png': null,
    });
    await openPage(tester);

    expect(find.textContaining('共 2 张'), findsOneWidget);
    expect(find.text('mistake_20261005-120000-384x151.png'), findsOneWidget);
    expect(find.text('mistake_20261005-120001-384x7910.png'), findsOneWidget);
    expect(find.text('全部清空'), findsOneWidget);
  });

  testWidgets('单张删除：过确认框，行消失且文件从磁盘删掉', (WidgetTester tester) async {
    // a 钉成较新的修改时间，保证它排在第一行。
    final File? a = await tester.runAsync(
      () => writePng('mistake_a.png', modified: DateTime(2026, 10, 5, 12, 0, 1)),
    );
    await preparePngs(tester, <String, DateTime?>{
      'mistake_b.png': DateTime(2026, 10, 5, 12, 0, 0),
    });
    await openPage(tester);

    await tester.tap(find.byIcon(Icons.delete_outline).first);
    await tester.pumpAndSettle();
    expect(find.text('删除这张图'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();

    expect(find.textContaining('mistake_a.png'), findsNothing);
    expect(a!.existsSync(), isFalse);
    expect(find.textContaining('共 1 张'), findsOneWidget);
  });

  testWidgets('全部清空：过确认框后进空态，share_plus 残留一并清掉',
      (WidgetTester tester) async {
    await preparePngs(tester, <String, DateTime?>{
      'mistake_a.png': null,
      'mistake_b.png': null,
    });
    final Directory sharePlus =
        Directory('${tempRoot.path}${Platform.pathSeparator}share_plus');
    await tester.runAsync(() async {
      await sharePlus.create(recursive: true);
      await File('${sharePlus.path}${Platform.pathSeparator}残留.png')
          .writeAsBytes(<int>[1]);
    });
    await openPage(tester);

    await tester.tap(find.text('全部清空'));
    await tester.pumpAndSettle();
    expect(find.text('清空全部输出图片'), findsOneWidget);

    // 确认按钮用 FilledButton 定位，避开 AppBar 里同名的 TextButton。
    await tester.tap(find.widgetWithText(FilledButton, '清空'));
    await tester.pumpAndSettle();

    expect(find.text('还没有输出图片'), findsOneWidget);
    expect(find.textContaining('mistake_a.png'), findsNothing);
    expect(sharePlus.existsSync(), isTrue);
    expect(sharePlus.listSync(), isEmpty);
  });

  testWidgets('取消清空确认框时一张都不删', (WidgetTester tester) async {
    await preparePngs(tester, <String, DateTime?>{'mistake_a.png': null});
    await openPage(tester);

    await tester.tap(find.text('全部清空'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(find.textContaining('mistake_a.png'), findsOneWidget);
  });
}

