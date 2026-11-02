import AppKit
import SwiftUI
import TranslationCore

@MainActor
enum BrandAssets {
    static let appIcon: NSImage = {
        #if SWIFT_PACKAGE
        let resources = Bundle.module
        #else
        let resources = Bundle.main
        #endif
        guard let url = resources.url(forResource: "AppIcon", withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            preconditionFailure("The application icon resource is missing from the app bundle.")
        }
        image.isTemplate = false
        return image
    }()
}

struct BrandLogo: View {
    var size: CGFloat = 36
    var body: some View {
        Image(nsImage: BrandAssets.appIcon).resizable().scaledToFit()
            .frame(width: size, height: size).accessibilityLabel(L10n.text("Lingua 标志"))
    }
}
