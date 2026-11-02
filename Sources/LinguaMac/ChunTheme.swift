import SwiftUI

/// macOS adaptation of ChunUI's semantic tokens. UIKit components are intentionally not linked.
enum CC {
    static let primary = Color(nsColor: .labelColor)
    static let onPrimary = Color(nsColor: .textBackgroundColor)
    static let background = Color(nsColor: .windowBackgroundColor)
    static let card = Color(nsColor: .textBackgroundColor)
    static let panel = Color.primary.opacity(0.025)
    static let border = Color.primary.opacity(0.10)
    static let muted = Color.secondary
    static let sm = Font.system(size: 12)
    static let caption = Font.system(size: 11)
    static let editorSize: CGFloat = 15
    static let base = Font.system(size: 15)
    static let lg = Font.system(size: 20, weight: .semibold)
}

struct NeoButtonStyle: ButtonStyle {
    var primary = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        ButtonSurface(primary: primary, enabled: enabled, pressed: configuration.isPressed) {
            configuration.label.font(CC.sm.weight(.medium))
                .padding(.horizontal, 16).frame(height: 32)
        }
    }
}

private struct ButtonSurface<Label: View>: View {
    var primary: Bool
    var enabled: Bool
    var pressed: Bool
    @ViewBuilder var label: Label
    @State private var hovered = false
    var body: some View {
        label.foregroundStyle(primary ? CC.onPrimary : CC.primary)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(primary ? CC.primary : (hovered ? CC.panel : CC.card))
                    .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(primary ? .clear : CC.border, lineWidth: 0.5) }
            }
            .contentShape(Rectangle())
            .opacity(!enabled ? 0.35 : (pressed ? 0.72 : 1))
            .onHover { hovered = $0 }
    }
}

/// The entire control, including its padding, is clickable.
struct QuietButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        QuietButtonSurface(enabled: enabled, pressed: configuration.isPressed, label: configuration.label)
    }
}

private struct QuietButtonSurface<Label: View>: View {
    var enabled: Bool
    var pressed: Bool
    var label: Label
    @State private var hovered = false
    var body: some View {
        label.padding(.horizontal, 7).padding(.vertical, 6)
            .background(hovered && enabled ? CC.panel : .clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
            .opacity(!enabled ? 0.35 : (pressed ? 0.6 : 1))
            .onHover { hovered = $0 }
    }
}

/// Sidebar selection, hover and press share one surface and one hit region.
struct SidebarButtonStyle: ButtonStyle {
    var selected: Bool
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        SidebarButtonSurface(selected: selected, enabled: enabled,
                             pressed: configuration.isPressed, label: configuration.label)
    }
}

private struct SidebarButtonSurface<Label: View>: View {
    var selected: Bool
    var enabled: Bool
    var pressed: Bool
    var label: Label
    @State private var hovered = false
    private var fillOpacity: Double {
        guard enabled else { return selected ? 0.06 : 0 }
        if pressed { return 0.11 }
        if selected { return hovered ? 0.085 : 0.065 }
        return hovered ? 0.035 : 0
    }
    var body: some View {
        label.padding(.horizontal, 12).frame(height: 36)
            .background(CC.primary.opacity(fillOpacity), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(Rectangle())
            .opacity(enabled ? 1 : 0.35)
            .onHover { hovered = $0 }
    }
}

extension View {
    func ccCard() -> some View {
        background(CC.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(CC.border, lineWidth: 0.5) }
    }
}

/// Small original line icons, keeping business iconography consistent across desktop controls.
struct LineIcon: View {
    enum Kind { case text, image, book, history, settings, arrow, swap, plus, copy, download, trash, close, sidebar }
    let kind: Kind
    var body: some View {
        GeometryReader { geometry in
            Path { p in
                func line(_ points: [(CGFloat, CGFloat)]) {
                    guard let first = points.first else { return }
                    p.move(to: CGPoint(x: first.0, y: first.1))
                    for point in points.dropFirst() { p.addLine(to: CGPoint(x: point.0, y: point.1)) }
                }
                switch kind {
                case .text:
                    line([(5,5),(19,5)]); line([(12,5),(12,20)]); line([(8,20),(16,20)])
                case .image:
                    p.addRoundedRect(in: CGRect(x:3,y:4,width:18,height:16), cornerSize: CGSize(width:3,height:3))
                    p.addEllipse(in: CGRect(x:6,y:7,width:3,height:3)); line([(4,18),(11,12),(15,16),(18,13),(21,16)])
                case .book:
                    line([(12,5),(12,21)]); line([(12,7),(6,4),(3,4),(3,18),(6,18),(12,21),(18,18),(21,18),(21,4),(18,4),(12,7)])
                case .history:
                    p.addArc(center: CGPoint(x:12,y:12), radius:8, startAngle:.degrees(-130), endAngle:.degrees(220), clockwise:false)
                    line([(3,4),(3,10),(8,10)]); line([(12,7),(12,12),(16,14)])
                case .settings:
                    for y: CGFloat in [6,12,18] { line([(3,y),(21,y)]) }
                    for (x,y): (CGFloat,CGFloat) in [(8,6),(16,12),(10,18)] { p.addEllipse(in: CGRect(x:x-2,y:y-2,width:4,height:4)) }
                case .arrow: line([(4,12),(20,12)]); line([(14,6),(20,12),(14,18)])
                case .swap: line([(3,7),(20,7),(16,3)]); line([(21,17),(4,17),(8,21)])
                case .plus: line([(12,4),(12,20)]); line([(4,12),(20,12)])
                case .copy:
                    p.addRoundedRect(in: CGRect(x:8,y:8,width:12,height:13),cornerSize:CGSize(width:2,height:2))
                    line([(16,5),(16,3),(3,3),(3,16),(5,16)])
                case .download: line([(12,3),(12,15)]); line([(7,10),(12,15),(17,10)]); line([(4,17),(4,21),(20,21),(20,17)])
                case .trash: line([(3,6),(21,6)]); line([(6,6),(7,21),(17,21),(18,6)]); line([(9,6),(9,3),(15,3),(15,6)]); line([(10,10),(10,17)]); line([(14,10),(14,17)])
                case .close: line([(5,5),(19,19)]); line([(19,5),(5,19)])
                case .sidebar:
                    p.addRoundedRect(in: CGRect(x:3,y:4,width:18,height:16),cornerSize:CGSize(width:2,height:2))
                    line([(9,4),(9,20)])
                }
            }
            .applying(CGAffineTransform(scaleX: geometry.size.width/24, y: geometry.size.height/24))
            .stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }.frame(width: 17, height: 17).accessibilityHidden(true)
    }
}

/// The entire disclosure header is a single button, including its title and whitespace.
struct WholeRowDisclosureStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { configuration.isExpanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .medium))
                        .rotationEffect(.degrees(configuration.isExpanded ? 90 : 0))
                        .foregroundStyle(CC.muted)
                    configuration.label
                    Spacer(minLength: 0)
                }.frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                    .contentShape(Rectangle())
            }.buttonStyle(.plain)
            if configuration.isExpanded { configuration.content }
        }
    }
}
