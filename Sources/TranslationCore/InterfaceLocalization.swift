import Foundation

/// UI language is independent of source/target languages and persisted model choices.
public enum InterfaceLanguage: String, CaseIterable, Identifiable, Sendable {
    case system, chinese = "zh-Hans", english = "en", japanese = "ja", korean = "ko"
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .system: L10n.text("跟随系统")
        case .chinese: "简体中文"
        case .english: "English"
        case .japanese: "日本語"
        case .korean: "한국어"
        }
    }
    public static func resolve(_ preferences: [String]) -> Self {
        for identifier in preferences {
            let code = identifier.lowercased().replacingOccurrences(of: "_", with: "-")
            if code == "zh" || code.hasPrefix("zh-") { return .chinese }
            if code == "en" || code.hasPrefix("en-") { return .english }
            if code == "ja" || code.hasPrefix("ja-") { return .japanese }
            if code == "ko" || code.hasPrefix("ko-") { return .korean }
        }
        return .english
    }
    public var resolved: Self { self == .system ? Self.resolve(Locale.preferredLanguages) : self }
}

private final class LocalizationBundleMarker {}

public enum L10n {
    public static var language: InterfaceLanguage {
        (InterfaceLanguage(rawValue: UserDefaults.standard.string(forKey: "interfaceLanguage") ?? "system") ?? .system).resolved
    }
    private static let catalog: [String: [String]] = {
        #if SWIFT_PACKAGE
        let resources = Bundle.module
        #else
        let resources = Bundle(for: LocalizationBundleMarker.self)
        #endif
        guard let url = resources.url(forResource: "InterfaceStrings", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let strings = try? JSONDecoder().decode([String: [String]].self, from: data) else {
            preconditionFailure("Missing UI translations")
        }
        return strings
    }()
    private struct Template: @unchecked Sendable {
        // NSRegularExpression is immutable after construction and safe for concurrent matching.
        let key: String
        let expression: NSRegularExpression
    }
    private static let templates: [Template] = catalog.keys.filter { $0.contains("%@") }
        .sorted { $0.count > $1.count }.map { key in
            let segments = key.components(separatedBy: "%@").map(NSRegularExpression.escapedPattern(for:))
            return Template(key: key, expression: try! NSRegularExpression(pattern: "^" + segments.joined(separator: "(.*?)") + "$", options: [.dotMatchesLineSeparators]))
        }
    public static var keys: [String] { Array(catalog.keys) }
    public static func hasTranslation(_ key: String, language: InterfaceLanguage) -> Bool {
        guard let values = catalog[key], values.count == 3 else { return false }
        return !values[index(language.resolved)].isEmpty
    }
    private static func index(_ language: InterfaceLanguage) -> Int {
        switch language { case .japanese: 1; case .korean: 2; default: 0 }
    }
    /// App-owned UI messages only. Never pass source text, output or glossary content here.
    public static func text(_ value: String, language choice: InterfaceLanguage? = nil) -> String {
        let selected = (choice ?? language).resolved
        guard selected != .chinese else { return value }
        if let translated = catalog[value] { return translated[index(selected)] }
        for template in templates {
            guard let match = template.expression.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) else { continue }
            var result = catalog[template.key]![index(selected)]
            for number in 1..<match.numberOfRanges {
                guard let range = Range(match.range(at: number), in: value), let slot = result.range(of: "%@") else { continue }
                let captured = String(value[range])
                let translatesArgument = ["上次结果：%@", "正在加载本地模型 · %@", "正在下载模型 · %@", "%@ · 约 %@"].contains(template.key)
                let argument = translatesArgument ? (catalog[captured].map { $0[index(selected)] } ?? captured) : captured
                result.replaceSubrange(slot, with: argument)
            }
            return result
        }
        for prefix in catalog.keys.filter({ $0.hasSuffix("：") || $0.hasSuffix(" · ") }).sorted(by: { $0.count > $1.count }) {
            if value.hasPrefix(prefix) { return catalog[prefix]![index(selected)] + value.dropFirst(prefix.count) }
        }
        return value // Preserve service errors, model IDs and other unrecognized external text.
    }
}
