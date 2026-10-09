import XCTest
import Foundation
import Darwin

final class PortListTests: XCTestCase {

    private func l(_ port: Int, _ addr: String, _ pid: Int32, _ cmd: String) -> PortList.RawListener {
        .init(port: port, address: addr, pid: pid, command: cmd)
    }
    /// Shaped like a real scan of this Mac (2026-10-09): ControlCenter appears once per address family.
    private var sample: [PortList.RawListener] {
        [l(52478, "127.0.0.1", 32865, "language_server"), l(52476, "127.0.0.1", 32703, "Antigravity"),
         l(61357, "*", 452, "rapportd"), l(5000, "*", 504, "ControlCenter"), l(5000, "*", 504, "ControlCenter"),
         l(5000, "::1", 504, "ControlCenter")]
    }
    private func scan(_ ls: [PortList.RawListener], uninspectable: Int = 0, ok: Bool = true) -> PortList.ListenerScan {
        .init(listeners: ls, readSucceeded: ok, uninspectable: uninspectable)
    }
    private let owners: [Int32: PortList.Owner] = [
        32865: .init(uid: 502, user: "wolong"), 32703: .init(uid: 502, user: "wolong"),
        452: .init(uid: 502, user: "wolong"), 504: .init(uid: 502, user: "wolong"),
        252: .init(uid: 65, user: "_mdnsresponder"),
    ]

    // MARK: - exposure

    func testExposureClassification() {
        XCTAssertEqual(PortList.exposure(ofAddress: "*"), .allInterfaces)
        XCTAssertEqual(PortList.exposure(ofAddress: "0.0.0.0"), .allInterfaces)
        XCTAssertEqual(PortList.exposure(ofAddress: "::"), .allInterfaces)
        XCTAssertEqual(PortList.exposure(ofAddress: "127.0.0.1"), .localOnly)
        XCTAssertEqual(PortList.exposure(ofAddress: "::1"), .localOnly)
        XCTAssertEqual(PortList.exposure(ofAddress: "192.168.1.7"), .specific)
    }

    func testTheMostExposedTwinWins() {
        XCTAssertEqual(PortList.combine(.localOnly, .allInterfaces), .allInterfaces)
        XCTAssertEqual(PortList.combine(.localOnly, .specific), .specific)
        XCTAssertEqual(PortList.combine(.localOnly, .localOnly), .localOnly)
    }

    // MARK: - building rows

    func testAddressFamilyTwinsOfOneSocketBecomeOneRow() {
        let built = PortList.build(scan: scan(sample), owners: owners, currentUID: 502, selfPID: 99_999)
        XCTAssertEqual(built.rows.count, 4, "ControlCenter's three listeners on :5000 are one row")
        let cc = built.rows.first { $0.pid == 504 }
        XCTAssertEqual(cc?.port, 5000)
        XCTAssertEqual(cc?.addresses, ["*", "::1"], "the same address twice is not repeated")
        XCTAssertEqual(cc?.exposure, .allInterfaces, "also open on * ⇒ reachable from the LAN")
    }

    func testRowsAreSortedByPortThenPid() {
        let built = PortList.build(scan: scan(sample), owners: owners, currentUID: 502, selfPID: 99_999)
        XCTAssertEqual(built.rows.map(\.port), built.rows.map(\.port).sorted())
        XCTAssertEqual(built.rows.first?.port, 5000)
    }

    // MARK: - who may be stopped

    func testOnlyTheUsersOwnProcessesCanBeStopped() {
        XCTAssertTrue(PortList.isTerminable(pid: 452, ownerUID: 502, currentUID: 502, selfPID: 99_999))
        XCTAssertFalse(PortList.isTerminable(pid: 252, ownerUID: 65, currentUID: 502, selfPID: 99_999),
                       "measured: kill -0 on root's mDNSResponder is 'operation not permitted'")
        XCTAssertFalse(PortList.isTerminable(pid: 452, ownerUID: nil, currentUID: 502, selfPID: 99_999),
                       "an unknown owner is not assumed to be the user")
    }

    func testKernelLaunchdAndXFinderItselfAreNeverOffered() {
        XCTAssertFalse(PortList.isTerminable(pid: 0, ownerUID: 502, currentUID: 502, selfPID: 99_999))
        XCTAssertFalse(PortList.isTerminable(pid: 1, ownerUID: 502, currentUID: 502, selfPID: 99_999))
        XCTAssertFalse(PortList.isTerminable(pid: 777, ownerUID: 502, currentUID: 502, selfPID: 777), "never itself")
        XCTAssertFalse(PortList.isTerminable(pid: -5, ownerUID: 502, currentUID: 502, selfPID: 99_999))
    }

    func testRowsCarryCanTerminateFromThoseRules() {
        let mixed = scan(sample + [l(5353, "*", 252, "mDNSResponder")])
        let built = PortList.build(scan: mixed, owners: owners, currentUID: 502, selfPID: 99_999)
        XCTAssertEqual(built.rows.first { $0.pid == 252 }?.canTerminate, false)
        XCTAssertEqual(built.rows.first { $0.pid == 252 }?.isMine, false, "shown, but not stoppable")
        XCTAssertEqual(built.rows.first { $0.pid == 452 }?.canTerminate, true)
        XCTAssertEqual(built.rows.count, 5, "a visible root-owned listener is SHOWN — hiding it would claim the port is free")
    }

    // MARK: - PID reuse (a stale Stop button must not hit a stranger)

    func testStaleStopIsRefusedWhenThePidNowBelongsToSomethingElse() {
        XCTAssertTrue(PortList.isSafeToSignal(pid: 452, listedCommand: "rapportd", currentCommand: "rapportd",
                                              currentOwnerUID: 502, currentUID: 502, selfPID: 99_999))
        XCTAssertFalse(PortList.isSafeToSignal(pid: 452, listedCommand: "rapportd", currentCommand: "Safari",
                                               currentOwnerUID: 502, currentUID: 502, selfPID: 99_999),
                       "pid reused by Safari after the list was drawn")
        XCTAssertFalse(PortList.isSafeToSignal(pid: 452, listedCommand: "rapportd", currentCommand: nil,
                                               currentOwnerUID: nil, currentUID: 502, selfPID: 99_999),
                       "the process is gone — nothing to signal")
        XCTAssertFalse(PortList.isSafeToSignal(pid: 452, listedCommand: "rapportd", currentCommand: "rapportd",
                                               currentOwnerUID: 0, currentUID: 502, selfPID: 99_999),
                       "ownership changed to root")
    }

    func testTruncatedCommandNamesStillMatchEitherWay() {
        XCTAssertTrue(PortList.isSafeToSignal(pid: 10, listedCommand: "Google Chrome He", currentCommand: "Google Chrome Helper",
                                              currentOwnerUID: 502, currentUID: 502, selfPID: 1_000))
        XCTAssertTrue(PortList.isSafeToSignal(pid: 10, listedCommand: "Google Chrome Helper", currentCommand: "Google Chrome He",
                                              currentOwnerUID: 502, currentUID: 502, selfPID: 1_000))
        XCTAssertTrue(PortList.isSafeToSignal(pid: 10, listedCommand: "NODE", currentCommand: "node",
                                              currentOwnerUID: 502, currentUID: 502, selfPID: 1_000), "case-insensitive")
        XCTAssertFalse(PortList.isSafeToSignal(pid: 10, listedCommand: "", currentCommand: "node",
                                               currentOwnerUID: 502, currentUID: 502, selfPID: 1_000),
                       "an empty listed name would match anything")
    }

    // MARK: - filter

    func testFilterMatchesPortByDigitsAndCommandByText() {
        let built = PortList.build(scan: scan(sample + [l(9222, "127.0.0.1", 2221, "Google Chrome Helper")]),
                                   owners: owners, currentUID: 502, selfPID: 99_999)
        XCTAssertEqual(PortList.filter(built.rows, query: "").count, built.rows.count)
        XCTAssertEqual(PortList.filter(built.rows, query: "5000").map(\.pid), [504])
        XCTAssertEqual(PortList.filter(built.rows, query: "9222").map(\.command), ["Google Chrome Helper"])
        XCTAssertEqual(PortList.filter(built.rows, query: "chrome").count, 1, "text matches the command, case-insensitively")
        XCTAssertEqual(PortList.filter(built.rows, query: "452").map(\.command), ["rapportd"], "a pid also matches")
        XCTAssertTrue(PortList.filter(built.rows, query: "no-such-thing").isEmpty)
        XCTAssertEqual(PortList.filter(built.rows, query: "  5000  ").count, 1, "surrounding spaces are ignored")
    }

    // MARK: - A failed scan is not an empty list; an incomplete one says so

    func testAFailedScanIsNotAnEmptyList() {
        let built = PortList.build(scan: scan([], ok: false), owners: [:], currentUID: 502, selfPID: 1)
        XCTAssertFalse(built.scanSucceeded, "the UI must show an error, never 'no open ports'")
        XCTAssertTrue(built.rows.isEmpty)
    }

    func testAQuietMachineIsAValidEmptyAnswer() {
        let built = PortList.build(scan: scan([]), owners: [:], currentUID: 502, selfPID: 1)
        XCTAssertTrue(built.scanSucceeded)
        XCTAssertTrue(built.rows.isEmpty)
    }

    func testUninspectableProcessesAreCarriedThroughSoTheListIsNeverPresentedAsComplete() {
        let built = PortList.build(scan: scan(sample, uninspectable: 303), owners: owners, currentUID: 502, selfPID: 1)
        XCTAssertEqual(built.uninspectable, 303)
    }

    // MARK: - The real scanner, against a real socket

    /// Opens a genuine listening socket in THIS process and requires the scanner to find it with the
    /// right port, pid, owner and address — and to stop reporting it once closed. No fixture can
    /// stand in for this: the bugs it would catch are byte-order and struct-layout mistakes.
    func testScannerFindsARealListenerAndForgetsItWhenClosed() throws {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        XCTAssertGreaterThanOrEqual(fd, 0)
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        addr.sin_port = 0
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        XCTAssertEqual(bound, 0)
        XCTAssertEqual(listen(fd, 1), 0)
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &len) }
        }
        XCTAssertEqual(named, 0)
        let port = Int(UInt16(bigEndian: addr.sin_port))
        XCTAssertGreaterThan(port, 0)

        // Add ESTABLISHED sockets in this same process (a client and the accepted peer). They are TCP
        // sockets too; reporting them as listeners would be the bug this guards against.
        let client = socket(AF_INET, SOCK_STREAM, 0)
        let connected = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(client, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        XCTAssertEqual(connected, 0)
        let accepted = accept(fd, nil, nil)
        XCTAssertGreaterThanOrEqual(accepted, 0)
        defer { close(client); close(accepted) }

        let found = PortScanner.scan()
        XCTAssertTrue(found.scan.readSucceeded)
        XCTAssertEqual(found.scan.listeners.filter { $0.pid == getpid() }.count, 1,
                       "only the LISTEN socket counts — the connected client and accepted peer are not listeners")
        let mine = found.scan.listeners.filter { $0.pid == getpid() && $0.port == port }
        XCTAssertEqual(mine.count, 1, "the scanner must find this process's listener on :\(port)")
        XCTAssertEqual(mine.first?.address, "127.0.0.1")
        XCTAssertEqual(found.owners[getpid()]?.uid, getuid())

        close(fd)
        let after = PortScanner.scan()
        XCTAssertFalse(after.scan.listeners.contains { $0.pid == getpid() && $0.port == port },
                       "a closed socket must disappear")
    }

    func testScannerReportsAProcessItCannotSeeAsUninspectableNotAsEmpty() {
        let found = PortScanner.scan()
        XCTAssertGreaterThan(found.scan.uninspectable, 0, "launchd and other users' processes are not inspectable")
        XCTAssertNil(PortScanner.process(pid: 99_999_999), "a pid that does not exist has no owner")
        let me = PortScanner.process(pid: getpid())
        XCTAssertEqual(me?.uid, getuid())
    }
}
