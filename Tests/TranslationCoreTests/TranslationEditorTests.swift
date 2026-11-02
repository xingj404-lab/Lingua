import AppKit
import XCTest
@testable import LinguaMac

final class TranslationEditorTests: XCTestCase {
    @MainActor
    func testImagePasteIsHandledAndPlainTextPasteStillEditsText() {
        _ = NSApplication.shared
        let board = NSPasteboard.general
        let saved = (board.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        }
        defer {
            board.clearContents()
            let items = saved.map { values in
                let item = NSPasteboardItem()
                for (type, data) in values { item.setData(data, forType: type) }
                return item
            }
            board.writeObjects(items)
        }
        let view = PlaceholderTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        view.isEditable = true; view.isRichText = false
        view.string = "Original"
        var imagePasteCount = 0
        view.onPasteImage = { _ in imagePasteCount += 1; return true }
        view.paste(nil)
        XCTAssertEqual(imagePasteCount, 1)
        XCTAssertEqual(view.string, "Original", "Handled image paste must not insert text or attachments")
        board.clearContents(); board.setString(" hello", forType: .string)
        view.onPasteImage = { _ in false }
        view.setSelectedRange(NSRange(location: 8, length: 0))
        view.paste(nil)
        XCTAssertEqual(view.string, "Original hello")
        view.isEditable = false
        view.paste(nil)
        XCTAssertEqual(view.string, "Original hello")
    }

    @MainActor
    func testReturnSubmitsSourceAndShiftReturnInsertsNewline() throws {
        _ = NSApplication.shared
        let view = PlaceholderTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        let window = NSWindow(contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = view
        window.makeFirstResponder(view)
        view.isEditable = true
        view.string = "Hello"
        view.setSelectedRange(NSRange(location: 5, length: 0))
        var submitted = 0
        view.onSubmit = { submitted += 1 }
        func enter(_ modifiers: NSEvent.ModifierFlags = [], keyCode: UInt16 = 36) throws -> NSEvent {
            try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
                timestamp: 0, windowNumber: 0, context: nil, characters: "\r",
                charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: keyCode))
        }
        view.keyDown(with: try enter())
        XCTAssertEqual(submitted, 1)
        XCTAssertEqual(view.string, "Hello")
        view.keyDown(with: try enter(keyCode: 76))
        XCTAssertEqual(submitted, 2)
        view.keyDown(with: try enter(.shift))
        XCTAssertEqual(submitted, 2)
        XCTAssertEqual(view.string, "Hello\n")
        // The translation output has no submit callback and retains normal editing.
        view.onSubmit = nil
        view.keyDown(with: try enter())
        XCTAssertEqual(view.string, "Hello\n\n")
        view.onSubmit = { submitted += 1 }
        view.setMarkedText("拼音", selectedRange: NSRange(location: 2, length: 0),
                           replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertTrue(view.hasMarkedText())
        view.keyDown(with: try enter())
        XCTAssertEqual(submitted, 2, "Confirming input method text must not submit translation")
    }
}
