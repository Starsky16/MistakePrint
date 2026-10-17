// 相册通道契约测试（设计 2026-10-14）。
// 全程用假 channel，不碰真实平台；只断言「Dart 侧发给通道什么」与「通道回什么就解析成什么」。

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mistake_print/share/gallery_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel channel = MethodChannel('mistake_print/gallery');
  final List<MethodCall> calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      calls.add(call);
      switch (call.method) {
        case 'ensureWritePermission':
          return true;
        case 'save':
          return <String, Object?>{
            'id': '7',
            'uri': 'content://media/external/images/media/7',
            'name': (call.arguments as Map)['name'],
            'size': 4,
            'date': 1700000000000,
          };
        case 'list':
          return <Object?>[
            <String, Object?>{
              'id': '7',
              'uri': 'content://media/external/images/media/7',
              'name': 'mistake_a.png',
              'size': 1024,
              'date': 1700000000000,
            },
          ];
        case 'read':
          return Uint8List.fromList(<int>[1, 2, 3, 4]);
        case 'deleteAll':
          return 1;
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('buildFileName 含时间戳与宽高，且为纯 ASCII', () {
    expect(
      GalleryStore.buildFileName(384, 151, DateTime(2026, 9, 21, 15, 30, 12)),
      'mistake_20260921-153012-384x151.png',
    );
  });

  test('save 先要权限，再把 name/bytes 发给通道，并把返回解析成 GalleryImage', () async {
    final GalleryStore store = GalleryStore(channel: channel);
    final GalleryImage image = await store.save(
      Uint8List.fromList(<int>[0x89, 0x50, 0x4E, 0x47]),
      name: 'mistake_a.png',
    );

    expect(calls.map((MethodCall c) => c.method),
        <String>['ensureWritePermission', 'save']);
    final Map<Object?, Object?> args = calls[1].arguments! as Map<Object?, Object?>;
    expect(args['name'], 'mistake_a.png');
    expect(args['bytes'], isA<Uint8List>());
    expect(image.uri, 'content://media/external/images/media/7');
    expect(image.name, 'mistake_a.png');
    expect(image.size, 4);
    expect(image.date.millisecondsSinceEpoch, 1700000000000);
  });

  test('权限被拒时抛 GalleryException，且不发 save', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      calls.add(call);
      if (call.method == 'ensureWritePermission') return false;
      return null;
    });
    final GalleryStore store = GalleryStore(channel: channel);
    expect(
      () => store.save(Uint8List(0), name: 'x.png'),
      throwsA(isA<GalleryException>()),
    );
    expect(calls.map((MethodCall c) => c.method), <String>['ensureWritePermission']);
  });

  test('list 解析成 GalleryImage 列表', () async {
    final List<GalleryImage> images = await GalleryStore(channel: channel).list();
    expect(images, hasLength(1));
    expect(images.single.name, 'mistake_a.png');
    expect(images.single.size, 1024);
  });

  test('readBytes 按 uri 取回字节', () async {
    final Uint8List bytes = await GalleryStore(channel: channel)
        .readBytes('content://media/external/images/media/7');
    expect(bytes, <int>[1, 2, 3, 4]);
    expect(calls.single.arguments, <String, Object?>{
      'uri': 'content://media/external/images/media/7',
    });
  });

  test('totalSize 汇总 list 的 size', () async {
    expect(await GalleryStore(channel: channel).totalSize(), 1024);
  });

  test('delete 发 uri，deleteAll 无参', () async {
    final GalleryStore store = GalleryStore(channel: channel);
    await store.delete('content://media/external/images/media/7');
    await store.deleteAll();
    expect(calls[0].method, 'delete');
    expect(calls[0].arguments, <String, Object?>{
      'uri': 'content://media/external/images/media/7',
    });
    expect(calls[1].method, 'deleteAll');
  });
}
