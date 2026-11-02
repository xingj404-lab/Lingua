# Lingua Mac App Store 发布准备

首版计划：免费，1.0.0（1）；macOS 14+、Apple Silicon（arm64）。本文件记录工程准备状态，不表示已经通过 Apple 审核。

## 现在可以使用

- `Lingua.xcodeproj`：原生 macOS App + TranslationCore framework，支持 Xcode Run / Archive。
- `Distribution/Lingua.entitlements`：App Sandbox、出站网络、用户选择文件的读写。没有完全磁盘访问、辅助功能、录屏或服务器监听权限。
- `Distribution/Resources/PrivacyInfo.xcprivacy`：应用偏好、应用内计时、沙盒内文件及用户选择文件的元数据用途。
- 中、英、日、韩应用内隐私政策、开源许可入口、API 地址级发送授权与撤销、带确认的清空历史。
- 应用本地凭据文件读写在后台进行，8 秒后界面解除等待；迟到的旧服务结果不会覆盖当前服务或用户输入。
- 模型仍内置 Hy-MT2-1.8B-4bit，保持既有权重与固定 revision；构建时不下载模型。
- `scripts/validate-store-bundle.py` 只做离线包装检查，不代替 Organizer 的 Validate App。

## 在 Xcode 中运行

1. 打开根目录的 `Lingua.xcodeproj`，选择 **Lingua** scheme 和 **My Mac**。
2. 在 Signing & Capabilities 选择你的开发者团队。当前本机 `Distribution/Config/Local.xcconfig` 使用已安装开发证书对应的团队；该文件不应提交到版本库。其他电脑可从 `.example` 复制填写。
3. 初次解析已固定版本的 Swift Package 需要联网。如 Xcode 询问信任 MLX 包宏，核对包来源后按 Xcode 提示处理。
4. Run。新工程产物位于 Xcode DerivedData；旧 `build/Lingua.app` 是之前的非沙盒开发包，不能把两者混淆。

模型来源默认是已验证的本机缓存。换电脑构建时，设置 `LINGUA_DEFAULT_MODEL_DIR` 为包含 `.lingua-manifest.json` 及完整模型文件的已验证快照目录；这是开发者打包参数，不是面向用户的模型导入功能。

本地命令：

```sh
./scripts/check.sh
./scripts/archive-app.sh
/usr/bin/python3 scripts/validate-store-bundle.py build/Lingua.xcarchive/Products/Applications/Lingua.app
```

`archive-app.sh` 不上传、不创建商店记录、不自动接受协议。当前 Archive 使用 Apple Development 签名，后续在 Organizer 中选择正确商店分发方式，由 Xcode 配置或使用 Apple Distribution 证书与所需描述文件。

## 版本库与可复现构建

提交 `Lingua.xcodeproj`、共享 scheme、Xcode 工作区内的 `Package.resolved`、Distribution 配置、资源、脚本与源代码。不要提交私有证书、私钥、本机团队配置、1 GB 模型生成目录和 DerivedData。

项目文件已生成，可直接用 Xcode，不要求安装 Ruby gem。需要重新生成项目文件时，使用已安装的 `xcodeproj` gem 执行 `ruby scripts/create-xcode-project.rb`。新增 Swift 文件后也可直接在 Xcode 的正确 target 添加。图标/基础 plist 可通过 `/usr/bin/python3 scripts/prepare-distribution.py` 重新生成；修改 Info.plist 前注意该脚本会覆盖生成字段。

## 沙盒与旧版数据

商店版本的 Application Support 会指向应用沙盒，和旧非沙盒开发版的 `~/Library/Application Support/LinguaMac` 不是同一个位置。旧文件没有删除，内置模型也不依赖旧缓存。

当前尚未实现旧版历史、术语、设置和额外下载模型的一次性迁移。不要为迁移添加完全磁盘访问权限或绕过沙盒。在正式替换已有用户版本前，需要决定通过用户明确选择旧数据文件/目录的方式迁移；全新用户无需此步骤。不要把沙盒下看不到 Qwen 缓存误认为旧缓存已被删除。

## 提交前由发布者补齐

- 开发者公开名称、版权主体、支持邮箱、Support URL。
- 将应用内隐私政策正文发布到稳定 HTTPS 网址，并补全联系信息；在 App Store Connect 填写 Privacy Policy URL。
- 确认 Bundle ID `app.lingua.mac` 是否是最终 ID，并在账号中注册。正式发布后不要随意更换。
- App Store Connect 建立 macOS App，免费定价；填写四语言名称、介绍、关键词、截图、分类、年龄分级、版权、发行地区。
- 需要提供实际 App 截图；尚未制作或上传商店截图。
- 隐私标签必须结合最终版本、API 服务商的保留政策与实际数据流填写。不要把本地模式的“不上传”直接套用到 API 模式。manifest 没有声明开发者自建收集服务；不代表所有自定义 API 都不保留数据。
- `ITSAppUsesNonExemptEncryption = NO` 按当前仅使用系统/标准网络加密及完整性校验准备；提交者须确认出口合规回答与最终功能一致。
- 确认模型、量化转换及所有依赖的许可与署名，当前打包保留了实际依赖的许可证文本和 Hy-MT2 归属文件。
- 确认正式构建使用 Apple 当时允许上传的 Xcode/SDK 版本，不能仅凭本机能够编译判断可上传。

## 用户手动验收清单

之后不再由助手自动启动、重启或操作 App 验收；编译和自动化测试结果单独报告。

- 全新用户、断网启动：内置模型可完成翻译，不要求下载或 API Key。
- 连续不同文本、重启、语言切换：模型只初始化一次，翻译和方向正确。
- 截图粘贴、图片导入、原图缩放、拖拽、取消导入、文本导出。
- 每个 API 地址首次发送显示页内同意提示（无模态弹窗）；取消不清空文字；换地址重新同意；撤销后重新同意。未同意不得发起翻译请求。
- 本地凭据文件不可读/等待：窗口可用，本地翻译仍可用；切换服务和输入新 Key 不被旧读取覆盖。
- 服务 401、网络超时、取消、模型下载失败重试。
- 四种界面语言、深浅色、键盘导航、VoiceOver 和长文本布局。
- 在 macOS 14 的实际 Apple Silicon 设备或环境测试最低系统；至少再测试一台资源较少的 Mac。
- 通过 TestFlight 分发后，验证安装、更新、离线模型、资源签名与崩溃情况。当前尚未执行 TestFlight 验收。

## 官方参考

- https://developer.apple.com/app-store/review/guidelines/
- https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox
- https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api
- https://developer.apple.com/app-store/submitting/
