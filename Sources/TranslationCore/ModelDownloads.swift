import Foundation

public enum ModelDownloadSource: String, CaseIterable, Identifiable, Sendable {
    case official = "Hugging Face 官方"
    case mirror = "HF-Mirror 国内镜像"
    case custom = "自定义下载源"
    public var id: String { rawValue }
    public func endpoint(custom: String = "") throws -> URL {
        switch self {
        case .official: return URL(string: "https://huggingface.co")!
        case .mirror: return URL(string: "https://hf-mirror.com")!
        case .custom: return try ModelDownloads.validateEndpoint(custom)
        }
    }
}

public enum ModelDownloads {
    public static func validateEndpoint(_ value: String) throws -> URL {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme == "https", let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.path.isEmpty || url.path == "/" else {
            throw TranslationError.backend("下载源须为 HTTPS 根地址，例如 https://hf-mirror.com，不要附带模型路径或登录信息。")
        }
        return url
    }
    public static func validateRepository(_ value: String) throws -> String {
        let id = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let regex = try! NSRegularExpression(pattern: #"^[A-Za-z0-9][A-Za-z0-9._-]*/[A-Za-z0-9][A-Za-z0-9._-]*$"#)
        guard regex.firstMatch(in: id, range: NSRange(id.startIndex..., in: id)) != nil else {
            throw TranslationError.backend("模型仓库格式应为「作者/模型名」，例如 mlx-community/Qwen3-4B-4bit。")
        }
        return id
    }
    public static func repositoryURL(endpoint: URL, repository: String, files: Bool = false) throws -> URL {
        let id = try validateRepository(repository)
        return endpoint.appendingPathComponent(id).appendingPathComponent(files ? "tree/main" : "")
    }
}
