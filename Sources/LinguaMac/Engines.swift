import Foundation
import Darwin
import TranslationCore
#if canImport(MLXLLM)
import MLX
import MLXLLM
import MLXLMCommon
import MLXHuggingFace
import HuggingFace
import Tokenizers
#endif

/// OpenAI-compatible service; remote endpoints require HTTPS, redirects are refused.
struct APIServiceEngine: Sendable {
    let endpoint: String
    let model: String
    var apiKey: String = ""

    func makeURLRequest(_ request: TranslationRequest) throws -> URLRequest {
        let base = try TranslationPlanning.apiEndpoint(endpoint)
        let name = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw TranslationError.backend("请填写服务中的模型名称。") }
        let token = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.contains(where: { $0.isNewline }) else { throw TranslationError.backend("API Key 不能包含换行。") }
        var urlRequest = URLRequest(url: base.appendingPathComponent("chat/completions"))
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 180
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !token.isEmpty { urlRequest.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        urlRequest.httpBody = try JSONEncoder().encode(Payload(
            model: name,
            messages: [Message(role: "system", content: request.instructions), Message(role: "user", content: request.prompt)],
            temperature: 0.1, max_tokens: 2048, stream: false,
            thinking: base.host == "api.deepseek.com" && (name == "deepseek-flash" || name.hasPrefix("deepseek-v4-")) ? Thinking(type: "disabled") : nil
        ))
        return urlRequest
    }

    func translate(_ request: TranslationRequest) async throws -> String {
        let urlRequest = try makeURLRequest(request)
        // Keep both source text and credentials on the explicitly configured endpoint.
        let session = URLSession(configuration: .ephemeral, delegate: NoRedirectDelegate(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else { throw TranslationError.emptyResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw TranslationError.backend("API 服务返回 HTTP \(http.statusCode)，请检查地址、API Key 和模型名称。")
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        guard let choice = decoded.choices.first else { throw TranslationError.emptyResponse }
        if choice.finish_reason == "length" { throw TranslationError.backend("输出达到模型长度上限，请缩短原文后重试。") }
        let result = choice.message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { throw TranslationError.emptyResponse }
        return result
    }

    private struct Message: Codable { let role: String; let content: String }
    private struct Thinking: Encodable { let type: String }
    private struct Payload: Encodable {
        let model: String; let messages: [Message]; let temperature: Double; let max_tokens: Int; let stream: Bool; let thinking: Thinking?
    }
    private struct Response: Decodable {
        struct Choice: Decodable { let message: Message; let finish_reason: String? }
        let choices: [Choice]
    }
}

private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

/// Prevent App Nap from demoting the ready model's worker queues between requests.
/// This does not prevent system sleep or run periodic GPU work.
private final class ModelReadyActivity: @unchecked Sendable {
    private let token: NSObjectProtocol
    init() {
        token = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep,
            reason: "保持已加载的本地翻译模型可响应")
    }
    deinit { ProcessInfo.processInfo.endActivity(token) }
}

actor NativeModelEngine {
    private(set) var actualLoadCount = 0
    private(set) var actualWarmupCount = 0
    private(set) var warmupDuration = 0.0
    #if canImport(MLXLLM)
    private var container: ModelContainer?
    private var residencyTicket: WiredMemoryTicket?
    #endif
    private var readyActivity: ModelReadyActivity?
    var readyActivityHeld: Bool { readyActivity != nil }
    private let preventModelAppNap: Bool
    private let keepModelResident: Bool
    private(set) var wiredBytes = 0

    init(keepModelResident: Bool = true, preventModelAppNap: Bool = true) {
        self.keepModelResident = keepModelResident
        self.preventModelAppNap = preventModelAppNap
    }

    private let performanceRunID = UUID().uuidString
    private var requestNumber = 0
    private var readyAt: TimeInterval?
    private var lastRequestEndedAt: TimeInterval?
    private var loadedID = ""
    private var promptFamily: NativeTranslationPrompt.Family = .general

    func load(id: String, directory: String, downloadEndpoint: URL, identity: String? = nil, progress: @escaping @Sendable (ModelDownloadStatus) -> Void) async throws {
        #if canImport(MLXLLM)
        let key = identity ?? (directory.isEmpty ? id : directory)
        if container != nil, loadedID == key { progress(.init(phase: .loading)); return }
        container = nil
        readyActivity = nil
        await releaseResidency()
        loadedID = ""
        let folder: URL
        if directory.isEmpty {
            folder = try await ModelDownloader(endpoint: downloadEndpoint).download(repository: id, progress: progress)
        } else {
            folder = URL(fileURLWithPath: directory)
            progress(.init(phase: .loading))
        }
        struct Configuration: Decodable { let model_type: String }
        let configuration = try JSONDecoder().decode(Configuration.self, from: Data(contentsOf: folder.appendingPathComponent("config.json")))
        let family: NativeTranslationPrompt.Family = configuration.model_type == "hunyuan_v1_dense" ? .hunyuan : .general
        let model = try await loadModelContainer(from: folder, using: #huggingFaceTokenizerLoader())
        try Task.checkCancellation()
        progress(.init(phase: .warming, file: "初始化输入处理与本地计算"))
        let warmupStart = ProcessInfo.processInfo.systemUptime
        let warmInputs: [(String, Language, Language)] = [
            ("你好。", .zh, .en),
            ("请确认我提交的文件版本，并告知处理结果。", .zh, .en),
            ("Hello.", .en, .zh),
            ("What version did you submit? The file has already been submitted.", .en, .zh)
        ]
        for (index, input) in warmInputs.enumerated() {
            progress(.init(phase: .warming, file: "准备双向计算 \(index + 1) / \(warmInputs.count)"))
            let warmPrompt = NativeTranslationPrompt(request: .init(text: input.0, options: .init(source: input.1, target: input.2), glossary: []), family: family)
            let warmRun = try await stream(model: model, prompt: warmPrompt, family: family, maxTokens: 16)
            do {
                for await _ in warmRun.stream { try Task.checkCancellation() }
            } catch {
                warmRun.task.cancel()
                await warmRun.task.value
                throw error
            }
            await warmRun.task.value
        }
        try Task.checkCancellation()
        warmupDuration = ProcessInfo.processInfo.systemUptime - warmupStart
        actualWarmupCount += 1
        // Hold a bounded Metal residency request for the resident model's lifetime.
        // An ordinary Swift reference alone does not keep its GPU buffers resident.
        if keepModelResident, let recommended = GPU.maxRecommendedWorkingSetBytes(), recommended > 0 {
            // Metal accounts for cached buffers too; omitting them can leave model
            // buffers outside the residency set when the allocator enumerates allocations.
            let budget = min(Memory.activeMemory + Memory.cacheMemory + 256 * 1024 * 1024, recommended)
            let ticket = WiredMemoryTicket(size: budget, policy: WiredFixedPolicy(limit: budget), kind: .active)
            _ = await ticket.start()
            if Task.isCancelled {
                _ = await ticket.end()
                throw CancellationError()
            }
            residencyTicket = ticket
            wiredBytes = budget
        }
        if preventModelAppNap { readyActivity = ModelReadyActivity() }
        container = model
        actualLoadCount += 1
        promptFamily = family
        loadedID = key
        readyAt = ProcessInfo.processInfo.systemUptime
        lastRequestEndedAt = nil
        trace(event: "ready", start: warmupStart)
        #else
        throw TranslationError.backend("此构建未包含 MLX。请使用完整构建，或配置 API 服务。")
        #endif
    }

    func verifyRuntime() throws -> String {
        #if canImport(MLXLLM)
        let values = MLXArray([Float(1), Float(2), Float(3)])
        let result = MLX.sum(values).item(Float.self)
        guard result == 6 else { throw TranslationError.backend("MLX Metal 运行检查失败。") }
        return "MLX Metal runtime OK: sum = 6"
        #else
        throw TranslationError.backend("This build does not include MLX.")
        #endif
    }

    func unload() async {
        readyActivity = nil
        readyAt = nil
        lastRequestEndedAt = nil
        #if canImport(MLXLLM)
        container = nil
        await releaseResidency()
        #endif
        loadedID = ""
    }

    func translate(_ request: TranslationRequest, expectedID: String,
                   stats: @escaping @Sendable (NativeGenerationStats) async -> Void = { _ in },
                   chunk: @escaping @Sendable (String) async -> Void) async throws -> String {
        #if canImport(MLXLLM)
        guard let container, loadedID == expectedID else { throw TranslationError.notConfigured }
        let activity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep,
                                                           reason: "用户发起的本地翻译")
        defer { ProcessInfo.processInfo.endActivity(activity) }
        let requestStart = ProcessInfo.processInfo.systemUptime
        requestNumber += 1
        let idleSeconds = lastRequestEndedAt.map { requestStart - $0 }
        var completion: NativeGenerationStats?
        var firstTokenTime: TimeInterval?
        trace(event: "request_started", start: requestStart, idleSeconds: idleSeconds)
        defer {
            trace(event: completion == nil ? "request_interrupted" : "request_finished", start: requestStart,
                  idleSeconds: idleSeconds, firstTokenSeconds: firstTokenTime.map { $0 - requestStart }, stats: completion)
            lastRequestEndedAt = ProcessInfo.processInfo.systemUptime
        }
        // Each segment has its own context. No conversation state is carried between documents.
        let prompt = NativeTranslationPrompt(request: request, family: promptFamily)
        trace(event: "prompt_built", start: requestStart, idleSeconds: idleSeconds)
        var result = ""
        let tokenizer = await container.tokenizer
        trace(event: "tokenizer_ready", start: requestStart, idleSeconds: idleSeconds)
        let generation = try await stream(model: container, prompt: prompt, family: promptFamily, maxTokens: 2048,
                                      requestStart: requestStart, idleSeconds: idleSeconds)
        var lastStatsTime = 0.0
        var lastPublishTime = 0.0
        do {
            for await event in generation.stream {
                try Task.checkCancellation()
                if let token = event.chunk {
                    let now = ProcessInfo.processInfo.systemUptime
                    if firstTokenTime == nil {
                        firstTokenTime = now
                        trace(event: "first_chunk", start: requestStart, idleSeconds: idleSeconds,
                              firstTokenSeconds: now - requestStart)
                    }
                    result += token
                    if now - lastPublishTime >= 0.08 {
                        lastPublishTime = now
                        await chunk(result)
                    }
                    if now - lastStatsTime >= 0.3 {
                        lastStatsTime = now
                        await stats(.init(outputTokens: tokenizer.encode(text: result).count,
                                          generationSeconds: now - (firstTokenTime ?? now), estimated: true))
                    }
                }
                if let info = event.info {
                    completion = .init(promptTokens: info.promptTokenCount, outputTokens: info.generationTokenCount,
                                      generationSeconds: info.generateTime, promptSeconds: info.promptTime,
                                      firstTokenSeconds: (firstTokenTime ?? ProcessInfo.processInfo.systemUptime) - requestStart,
                                      totalSeconds: ProcessInfo.processInfo.systemUptime - requestStart)
                    if let completion { await stats(completion) }
                }
                if let info = event.info, info.stopReason == .length {
                    throw TranslationError.backend("输出达到模型长度上限，请缩短原文后重试。")
                }
            }
        } catch {
            generation.task.cancel()
            await generation.task.value
            throw error
        }
        await generation.task.value
        try Task.checkCancellation()
        await chunk(result)
        guard !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw TranslationError.emptyResponse }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
        #else
        throw TranslationError.notConfigured
        #endif
    }
    #if canImport(MLXLLM)
    /// Translation is a single independent turn; no conversation ledger or shared KV cache is needed.
    private func stream(model: ModelContainer, prompt: NativeTranslationPrompt,
                        family: NativeTranslationPrompt.Family, maxTokens: Int,
                        requestStart: TimeInterval? = nil, idleSeconds: Double? = nil) async throws -> (stream: AsyncStream<Generation>, task: Task<Void, Never>) {
        var messages: [Chat.Message] = []
        if let instructions = prompt.instructions { messages.append(.system(instructions)) }
        messages.append(.user(prompt.text))
        let input = try await model.prepare(input: UserInput(chat: messages,
            additionalContext: family == .general ? ["enable_thinking": false] : [:]))
        try Task.checkCancellation()
        if let requestStart { trace(event: "input_prepared", start: requestStart, idleSeconds: idleSeconds) }
        let parameters = Self.parameters(family: family, maxTokens: maxTokens)
        let run = try await model.perform(nonSendable: input) { context, input in
            let iterator = try TokenIterator(input: input, model: context.model, parameters: parameters)
            return MLXLMCommon.generateTask(promptTokenCount: input.text.tokens.size,
                modelConfiguration: context.configuration, tokenizer: context.tokenizer, iterator: iterator)
        }
        if let requestStart { trace(event: "generation_started", start: requestStart, idleSeconds: idleSeconds) }
        return run
    }

    private func releaseResidency() async {
        let ticket = residencyTicket
        residencyTicket = nil
        wiredBytes = 0
        if let ticket { _ = await ticket.end() }
    }

    deinit {
        if let ticket = residencyTicket { Task { _ = await ticket.end() } }
    }
    #endif

    private func trace(event: String, start: TimeInterval, idleSeconds: Double? = nil,
                       firstTokenSeconds: Double? = nil, stats: NativeGenerationStats? = nil) {
        let now = ProcessInfo.processInfo.systemUptime
        let sample = ProcessResourceSample.current()
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        NativePerformanceTrace(runID: performanceRunID, event: event, requestNumber: requestNumber,
                               loadCount: actualLoadCount, warmupCount: actualWarmupCount,
                               sinceReadySeconds: readyAt.map { now - $0 }, idleSeconds: idleSeconds,
                               elapsedSeconds: now - start, firstTokenSeconds: firstTokenSeconds,
                               promptSeconds: stats?.promptSeconds, generationSeconds: stats?.generationSeconds,
                               promptTokens: stats?.promptTokens, outputTokens: stats?.outputTokens,
                               residentBytes: sample.residentBytes, mlxBytes: sample.mlxBytes, wiredBytes: wiredBytes, readyActivityHeld: readyActivityHeld,
                               cpuSeconds: sample.cpuSeconds, pageIns: Int64(usage.ru_majflt)).emit()
    }
    #if canImport(MLXLLM)
    private static func parameters(family: NativeTranslationPrompt.Family, maxTokens: Int) -> GenerateParameters {
        let policy = NativeSamplingPolicy(family: family, maxTokens: maxTokens)
        return GenerateParameters(maxTokens: policy.maxTokens, temperature: policy.temperature,
                                  topP: policy.topP, topK: policy.topK, repetitionPenalty: policy.repetitionPenalty)
    }
    #endif
}
