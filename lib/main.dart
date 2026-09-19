import 'package:flutter/material.dart';

void main() {
  runApp(const MistakePrintApp());
}

/// 应用根组件。
///
/// 当前仅为 P0 平台基线骨架，版式与出图链路在后续阶段接入。
class MistakePrintApp extends StatelessWidget {
  const MistakePrintApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MistakePrint',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2E6B4F)),
        // Material Design 3 是当前 Flutter 版本的默认行为，显式列出以固定意图。
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

/// 首页占位。
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('MistakePrint')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          '把含 LaTeX 的错题题干渲染成热敏打印机位图。',
          style: theme.textTheme.bodyLarge,
        ),
      ),
    );
  }
}