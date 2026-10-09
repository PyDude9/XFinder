import Foundation

/// The pure half of the open-ports page: turning `netstat -anv` + `ps` text into rows, and the
/// rules about who may be stopped. No process spawning here, so every rule is pinned by tests.
///
/// The job: *"something is holding port 3000 — what, and can I stop it?"*
///
/// Why `netstat` and not `lsof`: measured on this Mac, `lsof` without root cannot see another
/// user's sockets (it listed Chrome's UDP 5353 but not root's `mDNSResponder` on the same port),
/// so a page built on it would report a port as free while a root process holds it — an honest
/// absence turned into a lie. `netstat -anv` lists every user's listeners with a `process:pid`
/// column. Stopping is a separate question: `kill -0` on that same root process fails with
/// "operation not permitted", so such rows are SHOWN but never offered a Stop button.
enum PortList {

    // MARK: - Raw rows

    struct RawListener: Equatable {
        var port: Int
        var address: String        // "*", "127.0.0.1", "::1", …
        var pid: Int32
        var command: String
    }

    struct NetstatParse: Equatable {
        var listeners: [RawListener]
        /// Lines that said LISTEN. If this exceeds `listeners.count`, the format changed under us
        /// and the page must say the list is incomplete instead of presenting it as whole.
        var listenLines: Int
        /// Whether the output carried netstat's own title line ("Active Internet connections…").
        /// Real output ALWAYS does, even on a machine with nothing listening. Output without it is
        /// not "an empty list" — it is a failed read, and presenting it as "no open ports" would be
        /// a false all-clear. Measured: from some restricted parent processes `netstat -anv -p tcp`
        /// exits 0 with ZERO bytes; the same command from launchd returns the full list.
        var sawHeader: Bool = false
        var unparsed: Int { listenLines - listeners.count }
    }

    /// Parse `netstat -anv -p tcp`. A LISTEN line looks like (measured):
    ///
    ///     tcp4  0  0  127.0.0.1.52478  *.*  LISTEN  0  0  131072  131072  language_server:32865  00100 00000006 0000000000
    ///
    /// The process column is `name:pid` and the name may contain spaces
    /// (`Google Chrome Helper:2221`), so it cannot be a single whitespace token: it is everything
    /// between the 10th token and the last three (state, options, and a trailing hex word).
    static func parseNetstat(_ text: String) -> NetstatParse {
        var out: [RawListener] = []
        var listenLines = 0
        var sawHeader = false
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            if line.hasPrefix("Active Internet connections") { sawHeader = true }
            let t = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard t.count >= 6, t[0].hasPrefix("tcp"), t[5] == "LISTEN" else { continue }
            listenLines += 1
            guard t.count >= 14 else { continue }
            guard let (address, port) = splitLocal(t[3]) else { continue }
            let procTokens = t[10..<(t.count - 3)]
            let proc = procTokens.joined(separator: " ")
            guard let colon = proc.lastIndex(of: ":"),
                  let pid = Int32(proc[proc.index(after: colon)...]) else { continue }
            let name = String(proc[..<colon]).trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { continue }
            out.append(RawListener(port: port, address: address, pid: pid, command: name))
        }
        return NetstatParse(listeners: out, listenLines: listenLines, sawHeader: sawHeader)
    }

    /// `127.0.0.1.52478` → ("127.0.0.1", 52478); `*.61357` → ("*", 61357); `::1.3000` → ("::1", 3000).
    /// netstat joins address and port with a dot, so the port is whatever follows the LAST dot.
    static func splitLocal(_ token: String) -> (String, Int)? {
        guard let dot = token.lastIndex(of: "."),
              let port = Int(token[token.index(after: dot)...]), (1...65535).contains(port) else { return nil }
        let address = String(token[..<dot])
        return address.isEmpty ? nil : (address, port)
    }

    // MARK: - ps

    struct Owner: Equatable { var uid: UInt32; var user: String }

    /// `ps -axo pid=,uid=,user=` → pid → owner. Lines that do not parse are skipped.
    static func parsePs(_ text: String) -> [Int32: Owner] {
        var map: [Int32: Owner] = [:]
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let t = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard t.count >= 3, let pid = Int32(t[0]), let uid = UInt32(t[1]) else { continue }
            map[pid] = Owner(uid: uid, user: t[2...].joined(separator: " "))
        }
        return map
    }

    /// `ps -o uid=,comm= -p <pid>` → (uid, command basename). `comm` is a full path
    /// (`/usr/sbin/rapportd`, or one with spaces) and the listed name is the short one, so the
    /// basename is what is compared. nil when the process is gone (ps prints nothing).
    static func parsePsProcess(_ text: String) -> (uid: UInt32, command: String)? {
        let line = text.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? ""
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let space = trimmed.firstIndex(where: { $0 == " " || $0 == "\t" }),
              let uid = UInt32(trimmed[..<space]) else { return nil }
        let path = trimmed[space...].trimmingCharacters(in: .whitespaces)
        guard !path.isEmpty else { return nil }
        let base = path.split(separator: "/").last.map(String.init) ?? path
        return base.isEmpty ? nil : (uid, base)
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
        /// nil when `ps` did not know the pid (it exited between the two reads).
        var owner: Owner?
        var isMine: Bool
        var canTerminate: Bool
        var id: String { "\(port)-\(pid)" }
    }

    struct BuildResult: Equatable {
        var rows: [Row]
        /// Listeners whose line could not be parsed — surfaced, never hidden.
        var unparsedLines: Int
        /// False when netstat's output was empty or not netstat's at all. The page must show an
        /// error then, never an empty list.
        var netstatWasValid: Bool
    }

    /// Join netstat's listeners with ps's owners, merge the IPv4/IPv6 twins of one socket into a
    /// single row (`*.5000` appears as both `tcp4` and `tcp6`), and decide who may be stopped.
    static func build(netstat: NetstatParse, owners: [Int32: Owner], currentUID: UInt32, selfPID: Int32) -> BuildResult {
        var merged: [String: Row] = [:]
        for l in netstat.listeners {
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
        return BuildResult(rows: rows, unparsedLines: max(0, netstat.unparsed), netstatWasValid: netstat.sawHeader)
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
    /// STILL be the same command and STILL the user's. `ps`/`netstat` truncate command names, so
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
