import XCTest
import AppKit
import CoreText
import ImageIO
import UniformTypeIdentifiers
@testable import LinguaMac

final class OCRTests: XCTestCase {
    func testVisionRecognizesARealImage() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: url) }
        let context = CGContext(data: nil, width: 1600, height: 240, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 1600, height: 240))
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, 64, nil),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1)
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: "Translation memory requires 512 MB.", attributes: attributes))
        context.textPosition = CGPoint(x: 50, y: 95); CTLineDraw(line, context)
        let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let result = try await OCRService().recognize(url: url)
        XCTAssertTrue(result.text.contains("512"), result.text)
        XCTAssertTrue(result.text.localizedCaseInsensitiveContains("Translation memory"), result.text)
    }
    @MainActor
    func testClipboardBitmapIsRecognizedAndKeepsOriginalForPreview() async throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 1200, height: 200,
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 1200, height: 200))
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: "Clipboard image 512", attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, 64, nil),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1)
        ]))
        context.textPosition = CGPoint(x: 40, y: 80); CTLineDraw(line, context)
        let image = NSImage(cgImage: try XCTUnwrap(context.makeImage()), size: NSSize(width: 1200, height: 200))
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.writeObjects([image])
        let workspace = Workspace()
        XCTAssertTrue(workspace.pasteImage(board))
        for _ in 0..<200 where workspace.busy { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertFalse(workspace.busy)
        XCTAssertNil(workspace.error)
        XCTAssertTrue(workspace.source.contains("512"), workspace.source)
        XCTAssertEqual(workspace.originalImage?.size.width, 1200)
        XCTAssertNotNil(workspace.imagePreview)
        XCTAssertNil(workspace.imageURL, "Temporary clipboard files are not retained")
        workspace.removeImage()
        XCTAssertNil(workspace.originalImage)
        XCTAssertTrue(workspace.source.contains("512"), "Removing the attachment retains recognized text")
        board.clearContents(); board.setString("Plain text", forType: .string)
        XCTAssertFalse(workspace.pasteImage(board))
    }

    func testInvalidImageProducesActionableFailure() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("invalid".utf8).write(to: url)
        do {
            _ = try await OCRService().recognize(url: url)
            XCTFail("Invalid image should fail")
        } catch { XCTAssertTrue(error.localizedDescription.contains("图片")) }
    }
    func testNativeEngineRejectsTranslationUntilLoaded() async throws {
        let engine = NativeModelEngine()
        do {
            _ = try await engine.translate(.init(text: "Hello", options: .init(), glossary: []), expectedID: "unused") { _ in }
            XCTFail("Translation must require a loaded model")
        } catch { XCTAssertTrue(error.localizedDescription.contains("模型")) }
    }
}
