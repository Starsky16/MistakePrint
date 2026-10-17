// 分享链路测试（出图入相册、通用系统分享设计）。
// 假 channel 断言「发给通道的 uri 与 mime」与「三态映射」，不拉起真实面板。

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mistake_print/share/gallery_store.dart';
import 'package:mistake_print/share/share_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel channel = MethodChannel('mistake_print/gallery');
  final List<MethodCall> calls = <MethodCall>[];

  final GalleryImage sample = GalleryImage(
    id: '7',
    uri: 'content://media/external/images/media/7',
    name: 'mistake_a.png',
    size: 1024,
    date: DateTime.fromMillisecondsSinceEpoch(0),
  );

  setUp(() => calls.clear());

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  void mockShare(Object? Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      calls.add(call);
      return handler(call);
    });
  }

  test('发给通道的是媒体 uri 与 image/png，回 shared 映射为 shared', () async {
    mockShare((_) => 'shared');
    final ShareReport report =
        await ShareService(channel: channel).share(sample);

    expect(calls.single.method, 'share');
    expect(calls.single.arguments, <String, Object?>{
      'uri': 'content://media/external/images/media/7',
      'mimeType': 'image/png',
    });
    expect(report.outcome, ShareOutcome.shared);
    expect(report.image.uri, sample.uri);
  });

  test('原生回 unavailable 映射为 unavailable', () async {
    mockShare((_) => 'unavailable');
    final ShareReport report =
        await ShareService(channel: channel).share(sample);
    expect(report.outcome, ShareOutcome.unavailable);
    expect(report.image.uri, sample.uri);
  });

  test('通道异常降级为 failed，且携带原始异常与图', () async {
    mockShare(
      (_) => throw PlatformException(code: 'share_failed', message: '没有可分享的应用'),
    );
    final ShareReport report =
        await ShareService(channel: channel).share(sample);
    expect(report.outcome, ShareOutcome.failed);
    expect(report.error, isA<PlatformException>());
    expect(report.image.uri, sample.uri);
  });
}
