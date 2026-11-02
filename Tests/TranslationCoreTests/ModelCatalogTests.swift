import XCTest
@testable import TranslationCore

final class ModelCatalogTests: XCTestCase {
    func testWarmupUsesTheSameSamplingPathAsTranslation() {
        for family: NativeTranslationPrompt.Family in [.hunyuan, .general] {
            let live = NativeSamplingPolicy(family: family)
            let warm = NativeSamplingPolicy(family: family, maxTokens: 16)
            XCTAssertEqual(warm.temperature, live.temperature)
            XCTAssertGreaterThan(warm.temperature, 0)
            XCTAssertEqual(warm.topP, live.topP)
            XCTAssertEqual(warm.topK, live.topK)
            XCTAssertEqual(warm.repetitionPenalty, live.repetitionPenalty)
            XCTAssertLessThan(warm.maxTokens, live.maxTokens)
        }
    }
    func testRetiredModelMigratesAndExistingChoicesArePreserved() {
        XCTAssertEqual(LocalModelPreset.preferredRepository(saved: nil), LocalModelPreset.recommendedID)
        XCTAssertEqual(LocalModelPreset.preferredRepository(saved: "mlx-community/HY-MT1.5-1.8B-4bit"), LocalModelPreset.recommendedID)
        XCTAssertEqual(LocalModelPreset.preferredRepository(saved: "mlx-community/Qwen3-4B-4bit"), "mlx-community/Qwen3-4B-4bit")
        XCTAssertEqual(LocalModelPreset.preferredRepository(saved: "my/model"), LocalModelPreset.recommendedID)
        XCTAssertNil(LocalModelPreset.find("mlx-community/HY-MT1.5-1.8B-4bit"))
    }
    func testHunyuanUsesTranslationPromptAndOnlyRelevantTerms() {
        let request = TranslationRequest(text: "缓存命中率是 95%。", options: .init(target: .en), glossary: [
            .init(source: "缓存", target: "cache"), .init(source: "数据库", target: "database")
        ])
        let prompt = NativeTranslationPrompt(request: request, family: .hunyuan)
        XCTAssertNil(prompt.instructions)
        XCTAssertTrue(prompt.text.contains("缓存 翻译成 cache"))
        XCTAssertFalse(prompt.text.contains("database"))
        XCTAssertTrue(prompt.text.hasSuffix(request.text))
        XCTAssertTrue(prompt.text.contains("翻译为英语"))
        XCTAssertFalse(prompt.text.contains("/no_think"))
    }
    func testNonChineseHunyuanAndGeneralModelPrompts() {
        let request = TranslationRequest(text: "Hello", options: .init(source: .en, target: .fr, domain: .legal, tone: .formal), glossary: [])
        let hy = NativeTranslationPrompt(request: request, family: .hunyuan)
        XCTAssertTrue(hy.text.contains("into French"))
        XCTAssertTrue(hy.text.contains(Domain.legal.instruction))
        XCTAssertTrue(hy.text.contains(Tone.formal.instruction))
        let general = NativeTranslationPrompt(request: request, family: .general)
        XCTAssertEqual(general.instructions, request.instructions)
        XCTAssertEqual(general.text, request.prompt)
    }
}
