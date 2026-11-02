# 本地模型空闲后首条翻译延迟：诊断与修复（2026-10-23）

## 结论

启动加载与预热确实已完成，模型也没有重复加载。异常发生在 GPU 空闲恢复后的前向计算准备阶段。MLX 上游已记录 macOS 空闲时撤销 Metal 驻留的问题，并提供驻留续期修复：

- https://github.com/ml-explore/mlx/issues/4609
- https://github.com/ml-explore/mlx/pull/4633

本项目固定的 mlx-swift 0.32.3 尚不含该核心修复。仅保持 Swift 模型引用、一次性设置驻留预算或保持 App 用户活动，都未消除本机复现的延迟；不能把这些单独称为修复。

## 实测证据

同一台 Mac、相同 73 字符中文原文、中译英、输入 59 token。首条和重复请求保持同样文本与选项，正文输出因采样可能略有变化。

| 对照 | 空闲时长 | 首字等待：首条／重复 | 预填充：首条／重复 |
| --- | ---: | ---: | ---: |
| 旧策略，用户复测 | 453.6 秒 | 6.676／0.904 秒 | 6.598／0.828 秒 |
| 旧进程，同文再次空闲 | 513.5 秒 | 6.696／0.691 秒 | 6.575／0.658 秒 |
| 驻留续期修复 | 1113.3 秒 | 0.774／0.457 秒 | 0.598／0.438 秒 |

修复后的界面总耗时约 5.8／3.3 秒。正文生成分别约 4.68／2.77 秒，说明生成速度仍会波动；本轮消除的是已复现的数秒首字等待，不保证所有请求总耗时一致。全过程模型实际加载、启动预热均为 1 次。

原始数值事件保存在 `docs/performance/idle-before-residency.jsonl` 和 `idle-after-residency-refresh.jsonl`。另保留了驻留预算不足的失败对照，避免把中间尝试误认成修复。

## 实现

- `Vendor/mlx-swift`：基于 0.32.3（19601207e9a0de51e03ee6ec0c3c5f3784275075），仅回移上游 #4633 的 `resident.cpp`／`resident.h` 改动；原许可证和精确补丁均随源码保留。
- 根 Package.swift、Xcode 项目及项目生成脚本显式使用这个本地 MLX 产品，避免仅修改可被清除的 SourcePackages 缓存。当前 SwiftPM 会对同名本地覆盖给出警告，构建正常；兼容的正式 Swift 发行版包含修复后应撤掉此副本。
- 入口在任何 Metal 初始化之前设置进程内 `MLX_METAL_RESIDENCY_REFRESH_INTERVAL_MS=1000`。显式传入的环境变量保留，不修改系统 sysctl 或用户 shell 配置。
- 保持有限的当前模型 wired-memory ticket，预算计入活跃分配、缓存和 256 MiB 余量，且不超过设备推荐工作集。续期线程每秒只重新请求 Metal 驻留，不提交 GPU 推理任务。实际运行进程已采样确认该线程存在。
- 模型就绪期间持有允许系统休眠的用户活动声明，避免续期线程被 App Nap 调度影响；卸载／更换模型时释放活动与 ticket。
- 预热和翻译统一走独立单轮生成路径，保留原消息模板、采样设置和独立 KV cache；取消／失败时取消并等待生成 task。此路径调整本身不是此次延迟的根因修复。

## 验证与复现

43 项自动化测试、原生模型翻译／生成中取消后继续翻译、卸载资源释放、完整 arm64 Release 构建及签名检查通过。构建日志确认 `resident.cpp` 来自 Vendor，最终二进制含续期配置，运行进程有 ResidencySets 续期线程。

```sh
# 修复前证据：预期退出码 1
python3 scripts/check-inference-latency.py docs/performance/idle-before-residency.jsonl
# 修复后证据：预期退出码 0
python3 scripts/check-inference-latency.py docs/performance/idle-after-residency-refresh.jsonl

# 真实离线空闲基准，不创建窗口、不写翻译记录、不下载模型
build/DerivedData/Build/Products/Release/Lingua.app/Contents/MacOS/Lingua --benchmark-local --benchmark-idle 480
# 续期关闭对照（需新进程）
MLX_METAL_RESIDENCY_REFRESH_INTERVAL_MS=0 build/DerivedData/Build/Products/Release/Lingua.app/Contents/MacOS/Lingua --benchmark-local --benchmark-idle 480
# 生成中取消与后续请求
build/DerivedData/Build/Products/Release/Lingua.app/Contents/MacOS/Lingua --benchmark-local --benchmark-cancel
```

脚本只接受有明确长空闲、同输入 token 数、同加载次数、重复间隔不超过一分钟且重复请求首字等待不超过两秒的对照。调用者须确保实际文本／选项相同。首条同时超过两秒及重复请求三倍则 FAIL；无有效对照退出码为 2。

macOS unified logging 的 subsystem 为 `app.lingua.mac`、category 为 `LocalInference`；只记录运行 ID、数值阶段、加载次数、CPU／内存和空闲时长，不含原文、译文或凭据：

```sh
/usr/bin/log show --last 30m --style compact --predicate 'subsystem == "app.lingua.mac" AND category == "LocalInference"'
```

## 交付

已签名的独立 App 位于 `output/IdleFix/Lingua.app`。`/Applications/Lingua.app` 的目录权限拒绝自动替换，旧安装包未改动；安装时需由用户通过 Finder 替换。测试产生的本地翻译记录保留。
