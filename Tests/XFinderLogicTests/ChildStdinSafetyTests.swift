import XCTest

/// P7a — a write to a child's stdin after the child exits raises SIGPIPE, and SIGPIPE's default action kills XFinder
/// (measured: the unguarded writer died with exit 141; with `fcntl(fd, F_SETNOSIGPIPE, 1)` the write threw and the
/// writer lived). Found while building windowless sessions; the kitty/tmux sender and Khoá thư mục had the same hole.
/// The app target cannot be linked here, so the gate reads the sources.
final class ChildStdinSafetyTests: XCTestCase {

    func testEveryChildStdinPipeIsGuardedAgainstSIGPIPE() throws {
        let root = L10nFixture.repoRoot().appendingPathComponent("XFinder")
        let files = (FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? [])
            .filter { $0.pathExtension == "swift" }
        XCTAssertGreaterThan(files.count, 100, "the walk found almost nothing — the path rotted")
        var writers = 0
        for f in files {
            let src = try String(contentsOf: f, encoding: .utf8)
            let lines = src.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            let code = lines.joined(separator: "\n")
            // A pipe on stdin that the app then writes to.
            let writesStdin = code.range(of: #"\.standardInput\s*=\s*(?!FileHandle\.nullDevice)"#, options: .regularExpression) != nil
                && code.contains(".write(contentsOf:")      // NowPlayingMonitor only CLOSES its stdin pipe — no write, no SIGPIPE
            XCTAssertNil(code.range(of: #"fileHandleForWriting\.write\((?!contentsOf:)"#, options: .regularExpression),
                           "\(f.lastPathComponent): the legacy write(_:) raises an exception on EPIPE — use write(contentsOf:)")
            guard writesStdin else { continue }
            writers += 1
            XCTAssertTrue(code.contains("F_SETNOSIGPIPE"), "\(f.lastPathComponent) writes to a child's stdin without F_SETNOSIGPIPE")
        }
        XCTAssertGreaterThanOrEqual(writers, 3, "FolderLock, the P6 sender and the windowless manager write to stdin — the check found fewer")
    }
}
