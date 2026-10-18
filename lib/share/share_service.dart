import 'package:flutter/services.dart';

import 'gallery_store.dart';

/// 一次分享的结局。
enum ShareOutcome {
  /// 已把图交给系统分享面板（面板里用户选了谁，我方拿不到回执）。
  shared,

  /// 系统里没有任何可接收 image/png 的应用。
  unavailable,

  /// 拉起面板失败（通道异常等）；图仍在相册里，可重试。
  failed,
}

/// 分享结果。
class ShareReport {
  const ShareReport(this.outcome, this.image, {this.error});

  final ShareOutcome outcome;

  /// 被分享的相册记录；任何结局下都有效（分享源就是它）。
  final GalleryImage image;

  /// [ShareOutcome.failed] 时的原始异常，供开发者模式展示。
  final Object? error;

  @override
  String toString() => 'ShareReport(${outcome.name}, ${image.uri})';
}

/// 把相册里的一张图交给系统分享面板（通用分享设计）。
///
/// 用标准媒体 URI + `Intent.ACTION_SEND` + 系统 chooser，**不 setPackage**：面板里
/// 会出现任意图片 / 打印类应用（通用，不绑死喵喵机）。原生细节在 [kGalleryChannel]
/// 的 `share` 方法里；`dismissed` 不再可观测（我方不持有 chooser 回执），故结局
/// 只剩三种。
class ShareService {
  const ShareService({this.channel = kGalleryChannel});

  final MethodChannel channel;

  /// 拉起系统面板分享 [image]。
  Future<ShareReport> share(GalleryImage image) async {
    try {
      final String? status =
          await channel.invokeMethod<String>('share', <String, Object?>{
        'uri': image.uri,
        'mimeType': 'image/png',
      });
      return ShareReport(
        status == 'unavailable' ? ShareOutcome.unavailable : ShareOutcome.shared,
        image,
      );
    } on Object catch (error) {
      return ShareReport(ShareOutcome.failed, image, error: error);
    }
  }
}
