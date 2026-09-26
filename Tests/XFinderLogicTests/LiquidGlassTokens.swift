import SwiftUI
import AppKit

/// Unified Design Tokens for Liquid Glass styling (macOS 26/27 native feel).
///
/// Both Dock and Switcher import this token. No inline magic numbers.
public struct LiquidGlassTokens {
    // MARK: - Core Tokens
    public static let containerRadius: CGFloat = 24
    public static let cardRadius: CGFloat = 18
    public static let thumbRadius: CGFloat = 12
    public static let material: NSVisualEffectView.Material = .hudWindow
    public static let blurRadius: CGFloat = 40
    public static let saturation: CGFloat = 1.6
    public static let glassBackground = Color.black.opacity(0.35) // container lớn dark glass
    public static let cardBackground = Color.white.opacity(0.10)  // card unselected
    public static let cardSelectedBackground = Color.white.opacity(0.65) // card selected
    public static let glassBorder = Color.white.opacity(0.15)     // unselected border
    public static let cardSelectedBorder = Color.white.opacity(0.65) // selected border
    public static let glassHighlight = Color.white.opacity(0.30)
    public static let shadow = Color.black.opacity(0.30) // radius 40 y 16
    public static let shadowRadius: CGFloat = 40
    public static let shadowY: CGFloat = 16

    public static let spring = Animation.spring(response: 0.32, dampingFraction: 0.78, blendDuration: 0)
    public static let scaleSelected: CGFloat = 1.0 // dock preview không scale
    public static let switcherSelectionScale: CGFloat = 1.06
    public static let unselectedOpacity: Double = 0.65
    public static let unselectedSaturation: Double = 0.85

    public static let selectionGlow = Color.white.opacity(0.20)
    public static let selectionGlowRadius: CGFloat = 20

    public static let cardSize: CGSize = CGSize(width: 220, height: 172)
    public static let dockCardSize: CGSize = CGSize(width: 320, height: 280)
    public static let dockThumbSize: CGSize = CGSize(width: 304, height: 160)
    public static let switcherThumbSize: CGSize = CGSize(width: 204, height: 120)
    public static let searchPillWidth: CGFloat = 360
    public static let searchPillHeight: CGFloat = 36
    public static let searchPillRadius: CGFloat = 16

    // MARK: - Namespaces for structured access
    public enum Container {
        public static var cornerRadius: CGFloat { LiquidGlassTokens.containerRadius }
        public static let padding: CGFloat = 12
        public static let gap: CGFloat = 12
        public static let borderWidth: CGFloat = 1
        public static var borderColor: Color { LiquidGlassTokens.glassBorder }
    }

    public enum Card {
        public static var cornerRadius: CGFloat { LiquidGlassTokens.cardRadius }
        public static var thumbRadius: CGFloat { LiquidGlassTokens.thumbRadius }
        public static var size: CGSize { LiquidGlassTokens.cardSize }
        public static var dockSize: CGSize { LiquidGlassTokens.dockCardSize }
        public static var dockThumbSize: CGSize { LiquidGlassTokens.dockThumbSize }
        public static var switcherThumbSize: CGSize { LiquidGlassTokens.switcherThumbSize }
        public static let trafficDotSize: CGFloat = 10
        public static let appIconSize: CGFloat = 16
        public static let padding: CGFloat = 8
    }

    public enum SearchPill {
        public static var width: CGFloat { LiquidGlassTokens.searchPillWidth }
        public static var height: CGFloat { LiquidGlassTokens.searchPillHeight }
        public static var cornerRadius: CGFloat { LiquidGlassTokens.searchPillRadius }
        public static let iconSize: CGFloat = 12
    }

    public enum Motion {
        public static var spring: Animation { LiquidGlassTokens.spring }
        public static var selectionScale: CGFloat { LiquidGlassTokens.switcherSelectionScale }
        public static let scaleInitial: CGFloat = 0.92
        public static let scaleFinal: CGFloat = 1.0
    }
}
