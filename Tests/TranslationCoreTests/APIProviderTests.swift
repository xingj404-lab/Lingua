import XCTest
@testable import TranslationCore
@testable import LinguaMac

final class APIProviderTests: XCTestCase {
    func testLocalProfileIsRetiredWithoutChangingCustomEndpointSupport() throws {
        XCTAssertEqual(APIProvider.allCases, [.openAI, .deepSeek, .custom])
        XCTAssertEqual(APIProvider.restored(rawValue: "local", endpoint: "http://127.0.0.1:1234/v1"), .custom)
        XCTAssertEqual(APIProvider.identify(endpoint: "http://127.0.0.1:1234/v1"), .custom)
        XCTAssertEqual(try TranslationPlanning.apiEndpoint("http://127.0.0.1:1234/v1").host, "127.0.0.1")
    }
    func testPresetsBuildCorrectRequestsAndDeepSeekDisablesThinking() throws {
        let text = TranslationRequest(text: "Hello", options: .init(), glossary: [])
        for provider in [APIProvider.openAI, .deepSeek] {
            let modelID = provider == .deepSeek ? "deepseek-v4-user-selected" : "user-selected-model"
            let request = try APIServiceEngine(endpoint: provider.endpoint, model: modelID, apiKey: "test-key").makeURLRequest(text)
            XCTAssertEqual(request.url?.host, provider == .openAI ? "api.openai.com" : "api.deepseek.com")
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
            XCTAssertEqual(body["model"] as? String, modelID)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
            if provider == .deepSeek { XCTAssertEqual((body["thinking"] as? [String: String])?["type"], "disabled") }
            else { XCTAssertNil(body["thinking"]) }
        }
        let custom = try APIServiceEngine(endpoint: "https://example.com/v1", model: "deepseek-flash").makeURLRequest(text)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(custom.httpBody)) as? [String: Any])
        XCTAssertNil(body["thinking"])
    }
}
