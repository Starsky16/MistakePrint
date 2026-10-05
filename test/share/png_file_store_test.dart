// PngFileStore 管理能力测试（输出图片管理，设计 2026-10-05）。
//
// 注入临时目录，不碰 path_provider 的平台通道；修改时间手工钉死，排序才可断言。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mistake_print/share/png_file_store.dart';

void main() {
  late Directory tempRoot;

  setUp(() {
    tempRoot = Directory.systemTemp.createTempSync('mistake_print_store_test');
  });

  tearDown(() {
    if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
  });

  PngFileStore store() => PngFileStore(rootProvider: () async => tempRoot);

  /// 在注入目录里手写一张已知内容与修改时间的 PNG（不必是真图，数据层只管字节）。
  Future<File> writePng({
    required String name,
    required List<int> bytes,
    required DateTime modified,
  }) async {
    final Directory dir = Directory(
      '${tempRoot.path}${Platform.pathSeparator}${PngFileStore.kSubDirName}',
    );
    await dir.create(recursive: true);
    final File file = File('${dir.path}${Platform.pathSeparator}$name');
    await file.writeAsBytes(bytes, flush: true);
    file.setLastModifiedSync(modified);
    return file;
  }

  test('list() 按修改时间倒序，且只列 .png', () async {
    await writePng(
      name: 'mistake_1.png',
      bytes: List<int>.filled(10, 1),
      modified: DateTime(2026, 10, 5, 12, 0, 0),
    );
    await writePng(
      name: 'mistake_2.png',
      bytes: List<int>.filled(20, 2),
      modified: DateTime(2026, 10, 5, 12, 0, 2),
    );
    await writePng(
      name: 'mistake_3.png',
      bytes: List<int>.filled(30, 3),
      modified: DateTime(2026, 10, 5, 12, 0, 1),
    );
    // 杂物不进列表。
    await writePng(
      name: 'not-a-png.txt',
      bytes: <int>[0],
      modified: DateTime(2026, 10, 5, 12, 0, 3),
    );

    final List<File> files = await store().list();

    expect(
      files.map((File f) => f.uri.pathSegments.last),
      <String>['mistake_2.png', 'mistake_3.png', 'mistake_1.png'],
    );
  });

  test('totalSize() 是目录内全部文件字节数之和', () async {
    await writePng(
      name: 'a.png',
      bytes: List<int>.filled(10, 1),
      modified: DateTime(2026, 10, 5),
    );
    await writePng(
      name: 'b.png',
      bytes: List<int>.filled(32, 2),
      modified: DateTime(2026, 10, 5),
    );
    // share_plus 的残留不计入统计。
    final Directory sharePlus =
        Directory('${tempRoot.path}${Platform.pathSeparator}share_plus');
    await sharePlus.create(recursive: true);
    await File('${sharePlus.path}${Platform.pathSeparator}x.png')
        .writeAsBytes(List<int>.filled(999, 9));

    expect(await store().totalSize(), 42);
  });

  test('delete() 删掉对应文件，其余保留', () async {
    final File a = await writePng(
      name: 'a.png',
      bytes: <int>[1],
      modified: DateTime(2026, 10, 5),
    );
    await writePng(
      name: 'b.png',
      bytes: <int>[2],
      modified: DateTime(2026, 10, 5),
    );

    await store().delete(a);

    expect(a.existsSync(), isFalse);
    expect((await store().list()).length, 1);
  });

  test('deleteAll() 后文件清空、目录本身保留', () async {
    await writePng(
      name: 'a.png',
      bytes: <int>[1],
      modified: DateTime(2026, 10, 5),
    );
    final Directory dir = Directory(
      '${tempRoot.path}${Platform.pathSeparator}${PngFileStore.kSubDirName}',
    );

    await store().deleteAll();

    expect(dir.existsSync(), isTrue);
    expect(await store().list(), isEmpty);
    expect(await store().totalSize(), 0);
  });

  test('目录不存在时 list() 空表、totalSize() 0，都不抛', () async {
    expect(await store().list(), isEmpty);
    expect(await store().totalSize(), 0);
  });

  test('deleteSharePlusCache() 只清 share_plus 目录，目录不存在时静默跳过', () async {
    // 目录不存在：不抛，也不顺手把根目录建出来。
    await store().deleteSharePlusCache();
    expect(tempRoot.existsSync(), isTrue);

    final Directory sharePlus =
        Directory('${tempRoot.path}${Platform.pathSeparator}share_plus');
    await sharePlus.create(recursive: true);
    final File junk = File('${sharePlus.path}${Platform.pathSeparator}junk.png');
    await junk.writeAsBytes(<int>[1, 2, 3]);

    await store().deleteSharePlusCache();

    expect(junk.existsSync(), isFalse);
    expect(sharePlus.existsSync(), isTrue, reason: '只清文件，目录本身保留');
  });
}
