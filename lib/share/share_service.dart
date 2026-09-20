import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';

import '../render/offscreen/print_renderer.dart';
import 'png_file_store.dart';

/// 一次分享的结局。
enum ShareOutcome {
  /// 用户在系统面板里选了目标 App。
  shared,

  /// 用户划走了面板，没有分享。
  dismissed,

  /// 当前环境拿不到回执（部分机型与系统版本如此），不代表没有分享成功。
  unavailable,

  /// 拉起面板失败；图片仍在临时目录里，用户可以手动取用。
  failed,
}

/// 把一张图片交给系统分享面板的动作。
///
/// 抽成函数类型是为了让测试注入假实现。这里**没用** share_plus 自己的
/// `SharePlus.custom(platform)` 注入点：它要的是 `SharePlatform`，而这个类型没有
/// 从 `share_plus` 导出（只导出了 `ShareParams` / `XFile` / `ShareResult` 等），
/// 走那条路就得把 `share_plus_platform_interface` 提成直接依赖，只为测试不值当。
typedef ShareImageCallback = Future<ShareResult> Function(XFile file);

/// 分享结果 + 落盘位置。
class ShareReport {
  const ShareReport(this.outcome, this.file, {this.error});

  final ShareOutcome outcome;

  /// 图片落盘位置。任何结局下都有效 —— 失败时它就是「图还在哪」的答案。
  final File file;

  /// [ShareOutcome.failed] 时的原始异常，供开发者模式展示。
  final Object? error;

  @override
  String toString() => 'ShareReport(${outcome.name}, ${file.path})';
}

/// 把出图结果交给系统分享面板（计划 §5.6「分享」、§4 P3 主路径）。
///
/// 降级顺序只做了前两级 —— 定向 `cn.paperang.mm` 与「存相册后手动导入」见计划
/// P3 实施笔记 D1：`android_intent_plus` 的原生层只支持基础类型，会把
/// `Intent.EXTRA_STREAM` 当成字符串塞进 bundle，`content://` URI 送不到接收方，
/// 定向分享要等 P5 有真机时再定。
///
/// 1. 落盘到 `<temp>/mistake_print/`（[PngFileStore]）；
/// 2. 拉起系统分享面板；
/// 3. 面板失败时保留文件并回报路径，由界面提示用户手动取用。
class ShareService {
  const ShareService({
    this.store = const PngFileStore(),
    this.shareImage = shareViaSystemPanel,
  });

  final PngFileStore store;

  @visibleForTesting
  final ShareImageCallback shareImage;

  /// 默认分享动作：走 share_plus 的系统面板。
  static Future<ShareResult> shareViaSystemPanel(XFile file) =>
      SharePlus.instance.share(ShareParams(files: <XFile>[file]));

  /// 落盘后拉起系统分享面板。
  Future<ShareReport> share(PrintImage image) async {
    final File file = await store.write(
      image.png,
      width: image.width,
      height: image.height,
    );
    try {
      // 显式给 MIME，不依赖插件按扩展名猜；接收方据此判断能不能收这张图。
      final ShareResult result =
          await shareImage(XFile(file.path, mimeType: 'image/png'));
      return ShareReport(_outcomeOf(result.status), file);
    } on Object catch (error) {
      return ShareReport(ShareOutcome.failed, file, error: error);
    }
  }

  static ShareOutcome _outcomeOf(ShareResultStatus status) => switch (status) {
        ShareResultStatus.success => ShareOutcome.shared,
        ShareResultStatus.dismissed => ShareOutcome.dismissed,
        ShareResultStatus.unavailable => ShareOutcome.unavailable,
      };
}