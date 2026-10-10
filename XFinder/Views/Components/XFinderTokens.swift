import SwiftUI

/// The ONE source of truth for the app's visual scale. Measured before this file existed
/// (2026-10-10): 739 `.font(.system(size:` call sites across 26 distinct sizes, 112 corner radii
/// across 14 values, 256 opacities across 39 values. Pages did not disagree on purpose — they had
/// nothing to agree with. `scripts/audit-ui-tokens.py` fails on new literals in `Views/Detail/`.
///
/// Native on purpose: system font, system colours, light/dark from the OS. A fixed palette or a
/// custom typeface (the web-flavoured tokens in the OneNotch blueprint) breaks in Light mode and
/// against the HIG. `LiquidGlassTokens` stays the glass/overlay section for Dock preview, the
/// ⌘-Tab switcher and the Notch surface.
enum XFinderTokens {

    /// Spacing scale (points).
    enum Space {
        /// Horizontal page inset — every page edge, header, section and row.
        static let page: CGFloat = 20
        /// Between sections.
        static let section: CGFloat = 24
        /// Between rows inside a section.
        static let row: CGFloat = 10
        /// Inside a row (icon ↔ label, label ↔ control).
        static let inline: CGFloat = 12
        static let tight: CGFloat = 6
    }

    /// Corner radii. Four values; anything else is a design mistake, not a choice.
    enum Radius {
        static let badge: CGFloat = 6       // pills, chips, tags
        static let control: CGFloat = 8     // buttons, fields
        static let tile: CGFloat = 12       // grid tiles / thumbnails (TileCard)
        static let surface: CGFloat = 24    // notch, switcher, HUD containers
    }

    /// Typography. Sizes are the ones PageHeader / SectionHeader / MetricBigNumber already used,
    /// promoted from literals to names so pages can share them.
    enum Font {
        static let pageTitle = SwiftUI.Font.system(size: 26, weight: .bold)
        static let pageSubtitle = SwiftUI.Font.system(size: 13)
        static let pageIcon = SwiftUI.Font.system(size: 24, weight: .regular)
        static let sectionTitle = SwiftUI.Font.system(size: 14, weight: .semibold)
        static let sectionSubtitle = SwiftUI.Font.system(size: 12)
        static let sectionIcon = SwiftUI.Font.system(size: 13)
        /// Row label (LabeledLine, ToggleRow, PickerRow, ActionRow).
        static let row = SwiftUI.Font.system(size: 13, weight: .medium)
        /// Row value / status text.
        static let rowValue = SwiftUI.Font.system(size: 12)
        /// Captions, notes, hints.
        static let caption = SwiftUI.Font.system(size: 11)
        /// Big system readouts (CPU %, GB…). Rounded + monospaced digits so the number does not jitter.
        static let metric = SwiftUI.Font.system(size: 28, weight: .bold, design: .rounded).monospacedDigit()
        static let metricUnit = SwiftUI.Font.system(size: 14, weight: .medium)
        /// Tabular numbers inside rows (percentages, sizes).
        static let mono = SwiftUI.Font.system(size: 12, design: .monospaced)
    }

    /// Fills and strokes, as opacities of the dynamic system colours (so they follow Light/Dark).
    enum Fill {
        /// 1 px separators and tile borders.
        static let hairline = Color.primary.opacity(0.06)
        static let hover = Color.primary.opacity(0.04)
        static let focus = Color.accentColor.opacity(0.35)
        /// Subtle inset fill (search pill, tile background).
        static let inset = Color.primary.opacity(0.06)
        /// Flat in-page surface (TileCard body).
        static let surface = Color(nsColor: .controlBackgroundColor)
        static let window = Color(nsColor: .windowBackgroundColor)
    }

    /// Motion. Two curves only: surfaces that expand (notch, panels) and overlays that appear.
    enum Motion {
        /// Notch / edge panel expand-collapse. `response 0.32, damping 0.82` reads as elastic, not snappy.
        static let surface = Animation.spring(response: 0.32, dampingFraction: 0.82)
        /// Switcher / HUD appearance. One token replaces the 0.18 s literals.
        static let overlayIn: TimeInterval = 0.16
    }
}
