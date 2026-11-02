import Foundation
import CryptoKit
import TranslationCore

struct ModelDownloadStatus: Sendable {
    enum Phase: String, Sendable { case preparing = "获取模型信息", downloading = "下载模型", verifying = "校验文件", loading = "加载模型", warming = "预热模型" }
    var phase: Phase = .preparing
    var completed: Int64 = 0
    var total: Int64 = 0
    var cached: Int64 = 0
    var speed: Double = 0
    var file = ""
    var fraction: Double { total > 0 ? min(1, Double(completed) / Double(total)) : 0 }
    var totalText: String { total > 0 ? Self.bytes(total) : "获取中…" }
    var completedText: String { Self.bytes(completed) }
    var speedText: String { speed > 0 ? Self.bytes(Int64(speed)) + "/s" : "—" }
    static func bytes(_ value: Int64) -> String { ByteCountFormatter.string(fromByteCount: value, countStyle: .file) }
}

/// Downloads a pinned repository into ordinary files, avoiding Hub cache-path resolution.
struct ModelDownloader: Sendable {
    static func bundledSnapshot(repository: String, resources: URL? = Bundle.main.resourceURL, verifyContents: Bool = false) throws -> URL? {
        guard let resources else { return nil }
        return try Self(endpoint: URL(string: "https://hf-mirror.com")!, root: resources.appendingPathComponent("BundledModels"))
            .cachedSnapshot(repository: repository, verifyContents: verifyContents)
    }
    let endpoint: URL
    let root: URL
    init(endpoint: URL, root: URL? = nil) {
        self.endpoint = endpoint
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("LinguaMac/Models")
    }
    struct Entry: Codable, Sendable {
        struct LFS: Codable, Sendable { let oid: String; let size: Int64 }
        let type: String
        let path: String
        let size: Int64?
        let lfs: LFS?
        var byteCount: Int64 { lfs?.size ?? size ?? 0 }
    }
    struct Manifest: Codable { let revision: String; let entries: [Entry]; var repository: String? = nil }
    func cachedSnapshot(repository: String, verifyContents: Bool = false) throws -> URL? {
        try cachedModel(repository: repository, verifyContents: verifyContents)?.0
    }
    private func cacheDirectory(endpoint: URL, repository: String) -> URL {
        let namespace = SHA256.hash(data: Data((endpoint.absoluteString + "/" + repository).utf8)).map { String(format: "%02x", $0) }.joined()
        return root.appendingPathComponent(namespace)
    }
    private func cachedModel(repository: String, verifyContents: Bool) throws -> (URL, Manifest)? {
        _ = try ModelDownloads.validateRepository(repository)
        // Older manifests identify their repository through the source-specific directory.
        let known = [endpoint, URL(string: "https://hf-mirror.com")!, URL(string: "https://huggingface.co")!]
            .map { cacheDirectory(endpoint: $0, repository: repository) }
        let other = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        for directory in known + other.filter({ !known.contains($0) }) {
            guard let data = try? Data(contentsOf: directory.appendingPathComponent(".lingua-manifest.json")),
                  let manifest = try? JSONDecoder().decode(Manifest.self, from: data),
                  (manifest.repository == repository || (manifest.repository == nil && known.contains(directory))),
                  !manifest.entries.isEmpty, manifest.revision.count == 40,
                  manifest.revision.allSatisfy({ $0.isHexDigit }) else { continue }
            let snapshot = directory.appendingPathComponent(manifest.revision)
            var complete = true
            for entry in manifest.entries {
                try Task.checkCancellation()
                try Self.validatePath(entry.path)
                let file = snapshot.appendingPathComponent(entry.path)
                if verifyContents {
                    if try !Self.validFile(file, entry: entry) { complete = false; break }
                } else {
                    let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .isSymbolicLinkKey])
                    if values?.isRegularFile != true || values?.isSymbolicLink == true || Int64(values?.fileSize ?? -1) != entry.byteCount {
                        complete = false; break
                    }
                }
            }
            if complete { return (snapshot, manifest) }
        }
        return nil
    }

    static func validatePath(_ path: String) throws {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\"),
              !path.split(separator: "/", omittingEmptySubsequences: false).contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }),
              !path.contains(where: { $0.isNewline }) else {
            throw TranslationError.backend("模型仓库包含不安全的文件路径。")
        }
    }
    static func validFile(_ url: URL, entry: Entry) throws -> Bool {
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .isSymbolicLinkKey])
        guard values?.isRegularFile == true, values?.isSymbolicLink != true,
              Int64(values?.fileSize ?? -1) == entry.byteCount else { return false }
        if let lfs = entry.lfs {
            guard let stream = InputStream(url: url) else { return false }
            stream.open(); defer { stream.close() }
            var hash = SHA256()
            var buffer = [UInt8](repeating: 0, count: 1024 * 1024)
            while true {
                try Task.checkCancellation()
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count >= 0 else { throw stream.streamError ?? TranslationError.backend("无法校验模型文件。") }
                if count == 0 { break }
                hash.update(data: Data(buffer.prefix(count)))
            }
            return hash.finalize().map { String(format: "%02x", $0) }.joined() == lfs.oid
        }
        return true
    }

    func download(repository: String, progress: @escaping @Sendable (ModelDownloadStatus) -> Void) async throws -> URL {
        _ = try ModelDownloads.validateRepository(repository)
        let directory = cacheDirectory(endpoint: endpoint, repository: repository)
        let manifestURL = directory.appendingPathComponent(".lingua-manifest.json")
        progress(ModelDownloadStatus())
        if try cachedSnapshot(repository: repository) != nil {
            progress(.init(phase: .verifying, file: "校验本机缓存"))
        }
        // A complete, verified local snapshot can load offline.
        if let (cachedSnapshot, manifest) = try cachedModel(repository: repository, verifyContents: true) {
            let total = manifest.entries.reduce(Int64(0)) { $0 + $1.byteCount }
            progress(.init(phase: .loading, completed: total, total: total, cached: total))
            return cachedSnapshot
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCredentialStorage = nil
        configuration.httpCookieStorage = nil
        configuration.timeoutIntervalForRequest = 60
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        struct Info: Decodable { let sha: String }
        let api = endpoint.appendingPathComponent("api/models").appendingPathComponent(repository)
        let info: Info = try await json(session: session, url: api.appendingPathComponent("revision/main"))
        guard info.sha.count == 40, info.sha.allSatisfy({ $0.isHexDigit }) else { throw TranslationError.backend("下载源返回了无效的模型版本。") }
        let snapshot = directory.appendingPathComponent(info.sha)
        try FileManager.default.createDirectory(at: snapshot, withIntermediateDirectories: true)
        var components = URLComponents(url: api.appendingPathComponent("tree").appendingPathComponent(info.sha), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "recursive", value: "true")]
        let all: [Entry] = try await json(session: session, url: components.url!)
        let entries = all.filter { $0.type == "file" && ["json", "safetensors", "txt", "model", "jinja"].contains(URL(fileURLWithPath: $0.path).pathExtension.lowercased()) }
        guard entries.contains(where: { $0.path == "config.json" }), entries.contains(where: { $0.path.hasSuffix(".safetensors") }), entries.contains(where: { $0.path == "tokenizer.json" || $0.path.hasSuffix(".model") }) else {
            throw TranslationError.backend("仓库缺少模型配置、权重或分词器文件，请选择完整的 MLX 模型仓库。")
        }
        var status = ModelDownloadStatus(phase: .downloading, total: entries.reduce(Int64(0)) { $0 + $1.byteCount })
        for entry in entries.sorted(by: { $0.byteCount < $1.byteCount }) {
            try Task.checkCancellation()
            try Self.validatePath(entry.path)
            guard entry.byteCount > 0 else { throw TranslationError.backend("下载源未提供 \(entry.path) 的文件大小。") }
            let destination = snapshot.appendingPathComponent(entry.path)
            status.file = entry.path
            if try Self.validFile(destination, entry: entry) {
                status.completed += entry.byteCount; status.cached += entry.byteCount; status.speed = 0
                progress(status); continue
            }
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            let url = endpoint.appendingPathComponent(repository).appendingPathComponent("resolve").appendingPathComponent(info.sha).appendingPathComponent(entry.path)
            var request = URLRequest(url: url)
            request.timeoutInterval = 180
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let delegate = TransferProgress(base: status, progress: progress)
            progress(status)
            let temp: URL
            let response: URLResponse
            do { (temp, response) = try await delegate.download(request) }
            catch {
                if Task.isCancelled { throw CancellationError() }
                throw TranslationError.backend("下载 \(entry.path) 失败：\(error.localizedDescription)。重试会复用已完成文件。")
            }
            defer { try? FileManager.default.removeItem(at: temp) }
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw TranslationError.backend("下载 \(entry.path) 返回 HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)，请重试或更换下载源。")
            }
            status.phase = .verifying; status.speed = 0; status.completed += entry.byteCount
            progress(status)
            guard try Self.validFile(temp, entry: entry) else { throw TranslationError.backend("\(entry.path) 大小或校验值不匹配，请重试下载。") }
            if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
            try FileManager.default.moveItem(at: temp, to: destination)
            status.phase = .downloading
        }
        let manifest = Manifest(revision: info.sha, entries: entries, repository: repository)
        // Manifest lives beside the files: only publish it after every file verifies.
        try JSONEncoder().encode(manifest).write(to: snapshot.appendingPathComponent(".lingua-manifest.json"), options: .atomic)
        try JSONEncoder().encode(manifest).write(to: manifestURL, options: .atomic)
        status.phase = .loading; status.speed = 0; progress(status)
        return snapshot
    }

    private func json<T: Decodable>(session: URLSession, url: URL) async throws -> T {
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw TranslationError.backend("获取模型信息失败（HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)）。请检查下载源和仓库 ID。")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

private final class TransferProgress: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let base: ModelDownloadStatus
    private let progress: @Sendable (ModelDownloadStatus) -> Void
    private let lock = NSLock()
    private var lastTime = ProcessInfo.processInfo.systemUptime
    private var lastBytes: Int64 = 0
    init(base: ModelDownloadStatus, progress: @escaping @Sendable (ModelDownloadStatus) -> Void) { self.base = base; self.progress = progress }
    private var continuation: CheckedContinuation<(URL, URLResponse), any Error>?
    private var downloadedFile: URL?
    private var fileError: (any Error)?

    func download(_ request: URLRequest) async throws -> (URL, URLResponse) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCredentialStorage = nil
        configuration.httpCookieStorage = nil
        configuration.timeoutIntervalForRequest = 180
        configuration.timeoutIntervalForResource = 6 * 60 * 60
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if Task.isCancelled { continuation.resume(throwing: CancellationError()); return }
                self.continuation = continuation
                session.downloadTask(with: request).resume()
            }
        } onCancel: { session.invalidateAndCancel() }
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // URLSession removes its temporary file when this callback returns.
        let preserved = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do { try FileManager.default.moveItem(at: location, to: preserved); downloadedFile = preserved }
        catch { fileError = error }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        guard let continuation else { return }
        self.continuation = nil
        if let failure = error ?? fileError {
            if let downloadedFile { try? FileManager.default.removeItem(at: downloadedFile) }
            continuation.resume(throwing: failure)
        } else if let downloadedFile, let response = task.response {
            continuation.resume(returning: (downloadedFile, response))
        } else { continuation.resume(throwing: TranslationError.backend("下载未返回模型文件。")) }
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        lock.lock()
        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = now - lastTime
        guard elapsed >= 0.25 else { lock.unlock(); return }
        var value = base
        value.completed += totalBytesWritten
        value.speed = Double(max(0, totalBytesWritten - lastBytes)) / elapsed
        lastTime = now; lastBytes = totalBytesWritten
        lock.unlock()
        progress(value)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(request.url?.scheme == "https" ? request : nil)
    }
}
