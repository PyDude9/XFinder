import Foundation

/// The pure half of the open-ports page: turning a scan into rows, and the rules about who may be
/// stopped. No process inspection here, so every rule is pinned by tests.
///
/// The job: *"something is holding port 3000 — what, and can I stop it?"*
///
/// Why the scan is `libproc` (`PortScanner`) and NOT `netstat`/`lsof`, both measured on macOS 27:
/// * `lsof` without root cannot see another user's sockets.
/// * `netstat -anv -p tcp` returns ZERO bytes with exit status 0 when it is spawned by a program
///   (Swift `Process`, Python `subprocess`, `sh -c` — all tried) yet 9 KB from an interactive
///   shell, and plain `netstat -anv` silently omits its TCP section. A page built on it showed
///   "could not read" on every real launch. `libproc` runs in-process, so there is no spawn.
/// The price: libproc only opens processes the user may inspect, so other users' (root's)
/// listeners are NOT visible. The scan reports how many processes it could not open, and the page
/// says so instead of presenting the list as complete.
enum PortList {

    struct RawListener: Equatable {
        var port: Int
        var address: String        // "*", "127.0.0.1", "::1", …
        var pid: Int32
        var command: String
    }

    struct Owner: Equatable { var uid: UInt32; var user: String }

    struct ListenerScan: Equatable {
        var listeners: [RawListener]
        /// False when the process list itself could not be read. That is a FAILED scan — presenting
        /// it as "no open ports" would be a false all-clear.
        var readSucceeded: Bool
        /// Processes whose file descriptors the OS refused to show us (other users', system).
        var uninspectable: Int
    }

    // MARK: - Rows

    enum Exposure: Equatable {
        /// Only this Mac can connect (loopback).
        case localOnly
        /// Every network interface — reachable from the LAN. The one worth flagging.
        case allInterfaces
        /// A specific non-loopback address.
        case specific
    }

    static func exposure(ofAddress a: String) -> Exposure {
        if a == "*" || a == "0.0.0.0" || a == "::" { return .allInterfaces }
        if a == "::1" || a == "localhost" || a.hasPrefix("127.") { return .localOnly }
        return .specific
    }

    struct Row: Identifiable, Equatable {
        var port: Int
        var pid: Int32
        var command: String
        var addresses: [String]
        var exposure: Exposure
        /// nil when the owner could not be read (the process exited during the scan).
        var owner: Owner?
        var isMine: Bool
        var canTerminate: Bool
        var id: String { "\(port)-\(pid)" }
    }

    struct BuildResult: Equatable {
        var rows: [Row]
        /// Processes the OS would not let us inspect — surfaced so the list is never read as complete.
        var uninspectable: Int
        /// False when the scan itself failed. The page must show an error then, never an empty list.
        var scanSucceeded: Bool
    }

    /// Join the scan's listeners with their owners, merge the IPv4/IPv6 twins of one socket into a
    /// single row (`*:5000` appears once per address family), and decide who may be stopped.
    static func build(scan: ListenerScan, owners: [Int32: Owner], currentUID: UInt32, selfPID: Int32) -> BuildResult {
        var merged: [String: Row] = [:]
        for l in scan.listeners {
            let key = "\(l.port)-\(l.pid)"
            let owner = owners[l.pid]
            let mine = owner?.uid == currentUID
            if var existing = merged[key] {
                if !existing.addresses.contains(l.address) { existing.addresses.append(l.address) }
                existing.exposure = combine(existing.exposure, exposure(ofAddress: l.address))
                merged[key] = existing
            } else {
                merged[key] = Row(port: l.port, pid: l.pid, command: l.command, addresses: [l.address],
                                  exposure: exposure(ofAddress: l.address), owner: owner, isMine: mine,
                                  canTerminate: isTerminable(pid: l.pid, ownerUID: owner?.uid,
                                                             currentUID: currentUID, selfPID: selfPID))
            }
        }
        let rows = merged.values.sorted { ($0.port, $0.pid) < ($1.port, $1.pid) }
        return BuildResult(rows: rows, uninspectable: scan.uninspectable, scanSucceeded: scan.readSucceeded)
    }

    /// The most exposed of two exposures wins: a socket also open on `*` is reachable from the LAN
    /// even if its IPv4 twin is loopback-only.
    static func combine(_ a: Exposure, _ b: Exposure) -> Exposure {
        if a == .allInterfaces || b == .allInterfaces { return .allInterfaces }
        if a == .specific || b == .specific { return .specific }
        return .localOnly
    }

    // MARK: - Who may be stopped

    /// A Stop button exists only when sending the signal can work and cannot hit the wrong thing:
    /// the process is the user's own (otherwise the OS answers EPERM — measured on a root process),
    /// it is not pid 0/1 (kernel/launchd), and it is not XFinder itself.
    static func isTerminable(pid: Int32, ownerUID: UInt32?, currentUID: UInt32, selfPID: Int32) -> Bool {
        guard let ownerUID, ownerUID == currentUID else { return false }
        return pid > 1 && pid != selfPID
    }

    /// Re-checked at the moment of the click. The list can be seconds old, and a pid freed and
    /// reused by an unrelated process would be killed by a stale Stop button — so the pid must
    /// STILL be the same command and STILL the user's. `proc_name` truncates command names, so
    /// either name may be a prefix of the other.
    static func isSafeToSignal(pid: Int32, listedCommand: String, currentCommand: String?,
                               currentOwnerUID: UInt32?, currentUID: UInt32, selfPID: Int32) -> Bool {
        guard isTerminable(pid: pid, ownerUID: currentOwnerUID, currentUID: currentUID, selfPID: selfPID),
              let currentCommand, !currentCommand.isEmpty, !listedCommand.isEmpty else { return false }
        let a = currentCommand.lowercased(), b = listedCommand.lowercased()
        return a.hasPrefix(b) || b.hasPrefix(a)
    }

    // MARK: - Filter

    /// Digits match a port (or pid) by substring; anything else matches the command name.
    static func filter(_ rows: [Row], query: String) -> [Row] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return rows }
        if q.allSatisfy(\.isNumber) {
            return rows.filter { String($0.port).contains(q) || String($0.pid) == q }
        }
        return rows.filter { $0.command.localizedCaseInsensitiveContains(q) }
    }
}
