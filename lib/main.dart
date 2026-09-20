import 'dart:async';

import 'package:flutter/material.dart';

import 'app/app_version.dart';
import 'app/input_page.dart';
import 'state/profile_controller.dart';

void main() {
  runApp(const MistakePrintApp());
}

/// 应用根组件：持有唯一一份 [ProfileController]，并把当前档案共享给整棵树。
///
/// 只有接线，没有业务：出图在输入页、展示与分享在预览页、参数在设置页。
class MistakePrintApp extends StatefulWidget {
  const MistakePrintApp({super.key, this.controller});

  /// 测试注入一份不碰平台通道的控制器；为 null 时读应用私有目录里的存档。
  final ProfileController? controller;

  @override
  State<MistakePrintApp> createState() => _MistakePrintAppState();
}

class _MistakePrintAppState extends State<MistakePrintApp> {
  late final ProfileController _controller =
      widget.controller ?? ProfileController();

  @override
  void initState() {
    super.initState();
    // 读存档：没读到也不会卡住界面，未校准的默认档案本来就能直接出图。
    unawaited(_controller.load());
  }

  @override
  void dispose() {
    // 注入进来的控制器由注入方负责释放。
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ProfileScope(
        controller: _controller,
        child: MaterialApp(
          title: kAppName,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2E6B4F)),
            // Material Design 3 是当前 Flutter 版本的默认行为，显式列出以固定意图。
            useMaterial3: true,
          ),
          home: const InputPage(),
        ),
      );
}
