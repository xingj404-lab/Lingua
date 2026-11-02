import XCTest
@testable import TranslationCore

final class TranslationTests: XCTestCase {
    func testSegmentationPreservesAllUnicodeAndWhitespace() {
        let text = String(repeating: "技术文档👩🏽‍💻：版本 2.1，需要 512 MB。\n\n", count: 180) + "尾段\n"
        let parts = TranslationPlanning.segments(text)
        XCTAssertEqual(parts.joined(), text)
        XCTAssertTrue(parts.allSatisfy { $0.count <= 1200 && !$0.isEmpty })
        XCTAssertGreaterThan(parts.count, 1)
    }
    func testLongUnbrokenInputIsBounded() {
        let text = String(repeating: "x", count: 6001)
        let parts = TranslationPlanning.segments(text)
        XCTAssertEqual(parts.joined(), text)
        XCTAssertEqual(parts.count, 6)
    }
    func testInvalidRequestsFailBeforeInference() {
        XCTAssertThrowsError(try TranslationPlanning.validate(.init(text: " \n", options: .init(), glossary: [])))
        XCTAssertThrowsError(try TranslationPlanning.validate(.init(text: String(repeating: "a", count: 24001), options: .init(), glossary: [])))
        XCTAssertThrowsError(try TranslationPlanning.validate(.init(text: "文档", options: .init(source: .zh, target: .zh), glossary: [])))
    }
    func testAPIEndpointsRequireHTTPSExceptLoopback() throws {
        XCTAssertEqual(try TranslationPlanning.apiEndpoint("http://127.0.0.1:8080/v1").host, "127.0.0.1")
        XCTAssertEqual(try TranslationPlanning.apiEndpoint(" https://llm.example.com/v1/ ").host, "llm.example.com")
        XCTAssertEqual(try TranslationPlanning.apiEndpoint("http://[::1]:8080/v1").port, 8080)
        for value in ["http://example.com/v1", "http://127.0.0.1.example.com/v1", "https://user@example.com/v1", "file:///tmp/test", "http://localhost/v1?destination=cloud", "https://example.com/v1#secret", "https://example.com/v1/chat/completions", "https://example.com:99999/v1", "https://example.com/api path"] {
            XCTAssertThrowsError(try TranslationPlanning.apiEndpoint(value), value)
        }
    }
    func testRequiredTermsOnlyMatchTheCurrentSegment() {
        let request = TranslationRequest(text: "The API needs unified memory.", options: .init(domain: .technical),
            glossary: [.init(source: "unified memory", target: "统一内存"), .init(source: "contract", target: "合同")])
        XCTAssertTrue(request.instructions.contains("unified memory → 统一内存"))
        XCTAssertFalse(request.instructions.contains("contract → 合同"))
        XCTAssertTrue(request.instructions.contains("technical terminology"))
    }
    func testReviewDetectsMissingNumbersAndTerms() {
        let issues = TranslationReview.issues(source: "API requires 512 MB", target: "接口需要内存", glossary: [.init(source: "API", target: "应用程序接口")])
        XCTAssertEqual(issues.count, 2)
        XCTAssertTrue(issues.contains { $0.message.contains("512") })
        XCTAssertTrue(TranslationReview.issues(source: "API requires 512 MB", target: "应用程序接口需要 512 MB", glossary: [.init(source: "API", target: "应用程序接口")]).isEmpty)
    }
    func testWorkspaceRoundTripAndCorruptDataIsNotOverwritten() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = WorkspaceStore(url: folder.appendingPathComponent("workspace.json"))
        var data = try store.load()
        data.glossary = [.init(source: "API", target: "接口")]
        data.history = [.init(source: "Hello", translation: "你好", options: .init(), engine: "test")]
        try store.save(data)
        let loaded = try store.load()
        XCTAssertEqual(loaded.glossary, data.glossary)
        XCTAssertEqual(loaded.history.first?.translation, "你好")
        let bad = Data("corrupt".utf8)
        try bad.write(to: store.url)
        XCTAssertThrowsError(try store.load())
        XCTAssertEqual(try Data(contentsOf: store.url), bad)
    }
}
