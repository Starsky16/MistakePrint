# MistakePrint

把**含 LaTeX 的错题题干**（纯文本）渲染成**宽度精确匹配热敏打印机点阵**的 1-bit 位图，再由用户手动分享给「作业帮喵喵机」官方 App 打印。

- 面向场景：作业帮等 App 的错题打印，题干里混有中文、数学公式与教材符号。
- 目标机型：**喵喵机 P1**（203 dpi，名义有效打印宽度 384 点，待实机标定）。
- 平台：Android 手机端，Flutter + Material Design 3。

## 非目标（明确不做，避免范围漂移）

- **不做蓝牙 / BLE 通信**，不生成 ESC/POS、CPCL、TSPL 等打印机指令，不直接驱动打印机。
- 不做设备配对、不接入喵喵机 SDK、不自动化其官方 App。
- **不处理图片输入**（无图题、无扫描件）。
- 不做 OCR，不做题库管理，不做错题本业务。
- 化学式（mhchem `\ce{}`）为后续增量，不阻塞首期。

终点是「输出图片并交给用户分享」，打印由官方 App 完成。

## 构建与检查

```powershell
$env:PATH = "C:\Users\admin\library\flutter\bin;$env:PATH"
flutter pub get
flutter analyze
flutter build apk --debug
```

## 第三方资源

| 资源 | 用途 | 许可证 |
|---|---|---|
| [flutter_math_fork](https://pub.dev/packages/flutter_math_fork) 0.7.4 | 公式排版（自带 KaTeX 字体） | Apache-2.0 |
| [image](https://pub.dev/packages/image) 4.9.1 | 二值化与 1-bit PNG 编码 | MIT |
| [share_plus](https://pub.dev/packages/share_plus) 13.1.0 | 系统分享面板 | BSD-3-Clause |
| [Noto Sans SC](https://github.com/google/fonts/tree/main/ofl/notosanssc) | 正文中文 | OFL-1.1 |
| [STIX Two Math](https://github.com/google/fonts/tree/main/ofl/stixtwomath) | 数学符号兜底 | OFL-1.1 |

`assets/fonts/` 下的字体各自附有原始 `OFL.txt`。

## AI 辅助声明

本项目在开发过程中使用了 AI 辅助生成。

## 许可证

[MIT](LICENSE)