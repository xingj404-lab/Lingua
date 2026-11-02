import SwiftUI
import AppKit
import TranslationCore

/// Uses the original bitmap, not the small OCR attachment thumbnail.
struct ImagePreviewView: View {
    let image: NSImage
    let name: String
    @Environment(\.dismiss) private var dismiss
    @State private var zoom = 1.0

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Spacer()
                Button(L10n.text("适合窗口")) { zoom = 1 }.buttonStyle(QuietButtonStyle())
                Slider(value: $zoom, in: 1...5).frame(width: 120)
                    .accessibilityLabel(L10n.text("缩放图片"))
                Text("\(Int(zoom * 100))%").font(.system(size: 11).monospacedDigit()).frame(width: 38)
                Button { dismiss() } label: { Image(systemName: "xmark") }
                    .buttonStyle(QuietButtonStyle()).help(L10n.text("关闭"))
                    .accessibilityLabel(L10n.text("关闭")).keyboardShortcut(.cancelAction)
            }.padding(14)
            Divider()
            GeometryReader { geometry in
                let scale = min(geometry.size.width / max(image.size.width, 1),
                                geometry.size.height / max(image.size.height, 1))
                let size = CGSize(width: image.size.width * scale * zoom,
                                  height: image.size.height * scale * zoom)
                ScrollView([.horizontal, .vertical]) {
                    Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
                        .frame(width: size.width, height: size.height)
                        .frame(minWidth: geometry.size.width, minHeight: geometry.size.height)
                }
            }.padding(16).background(Color(nsColor: .underPageBackgroundColor))
        }.frame(width: 860, height: 620)
    }
}
