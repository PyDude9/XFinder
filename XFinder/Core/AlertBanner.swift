import AppKit
import SwiftUI

/// XFinder's own alert banner: top-right, 8 s, orange symbol — a `ToastSurface(.banner)`. Needs no
/// permission — the reason it exists (see `AlertMonitor`: Notification Center refuses self-signed builds).
@MainActor
final class AlertBanner {
    private let surface = ToastSurface(style: .banner)
    func show(symbol: String, title: String, body: String) {
        surface.show(symbol: symbol, tint: .orange, title: title, detail: body, duration: 8)
    }
}
