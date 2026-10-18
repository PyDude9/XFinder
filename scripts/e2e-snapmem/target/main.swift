import AppKit
import Foundation

// SnapMemTarget — a throw-away AppKit app used only by the snap-memory e2e
// harness. It opens one 600x400 titled window at a known off-target
// position (x=300, y=300 in NSWindow.frame / AppKit bottom-left space), and
// reports every move/resize both to stdout AND to a fixed log file (because
// when launched via `open`, the launching terminal does not see the child's
// stdout — the log file is what the harness driver actually reads from).
//
// It quits on the distributed notification com.xfinder.e2e.snapmem.quit.

// <build>/target/SnapMemTarget.app → <build>/target.log, where run-e2e.sh (copied into <build>/ by scripts/e2e-snapmem.sh) reads it.
let logPath = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("target.log").path

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var observerTokens: [NSObjectProtocol] = []
    var logHandle: FileHandle?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Truncate the log at each launch so stale lines from a previous
        // run can never be mistaken for this run's output.
        FileManager.default.createFile(atPath: logPath, contents: nil)
        logHandle = FileHandle(forWritingAtPath: logPath)

        let frame = NSRect(x: 300, y: 300, width: 600, height: 400)
        let win = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "SnapMem Target"
        win.isReleasedWhenClosed = false
        win.makeKeyAndOrderFront(nil)
        self.window = win

        NSApp.activate(ignoringOtherApps: true)

        writeLine("INIT", frame: win.frame)

        let nc = NotificationCenter.default
        let moveToken = nc.addObserver(forName: NSWindow.didMoveNotification, object: win, queue: .main) { [weak self] _ in
            guard let self, let w = self.window else { return }
            self.writeLine("FRAME", frame: w.frame)
        }
        let resizeToken = nc.addObserver(forName: NSWindow.didResizeNotification, object: win, queue: .main) { [weak self] _ in
            guard let self, let w = self.window else { return }
            self.writeLine("FRAME", frame: w.frame)
        }
        observerTokens = [moveToken, resizeToken]

        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(
            forName: Notification.Name("com.xfinder.e2e.snapmem.quit"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.writeRaw("QUIT received\n")
            NSApp.terminate(nil)
        }
    }

    func writeLine(_ prefix: String, frame: NSRect) {
        // NSWindow.frame is bottom-left origin (AppKit screen space, points).
        let line = "\(prefix) \(frame.origin.x) \(frame.origin.y) \(frame.size.width) \(frame.size.height)\n"
        writeRaw(line)
    }

    func writeRaw(_ s: String) {
        print(s, terminator: "")
        fflush(stdout)
        if let data = s.data(using: .utf8) {
            logHandle?.write(data)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
