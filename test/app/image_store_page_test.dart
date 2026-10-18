// 输出图片管理页测试（出图入相册设计）。
//
// 用内存 FakeGalleryStore，不打平台通道；断言列表渲染、单删/全清的确认交互、空态。
// 与 share_service_test 的假 channel 不同：这里直接替换 GalleryStore 的方法，
// 因为页面只依赖 store 抽象、不关心通道。

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mistake_print/app/image_store_page.dart';
import 'package:mistake_print/share/gallery_store.dart';

/// 内存假相册：list/delete/deleteAll 直接改内存列表，全同步完成。
class FakeGalleryStore extends GalleryStore {
  FakeGalleryStore(this.items);

  List<GalleryImage> items;

  @override
  Future<List<GalleryImage>> list() async => List<GalleryImage>.from(items);

  @override
  Future<void> delete(String uri) async =>
      items.removeWhere((GalleryImage image) => image.uri == uri);

  @override
  Future<void> deleteAll() async => items = <GalleryImage>[];

  @override
  Future<Uint8List> readBytes(String uri) async => Uint8List(0);
}

GalleryImage img(String name, {int size = 1024, int date = 0}) => GalleryImage(
      id: name,
      uri: 'content://media/external/images/media/$name',
      name: name,
      size: size,
      date: DateTime.fromMillisecondsSinceEpoch(date),
    );

void main() {
  Future<void> openPage(WidgetTester tester, GalleryStore store) async {
    await tester.pumpWidget(MaterialApp(home: ImageStorePage(store: store)));
    await tester.pumpAndSettle();
  }

  testWidgets('空态：没有出图时给提示，不出现清空入口', (WidgetTester tester) async {
    await openPage(tester, FakeGalleryStore(<GalleryImage>[]));

    expect(find.text('还没有输出图片'), findsOneWidget);
    expect(find.text('全部清空'), findsNothing);
  });

  testWidgets('列表展示文件名、占用汇总与清空入口', (WidgetTester tester) async {
    await openPage(
      tester,
      FakeGalleryStore(<GalleryImage>[
        img('mistake_20261005-120000-384x151.png', size: 1024),
        img(
          'mistake_20261005-120001-384x7910.png',
          size: 2 * 1024 * 1024,
          date: 1,
        ),
      ]),
    );

    expect(find.textContaining('共 2 张'), findsOneWidget);
    expect(find.text('mistake_20261005-120000-384x151.png'), findsOneWidget);
    expect(find.text('mistake_20261005-120001-384x7910.png'), findsOneWidget);
    expect(find.text('全部清空'), findsOneWidget);
  });

  testWidgets('单张删除：过确认框，行消失', (WidgetTester tester) async {
    final FakeGalleryStore store = FakeGalleryStore(<GalleryImage>[
      img('mistake_a.png', date: 1),
      img('mistake_b.png', date: 0),
    ]);
    await openPage(tester, store);

    await tester.tap(find.byIcon(Icons.delete_outline).first);
    await tester.pumpAndSettle();
    expect(find.text('删除这张图'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();

    expect(find.textContaining('mistake_a.png'), findsNothing);
    expect(find.textContaining('共 1 张'), findsOneWidget);
    expect(store.items.map((GalleryImage i) => i.name), <String>['mistake_b.png']);
  });

  testWidgets('全部清空：过确认框后进空态', (WidgetTester tester) async {
    final FakeGalleryStore store = FakeGalleryStore(<GalleryImage>[
      img('mistake_a.png'),
      img('mistake_b.png'),
    ]);
    await openPage(tester, store);

    await tester.tap(find.text('全部清空'));
    await tester.pumpAndSettle();
    expect(find.text('清空全部输出图片'), findsOneWidget);

    // 确认按钮用 FilledButton 定位，避开 AppBar 里同名的 TextButton。
    await tester.tap(find.widgetWithText(FilledButton, '清空'));
    await tester.pumpAndSettle();

    expect(find.text('还没有输出图片'), findsOneWidget);
    expect(find.textContaining('mistake_a.png'), findsNothing);
    expect(store.items, isEmpty);
  });

  testWidgets('取消清空确认框时一张都不删', (WidgetTester tester) async {
    final FakeGalleryStore store =
        FakeGalleryStore(<GalleryImage>[img('mistake_a.png')]);
    await openPage(tester, store);

    await tester.tap(find.text('全部清空'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(find.textContaining('mistake_a.png'), findsOneWidget);
    expect(store.items, hasLength(1));
  });
}
