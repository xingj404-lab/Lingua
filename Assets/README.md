# Lingua Logo

原创双页文档与转译箭头标志。深灰表示原文，粉色表示译文；白色圆角底板用于 macOS 应用图标。

- `LinguaLogo.svg`：可编辑矢量预览。
- `LinguaLogo.png`：1024 × 1024 透明背景应用图标。
- `../Sources/LinguaMac/Resources/AppIcon.png`：应用内共享资源。

生成源为 `scripts/generate-icon.swift`；修改图形、配色后运行 `swift scripts/generate-icon.swift`，再运行 `scripts/build-app.sh`。打包脚本生成 16–1024 像素 iconset 和 `AppIcon.icns`。侧栏与 Dock 使用同一个原图。
