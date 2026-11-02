# macOS 专业本地翻译：模型与运行时调研

调研日期：2026-10-07。本文基于模型发布方、Apple、模型运行时维护者的官方文档与代码；没有在本机下载权重或测量翻译质量、速度、峰值内存。建议和内存规划不是实测结果。

## 当前实现与本报告的关系

当前原型已采用应用内 MLX Swift（固定 3.32.3）+ Qwen3 4B 通用指令模型、Vision OCR 和本机兼容服务接口。Apple Translation、TranslateGemma 专属模板、Core ML 推理都是下文的候选路线，尚未在当前原型中接入。本报告的建议不代表这些后端已实现。

## 推荐结论

第一版采用 **Apple Translation + Vision OCR**，得到真正能用的离线文本、图片翻译；独立定义翻译引擎接口，第二阶段接入 **MLX Swift + TranslateGemma 4B / 12B**。同时用 **Qwen3.5 4B / 9B** 做术语约束、风格和译后编辑的对照实验。Core ML 保留为后续专项优化路线，先证明模型值得上线，再支付转换与维护成本。

“专业”首先体现为原文/译文对应、术语库、数字与占位符检查、版本记录、可编辑 OCR 和可靠导出。更大参数量、公开基准领先、Apple GPU 加速都不能单独证明专业领域的准确率。

## Offgrid 的身份仍需核实

仅凭“Offgrid iOS 翻译软件”未能唯一定位到对应产品的官方页面或开源项目。搜索出现多个同名项目，例如 [Off Grid AI App Store 页面](https://apps.apple.com/us/app/off-grid-ai-private-local-ai/id6759299882)，其页面描述为本地 AI 聊天；[Offgrid Studio 的 OffgridScribe](https://offgridstudio.app/offgridscribe) 是转录产品。它们不足以证明就是用户提到的口语翻译应用。

因此不把任何一个同名项目的模型、量化格式或推理框架写成 Offgrid 的已知实现。获取原版 App Store 链接或源码后，才能做精确对比。目前可以落实用户希望借鉴的原则：本地小模型、显式下载、模型生命周期管理、离线运行；不需要复制语音或对话流程。

## 候选模型

| 选项 | 已核实事实 | 产品建议 |
| --- | --- | --- |
| TranslateGemma 4B / 12B / 27B | Google 基于 Gemma 3 发布的翻译专用模型，覆盖 55 种语言，也保留图像内文字翻译能力 | 4B 为小模型评测首选；12B 为高质量档候选；27B 为高内存设备选项，不作默认下载 |
| Qwen3.5 4B / 9B | 官方 9B 模型为通用多模态生成模型，Apache 2.0 | 对照评测译后编辑、领域上下文与术语遵循；不能宣称翻译优于 TranslateGemma |
| Qwen3 8B | 官方模型为 Apache 2.0，属于通用生成模型 | 成熟架构回退候选；不要因较旧而直接淘汰，也不要当成当前最新 Qwen |
| NLLB-200 distilled 600M | CC-BY-NC 4.0；官方定位研究用途，明确排除生产部署、专业领域和文档翻译；训练输入未超过 512 tokens | 不作为商业专业产品默认模型；研究实验可以保留 |
| Marian / OPUS-MT | 语对专用 encoder-decoder 模型，例如官方 opus-mt-en-zh 卡片标 Apache 2.0，需要 SentencePiece 和目标语言标记 | 低内存、特定语对的实验路线；逐个检查 checkpoint 授权，不能把整个 OPUS 系列当成同一种许可 |

来源：[Google 发布说明](https://blog.google/innovation-and-ai/technology/developers-tools/translategemma/)、[Qwen3.5 4B 官方模型卡](https://huggingface.co/Qwen/Qwen3.5-4B)、[Qwen3.5 9B 官方模型卡](https://huggingface.co/Qwen/Qwen3.5-9B)、[Qwen3 8B 官方模型卡](https://huggingface.co/Qwen/Qwen3-8B)、[Meta NLLB 官方模型卡](https://huggingface.co/facebook/nllb-200-distilled-600M)、[Helsinki-NLP 英译中模型卡](https://huggingface.co/Helsinki-NLP/opus-mt-en-zh)。

Google 宣布 TranslateGemma 12B 在其评测中优于 Gemma 3 27B 基线。这个结果是与该基线、该评测的比较，不能推导它优于商业翻译引擎、Offgrid 或特定法律/工程语料。[Google 发布说明](https://blog.google/innovation-and-ai/technology/developers-tools/translategemma/)

### TranslateGemma 接入的关键限制

官方模板接受 user / assistant；user 内容为单一 text 或 image 条目，必须带 `source_lang_code`、`target_lang_code`。文字项的 `text` 应只包含待译原文。不能直接沿用普通聊天模型的 system prompt。官方说明其他提示方式（如自动译后编辑）不在正式支持范围内，需要手工构造并验证。[官方模型卡与模板示例](https://huggingface.co/google/translategemma-4b-it)

实施时先做严格标准模板的纯翻译。把术语库当作校验、候选提示和人工修订工具；尚未证实模型支持强制术语时，不能把 UI 的“术语已锁定”当成保证。Qwen 的指令能力可作为另一种方案，但需要独立评测，并防止源文中的指令干扰翻译。

TranslateGemma 适用 Gemma 使用条款而非 Apache 2.0。分发权重/衍生模型需要包含条款、使用限制及 NOTICE，修改文件需带修改标记。可以做商业产品路线，但发布流程需要落实具体条款；社区量化不解除原模型的限制。[Gemma Terms of Use](https://ai.google.dev/gemma/terms)

## MLX Swift：Mac 优先路线

MLX 面向 Apple silicon，提供 Swift API。[MLX Swift 官方仓库](https://github.com/ml-explore/mlx-swift)

可复用语言模型库已经从 `mlx-swift-examples` 移到 `mlx-swift-lm`，示例仓库继续提供 LLMBasic / LLMEval 等应用参考。新实现应直接依赖语言模型库，而不是将示例聊天应用作为产品架构。[官方示例仓库](https://github.com/ml-explore/mlx-swift-examples)

当前 `mlx-swift-lm` 的 3.x 分离 tokenizer / downloader 接口；README 展示 `MLXLLM`、`MLXLMCommon`、`MLXHuggingFace` 以及 Hugging Face Swift 包。当前 main 的 Package.swift 使用 Swift tools 6.2，声明 macOS 14。开发应固定经过构建验证的 release/tag，并保存 `Package.resolved`；不要混用 2.x 与 3.x 样例。当前主线的 FoundationModels 桥接依赖更新 SDK，基础 MLX 接入不需要该桥接。[库 README](https://github.com/ml-explore/mlx-swift-lm)、[Package.swift](https://github.com/ml-explore/mlx-swift-lm/blob/main/Package.swift)

官方模型工厂当前注册 `gemma3` / `gemma3_text`、`qwen3_5` / `qwen3_5_text`。这证明相关架构有实现，不等于每个 TranslateGemma 或 Qwen 量化 checkpoint 的配置、tokenizer、模板已在本应用验证。[模型工厂源码](https://raw.githubusercontent.com/ml-explore/mlx-swift-lm/main/Libraries/MLXLLM/LLMModelFactory.swift)

建议原生流程：

1. 模型 manifest 记录上游名称、固定 revision、权重格式、hash、tokenizer、模板版本、许可、支持语言和预估资源。
2. 用户选择下载；下载到临时目录，可暂停/恢复；校验后原子移动到 Application Support。
3. 一个 actor 管理加载、串行推理、取消、内存压力卸载。主线程只更新界面。
4. 段落分块保留编号；每块独立完成并记录状态。限制上下文与输出长度，截断不能算成功。
5. 根据模型模板生成输入；结果只解码新生成 token，排除提示词、控制 token 和思考内容。

社区 MLX 量化可以用于原型，但发布时应从官方权重生成并固定转换工具版本，或审核所选发布者的权重、配置与来源。本文没有把社区模型页面作为质量或安全性的第一方证据。

## Core ML：可行，但不是一键替换 MLX

Core ML 的 stateful `mlprogram` 自 iOS 18 / macOS 15 起可保持状态，适合 KV cache；Apple 文档以 GPU 上的 Transformer 为例演示转换与优化。状态管理、PyTorch tracing、输入形状与数值验证仍需要完成。**Core ML 不保证所有层跑 Neural Engine，也不保证比 MLX 更快。**[Apple stateful models 文档](https://apple.github.io/coremltools/docs-guides/source/stateful-models.html)

对于 TranslateGemma / Qwen，先做一个固定上下文长度、batch = 1 的 prototype：分离 prefill / decode，适配 attention 和 cache，转换并量化；在相同 tokenizer、模板和源文上比较 PyTorch → MLX → Core ML 的输出差异，再测冷启动、首 token、总时间、能耗、峰值内存。未找到本次候选模型发布方提供的可直接用于本产品的完整 Core ML 包，因此将其标记为后续工程任务。

Marian 是 encoder-decoder，除了 encoder 还要维护 decoder、cross-attention cache、SentencePiece 和 beam search。转为 Core ML 技术上可实验，但缺少现成 Swift 翻译层时工程量明显高于 Apple Translation。CTranslate2 的官方转换器支持 Marian / OPUS-MT，可作为 CPU 路线；官方硬件页面列 ARM64 CPU、NVIDIA GPU，不能把它误写成 macOS Metal 加速方案。[CTranslate2 转换文档](https://github.com/OpenNMT/CTranslate2/blob/master/docs/conversion.md)、[硬件支持](https://opennmt.net/CTranslate2/hardware_support.html)、[OPUS-MT 示例](https://github.com/OpenNMT/CTranslate2/blob/master/docs/guides/opus_mt.md)

## Apple Translation 与图片翻译

Apple `TranslationSession` 在设备上处理翻译。用户尚未安装语言包时框架管理授权下载。API 可单条/批量翻译；不要把“本地处理”写成“绝无任何遥测”，官方明确允许收集不含原文/译文内容的 API 使用和性能指标。[Apple TranslationSession](https://developer.apple.com/documentation/translation/translationsession)、[WWDC Translation API](https://developer.apple.com/videos/play/wwdc2024/10117/)

运行时查询 `LanguageAvailability` 的 `.installed` / `.supported` / `.unsupported`，不要写死所有语言对可用。新版本文档包含更新 API，部署 macOS 15 时需逐个检查 availability。[Apple LanguageAvailability](https://developer.apple.com/documentation/translation/languageavailability)

图片流程建议 **Vision OCR → 用户校对原文 → 按阅读顺序分块 → 翻译**。这样识别错误可追踪，术语与数字检查能复用。保留 OCR bounding box 和置信度，在图片旁边显示原文与译文，不在第一版承诺自动重排所有复杂版式。[Apple Vision 文本识别](https://developer.apple.com/documentation/vision/recognizing-text-in-images)

## 内存规划：理论下限与建议必须区分

4-bit 的理论权重存储为 `参数量 × 0.5 byte`：4B ≈ 2 GB、9B ≈ 4.5 GB、12B ≈ 6 GB、27B ≈ 13.5 GB（十进制）。这是数学估算，**不是实际下载大小或运行内存**。量化 scale、未量化 tensor、视觉塔、tokenizer、KV cache、临时激活、Metal 缓冲和系统应用会增加开销。

| 统一内存 | 初始产品建议，尚待实测 |
| --- | --- |
| 8 GB | Apple Translation；可实验 4B 4-bit，但不默认承诺大文本性能 |
| 16 GB | TranslateGemma 4B；9B / 12B 短块实验，避免模型并驻 |
| 24–32 GB | 12B 4-bit 为高质量候选；27B 仍需测量并预留系统空间 |
| 48–64 GB 及以上 | 27B 4-bit 候选；更高精度是否改善译文需评测 |

设置页显示设备统一内存、下载体积和“建议配置”；运行时以内存压力为准。文档、OCR 和翻译都使用有界队列；不把整本文档和两套大模型同时装入内存。

## 上线前评测与实现顺序

这些是本项目建议，不是已取得结果：

1. 先实现 macOS 15+ 原生文本、图片导入、Vision OCR、Apple Translation、双栏审校、导出和取消。
2. 做 MLX 工程 spike：先验证 4B 标准模板加载和生成，再验证 12B；确定 release、checkpoint revision 与最大块长。
3. 建立中英双向为主的约 200 段测试集，含工程规格、软件文档、商务邮件、学术文字、数字/单位、表格、占位符和 OCR 噪声。记录人工参考与术语表。
4. 对比 Apple Translation、TranslateGemma 4B / 12B、Qwen3.5 4B / 9B；人工盲评漏译、错译、增译、术语、语气、数字，自动检查占位符和段落对应。
5. 在 8 / 16 / 24 或 32 GB Apple silicon Mac 上记录模型 revision、量化版本、冷/热启动、首 token、完整段落时间、峰值内存与取消延迟。没有这些数据就不宣传“比 Offgrid 更强”或“专业准确率”。
6. 只在 MLX 测得明确能耗/延迟问题且模型质量已达标时，对最有价值的一个 checkpoint 做 Core ML 转换。首版不用同时维护两套大模型后端。

待决项：Offgrid 精确链接、首要语对与专业领域、最低设备内存、是否需要 Intel Mac、商业分发方式。它们影响最终默认模型，但不阻碍先做文本/图片本地翻译和可替换引擎架构。
