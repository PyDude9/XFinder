import XCTest

/// XF-VOICE-PERMISSIONS (2026-11-08) — a permission callback formed inside a main-actor type inherits MainActor
/// isolation when the framework's block is not annotated Sendable; if the framework then runs it on another queue, the
/// executor check Swift 6 inserts traps. NOT measured: which queue Speech actually uses — a request from the old code in
/// a fresh account (Atlas helper) completed without a crash, so this guards a latent risk, not a reproduced crash.
/// Measured three ways:
/// - a probe of that shape (closure formed in a `@MainActor` method, passed to an un-annotated ObjC block that runs it on
///   a global queue): **SIGTRAP, exit 133**; the same closure written `{ @Sendable … }` survived (exit 0);
/// - SIL of `SFSpeechRecognizer.requestAuthorization { _ in … }` inside a `@MainActor` class: isolation MainActor with
///   `_checkExpectedExecutor` (the old FeatureHub and VoiceManager code); with `@Sendable`: nonisolated, no check;
/// - SIL of `AVCaptureDevice.requestAccess(for:) { _ in … }`: already nonisolated (the SDK marks that block Sendable).
/// The rule is uniform — every callback-form permission request is written `{ @Sendable …}` — so safety never depends on
/// how a given SDK version annotates a block. The app target cannot be linked here, so the gate reads the sources.
final class PermissionCallbackIsolationTests: XCTestCase {

    func testEveryPermissionCallbackClosureIsExplicitlySendable() throws {
        let root = L10nFixture.repoRoot().appendingPathComponent("XFinder")
        let files = (FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? [])
            .filter { $0.pathExtension == "swift" }
        XCTAssertGreaterThan(files.count, 100, "the walk found almost nothing — the path rotted")
        // A trailing closure handed to one of the callback-style permission requests. The async forms
        // (`await AVCaptureDevice.requestAccess(for:)`, EventKit, UserNotifications) take no closure and are not matched.
        let call = try NSRegularExpression(
            pattern: #"(requestAuthorization|requestAccess\(for:[^)]*\))\s*\{\s*(@Sendable)?"#)
        var sites = 0
        for f in files {
            let src = try String(contentsOf: f, encoding: .utf8)
            let code = src.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                .joined(separator: "\n")
            let ns = code as NSString
            for m in call.matches(in: code, range: NSRange(location: 0, length: ns.length)) {
                sites += 1
                let line = code.prefix(m.range.location).filter { $0 == "\n" }.count + 1
                XCTAssertNotEqual(m.range(at: 2).location, NSNotFound,
                                  "\(f.lastPathComponent) (code line \(line)): \(ns.substring(with: m.range(at: 1))) callback is not "
                                  + "`{ @Sendable …}` — it would trap off the main queue in Swift 6")
            }
        }
        // Positive control for the scan itself: FeatureHub (microphone, speech) and VoiceManager (speech) use the
        // callback form today. Fewer means the pattern stopped matching, not that the code got safer.
        XCTAssertGreaterThanOrEqual(sites, 3, "found \(sites) permission callbacks — the scan no longer sees FeatureHub/VoiceManager")
    }
}
