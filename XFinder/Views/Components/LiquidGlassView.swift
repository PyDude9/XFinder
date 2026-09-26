import SwiftUI
import AppKit

/// Visual effect view wrapper with NSVisualEffectView .hudWindow + .withinWindow
public struct VisualEffectView: NSViewRepresentable {
    public var material: NSVisualEffectView.Material
    public var blendingMode: NSVisualEffectView.BlendingMode

    public init(
        material: NSVisualEffectView.Material = LiquidGlassTokens.material,
        blendingMode: NSVisualEffectView.BlendingMode = .withinWindow
    ) {
        self.material = material
        self.blendingMode = blendingMode
    }

    public func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blendingMode
        v.state = .active
        v.wantsLayer = true
        return v
    }

    public func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = .active
    }
}

/// Liquid Glass visual effect container for panels (e.g. switcher container, dock preview container)
public struct LiquidGlassView<Content: View>: View {
    public let content: Content
    public var isSelected: Bool
    public var cornerRadius: CGFloat

    public init(
        isSelected: Bool = false,
        cornerRadius: CGFloat = LiquidGlassTokens.containerRadius,
        @ViewBuilder content: () -> Content
    ) {
        self.isSelected = isSelected
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    public var body: some View {
        content
            .background {
                ZStack {
                    VisualEffectView(material: LiquidGlassTokens.material, blendingMode: .withinWindow)
                    LiquidGlassTokens.glassBackground
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(LiquidGlassTokens.containerBorder, lineWidth: 0.5)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .shadow(color: LiquidGlassTokens.shadow, radius: LiquidGlassTokens.shadowRadius, x: 0, y: LiquidGlassTokens.shadowY)
    }
}

/// Liquid Glass visual effect card for individual window previews (clean, unselected is 100% transparent)
public struct LiquidGlassCard<Content: View>: View {
    public let content: Content
    public var isSelected: Bool
    public var cornerRadius: CGFloat

    public init(
        isSelected: Bool = false,
        cornerRadius: CGFloat = LiquidGlassTokens.cardRadius,
        @ViewBuilder content: () -> Content
    ) {
        self.isSelected = isSelected
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    public var body: some View {
        content
            .background {
                if isSelected {
                    ZStack {
                        VisualEffectView(material: LiquidGlassTokens.material, blendingMode: .withinWindow)
                        LiquidGlassTokens.cardSelectedBackground
                    }
                } else {
                    Color.clear
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .shadow(color: isSelected ? Color.black.opacity(0.14) : Color.clear, radius: 20, x: 0, y: 8)
    }
}

/// 100% Flat, crisp window thumbnail view with zero 3D distortion or inner stroke.
public struct WindowThumbnailView: View {
    public var image: NSImage?
    public var width: CGFloat?
    public var height: CGFloat?

    public init(image: NSImage? = nil, width: CGFloat? = nil, height: CGFloat? = nil) {
        self.image = image
        self.width = width
        self.height = height
    }

    public var body: some View {
        GeometryReader { geo in
            Group {
                if let image = image {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color.white.opacity(0.06))
                        .overlay {
                            ProgressView().scaleEffect(0.6)
                        }
                }
            }
        }
        .frame(width: width, height: height ?? LiquidGlassTokens.Card.switcherThumbSize.height)
        .clipShape(RoundedRectangle(cornerRadius: LiquidGlassTokens.thumbRadius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: LiquidGlassTokens.thumbRadius))
    }
}

public extension View {
    func liquidGlass(isSelected: Bool = false, cornerRadius: CGFloat = LiquidGlassTokens.containerRadius) -> some View {
        LiquidGlassView(isSelected: isSelected, cornerRadius: cornerRadius) {
            self
        }
    }

    func liquidGlassContainer(cornerRadius: CGFloat = LiquidGlassTokens.containerRadius) -> some View {
        LiquidGlassView(isSelected: false, cornerRadius: cornerRadius) {
            self
        }
    }

    func liquidGlassCard(isSelected: Bool = false, cornerRadius: CGFloat = LiquidGlassTokens.cardRadius) -> some View {
        LiquidGlassCard(isSelected: isSelected, cornerRadius: cornerRadius) {
            self
        }
    }

    func liquidGlassPill(cornerRadius: CGFloat = LiquidGlassTokens.searchPillRadius) -> some View {
        LiquidGlassView(isSelected: false, cornerRadius: cornerRadius) {
            self
        }
    }
}
