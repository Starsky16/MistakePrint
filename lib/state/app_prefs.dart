import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../domain/input_preprocess.dart';

/// 界面偏好：与打印参数无关的那点小事。
///
/// 单独立一份而不混进 `PaperProfile`：档案是「打印机的物理事实」，会被校准向导整体
/// 重写一次；偏好是「用户看腻了这条提示」「上次选的输出模式」，两者生命周期完全不同。
class AppPrefs {
  const AppPrefs({
    this.calibrationHintDismissed = false,
    this.outputMode = OutputMode.fullText,
  });

  /// 用户是否已经关掉首页的「还没校准过」提示条。
  final bool calibrationHintDismissed;

  /// 上次选的输出模式（默认全文：粘贴 AI 输出即用）。
  final OutputMode outputMode;

  AppPrefs copyWith({
    bool? calibrationHintDismissed,
    OutputMode? outputMode,
  }) =>
      AppPrefs(
        calibrationHintDismissed:
            calibrationHintDismissed ?? this.calibrationHintDismissed,
        outputMode: outputMode ?? this.outputMode,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'calibrationHintDismissed': calibrationHintDismissed,
        'outputMode': outputMode.name,
      };

  /// 容错解码：字段缺了或类型不对都取默认值。
  static AppPrefs fromJson(Object? raw) {
    if (raw is! Map) return const AppPrefs();
    const AppPrefs defaults = AppPrefs();
    final Object? dismissed = raw['calibrationHintDismissed'];
    return AppPrefs(
      calibrationHintDismissed: dismissed is bool
          ? dismissed
          : defaults.calibrationHintDismissed,
      outputMode: OutputMode.fromName(raw['outputMode']),
    );
  }
}

/// 偏好的持久化：应用私有目录下的 `prefs.json`。
class AppPrefsStore {
  const AppPrefsStore({this.rootProvider = getApplicationSupportDirectory});

  /// 存档根目录的来源，测试注入。
  final Future<Directory> Function() rootProvider;

  static const String kFileName = 'prefs.json';

  Future<File> file() async => File(
        '${(await rootProvider()).path}${Platform.pathSeparator}$kFileName',
      );

  /// 读偏好；**预期内的失败都回落默认值**。
  ///
  /// 这里破例吞掉两类预期异常：偏好只决定一条提示条是否出现，读不到就用默认值继续，
  /// 不值得为它中断启动。其余异常照常上抛，免得把真 bug 也一起盖住。
  Future<AppPrefs> load() async {
    try {
      final File target = await file();
      if (!await target.exists()) return const AppPrefs();
      return AppPrefs.fromJson(jsonDecode(await target.readAsString()));
    } on FileSystemException catch (error) {
      debugPrint('[偏好] 读取失败，改用默认值：$error');
      return const AppPrefs();
    } on FormatException catch (error) {
      debugPrint('[偏好] 存档内容损坏，改用默认值：$error');
      return const AppPrefs();
    }
  }

  /// 写偏好。失败同样只记日志：偏好写不进去不影响出图。
  Future<void> save(AppPrefs prefs) async {
    try {
      final File target = await file();
      await target.parent.create(recursive: true);
      await target.writeAsString(jsonEncode(prefs.toJson()), flush: true);
    } on FileSystemException catch (error) {
      debugPrint('[偏好] 写入失败：$error');
    }
  }
}