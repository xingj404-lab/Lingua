import AppKit
import SwiftUI
import UniformTypeIdentifiers
import TranslationCore

@MainActor @Observable
final class Workspace {
    enum Page: String, CaseIterable { case text = "翻译", glossary = "术语表", history = "翻译记录", settings = "模型与设置" }
    enum Backend: String, CaseIterable { case native = "应用内 MLX", server = "API 服务" }
    var page: Page = .text
    var source = "" { didSet {
        if source != oldValue {
            automaticTargetOverride = nil
            detectedSourceLanguage = SourceLanguageDetection.detect(source)
        }
    } }
    private(set) var detectedSourceLanguage: Language?
    var output = ""
    var options = TranslationOptions()
    var directionMode: TranslationDirectionMode { didSet {
        if directionMode == .fixed && oldValue == .bidirectional {
            let direction = automaticDirection
            options.source = direction.source; options.target = direction.target
        }
        UserDefaults.standard.set(directionMode.rawValue, forKey: "directionMode")
        automaticTargetOverride = nil
    } }
    var myLanguage: Language { didSet { UserDefaults.standard.set(myLanguage.rawValue, forKey: "myLanguage"); automaticTargetOverride = nil } }
    var partnerLanguage: Language { didSet { UserDefaults.standard.set(partnerLanguage.rawValue, forKey: "partnerLanguage"); automaticTargetOverride = nil } }
    var automaticTargetOverride: Language?
    var outputLanguage: Language?
    var data = WorkspaceData()
    var error: String?
    var notice: String?
    var status = "准备就绪"
    var busy = false
    var loading = false
    var downloadStatus = ModelDownloadStatus()
    var progress = 0.0
    var loadedModel = ""
    var resources: ProcessResourceSample?
    var cpuPercent: Double?
    var generationStats = NativeGenerationStats()
    var loadStarted: TimeInterval?
    var loadDuration: TimeInterval?
    var translationStarted: TimeInterval?
    var translationDuration: TimeInterval?
    var loadingModel = ""
    private var resourceTask: Task<Void, Never>?
    private var started = false
    var imageURL: URL?
    var imagePreview: NSImage?
    var originalImage: NSImage?
    var imageName = ""
    var search = ""
    var backend: Backend { didSet {
        UserDefaults.standard.set(backend.rawValue, forKey: "backend")
        if backend != oldValue { pendingAPIConsentEndpoint = nil }
    } }
    var settingsBackend: Backend = .native
    var downloadingModelID: String?
    var modelLibraryRevision = 0
    var modelID: String { didSet { UserDefaults.standard.set(modelID, forKey: "modelID") } }
    var endpoint: String { didSet {
        UserDefaults.standard.set(endpoint, forKey: "endpoint")
        if endpoint != oldValue { pendingAPIConsentEndpoint = nil; loadSavedAPIKey() }
    } }
    var apiProvider: APIProvider { didSet { UserDefaults.standard.set(apiProvider.rawValue, forKey: "apiProvider") } }
    var apiKey = "" { didSet { apiKeySaved = false } }
    var apiKeySaved = false
    var apiKeyLoading = false
    var pendingAPIConsentEndpoint: String?
    private var credentialRequest = UUID()
    var downloadSource: ModelDownloadSource { didSet { UserDefaults.standard.set(downloadSource.rawValue, forKey: "downloadSource") } }
    var customDownloadEndpoint: String { didSet { UserDefaults.standard.set(customDownloadEndpoint, forKey: "downloadEndpoint") } }
    var serverModel: String { didSet { UserDefaults.standard.set(serverModel, forKey: "serverModel") } }
    private var task: Task<Void, Never>?
    private let native = NativeModelEngine()
    private var persistenceAvailable = true
    private let store: WorkspaceStore

    init() {
        let defaults = UserDefaults.standard
        for field in ["endpoint", "model"] {
            let key = "apiProfile.custom.\(field)"
            if defaults.string(forKey: key) == nil, let legacy = defaults.string(forKey: "apiProfile.local.\(field)") {
                defaults.set(legacy, forKey: key)
            }
        }
        directionMode = TranslationDirectionMode(rawValue: defaults.string(forKey: "directionMode") ?? "") ?? .bidirectional
        let savedMine = Language(rawValue: defaults.string(forKey: "myLanguage") ?? "") ?? .zh
        let mine = savedMine == .auto ? .zh : savedMine
        myLanguage = mine
        let partner = Language(rawValue: defaults.string(forKey: "partnerLanguage") ?? "") ?? .en
        partnerLanguage = partner == .auto || partner == mine ? (mine == .en ? .zh : .en) : partner
        let savedBackend = defaults.string(forKey: "backend") ?? ""
        backend = savedBackend == "本机模型服务" ? .server : (Backend(rawValue: savedBackend) ?? .native)
        modelID = LocalModelPreset.preferredRepository(saved: defaults.string(forKey: "modelID"))
        let savedEndpoint = defaults.string(forKey: "endpoint") ?? "http://127.0.0.1:8080/v1"
        endpoint = savedEndpoint
        apiProvider = APIProvider.restored(rawValue: defaults.string(forKey: "apiProvider"), endpoint: savedEndpoint)
        serverModel = defaults.string(forKey: "serverModel") ?? ""
        downloadSource = ModelDownloadSource(rawValue: defaults.string(forKey: "downloadSource") ?? "") ?? .mirror
        customDownloadEndpoint = defaults.string(forKey: "downloadEndpoint") ?? "https://hf-mirror.com"
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        store = WorkspaceStore(url: root.appendingPathComponent("LinguaMac/workspace.json"))
        settingsBackend = backend
        do { data = try store.load() } catch { persistenceAvailable = false; self.error = "本地记录读取失败，原文件已保留：\(error.localizedDescription)" }
    }

    var modelPreset: LocalModelPreset? { LocalModelPreset.find(modelID) }
    func selectModel(_ id: String) {
        guard !busy && !loading, LocalModelPreset.find(id) != nil else { return }
        modelID = id; downloadStatus = .init(); error = nil; notice = nil
        status = loadedModel == id ? "本地模型已就绪" : "已选择模型，下载并加载后可翻译"
    }
    var modelIsReady: Bool { !loadedModel.isEmpty && loadedModel == modelKey }
    var modelIsDownloaded: Bool { modelIsDownloaded(modelKey) }
    func modelIsDownloaded(_ id: String) -> Bool {
        _ = modelLibraryRevision
        guard LocalModelPreset.find(id) != nil else { return false }
        let host = (try? downloadSource.endpoint(custom: customDownloadEndpoint)) ?? URL(string: "https://hf-mirror.com")!
        return (try? ModelDownloader.bundledSnapshot(repository: id)) != nil ||
            (try? ModelDownloader(endpoint: host).cachedSnapshot(repository: id)) != nil
    }
    var modelIsBundled: Bool { modelIsBundled(modelKey) }
    func modelIsBundled(_ id: String) -> Bool { (try? ModelDownloader.bundledSnapshot(repository: id)) != nil }
    func useLibraryModel(_ id: String) {
        guard !busy, !loading, LocalModelPreset.find(id) != nil, modelIsDownloaded(id) else { return }
        selectModel(id)
        selectBackend(.native)
    }
    /// Download a supported model without changing the selected backend or resident model.
    func downloadLibraryModel(_ id: String) {
        guard !busy, !loading, LocalModelPreset.find(id) != nil, !modelIsDownloaded(id) else { return }
        let host: URL
        do { host = try downloadSource.endpoint(custom: customDownloadEndpoint) }
        catch { self.error = error.localizedDescription; return }
        loading = true; downloadingModelID = id; downloadStatus = .init(); error = nil; notice = nil
        status = "正在下载模型"
        task = Task {
            defer { loading = false; downloadingModelID = nil; modelLibraryRevision += 1; task = nil }
            do {
                _ = try await ModelDownloader(endpoint: host).download(repository: id) { [weak self] value in
                    Task { @MainActor in
                        guard let self, self.downloadingModelID == id else { return }
                        self.downloadStatus = value
                    }
                }
                try Task.checkCancellation()
                status = "模型下载完成，可在模型库中切换使用"
            } catch {
                if Task.isCancelled || error is CancellationError { status = "下载已取消" }
                else { self.error = error.localizedDescription; status = "下载失败" }
            }
        }
    }
    func start() {
        guard !started else { return }
        started = true
        loadSavedAPIKey()
        prepareLocalModel()
    }
    func prepareLocalModel() {
        guard backend == .native, !busy, !loading, !modelIsReady else { return }
        loadModel(allowDownload: false)
    }
    var modelActionTitle: String {
        modelIsReady ? "开始翻译" : (modelIsDownloaded ? "加载模型" : "下载并加载")
    }
    var loadElapsed: TimeInterval {
        loadStarted.map { max(0, (resources?.time ?? ProcessInfo.processInfo.systemUptime) - $0) } ?? 0
    }
    var translationElapsed: TimeInterval {
        translationDuration ?? translationStarted.map { max(0, (resources?.time ?? ProcessInfo.processInfo.systemUptime) - $0) } ?? 0
    }
    private func monitorResources() {
        guard resourceTask == nil else { return }
        resourceTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.loading || !self.loadedModel.isEmpty else { break }
                let sample = ProcessResourceSample.current()
                self.cpuPercent = self.resources.flatMap { sample.cpuPercent(since: $0) }
                self.resources = sample
                do { try await Task.sleep(for: .seconds(1)) } catch { break }
            }
            self?.resourceTask = nil
        }
    }
    func selectBackend(_ selection: Backend) {
        guard !busy && !loading else { return }
        backend = selection
        settingsBackend = selection
        error = nil; notice = nil
        status = selection == .native ? (modelIsReady ? "本地模型已就绪" : "请先加载本地模型") : "已选择 API 服务"
        if selection == .native { prepareLocalModel() }
    }
    var modelKey: String { modelID.trimmingCharacters(in: .whitespacesAndNewlines) }
    var modelFilesURL: URL? {
        guard let host = try? downloadSource.endpoint(custom: customDownloadEndpoint) else { return nil }
        return try? ModelDownloads.repositoryURL(endpoint: host, repository: modelID, files: true)
    }
    var downloadHost: String { (try? downloadSource.endpoint(custom: customDownloadEndpoint).host) ?? "地址无效" }
    var apiHost: String { (try? TranslationPlanning.apiEndpoint(endpoint).host) ?? "地址无效" }
    var usesRemoteAPI: Bool {
        guard let url = try? TranslationPlanning.apiEndpoint(endpoint) else { return false }
        return !TranslationPlanning.isLoopback(url)
    }
    func selectAPIProvider(_ provider: APIProvider) {
        guard !busy && !loading && provider != apiProvider else { return }
        let defaults = UserDefaults.standard
        defaults.set(endpoint, forKey: "apiProfile.\(apiProvider.rawValue).endpoint")
        defaults.set(serverModel, forKey: "apiProfile.\(apiProvider.rawValue).model")
        apiProvider = provider
        endpoint = defaults.string(forKey: "apiProfile.\(provider.rawValue).endpoint") ?? provider.endpoint
        serverModel = defaults.string(forKey: "apiProfile.\(provider.rawValue).model") ?? ""
        error = nil; notice = nil; status = "填写服务凭据后可翻译"
    }
    private func loadSavedAPIKey() {
        apiKey = ""; apiKeySaved = false
        let request = UUID(); credentialRequest = request
        guard let url = try? TranslationPlanning.apiEndpoint(endpoint) else { apiKeyLoading = false; return }
        apiKeyLoading = true
        // Read only app-local credential files; keep disk I/O off the main thread.
        Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) { Result { try APICredentials.read(endpoint: url) } }.value
            guard let self, self.credentialRequest == request else { return }
            self.apiKeyLoading = false
            guard self.apiKey.isEmpty else { return } // Preserve a key typed while reading.
            switch result {
            case .success(let key): self.apiKey = key ?? ""; self.apiKeySaved = !(key ?? "").isEmpty
            case .failure: self.notice = "无法读取已存凭据。可重新输入 API Key，或继续使用本地模型。"
            }
        }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard let self, self.credentialRequest == request, self.apiKeyLoading else { return }
            self.credentialRequest = UUID(); self.apiKeyLoading = false
            self.notice = "本地凭据访问超时。可重新输入 API Key，或继续使用本地模型。"
        }
    }
    func saveAPIKey() {
        guard !busy && !loading && !apiKeyLoading else { return }
        guard let url = try? TranslationPlanning.apiEndpoint(endpoint) else { return }
        let token = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let request = UUID(); credentialRequest = request; apiKeyLoading = true
        Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) { Result { try APICredentials.save(token, endpoint: url) } }.value
            guard let self, self.credentialRequest == request else { return }
            self.apiKeyLoading = false
            switch result {
            case .success:
                if self.apiKey.trimmingCharacters(in: .whitespacesAndNewlines) == token {
                    self.apiKey = token; self.apiKeySaved = !token.isEmpty
                }
                self.notice = token.isEmpty ? "已移除该服务的已存 API Key。" : "API Key 已保存到本地。"
            case .failure(let error): self.error = error.localizedDescription
            }
        }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard let self, self.credentialRequest == request, self.apiKeyLoading else { return }
            self.credentialRequest = UUID(); self.apiKeyLoading = false
            self.notice = "本地凭据访问超时。可重新输入 API Key，或继续使用本地模型。"
        }
    }
    func approveAPIConsent(_ address: String) {
        guard backend == .server, pendingAPIConsentEndpoint == address,
              (try? TranslationPlanning.apiEndpoint(endpoint).absoluteString) == address else { return }
        pendingAPIConsentEndpoint = nil
        var accepted = UserDefaults.standard.stringArray(forKey: "consentedAPIEndpoints.v1") ?? []
        if !accepted.contains(address) { accepted.append(address) }
        UserDefaults.standard.set(accepted, forKey: "consentedAPIEndpoints.v1")
        translate()
    }
    func revokeAPIConsent() {
        UserDefaults.standard.removeObject(forKey: "consentedAPIEndpoints.v1")
        pendingAPIConsentEndpoint = nil
        notice = "已撤销 API 发送授权，下次翻译前将重新询问。"
    }
    func clearHistory() {
        guard !busy && !loading else { return }
        data.history.removeAll(); save()
    }
    var engineName: String { backend == .native ? modelKey : serverModel }
    var automaticDirection: TranslationDirection {
        TranslationDirection.resolve(detected: detectedSourceLanguage, mine: myLanguage,
                                     partner: partnerLanguage, override: automaticTargetOverride)
    }
    var effectiveOptions: TranslationOptions {
        var result = options
        if directionMode == .bidirectional {
            let direction = automaticDirection
            result.source = direction.source; result.target = direction.target
        }
        return result
    }
    func selectMyLanguage(_ language: Language) {
        guard language != .auto, !busy, !loading else { return }
        let old = myLanguage
        if partnerLanguage == language { partnerLanguage = old }
        myLanguage = language
    }
    func selectPartnerLanguage(_ language: Language) {
        guard language != .auto, !busy, !loading else { return }
        let old = partnerLanguage
        if myLanguage == language { myLanguage = old }
        partnerLanguage = language
    }
    var canTranslate: Bool {
        !busy && !loading && !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (backend == .server || (!loadedModel.isEmpty && loadedModel == modelKey))
    }
    var issues: [ReviewIssue] { output.isEmpty ? [] : TranslationReview.issues(source: source, target: output, glossary: data.glossary) }
    var filteredHistory: [TranslationRecord] {
        data.history.filter { search.isEmpty || $0.source.localizedCaseInsensitiveContains(search) || $0.translation.localizedCaseInsensitiveContains(search) }
    }

    func loadModel(allowDownload: Bool = true) {
        guard !busy && !loading else { return }
        guard !modelIsReady else { status = "本地模型已就绪 · 已复用，无需重新加载"; return }
        guard LocalModelPreset.find(modelKey) != nil else { error = "请选择模型库中的已适配模型。"; return }
        let bundled = try? ModelDownloader.bundledSnapshot(repository: modelKey)
        if !allowDownload && !modelIsDownloaded {
            status = "没有可用的本地模型"
            error = "所选模型尚未下载或文件不可用，请前往模型设置选择内置模型，或下载其他模型。"
            return
        }
        let host: URL
        do {
            // Installed library models are resolved locally before considering the network.
            host = modelIsDownloaded ? ((try? downloadSource.endpoint(custom: customDownloadEndpoint)) ?? URL(string: "https://hf-mirror.com")!) : try downloadSource.endpoint(custom: customDownloadEndpoint)
            _ = try ModelDownloads.validateRepository(modelID)
        } catch { self.error = error.localizedDescription; return }
        loading = true; progress = 0; downloadStatus = .init(); error = nil; loadedModel = ""
        loadStarted = ProcessInfo.processInfo.systemUptime; loadDuration = nil
        loadingModel = modelKey; generationStats = .init(); monitorResources()
        status = modelIsDownloaded ? "加载本地模型…" : "通过 \(host.host ?? "") 下载 / 加载…"
        let key = modelKey, id = modelID.trimmingCharacters(in: .whitespacesAndNewlines), folder = bundled?.path ?? ""
        task = Task {
            do {
                if bundled != nil {
                    downloadStatus = .init(phase: .verifying, file: "校验内置模型")
                    let verified = try await Task.detached { try ModelDownloader.bundledSnapshot(repository: id, verifyContents: true) }.value
                    guard verified != nil else { throw TranslationError.backend("内置模型文件不完整，请重新安装 App，或在模型设置中选择其他模型。") }
                }
                if !allowDownload && folder.isEmpty {
                    // Resolve and verify offline; never enter the network downloader during startup.
                    let cached = try await Task.detached { try ModelDownloader(endpoint: host).cachedSnapshot(repository: id, verifyContents: true) }.value
                    guard let cached else { throw TranslationError.backend("本地模型文件不完整，请前往模型设置下载或选择其他模型。") }
                    try await native.load(id: id, directory: cached.path, downloadEndpoint: host, identity: key) { [weak self] value in
                        Task { @MainActor in guard let self, self.loading else { return }; self.downloadStatus = value; self.status = value.phase.rawValue }
                    }
                } else {
                try await native.load(id: id, directory: folder, downloadEndpoint: host, identity: key) { [weak self = self] value in
                    Task { @MainActor in
                        guard let self, self.loading else { return }
                        self.downloadStatus = value; self.progress = value.fraction
                        self.status = value.phase.rawValue
                    }
                }
                }
                try Task.checkCancellation()
                loadedModel = key; status = "本地模型已就绪"; notice = "模型已加载，翻译在本机运行。"
            } catch is CancellationError { status = "加载已取消" }
              catch {
                if Task.isCancelled { status = "加载已取消" }
                else { self.error = error.localizedDescription; status = "加载失败" }
            }
            downloadStatus.speed = 0
            loadDuration = ProcessInfo.processInfo.systemUptime - (loadStarted ?? ProcessInfo.processInfo.systemUptime)
            loadStarted = nil
            if !loadedModel.isEmpty && allowDownload {
                notice = "本地模型已就绪，加载用时 \(String(format: "%.1f", loadDuration ?? 0)) 秒。后续翻译直接复用，无需重复加载。"
            } else if !loadedModel.isEmpty {
                notice = nil
            }
            loading = false; task = nil
        }
    }
    func unloadModel() {
        guard !busy && !loading else { return }
        loadedModel = ""; status = "模型已卸载"
        task = Task { await native.unload(); task = nil }
    }

    func translate() {
        guard !busy && !loading else { return }
        let request = TranslationRequest(text: source, options: effectiveOptions, glossary: data.glossary)
        do { try TranslationPlanning.validate(request) } catch { self.error = error.localizedDescription; return }
        guard canTranslate else { error = TranslationError.notConfigured.localizedDescription; page = .settings; return }
        let selectedBackend = backend, key = modelKey, engine = engineName
        let apiService = APIServiceEngine(endpoint: endpoint, model: serverModel, apiKey: apiKey)
        if selectedBackend == .server {
            do { _ = try apiService.makeURLRequest(request) }
            catch { self.error = error.localizedDescription; page = .settings; return }
        }
        if selectedBackend == .server {
            guard !apiKeyLoading else { notice = "正在读取 API 凭据，请稍候。"; return }
            let address = (try? TranslationPlanning.apiEndpoint(endpoint).absoluteString) ?? endpoint
            let accepted = UserDefaults.standard.stringArray(forKey: "consentedAPIEndpoints.v1") ?? []
            guard accepted.contains(address) else { pendingAPIConsentEndpoint = address; return }
        }
        let parts = TranslationPlanning.segments(request.text)
        busy = true; error = nil; notice = nil; output = ""; progress = 0
        outputLanguage = request.options.target
        if selectedBackend == .native {
            generationStats = .init(); translationStarted = ProcessInfo.processInfo.systemUptime; translationDuration = nil
        }
        task = Task(priority: .userInitiated) {
            var completed = ""
            var previousStats = NativeGenerationStats()
            do {
                for (index, part) in parts.enumerated() {
                    try Task.checkCancellation()
                    status = "翻译第 \(index + 1) / \(parts.count) 段"
                    let segment = TranslationRequest(text: part, options: request.options, glossary: request.glossary)
                    let prefix = completed
                    let result: String
                    if selectedBackend == .native {
                        let baseStats = previousStats
                        result = try await native.translate(segment, expectedID: key, stats: { [weak self = self] value in
                            await MainActor.run {
                                self?.generationStats = .init(promptTokens: baseStats.promptTokens + value.promptTokens,
                                    outputTokens: baseStats.outputTokens + value.outputTokens,
                                    generationSeconds: baseStats.generationSeconds + value.generationSeconds,
                                    promptSeconds: baseStats.promptSeconds + value.promptSeconds,
                                    firstTokenSeconds: value.firstTokenSeconds,
                                    totalSeconds: baseStats.totalSeconds + value.totalSeconds, estimated: value.estimated)
                            }
                        }) { [weak self = self] value in
                            await MainActor.run { self?.output = prefix + value }
                        }
                        previousStats = generationStats
                    } else { result = try await apiService.translate(segment) }
                    try Task.checkCancellation()
                    // Restore source paragraph boundaries removed by model output trimming.
                    let leading = String(part.prefix(while: { $0.isWhitespace }))
                    let trailing = String(part.reversed().prefix(while: { $0.isWhitespace }).reversed())
                    completed += leading + result + trailing
                    output = completed; progress = Double(index + 1) / Double(parts.count)
                }
                guard !output.isEmpty else { throw TranslationError.emptyResponse }
                data.history.insert(TranslationRecord(source: request.text, translation: output, options: request.options, engine: engine), at: 0)
                data.history = Array(data.history.prefix(100)); save()
                status = "翻译完成"; notice = nil
            } catch is CancellationError { status = "已停止 · 当前译文未保存" }
              catch {
                if Task.isCancelled { status = "已停止 · 当前译文未保存" }
                else { self.error = error.localizedDescription; status = "翻译未完成 · 当前译文未保存" }
            }
            busy = false; task = nil
            if selectedBackend == .native {
                translationDuration = ProcessInfo.processInfo.systemUptime - (translationStarted ?? ProcessInfo.processInfo.systemUptime)
                translationStarted = nil
            }
        }
    }

    func stop() { task?.cancel() }
    func reset() {
        guard !busy && !loading else { return }
        pendingAPIConsentEndpoint = nil
        source = ""; output = ""; imageURL = nil; imagePreview = nil; originalImage = nil; imageName = ""; error = nil; notice = nil; status = "准备就绪"
        generationStats = .init(); translationStarted = nil; translationDuration = nil; progress = 0
        outputLanguage = nil
    }
    func swapLanguages() {
        if directionMode == .bidirectional {
            guard !busy, !loading else { return }
            automaticTargetOverride = automaticDirection.target == myLanguage ? partnerLanguage : myLanguage
            return
        }
        guard !busy && options.source != .auto else { return }
        let old = options.source; options.source = options.target; options.target = old
        if !output.isEmpty { source = output; output = "" }
    }
    func restore(_ record: TranslationRecord) {
        guard !busy && !loading else { return }
        source = record.source; output = record.translation; options = record.options
        outputLanguage = record.options.target
        imageURL = nil; imagePreview = nil; originalImage = nil; imageName = ""; page = .text; notice = "已打开历史记录；编辑后可重新翻译。"
    }
    func importImage() {
        guard !busy && !loading else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff, .webP]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        recognize(url)
    }
    /// Image data takes precedence over plain text; normal text paste stays in NSTextView.
    func pasteImage(_ pasteboard: NSPasteboard) -> Bool {
        let files = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        if let url = files.first(where: { UTType(filenameExtension: $0.pathExtension)?.conforms(to: .image) == true }) {
            if !busy && !loading { recognize(url) }
            return true
        }
        guard let image = NSImage(pasteboard: pasteboard) else { return false }
        guard !busy && !loading else { return true }
        guard let data = image.tiffRepresentation else { return false }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Lingua-clipboard-\(UUID().uuidString).tiff")
        do {
            try data.write(to: url, options: .atomic)
            recognize(url, clipboardImage: true)
        } catch { self.error = error.localizedDescription }
        return true
    }
    func recognize(_ url: URL, clipboardImage: Bool = false) {
        guard !busy && !loading else { return }
        page = .text; busy = true; error = nil; status = "识别图片文字…"
        task = Task {
            let access = url.startAccessingSecurityScopedResource()
            defer {
                if access { url.stopAccessingSecurityScopedResource() }
                if clipboardImage { try? FileManager.default.removeItem(at: url) }
            }
            do {
                let result = try await OCRService().recognize(url: url)
                try Task.checkCancellation()
                originalImage = (try? Data(contentsOf: url)).flatMap { NSImage(data: $0) }
                source = result.text; output = ""; imageURL = clipboardImage ? nil : url; imagePreview = result.previewData.flatMap { NSImage(data: $0) }; imageName = clipboardImage ? L10n.text("粘贴的图片") : url.lastPathComponent
                notice = result.lowConfidenceLines == 0 ? "文字已识别。请核对原文后点击翻译。" : "\(result.lowConfidenceLines) 行识别置信度较低，请核对原文。"
                status = "文字识别完成"
            } catch is CancellationError { status = "识别已取消" }
              catch { self.error = error.localizedDescription; status = "识别失败" }
            busy = false; task = nil
        }
    }
    func removeImage() {
        guard !busy && !loading else { return }
        imageURL = nil; imagePreview = nil; originalImage = nil; imageName = ""
    }
    @discardableResult
    func importFile(_ url: URL) -> Bool {
        guard url.isFileURL, !busy && !loading else { return false }
        let type = UTType(filenameExtension: url.pathExtension)
        if type?.conforms(to: .image) == true {
            recognize(url)
        } else if type?.conforms(to: .plainText) == true || url.pathExtension.lowercased() == "md" {
            readText(url)
        } else {
            error = "请选择图片或 TXT / Markdown 文本文件。"
            return false
        }
        return true
    }
    func importText() {
        guard !busy && !loading else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.plainText, UTType(filenameExtension: "md")!]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        readText(url)
    }
    private func readText(_ url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard (attributes[.size] as? NSNumber)?.intValue ?? 0 <= 200_000 else { throw TranslationError.tooLong }
            let value = try String(contentsOf: url, encoding: .utf8)
            guard value.count <= 24_000 else { throw TranslationError.tooLong }
            source = value; output = ""; removeImage(); page = .text; error = nil; notice = nil; status = "文本已导入"
        } catch { self.error = error.localizedDescription }
    }
    func export() {
        guard !output.isEmpty && !busy else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.plainText]; panel.nameFieldStringValue = L10n.text("译文.txt")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try output.write(to: url, atomically: true, encoding: .utf8); notice = "译文已导出。" }
        catch { self.error = error.localizedDescription }
    }
    func copy() { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(output, forType: .string); notice = "译文已复制。" }
    func addTerm(source: String, target: String) -> Bool {
        let s = source.trimmingCharacters(in: .whitespacesAndNewlines), t = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty && !t.isEmpty else { error = "请填写原文术语和对应译法。"; return false }
        guard !data.glossary.contains(where: { $0.source.localizedCaseInsensitiveCompare(s) == .orderedSame }) else { error = "该术语已存在，请先删除旧条目再添加。"; return false }
        data.glossary.append(GlossaryEntry(source: s, target: t)); save(); return true
    }
    func deleteTerm(_ id: UUID) { data.glossary.removeAll { $0.id == id }; save() }
    func deleteRecord(_ id: UUID) { data.history.removeAll { $0.id == id }; save() }
    func save() {
        guard persistenceAvailable else { error = "原记录文件读取失败，新记录仅在内存中保留，避免覆盖原文件。请检查 Application Support/LinguaMac/workspace.json。"; return }
        do { try store.save(data) } catch { self.error = "保存失败：\(error.localizedDescription)" } }
}
