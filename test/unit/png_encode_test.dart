// pHYs 块的 dpi 必须来自机型档案：此前写死 P1 的 203，P2（300 dpi）出图会被
// 按 203 dpi 解释成错误的物理尺寸。这里直接按 PNG chunk 结构解析断言，
// 不依赖 image 包的解码回读（与 document_render_test 的 IHDR 断言同一口径）。

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mistake_print/render/raster/png_encode.dart';
import 'package:mistake_print/render/raster/raw_capture.dart';

/// 在 PNG 字节流里按 chunk 结构找 pHYs，返回 (xPPM, yPPM, unit)；没有则 null。
(int, int, int)? physChunk(Uint8List png) {
  int offset = 8; // 跳过 8 字节文件签名
  while (offset + 8 <= png.length) {
    final ByteData header = ByteData.sublistView(png, offset);
    final int length = header.getUint32(0);
    final String type =
        String.fromCharCodes(png.sublist(offset + 4, offset + 8));
    if (type == 'pHYs') {
      final ByteData data =
          ByteData.sublistView(png, offset + 8, offset + 8 + 9);
      return (data.getUint32(0), data.getUint32(4), data.getUint8(8));
    }
    if (type == 'IEND') return null;
    offset += 12 + length; // length(4) + type(4) + data + crc(4)
  }
  return null;
}

void main() {
  List<List<bool>> bitmap() => List<List<bool>>.generate(
        4,
        (int y) => List<bool>.generate(4, (int x) => (x + y).isEven),
      );

  test('pHYs 按传入 dpi 写入（P2 = 300 dpi ≈ 11811 点/米）', () {
    final Uint8List png = encodeBitmap(bitmap(), withPhys: true, dpi: 300);
    final (int x, int y, int unit) = physChunk(png)!;
    expect(unit, 1, reason: 'pHYs 单位必须是米');
    expect(x, closeTo(300 * 39.3701, 2));
    expect(y, x);
  });

  test('P1 的 203 dpi 同样按传入值写入（不再是写死常量）', () {
    final Uint8List png = encodeBitmap(bitmap(), withPhys: true, dpi: 203);
    final (int x, int y, int unit) = physChunk(png)!;
    expect(unit, 1);
    expect(x, closeTo(203 * 39.3701, 2));
    expect(y, x);
  });

  test('不写 pHYs 时没有该 chunk', () {
    expect(
      physChunk(encodeBitmap(bitmap(), withPhys: false, dpi: 300)),
      isNull,
    );
  });

  test('encodeGray 同样透传 dpi', () {
    final Uint8List png = encodeGray(
      RawCapture(
        Uint8List.fromList(<int>[
          255, 255, 255, 255, 255, 255, 255, 255,
          255, 255, 255, 255, 255, 255, 255, 255,
          255, 255, 255, 255, 255, 255, 255, 255,
          255, 255, 255, 255, 255, 255, 255, 255,
        ]),
        2,
        2,
      ),
      withPhys: true,
      dpi: 300,
    );
    final (int x, _, _) = physChunk(png)!;
    expect(x, closeTo(300 * 39.3701, 2));
  });
}
