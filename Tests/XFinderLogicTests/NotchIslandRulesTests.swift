import XCTest
import Foundation

final class NotchIslandRulesTests: XCTestCase {
    typealias Page = NotchSurfaceMachine.Page

    // MARK: - Single collapsed signal

    func testCollapsedSignalShowsAtMostOneSignalAndFollowsPriority() {
        // Nothing active ⇒ .none
        let idle = NotchCollapsedSignal.resolve(
            itemCount: 0, timerActive: false, timerPaused: false,
            nowPlayingActive: false, nowPlayingPlaying: false,
            agentActive: false, agentBusy: false, agentsNeedingYou: 0
        )
        XCTAssertEqual(idle, .none)
        XCTAssertFalse(idle.projection(agentCount: 0).isVisible)

        // All signals active at once ⇒ agent needing you wins; projection enables ONLY agent.
        let waiting = NotchCollapsedSignal.resolve(
            itemCount: 4, timerActive: true, timerPaused: false,
            nowPlayingActive: true, nowPlayingPlaying: true,
            agentActive: true, agentBusy: true, agentsNeedingYou: 1
        )
        XCTAssertEqual(waiting, .agentNeedsYou)
        let wp = waiting.projection(agentCount: 2)
        XCTAssertTrue(wp.agentActive)
        XCTAssertEqual(wp.itemCount, 0)
        XCTAssertFalse(wp.timerActive)
        XCTAssertFalse(wp.nowPlayingActive)
        XCTAssertEqual(waiting.targetPage, .agents)

        // Running timer beats held files and music; projection shows ONLY timer.
        let timer = NotchCollapsedSignal.resolve(
            itemCount: 3, timerActive: true, timerPaused: false,
            nowPlayingActive: true, nowPlayingPlaying: true,
            agentActive: true, agentBusy: true, agentsNeedingYou: 0
        )
        XCTAssertEqual(timer, .timerRunning)
        let tp = timer.projection(agentCount: 2)
        XCTAssertTrue(tp.timerActive)
        XCTAssertEqual(tp.itemCount, 0)
        XCTAssertFalse(tp.nowPlayingActive)
        XCTAssertFalse(tp.agentActive)
        XCTAssertEqual(timer.targetPage, .timer)

        // When timer finishes while files are held ⇒ falls back cleanly to held files count.
        let files = NotchCollapsedSignal.resolve(
            itemCount: 3, timerActive: false, timerPaused: false,
            nowPlayingActive: true, nowPlayingPlaying: true,
            agentActive: true, agentBusy: true, agentsNeedingYou: 0
        )
        XCTAssertEqual(files, .files(3))
        let fp = files.projection(agentCount: 2)
        XCTAssertEqual(fp.itemCount, 3)
        XCTAssertFalse(fp.timerActive)
        XCTAssertFalse(fp.nowPlayingActive)
        XCTAssertFalse(fp.agentActive)
        XCTAssertEqual(files.targetPage, .files)

        // Playing track wins over idle agent when no files/timer.
        let music = NotchCollapsedSignal.resolve(
            itemCount: 0, timerActive: false, timerPaused: false,
            nowPlayingActive: true, nowPlayingPlaying: true,
            agentActive: true, agentBusy: false, agentsNeedingYou: 0
        )
        XCTAssertEqual(music, .nowPlaying)
        XCTAssertEqual(music.targetPage, .nowPlaying)
    }

    // MARK: - Expanded navigation partitioning (named pinned + "Thêm" overflow)

    func testNavLayoutPinsNamedItemsAndPutsRestInOverflow() {
        let all = NotchPages.defaultOrder
        let widePlan = NotchNavLayout.plan(
            shown: all,
            available: { _ in true },
            current: .files,
            isWide: true,
            hasPhysicalNotch: true
        )
        XCTAssertEqual(widePlan.pinned, [.files, .clipboard, .nowPlaying])
        XCTAssertEqual(widePlan.overflowPages, [.agents, .calendar, .timer, .aiUsage])
        XCTAssertEqual(widePlan.overflowExtras, [.system, .audio])

        let weatherPlan = NotchNavLayout.plan(
            shown: all,
            available: { _ in true },
            current: .files,
            isWide: true,
            hasPhysicalNotch: true,
            weatherAvailable: true
        )
        XCTAssertEqual(weatherPlan.overflowExtras, [.weather, .system, .audio])

        let financePlan = NotchNavLayout.plan(
            shown: all,
            available: { _ in true },
            current: .files,
            isWide: true,
            hasPhysicalNotch: true,
            weatherAvailable: true,
            stocksAvailable: true,
            revenueAvailable: true
        )
        XCTAssertEqual(financePlan.overflowExtras, [.weather, .stocks, .revenue, .system, .audio])
        XCTAssertFalse(NotchNavLayout.usesWideCanvas(page: .files, extraModule: .stocks, preferNarrowExtra: true))
        XCTAssertTrue(NotchNavLayout.usesWideCanvas(page: .files, extraModule: .stocks, preferNarrowExtra: false))

        // Clipboard with search field on physical notch keeps 2 pinned so search fits.
        let clipPlan = NotchNavLayout.plan(
            shown: all,
            available: { _ in true },
            current: .clipboard,
            isWide: true,
            hasPhysicalNotch: true,
            searchFieldVisible: true
        )
        XCTAssertEqual(clipPlan.pinned, [.files, .clipboard])
        XCTAssertTrue(clipPlan.overflowPages.contains(.nowPlaying))

        // Narrow physical-notch page shows the active page on the left wing and moves the rest to Thêm.
        let narrowPlan = NotchNavLayout.plan(
            shown: all,
            available: { _ in true },
            current: .timer,
            isWide: false,
            hasPhysicalNotch: true
        )
        XCTAssertEqual(narrowPlan.pinned, [.timer])
        XCTAssertTrue(narrowPlan.overflowPages.contains(.files))
        XCTAssertTrue(narrowPlan.overflowPages.contains(.clipboard))

        // External / plain display has no camera gap ⇒ fits 3 pinned items even on narrow pages.
        let externalPlan = NotchNavLayout.plan(
            shown: all,
            available: { _ in true },
            current: .timer,
            isWide: false,
            hasPhysicalNotch: false
        )
        XCTAssertEqual(externalPlan.pinned.count, 3)
        XCTAssertEqual(externalPlan.pinned.first, .files)
    }

    func testNavLayoutUsesWideCanvasForFilesAndExtraModules() {
        XCTAssertTrue(NotchNavLayout.usesWideCanvas(page: .files, extraModule: nil))
        XCTAssertTrue(NotchNavLayout.usesWideCanvas(page: .clipboard, extraModule: nil))
        XCTAssertFalse(NotchNavLayout.usesWideCanvas(page: .nowPlaying, extraModule: nil))
        XCTAssertTrue(NotchNavLayout.usesWideCanvas(page: .nowPlaying, extraModule: .system))
        for page in Page.allCases {
            XCTAssertEqual(
                NotchNavLayout.usesWideCanvas(page: page, extraModule: nil),
                NotchSurfaceLayout.Metrics.isWide(page),
                "\(page) width agreement between NotchNavLayout and NotchSurfaceLayout"
            )
        }
    }

    // MARK: - Open-page priority

    func testActiveFileOperationPrioritizesFilesUnlessExplicitPageRequested() {
        let shown = NotchPages.defaultOrder
        let act = NotchHoverOpen.Activity(itemCount: 2, trackPlaying: true, agentNeedsYou: false, lastPage: .nowPlaying)
        XCTAssertEqual(
            NotchExpandPriority.resolveOpenPage(
                explicitPage: nil, clickRule: .lastPage, activity: act, shown: shown, hasActiveFileOperation: true
            ),
            .files,
            "active file work opens .files even when clickOpens is lastPage"
        )
        XCTAssertEqual(
            NotchExpandPriority.resolveOpenPage(
                explicitPage: .calendar, clickRule: .files, activity: act, shown: shown, hasActiveFileOperation: true
            ),
            .calendar,
            "explicit destination always wins"
        )
        XCTAssertEqual(
            NotchExpandPriority.resolveOpenPage(
                explicitPage: nil, clickRule: .lastPage, activity: act, shown: [.clipboard, .nowPlaying], hasActiveFileOperation: true
            ),
            .nowPlaying,
            "hidden .files falls back cleanly"
        )
    }

    // MARK: - Reduce Motion policy

    func testReduceMotionDisablesGrowBlurAndHoverScale() {
        XCTAssertTrue(NotchMotionPolicy.shouldGrowFromNotch(wasVisible: false, anchor: .notch, reduceMotion: false))
        XCTAssertFalse(NotchMotionPolicy.shouldGrowFromNotch(wasVisible: false, anchor: .notch, reduceMotion: true))
        XCTAssertEqual(NotchMotionPolicy.appearBlurRadius(appearFromNotch: true, reduceMotion: false), 8)
        XCTAssertEqual(NotchMotionPolicy.appearBlurRadius(appearFromNotch: true, reduceMotion: true), 0)
        XCTAssertEqual(NotchMotionPolicy.pillHoverScale(hovered: true, reduceMotion: false), 1.03)
        XCTAssertEqual(NotchMotionPolicy.pillHoverScale(hovered: true, reduceMotion: true), 1.0)
    }

    // MARK: - Keyboard routing

    func testHubKeyboardDecodingRespectsPageContext() {
        XCTAssertEqual(NotchHubKeyAction.decode(keyCode: 53, characters: nil, command: false, shift: false, option: false, control: false, onFilesPage: false), .escape)
        XCTAssertEqual(NotchHubKeyAction.decode(keyCode: 49, characters: " ", command: false, shift: false, option: false, control: false, onFilesPage: true), .quickLook)
        XCTAssertNil(NotchHubKeyAction.decode(keyCode: 49, characters: " ", command: false, shift: false, option: false, control: false, onFilesPage: false))
        XCTAssertEqual(NotchHubKeyAction.decode(keyCode: 0, characters: "a", command: true, shift: false, option: false, control: false, onFilesPage: true), .selectAll)
        XCTAssertEqual(NotchHubKeyAction.decode(keyCode: 124, characters: nil, command: false, shift: true, option: false, control: false, onFilesPage: true), .moveSelection(delta: 1, extend: true))
        XCTAssertEqual(NotchHubKeyAction.decode(keyCode: 51, characters: nil, command: false, shift: false, option: false, control: false, onFilesPage: true), .removeSelected)
        XCTAssertEqual(NotchHubKeyAction.decode(keyCode: 18, characters: "2", command: true, shift: false, option: false, control: false, onFilesPage: false), .switchToSlot(2))
        XCTAssertEqual(NotchHubKeyAction.decode(keyCode: 5, characters: "g", command: true, shift: false, option: false, control: false, onFilesPage: true), .toggleMoreGallery)
    }
}
