import XCTest
@testable import TranslationCore

final class InterfaceLocalizationTests: XCTestCase {
    func testSystemLanguageResolution() {
        XCTAssertEqual(InterfaceLanguage.resolve(["ja-JP", "en-US"]), .japanese)
        XCTAssertEqual(InterfaceLanguage.resolve(["ko_KR"]), .korean)
        XCTAssertEqual(InterfaceLanguage.resolve(["zh-TW"]), .chinese)
        XCTAssertEqual(InterfaceLanguage.resolve(["de-DE", "en-GB"]), .english)
        XCTAssertEqual(InterfaceLanguage.resolve([]), .english)
    }
    func testCatalogIsCompleteAndPreservesFormatArguments() {
        for key in L10n.keys {
            for language in [InterfaceLanguage.english, .japanese, .korean] {
                XCTAssertTrue(L10n.hasTranslation(key, language: language), "Missing \(language): \(key)")
                let translated = L10n.text(key, language: language)
                XCTAssertEqual(translated.components(separatedBy: "%@").count,
                               key.components(separatedBy: "%@").count, "Changed arguments: \(key)")
            }
        }
    }
    func testDynamicStatusAndModelIDs() {
        XCTAssertEqual(L10n.text("翻译第 2 / 4 段", language: .english), "Translating part 2 / 4")
        XCTAssertEqual(L10n.text("上次结果：英语", language: .japanese), "前回の結果：英語")
        XCTAssertEqual(L10n.text("12 字符", language: .korean), "12자")
        XCTAssertEqual(L10n.text("术语待核对：翻译 → 译文", language: .english), "Check term: 翻译 → 译文")
        XCTAssertEqual(L10n.text("数字待核对：123", language: .japanese), "数字を確認：123")
        XCTAssertEqual(L10n.text("mlx-community/Hy-MT2-1.8B-4bit", language: .korean), "mlx-community/Hy-MT2-1.8B-4bit")
        XCTAssertEqual(L10n.text("unrecognized API response", language: .japanese), "unrecognized API response")
        XCTAssertEqual(L10n.text("翻译完成", language: .chinese), "翻译完成")
    }
    func testTranslationLanguageAndPromptsAreIndependent() {
        XCTAssertEqual(L10n.text(Language.en.title, language: .japanese), "英語")
        XCTAssertEqual(Language.en.title, "英语")
        let request = TranslationRequest(text: "你好", options: .init(source: .zh, target: .en), glossary: [])
        XCTAssertTrue(request.instructions.contains("into English"))
        XCTAssertEqual(request.text, "你好")
    }
}
