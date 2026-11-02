# 第三方代码与模型许可

根目录的 [MIT License](LICENSE) 适用于 Lingua 的原创代码。第三方代码、模型、分词器及其他资源保留其自身版权和许可，不因放入或用于本项目而改为 MIT。

## 代码依赖

- `Vendor/mlx-swift/`：保留上游 [MLX Swift LICENSE](Vendor/mlx-swift/LICENSE)，其 C/C++ 依赖还包含各自许可证，见相应子目录。
- MLX Swift LM、Swift Hugging Face、Swift Transformers 及传递依赖：来源与版本见 `Package.swift`、`Package.resolved` 及 Xcode 的解析文件；分发时应保留实际解析版本的许可与通知。

`scripts/collect-licenses.py` 从已解析的依赖 checkout 收集许可，并加入本地 MLX 和 Hy-MT2 通知。生成目录不会提交到版本库，不能仅依据根目录 LICENSE 判断所有分发资源的许可。

## 模型

默认 Hy-MT2 模型的许可及归属文件保存在：

- [LICENSE.txt](scripts/model-licenses/Hy-MT2/LICENSE.txt)
- [ATTRIBUTION.txt](scripts/model-licenses/Hy-MT2/ATTRIBUTION.txt)
- [模型说明与来源](scripts/model-licenses/Hy-MT2/MODEL_CARD.md)

模型权重不随源码仓库分发。下载、使用或重新分发 Hy-MT2、Qwen 或其他模型时，请查阅所选模型及固定 revision 的实际许可、模型卡与使用条件。Lingua 的 MIT 协议不授予模型提供方未授予的权利。
