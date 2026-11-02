import SwiftUI
import TranslationCore

enum LegalDocument: String, Identifiable {
    case privacy, licenses
    var id: String { rawValue }
    var title: String { L10n.text(self == .privacy ? "隐私政策" : "开源许可") }
    var text: String {
        #if SWIFT_PACKAGE
        let resources = Bundle.module
        #else
        let resources = Bundle.main
        #endif
        guard let root = resources.resourceURL?.appendingPathComponent("Legal") else { return "" }
        if self == .privacy {
            let language = L10n.language.rawValue
            return (try? String(contentsOf: root.appendingPathComponent("privacy-\(language).md"), encoding: .utf8)) ??
                (try? String(contentsOf: root.appendingPathComponent("privacy-en.md"), encoding: .utf8)) ?? ""
        }
        let folder = root.appendingPathComponent("ThirdParty")
        let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey])?
            .compactMap { $0 as? URL }.filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }.sorted { $0.path < $1.path } ?? []
        return files.compactMap { url in
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            return url.path.replacingOccurrences(of: folder.path + "/", with: "") + "\n\n" + text
        }.joined(separator: "\n\n────────────────────\n\n")
    }
}

struct LegalDocumentsView: View {
    let document: LegalDocument
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(document.title).font(.headline)
                Spacer()
                Button(L10n.text("关闭")) { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(18)
            Divider()
            ScrollView {
                Text(document.text).font(.system(size: 13)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(22)
            }
        }.frame(width: 720, height: 600)
    }
}
