// 语料水平溢出**测量**断言（计划 2026-09-19 §4 P4 成功标准 5 / 6）。
//
// 与语料原文的回归（`tool/corpus_check.dart`）配套：那个脚本断言「预处理认出了公式」，
// 这里断言「渲染出来的东西真的没超出目标宽度」——不是目测，是量片段宽度。
//
// 为什么这么量（实测记录，2026-10-02）：
// 1. Flutter 的 `RenderParagraph` 对超宽内容**静默裁剪**。往 384 点宽的段落里塞一个
//    500px 的 `WidgetSpan`，子树照常布局、不报 overflow 异常；`RepaintBoundary.toImage`
//    只有 384 宽，第 384 个像素就是边界。
// 2. `RenderParagraph.getBoxesForSelection` 同样把 `box.right` 钳在约束内（实测人造
//    500px 内联块只报 `right=384`），所以它量不出溢出。
// 3. 因此唯一可靠的判据是**片段自身的自然宽度**：`DocumentView.debugFormulaSink`
//    在每个公式片段参与排版前上报它的宽度，以及它是否走了「整体缩放」兜底。
//
// 断言口径：
// - 任意片段宽度 ≤ 目标宽度 + 容差（显式容差 = 0.5 点，浮点排版取整）；
// - 或者该片段被显式标记 `degraded`（走 `FittedBox(scaleDown)` 缩到 384，**有告警**）；
// - `degraded == false` 且超宽的片段 = 静默裁切，必须为 0。

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mistake_print/profiles/paper_profile.dart';
import 'package:mistake_print/render/raster/binarize.dart';

import '../support/document_measure.dart';
import '../support/test_fonts.dart';

/// 浮点排版取整容差（点）。显式写出来，不用魔法值。
///
/// Flutter 的文本/公式布局在 1e-7 量级上仍有浮点误差，375.x 这类读数属于正常；
/// 容差取 0.5 点（约 1/2 打印机点，远小于 1 个墨点），既能吸收舍入又不会放过真实溢出。
const double kWidthToleranceDots = 0.5;

/// 一句话里同时含行内/块级公式的常规样例。
const String kSample = r'''
已知函数 $f(x)=x^2+2x+1$，求 $f(x)$ 的最小值。

$$\frac{a+b}{2}\geq\sqrt{ab}$$

设 $x$ 为正数，则 $\frac{x}{2}+\frac{1}{x}$ 的最小值为？
''';

/// 极端超宽公式：Q4 先在加号处断行。
const String kOversize =
    r'$$a_{1}+a_{2}+a_{3}+a_{4}+a_{5}+a_{6}+a_{7}+a_{8}+a_{9}+a_{10}+a_{11}+a_{12}+a_{13}+a_{14}=S$$';

/// 连断行都放不下的公式：`cases` 环境当前不支持拆解，`texBreak` 会整段返回。
/// 样例逐字取自真实语料 q04-题 18，整段宽约 518 点，超出 384。
const String kUnbreakableOversize =
    r'$\begin{cases} \vec{n} \cdot \vec{BC} = 0 \Rightarrow -x + \sqrt{3}y = 0 \Rightarrow x = \sqrt{3}y \\ '
    r'\vec{n} \cdot \vec{BD} = 0 \Rightarrow -2x - \sqrt{3}y + z = 0 \end{cases}$';

/// 嵌套根号（验收 ⑥ / E4 回归）：`+` 全在 `\sqrt{…}` 内层，`texBreak` 只扫顶层
/// 关系符/二元运算符，找不到任何断点 → 整段单段返回，必须落到整体缩放兜底。
/// 自然宽约 427 点，超出 384。
const String kNestedSqrtOversize =
    r'$$\sqrt{2+\sqrt{2+\sqrt{2+\sqrt{2+\sqrt{2+\sqrt{2+\sqrt{2}}}}}}}$$';

/// 造一份「正文很长、公式很多」的超宽压力样例。
String wideText({int lines = 12}) {
  const String body =
      r'已知函数 $f(x)=\frac{x^2+2x+1}{x-1}$，求 $f(x)$ 的最小值，并说明理由：';
  return List<String>.generate(lines, (int i) => '第 ${i + 1} 行：$body').join('\n');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await loadTestFonts();
  });

  group('水平溢出测量', () {
    testWidgets('常规样例：所有公式片段宽度都不超过目标宽度', (WidgetTester tester) async {
      final DocumentMeasure m = await measureAtPrintableWidth(
        tester,
        kSample,
        profile: kPaperangP1Default,
      );
      final double target = kPaperangP1Default.printableDotsWidth.toDouble();

      debugPrint(
        '[溢出] 常规样例 画面 ${m.widgetSize.width}×${m.widgetSize.height}，'
        '公式片段 ${m.fragments.length} 个，最宽 '
        '${m.fragments.isEmpty ? '—' : m.fragments.map((f) => f.widthDots).reduce((a, b) => a > b ? a : b).toStringAsFixed(1)} 点',
      );

      expect(m.widgetSize.width, target, reason: '渲染根宽度必须精确等于目标宽度');
      expect(m.fragments, isNotEmpty, reason: '样例应至少有一个公式片段');

      final List<FormulaFragment> over = m.overflow(target, tolerance: kWidthToleranceDots);
      expect(
        over,
        isEmpty,
        reason: '常规样例不应有任何片段超过目标宽度 ${target.toInt()} 点（容差 $kWidthToleranceDots）',
      );
    });

    testWidgets('长正文 + 多公式：正文折行后无水平溢出', (WidgetTester tester) async {
      final DocumentMeasure m = await measureAtPrintableWidth(
        tester,
        wideText(),
        profile: kPaperangP1Default,
      );
      final double target = kPaperangP1Default.printableDotsWidth.toDouble();

      final List<FormulaFragment> over = m.overflow(target, tolerance: kWidthToleranceDots);
      final List<FormulaFragment> silent = m.silentOverflow(target, tolerance: kWidthToleranceDots);
      debugPrint(
        '[溢出] 压力样例 片段 ${m.fragments.length} 个，超宽 ${over.length} 个，'
        '其中静默 ${silent.length} 个',
      );

      expect(m.widgetSize.width, target);
      expect(over, isEmpty, reason: '正文折行由 softWrap 保证，公式片段也不应超宽');
      expect(silent, isEmpty, reason: '不允许出现「既超宽又没标 degraded」的静默裁切');
    });

    testWidgets('极端超宽样例：走断行策略，每个片段都在目标宽度内', (WidgetTester tester) async {
      final DocumentMeasure m = await measureAtPrintableWidth(
        tester,
        kOversize,
        profile: kPaperangP1Default,
      );
      final double target = kPaperangP1Default.printableDotsWidth.toDouble();
      final List<FormulaFragment> over = m.overflow(target, tolerance: kWidthToleranceDots);

      debugPrint(
        '[溢出] 超宽样例 片段 ${m.fragments.length} 个：'
        '${m.fragments.map((f) => '${f.label}=${f.widthDots.toStringAsFixed(1)}').join(', ')}',
      );

      // 成功标准 6：极端超宽走既定策略（先断行），且每一段都真的放得下。
      expect(m.fragments, isNotEmpty);
      expect(
        m.fragments.every((f) => f.oversize),
        isTrue,
        reason: '整段原始宽度应超过目标宽度，才谈得上走超宽策略',
      );
      expect(
        m.fragments.length,
        greaterThan(1),
        reason: '应断为多段，而不是退化成整体缩放',
      );
      expect(
        m.fragments.every((f) => !f.degraded),
        isTrue,
        reason: '断行后每段都应在目标宽度内，不应走整体缩放兜底',
      );
      expect(over, isEmpty, reason: '断行后的每一段都不得超过目标宽度');
      expect(m.silentOverflow(target, tolerance: kWidthToleranceDots), isEmpty);
    });

    testWidgets('连断行都放不下的样例：必须走整体缩放并显式标记 degraded', (WidgetTester tester) async {
      final DocumentMeasure m = await measureAtPrintableWidth(
        tester,
        kUnbreakableOversize,
        profile: kPaperangP1Default,
      );
      final double target = kPaperangP1Default.printableDotsWidth.toDouble();
      final List<FormulaFragment> silent = m.silentOverflow(target, tolerance: kWidthToleranceDots);

      debugPrint(
        '[溢出] 不可断样例 片段 ${m.fragments.length} 个：'
        '${m.fragments.map((f) => '${f.label}=${f.widthDots.toStringAsFixed(1)} degraded=${f.degraded}').join(', ')}',
      );

      expect(m.widgetSize.width, target, reason: '缩放兜底后渲染根宽度仍须精确');
      // 关键断言：超宽片段必须被显式标记为「已整体缩放」，不允许静默裁切。
      expect(
        silent,
        isEmpty,
        reason: '超过目标宽度的片段必须走 degraded（FittedBox 缩放）路径，不能静默裁切',
      );
      // 并且这个形态本就应该触发兜底——否则说明测试样例选错了。
      expect(
        m.fragments.any((f) => f.widthDots > target + kWidthToleranceDots),
        isTrue,
        reason: '本样例的整段公式应超过目标宽度',
      );
      expect(
        m.fragments.where((f) => f.degraded).length,
        greaterThan(0),
        reason: '超宽片段应被标记为整体缩放兜底',
      );
    });

    testWidgets('嵌套根号不可断行（E4 回归）：走整体缩放兜底，不静默裁切', (WidgetTester tester) async {
      final DocumentMeasure m = await measureAtPrintableWidth(
        tester,
        kNestedSqrtOversize,
        profile: kPaperangP1Default,
      );
      final double target = kPaperangP1Default.printableDotsWidth.toDouble();
      final List<FormulaFragment> silent = m.silentOverflow(target, tolerance: kWidthToleranceDots);

      debugPrint(
        '[溢出] 嵌套根号 片段 ${m.fragments.length} 个：'
        '${m.fragments.map((f) => '${f.label}=${f.widthDots.toStringAsFixed(1)} degraded=${f.degraded}').join(', ')}',
      );

      expect(m.widgetSize.width, target, reason: '渲染根宽度必须精确等于目标宽度');
      expect(m.fragments, isNotEmpty, reason: '嵌套根号应产出可测量的公式片段');
      expect(
        m.fragments.every((f) => f.oversize),
        isTrue,
        reason: '整段自然宽约 427 点，应超过目标宽度 384',
      );
      expect(silent, isEmpty, reason: '不允许「既超宽又没标 degraded」的静默裁切');
      expect(
        m.fragments.every((f) => f.degraded),
        isTrue,
        reason: 'texBreak 在根号结构内无可断点，超宽片段应全部走 FittedBox 整体缩放兜底',
      );
    });

    testWidgets('整体缩放策略（OversizeStrategy.scale）：渲染宽度仍精确、超宽被标记', (WidgetTester tester) async {
      final PaperProfile scaleProfile = PaperProfile(
        id: 'test-scale',
        name: '兜底策略测试档案',
        dpi: 203,
        paperWidthMm: 57,
        printableDotsWidth: kPaperangP1Default.printableDotsWidth,
        minFontPx: 20,
        bodyFontPx: 20,
        mathFontPx: 24,
        lineHeight: 1.3,
        threshold: kStrictThreshold,
        protectStructureLines: true,
        structureRunLength: kStructureRunLength,
        promoteSubDotStrokes: true,
        minLineWidthPx: 1,
        writePhys: true,
        oversizeStrategy: OversizeStrategy.scale,
        columns: 1,
        isCalibrated: false,
      );

      final DocumentMeasure m = await measureAtPrintableWidth(
        tester,
        kOversize,
        profile: scaleProfile,
      );
      final double target = scaleProfile.printableDotsWidth.toDouble();
      final List<FormulaFragment> silent = m.silentOverflow(target, tolerance: kWidthToleranceDots);

      debugPrint(
        '[溢出] scale 策略 片段 ${m.fragments.length} 个：'
        '${m.fragments.map((f) => '${f.label}=${f.widthDots.toStringAsFixed(1)} degraded=${f.degraded}').join(', ')}',
      );

      expect(m.widgetSize.width, target, reason: '缩放兜底后渲染根宽度仍须精确');
      expect(m.fragments.single.oversize, isTrue, reason: '整段公式应超宽');
      expect(silent, isEmpty, reason: '不允许静默裁切');
      expect(m.fragments.single.degraded, isTrue, reason: 'scale 策略下必须标记整体缩放');
    });
  });
}