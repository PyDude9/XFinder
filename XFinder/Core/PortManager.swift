import Foundation
import Darwin

/// The live half of the open-ports page: scans with `PortScanner` off the main thread and sends the
/// signal. Every rule about WHAT may be stopped lives in `PortList` (pure, tested); this class only
/// does the spawning and the `kill(2)`.
///
/// No timer: the list is read when the page appears, on "Làm mới", and after a stop. A page that
/// polls the scan forever would break the 0 % idle rule for a list nobody is looking at.
@MainActor
@Observable
final class PortManager {
    static let shared = PortManager()

    enum StopResult: Equatable {
        /// The process exited.
        case stopped
        /// The signal was delivered but the process is still alive after the wait.
        case stillRunning
        /// The pre-signal safety check failed (pid reused, no longer ours, gone…). Nothing was sent.
        case refused
        case failed(String)
    }

    private(set) var result: PortList.BuildResult?
    private(set) var isLoading = false
    private(set) var refreshedAt: Date?
    private var generation = 0

    private init() {}

    func refresh() async {
        generation += 1
        let mine = generation
        isLoading = true
        let uid = getuid(), me = getpid()
        let built = await Task.detached(priority: .utility) { () -> PortList.BuildResult in
            let r = PortScanner.scan()
            return PortList.build(scan: r.scan, owners: r.owners, currentUID: uid, selfPID: me)
        }.value
        // A slower, older read must not overwrite a newer one.
        guard mine == generation else { return }
        isLoading = false
        // A failed scan is NOT an empty list: `scanSucceeded == false` makes the page say so.
        result = built
        refreshedAt = Date()
    }

    /// SIGTERM (a polite request the process may handle or ignore) or, with `force`, SIGKILL.
    /// The pid is re-verified first: the list can be seconds old and a freed pid may now belong to
    /// something unrelated.
    func stop(_ row: PortList.Row, force: Bool) async -> StopResult {
        let uid = getuid(), me = getpid()
        let pid = row.pid
        let current = await Task.detached(priority: .userInitiated) { () -> (uid: UInt32, command: String)? in
            PortScanner.process(pid: pid).map { ($0.uid, $0.command) }
        }.value
        guard PortList.isSafeToSignal(pid: pid, listedCommand: row.command, currentCommand: current?.command,
                                      currentOwnerUID: current?.uid, currentUID: uid, selfPID: me) else {
            await refresh()
            return .refused
        }
        if kill(pid, force ? SIGKILL : SIGTERM) != 0 {
            let message = String(cString: strerror(errno))
            await refresh()
            return .failed(message)
        }
        // Up to 2 s for it to exit; `kill(pid, 0)` fails with ESRCH once it is gone.
        for _ in 0..<10 {
            try? await Task.sleep(nanoseconds: 200_000_000)
            if kill(pid, 0) != 0 { await refresh(); return .stopped }
        }
        await refresh()
        return .stillRunning
    }
}
