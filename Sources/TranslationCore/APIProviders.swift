import Foundation

public enum APIProvider: String, CaseIterable, Identifiable, Sendable {
    case openAI, deepSeek, custom
    public var id: String { rawValue }
    public var title: String {
        switch self { case .openAI: "OpenAI（ChatGPT）"; case .deepSeek: "DeepSeek"; case .custom: "自定义" }
    }
    public var endpoint: String {
        switch self { case .openAI: "https://api.openai.com/v1"; case .deepSeek: "https://api.deepseek.com"; case .custom: "" }
    }
    public var keyURL: URL? {
        switch self { case .openAI: URL(string: "https://platform.openai.com/api-keys"); case .deepSeek: URL(string: "https://platform.deepseek.com/api_keys"); case .custom: nil }
    }
    public var help: String {
        switch self {
        case .openAI: "填写模型 ID 和 OpenAI API Key。ChatGPT 订阅与 API 额度分别计费。"
        case .deepSeek: "填写模型 ID 和 DeepSeek API Key，默认使用非思考模式翻译。"
        case .custom: "填写服务商提供的 API 根地址、模型 ID 和 API Key，需兼容 OpenAI 接口。"
        }
    }
    public static func restored(rawValue: String?, endpoint: String) -> Self {
        // The retired local profile becomes Custom while preserving its saved endpoint/model.
        if rawValue == "local" { return .custom }
        return rawValue.flatMap(Self.init(rawValue:)) ?? identify(endpoint: endpoint)
    }
    public static func identify(endpoint: String) -> Self {
        guard let url = URL(string: endpoint) else { return .custom }
        if url.host == "api.openai.com" && url.path == "/v1" { return .openAI }
        if url.host == "api.deepseek.com" && ["", "/", "/v1"].contains(url.path) { return .deepSeek }
        return .custom
    }
}
