import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../share/gallery_store.dart';

/// 字节数的可读形式：不足 1 MB 用 KB，往上用 MB（出图多为几百 KB 的长条图）。
String formatBytes(int bytes) {
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
}

/// 输出图片管理页：列出系统相册 `Pictures/MistakePrint/` 里本应用写入的图，
/// 支持全屏预览、单张删除与全部清空（出图入相册设计）。
///
/// 数据源就是对相册的实时查询，没有本地索引——删完即生效，不存在「App 里删了、
/// 图库还留着」的死链。
class ImageStorePage extends StatefulWidget {
  const ImageStorePage({super.key, this.store = const GalleryStore()});

  /// 相册来源，测试注入假实现。
  final GalleryStore store;

  @override
  State<ImageStorePage> createState() => _ImageStorePageState();
}

class _ImageStorePageState extends State<ImageStorePage> {
  List<GalleryImage> _images = <GalleryImage>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final List<GalleryImage> images = await widget.store.list();
    if (!mounted) return;
    setState(() {
      _images = images;
      _loading = false;
    });
  }

  Future<bool?> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
  }) =>
      showDialog<bool>(
        context: context,
        builder: (BuildContext context) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(confirmLabel),
            ),
          ],
        ),
      );

  Future<void> _delete(GalleryImage image) async {
    final bool? ok = await _confirm(
      title: '删除这张图',
      message: '${image.name} 将从相册中删除，无法恢复。继续？',
      confirmLabel: '删除',
    );
    if (ok != true) return;
    try {
      await widget.store.delete(image.uri);
      await _refresh();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('删除失败：$error')));
    }
  }

  Future<void> _deleteAll() async {
    final bool? ok = await _confirm(
      title: '清空全部输出图片',
      message: '共 ${_images.length} 张将从相册中删除，无法恢复。继续？',
      confirmLabel: '清空',
    );
    if (ok != true) return;
    try {
      await widget.store.deleteAll();
      await _refresh();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('清空失败：$error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final int totalSize =
        _images.fold<int>(0, (int sum, GalleryImage image) => sum + image.size);
    return Scaffold(
      appBar: AppBar(
        title: const Text('输出图片'),
        actions: <Widget>[
          if (!_loading && _images.isNotEmpty)
            TextButton(
              onPressed: _deleteAll,
              child: const Text('全部清空'),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _images.isEmpty
              ? const Center(child: Text('还没有输出图片'))
              : Column(
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '共 ${_images.length} 张 · 占用 ${formatBytes(totalSize)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _images.length,
                        itemBuilder: (BuildContext context, int index) {
                          final GalleryImage image = _images[index];
                          return ListTile(
                            title: Text(image.name),
                            subtitle: Text(formatBytes(image.size)),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline),
                              tooltip: '删除',
                              onPressed: () => _delete(image),
                            ),
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (BuildContext context) =>
                                    _ImagePreviewPage(
                                  store: widget.store,
                                  image: image,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
    );
  }
}

/// 全屏预览：纯黑底 + 双指缩放拖动；字节经相册通道按媒体 URI 读回。
class _ImagePreviewPage extends StatefulWidget {
  const _ImagePreviewPage({required this.store, required this.image});

  final GalleryStore store;
  final GalleryImage image;

  @override
  State<_ImagePreviewPage> createState() => _ImagePreviewPageState();
}

class _ImagePreviewPageState extends State<_ImagePreviewPage> {
  Uint8List? _bytes;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final Uint8List bytes = await widget.store.readBytes(widget.image.uri);
      if (!mounted) return;
      setState(() => _bytes = bytes);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(
          widget.image.name,
          style: const TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: _error != null
            ? Text(
                '读取失败：$_error',
                style: const TextStyle(color: Colors.white70),
              )
            : _bytes == null
                ? const CircularProgressIndicator()
                : InteractiveViewer(
                    maxScale: 8,
                    child: Image.memory(_bytes!, fit: BoxFit.contain),
                  ),
      ),
    );
  }
}
