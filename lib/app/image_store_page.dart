import 'dart:io';

import 'package:flutter/material.dart';

import '../share/png_file_store.dart';

/// 字节数的可读形式：不足 1 MB 用 KB，往上用 MB（出图多为几百 KB 的长条图）。
String formatBytes(int bytes) {
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
}

/// 输出图片管理页：列出 `<cacheDir>/mistake_print/` 里的历史出图，
/// 支持全屏预览、单张删除与全部清空（设计 2026-10-05）。
class ImageStorePage extends StatefulWidget {
  const ImageStorePage({super.key, this.store});

  /// 存储来源；默认走 path_provider（Android 上是 cacheDir），测试注入临时目录。
  final PngFileStore? store;

  @override
  State<ImageStorePage> createState() => _ImageStorePageState();
}

class _ImageStorePageState extends State<ImageStorePage> {
  late final PngFileStore _store = widget.store ?? PngFileStore();

  List<File> _files = <File>[];
  int _totalSize = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final List<File> files = await _store.list();
    final int totalSize = await _store.totalSize();
    if (!mounted) return;
    setState(() {
      _files = files;
      _totalSize = totalSize;
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

  Future<void> _delete(File file) async {
    final bool? ok = await _confirm(
      title: '删除这张图',
      message: '${file.uri.pathSegments.last} 将被删除，无法恢复。继续？',
      confirmLabel: '删除',
    );
    if (ok != true) return;
    try {
      await _store.delete(file);
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
      message: '共 ${_files.length} 张将被删除，无法恢复。继续？',
      confirmLabel: '清空',
    );
    if (ok != true) return;
    try {
      await _store.deleteAll();
      // share_plus 每次分享都会重新复制一份，顺带清掉它的残留（见设计文档）。
      await _store.deleteSharePlusCache();
      await _refresh();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('清空失败：$error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('输出图片'),
        actions: <Widget>[
          if (!_loading && _files.isNotEmpty)
            TextButton(
              onPressed: _deleteAll,
              child: const Text('全部清空'),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _files.isEmpty
              ? const Center(child: Text('还没有输出图片'))
              : Column(
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '共 ${_files.length} 张 · 占用 ${formatBytes(_totalSize)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _files.length,
                        itemBuilder: (BuildContext context, int index) {
                          final File file = _files[index];
                          return ListTile(
                            title: Text(file.uri.pathSegments.last),
                            subtitle: Text(formatBytes(file.lengthSync())),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline),
                              tooltip: '删除',
                              onPressed: () => _delete(file),
                            ),
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (BuildContext context) =>
                                    _ImagePreviewPage(file: file),
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

/// 全屏预览：纯黑底 + 双指缩放拖动。
class _ImagePreviewPage extends StatelessWidget {
  const _ImagePreviewPage({required this.file});

  final File file;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(
          file.uri.pathSegments.last,
          style: const TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: InteractiveViewer(
          maxScale: 8,
          child: Image.file(file, fit: BoxFit.contain),
        ),
      ),
    );
  }
}
