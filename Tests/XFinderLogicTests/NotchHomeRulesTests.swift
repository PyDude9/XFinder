import XCTest
import Foundation

/// Pure unit tests for Dynamic Island Home ("Tổng quan") snapshot rules:
/// module gating, empty state, active-work priority, narrow/wide layout columns, and L10n keys.
final class NotchHomeRulesTests: XCTestCase {
    typealias R = NotchHomeRules
    typealias Catalog = NotchDestinationCatalog
    typealias Avail = NotchDestinationAvailability

    private let now = Date(timeIntervalSince1970: 1_795_000_000)

    func testEmptyStateWhenNoModulesHaveActiveSnapshots() {
        let snap = R.build(
            R.Input(
                catalog: Catalog.defaultState,
                availability: Avail.builtInOnly,
                now: now,
                nowPlaying: nil,
                calendar: nil,
                activeWork: R.ActiveWorkInput()
            )
        )
        XCTAssertTrue(snap.isEmpty)
        XCTAssertTrue(snap.cards.isEmpty)
        XCTAssertEqual(snap.layoutColumns(isNarrow: false), 1)
        XCTAssertEqual(snap.layoutColumns(isNarrow: true), 1)
        XCTAssertFalse(snap.quickDestinations.isEmpty)
        XCTAssertTrue(snap.quickDestinations.count <= 4)
    }

    func testRespectsCatalogAndAvailabilityGatingForEveryModule() {
        let catalog = Catalog.defaultState
            .setting(.nowPlaying, enabled: false)
            .setting(.calendar, enabled: true)
            .setting(.timer, enabled: false)
            .setting(.agents, enabled: false)
            .setting(.files, enabled: true)

        var avail = Avail.builtInOnly
        avail.calendarReady = false // feature disabled at feature page

        let snap = R.build(
            R.Input(
                catalog: catalog,
                availability: avail,
                now: now,
                nowPlaying: R.NowPlayingInput(headline: "Track", subline: "Artist", isPlaying: true, appName: "Music"),
                calendar: R.CalendarInput(
                    isAuthorized: true,
                    title: "Standup",
                    start: now.addingTimeInterval(600),
                    end: now.addingTimeInterval(2400),
                    isAllDay: false,
                    hasMeetingLink: true,
                    todayCount: 1
                ),
                activeWork: R.ActiveWorkInput(
                    clockLabel: "12:00",
                    clockMode: .pomodoro,
                    clockSymbol: "flame.fill",
                    clockPaused: false,
                    agentCount: 2,
                    agentsNeedingYou: 1,
                    agentBusy: true,
                    stagedFileCount: 3,
                    hasActiveFileTask: false
                )
            )
        )

        // Only `.files` is both enabled and ready; hidden/disabled Now Playing, Calendar, Timer, Agents are omitted.
        XCTAssertEqual(snap.cards.count, 1)
        XCTAssertEqual(snap.cards[0].kind, .activeWork)
        XCTAssertEqual(snap.cards[0].destination, .page(.files))
        XCTAssertEqual(snap.cards[0].extraActiveCount, 0)
        XCTAssertFalse(snap.quickDestinations.contains(.nowPlaying))
        XCTAssertFalse(snap.quickDestinations.contains(.calendar))
    }

    func testUnauthorizedCalendarNeverProducesCardWithoutPrompting() {
        let snap = R.build(
            R.Input(
                catalog: Catalog.defaultState,
                availability: Avail.builtInOnly,
                now: now,
                nowPlaying: nil,
                calendar: R.CalendarInput(
                    isAuthorized: false,
                    title: "Secret Event",
                    start: now.addingTimeInterval(300),
                    end: now.addingTimeInterval(1800),
                    isAllDay: false,
                    hasMeetingLink: false,
                    todayCount: 1
                ),
                activeWork: R.ActiveWorkInput()
            )
        )
        XCTAssertTrue(snap.isEmpty)
    }

    func testThreeCardWideLayoutAndOneColumnNarrowLayout() {
        let snap = R.build(
            R.Input(
                catalog: Catalog.defaultState,
                availability: Avail.builtInOnly,
                now: now,
                nowPlaying: R.NowPlayingInput(headline: "Lofi Beats", subline: "ChilledCow", isPlaying: true, appName: "Music"),
                calendar: R.CalendarInput(
                    isAuthorized: true,
                    title: "Design Sync",
                    start: now.addingTimeInterval(-300),
                    end: now.addingTimeInterval(1500),
                    isAllDay: false,
                    hasMeetingLink: true,
                    todayCount: 2
                ),
                activeWork: R.ActiveWorkInput(
                    clockLabel: "24:15",
                    clockMode: .pomodoro,
                    clockSymbol: "flame.fill",
                    clockPaused: false,
                    agentCount: 1,
                    agentsNeedingYou: 0,
                    agentBusy: true,
                    stagedFileCount: 2,
                    hasActiveFileTask: false
                )
            )
        )

        XCTAssertEqual(snap.cards.map(\.kind), [.nowPlaying, .calendar, .activeWork])
        XCTAssertEqual(snap.layoutColumns(isNarrow: false), 3)
        XCTAssertEqual(snap.layoutColumns(isNarrow: true), 1)
        // Running clock beats staged files and non-waiting busy agents; 2 other active subsystems counted.
        XCTAssertEqual(snap.cards[2].destination, .page(.timer))
        XCTAssertEqual(snap.cards[2].extraActiveCount, 2)
        // Meeting link surfaces meeting badge on calendar card.
        XCTAssertEqual(snap.cards[1].badge, .status(key: "Cuộc họp"))
    }

    func testWaitingAgentTakesPriorityOverRunningClock() {
        let snap = R.build(
            R.Input(
                catalog: Catalog.defaultState,
                availability: Avail.builtInOnly,
                now: now,
                nowPlaying: nil,
                calendar: nil,
                activeWork: R.ActiveWorkInput(
                    clockLabel: "05:00",
                    clockMode: .countdown,
                    clockSymbol: "timer",
                    clockPaused: false,
                    agentCount: 3,
                    agentsNeedingYou: 2,
                    agentBusy: true,
                    stagedFileCount: 0,
                    hasActiveFileTask: false
                )
            )
        )
        XCTAssertEqual(snap.cards.count, 1)
        XCTAssertEqual(snap.cards[0].destination, .page(.agents))
        XCTAssertEqual(snap.cards[0].badge, .countWaiting(2))
        XCTAssertEqual(snap.cards[0].extraActiveCount, 1)
    }

    func testAllHomeL10nKeysExistInStore() throws {
        let store = try L10nFixture.load()
        let requiredKeys = [
            "Tổng quan",
            "Đang phát",
            "Đang tạm dừng",
            "Đang diễn ra",
            "Cuộc họp",
            "Lịch sắp tới",
            "Tác vụ đang chạy",
            "Chưa có hoạt động nào từ các tab đang bật",
            "Bật nhạc, lịch hoặc bắt đầu tác vụ để xem nhanh tại đây.",
            "Mở nhanh",
            "Mở ",
            "Cài đặt",
            "Đang chạy",
            "Đang bận",
            "Đang xử lý tệp",
            " chờ phản hồi",
            " phiên",
            " tệp",
        ]
        for key in requiredKeys {
            guard let entry = store.entries[key] else {
                XCTFail("Missing L10n entry for Home key: \(key)")
                continue
            }
            XCTAssertFalse(entry.en.isEmpty, "Empty English translation for Home key: \(key)")
        }
    }
}
