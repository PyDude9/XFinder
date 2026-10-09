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

/// A short "Copied #RRGGBB" confirmation. The flyout that started the pick has already closed, so
/// without this the user would get no sign anything happened. Non-activating and
/// mouse-transparent, like the other floating panels (never `NSApp.activate`).
@MainActor
final class ColorToast {
    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?

    func show(hex: String, color: NSColor) {
        hideWork?.cancel()
        panel?.orderOut(nil)
        let size = NSSize(width: 230, height: 54)
        let host = NSHostingController(rootView: ColorToastView(hex: hex, color: color))
        host.view.frame = NSRect(origin: .zero, size: size)
        let p = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.contentViewController = host
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .statusBar
        p.hidesOnDeactivate = false
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })
            ?? NSScreen.main ?? NSScreen.screens.first
        if let frame = screen?.visibleFrame {
            p.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.maxY - size.height - 72))
        }
        p.orderFrontRegardless()
        panel = p

        // One one-shot hide; nothing runs after it.
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.panel?.orderOut(nil)
                self?.panel = nil
            }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: work)
    }
}

struct ColorToastView: View {
    let hex: String
    let color: NSColor

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(nsColor: color))
                .frame(width: 26, height: 26)
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.25), lineWidth: 1))
            VStack(alignment: .leading, spacing: 1) {
                Text(L10n.t("Đã sao chép"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(hex)
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(width: 230, height: 54)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
