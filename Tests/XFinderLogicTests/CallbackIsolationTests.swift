import XCTest
import Foundation

/// A callback's thread is a measurement, not a comment. IOBluetooth delivered a real "device connected"
/// on `com.apple.bluetooth.iobluetooth.coordinatorQueue`, and `MainActor.assumeIsolated` inside the
/// `@objc` shim trapped the whole app on launch for anyone with a Bluetooth mouse (three crash reports,
/// 2026-10-11). The shim is AppKit and cannot run here, so this gate reads the SOURCE: every
/// `@objc nonisolated` callback in the live-activity monitor must hop through `runOnMainActor` and
/// must not assume the main actor. It fails on zero matches — a rotted anchor must not read as green.
final class CallbackIsolationTests: XCTestCase {
    static let repoRoot: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// Bodies of `@objc nonisolated … func name(...) { … }` declarations, keyed by function name.
    static func objcCallbacks(in source: String) -> [String: String] {
        var out: [String: String] = [:]
        let pattern = #"@objc\s+nonisolated\s+(?:private\s+)?func\s+(\w+)\s*\([^)]*\)\s*\{"#
        let regex = try! NSRegularExpression(pattern: pattern)
        let ns = source as NSString
        for m in regex.matches(in: source, range: NSRange(location: 0, length: ns.length)) {
            let name = ns.substring(with: m.range(at: 1))
            // Walk braces from the opening one to find the body's end.
            var depth = 0, i = m.range.location + m.range.length - 1, end = i
            let chars = Array(source.utf16)
            while i < chars.count {
                if chars[i] == 123 { depth += 1 } else if chars[i] == 125 { depth -= 1; if depth == 0 { end = i; break } }
                i += 1
            }
            out[name] = ns.substring(with: NSRange(location: m.range.location, length: end - m.range.location + 1))
        }
        return out
    }

    func testBluetoothCallbacksHopToMainInsteadOfAssumingIt() throws {
        let url = Self.repoRoot.appendingPathComponent("XFinder/Core/Notch/LiveActivityMonitor.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        let callbacks = Self.objcCallbacks(in: source)
        XCTAssertGreaterThanOrEqual(callbacks.count, 2, "expected the connect and disconnect callbacks; the anchor rotted")
        for (name, body) in callbacks {
            XCTAssertFalse(body.contains("assumeIsolated"),
                           "\(name) assumes the main actor inside an IOBluetooth callback — measured to arrive on the coordinator queue")
            XCTAssertTrue(body.contains("runOnMainActor"), "\(name) must hop to the main actor")
        }
    }

    func testTheParserSeesABodyAndItsBraces() {
        let src = """
        @objc nonisolated private func a(_ x: Int) { if x > 0 { MainActor.assumeIsolated { } } }
        @objc nonisolated func b() { runOnMainActor { } }
        func c() { MainActor.assumeIsolated { } }
        """
        let cbs = Self.objcCallbacks(in: src)
        XCTAssertEqual(Set(cbs.keys), ["a", "b"], "only @objc nonisolated callbacks count")
        XCTAssertTrue(cbs["a"]!.contains("assumeIsolated") && cbs["a"]!.hasSuffix("} }"))
        XCTAssertTrue(cbs["b"]!.contains("runOnMainActor"))
    }
}
