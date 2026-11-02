import Foundation

/// Curated MLX repositories; sizes are download estimates, not runtime memory requirements.
public struct LocalModelPreset: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let downloadBytes: Int64
    public let summary: String
    public let category: String
    public static let recommendedID = "mlx-community/Hy-MT2-1.8B-4bit"
    public static let all: [Self] = [
        .init(id: recommendedID, title: "Hy-MT2-1.8B-4bit", downloadBytes: 1_017_375_718,
              summary: "默认推荐。专为多语种翻译训练，适合邮件、文档，以及需要指定术语或语气的译文。无需另行下载。", category: "专用翻译 · 推荐"),
        .init(id: "mlx-community/Qwen3-0.6B-4bit", title: "Qwen3-0.6B-4bit", downloadBytes: 351_383_618,
              summary: "优先节省存储与运行内存时选择。适合简短消息、常用句子；复杂长句和专业术语建议使用内置翻译模型。", category: "通用模型 · 轻量"),
        .init(id: "mlx-community/Qwen3-1.7B-4bit", title: "Qwen3-1.7B-4bit", downloadBytes: 984_013_244,
              summary: "希望尝试通用模型的不同表达时选择。适合日常段落、邮件和多语言文字，体积介于 0.6B 与 4B 之间。", category: "通用模型 · 均衡"),
        .init(id: "mlx-community/Qwen3-4B-4bit", title: "Qwen3-4B-4bit", downloadBytes: 2_278_969_756,
              summary: "愿意增加存储与内存占用时，可尝试处理复杂句式和细致的表达要求。体积最大，适合有充足资源的 Mac。", category: "通用模型 · 较大")
    ]
    public static func preferredRepository(saved: String?) -> String {
        // Only models adapted and listed by the app can be restored.
        guard let saved, find(saved) != nil else { return recommendedID }
        return saved
    }
    public static func find(_ id: String) -> Self? { all.first { $0.id == id.trimmingCharacters(in: .whitespacesAndNewlines) } }
}

/// Hunyuan MT uses a user-only translation prompt, without Qwen's /no_think marker.
public struct NativeTranslationPrompt: Sendable {
    public enum Family: Sendable { case general, hunyuan }
    public let instructions: String?
    public let text: String
    public init(request: TranslationRequest, family: Family) {
        if family == .general { instructions = request.instructions; text = request.prompt; return }
        instructions = nil
        let terms = request.glossary.filter { !$0.source.isEmpty && request.text.localizedCaseInsensitiveContains($0.source) }
        let chinese = request.options.target == .zh || request.options.source == .zh || !terms.isEmpty ||
            (request.options.source == .auto && request.text.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) })
        var prefix = ""
        if !terms.isEmpty {
            prefix = chinese ? "参考下面的翻译：\n" : "Use the following terminology:\n"
            prefix += terms.map { chinese ? "\($0.source) 翻译成 \($0.target)" : "\($0.source) → \($0.target)" }.joined(separator: "\n") + "\n\n"
        }
        if request.options.domain != .general || request.options.tone != .faithful {
            prefix += "\(request.options.domain.instruction) \(request.options.tone.instruction)\n\n"
        }
        text = prefix + (chinese
            ? "将以下文本翻译为\(request.options.target.title)，注意只需要输出翻译后的结果，不要额外解释：\n\n\(request.text)"
            : "Translate the following text into \(request.options.target.englishName). Note that you should only output the translated result without any additional explanation:\n\n\(request.text)")
    }
}

/// Warmup and user requests must execute the same sampler operations.
public struct NativeSamplingPolicy: Sendable, Equatable {
    public let maxTokens: Int
    public let temperature: Float
    public let topP: Float
    public let topK: Int
    public let repetitionPenalty: Float?
    public init(family: NativeTranslationPrompt.Family, maxTokens: Int = 2048) {
        self.maxTokens = maxTokens
        temperature = family == .hunyuan ? 0.7 : 0.1
        topP = family == .hunyuan ? 0.6 : 1
        topK = family == .hunyuan ? 20 : 0
        repetitionPenalty = family == .hunyuan ? 1.05 : nil
    }
}
