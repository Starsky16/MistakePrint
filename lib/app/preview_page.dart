import 'dart:async';

import 'package:flutter/material.dart';

import '../render/offscreen/print_renderer.dart';
import '../share/gallery_store.dart';
import '../share/share_service.dart';

/// 预览页：看这一张图长什么样，进入即写入系统相册，然后交给系统面板分享。
///
/// 出图与落相册都已在进入本页时完成或在下方一步完成，所以这一页只做展示、
/// 落库与转发，不再持有题干。
class PreviewPage extends StatefulWidget {
  const PreviewPage({
    super.key,
    required this.image,
    this.notices = const <String>[],
    this.galleryStore = const GalleryStore(),
    this.shareService = const ShareService(),
  });

  final PrintImage image;

  /// 预处理层动过的地方（识别到几处公式、删了几个表情……），空列表表示没动过。
  final List<String> notices;

  final GalleryStore galleryStore;

  final ShareService shareService;

  @override
  State<PreviewPage> createState() => _PreviewPageState();
}

class _PreviewPageState extends State<PreviewPage> {
  bool _saving = true;
  bool _sharing = false;
  GalleryImage? _saved;
  Object? _saveError;
  ShareReport? _report;

  @override
  void initState() {
    super.initState();
    unawaited(_save());
  }

  /// 出图完成即写相册（「所有出图直接写入相册」的设计拍板）：
  /// PNG 字节已在本页手里，保存失败也还能重试，不丢图。
  Future<void> _save() async {
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      final GalleryImage image = await widget.galleryStore.save(
        widget.image.png,
        name: GalleryStore.buildFileName(
          widget.image.width,
          widget.image.height,
          null,
        ),
      );
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saved = image;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = error;
      });
    }
  }

  Future<void> _share() async {
    final GalleryImage? image = _saved;
    if (_sharing || image == null) return;
    setState(() => _sharing = true);
    final ShareReport report = await widget.shareService.share(image);
    if (!mounted) return;
    setState(() {
      _sharing = false;
      _report = report;
    });
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(_describe(report))));
  }

  /// 三种结局的人话（`unavailable` 不是失败，别吓用户）。
  static String _describe(ShareReport report) => switch (report.outcome) {
        ShareOutcome.shared => '已交给系统分享面板',
        ShareOutcome.unavailable => '没有应用可以接收这张图片',
        ShareOutcome.failed => '拉起分享面板失败：${report.error}',
      };

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
                const SizedBox(height: 8),
                _saveStatus(theme),
                if (_report != null) ...<Widget>[
                  const SizedBox(height: 8),
                  SelectableText(
                    '分享源：${_report!.image.uri}',
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
            child: _bottomButton(),
          ),
        ),
      ),
    );
  }

  Widget _saveStatus(ThemeData theme) {
    if (_saving) {
      return Text('正在写入相册…', style: theme.textTheme.bodySmall);
    }
    final GalleryImage? saved = _saved;
    if (saved != null) {
      return Text(
        '已保存到相册 · ${saved.name}',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }
    return Text(
      '保存到相册失败：$_saveError',
      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
    );
  }

  Widget _bottomButton() {
    if (_saving) {
      return FilledButton.icon(
        onPressed: null,
        icon: const Icon(Icons.sync),
        label: const Text('正在写入相册…'),
      );
    }
    if (_saved == null) {
      return FilledButton.icon(
        onPressed: () => unawaited(_save()),
        icon: const Icon(Icons.refresh),
        label: const Text('重试保存到相册'),
      );
    }
    return FilledButton.icon(
      onPressed: _sharing ? null : () => unawaited(_share()),
      icon: const Icon(Icons.ios_share),
      label: Text(_sharing ? '正在拉起分享…' : '分享 / 发送图片'),
    );
  }
}
