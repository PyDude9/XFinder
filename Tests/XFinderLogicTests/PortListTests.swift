import XCTest
import Foundation

final class PortListTests: XCTestCase {

    // Lines copied from `netstat -anv -p tcp` on this Mac (2026-10-09, macOS 27.0), except the one
    // marked SYNTHESISED, which reproduces the real column layout around a name with spaces.
    private let header = """
    Active Internet connections (including servers)
    Proto Recv-Q Send-Q  Local Address          Foreign Address        (state)          rxbytes      txbytes  rhiwat  shiwat          process:pid    state  options
    """
    private let real = """
    tcp4       0      0  127.0.0.1.52478        *.*                    LISTEN                 0            0  131072  131072  language_server:32865  00100 00000006 0000000000
    tcp4       0      0  127.0.0.1.52476        *.*                    LISTEN                 0            0  131072  131072      Antigravity:32703  00100 00000106 0000000000
    tcp46      0      0  *.61357                *.*                    LISTEN                 0            0  131072  131072         rapportd:452    00100 00000006 0000000000
    tcp6       0      0  *.5000                 *.*                    LISTEN                 0            0  131072  131072    ControlCenter:504    00100 00000006 0000000000
    tcp4       0      0  *.5000                 *.*                    LISTEN                 0            0  131072  131072    ControlCenter:504    00100 00000006 0000000000
    """
    // SYNTHESISED: the process column holds a name with spaces.
    private let spaced = "tcp4       0      0  127.0.0.1.9222         *.*                    LISTEN                 0            0  131072  131072  Google Chrome Helper:2221  00100 00000006 0000000000"

    // MARK: - netstat parsing

    func testParsesRealLinesIncludingBothIPFamilies() {
        let p = PortList.parseNetstat(header + "\n" + real)
        XCTAssertEqual(p.listenLines, 5)
        XCTAssertEqual(p.listeners.count, 5)
        XCTAssertEqual(p.unparsed, 0)
        XCTAssertEqual(p.listeners[0], .init(port: 52478, address: "127.0.0.1", pid: 32865, command: "language_server"))
        XCTAssertEqual(p.listeners[2], .init(port: 61357, address: "*", pid: 452, command: "rapportd"))
    }

    func testProcessNamesWithSpacesAreNotTruncated() {
        let p = PortList.parseNetstat(spaced)
        XCTAssertEqual(p.listeners, [.init(port: 9222, address: "127.0.0.1", pid: 2221, command: "Google Chrome Helper")],
                       "an awk-style whitespace split would have produced a pid-less 'Chrome' and dropped the row")
    }

    func testNonListenLinesAndHeadersAreIgnoredAndNotCounted() {
        let text = header + "\n" + """
        tcp4       0      0  192.168.1.5.52000      17.253.1.1.443         ESTABLISHED       100          200  131072  131072          Safari:900    00100 00000006 0000000000
        tcp4       0      0  192.168.1.5.52001      17.253.1.1.443         TIME_WAIT           0            0  131072  131072          kernel:0    00100 00000006 0000000000
        udp4       0      0  *.5353                 *.*                                        0            0  196724    9216      Chrome:2221  00000 00000000 0000000000
        """
        let p = PortList.parseNetstat(text)
        XCTAssertEqual(p.listenLines, 0)
        XCTAssertTrue(p.listeners.isEmpty)
    }

    /// The page must be able to say "this list is incomplete". A LISTEN line the parser cannot read
    /// must show up as `unparsed`, not vanish.
    func testAnUnreadableListenLineIsCountedNotSilentlyDropped() {
        let bad = "tcp4  0  0  127.0.0.1.8080  *.*  LISTEN  no-process-column-at-all"
        let p = PortList.parseNetstat(real + "\n" + bad)
        XCTAssertEqual(p.listenLines, 6)
        XCTAssertEqual(p.listeners.count, 5)
        XCTAssertEqual(p.unparsed, 1)
        let built = PortList.build(netstat: p, owners: [:], currentUID: 502, selfPID: 1)
        XCTAssertEqual(built.unparsedLines, 1, "the build result carries the warning to the UI")
    }

    func testLocalAddressSplitsOnTheLastDot() {
        XCTAssertTrue(PortList.splitLocal("127.0.0.1.52478")! == ("127.0.0.1", 52478))
        XCTAssertTrue(PortList.splitLocal("*.61357")! == ("*", 61357))
        XCTAssertTrue(PortList.splitLocal("::1.3000")! == ("::1", 3000))
        XCTAssertTrue(PortList.splitLocal("fe80::1%lo0.8080")! == ("fe80::1%lo0", 8080))
        XCTAssertNil(PortList.splitLocal("*.0"), "port 0 is not a listening port")
        XCTAssertNil(PortList.splitLocal("*.99999"))
        XCTAssertNil(PortList.splitLocal("nodot"))
        XCTAssertNil(PortList.splitLocal(".80"))
    }

    // MARK: - ps parsing

    func testParsesPsOwnersIncludingUnderscoreUsersAndLeadingSpaces() {
        let ps = """
          452   502 wolong
          252    65 _mdnsresponder
            1     0 root
        garbage line
        """
        let map = PortList.parsePs(ps)
        XCTAssertEqual(map[452], .init(uid: 502, user: "wolong"))
        XCTAssertEqual(map[252], .init(uid: 65, user: "_mdnsresponder"))
        XCTAssertEqual(map[1]?.uid, 0)
        XCTAssertEqual(map.count, 3, "the malformed line is skipped, not turned into an entry")
    }

    // MARK: - exposure

    func testExposureClassification() {
        for a in ["*", "0.0.0.0", "::"] { XCTAssertEqual(PortList.exposure(ofAddress: a), .allInterfaces, a) }
        for a in ["127.0.0.1", "127.1.2.3", "::1", "localhost"] { XCTAssertEqual(PortList.exposure(ofAddress: a), .localOnly, a) }
        XCTAssertEqual(PortList.exposure(ofAddress: "192.168.1.5"), .specific)
        XCTAssertEqual(PortList.exposure(ofAddress: "fe80::1%lo0"), .specific, "link-local is not loopback")
    }

    func testTheMostExposedTwinWins() {
        XCTAssertEqual(PortList.combine(.localOnly, .allInterfaces), .allInterfaces)
        XCTAssertEqual(PortList.combine(.allInterfaces, .localOnly), .allInterfaces)
        XCTAssertEqual(PortList.combine(.localOnly, .specific), .specific)
        XCTAssertEqual(PortList.combine(.localOnly, .localOnly), .localOnly)
    }

    // MARK: - building rows

    private let owners: [Int32: PortList.Owner] = [
        32865: .init(uid: 502, user: "wolong"), 32703: .init(uid: 502, user: "wolong"),
        452: .init(uid: 502, user: "wolong"), 504: .init(uid: 502, user: "wolong"),
        252: .init(uid: 65, user: "_mdnsresponder"),
    ]

    func testIPv4AndIPv6TwinsOfOneSocketBecomeOneRow() {
        let built = PortList.build(netstat: PortList.parseNetstat(real), owners: owners, currentUID: 502, selfPID: 99_999)
        // 5 netstat lines, but ControlCenter's *.5000 is listed as tcp6 AND tcp4 → 4 rows.
        XCTAssertEqual(built.rows.count, 4)
        let cc = built.rows.first { $0.pid == 504 }
        XCTAssertEqual(cc?.port, 5000)
        XCTAssertEqual(cc?.addresses, ["*"], "the same address from both families is not repeated")
        XCTAssertEqual(cc?.exposure, .allInterfaces)
    }

    func testRowsAreSortedByPortThenPid() {
        let built = PortList.build(netstat: PortList.parseNetstat(real), owners: owners, currentUID: 502, selfPID: 99_999)
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
        let mixed = PortList.parseNetstat(real + "\n" + "tcp4 0 0 *.5353 *.* LISTEN 0 0 131072 131072 mDNSResponder:252 00100 00000006 0000000000")
        let built = PortList.build(netstat: mixed, owners: owners, currentUID: 502, selfPID: 99_999)
        XCTAssertEqual(built.rows.first { $0.pid == 252 }?.canTerminate, false)
        XCTAssertEqual(built.rows.first { $0.pid == 252 }?.isMine, false, "shown, but not stoppable")
        XCTAssertEqual(built.rows.first { $0.pid == 452 }?.canTerminate, true)
        XCTAssertEqual(built.rows.count, 5, "the root-owned listener is SHOWN — hiding it would claim the port is free")
    }

    // MARK: - PID reuse (a stale Stop button must not hit a stranger)

    func testStaleStopIsRefusedWhenThePidNowBelongsToSomethingElse() {
        let ok = PortList.isSafeToSignal(pid: 452, listedCommand: "rapportd", currentCommand: "rapportd",
                                         currentOwnerUID: 502, currentUID: 502, selfPID: 99_999)
        XCTAssertTrue(ok)
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
        // ps/netstat truncate p_comm; the listed name may be a prefix of the live one or the reverse.
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
        let built = PortList.build(netstat: PortList.parseNetstat(real + "\n" + spaced), owners: owners, currentUID: 502, selfPID: 99_999)
        XCTAssertEqual(PortList.filter(built.rows, query: "").count, built.rows.count)
        XCTAssertEqual(PortList.filter(built.rows, query: "5000").map(\.pid), [504])
        XCTAssertEqual(PortList.filter(built.rows, query: "9222").map(\.command), ["Google Chrome Helper"])
        XCTAssertEqual(PortList.filter(built.rows, query: "chrome").count, 1, "text matches the command, case-insensitively")
        XCTAssertEqual(PortList.filter(built.rows, query: "452").map(\.command), ["rapportd"], "a pid also matches")
        XCTAssertTrue(PortList.filter(built.rows, query: "no-such-thing").isEmpty)
        XCTAssertEqual(PortList.filter(built.rows, query: "  5000  ").count, 1, "surrounding spaces are ignored")
    }

    // MARK: - A failed read is not an empty list

    /// Measured: from some restricted parent processes `netstat -anv -p tcp` exits 0 with ZERO
    /// bytes. A page that rendered that as "no open ports" would be a false all-clear.
    func testEmptyNetstatOutputIsAFailedReadNotAnEmptyList() {
        let empty = PortList.parseNetstat("")
        XCTAssertFalse(empty.sawHeader)
        let built = PortList.build(netstat: empty, owners: [:], currentUID: 502, selfPID: 1)
        XCTAssertFalse(built.netstatWasValid, "the UI must show an error here")
        XCTAssertTrue(built.rows.isEmpty)
    }

    func testRealOutputWithNothingListeningIsStillValid() {
        // A quiet machine: the title and column header, but no LISTEN line. Valid, and genuinely empty.
        let quiet = PortList.parseNetstat(header)
        XCTAssertTrue(quiet.sawHeader)
        let built = PortList.build(netstat: quiet, owners: [:], currentUID: 502, selfPID: 1)
        XCTAssertTrue(built.netstatWasValid, "nothing listening is a real answer, unlike no output at all")
        XCTAssertTrue(built.rows.isEmpty)
    }

    func testGarbageOutputIsNotMistakenForNetstat() {
        XCTAssertFalse(PortList.parseNetstat("netstat: sysctl: Operation not permitted\n").sawHeader)
        XCTAssertFalse(PortList.parseNetstat("\n\n").sawHeader)
        XCTAssertTrue(PortList.parseNetstat(header + "\n" + real).sawHeader)
    }

    // MARK: - ps for a single pid (re-check at click time)

    func testParsesPsForOnePidAndReducesThePathToItsBasename() {
        XCTAssertTrue(PortList.parsePsProcess("  502 /usr/sbin/rapportd\n")! == (502, "rapportd"))
        XCTAssertTrue(PortList.parsePsProcess("502 /Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Helpers/Google Chrome Helper.app/Contents/MacOS/Google Chrome Helper")!
                      == (502, "Google Chrome Helper"), "a path with spaces keeps the full last component")
        XCTAssertNil(PortList.parsePsProcess(""), "the process is gone")
        XCTAssertNil(PortList.parsePsProcess("   \n"))
        XCTAssertNil(PortList.parsePsProcess("notanumber /bin/sh"))
        XCTAssertNil(PortList.parsePsProcess("502"), "a uid with no command is not a process")
    }
}
