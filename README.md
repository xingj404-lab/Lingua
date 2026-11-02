<p align="center">
  <img src="Assets/LinguaLogo.png" width="96" alt="Lingua icon">
</p>

# Lingua for Mac

原生 macOS AI 翻译工作台，让文本翻译、截图 OCR 和译文审校在一个窗口完成。使用 SwiftUI、Apple Vision 与 MLX Swift，本地模式在你的 Mac 上运行。

**[从 Mac App Store 下载](https://apps.apple.com/cn/app/id6823065438)** · [提交问题](https://github.com/xingj404-lab/Lingua/issues) · [参与贡献](CONTRIBUTING.md) · [MIT License](LICENSE)

> **English:** Lingua is a native macOS translation workspace with on-device MLX inference, image OCR, editable translations, terminology hints and local history. An optional API mode sends text to a service you explicitly configure and authorize. Requires macOS 14+; local inference targets Apple Silicon. [Download on the Mac App Store](https://apps.apple.com/app/id6823065438).

## 功能

- **本地 AI 翻译**：适配 Hy-MT2 与 Qwen 模型，支持流式译文、取消、模型下载与切换。
- **截图与图片 OCR**：粘贴截图、拖入或导入图片，通过 Apple Vision 提取文字，校对后翻译。
- **双栏编辑**：原文与译文均可编辑，提供领域、风格和术语提示，以及数字与术语遗漏提醒。
- **本地工作区**：最近 100 条翻译记录、搜索、术语表、TXT / Markdown 导入与 TXT 导出。
- **可选 API 服务**：支持 OpenAI 兼容协议，可配置 HTTPS 远程服务或本机 loopback 服务。
- **多语言界面**：简体中文、English、日本語、한국어，支持系统浅色与深色外观。

## 下载与使用

推荐从 **[Mac App Store](https://apps.apple.com/cn/app/id6823065438)** 安装，商店名称为 **Lingua: Offline AI Translator**。

1. 输入文字，或粘贴、拖入图片进行 OCR。
2. 在设置中选择本地模型，设置目标语言及需要的翻译选项。
3. 开始翻译，编辑、复制或导出译文。

商店版内置默认模型，可在本地模式离线翻译。额外模型需要先下载；API 模式需要自行配置服务。

## 隐私与数据

| 使用场景 | 数据去向 |
| --- | --- |
| 图片 OCR、本地模型翻译 | 在 Mac 本机处理 |
| 翻译历史、术语表 | 保存在本机，无云同步 |
| 下载额外模型 | 连接用户选择的 Hugging Face、HF-Mirror 或自定义 HTTPS 下载源 |
| 可选 API 翻译 | 经用户授权后，原文及相关术语发送到所配置的服务 |

应用不会在本地推理失败时自动改用远程 API。API 发送授权按服务地址保存，可撤销；远程服务的数据保留规则由服务提供方决定。

API Key 默认仅供当前会话使用；主动保存后写入应用数据目录中的本地明文 JSON 文件，目录权限为 `0700`、文件权限为 `0600`，不使用 macOS 钥匙串。请勿将凭据或真实翻译记录提交到 issue。

详细说明见应用内隐私政策及[隐私政策源文件](Sources/LinguaMac/Resources/Legal/privacy-zh-Hans.md)。

## 从源码构建

### 环境要求

- Apple Silicon Mac、macOS 14 或更高版本。
- 支持 Swift 6.2 或更高版本的完整 Xcode 工具链。
- Python 3：用于打包辅助脚本和部分测试，不是应用运行依赖。
- 首次解析 Swift Package 需要联网；依赖版本已通过 `Package.resolved` 固定。

```sh
git clone https://github.com/xingj404-lab/Lingua.git
cd Lingua
cp Distribution/Config/Local.xcconfig.example Distribution/Config/Local.xcconfig
open Lingua.xcodeproj
```

在 Xcode 中选择 **Lingua** scheme 和 **My Mac**，设置自己的开发者团队。

**模型权重不包含在源码仓库中。** 当前完整应用构建会打包 Hy-MT2 默认模型，需要先准备包含 `.lingua-manifest.json` 和完整模型文件的已验证快照，再通过 `LINGUA_DEFAULT_MODEL_DIR` 指定目录。打包脚本只读取本地文件，不会自动下载权重。

例如在准备好模型和签名配置后归档：

```sh
LINGUA_DEFAULT_MODEL_DIR="/absolute/path/to/verified-model-snapshot" ./scripts/archive-app.sh
```

完整 MLX 构建需要 Xcode / `xcodebuild` 编译 Metal shaders，不能只用 `swift build`。模型准备、沙盒、签名及归档说明见[发布与构建指南](docs/release/README.md)。该指南保留了首次发布准备记录，当前商店状态以 App Store 为准。

### 检查与测试

```sh
./scripts/check.sh
```

此脚本编译不含 MLX 后端的检查包并运行测试，不下载模型。覆盖翻译核心逻辑、OCR、API 授权与请求、本地持久化、模型下载及缓存等；HTTP 测试使用临时本机服务，不需要真实 API Key。它不代替完整 MLX 构建或实际模型翻译质量验证。

## 项目结构

| 路径 | 内容 |
| --- | --- |
| `Sources/LinguaMac/` | SwiftUI 应用、推理适配、OCR 和本地工作区 |
| `Sources/TranslationCore/` | 翻译逻辑、模型目录及界面本地化资源 |
| `Tests/TranslationCoreTests/` | 自动化测试 |
| `Distribution/` | App Store 工程配置、资源和隐私清单 |
| `Vendor/mlx-swift/` | 随仓库维护的 MLX Swift 依赖及原始许可 |
| `scripts/` | 检查、模型打包、许可收集和归档脚本 |
| `website/` | 支持与隐私网页生成工具 |
| `docs/` | 构建说明、模型调研及开发记录 |

## 已知限制

- 本地推理面向 Apple Silicon，Intel Mac 未验证。
- 模型可能误译；术语提示及数字检查不保证准确，重要内容需要人工审校。
- 长文本采用分块处理，块之间不传递全文上下文。
- 复杂多栏或表格图片的 OCR 阅读顺序可能需要人工整理，不支持原图排版重建。
- 当前不包含语音或对话翻译；本地模型仅支持模型库中已适配的型号。
- 本项目目前独立管理模型，尚未接入螺壳的共享模型服务。

## 贡献与支持

欢迎通过 [GitHub Issues](https://github.com/xingj404-lab/Lingua/issues) 提交问题和建议，或提交 Pull Request。请先阅读[贡献指南](CONTRIBUTING.md)与[行为准则](CODE_OF_CONDUCT.md)。安全漏洞请依照[安全政策](SECURITY.md)私下报告。

历史实现细节见[开发记录](docs/development-notes.md)，模型选型见[模型调研](docs/model-research.md)。

## 许可证与致谢

Lingua 的原创代码采用 **[MIT License](LICENSE)**，Copyright © 2026 xingj404-lab。

第三方依赖、模型权重、分词器和相关资源仍适用各自许可证，根目录 MIT 协议不替代这些许可。特别是 Hy-MT2 模型适用其自身许可，并非由本仓库 MIT 协议授权。详情见[第三方许可说明](THIRD_PARTY_NOTICES.md)。

感谢 MLX Swift、MLX Swift LM、Hugging Face Swift 工具链和 Hy-MT2 / Qwen 模型社区。
