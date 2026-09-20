import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// 出图 PNG 的落盘位置（计划 §4 P3「写文件到临时/应用私有目录」）。
///
/// **不能**写进 share_plus 自带的 FileProvider 目录 `<cacheDir>/share_plus/`：
/// share_plus 13.1.0 的 `Share.kt` 对该目录下的文件直接抛 IOException，而且它的
/// FileProvider 只声明了这一个可分享目录。写在兄弟目录 `<cacheDir>/mistake_print/`
/// 即可 —— 插件会把文件复制进它自己的可分享目录再交给系统面板。
class PngFileStore {
  const PngFileStore({this.rootProvider = getTemporaryDirectory});

  /// 临时根目录的来源，测试注入；默认走 path_provider（Android 上是 `cacheDir`）。
  final Future<Directory> Function() rootProvider;

  /// 应用专属子目录名（相对临时根目录）。
  static const String kSubDirName = 'mistake_print';

  /// 写入一张 PNG 并返回落盘文件。
  Future<File> write(
    Uint8List png, {
    required int width,
    required int height,
    DateTime? now,
  }) async {
    final Directory dir = Directory(
      '${(await rootProvider()).path}${Platform.pathSeparator}$kSubDirName',
    );
    await dir.create(recursive: true);
    final File file = File(
      '${dir.path}${Platform.pathSeparator}${buildFileName(width, height, now)}',
    );
    await file.writeAsBytes(png, flush: true);
    return file;
  }

  /// 生成文件名。
  ///
  /// 形如 `mistake_20260921-153012-384x7910.png`：时间戳保证同一秒外的两次出图不
  /// 互相覆盖，宽高让用户在分享面板里一眼认出是哪一张。全 ASCII —— 文件名会经
  /// `Intent.EXTRA_STREAM` 传给别的 App，不用中文以免个别机型上乱码。
  @visibleForTesting
  static String buildFileName(int width, int height, DateTime? now) {
    String two(int value) => value.toString().padLeft(2, '0');
    final DateTime t = now ?? DateTime.now();
    final String stamp = '${t.year}${two(t.month)}${two(t.day)}'
        '-${two(t.hour)}${two(t.minute)}${two(t.second)}';
    return 'mistake_$stamp-${width}x$height.png';
  }
}