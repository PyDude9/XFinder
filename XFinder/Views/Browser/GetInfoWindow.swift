import AppKit
import SwiftUI

/// XF-T28 Wave 4 — STUB written by the integrator; the W4-info agent implements it (docs/specs/XF-T28-wave4.md §A).
@MainActor final class GetInfoWindowController {
    static let shared = GetInfoWindowController()
    /// One window per item (or one summary window for several); `readOnly` for search results.
    func show(paths: [String], readOnly: Bool) {}
}
