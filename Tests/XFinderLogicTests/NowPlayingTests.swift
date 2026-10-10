import XCTest
import Foundation

final class NowPlayingTests: XCTestCase {
    typealias NP = NowPlaying
    let t0 = Date(timeIntervalSince1970: 1_760_000_000)

    // MARK: Parsing the helper's lines

    func testParsesHelloEmptyAndSnapshot() {
        XCTAssertEqual(NP.parse(#"{"t":"hello","v":1}"#), .hello(version: 1))
        XCTAssertEqual(NP.parse(#"{"t":"np","empty":true}"#), .empty)
        let line = #"{"t":"np","title":"Xin \"chào\"","artist":"A","album":"B","duration":300.0,"elapsed":42.0,"rate":1.0,"ts":1760000000.0,"playing":true,"pid":4677,"artworkId":"abc","artworkMime":"image/jpeg","artwork":"aGVsbG8="}"#
        guard case .snapshot(let s, let art) = NP.parse(line) else { return XCTFail("not a snapshot") }
        XCTAssertEqual(s.title, "Xin \"chào\"")
        XCTAssertEqual(s.artist, "A"); XCTAssertEqual(s.album, "B")
        XCTAssertEqual(s.duration, 300); XCTAssertEqual(s.elapsed, 42); XCTAssertEqual(s.rate, 1)
        XCTAssertEqual(s.timestamp, t0); XCTAssertTrue(s.playing); XCTAssertEqual(s.pid, 4677)
        XCTAssertEqual(s.artworkID, "abc"); XCTAssertEqual(s.artworkMIME, "image/jpeg")
        XCTAssertEqual(art, "hello".data(using: .utf8))
    }

    func testGarbageAndUnknownLinesNeverBecomeASnapshot() {
        for bad in ["", "not json", "{}", #"{"t":"weird"}"#, "{\"t\":\"np\",\"title\":", #"[1,2]"#] {
            let line = NP.parse(bad)
            if case .snapshot = line { XCTFail("\(bad.debugDescription) parsed as a snapshot") }
            if case .empty = line { XCTFail("\(bad.debugDescription) parsed as empty") }
        }
        XCTAssertEqual(NP.parse(#"{"t":"error","reason":"dlopen"}"#), .error(reason: "dlopen"))
    }

    func testSnapshotWithoutArtworkKeepsTheFieldNil() {
        guard case .snapshot(let s, let art) = NP.parse(#"{"t":"np","title":"T","playing":false,"pid":0}"#) else { return XCTFail() }
        XCTAssertNil(art); XCTAssertNil(s.artworkID); XCTAssertFalse(s.playing)
        XCTAssertTrue(s.hasTrack)
        XCTAssertFalse(NP.Snapshot(playing: true).hasTrack, "no title and no artist is nothing to show")
    }

    func testHeadlineAndSubline() {
        let full = NP.Snapshot(title: "T", artist: "A", album: "B", playing: true)
        XCTAssertEqual(full.headline, "T"); XCTAssertEqual(full.subline, "A · B")
        let noTitle = NP.Snapshot(artist: "A", album: "B", playing: true)
        XCTAssertEqual(noTitle.headline, "A", "the artist stands in for a missing title")
        XCTAssertEqual(noTitle.subline, "B", "and is not repeated underneath")
        XCTAssertEqual(NP.Snapshot(title: "T", playing: true).subline, "")
    }

    // MARK: The playhead without polling

    func testPositionAdvancesOnlyWhilePlayingAndIsClamped() {
        var s = NP.Snapshot(duration: 300, elapsed: 42, rate: 1, timestamp: t0, playing: true)
        XCTAssertEqual(NP.position(of: s, at: t0 + 10), 52)
        s.playing = false                                   // a paused publisher still said rate 1.0 (measured)
        XCTAssertEqual(NP.position(of: s, at: t0 + 10), 42, "paused ⇒ the playhead does not move")
        s.playing = true; s.rate = 2
        XCTAssertEqual(NP.position(of: s, at: t0 + 10), 62)
        XCTAssertEqual(NP.position(of: s, at: t0 + 1000), 300, "never past the end of the track")
        s.elapsed = 5; s.rate = -1
        XCTAssertEqual(NP.position(of: s, at: t0 + 100), 0, "never negative")
        XCTAssertNil(NP.position(of: NP.Snapshot(playing: true), at: t0), "nothing reported ⇒ nil, not 0")
    }

    func testTimeLabel() {
        XCTAssertEqual(NP.timeLabel(0), "0:00")
        XCTAssertEqual(NP.timeLabel(59.9), "0:59")
        XCTAssertEqual(NP.timeLabel(61), "1:01")
        XCTAssertEqual(NP.timeLabel(3600), "1:00:00")
        XCTAssertEqual(NP.timeLabel(-5), "0:00")
        XCTAssertEqual(NP.timeLabel(.nan), "0:00")
        XCTAssertEqual(NP.timeLabel(.infinity), "0:00")
    }

    // MARK: Supervising the helper

    func testACrashLoopIsGivenUpAfterFiveAttemptsWithGrowingDelays() {
        var sup = NP.Supervisor()
        var delays: [TimeInterval] = []
        for _ in 0..<5 {
            guard case .restart(let d) = sup.helperExited(afterUptime: 0.2) else { return XCTFail("gave up too early") }
            delays.append(d)
        }
        XCTAssertEqual(delays, [0.5, 1, 2, 4, 8])
        XCTAssertEqual(sup.helperExited(afterUptime: 0.2), .giveUp)
    }

    func testAHelperThatRanForAWhileIsNotACrashLoop() {
        var sup = NP.Supervisor()
        for _ in 0..<4 { _ = sup.helperExited(afterUptime: 0.1) }
        XCTAssertEqual(sup.helperExited(afterUptime: 3600), .restart(after: 0.5),
                       "an hour of service then a death (sleep/wake) starts the count over")
        XCTAssertEqual(sup.helperExited(afterUptime: 59), .restart(after: 1), "just under the bar counts")
    }

    func testEveryAvailabilityMessageIsInTheStore() throws {
        let store = try L10nFixture.load()
        XCTAssertEqual(NP.Availability.allCases.count, 6, "the case list collapsed; the loop would prove nothing")
        for a in NP.Availability.allCases {
            let key = a.messageKey
            XCTAssertNotNil(store.entries[key], "\(key.debugDescription) is not in L10n.strings.json — it would reach the English UI as Vietnamese")
        }
    }

    func testOnlyAReadyHelperIsLive() {
        for a in NP.Availability.allCases {
            XCTAssertEqual(a.isLive, a == .ready, "\(a): a dead or restarting helper knows nothing — nothing from it may show as live")
        }
    }

    func testHostScriptLoadsTheDylibThenSleeps() {
        let s = NP.hostScript()
        XCTAssertTrue(s.contains("DynaLoader::dl_load_file($ARGV[0], 0)"))
        XCTAssertTrue(s.contains("select(undef, undef, undef"), "the host must block, not exit, after loading")
        XCTAssertFalse(s.contains("\n"), "a one-liner for `perl -e`")
    }
}
