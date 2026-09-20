// P3 分享链路测试（计划 P3 实施笔记 §3 提交 2）。
//
// 注入假的分享动作断言「交给系统面板的是什么」与「四种结局的映射」，不拉起真实
// 面板；落盘用注入的临时目录，不碰 path_provider 的平台通道。

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mistake_print/render/offscreen/print_renderer.dart';
import 'package:mistake_print/share/png_file_store.dart';
import 'package:mistake_print/share/share_service.dart';
import 'package:share_plus/share_plus.dart';

/// 出图结果的替身：分享链路只关心字节与宽高，不需要真出一次图。
PrintImage sampleImage() => PrintImage(
      png: Uint8List.fromList(<int>[0x89, 0x50, 0x4E, 0x47]),
      width: 384,
      height: 151,
      blackDots: 3115,
      elapsed: const Duration(milliseconds: 100),
      layoutPasses: 2,
    );

/// 记录调用参数、按脚本返回结局的假分享动作。
class FakeShare {
  FakeShare({this.result = const ShareResult('ok', ShareResultStatus.success), this.error});

  final ShareResult result;
  final Object? error;

  final List<XFile> received = <XFile>[];

  Future<ShareResult> call(XFile file) async {
    received.add(file);
    if (error != null) throw error!;
    return result;
  }
}

void main() {
  late Directory tempRoot;

  setUp(() {
    tempRoot = Directory.systemTemp.createTempSync('mistake_print_share_test');
  });

  tearDown(() {
    if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
  });

  PngFileStore store() => PngFileStore(rootProvider: () async => tempRoot);

  test('文件名含时间戳与宽高，且为纯 ASCII', () {
    final String name = PngFileStore.buildFileName(
      384,
      151,
      DateTime(2026, 9, 21, 15, 30, 12),
    );
    expect(name, 'mistake_20260921-153012-384x151.png');
    expect(name.contains(RegExp(r'[^\x20-\x7E]')), isFalse, reason: '文件名应全为 ASCII');
  });

  test('落盘到 <temp>/mistake_print/ 下，不在 share_plus 的可分享目录内', () async {
    final File file = await store().write(
      sampleImage().png,
      width: 384,
      height: 151,
      now: DateTime(2026, 9, 21, 15, 30, 12),
    );

    expect(file.existsSync(), isTrue);
    expect(file.readAsBytesSync(), sampleImage().png);
    expect(
      file.parent.path,
      '${tempRoot.path}${Platform.pathSeparator}${PngFileStore.kSubDirName}',
    );
    // share_plus 对落在它自己 cache 目录里的文件直接抛 IOException（见 E22），
    // 因此路径里绝不能让 share_plus 目录成为前缀。
    expect(file.path.contains('${Platform.pathSeparator}share_plus'), isFalse);
  });

  test('交给面板的是一张 image/png，路径指向刚落盘的文件', () async {
    final FakeShare fake = FakeShare();
    final ShareReport report =
        await ShareService(store: store(), shareImage: fake.call).share(sampleImage());

    expect(fake.received, hasLength(1));
    final XFile sent = fake.received.single;
    expect(sent.path, report.file.path);
    expect(sent.mimeType, 'image/png');
    expect(File(sent.path).existsSync(), isTrue);
    expect(report.outcome, ShareOutcome.shared);
  });

  test('三种平台结局分别映射为 shared / dismissed / unavailable', () async {
    Future<ShareOutcome> outcomeFor(String raw, ShareResultStatus status) async {
      final FakeShare fake =
          FakeShare(result: ShareResult(raw, status));
      final ShareReport report =
          await ShareService(store: store(), shareImage: fake.call).share(sampleImage());
      return report.outcome;
    }

    expect(await outcomeFor('com.example', ShareResultStatus.success),
        ShareOutcome.shared);
    expect(
        await outcomeFor('', ShareResultStatus.dismissed), ShareOutcome.dismissed);
    expect(
        await outcomeFor(
          'dev.fluttercommunity.plus/share/unavailable',
          ShareResultStatus.unavailable,
        ),
        ShareOutcome.unavailable);
  });

  test('面板失败时降级为 failed，且图片仍留在临时目录里', () async {
    final FakeShare fake = FakeShare(error: Exception('没有可分享的应用'));
    final ShareReport report =
        await ShareService(store: store(), shareImage: fake.call).share(sampleImage());

    expect(report.outcome, ShareOutcome.failed);
    expect(report.error, isNotNull);
    expect(report.file.existsSync(), isTrue, reason: '失败路径也必须保住已出的图');
    debugPrint('[分享] 降级：${report.error}，图在 ${report.file.path}');
  });
}