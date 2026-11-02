import XCTest
@testable import TranslationCore
@testable import LinguaMac

final class TranslationDirectionTests: XCTestCase {
    func testAlternatingMessagesResolveInBothDirections() {
        XCTAssertEqual(TranslationDirection.resolve(detected: .zh, mine: .zh, partner: .en).target, .en)
        XCTAssertEqual(TranslationDirection.resolve(detected: .en, mine: .zh, partner: .en).target, .zh)
        XCTAssertEqual(TranslationDirection.resolve(detected: .ja, mine: .ja, partner: .en).target, .en)
        XCTAssertEqual(TranslationDirection.resolve(detected: .en, mine: .ja, partner: .en).target, .ja)
        XCTAssertEqual(TranslationDirection.resolve(detected: .fr, mine: .zh, partner: .en).target, .zh)
    }
    func testUnknownTextAndExplicitOverride() {
        let unknown = TranslationDirection.resolve(detected: nil, mine: .zh, partner: .en)
        XCTAssertFalse(unknown.detected)
        XCTAssertEqual(unknown.source, .auto)
        XCTAssertEqual(unknown.target, .en)
        XCTAssertEqual(TranslationDirection.resolve(detected: .en, mine: .zh, partner: .en, override: .en).target, .en)
    }
    func testNativeLanguageDetectionForChatMessages() {
        XCTAssertEqual(SourceLanguageDetection.detect("我现在已经提交了，请确认收到。"), .zh)
        XCTAssertEqual(SourceLanguageDetection.detect("What version did you submit?"), .en)
        XCTAssertEqual(SourceLanguageDetection.detect("你好，App 的版本是 v1.2.3。"), .zh)
        XCTAssertNil(SourceLanguageDetection.detect("12345 👍"))
    }
}
