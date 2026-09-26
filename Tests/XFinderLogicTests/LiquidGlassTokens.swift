import SwiftUI
import AppKit

/// Unified Design Tokens for Liquid Glass styling (macOS 26/27 native feel).
///
/// Both Dock and Switcher import this token. No inline magic numbers.
public struct LiquidGlassTokens {
    // MARK: - Core Tokens
    public static let containerRadius: CGFloat = 24
    public static let cardRadius: CGFloat = 16
    public static let thumbRadius: CGFloat = 10
    public static let material: NSVisualEffectView.Material = .popover
    public static let blurRadius: CGFloat = 32
    public static let saturation: CGFloat = 1.4
    public static let glassBackground = Color.white.opacity(0.10)
    public static let cardBackground = Color.clear  // unselected: fully transparent
    public static let cardSelectedBackground = Color.white.opacity(0.18) // selected: subtle glass lift
    public static let glassBorder = Color.clear
    public static let containerBorder = Color.white.opacity(0.12)
    public static let containerHighlight = Color.clear
    public static let cardSelectedBorder = Color.clear
    public static let glassHighlight = Color.clear
    public static let shadow = Color.black.opacity(0.14) // single 0 10 30 layer
    public static let shadowRadius: CGFloat = 30
    public static let shadowY: CGFloat = 10
    public static let shadowSecondary = Color.clear
    public static let shadowSecondaryRadius: CGFloat = 0
    public static let shadowSecondaryY: CGFloat = 0

    public static let spring = Animation.spring(response: 0.25, dampingFraction: 0.88, blendDuration: 0)
    public static let scaleSelected: CGFloat = 1.0 // dock preview không scale
    public static let switcherSelectionScale: CGFloat = 1.04
    public static let switcherSelectionYOffset: CGFloat = -2
    public static let switcherSelectionBrightness: Double = 0.0
    public static let unselectedOpacity: Double = 0.70
    public static let unselectedSaturation: Double = 1.0

    public static let selectionGlow = Color.clear
    public static let selectionGlowRadius: CGFloat = 0

    public static let cardSize: CGSize = CGSize(width: 200, height: 140)
    public static let dockCardSize: CGSize = CGSize(width: 320, height: 280)
    public static let dockThumbSize: CGSize = CGSize(width: 304, height: 160)
    public static let switcherThumbSize: CGSize = CGSize(width: 184, height: 86)
    public static let searchPillWidth: CGFloat = 300
    public static let searchPillHeight: CGFloat = 28
    public static let searchPillRadius: CGFloat = 14

    // MARK: - Namespaces for structured access
    public enum Container {
        public static var cornerRadius: CGFloat { LiquidGlassTokens.containerRadius }
        public static let padding: CGFloat = 12
        public static let gap: CGFloat = 10
        public static let borderWidth: CGFloat = 0.5
        public static var borderColor: Color { LiquidGlassTokens.containerBorder }
    }

    public enum Card {
        public static var cornerRadius: CGFloat { LiquidGlassTokens.cardRadius }
        public static var thumbRadius: CGFloat { LiquidGlassTokens.thumbRadius }
        public static var size: CGSize { LiquidGlassTokens.cardSize }
        public static var dockSize: CGSize { LiquidGlassTokens.dockCardSize }
        public static var dockThumbSize: CGSize { LiquidGlassTokens.dockThumbSize }
        public static var switcherThumbSize: CGSize { LiquidGlassTokens.switcherThumbSize }
        public static let trafficDotSize: CGFloat = 10
        public static let appIconSize: CGFloat = 22
        public static let badgeIconSize: CGFloat = 28
        public static let padding: CGFloat = 8
    }

    public enum SearchPill {
        public static var width: CGFloat { LiquidGlassTokens.searchPillWidth }
        public static var height: CGFloat { LiquidGlassTokens.searchPillHeight }
        public static var cornerRadius: CGFloat { LiquidGlassTokens.searchPillRadius }
        public static let iconSize: CGFloat = 11
    }

    public enum Motion {
        public static var spring: Animation { LiquidGlassTokens.spring }
        public static var selectionScale: CGFloat { LiquidGlassTokens.switcherSelectionScale }
        public static let scaleInitial: CGFloat = 0.98
        public static let scaleFinal: CGFloat = 1.0
    }
}
