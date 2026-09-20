// 版本号一致性：界面显示的版本必须与 pubspec.yaml 一致，不能靠人记住两处同步。
//
// 不引 package_info_plus 就是为了这个：多一个原生依赖去读一个编译期常量不划算，
// 代价是这条例行断言。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mistake_print/app/app_version.dart';

void main() {
  test('kAppVersion 与 pubspec.yaml 的 version 一致', () {
    final String pubspec = File('pubspec.yaml').readAsStringSync();
    final RegExpMatch? match =
        RegExp(r'^version:\s*(\S+)\s*$', multiLine: true).firstMatch(pubspec);

    expect(match, isNotNull, reason: 'pubspec.yaml 里找不到 version 字段');
    expect(kAppVersion, match!.group(1));
  });
}