import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'paper_profile.dart';
import 'profile_codec.dart';

/// Profile 的持久化：应用私有目录下的单个 JSON 文件（计划 §5.5）。
///
/// 没有引 `shared_preferences`（P3 实施笔记 D1）：档案是结构化数据，JSON 文件
/// 既能被开发者模式直接查看与导出，也省掉一个原生依赖。
class ProfileStore {
  const ProfileStore({this.rootProvider = getApplicationSupportDirectory});

  /// 存档根目录的来源，测试注入；默认走 path_provider 的应用支持目录
  /// （Android 上是 `filesDir`，清缓存不会丢，也不属于 share_plus 的可分享目录）。
  final Future<Directory> Function() rootProvider;

  static const String kFileName = 'profile.json';

  /// 存档文件路径。不创建目录，由 [save] 负责。
  Future<File> file() async => File(
        '${(await rootProvider()).path}${Platform.pathSeparator}$kFileName',
      );

  /// 读取存档。
  ///
  /// 文件不存在、内容被截断、版本不符时一律回落到 [kPaperangP1Default] —— 档案是
  /// 可随时重跑校准向导重新生成的数据，坏了就重来，不值得为它中断启动。
  Future<PaperProfile> load() async {
    final File target = await file();
    if (!await target.exists()) return kPaperangP1Default;
    return decodeProfileJson(await target.readAsString()) ?? kPaperangP1Default;
  }

  /// 写入存档。
  Future<void> save(PaperProfile profile) async {
    final File target = await file();
    await target.parent.create(recursive: true);
    await target.writeAsString(encodeProfileJson(profile), flush: true);
  }
}