import 'dart:async';

import 'package:flutter/material.dart';

import '../render/offscreen/print_renderer.dart';
import '../share/share_service.dart';

/// 预览页：看这一张图长什么样，然后交给系统分享面板。
///
/// 出图与分享都已完成或在下方一步完成，所以这一页只做展示与转发，不再持有题干。
class PreviewPage extends StatefulWidget {
  const PreviewPage({
    super.key,
    required this.image,
    this.notices = const <String>[],
    this.shareService = const ShareService(),
  });

  final PrintImage image;

  /// 预处理层动过的地方（识别到几处公式、删了几个表情……），空列表表示没动过。
  final List<String> notices;

  final ShareService shareService;

  @override
  State<PreviewPage> createState() => _PreviewPageState();
}

class _PreviewPageState extends State<PreviewPage> {
  bool _sharing = false;

  /// 最近一次分享的结局；失败时它还是「图在哪」的答案。
  ShareReport? _report;

  Future<void> _share() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    final ShareReport report = await widget.shareService.share(widget.image);
    if (!mounted) return;
    setState(() {
      _sharing = false;
      _report = report;
    });
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(_describe(report))));
  }

  /// 四种结局的人话（`unavailable` 不是失败，别吓用户）。
  static String _describe(ShareReport report) {
    switch (report.outcome) {
      case ShareOutcome.shared:
        return '已交给系统分享面板';
      case ShareOutcome.dismissed:
        return '已取消分享';
      case ShareOutcome.unavailable:
        return '这一机型拿不到分享回执，请到喵喵机 App 里确认';
      case ShareOutcome.failed:
        return '拉起分享面板失败：${report.error}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final PrintImage image = widget.image;
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('预览')),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '${image.width} × ${image.height} 点 · 黑点 ${image.blackDots}'
                  '（${(image.blackRatio * 100).toStringAsFixed(2)}%）',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 2),
                Text(
                  '排版 ${image.layoutPasses} 轮 · 耗时 '
                  '${image.elapsed.inMilliseconds} ms',
                  style: theme.textTheme.bodySmall,
                ),
                if (widget.notices.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 8),
                  for (final String notice in widget.notices)
                    Text(
                      '· $notice',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
                if (_report != null) ...<Widget>[
                  const SizedBox(height: 8),
                  SelectableText(
                    '图片已保存到：${_report!.file.path}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ColoredBox(
              color: theme.colorScheme.surfaceContainerHighest,
              child: SingleChildScrollView(
                child: Center(
                  // 1-bit 图必须关掉插值，否则缩放后细线会被糊成灰边。
                  child: Image.memory(
                    image.png,
                    filterQuality: FilterQuality.none,
                    width: image.width.toDouble(),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _sharing ? null : () => unawaited(_share()),
              icon: const Icon(Icons.ios_share),
              label: Text(_sharing ? '正在拉起分享…' : '分享到喵喵机 App'),
            ),
          ),
        ),
      ),
    );
  }
}