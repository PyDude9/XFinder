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
        /// The vertical inset of a small tag (the PRO badge).
        static let hairline: CGFloat = 2
    }

    /// Corner radii. Five values; anything else is a design mistake, not a choice.
    enum Radius {
        static let badge: CGFloat = 6       // pills, chips, tags
        static let control: CGFloat = 8     // buttons, fields
        static let tile: CGFloat = 12       // grid tiles / thumbnails (TileCard)
        static let surface: CGFloat = 24    // switcher, HUD containers, the notch's peek / pointer tray
        /// The expanded notch hub (D1, user request after the OneNotch reference): on a 752-pt-wide panel a
        /// 24-pt corner reads as a sharp rectangle; the reference's corners measure ≈ 0.155 × panel height
        /// (232 pt ⇒ 36). Continuous (superellipse) curve, like every corner here.
        static let hub: CGFloat = 36
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

    /// XF-T32 W2/W3 — custom-property colours (Tilde's 7). Chip = tint at `chipFill` opacity behind tint text.
    /// STUB values — builder `sidebarparts` tunes them against the Tilde screenshots.
    enum PropertyTint {
        static let chipFill: Double = 0.18
        static func color(_ tint: PropertyColor) -> Color {
            switch tint {
            case .gray: return Color(nsColor: .systemGray)
            case .red: return Color(nsColor: .systemRed)
            case .orange: return Color(nsColor: .systemOrange)
            case .yellow: return Color(nsColor: .systemYellow)
            case .green: return Color(nsColor: .systemGreen)
            case .blue: return Color(nsColor: .systemBlue)
            case .purple: return Color(nsColor: .systemPurple)
            }
        }
    }

    /// Motion. Two curves only: surfaces that expand (notch, panels) and overlays that appear.
    /// P1 — the notch surface's own palette and motion, measured on the owner's OneNotch screenshots
    /// (pt = px / 2 of its 700 × 745 window at 2×). Layout sizes live in `NotchSurfaceLayout.Metrics`.
    enum Notch {
        /// The page-dots capsule and the toolbar capsule in the band: #181818 on the black body.
        static let capsule = Color(red: 0x18 / 255, green: 0x18 / 255, blue: 0x18 / 255)
        static let dotLit = Color.white
        static let dotDim = Color(red: 0x52 / 255, green: 0x52 / 255, blue: 0x54 / 255)
        static let toolbarIcon = Color(red: 0x6B / 255, green: 0x6B / 255, blue: 0x6E / 255)
        /// Dots capsule 54 × 20 holding up to 3 dots of 5.5 pt, 15 pt apart; search circle 24; toolbar 63 × 22.
        static let dotsCapsuleHeight: CGFloat = 20
        static let dotSize: CGFloat = 5.5
        static let dotPitch: CGFloat = 15
        static let searchDiameter: CGFloat = 24
        static let toolbarHeight: CGFloat = 22
        static let toolbarIconPitch: CGFloat = 19
        /// The Now Playing progress track (#818184 measured) and a card's hairline.
        static let progressTrack = Color(red: 0x81 / 255, green: 0x81 / 255, blue: 0x84 / 255).opacity(0.45)
        static let cardStroke = Color.white.opacity(0.10)
        /// Opening overshoots a little (OneNotch measured 87 → 93 → 87 px, ~4 %), closing is quick and never bounces
        /// (~130 ms measured), and a page change cross-fades its content (~200 ms measured) while the shape springs.
        static let open = Animation.spring(response: 0.36, dampingFraction: 0.76)
        static let close = Animation.spring(response: 0.22, dampingFraction: 1.0)
        static let pageFade = Animation.easeInOut(duration: 0.18)
        /// A live notice (volume, brightness, Caps Lock…) is feedback for a key the user JUST pressed: it must be
        /// readable at once, so it grows faster than the hub and does not overshoot. With `open` (0.36, overshoot) the
        /// strip was still growing a third of a second after the first press — the "khựng" the owner reported.
        static let activity = Animation.spring(response: 0.2, dampingFraction: 0.92)
        /// The level bar follows each 1/16 step quickly enough to keep up with key repeat (~80 ms apart).
        static let level = Animation.easeOut(duration: 0.12)
    }

    /// P3 (2026-10-13) — the settings window shell, measured on OneNotch's settings screenshots (870×712 pt @2x,
    /// `scratchpad/uiux2/spec/report-settings.md`). Geometry is copied; colours are NOT copied as hex — each one is the
    /// system colour (or `primary` at an opacity) that renders the measured light-mode value on a white page, so dark
    /// mode keeps working from the OS like every other token here.
    enum Settings {
        /// Fixed, never a range (the "sidebar width jumped" bug). OneNotch measures 220 exactly.
        static let sidebarWidth: CGFloat = 220
        /// Coloured icon tile behind every sidebar row: 22×22, corner 6, white glyph.
        static let tileSize: CGFloat = 22
        static let tileRadius: CGFloat = 6
        static let tileGlyph = SwiftUI.Font.system(size: 12, weight: .semibold)
        static let sidebarRow = SwiftUI.Font.system(size: 13)
        /// Sidebar group label — measured ≈ 11 pt, #808080 = secondaryLabel on white.
        static let sidebarHeader = SwiftUI.Font.system(size: 11, weight: .medium)
        /// Page header bar: 52 tall, title ≈ 20 pt at the page inset, a hairline under it.
        static let headerHeight: CGFloat = 52
        static let headerTitle = SwiftUI.Font.system(size: 20, weight: .semibold)
        /// #4D4D4D on white = black at 70 %.
        static let headerTitleColor = Color.primary.opacity(0.70)
        /// #E5E5E5 on white = black at 10 %.
        static let hairline = Color.primary.opacity(0.10)
        /// Section title above a card — ≈ 13 pt semibold.
        static let sectionTitle = SwiftUI.Font.system(size: 13, weight: .semibold)
        /// The grouped card: #F7F7F7 on white = black at 3 %; dark mode uses white at 6 % (macOS's own grouped
        /// boxes read about that light on a dark window). Flat: no stroke, no shadow.
        static let cardFill = Color(nsColor: NSColor(name: "XFinderSettingsCard") { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor.white.withAlphaComponent(0.06)
                : NSColor.black.withAlphaComponent(0.03)
        })
        static let cardRadius: CGFloat = 10
        /// Inside a card: rows start 10 pt in, dividers start where the text starts.
        static let cardInset: CGFloat = 10
        /// One-line row height; a row with a subtitle grows instead of squeezing (our subtitles are longer than
        /// OneNotch's, and a clipped explanation is worse than a taller row).
        static let rowMinHeight: CGFloat = 31
        static let rowVerticalPadding: CGFloat = 6
        /// Gap between two sections (title + card).
        static let sectionGap: CGFloat = 20
        /// The page behind the cards: white in light mode, the text background in dark — the measured #FFFFFF.
        static let contentBackground = Color(nsColor: .textBackgroundColor)
        /// A keyboard shortcut drawn as a keycap ("⌘⇧V").
        static let keycap = SwiftUI.Font.system(size: 12, weight: .medium, design: .rounded)
    }

    enum Motion {
        /// Notch / edge panel expand-collapse. `response 0.32, damping 0.82` reads as elastic, not snappy.
        static let surface = Animation.spring(response: 0.32, dampingFraction: 0.82)
        /// Switcher / HUD appearance. One token replaces the 0.18 s literals.
        static let overlayIn: TimeInterval = 0.16
    }

    /// XF-T30 W6 — how a file pending a Windows-style ⌘X cut is drawn (Finder/Explorer fade it).
    enum Emphasis {
        static let cutItemAlpha: CGFloat = 0.45
    }
}
