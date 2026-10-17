import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 相册通道名（Android MainActivity 里同名 MethodChannel）。
const MethodChannel kGalleryChannel = MethodChannel('mistake_print/gallery');

/// 相册里一条本应用写入的图片记录。
class GalleryImage {
  const GalleryImage({
    required this.id,
    required this.uri,
    required this.name,
    required this.size,
    required this.date,
  });

  /// MediaStore 的 `_ID`。
  final String id;

  /// 标准媒体 URI（`content://media/...`）——分享与回读都用它。
  final String uri;

  /// 展示名（`DISPLAY_NAME`）。
  final String name;

  /// 字节数（`SIZE`）。
  final int size;

  /// 写入时间（`DATE_ADDED`）。
  final DateTime date;

  /// 把通道返回的 Map 解析成记录；缺字段按空值兜底，不抛。
  static GalleryImage fromChannel(Object? raw) {
    final Map<Object?, Object?> map = raw! as Map<Object?, Object?>;
    return GalleryImage(
      id: (map['id'] as String?) ?? '',
      uri: (map['uri'] as String?) ?? '',
      name: (map['name'] as String?) ?? '',
      size: (map['size'] as num?)?.toInt() ?? 0,
      date: DateTime.fromMillisecondsSinceEpoch(
        (map['date'] as num?)?.toInt() ?? 0,
      ),
    );
  }
}

/// 相册操作失败（权限被拒、通道异常等），message 为可直接展示的中文。
class GalleryException implements Exception {
  const GalleryException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 出图相册存储（出图直接写入系统相册的设计）。
///
/// 出图 PNG 写入系统相册 `Pictures/MistakePrint/`；管理页与分享都基于相册里的媒体
/// URI。所有原生细节封装在 [kGalleryChannel] 之后，本类只做契约转换。
class GalleryStore {
  const GalleryStore({this.channel = kGalleryChannel});

  final MethodChannel channel;

  /// 写入一张 PNG 到相册，返回该记录。
  ///
  /// API 24–28 需要写公共存储的运行时权限，由原生 `ensureWritePermission` 处理；
  /// 拿不到就抛 [GalleryException]（中文提示）。
  Future<GalleryImage> save(Uint8List png, {required String name}) async {
    final bool granted =
        await channel.invokeMethod<bool>('ensureWritePermission') ?? false;
    if (!granted) {
      throw const GalleryException('未获得存储权限，无法保存到相册');
    }
    final Object? raw = await channel.invokeMethod<Object>('save', <String, Object?>{
      'name': name,
      'bytes': png,
    });
    return GalleryImage.fromChannel(raw);
  }

  /// 列出相册中本应用写入的图片，按写入时间倒序（原生保证），最新在上。
  Future<List<GalleryImage>> list() async {
    final List<Object?>? raw =
        await channel.invokeMethod<List<Object?>>('list');
    if (raw == null) return const <GalleryImage>[];
    return <GalleryImage>[
      for (final Object? item in raw) GalleryImage.fromChannel(item),
    ];
  }

  /// 按媒体 [uri] 读回字节（供预览 `Image.memory`）。
  Future<Uint8List> readBytes(String uri) async {
    final Uint8List? bytes =
        await channel.invokeMethod<Uint8List>('read', <String, Object?>{
      'uri': uri,
    });
    return bytes ?? Uint8List(0);
  }

  /// 删除单张；图片已不存在由原生静默处理。
  Future<void> delete(String uri) =>
      channel.invokeMethod<void>('delete', <String, Object?>{'uri': uri});

  /// 删除相册中本应用写入的全部图片。
  Future<void> deleteAll() => channel.invokeMethod<void>('deleteAll');

  /// 汇总本应用已写入相册图片的字节数。
  Future<int> totalSize() async {
    final List<GalleryImage> images = await list();
    return images.fold<int>(0, (int sum, GalleryImage image) => sum + image.size);
  }

  /// 生成文件名。
  ///
  /// 形如 `mistake_20260921-153012-384x7910.png`：时间戳保证同一秒外的两次出图不
  /// 互相覆盖，宽高让用户在相册与分享面板里一眼认出是哪一张。全 ASCII —— 文件名
  /// 会经 `Intent.EXTRA_STREAM` 传给别的 App，不用中文以免个别机型上乱码。
  static String buildFileName(int width, int height, DateTime? now) {
    String two(int value) => value.toString().padLeft(2, '0');
    final DateTime t = now ?? DateTime.now();
    final String stamp = '${t.year}${two(t.month)}${two(t.day)}'
        '-${two(t.hour)}${two(t.minute)}${two(t.second)}';
    return 'mistake_$stamp-${width}x$height.png';
  }
}
