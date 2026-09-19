import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// 把 PNG 写到 [dir] 下并打印 IHDR 关键字段，供开发期离线自检。
void writePng(String dir, String name, Uint8List bytes) {
  final Directory outDir = Directory(dir)..createSync(recursive: true);
  File('${outDir.path}${Platform.pathSeparator}$name').writeAsBytesSync(bytes);
  final _PngHeader h = _parseIhdr(bytes);
  debugPrint(
    '[输出] $name  ${bytes.length} B  '
    '${h.width}x${h.height} bitDepth=${h.bitDepth} colorType=${h.colorType} '
    'pHYs=${_hasPhys(bytes)}',
  );

  // 1-bit 图必须是 bitDepth=1 / colorType=0，否则说明编码路径走偏了。
  if (h.bitDepth == 1) {
    expect(h.colorType, 0, reason: '$name 应为灰度 colorType=0');
  }
}

/// PNG IHDR 关键字段。
class _PngHeader {
  const _PngHeader(this.width, this.height, this.bitDepth, this.colorType);

  final int width;
  final int height;
  final int bitDepth;
  final int colorType;
}

_PngHeader _parseIhdr(Uint8List png) {
  final ByteData bd = ByteData.sublistView(png);
  return _PngHeader(
    bd.getUint32(16),
    bd.getUint32(20),
    bd.getUint8(24),
    bd.getUint8(25),
  );
}

/// 扫描 PNG 块，判断是否存在 pHYs。
bool _hasPhys(Uint8List png) {
  for (int i = 8; i + 8 <= png.length;) {
    final ByteData bd = ByteData.sublistView(png);
    final int length = bd.getUint32(i);
    final String type = String.fromCharCodes(png.sublist(i + 4, i + 8));
    if (type == 'pHYs') {
      return true;
    }
    if (type == 'IEND') {
      return false;
    }
    i += 12 + length;
  }
  return false;
}