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
    final Directory dir = await _subDir();
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

  /// 列出已落盘的出图，按文件修改时间倒序（最新在上）。
  ///
  /// 目录不存在（还没出过图）返回空表，不抛。只列 `.png`，杂物不进列表；
  /// 统计口径只覆盖本应用目录，不含 share_plus 的复制残留。
  Future<List<File>> list() async {
    final Directory dir = await _subDir();
    if (!dir.existsSync()) return <File>[];
    final List<File> files = dir
        .listSync()
        .whereType<File>()
        .where((File file) => file.path.toLowerCase().endsWith('.png'))
        .toList();
    final Map<File, DateTime> modified = <File, DateTime>{
      for (final File file in files) file: (await file.stat()).modified,
    };
    files.sort((File a, File b) => modified[b]!.compareTo(modified[a]!));
    return files;
  }

  /// 目录内全部文件字节数之和（`File.length()`）；目录不存在返回 0。
  Future<int> totalSize() async {
    final Directory dir = await _subDir();
    if (!dir.existsSync()) return 0;
    int total = 0;
    for (final FileSystemEntity entity in dir.listSync()) {
      if (entity is File) total += (await entity.stat()).size;
    }
    return total;
  }

  /// 删除单个出图文件；文件已不存在按成功处理。
  Future<void> delete(File file) async {
    if (await file.exists()) await file.delete();
  }

  /// 删掉目录下全部文件（保留目录本身）；目录不存在静默跳过。
  Future<void> deleteAll() async {
    final Directory dir = await _subDir();
    if (!dir.existsSync()) return;
    for (final FileSystemEntity entity in dir.listSync()) {
      await entity.delete(recursive: true);
    }
  }

  /// 清掉 share_plus 在自己缓存目录里的复制残留（目录不存在时静默跳过）。
  ///
  /// share_plus 每次分享前都会重新复制一份，删残留无副作用。
  Future<void> deleteSharePlusCache() async {
    final Directory dir = Directory(
      '${(await rootProvider()).path}${Platform.pathSeparator}share_plus',
    );
    if (!dir.existsSync()) return;
    for (final FileSystemEntity entity in dir.listSync()) {
      await entity.delete(recursive: true);
    }
  }

  /// 应用专属子目录（相对临时根目录）。只读查询不建目录，创建交给 [write]。
  Future<Directory> _subDir() async => Directory(
        '${(await rootProvider()).path}${Platform.pathSeparator}$kSubDirName',
      );
}