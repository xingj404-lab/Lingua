# 小型 MLX 翻译模型候选

核查日期：2026-10-08。本次读取模型发布者的模型卡、Hugging Face 仓库 API 和原始配置，并对照项目锁定的 `mlx-swift-lm 3.32.3`、`swift-transformers 1.3.0` 源码。以下是静态兼容性结论；模型质量、速度和内存仍需实际推理验证。

## 可接入的选择

用户提到的混元 1.8B 对应明确存在的 **HY-MT1.5-1.8B**。腾讯提供原始模型，`mlx-community/HY-MT1.5-1.8B-4bit` 是社区转换的 MLX 权重，不能将它描述为腾讯官方 MLX 发布。原始腾讯 BF16 权重约 4.08 GB，而社区 MLX 4-bit 下载约 1.02 GB。[腾讯模型卡](https://huggingface.co/tencent/HY-MT1.5-1.8B)、[MLX 转换模型卡](https://huggingface.co/mlx-community/HY-MT1.5-1.8B-4bit)

建议首批提供混元专用翻译模型，以及 Qwen3 的三个体积档位。Qwen3 是通用指令模型，不应称为专用翻译模型；也不能根据参数量推断某个模型的专业翻译效果更好。

| 仓库 ID | 应用实际选择文件总大小 | 类别 | 接入判断 |
| --- | ---: | --- | --- |
| `mlx-community/HY-MT1.5-1.8B-4bit` | 1,017,529,652 B，约 1.02 GB | 专用翻译，1.8B / 4-bit | 建议作为轻量专业候选，使用混元专属提示 |
| `mlx-community/Qwen3-0.6B-4bit` | 351,383,618 B，约 351 MB | 通用，0.6B / 4-bit | 最小下载档位，适合简单短文本，质量需实测 |
| `mlx-community/Qwen3-1.7B-4bit` | 984,013,244 B，约 984 MB | 通用，1.7B / 4-bit | 中等体积，沿用 Qwen 提示流程 |
| `mlx-community/Qwen3-4B-4bit` | 2,278,969,756 B，约 2.28 GB | 通用，4B / 4-bit | 保留已有选项，不要求用户重新下载 |
| `mlx-community/Hy-MT2-1.8B-4bit` | 1,017,375,718 B，约 1.02 GB | 专用翻译，1.8B / 4-bit | 存在的后续候选，同样支持静态架构适配 |

大小来自仓库树 API 的文件 `size` 求和，使用当前下载器的后缀过滤规则：`json`、`safetensors`、`txt`、`model`、`jinja`。它是下载体积，不是推理内存，也不包括图片/Markdown 等未选择文件。下载时应以当前仓库 API 返回值显示实时总量。

数据来源：[HY 1.5 文件树 API](https://huggingface.co/api/models/mlx-community/HY-MT1.5-1.8B-4bit/tree/main?recursive=true)、[Qwen 0.6B 文件树 API](https://huggingface.co/api/models/mlx-community/Qwen3-0.6B-4bit/tree/main?recursive=true)、[Qwen 1.7B 文件树 API](https://huggingface.co/api/models/mlx-community/Qwen3-1.7B-4bit/tree/main?recursive=true)、[Qwen 4B 文件树 API](https://huggingface.co/api/models/mlx-community/Qwen3-4B-4bit/tree/main?recursive=true)、[HY 2 文件树 API](https://huggingface.co/api/models/mlx-community/Hy-MT2-1.8B-4bit/tree/main?recursive=true)。

## 混元架构与 tokenizer

两个混元 MLX 1.8B 仓库都声明 `model_type: hunyuan_v1_dense`，量化配置为 `bits: 4`、`group_size: 64`、`mode: affine`。关键配置一致：32 层、隐藏维度 2048、16 个注意力头、4 个 KV 头、head dimension 128、词表 120818、QK normalization 开启、词嵌入权重共享、CLA 关闭。[HY 1.5 配置](https://huggingface.co/mlx-community/HY-MT1.5-1.8B-4bit/blob/main/config.json)、[HY 2 配置](https://huggingface.co/mlx-community/Hy-MT2-1.8B-4bit/blob/main/config.json)

本项目依赖的 LLM 工厂已经注册 `hunyuan_v1_dense`，`Hunyuan.swift` 实现上述普通 dense attention、QK normalization、dynamic NTK alpha RoPE 与共享嵌入。无需升级依赖或另写模型层。这个结论适用于所核查的 1.8B 配置，不自动覆盖其他开启 CLA 的混元变体。[锁定版本工厂](https://github.com/ml-explore/mlx-swift-lm/blob/3b339ad6e3b3f44c8121ecff5131c7fd55e075e6/Libraries/MLXLLM/LLMModelFactory.swift)、[锁定版本 Hunyuan 实现](https://github.com/ml-explore/mlx-swift-lm/blob/3b339ad6e3b3f44c8121ecff5131c7fd55e075e6/Libraries/MLXLLM/Models/Hunyuan.swift)

HY 1.5 的 tokenizer 配置本身没有内嵌 `chat_template`，但仓库包含独立 `chat_template.jinja`。Swift Transformers 的本地 Hub 配置读取路径会读取这个文件并合并到 tokenizer 配置，因此当前下载器必须继续保存 `.jinja` 文件。模板支持可选首个 system 消息以及 user/assistant 消息。EOS 是混元占位 token 2（ID 120020），与模型配置一致。[独立模板](https://huggingface.co/mlx-community/HY-MT1.5-1.8B-4bit/blob/main/chat_template.jinja)、[tokenizer 配置](https://huggingface.co/mlx-community/HY-MT1.5-1.8B-4bit/blob/main/tokenizer_config.json)、[Swift 本地 tokenizer 读取源码](https://github.com/huggingface/swift-transformers/blob/1.3.0/Sources/Hub/Hub.swift)

## 翻译提示与采样

腾讯的 HY 1.5 文档推荐单个 user 消息，没有默认 system prompt。中文参与的语言对使用中文翻译指令，其他语言对使用英文翻译指令；术语使用源词与译词映射作为指令前缀。建议为模型族建立翻译提示适配，避免向混元套用 Qwen 的通用 system prompt。领域、风格和段落保留等额外要求需要实际测试，不能声称具有官方保证。[官方提示与推理说明](https://huggingface.co/tencent/HY-MT1.5-1.8B#prompts)

官方推荐采样值是 temperature 0.7、top-p 0.6、top-k 20、repetition penalty 1.05。MLX Swift 的 `GenerateParameters` 支持全部这些值。单纯修改仓库 ID 而保留原 Qwen 的 temperature 0.1，不属于按混元推荐方式接入。[MLX 转换卡的推理参数](https://huggingface.co/mlx-community/HY-MT1.5-1.8B-4bit)、[GenerateParameters 实现](https://github.com/ml-explore/mlx-swift-lm/blob/3b339ad6e3b3f44c8121ecff5131c7fd55e075e6/Libraries/MLXLMCommon/Evaluate.swift)

腾讯 Transformers 示例设置 `add_generation_prompt=False`，而社区 MLX 示例设置 `True`。二者在此 Jinja 模板中有不同尾部 token。现有 ChatSession 可以先沿用 MLX 示例的 `True`，再用真实短句验证结果与停止条件；不要把这一差异遗漏成“完全无改动兼容”。上述架构和 tokenizer 静态核查不等于已跑通模型。

## 仓库修订与范围

本次读取的 `main` 修订：

- HY 1.5：`f6911967a04cfbeb2246a164fe1af5da2cc093ad`
- HY 2：`e5c6fe56c7b3bc77fae5ae92db31f2178f1e6912`
- Qwen 0.6B：`73e3e38d981303bc594367cd910ea6eb48349da8`
- Qwen 1.7B：`3b1b1768f8f8cf8351c712464f906e86c2b8269e`
- Qwen 4B：`4dcb3d101c2a062e5c1d4bb173588c54ea6c4d25`

现有下载器会先解析 revision，然后以固定 revision 下载，适合继续复用。GPTQ、FP8 和 GGUF 的文件不能作为 MLX affine 量化权重直接加载；不要因为名称含 `1.8B` 或 `Int4` 就纳入可用模型菜单。以上调研没有对翻译质量进行横向基准测试，也未给出未经测量的内存或 tokens/s 数字。

## 最终选择：仅保留 Hy-MT2（2026-10-08）

根据用户要求，同体积的混元预设仅保留较强的 Hy-MT2-1.8B-4bit，作为新默认，旧 HY-MT1.5 预设选择迁移到它。两个 MLX 仓库下载量均约 1.02 GB，精确差值只有 153,934 B。Qwen 的三个体积档位仍保留。

官方 Hy-MT2 报告表 3 对相同 1.8B 规模提供直接比较：DomainMTBench 平均 GEMBA 从 88.82 提高到 91.08；WildMTBench GEMBA 从 80.84 提高到 86.04。但 DomainMTBench XCOMET 从 93.52 略降到 93.41，因此不能宣称每个指标全面更好。结合项目的专业文档、术语与风格需求，推荐 Hy-MT2 是基于上述官方基准的产品选择，并非本应用实测量化版胜出。[官方报告表 3](https://arxiv.org/html/2605.22064v1#S3.T3)、[官方 Hy-MT2 提示示例](https://github.com/Tencent-Hunyuan/Hy-MT2#hy-mt2-translation-task-instruction-examples-chinese-english-comparison)

官方量化表 5 的 Q4_K_M 数据属于 GGUF 量化，不能直接作为社区 MLX affine 4-bit 的实测结果。应用已静态验证 MLX 模型配置 / tokenizer 兼容性，提示改用 Hy-MT2 官方中英翻译模板。按用户要求，下载测试已取消，后续完整模型由用户手动下载；本应用暂未实测两个混元量化版的推理质量与速度。
