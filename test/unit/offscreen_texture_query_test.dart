// 离屏出图纹理上限查询的单测（真机 bug：超采样物理边长超 GL_MAX_TEXTURE_SIZE
// 时引擎静默等比缩小，出图断言炸出「908 不等于 1152」）。
//
// 用 mock 通道钉住三条契约：成功缓存、失败不缓存、通道不通回落 null。

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mistake_print/render/offscreen/offscreen_canvas.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    OffscreenCanvas.maxTextureSizeCache = null;
  });

  tearDown(() {
    OffscreenCanvas.maxTextureSizeCache = null;
  });

  test('查询成功：返回真值并缓存，第二次不再走通道', () async {
    const MethodChannel channel = MethodChannel('test/tex');
    int calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      expect(call.method, 'maxTextureSize');
      calls++;
      return 8192;
    });

    expect(await OffscreenCanvas.queryMaxTextureSize(channel: channel), 8192);
    // 通道换成一个必然失败的，仍命中缓存拿到 8192 —— 证明第二次没走通道。
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      throw PlatformException(code: 'boom');
    });
    expect(await OffscreenCanvas.queryMaxTextureSize(channel: channel), 8192);
    expect(calls, 1);
  });

  test('PlatformException：返回 null 且不缓存，下次重试可拿到真值', () async {
    const MethodChannel channel = MethodChannel('test/tex');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      throw PlatformException(code: 'no_egl');
    });
    expect(await OffscreenCanvas.queryMaxTextureSize(channel: channel), isNull);
    expect(OffscreenCanvas.maxTextureSizeCache, isNull);

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      return 4096;
    });
    expect(await OffscreenCanvas.queryMaxTextureSize(channel: channel), 4096);
  });

  test('通道未实现（MissingPluginException，测试环境常态）：回落 null 不抛', () async {
    const MethodChannel channel = MethodChannel('test/tex-unimplemented');
    expect(await OffscreenCanvas.queryMaxTextureSize(channel: channel), isNull);
    expect(OffscreenCanvas.maxTextureSizeCache, isNull);
  });
}
