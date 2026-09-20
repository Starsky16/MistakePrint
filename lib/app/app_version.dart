/// 应用版本号。
///
/// 与 `pubspec.yaml` 的 `version` 必须逐字一致，由 `test/app/app_version_test.dart`
/// 直接读 pubspec 比对。不引 `package_info_plus`：为了读一个编译期就已知的常量去加
/// 一个原生依赖不划算。
const String kAppVersion = '0.1.0+1';

/// 应用显示名（首页标题与「关于」共用一处）。
const String kAppName = 'MistakePrint';