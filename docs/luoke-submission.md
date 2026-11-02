# 新项目：Lingua — 本地 AI 文本与 OCR 翻译工作台

**它做什么、给谁用**

大家好，想申请将已上架 Mac App Store 的 Lingua 接入螺壳生态，请团队评估是否适合立项。它是面向外文阅读、截图翻译和译文审校的原生 macOS 应用，支持文本翻译、Apple Vision OCR、原文译文双栏编辑、术语提示、本地历史和文本导入导出。

**怎么跑**

本地推理面向 Apple Silicon Mac、macOS 14+，使用 SwiftUI、Apple Vision 和 MLX Swift，已适配 Hy-MT2 和 Qwen。目前自行管理模型，尚未接入 luoke-core。希望讨论通过 luoke-core 复用全机共享模型及资源管理能力的接入方式，目前没有接入螺壳记忆。

**用户的数据会去哪**

本地模式的 OCR 和翻译在本机完成，历史及术语表保存在本机，没有云同步；下载额外模型时连接用户选择的下载源。

当前独立发行版另有可选远程 OpenAI 兼容 API 模式：用户确认授权后，原文及相关术语会发往用户配置的服务，不会自动从本地模式切换到远程。因此现有发行版并非所有模式均满足螺壳纯本地要求。希望讨论提供仅使用螺壳本机推理的接入版本，以及是否应在该版本移除远程 API 入口。

**已经有的代码或演示**

- 源码仓库：https://github.com/xingj404-lab/Lingua （作者将自行处理公开设置及开源许可）
- Mac App Store：https://apps.apple.com/cn/app/id6823065438
- 商店名称：Lingua: Offline AI Translator

请问此方向是否适合加入螺壳？已有独立应用是否必须先公开源码、是否有推荐的许可证及共享模型接入规范？谢谢！
