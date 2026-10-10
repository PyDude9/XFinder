import AppKit
import SwiftUI

/// "Pick a colour from anywhere on screen and copy it" — the live half of `ColorFormat`.
///
/// Uses `NSColorSampler`, the system's own eyedropper loupe (public API, macOS 10.15+). The
/// picked colour is converted to sRGB, written to the pasteboard as `#RRGGBB`, and confirmed with
/// a short toast. The clipboard manager then records it as a colour entry by itself, because
/// `#RRGGBB` is exactly what `ClipboardClassifier` calls `.color`.
///
/// Cost: nothing at rest. The sampler and the toast exist only during a pick.
@MainActor
@Observable
final class ScreenColorPicker {
    static let shared = ScreenColorPicker()

    /// The last colour copied this session (`#RRGGBB`), nil until one was picked.
    private(set) var lastPicked: String?
    private(set) var isPicking = false

    private var sampler: NSColorSampler?
    private let toast = ColorToast()

    // Internal, not private: a standalone harness builds its own instance to drive the real code.
    init() {}

    /// Show the system loupe. Esc / clicking nothing cancels and leaves the clipboard untouched.
    func pick() {
        guard !isPicking else { return }
        isPicking = true
        let s = NSColorSampler()
        sampler = s
        s.show { [weak self] color in
            // NSColorSampler delivers on the main thread.
            MainActor.assumeIsolated { self?.finish(with: color) }
        }
    }

    private func finish(with color: NSColor?) {
        isPicking = false
        sampler = nil
        guard let color, let srgb = color.usingColorSpace(.sRGB) else { return }
        let hex = ColorFormat.hex(red: Double(srgb.redComponent),
                                  green: Double(srgb.greenComponent),
                                  blue: Double(srgb.blueComponent))
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(hex, forType: .string)
        lastPicked = hex
        toast.show(hex: hex, color: srgb)
    }
}

/// "Copied #RRGGBB" confirmation — a `ToastSurface(.compact)` showing the colour as a swatch.
/// Kept as a named type so the picker's call site and the e2e probe (230×54 panel) stay unchanged.
@MainActor
final class ColorToast {
    private let surface = ToastSurface(style: .compact)
    func show(hex: String, color: NSColor) {
        surface.show(symbol: "eyedropper", title: L10n.t("Đã sao chép"), detail: hex, swatch: color, duration: 1.8)
    }
}
