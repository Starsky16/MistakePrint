// E6：首次生成时根号不渲染，重试才恢复。
//
// 根号不是字体字形，而是 flutter_math_fork 把 `\sqrt` 渲染成 SVG 路径、经
// flutter_svg 异步加载的结果；未解码时它画的是 vector_graphics 的空白占位方盒。
// release（AOT）下这条加载链要真的开 isolate 编码，而离屏管线「排版 → 绘制 →
// toImage」全程同步，首帧必然拿不到图；重试时 flutter_svg 的全局 svg.cache 已命中
// ByteData，加载退化成同步，于是又好。本用例锁住「首帧即带矢量图」这条契约。
//
// 为什么不直接渲一道 `\sqrt`：flutter_svg 在 debug 下把 compute 换成了同步实现
// （见包的 src/utilities/compute.dart），只有 release 才走 isolate。也就是说这个竞态
// 在 flutter test 里天然不可复现（已实测：debug 下冷缓存的第 1 次出图就已带根号）。
// 这里用一个「延迟一个真实回合才交出数据」的 loader，在这条离屏管线上等价复现
// release 的异步行为。

import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mistake_print/profiles/paper_profile.dart';
import 'package:mistake_print/render/offscreen/offscreen_canvas.dart';
import 'package:mistake_print/render/raster/raw_capture.dart';

/// 一块实心方块的 SVG：落纸后是一整片黑，便于像素断言。
const String _solidSquareSvg =
    '<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100" '
    'viewBox="0 0 100 100">'
    '<path fill="rgb(0,0,0)" d="M0 0h100v100H0z"/></svg>';

/// 延迟一个真实事件循环回合才交出字节的 loader，模拟 release 下的 isolate 编码。
///
/// 与 flutter_svg 的 loader 一样，同一 cache key 的并发请求共享同一个 Future——这样
/// 「等它落地」等到的就是 widget 自己那条链，而不是另起一份。
class _SlowSvgLoader extends BytesLoader {
  const _SlowSvgLoader();

  static final Map<Object, Future<ByteData>> _pending =
      <Object, Future<ByteData>>{};

  @override
  Future<ByteData> loadBytes(BuildContext? context) => _pending.putIfAbsent(
        cacheKey(context),
        () => Future<void>.delayed(const Duration(milliseconds: 30)).then(
            (_) => const SvgStringLoader(_solidSquareSvg).loadBytes(context)),
      );

  @override
  Object cacheKey(BuildContext? context) => 'e6-slow-svg';
}

/// 画面里的深色像素数（黑字白底，直接数即可）。
///
/// 必须带上 alpha 判断：离屏树里没有白底（白底是 [DocumentView] 自己画的），
/// 未落墨处是**全透明**，只看 R 会把整张图都当成黑的。
int _darkPixels(RawCapture raw) {
  int dark = 0;
  for (int i = 0; i < raw.rgba.length; i += 4) {
    if (raw.rgba[i + 3] >= 128 && raw.rgba[i] < 128) dark++;
  }
  return dark;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('首次出图就带内嵌矢量图，不依赖重试', (WidgetTester tester) async {
    svg.cache.clear();
    late RawCapture raw;
    await tester.runAsync(() async {
      final OffscreenCapture shot = await const OffscreenCanvas().capture(
        child: const SvgPicture(_SlowSvgLoader(), width: 40, height: 40),
        widthDots: kPaperangP1Default.printableDotsWidth,
      );
      raw = shot.raw;
    });

    expect(raw.width, kPaperangP1Default.printableDotsWidth);
    expect(_darkPixels(raw), greaterThan(0),
        reason: '首帧就应画出矢量图；为 0 说明光栅化跑赢了异步加载（真机上就是根号缺失）');
  });
}