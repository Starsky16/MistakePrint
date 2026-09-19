import 'dart:typed_data';

/// 一次离屏渲染捕获到的原始 RGBA 像素。
///
/// [rgba] 逐行排列，长度 = `width × height × 4`；空白处为不透明白。
class RawCapture {
  RawCapture(this.rgba, this.width, this.height);

  final Uint8List rgba;
  final int width;
  final int height;
}

/// 逐像素计算亮度（0 黑 ~ 255 白），权重按 ITU-R BT.601。
Uint8List luminanceOf(RawCapture cap) {
  final Uint8List lum = Uint8List(cap.width * cap.height);
  for (int i = 0; i < lum.length; i++) {
    final int r = cap.rgba[i * 4];
    final int g = cap.rgba[i * 4 + 1];
    final int b = cap.rgba[i * 4 + 2];
    lum[i] = (r * 299 + g * 587 + b * 114) ~/ 1000;
  }
  return lum;
}