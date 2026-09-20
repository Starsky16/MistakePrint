import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import '../render/text/text_styles.dart';

/// 目标机型的名义点阵宽度（喵喵机 P1）。默认值，真实值由校准向导得出。
const int kPaperWidth = 384;

/// 画布宽度（double 版）。`const Size` 里不能写 `kPaperWidth.toDouble()`，
/// 因为方法调用不是常量表达式。
const double kPaperWidthDots = 384;

/// 图 A 高度。
const double kFigureAHeight = 48;

const Color _black = Color(0xFF000000);
const Color _white = Color(0xFFFFFFFF);

// 字体族名与正文字样统一由 render/text/text_styles.dart 提供（正文渲染与校准素材
// 必须是同一套字体定义）。

/// 固定宽度画布，背景纯白。
Widget canvas(double width, {double? height, required Widget child}) => SizedBox(
      width: width,
      height: height,
      child: ColoredBox(color: _white, child: child),
    );

// ---------------------------------------------------------------------------
// 图 A：点阵宽度标尺
// ---------------------------------------------------------------------------

/// 图 A：贴四边的 1px 边框 + 刻度 + 数字，用于反推真实点阵密度与是否被裁边。
Widget figureA() => canvas(
      kPaperWidthDots,
      height: kFigureAHeight,
      child: CustomPaint(size: const Size(kPaperWidthDots, kFigureAHeight), painter: _RulerPainter()),
    );

class _RulerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // 整数坐标 + 关闭抗锯齿：1:1 下得到纯黑零灰边（已实测）。
    final line = Paint()
      ..color = _black
      ..isAntiAlias = false
      ..strokeWidth = 1;

    final double w = size.width;
    final double h = size.height;

    // 1) 四边 1px 边框，贴边绘制。
    canvas.drawRect(const Rect.fromLTWH(0, 0, kPaperWidthDots, 1), line);
    canvas.drawRect(Rect.fromLTWH(0, h - 1, w, 1), line);
    canvas.drawRect(Rect.fromLTWH(0, 0, 1, h), line);
    canvas.drawRect(Rect.fromLTWH(w - 1, 0, 1, h), line);

    // 2) 顶部刻度：32px 标记（高 4）< 10px 短刻度（高 6）< 50px 长刻度（高 12）。
    for (int x = 0; x <= kPaperWidth; x += 32) {
      canvas.drawRect(Rect.fromLTWH(x.toDouble(), 1, 1, 4), line);
    }
    for (int x = 0; x <= kPaperWidth; x += 10) {
      canvas.drawRect(Rect.fromLTWH(x.toDouble(), 1, 1, 6), line);
    }
    for (int x = 0; x <= kPaperWidth - 1; x += 50) {
      canvas.drawRect(Rect.fromLTWH(x.toDouble(), 1, 1, 12), line);
    }

    // 3) 底部 32px 标记，便于目测数格（384 = 12 × 32）。
    for (int x = 0; x <= kPaperWidth; x += 32) {
      canvas.drawRect(Rect.fromLTWH(x.toDouble(), h - 5, 1, 4), line);
    }

    // 4) 长刻度旁标数字，中心对齐刻度。
    for (int x = 0; x <= kPaperWidth - 1; x += 50) {
      final tp = TextPainter(
        text: TextSpan(text: '$x', style: bodyStyle(10)),
        textDirection: TextDirection.ltr,
      )..layout();
      final double left = (x - tp.width / 2).clamp(1, w - tp.width - 1);
      tp.paint(canvas, Offset(left, 15));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ---------------------------------------------------------------------------
// 图 B：字号与线宽/灰度阶梯
// ---------------------------------------------------------------------------

/// 图 B 逐档字号。
const List<double> kFontLadder = [12, 14, 16, 18, 20, 22, 24, 28, 32];

/// 图 B：最小可读字号 + 1px 线是否可见 + 首个可见灰度档（定阈值）。
Widget figureB() => canvas(
      kPaperWidthDots,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final double fs in kFontLadder) ...[
            Padding(
              padding: const EdgeInsets.only(left: 2, top: 2),
              child: Text('fs=${fs.toInt()}', style: bodyStyle(8)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Text('错题 1：△ABC ≌ △DEF，∠A=30°，AB//DE', style: bodyStyle(fs)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Text('x² + y² = r²，a/b，√3，①②③，Ⅰ Ⅱ Ⅲ', style: bodyStyle(fs)),
            ),
            const SizedBox(height: 8),
          ],
          const Padding(
            padding: EdgeInsets.only(left: 2, top: 4),
            child: Text('线宽：1px / 2px / 3px 水平线各 3 条（长 200）与竖线各 3 条', style: TextStyle(fontFamily: kBodyFont, fontSize: 8, color: _black)),
          ),
          canvas(
            kPaperWidthDots,
            height: 70,
            child: CustomPaint(size: const Size(kPaperWidthDots, 70), painter: _LineWidthPainter()),
          ),
          const Padding(
            padding: EdgeInsets.only(left: 2, top: 6),
            child: Text('灰度阶梯：10 档（左黑右白）', style: TextStyle(fontFamily: kBodyFont, fontSize: 8, color: _black)),
          ),
          canvas(
            kPaperWidthDots,
            height: 44,
            child: CustomPaint(size: const Size(kPaperWidthDots, 44), painter: _GrayLadderPainter()),
          ),
        ],
      ),
    );

/// 1px / 2px / 3px 水平线与竖线阶梯。
class _LineWidthPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    double y = 2;
    // 水平线：1px、2px、3px 各三条，长 200。
    for (final int width in [1, 2, 3]) {
      final paint = Paint()
        ..color = _black
        ..isAntiAlias = false;
      for (int i = 0; i < 3; i++) {
        canvas.drawRect(Rect.fromLTWH(10, y, 200, width.toDouble()), paint);
        y += width + 4;
      }
      y += 4;
    }

    // 竖线：1px、2px、3px 各三条，高 40，放在右侧。
    double x = 250;
    for (final int width in [1, 2, 3]) {
      final paint = Paint()
        ..color = _black
        ..isAntiAlias = false;
      for (int i = 0; i < 3; i++) {
        canvas.drawRect(Rect.fromLTWH(x, 2, width.toDouble(), 40), paint);
        x += width + 4;
      }
      x += 6;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 10 档灰度阶梯，每档 38px 宽（最后一档补足剩余宽度）。
class _GrayLadderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    for (int i = 0; i < 10; i++) {
      final int value = (255 * i / 9).round();
      final double left = (38 * i).toDouble();
      final double right = i == 9 ? size.width : (38 * (i + 1)).toDouble();
      canvas.drawRect(
        Rect.fromLTRB(left, 0, right, size.height),
        Paint()..color = Color.fromARGB(255, value, value, value),
      );
    }
    // 每档之间画 1px 分隔线，便于在打印结果上定位档位。
    final line = Paint()
      ..color = _black
      ..isAntiAlias = false;
    for (int i = 0; i <= 9; i++) {
      canvas.drawRect(Rect.fromLTWH((38 * i).toDouble(), 0, 1, size.height), line);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ---------------------------------------------------------------------------
// 图 C：细线保真（分式、根号、上下标、1px 表格与抖动探测）
// ---------------------------------------------------------------------------

/// 图 C1 的分式字号阶梯。
const List<double> kFractionLadder = [10, 12, 14, 16, 20, 24, 28];

/// 图 C1：`a/b` 分式在 7 档字号下的表现，用于判读分数线是否被二值化抹掉。
Widget figureC1() => canvas(
      kPaperWidthDots,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final double fs in kFractionLadder) ...[
            Padding(
              padding: const EdgeInsets.only(left: 2),
              child: Text('fs=${fs.toInt()}', style: bodyStyle(8)),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 6, bottom: 6),
              child: Math.tex(
                r'\frac{a}{b} \quad \frac{1}{x+1} \quad \frac{x^2-1}{x+1}',
                textStyle: bodyStyle(fs),
              ),
            ),
          ],
        ],
      ),
    );

/// 图 C2：三层嵌套分式、根号横线、上下标极限样本。
Widget figureC2() => canvas(
      kPaperWidthDots,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('三层嵌套分式', style: TextStyle(fontFamily: kBodyFont, fontSize: 8, color: _black, height: 1.4)),
            Math.tex(
              r'\frac{1}{1+\frac{1}{1+\frac{1}{x}}}',
              textStyle: bodyStyle(24),
            ),
            const SizedBox(height: 6),
            const Text('根号横线', style: TextStyle(fontFamily: kBodyFont, fontSize: 8, color: _black, height: 1.4)),
            Math.tex(r'\sqrt{x} \quad \sqrt[3]{x} \quad \sqrt{x^2+y^2}', textStyle: bodyStyle(24)),
            const SizedBox(height: 6),
            const Text('上下标与极限', style: TextStyle(fontFamily: kBodyFont, fontSize: 8, color: _black, height: 1.4)),
            Math.tex(r'x^{n}_{i} \quad a^{2^{3}} \quad \sum_{i=1}^{n} a_i', textStyle: bodyStyle(24)),
          ],
        ),
      ),
    );

/// 图 C3：1px 小表格 + 1px 棋盘格 + 竖条纹（探测 App 是否抖动）。
Widget figureC3() => canvas(
      kPaperWidthDots,
      height: 320,
      child: CustomPaint(size: const Size(kPaperWidthDots, 320), painter: _ThinLinePainter()),
    );

class _ThinLinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = _black
      ..isAntiAlias = false;

    // 1) 1px 边框小表格：4 列 × 3 行，列宽 60、行高 24。
    const double cellW = 60;
    const double cellH = 24;
    const double tableLeft = 6;
    const double tableTop = 16;
    for (int c = 0; c <= 4; c++) {
      canvas.drawRect(Rect.fromLTWH(tableLeft + cellW * c, tableTop, 1, cellH * 3), line);
    }
    for (int r = 0; r <= 3; r++) {
      canvas.drawRect(Rect.fromLTWH(tableLeft, tableTop + cellH * r, cellW * 4, 1), line);
    }
    _drawLabel(canvas, '1px 表格', tableLeft, tableTop + cellH * 3 + 3);

    // 2) 1px 棋盘格 96×96（每隔一像素取反，最容易暴露抖动）。
    const double checkerTop = 120;
    for (int y = 0; y < 96; y++) {
      for (int x = 0; x < 96; x++) {
        if ((x + y).isEven) {
          canvas.drawRect(Rect.fromLTWH(6 + x.toDouble(), checkerTop + y.toDouble(), 1, 1), line);
        }
      }
    }
    _drawLabel(canvas, '1px 棋盘格', 6, checkerTop + 99);

    // 3) 1px 竖条纹（周期 2px 与 3px）。
    const double stripeTop = 240;
    for (int x = 0; x < 180; x += 2) {
      canvas.drawRect(Rect.fromLTWH(6 + x.toDouble(), stripeTop, 1, 40), line);
    }
    for (int x = 0; x < 180; x += 3) {
      canvas.drawRect(Rect.fromLTWH(200 + x.toDouble(), stripeTop, 1, 40), line);
    }
    _drawLabel(canvas, '1px 竖条纹 周期2 / 周期3', 6, stripeTop + 43);
  }

  void _drawLabel(Canvas canvas, String text, double x, double y) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: bodyStyle(8)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(x, y));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ---------------------------------------------------------------------------
// 图 D：Unicode 覆盖表
// ---------------------------------------------------------------------------

/// 分组字符清单（与计划 6.4 一致）。
const List<(String, String)> kUnicodeGroups = [
  ('几何与关系', '▱▭△▲⊙≌∽⌢∠⊥∥'),
  ('序号', '①②③④⑤⑩⑴⒈'),
  ('罗马数字', 'ⅠⅡⅢⅣⅤ'),
  ('单位', '℃ΩµÅ℉%'),
  ('分数与上下标', '½⅓²³₁₂⁻¹'),
  ('箭头', '→←↑↓⇌⟶⇒'),
  ('希腊', 'αβγθπΔΣω'),
  ('中文标点', '《》「」……～、；：'),
  ('对照（私用区，必然缺失）', '\uE000\uE001'),
];

/// 每格宽度：6 格 × 64 = 384。
const double kCellWidth = 64;

/// 图 D：网格布局，每格一个字符 + 下方码点标签。
///
/// [symbolFont] 为 true 时走数学符号字体通道，否则走正文通道。
Widget figureD({required bool symbolFont, required String title}) => canvas(
      kPaperWidthDots,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 2, top: 4, bottom: 4),
            child: Text(title, style: bodyStyle(11)),
          ),
          for (final (String groupName, String chars) in kUnicodeGroups) ...[
            Padding(
              padding: const EdgeInsets.only(left: 2, top: 4),
              child: Text(groupName, style: bodyStyle(8)),
            ),
            Wrap(
              children: [
                for (final int rune in chars.runes)
                  SizedBox(
                    width: kCellWidth,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          String.fromCharCode(rune),
                          style: symbolFont ? symbolStyle(26) : bodyStyle(26),
                        ),
                        Text(
                          'U+${rune.toRadixString(16).toUpperCase().padLeft(4, '0')}',
                          style: bodyStyle(8),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 6),
        ],
      ),
    );

// ---------------------------------------------------------------------------
// 图 E：App 处理行为探针
// ---------------------------------------------------------------------------

/// 图 E 之一：10 档灰度阶梯放大版（判定 App 是阈值化还是抖动）。
Widget figureEGrayLadder() => canvas(
      kPaperWidthDots,
      height: 200,
      child: const CustomPaint(
        size: Size(kPaperWidthDots, 200),
        painter: _BigGrayLadderPainter(),
      ),
    );

class _BigGrayLadderPainter extends CustomPainter {
  const _BigGrayLadderPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final double stepH = size.height / 10;
    for (int i = 0; i < 10; i++) {
      final int value = (255 * i / 9).round();
      canvas.drawRect(
        Rect.fromLTWH(0, stepH * i, size.width, stepH),
        Paint()..color = Color.fromARGB(255, value, value, value),
      );
      final tp = TextPainter(
        text: TextSpan(text: '$value', style: bodyStyle(8)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(4, stepH * i + 2));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 图 E 之一：故意超宽（1024px）的横线与文字，判定 App 是否裁切或压缩。
Widget figureEOversize() => canvas(
      1024,
      height: 120,
      child: CustomPaint(size: const Size(1024, 120), painter: _OversizePainter()),
    );

class _OversizePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = _black
      ..isAntiAlias = false;
    // 满宽 1px 横线 3 条，间隔 20px。
    for (int i = 0; i < 3; i++) {
      canvas.drawRect(Rect.fromLTWH(0, (10 + i * 20).toDouble(), 1024, 1), line);
    }
    // 端点是重复的竖线参考。
    for (int x = 0; x < 1024; x += 256) {
      canvas.drawRect(Rect.fromLTWH(x.toDouble(), 70, 4, 20), line);
    }
    final tp = TextPainter(
      text: TextSpan(text: '超宽探针：本图宽 1024 点，若被压缩则竖线间距变窄', style: bodyStyle(14)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, const Offset(4, 94));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 图 E 之一：细长图 300×3000，判定是否被截断或强压缩。
Widget figureETall() => canvas(
      300,
      height: 3000,
      child: CustomPaint(size: const Size(300, 3000), painter: _TallPainter()),
    );

class _TallPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = _black
      ..isAntiAlias = false;
    // 左右 1px 边框，贯穿全高。
    canvas.drawRect(const Rect.fromLTWH(0, 0, 1, 3000), line);
    canvas.drawRect(const Rect.fromLTWH(299, 0, 1, 3000), line);
    // 每 100px 一条 1px 横线并标序号。
    for (int y = 0; y < 3000; y += 100) {
      canvas.drawRect(Rect.fromLTWH(0, y.toDouble(), 300, 1), line);
      final tp = TextPainter(
        text: TextSpan(text: '$y', style: bodyStyle(10)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(6, y + 4));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}