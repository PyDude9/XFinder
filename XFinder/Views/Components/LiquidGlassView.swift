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
                    .stroke(LiquidGlassTokens.containerBorder, lineWidth: 1)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(
                        LinearGradient(colors: [LiquidGlassTokens.containerHighlight, .clear], startPoint: .top, endPoint: .bottom),
                        lineWidth: 1
                    )
                    .mask(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .center))
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .shadow(color: LiquidGlassTokens.shadow, radius: LiquidGlassTokens.shadowRadius, x: 0, y: LiquidGlassTokens.shadowY)
            .shadow(color: LiquidGlassTokens.shadowSecondary, radius: LiquidGlassTokens.shadowSecondaryRadius, x: 0, y: LiquidGlassTokens.shadowSecondaryY)
            .shadow(color: isSelected ? LiquidGlassTokens.selectionGlow : .clear, radius: LiquidGlassTokens.selectionGlowRadius, x: 0, y: 0)
    }
}

/// Liquid Glass visual effect card for individual window previews (ZStack with .hudWindow + dark tint)
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
                ZStack {
                    VisualEffectView(material: LiquidGlassTokens.material, blendingMode: .withinWindow)
                    isSelected ? LiquidGlassTokens.cardSelectedBackground : LiquidGlassTokens.cardBackground
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(isSelected ? LiquidGlassTokens.cardSelectedBorder : LiquidGlassTokens.glassBorder, lineWidth: isSelected ? 1.5 : 1.0)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(
                        LinearGradient(colors: [LiquidGlassTokens.glassHighlight, .clear], startPoint: .top, endPoint: .bottom),
                        lineWidth: 1
                    )
                    .mask(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .center))
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .shadow(color: LiquidGlassTokens.shadow, radius: LiquidGlassTokens.shadowRadius, x: 0, y: LiquidGlassTokens.shadowY)
            .shadow(color: isSelected ? LiquidGlassTokens.selectionGlow : .clear, radius: LiquidGlassTokens.selectionGlowRadius, x: 0, y: 0)
    }
}

/// 100% Flat, crisp window thumbnail view with zero 3D distortion or blur.
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
        .frame(width: width, height: height ?? 110)
        .clipShape(RoundedRectangle(cornerRadius: LiquidGlassTokens.thumbRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: LiquidGlassTokens.thumbRadius, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
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
