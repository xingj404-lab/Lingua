import AppKit
import SwiftUI

/// Keeps the placeholder and insertion point in the same AppKit text coordinate system.
struct TranslationTextEditor: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let editable: Bool
    let label: String
    var onSubmit: (() -> Void)? = nil
    var onPasteImage: ((NSPasteboard) -> Bool)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay

        let view = PlaceholderTextView(frame: .zero)
        view.isRichText = false
        view.importsGraphics = false
        view.allowsUndo = true
        view.drawsBackground = false
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        view.minSize = .zero
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.textContainer?.widthTracksTextView = true
        view.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        view.textContainerInset = NSSize(width: 6, height: 8)
        view.textContainer?.lineFragmentPadding = 0
        view.font = .systemFont(ofSize: CC.editorSize)
        view.textColor = .labelColor
        view.insertionPointColor = .labelColor
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 5
        view.defaultParagraphStyle = paragraph
        view.typingAttributes = [.font: NSFont.systemFont(ofSize: CC.editorSize), .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph]
        view.delegate = context.coordinator
        view.onSubmit = onSubmit
        view.onPasteImage = onPasteImage
        view.focusesWhenAttached = onSubmit != nil
        view.setAccessibilityLabel(label)
        scroll.documentView = view
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? PlaceholderTextView else { return }
        context.coordinator.text = $text
        view.placeholder = placeholder
        view.isEditable = editable
        view.onSubmit = onSubmit
        view.onPasteImage = onPasteImage
        // Do not interrupt an input method's marked text during SwiftUI updates.
        if view.string != text && !view.hasMarkedText() {
            let selection = view.selectedRange()
            view.string = text
            view.setSelectedRange(NSRange(location: min(selection.location, (text as NSString).length), length: 0))
            view.undoManager?.removeAllActions()
        }
        view.needsDisplay = true
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        init(text: Binding<String>) { self.text = text }
        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            text.wrappedValue = view.string
            view.needsDisplay = true
        }
    }
}

final class PlaceholderTextView: NSTextView {
    var placeholder = ""
    var onSubmit: (() -> Void)?
    var onPasteImage: ((NSPasteboard) -> Bool)?
    var focusesWhenAttached = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if focusesWhenAttached, let window {
            window.makeFirstResponder(self)
            focusesWhenAttached = false
        }
    }

    override func paste(_ sender: Any?) {
        guard isEditable else { return }
        if onPasteImage?(NSPasteboard.general) == true { return }
        super.paste(sender)
    }

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.shift, .control, .option, .command])
        if (event.keyCode == 36 || event.keyCode == 76), modifiers.isEmpty,
           !hasMarkedText(), isEditable, let onSubmit {
            onSubmit()
            return
        }
        super.keyDown(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !hasMarkedText(), let container = textContainer else { return }
        var attributes = typingAttributes
        attributes[.foregroundColor] = NSColor.placeholderTextColor
        let storage = NSTextStorage(string: placeholder, attributes: attributes)
        let layout = NSLayoutManager()
        let placeholderContainer = NSTextContainer(size: container.containerSize)
        placeholderContainer.lineFragmentPadding = container.lineFragmentPadding
        storage.addLayoutManager(layout)
        layout.addTextContainer(placeholderContainer)
        let glyphs = layout.glyphRange(for: placeholderContainer)
        // Same origin, font, paragraph style and padding as the editable text/caret.
        layout.drawGlyphs(forGlyphRange: glyphs, at: textContainerOrigin)
    }
}
