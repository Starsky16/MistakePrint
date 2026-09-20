import 'package:flutter/material.dart';

/// 正文字体族名，与 pubspec.yaml 的声明一致。
const String kBodyFont = 'NotoSansSC';

/// 数学符号兜底字体族名。
const String kSymbolFont = 'STIXTwoMath';

/// 默认行高倍数（热敏纸上略放宽，便于目视分辨笔画）。
const double kBodyLineHeight = 1.3;

/// 打印墨色（纯黑，二值化的目标）。
const Color kInk = Color(0xFF000000);

/// 正文样式：字号与行高都显式给出，不依赖系统主题，保证跨机型可复现。
TextStyle bodyStyle(double fontSize, {Color color = kInk, double? height}) =>
    TextStyle(
      fontFamily: kBodyFont,
      fontSize: fontSize,
      color: color,
      height: height ?? kBodyLineHeight,
    );

/// 数学符号样式（STIX Two Math 通道）。
TextStyle symbolStyle(double fontSize, {Color color = kInk, double? height}) =>
    TextStyle(
      fontFamily: kSymbolFont,
      fontSize: fontSize,
      color: color,
      height: height ?? kBodyLineHeight,
    );