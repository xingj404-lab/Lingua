import Foundation

public enum TranslationDirectionMode: String, CaseIterable, Sendable, Identifiable {
    case bidirectional, fixed
    public var id: String { rawValue }
    public var title: String { self == .bidirectional ? "自动双向" : "固定方向" }
}

public struct TranslationDirection: Sendable, Equatable {
    public let source: Language
    public let target: Language
    public let detected: Bool
    public static func resolve(detected: Language?, mine: Language, partner: Language, override: Language? = nil) -> Self {
        let source = detected ?? .auto
        let target = override ?? (source == .auto || source == mine ? partner : mine)
        return .init(source: source, target: target, detected: source != .auto)
    }
}
