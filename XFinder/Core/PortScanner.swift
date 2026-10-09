import Foundation
import Darwin

/// Reads TCP listeners through `libproc` — the same public API Activity Monitor-style tools use —
/// instead of spawning `netstat` (which returns nothing when spawned; see `PortList`).
///
/// In-process, so it costs no subprocess and has no lineage quirks. It can only open processes the
/// user may inspect; the rest are counted in `uninspectable`.
enum PortScanner {

    static func scan() -> (scan: PortList.ListenerScan, owners: [Int32: PortList.Owner]) {
        let capacity = proc_listallpids(nil, 0)
        guard capacity > 0 else {
            return (PortList.ListenerScan(listeners: [], readSucceeded: false, uninspectable: 0), [:])
        }
        var pids = [Int32](repeating: 0, count: Int(capacity) + 64)
        let filled = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<Int32>.size))
        guard filled > 0 else {
            return (PortList.ListenerScan(listeners: [], readSucceeded: false, uninspectable: 0), [:])
        }

        var listeners: [PortList.RawListener] = []
        var owners: [Int32: PortList.Owner] = [:]
        var uninspectable = 0
        for pid in pids.prefix(Int(filled)) where pid > 0 {
            let found = tcpListeners(of: pid)
            switch found {
            case nil: uninspectable += 1
            case let l? where l.isEmpty: break
            case let l?:
                listeners += l
                if let info = process(pid: pid) { owners[pid] = PortList.Owner(uid: info.uid, user: info.user) }
            }
        }
        return (PortList.ListenerScan(listeners: listeners, readSucceeded: true, uninspectable: uninspectable), owners)
    }

    /// The live owner and short command name of a pid, or nil when it is gone.
    static func process(pid: Int32) -> (uid: UInt32, user: String, command: String)? {
        var bsd = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsd, size) == size else { return nil }
        var name = [CChar](repeating: 0, count: 256)
        proc_name(pid, &name, 256)
        let command = String(cString: name)
        guard !command.isEmpty else { return nil }
        let user = getpwuid(bsd.pbi_uid).map { String(cString: $0.pointee.pw_name) } ?? String(bsd.pbi_uid)
        return (bsd.pbi_uid, user, command)
    }

    /// nil = the OS refused to list this process's descriptors.
    private static func tcpListeners(of pid: Int32) -> [PortList.RawListener]? {
        let bytes = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard bytes > 0 else { return nil }
        var fds = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(bytes) / MemoryLayout<proc_fdinfo>.size + 8)
        let got = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &fds, Int32(fds.count * MemoryLayout<proc_fdinfo>.size))
        guard got > 0 else { return nil }
        var command: String?
        var out: [PortList.RawListener] = []
        for fd in fds.prefix(Int(got) / MemoryLayout<proc_fdinfo>.size) where fd.proc_fdtype == UInt32(PROX_FDTYPE_SOCKET) {
            var si = socket_fdinfo()
            let size = Int32(MemoryLayout<socket_fdinfo>.size)
            guard proc_pidfdinfo(pid, fd.proc_fd, PROC_PIDFDSOCKETINFO, &si, size) == size,
                  si.psi.soi_kind == Int32(SOCKINFO_TCP),
                  si.psi.soi_proto.pri_tcp.tcpsi_state == TSI_S_LISTEN else { continue }
            let ini = si.psi.soi_proto.pri_tcp.tcpsi_ini
            // `insi_lport` holds the port in network byte order in its low 16 bits.
            let port = Int(UInt16(bigEndian: UInt16(truncatingIfNeeded: ini.insi_lport)))
            guard (1...65535).contains(port) else { continue }
            if command == nil {
                var name = [CChar](repeating: 0, count: 256)
                proc_name(pid, &name, 256)
                command = String(cString: name)
            }
            guard let command, !command.isEmpty else { continue }
            out.append(PortList.RawListener(port: port, address: address(of: ini), pid: pid, command: command))
        }
        return out
    }

    private static func address(of ini: in_sockinfo) -> String {
        var buf = [CChar](repeating: 0, count: 64)
        if ini.insi_vflag & UInt8(INI_IPV6) != 0 {
            var a = ini.insi_laddr.ina_6
            inet_ntop(AF_INET6, &a, &buf, 64)
            let s = String(cString: buf)
            return s == "::" ? "*" : s
        }
        var a = ini.insi_laddr.ina_46.i46a_addr4
        inet_ntop(AF_INET, &a, &buf, 64)
        let s = String(cString: buf)
        return s == "0.0.0.0" ? "*" : s
    }
}
