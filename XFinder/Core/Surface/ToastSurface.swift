import AppKit
import SwiftUI

/// One passive, self-expiring confirmation surface for the whole app: colour picked, text copied,
/// alert fired. Three classes used to hand-roll the same NSPanel (ColorToast 230×54 top-centre,
/// TextToast 340×62 top-centre, AlertBanner 380×68 top-right); they are now thin wrappers over this.
///
/// Prepare-once: the `SurfacePanel` and its `NSHostingController` are built on first use and then
/// only re-shown with new model values — never rebuilt on the hot path (measured 0.15–0.65 s per
/// `NSHostingController` in QuitProtection).
@MainActor
final class ToastSurface {

    enum Style {
        case compact   // 230×54, top-centre — colour pick
        case toast     // 340×62, top-centre — OCR, generic confirmations
        case banner    // 380×68, top-right — alerts

        var size: CGSize {
            switch self {
            case .compact: return CGSize(width: 230, height: 54)
            case .toast: return CGSize(width: 340, height: 62)
            case .banner: return CGSize(width: 380, height: 68)
            }
        }
        var anchor: SurfaceGeometry.Anchor {
            switch self {
            case .compact, .toast: return .topCenter(inset: 72)
            case .banner: return .topRight(inset: 16)
            }
        }
    }

    @Observable
    final class Model {
        var symbol = "checkmark"
        var tint: Color = .accentColor
        var title = ""
        var detail = ""
        /// When set, drawn instead of the symbol (the picked colour).
        var swatch: NSColor?
    }

    let style: Style
    private let model = Model()
    private var panel: SurfacePanel?

    init(style: Style) { self.style = style }

    private func prepared() -> SurfacePanel {
        if let panel { return panel }
        let p = SurfacePanel(kind: .passive, size: style.size)
        p.host(ToastView(model: model, size: style.size))
        panel = p
        return p
    }

    func show(symbol: String, tint: Color = .accentColor, title: String, detail: String = "", swatch: NSColor? = nil, duration: TimeInterval) {
        model.symbol = symbol; model.tint = tint; model.title = title; model.detail = detail; model.swatch = swatch
        let p = prepared()
        p.show(anchor: style.anchor)
        p.hide(after: duration)
    }

    func hide() { panel?.hide() }
}

struct ToastView: View {
    @Bindable var model: ToastSurface.Model
    let size: CGSize

    var body: some View {
        HStack(spacing: XFinderTokens.Space.inline) {
            if let swatch = model.swatch {
                Circle().fill(Color(nsColor: swatch))
                    .frame(width: 26, height: 26)
                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.25), lineWidth: 1))
            } else {
                Image(systemName: model.symbol)
                    .font(.system(size: size.height > 60 ? 22 : 20))
                    .foregroundColor(model.tint)
                    .frame(width: 30)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(model.title)
                    .font(model.swatch == nil ? XFinderTokens.Font.row : XFinderTokens.Font.caption)
                    .foregroundStyle(model.swatch == nil ? .primary : .secondary)
                if !model.detail.isEmpty {
                    Text(model.detail)
                        .font(model.swatch == nil ? XFinderTokens.Font.rowValue : .system(size: 15, weight: .semibold, design: .monospaced))
                        .foregroundStyle(model.swatch == nil ? .secondary : .primary)
                        .lineLimit(2).truncationMode(.tail)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .frame(width: size.width, height: size.height)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
