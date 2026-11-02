import SwiftUI
import AppKit
import TranslationCore

@main
enum LinguaEntryPoint {
    @MainActor
    static func main() async {
        // MLX #4633: renew Metal residency without periodic GPU computations.
        // Configure before any MLX device initialization; explicit overrides win.
        setenv("MLX_METAL_RESIDENCY_REFRESH_INTERVAL_MS", "1000", 0)
        if CommandLine.arguments.contains("--benchmark-local") {
            do {
                let id = LocalModelPreset.recommendedID
                let endpoint = URL(string: "https://hf-mirror.com")!
                guard let folder = try ModelDownloader.bundledSnapshot(repository: id, verifyContents: true)
                    ?? ModelDownloader(endpoint: endpoint).cachedSnapshot(repository: id, verifyContents: true) else {
                    throw TranslationError.backend("No complete local model; benchmark never downloads weights.")
                }
                let engine = NativeModelEngine(keepModelResident: !CommandLine.arguments.contains("--benchmark-unwired"),
                                               preventModelAppNap: !CommandLine.arguments.contains("--benchmark-allow-nap"))
                let start = ProcessInfo.processInfo.systemUptime
                try await engine.load(id: id, directory: folder.path, downloadEndpoint: endpoint) { _ in }
                print("Load and warmup: \(ProcessInfo.processInfo.systemUptime - start)s")
                let activityExpected = !CommandLine.arguments.contains("--benchmark-allow-nap")
                guard await engine.readyActivityHeld == activityExpected else {
                    throw TranslationError.backend("Ready-model activity state is incorrect.")
                }
                if CommandLine.arguments.contains("--benchmark-cancel") {
                    let gate = BenchmarkChunkGate()
                    let cancellation = Task {
                        try await engine.translate(.init(text: String(repeating: "今天我们需要核对提交的文件版本，并认真检查其中的所有修改。", count: 8),
                            options: .init(source: .zh, target: .en), glossary: []), expectedID: folder.path) { _ in await gate.mark() }
                    }
                    let deadline = ProcessInfo.processInfo.systemUptime + 15
                    while !(await gate.received), ProcessInfo.processInfo.systemUptime < deadline {
                        try await Task.sleep(for: .milliseconds(10))
                    }
                    cancellation.cancel()
                    switch await cancellation.result {
                    case .failure(let error) where error is CancellationError: print("PASS: cancelled active generation; checking subsequent requests")
                    default: throw TranslationError.backend("Active generation did not cancel as expected.")
                    }
                }
                let idleIndex = CommandLine.arguments.firstIndex(of: "--benchmark-idle")
                let idleSeconds = idleIndex.flatMap { index in
                    CommandLine.arguments.indices.contains(index + 1) ? Double(CommandLine.arguments[index + 1]) : nil
                } ?? 0
                guard idleSeconds.isFinite, (0...3600).contains(idleSeconds) else {
                    throw TranslationError.backend("Benchmark idle duration must be between 0 and 3600 seconds.")
                }
                let idleText = "所以，代码没有把模型加载推迟到第一次翻译。但持有模型实例不等于锁定物理内存，也不能保证所有输入形状的 GPU 计算都已预热；这两点仍需进一步排查。"
                let inputs: [(String, Language, Language)] = idleSeconds > 0 ? [(idleText, .zh, .en)] : [("你好我好大家好", .zh, .en),
                                               ("他好我也好", .zh, .en),
                                               ("What version did you submit?", .en, .zh)]
                for (text, source, target) in inputs {
                    if idleSeconds > 0 {
                        _ = try await engine.translate(.init(text: text, options: .init(source: source, target: target), glossary: []),
                                                       expectedID: folder.path) { _ in }
                        print("Primed same input shape; idle \(idleSeconds)s; wiredBytes=\(await engine.wiredBytes)")
                        fflush(stdout)
                        try await Task.sleep(for: .seconds(idleSeconds))
                    }
                    var measurements: [Double] = []
                    var firstTokens: [Double] = []
                    for iteration in 1...2 {
                        let start = ProcessInfo.processInfo.systemUptime
                        let sample = BenchmarkFirstToken()
                        _ = try await engine.translate(.init(text: text, options: .init(source: source, target: target), glossary: []),
                                                       expectedID: folder.path, stats: { value in
                            if !value.estimated {
                                await sample.set(value.firstTokenSeconds)
                                print("\(source.rawValue)->\(target.rawValue) #\(iteration): prefill=\(value.promptSeconds)s firstToken=\(value.firstTokenSeconds)s generation=\(value.generationSeconds)s")
                            }
                        }) { _ in }
                        measurements.append(ProcessInfo.processInfo.systemUptime - start)
                        firstTokens.append(await sample.value)
                    }
                    print("Elapsed: \(measurements)")
                    guard firstTokens.allSatisfy({ $0.isFinite && $0 > 0 }) else {
                        throw TranslationError.backend("Benchmark did not receive valid first-token measurements.")
                    }
                    guard firstTokens[0] <= max(2, firstTokens[1] * 3) else {
                        throw TranslationError.backend("Cold translation regression: first-token wait exceeds 2s and 3x repeat latency.")
                    }
                }
                guard await engine.actualLoadCount == 1, await engine.actualWarmupCount == 1 else {
                    throw TranslationError.backend("Benchmark expected one model load and one warmup.")
                }
                print("PASS: first/repeat latency within tolerance; loads=\(await engine.actualLoadCount), warmups=\(await engine.actualWarmupCount)")
                await engine.unload()
                guard await engine.wiredBytes == 0, !(await engine.readyActivityHeld) else { throw TranslationError.backend("Model unload did not release residency.") }
                exit(0)
            } catch {
                print("FAIL: \(error.localizedDescription)")
                exit(1)
            }
        }
        LinguaMacApp.main()
    }
}

private actor BenchmarkChunkGate {
    var received = false
    func mark() { received = true }
}

private actor BenchmarkFirstToken {
    var value = 0.0
    func set(_ seconds: Double) { value = seconds }
}

struct LinguaMacApp: App {
    @State private var workspace = Workspace()
    @AppStorage("interfaceLanguage") private var interfaceLanguage = "system"
    var body: some Scene {
        Window("Lingua", id: "main") {
            ContentView(workspace: workspace)
                 .environment(\.locale, Locale(identifier: L10n.language.rawValue))
                 .id(interfaceLanguage)
                 .onAppear {
                    NSApp.applicationIconImage = BrandAssets.appIcon
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                    if !CommandLine.arguments.contains(where: { $0.hasPrefix("--verify-") }) { workspace.start() }
                    if CommandLine.arguments.contains("--verify-runtime") {
                        Task {
                            do {
                                print(try await NativeModelEngine().verifyRuntime())
                                exit(0)
                            } catch {
                                print("Runtime check failed: \(error.localizedDescription)")
                                exit(1)
                            }
                        }
                    }
                    if CommandLine.arguments.contains("--verify-cached-model") {
                        Task {
                            do {
                                let id = LocalModelPreset.recommendedID
                                let packaged = try ModelDownloader.bundledSnapshot(repository: id, verifyContents: true)
                                guard let folder = try packaged ?? ModelDownloader(endpoint: URL(string: "https://hf-mirror.com")!).cachedSnapshot(repository: id, verifyContents: true) else {
                                    throw TranslationError.backend("No complete cached model; verification will not download weights.")
                                }
                                print(packaged != nil ? "Using packaged model (independent of user cache)" : "Using user cache")
                                let engine = NativeModelEngine()
                                let start = ProcessInfo.processInfo.systemUptime
                                for _ in 0..<2 {
                                    try await engine.load(id: id, directory: folder.path, downloadEndpoint: URL(string: "https://hf-mirror.com")!) { _ in }
                                }
                                print("Cached model loaded: \(ProcessInfo.processInfo.systemUptime - start) seconds")
                                for text in ["你提交的是什么版本", "你提交的是什么版本", "我现在已经提交了", "我现在已经提交了"] {
                                    let generationStart = ProcessInfo.processInfo.systemUptime
                                    let output = try await engine.translate(.init(text: text, options: .init(target: .en), glossary: []), expectedID: folder.path, stats: { stats in
                                        if !stats.estimated {
                                            print("Tokens: input=\(stats.promptTokens), output=\(stats.outputTokens), rate=\(stats.tokensPerSecond)")
                                            print("Phases: prefill=\(stats.promptSeconds), generation=\(stats.generationSeconds), firstToken=\(stats.firstTokenSeconds), total=\(stats.totalSeconds)")
                                        }
                                    }) { _ in }
                                    print("Translation: \(output)")
                                    print("Translation elapsed: \(ProcessInfo.processInfo.systemUptime - generationStart) seconds")
                                }
                                let count = await engine.actualLoadCount
                                guard count == 1 else { throw TranslationError.backend("Model was loaded \(count) times") }
                                let warmups = await engine.actualWarmupCount
                                guard warmups == 1 else { throw TranslationError.backend("Model was warmed up \(warmups) times") }
                                print("Warmup: \(await engine.warmupDuration) seconds, count=\(warmups)")
                                print("PASS: repeated loads and translations reused one model; no downloads")
                                exit(0)
                            } catch { print("Cached verification failed: \(error.localizedDescription)"); exit(1) }
                        }
                    }
                }
        }.defaultSize(width: 1260, height: 820)
            .commands {
                CommandGroup(replacing: .appSettings) {
                    Button(L10n.text("模型与设置…")) { workspace.page = .settings }.keyboardShortcut(",")
                }
                CommandGroup(replacing: .newItem) {
                    Button(L10n.text("新建翻译"), action: workspace.reset).keyboardShortcut("n")
                    Button(L10n.text("导入文本"), action: workspace.importText).keyboardShortcut("o")
                    Button(L10n.text("导入图片"), action: workspace.importImage).keyboardShortcut("o", modifiers: [.command, .shift])
                }
                CommandGroup(after: .pasteboard) {
                    Button(L10n.text("复制译文"), action: workspace.copy).keyboardShortcut("c", modifiers: [.command, .shift]).disabled(workspace.output.isEmpty || workspace.busy)
                    Button(L10n.text("导出译文"), action: workspace.export).keyboardShortcut("s", modifiers: [.command, .shift]).disabled(workspace.output.isEmpty || workspace.busy)
                }
            }
    }
}
