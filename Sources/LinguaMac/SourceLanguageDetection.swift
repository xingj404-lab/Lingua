import Foundation
import NaturalLanguage
import TranslationCore

enum SourceLanguageDetection {
    static func detect(_ text: String) -> Language? {
        let sample = String(text.prefix(2000))
        guard sample.unicodeScalars.contains(where: { CharacterSet.letters.contains($0) }) else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(sample)
        guard let language = recognizer.dominantLanguage else { return nil }
        switch language {
        case .simplifiedChinese, .traditionalChinese: return .zh
        case .english: return .en
        case .japanese: return .ja
        case .korean: return .ko
        case .french: return .fr
        case .german: return .de
        case .spanish: return .es
        default: return nil
        }
    }
}
