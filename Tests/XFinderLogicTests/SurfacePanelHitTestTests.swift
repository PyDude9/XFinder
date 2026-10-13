import XCTest
import Foundation

/// N1b (2026-10-13) — the notch panel is ONE fixed frame (776 pt wide) laid over every title bar under the notch, so
/// it must hit-test by its drawn shape, not by its frame. Measured with `NSWindow.windowNumber(at:)` on a clear
/// 600×300 panel holding a 100×100 opaque square (`scratchpad/onenotch/probe2/ignores.swift`):
///
///   `ignoresMouseEvents` never assigned            → opaque point hits the panel, clear point falls through
///   `ignoresMouseEvents = false` assigned (any time) → BOTH points hit the panel (the whole frame blocks clicks)
///   the property reads `false` in both states
///
/// AppKit keeps a third, unset state ("hit-test by shape") that the Bool API cannot express, and the only way to stay
/// in it is to never write the property. This gate reads the source so nobody re-adds the assignment "for clarity".
final class SurfacePanelHitTestTests: XCTestCase {
    static let repoRoot: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private func source(_ rel: String) throws -> String {
        try String(contentsOf: Self.repoRoot.appendingPathComponent(rel), encoding: .utf8)
    }

    /// Code only: every `//` comment stripped, so a comment MENTIONING the property does not trip the gate.
    private func code(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                if let r = line.range(of: "//") { return String(line[..<r.lowerBound]) }
                return String(line)
            }
            .joined(separator: "\n")
    }

    func testNotchKindNeverWritesIgnoresMouseEvents() throws {
        let text = code(try source("XFinder/Core/Surface/SurfacePanel.swift"))
        guard let start = text.range(of: "switch kind {") else { return XCTFail("anchor `switch kind {` not found — gate rotted") }
        guard let end = text.range(of: "\n        }", range: start.upperBound..<text.endIndex) else { return XCTFail("switch end not found") }
        let block = String(text[start.upperBound..<end.lowerBound])
        guard let notch = block.range(of: "case .notch:") else { return XCTFail("`case .notch:` not found in the kind switch — gate rotted") }
        let notchArm = String(block[notch.upperBound...])
        XCTAssertFalse(notchArm.contains("ignoresMouseEvents"),
                       "the .notch arm writes ignoresMouseEvents — assigning it (even `false`) makes the whole 776-pt frame block clicks. Arm:\n\(notchArm)")
        // The other kinds keep their explicit values: the gate is about the notch, not about the property in general.
        XCTAssertTrue(block.contains("case .passive:") && block.contains("ignoresMouseEvents = true"), "passive panels stay mouse-transparent")
    }

    func testNotchControllerNeverWritesIgnoresMouseEvents() throws {
        let text = code(try source("XFinder/Core/Notch/NotchSurfaceController.swift"))
        XCTAssertTrue(text.contains("SurfacePanel(kind: .notch"), "anchor: the controller builds the notch panel — gate rotted")
        XCTAssertFalse(text.contains("ignoresMouseEvents"),
                       "NotchSurfaceController writes ignoresMouseEvents — any write (true or false) leaves the shape-hit-test state")
    }
}
