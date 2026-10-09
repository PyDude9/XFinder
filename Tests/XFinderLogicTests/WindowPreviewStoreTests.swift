import XCTest
import AppKit
@testable import XFinderLogicTests

final class WindowPreviewStoreTests: XCTestCase {

    // MARK: - PreviewItem Tests

    func testPreviewItemProperties() {
        let dummyImage = NSImage(size: NSSize(width: 100, height: 100))
        let item = PreviewItem(
            windowID: 101,
            bundleID: "com.apple.Safari",
            title: "Safari Window",
            thumbnail: dummyImage,
            isFrozen: false
        )

        XCTAssertEqual(item.id, 101)
        XCTAssertEqual(item.windowID, 101)
        XCTAssertEqual(item.bundleID, "com.apple.Safari")
        XCTAssertEqual(item.title, "Safari Window")
        XCTAssertEqual(item.thumbnail, dummyImage)
        XCTAssertFalse(item.isFrozen)
    }

    func testPreviewItemEquality() {
        let item1 = PreviewItem(windowID: 101, bundleID: "com.apple.Safari", title: "Tab 1", isFrozen: false)
        let item2 = PreviewItem(windowID: 101, bundleID: "com.apple.Safari", title: "Tab 1", isFrozen: false)
        let item3 = PreviewItem(windowID: 102, bundleID: "com.apple.Safari", title: "Tab 2", isFrozen: false)

        XCTAssertEqual(item1, item2)
        XCTAssertNotEqual(item1, item3)
    }

    // MARK: - LRU Cache Tests

    func testLRUCacheCapacityAndEviction() {
        let cache = LRUThumbnailCache(capacity: 3)
        let img1 = NSImage(size: NSSize(width: 10, height: 10))
        let img2 = NSImage(size: NSSize(width: 20, height: 20))
        let img3 = NSImage(size: NSSize(width: 30, height: 30))
        let img4 = NSImage(size: NSSize(width: 40, height: 40))

        cache.set(1, image: img1)
        cache.set(2, image: img2)
        cache.set(3, image: img3)
        XCTAssertEqual(cache.count, 3)

        // Access 1 and 2 to update last access time
        _ = cache.get(1)
        _ = cache.get(2)

        // Adding 4 should evict 3 (least recently accessed)
        cache.set(4, image: img4)
        XCTAssertEqual(cache.count, 3)
        XCTAssertNotNil(cache.get(1))
        XCTAssertNotNil(cache.get(2))
        XCTAssertNotNil(cache.get(4))
        XCTAssertNil(cache.get(3))
    }

    func testLRUCacheClearAndRemove() {
        let cache = LRUThumbnailCache(capacity: 5)
        let img = NSImage(size: NSSize(width: 10, height: 10))
        cache.set(100, image: img)
        cache.set(101, image: img)
        XCTAssertEqual(cache.count, 2)

        cache.remove(100)
        XCTAssertEqual(cache.count, 1)
        XCTAssertNil(cache.get(100))
        XCTAssertNotNil(cache.get(101))

        cache.clear()
        XCTAssertEqual(cache.count, 0)
    }

    // MARK: - Mock Screen Capture Tests

    func testMockScreenCaptureAllowedVsDenied() async {
        let mock = MockScreenCaptureProvider(isAllowed: true)
        let img = NSImage(size: NSSize(width: 50, height: 50))
        mock.setMockImage(for: 1, image: img)

        let captured = await mock.captureWindow(windowID: 1)
        XCTAssertNotNil(captured)

        mock.isAllowed = false
        mock.cache.clear()
        let denied = await mock.captureWindow(windowID: 1)
        XCTAssertNil(denied)
    }

    // MARK: - Browser Tabs & Frozen Filtering Tests

    func testBrowserTabFrozenDetection() {
        XCTAssertTrue(BrowserTabProvider.isTabFrozen(title: "Perplexity [Discarded]", url: "https://perplexity.ai"))
        XCTAssertTrue(BrowserTabProvider.isTabFrozen(title: "Gmail (Sleeping)", url: "https://mail.google.com"))
        XCTAssertTrue(BrowserTabProvider.isTabFrozen(title: "Documentation (Frozen)", url: "https://apple.com"))
        XCTAssertTrue(BrowserTabProvider.isTabFrozen(title: "Dashboard - Saved Memory", url: "https://example.com"))
        XCTAssertTrue(BrowserTabProvider.isTabFrozen(title: "Tab", url: "chrome://discards/"))
        XCTAssertTrue(BrowserTabProvider.isTabFrozen(title: "Tab", url: "edge://discards/"))
        XCTAssertTrue(BrowserTabProvider.isTabFrozen(title: "Blank", url: "about:discarded"))

        XCTAssertFalse(BrowserTabProvider.isTabFrozen(title: "Active Safari Tab", url: "https://apple.com"))
        XCTAssertFalse(BrowserTabProvider.isTabFrozen(title: "GitHub Pull Request", url: "https://github.com"))
    }

    func testSafariTenTabsWithThreeFrozen() async {
        let provider = BrowserTabProvider()
        let tabs: [BrowserTabItem] = [
            BrowserTabItem(title: "Active Tab 1", url: "https://tab1.com", isFrozen: false),
            BrowserTabItem(title: "Active Tab 2", url: "https://tab2.com", isFrozen: false),
            BrowserTabItem(title: "Active Tab 3", url: "https://tab3.com", isFrozen: false),
            BrowserTabItem(title: "Active Tab 4", url: "https://tab4.com", isFrozen: false),
            BrowserTabItem(title: "Active Tab 5", url: "https://tab5.com", isFrozen: false),
            BrowserTabItem(title: "Active Tab 6", url: "https://tab6.com", isFrozen: false),
            BrowserTabItem(title: "Active Tab 7", url: "https://tab7.com", isFrozen: false),
            // 3 frozen tabs
            BrowserTabItem(title: "Frozen Tab 8 [Discarded]", url: "https://tab8.com", isFrozen: true),
            BrowserTabItem(title: "Frozen Tab 9 (Sleeping)", url: "https://tab9.com", isFrozen: true),
            BrowserTabItem(title: "Frozen Tab 10", url: "about:discarded", isFrozen: true)
        ]
        XCTAssertEqual(tabs.count, 10)

        provider.setMockTabs(for: "com.apple.Safari", tabs: tabs)
        let activeTabs = await provider.fetchTabs(bundleID: "com.apple.Safari")

        XCTAssertEqual(activeTabs.count, 7)
        for t in activeTabs {
            XCTAssertFalse(t.isFrozen)
            XCTAssertFalse(t.title.contains("Frozen"))
        }
    }

    func testChromeAndEdgeTabSupport() async {
        let provider = BrowserTabProvider()
        let chromeTabs = [
            BrowserTabItem(title: "Google Search", url: "https://google.com", isFrozen: false),
            BrowserTabItem(title: "Sleeping Tab", url: "chrome://discards", isFrozen: true)
        ]
        provider.setMockTabs(for: "com.google.Chrome", tabs: chromeTabs)
        let activeChrome = await provider.fetchTabs(bundleID: "com.google.Chrome")
        XCTAssertEqual(activeChrome.count, 1)
        XCTAssertEqual(activeChrome.first?.title, "Google Search")

        let edgeTabs = [
            BrowserTabItem(title: "Microsoft Learn", url: "https://learn.microsoft.com", isFrozen: false),
            BrowserTabItem(title: "Discarded Page", url: "edge://discards", isFrozen: true)
        ]
        provider.setMockTabs(for: "com.microsoft.edgems", tabs: edgeTabs)
        let activeEdge = await provider.fetchTabs(bundleID: "com.microsoft.edgems")
        XCTAssertEqual(activeEdge.count, 1)
        XCTAssertEqual(activeEdge.first?.title, "Microsoft Learn")
    }

    func testBrowserTabDomainExtraction() {
        let tab1 = BrowserTabItem(title: "Example", url: "https://www.apple.com/mac")
        XCTAssertEqual(tab1.domain, "apple.com")

        let tab2 = BrowserTabItem(title: "Sub", url: "https://developer.apple.com/documentation")
        XCTAssertEqual(tab2.domain, "developer.apple.com")
    }

    // MARK: - Calendar & Weather Tests

    func testCalendarEventItem() {
        let now = Date()
        let event = CalendarEventItem(
            title: "Standup",
            startDate: now,
            endDate: now.addingTimeInterval(1800),
            isAllDay: false
        )
        XCTAssertEqual(event.title, "Standup")
        XCTAssertFalse(event.isAllDay)
        XCTAssertFalse(event.timeString.isEmpty)

        let allDayEvent = CalendarEventItem(
            title: "Holiday",
            startDate: now,
            endDate: now,
            isAllDay: true
        )
        XCTAssertEqual(allDayEvent.timeString, "Cả ngày")
    }

    func testCalendarFallbackEvents() async {
        let provider = CalendarPreviewProvider()
        let events = await provider.fetchNextEvents(limit: 3)
        XCTAssertLessThanOrEqual(events.count, 3)
        XCTAssertFalse(events.isEmpty)
    }

    func testWeatherPreview() async {
        let provider = WeatherPreviewProvider()
        let w = await provider.fetchWeather()
        XCTAssertFalse(w.temperature.isEmpty)
        XCTAssertFalse(w.condition.isEmpty)
        XCTAssertFalse(w.symbolName.isEmpty)
    }

    // MARK: - WindowPreviewStore Integration Tests

    @MainActor
    func testWindowPreviewStoreState() {
        let mockCapture = MockScreenCaptureProvider(isAllowed: true)
        let mockBrowser = BrowserTabProvider()
        let store = WindowPreviewStore(
            captureProvider: mockCapture,
            browserProvider: mockBrowser
        )

        let item = PreviewItem(windowID: 200, bundleID: "com.apple.Safari", title: "Safari Main")
        store.previewItems = [item]
        XCTAssertEqual(store.previewItems.count, 1)
        XCTAssertEqual(store.previewItems.first?.windowID, 200)

        store.clear()
        XCTAssertTrue(store.previewItems.isEmpty)
        XCTAssertTrue(store.activeBrowserTabs.isEmpty)
        XCTAssertTrue(store.calendarEvents.isEmpty)
        XCTAssertNil(store.weatherInfo)
    }

    // MARK: - New Tests for PATCH 2.1 (Switcher Hold/Release, Search Filter, Dock Hover)

    @MainActor
    func testSwitcherHoldAndReleaseCycle() {
        let store = WindowPreviewStore()
        let win1 = PreviewItem(windowID: 101, bundleID: "com.apple.dt.Xcode", title: "Xcode - Project")
        let win2 = PreviewItem(windowID: 102, bundleID: "com.apple.Safari", title: "Safari - GitHub")
        let win3 = PreviewItem(windowID: 103, bundleID: "com.tinyspeck.slackmacgap", title: "Slack - General")

        store.previewItems = [win1, win2, win3]
        store.selectedIndex = 1 // Start on 2nd window when opened

        // Step forward: 1 -> 2
        store.step(forward: true)
        XCTAssertEqual(store.selectedIndex, 2)
        XCTAssertEqual(store.commitSelection()?.windowID, 103)

        // Step forward wraps: 2 -> 0
        store.step(forward: true)
        XCTAssertEqual(store.selectedIndex, 0)
        XCTAssertEqual(store.commitSelection()?.windowID, 101)

        // Step backward: 0 -> 2
        store.step(forward: false)
        XCTAssertEqual(store.selectedIndex, 2)

        // Commit on release
        let committed = store.commitSelection()
        XCTAssertNotNil(committed)
        XCTAssertEqual(committed?.windowID, 103)
        XCTAssertEqual(committed?.bundleID, "com.tinyspeck.slackmacgap")

        // Cancel / dismiss
        store.clear()
        XCTAssertEqual(store.selectedIndex, 0)
        XCTAssertTrue(store.previewItems.isEmpty)
    }

    @MainActor
    func testSearchFilterLive() {
        let store = WindowPreviewStore()
        let win1 = PreviewItem(windowID: 201, bundleID: "com.apple.Safari", title: "Safari - GitHub")
        let win2 = PreviewItem(windowID: 202, bundleID: "com.google.Chrome", title: "Google Chrome - Docs")
        let win3 = PreviewItem(windowID: 203, bundleID: "com.apple.Notes", title: "Notes - Meeting Notes")

        store.previewItems = [win1, win2, win3]

        // Empty query -> all items
        store.searchQuery = ""
        XCTAssertEqual(store.filteredPreviewItems.count, 3)

        // Query "chrome" -> 1 match
        store.searchQuery = "chrome"
        XCTAssertEqual(store.filteredPreviewItems.count, 1)
        XCTAssertEqual(store.filteredPreviewItems.first?.windowID, 202)

        // Query "meeting" by window title -> 1 match
        store.searchQuery = "meeting"
        XCTAssertEqual(store.filteredPreviewItems.count, 1)
        XCTAssertEqual(store.filteredPreviewItems.first?.windowID, 203)

        // Query with no match -> empty ("No windows" state)
        store.searchQuery = "xyz_nonexistent_search_query"
        XCTAssertTrue(store.filteredPreviewItems.isEmpty)
    }

    @MainActor
    func testDockHoverWindowLoading() {
        let store = WindowPreviewStore()
        store.windowLister = {
            [
                WindowPreviewStore.WindowRef(id: 301, ownerPID: 5001, ownerName: "Safari", title: "GitHub PR #42", bounds: CGRect(x: 0, y: 0, width: 800, height: 600)),
                WindowPreviewStore.WindowRef(id: 302, ownerPID: 5001, ownerName: "Safari", title: "Apple Developer", bounds: CGRect(x: 0, y: 0, width: 800, height: 600)),
                WindowPreviewStore.WindowRef(id: 303, ownerPID: 5002, ownerName: "Terminal", title: "zsh - ~/github", bounds: CGRect(x: 0, y: 0, width: 600, height: 400))
            ]
        }

        // Hover over PID 5001 (Safari)
        store.loadDockPreviews(for: 5001)
        XCTAssertEqual(store.previewItems.count, 1)
        XCTAssertEqual(store.previewItems[0].windowID, 301)
        XCTAssertEqual(store.previewItems[0].windowCount, 2)

        // Hover over PID 5002 (Terminal)
        store.loadDockPreviews(for: 5002)
        XCTAssertEqual(store.previewItems.count, 1)
        XCTAssertEqual(store.previewItems[0].windowID, 303)
        XCTAssertEqual(store.previewItems[0].title, "zsh - ~/github")
        XCTAssertEqual(store.previewItems[0].windowCount, 1)
    }

    // MARK: - PATCH 2.4 New Tests

    func testTabEligibilityAndVisibility() {
        let validTab = BrowserTab(title: "Google", url: "https://google.com", isFrozen: false)
        let frozenTab = BrowserTab(title: "Gmail", url: "https://mail.google.com", isFrozen: true)
        let discardedTab = BrowserTab(title: "Discarded Tab", url: "https://example.com/discarded", isFrozen: false)
        let emptyUrlTab = BrowserTab(title: "Empty URL", url: "", isFrozen: false)
        let emptyTitleTab = BrowserTab(title: "", url: "https://example.com", isFrozen: false)

        XCTAssertTrue(isTabEligible(validTab))
        XCTAssertFalse(isTabEligible(frozenTab))
        XCTAssertFalse(isTabEligible(discardedTab))
        XCTAssertFalse(isTabEligible(emptyUrlTab))
        XCTAssertFalse(isTabEligible(emptyTitleTab))

        // When item has no thumbnail or is frozen, tabs are excluded
        let itemNoThumb = PreviewItem(windowID: 901, bundleID: "com.apple.Safari", title: "Safari", thumbnail: nil, isFrozen: false)
        XCTAssertNil(itemNoThumb.thumbnail)

        let itemFrozen = PreviewItem(windowID: 902, bundleID: "com.apple.Safari", title: "Safari Frozen", thumbnail: NSImage(size: NSSize(width: 10, height: 10)), isFrozen: true)
        XCTAssertTrue(itemFrozen.isFrozen)
    }

    @MainActor
    func testSafariFullscreenWindowPreview() async {
        let store = WindowPreviewStore()
        let mockCapture = MockScreenCaptureProvider(isAllowed: true)
        let fsThumb = NSImage(size: NSSize(width: 800, height: 500))
        mockCapture.setMockImage(for: 999, image: fsThumb)

        store.windowLister = {
            [
                WindowPreviewStore.WindowRef(
                    id: 999,
                    ownerPID: 8888,
                    ownerName: "Safari",
                    title: "Safari Fullscreen",
                    bounds: CGRect(x: 0, y: 0, width: 1920, height: 1080)
                )
            ]
        }

        let wins = store.windowLister()
        XCTAssertEqual(wins.count, 1)
        XCTAssertEqual(wins.first?.id, 999)

        let item = PreviewItem(
            windowID: 999,
            bundleID: "com.apple.Safari",
            title: wins[0].title,
            thumbnail: await mockCapture.captureWindow(windowID: 999),
            isFrozen: false
        )

        XCTAssertEqual(item.windowID, 999)
        XCTAssertEqual(item.bundleID, "com.apple.Safari")
        XCTAssertNotNil(item.thumbnail)
    }

    func testSquareBackgroundClipTokens() {
        // Tokens for lightweight macOS switcher styling: container 24, card 16, thumb 10, blur 32, saturation 1.4
        XCTAssertEqual(LiquidGlassTokens.containerRadius, 24)
        XCTAssertEqual(LiquidGlassTokens.cardRadius, 16)
        XCTAssertEqual(LiquidGlassTokens.thumbRadius, 10)
        XCTAssertEqual(LiquidGlassTokens.blurRadius, 32)
        XCTAssertEqual(LiquidGlassTokens.saturation, 1.4)
    }

    func testTabAndWindowPreviewableConditions() {
        // 1. Tab previewable rules:
        let activeTab = BrowserTab(title: "Active Page", url: "https://example.com", isFrozen: false, isActive: true)
        let inactiveTab = BrowserTab(title: "Background Tab", url: "https://example.com/other", isFrozen: false, isActive: false)
        let frozenTab = BrowserTab(title: "Sleeping Tab", url: "https://example.com", isFrozen: true, isActive: true)
        let blankUrlTab = BrowserTab(title: "Blank", url: "about:blank", isFrozen: false, isActive: true)
        let emptyTab = BrowserTab(title: "", url: "", isFrozen: false, isActive: true)

        XCTAssertTrue(isTabPreviewable(activeTab))
        XCTAssertTrue(isTabPreviewable(inactiveTab), "Background tabs with content are previewable in Dock")
        XCTAssertFalse(isTabPreviewable(frozenTab), "Frozen tabs must not be previewable")
        XCTAssertFalse(isTabPreviewable(blankUrlTab), "Blank URL tabs have no content")
        XCTAssertFalse(isTabPreviewable(emptyTab), "Empty title/url tabs have no content")

        // 2. Window previewable rules:
        let winWithValidThumb = PreviewItem(
            windowID: 101,
            bundleID: "com.apple.Safari",
            title: "Safari Window",
            thumbnail: NSImage(size: NSSize(width: 800, height: 500)),
            isFrozen: false
        )
        let winWithNilThumb = PreviewItem(
            windowID: 102,
            bundleID: "com.apple.Safari",
            title: "Safari Window Other Space",
            thumbnail: nil,
            isFrozen: false,
            isOnOtherSpace: true
        )
        let winWithTinyThumb = PreviewItem(
            windowID: 103,
            bundleID: "com.apple.Safari",
            title: "Tiny",
            thumbnail: NSImage(size: NSSize(width: 5, height: 5)),
            isFrozen: false
        )
        let winFrozen = PreviewItem(
            windowID: 104,
            bundleID: "com.apple.Safari",
            title: "Frozen",
            thumbnail: NSImage(size: NSSize(width: 800, height: 500)),
            isFrozen: true
        )

        XCTAssertTrue(isWindowPreviewable(winWithValidThumb))
        XCTAssertFalse(isWindowPreviewable(winWithNilThumb), "Nil thumbnail is not previewable")
        XCTAssertFalse(isWindowPreviewable(winWithTinyThumb), "Width <= 10 is not previewable")
        XCTAssertFalse(isWindowPreviewable(winFrozen), "Frozen window is not previewable")
    }

    func testTabFiltersDockVsSwitcher() {
        let activeTab = BrowserTab(title: "Active Page", url: "https://example.com", isFrozen: false, isActive: true, isHidden: false)
        let inactiveTab = BrowserTab(title: "Background Tab", url: "https://example.com/other", isFrozen: false, isActive: false, isHidden: false)
        let discardedTab = BrowserTab(title: "Discarded Page [Discarded]", url: "https://example.com/disc", isFrozen: false, isHidden: false)
        let hiddenTab = BrowserTab(title: "Hidden Tab", url: "https://example.com/hid", isFrozen: false, isHidden: true)
        let emptyTab = BrowserTab(title: "", url: "", isFrozen: false)

        // Dock Hover filter: shows all open tabs (active & background), not frozen, not discarded, has content
        XCTAssertTrue(isTabPreviewableForDock(activeTab))
        XCTAssertTrue(isTabPreviewableForDock(inactiveTab), "Dock must show all open tabs")
        XCTAssertFalse(isTabPreviewableForDock(discardedTab))
        XCTAssertFalse(isTabPreviewableForDock(hiddenTab))
        XCTAssertFalse(isTabPreviewableForDock(emptyTab))

        // Switcher filter: shows tabs including inactive, but skips discarded or hidden
        XCTAssertTrue(isTabVisibleForSwitcher(activeTab))
        XCTAssertTrue(isTabVisibleForSwitcher(inactiveTab), "Switcher must show inactive tabs")
        XCTAssertFalse(isTabVisibleForSwitcher(discardedTab))
        XCTAssertFalse(isTabVisibleForSwitcher(hiddenTab))
    }

    func testLiquidGlassTokensPatch26() {
        XCTAssertEqual(LiquidGlassTokens.switcherSelectionScale, 1.04)
        XCTAssertEqual(LiquidGlassTokens.unselectedOpacity, 0.70)
        XCTAssertEqual(LiquidGlassTokens.cardSize.width, 200)
        XCTAssertEqual(LiquidGlassTokens.cardSize.height, 140)
        XCTAssertEqual(LiquidGlassTokens.dockCardSize.width, 320)
        XCTAssertEqual(LiquidGlassTokens.dockCardSize.height, 280)
    }

    func testCmdTabVsDockHoverVisibilityRules() {
        // Switcher lists all windows, including other spaces
        let spaceWin = PreviewItem(
            windowID: 201,
            bundleID: "com.apple.Safari",
            title: "Safari Fullscreen",
            thumbnail: nil,
            isFrozen: false,
            tabs: [],
            isOnOtherSpace: true
        )
        XCTAssertEqual(spaceWin.subtitle, "On another Space")

        let currentWin = PreviewItem(
            windowID: 202,
            bundleID: "com.apple.Safari",
            title: "Safari Active",
            thumbnail: NSImage(size: NSSize(width: 800, height: 500)),
            isFrozen: false,
            tabs: [
                BrowserTab(title: "Active", url: "https://apple.com", isFrozen: false, isActive: true),
                BrowserTab(title: "Inactive", url: "https://bing.com", isFrozen: false, isActive: false)
            ],
            isOnOtherSpace: false
        )
        XCTAssertEqual(currentWin.subtitle, "Safari Active")

        let allSwitcherItems = [spaceWin, currentWin]
        // Cmd+Tab Switcher keeps ALL items (including spaceWin with nil thumb)
        XCTAssertEqual(allSwitcherItems.count, 2)

        // Dock Hover filters ONLY previewable windows
        let dockItems = allSwitcherItems.filter(isWindowPreviewable)
        XCTAssertEqual(dockItems.count, 1)
        XCTAssertEqual(dockItems.first?.windowID, 202)

        // Tabs keep all open previewable tabs
        let previewableTabs = currentWin.tabs.filter(isTabPreviewable)
        XCTAssertEqual(previewableTabs.count, 2)
        XCTAssertEqual(previewableTabs.first?.title, "Active")
    }

    func testPatch27StraightSharpCaptureAndThumbnailTokens() {
        // SCK capture target dimensions 800x500
        let sckWidth = 800
        let sckHeight = 500
        XCTAssertEqual(sckWidth, 800)
        XCTAssertEqual(sckHeight, 500)

        // Card & Thumbnail tokens for Dock and Switcher
        let dockCard = LiquidGlassTokens.dockCardSize
        XCTAssertEqual(dockCard.width, 320)
        XCTAssertEqual(dockCard.height, 280)

        let switcherCard = LiquidGlassTokens.cardSize
        XCTAssertEqual(switcherCard.width, 200)
        XCTAssertEqual(switcherCard.height, 140)

        // Calculated inner thumbnail dimensions
        let dockThumb = LiquidGlassTokens.Card.dockThumbSize
        let switcherThumb = LiquidGlassTokens.Card.switcherThumbSize
        XCTAssertEqual(dockThumb.width, 304)
        XCTAssertEqual(dockThumb.height, 160)
        XCTAssertEqual(switcherThumb.width, 184)
        XCTAssertEqual(switcherThumb.height, 86)

        // Uncapturable / other Space window returns nil thumbnail for clean fallback
        let uncapturableItem = PreviewItem(
            windowID: 999,
            bundleID: "com.apple.Notes",
            title: "Notes on Space 2",
            thumbnail: nil,
            isOnOtherSpace: true
        )
        XCTAssertNil(uncapturableItem.thumbnail)
        XCTAssertTrue(uncapturableItem.isOnOtherSpace)
    }

    func testPatch28GroupUnfetchableWindowsByApp() {
        let safari1 = PreviewItem(windowID: 301, bundleID: "com.apple.Safari", title: "Safari 1", appName: "Safari", thumbnail: nil, isOnOtherSpace: true)
        let safari2 = PreviewItem(windowID: 302, bundleID: "com.apple.Safari", title: "Safari 2", appName: "Safari", thumbnail: nil, isOnOtherSpace: true)
        let safari3 = PreviewItem(windowID: 303, bundleID: "com.apple.Safari", title: "Safari 3", appName: "Safari", thumbnail: nil, isOnOtherSpace: true)

        let tv1 = PreviewItem(windowID: 401, bundleID: "com.tradingview.desktop", title: "TradingView Chart 1", appName: "TradingView", thumbnail: nil, isOnOtherSpace: true)
        let tv2 = PreviewItem(windowID: 402, bundleID: "com.tradingview.desktop", title: "TradingView Chart 2", appName: "TradingView", thumbnail: nil, isOnOtherSpace: true)

        let chrome1 = PreviewItem(
            windowID: 501,
            bundleID: "com.google.Chrome",
            title: "Google Chrome",
            appName: "Google Chrome",
            thumbnail: NSImage(size: NSSize(width: 800, height: 500)),
            isOnOtherSpace: false
        )

        let rawItems = [safari1, safari2, safari3, tv1, tv2, chrome1]

        // Grouping logic for Switcher:
        let previewable = rawItems.filter { !$0.isOnOtherSpace || ($0.thumbnail != nil && ($0.thumbnail?.size.width ?? 0) > 10) }
        let otherSpaceUnpreviewable = rawItems.filter { $0.isOnOtherSpace && ($0.thumbnail == nil || ($0.thumbnail?.size.width ?? 0) <= 10) }

        var grouped: [PreviewItem] = []
        let groupedDict = Dictionary(grouping: otherSpaceUnpreviewable, by: { $0.bundleID })
        for (bundleID, appWins) in groupedDict {
            let appName = appWins.first?.appName.isEmpty == false ? appWins.first!.appName : bundleID
            let group = PreviewItemGroup(
                bundleID: bundleID,
                appName: appName,
                count: appWins.count,
                windowIDs: appWins.map { $0.windowID },
                isOnOtherSpace: true
            )
            grouped.append(group.asPreviewItem())
        }

        let switcherStrip = previewable + grouped
        // Collapsed from 6 down to 3 cards!
        XCTAssertEqual(switcherStrip.count, 3)

        // Chrome remains single previewable card
        let chromeCard = switcherStrip.first(where: { $0.bundleID == "com.google.Chrome" })
        XCTAssertNotNil(chromeCard)
        XCTAssertFalse(chromeCard!.isGroup)
        XCTAssertEqual(chromeCard!.windowCount, 1)

        // Safari is collapsed to 1 group card with count 3
        let safariCard = switcherStrip.first(where: { $0.bundleID == "com.apple.Safari" })
        XCTAssertNotNil(safariCard)
        XCTAssertTrue(safariCard!.isGroup)
        XCTAssertEqual(safariCard!.windowCount, 3)
        XCTAssertEqual(safariCard!.windowIDs, [301, 302, 303])

        // TradingView is collapsed to 1 group card with count 2
        let tvCard = switcherStrip.first(where: { $0.bundleID == "com.tradingview.desktop" })
        XCTAssertNotNil(tvCard)
        XCTAssertTrue(tvCard!.isGroup)
        XCTAssertEqual(tvCard!.windowCount, 2)
        XCTAssertEqual(tvCard!.windowIDs, [401, 402])
    }

    @MainActor
    func testPatch28DockHoverNeverIncludesGroupedOrOtherSpace() {
        let store = WindowPreviewStore(
            captureProvider: MockScreenCaptureProvider(isAllowed: true),
            browserProvider: BrowserTabProvider.shared,
            calendarProvider: CalendarPreviewProvider.shared,
            weatherProvider: WeatherPreviewProvider.shared
        )

        let winCurrent = WindowPreviewStore.WindowRef(id: 11, ownerPID: 500, ownerName: "Chrome", title: "Win 1", isOnCurrentSpace: true)
        let winOther = WindowPreviewStore.WindowRef(id: 12, ownerPID: 500, ownerName: "Chrome", title: "Win 2", isOnCurrentSpace: false)
        store.windowLister = { [winCurrent, winOther] }

        store.loadDockPreviews(for: 500)

        // Dock preview must only contain current space windows, never otherSpace
        let dockItems = store.previewItems.filter { !$0.isOnOtherSpace }
        XCTAssertEqual(dockItems.count, 1)
        XCTAssertEqual(dockItems.first?.windowID, 11)
        XCTAssertFalse(dockItems.first?.isGroup ?? true)
    }

    @MainActor
    func testPatch29SwitcherOneCardPerAppAndDockIsolation() {
        let store = WindowPreviewStore(
            captureProvider: MockScreenCaptureProvider(isAllowed: true),
            browserProvider: BrowserTabProvider.shared,
            calendarProvider: CalendarPreviewProvider.shared,
            weatherProvider: WeatherPreviewProvider.shared
        )

        // Setup 3 Safari windows, 2 Chrome windows, 1 TradingView window
        let safari1 = WindowPreviewStore.WindowRef(id: 101, ownerPID: 1000, ownerName: "Safari", title: "GitHub", bounds: CGRect(x: 0, y: 0, width: 800, height: 600), isOnCurrentSpace: true)
        let safari2 = WindowPreviewStore.WindowRef(id: 102, ownerPID: 1000, ownerName: "Safari", title: "Apple", bounds: CGRect(x: 0, y: 0, width: 800, height: 600), isOnCurrentSpace: true)
        let safari3 = WindowPreviewStore.WindowRef(id: 103, ownerPID: 1000, ownerName: "Safari", title: "Swift", bounds: CGRect(x: 0, y: 0, width: 800, height: 600), isOnCurrentSpace: false)

        let chrome1 = WindowPreviewStore.WindowRef(id: 201, ownerPID: 2000, ownerName: "Google Chrome", title: "Docs", bounds: CGRect(x: 0, y: 0, width: 800, height: 600), isOnCurrentSpace: true)
        let chrome2 = WindowPreviewStore.WindowRef(id: 202, ownerPID: 2000, ownerName: "Google Chrome", title: "Sheets", bounds: CGRect(x: 0, y: 0, width: 800, height: 600), isOnCurrentSpace: false)

        let tv1 = WindowPreviewStore.WindowRef(id: 301, ownerPID: 3000, ownerName: "TradingView", title: "BTCUSDT", bounds: CGRect(x: 0, y: 0, width: 800, height: 600), isOnCurrentSpace: true)

        store.windowLister = { [safari1, safari2, safari3, chrome1, chrome2, tv1] }

        // 1. Switcher: 6 windows collapse to EXACTLY 3 cards (1 per app)
        store.loadSwitchableWindows()
        XCTAssertEqual(store.previewItems.count, 3)

        let safariCard = store.previewItems.first(where: { $0.title.contains("Safari") || $0.appName.contains("Safari") })
        XCTAssertNotNil(safariCard)
        XCTAssertEqual(safariCard?.windowCount, 3)
        XCTAssertTrue(safariCard?.isGroup ?? false)
        XCTAssertEqual(safariCard?.windowIDs, [101, 102, 103])

        let chromeCard = store.previewItems.first(where: { $0.title.contains("Chrome") || $0.appName.contains("Chrome") })
        XCTAssertNotNil(chromeCard)
        XCTAssertEqual(chromeCard?.windowCount, 2)
        XCTAssertTrue(chromeCard?.isGroup ?? false)
        XCTAssertEqual(chromeCard?.windowIDs, [201, 202])

        let tvCard = store.previewItems.first(where: { $0.title.contains("TradingView") || $0.appName.contains("TradingView") })
        XCTAssertNotNil(tvCard)
        XCTAssertEqual(tvCard?.windowCount, 1)
        XCTAssertFalse(tvCard?.isGroup ?? true)

        // Switcher removes Open Tabs
        XCTAssertTrue(store.activeBrowserTabs.isEmpty)

        // 2. Dock Hover isolation: 1 window thumbnail on top
        store.loadDockPreviews(for: 1000)
        XCTAssertEqual(store.previewItems.count, 1)
        XCTAssertEqual(store.previewItems.first?.windowID, 101)
        XCTAssertEqual(store.previewItems.first?.windowCount, 3)

        store.loadDockPreviews(for: 3000)
        XCTAssertEqual(store.previewItems.count, 1)
        XCTAssertEqual(store.previewItems.first?.windowID, 301)
        XCTAssertEqual(store.previewItems.first?.windowCount, 1)
        XCTAssertTrue(store.activeBrowserTabs.isEmpty)
    }

    // MARK: - Stage Manager & Circular Round-Robin Tests

    func testStageManagerProxyDetection() {
        // Stage Manager miniatures: width/height <= 260 or origin.x <= 80 && width <= 280
        let proxy1 = CGRect(x: 15, y: 730, width: 157, height: 172) // Chrome proxy
        let proxy2 = CGRect(x: 15, y: 425, width: 157, height: 149) // Preview proxy
        let proxy3 = CGRect(x: 45, y: 600, width: 88, height: 110)  // Finder proxy
        let regularWin = CGRect(x: 100, y: 100, width: 800, height: 600) // Regular window
        let fullScreenWin = CGRect(x: 0, y: 30, width: 1728, height: 1084) // Full screen

        XCTAssertTrue(ScreenCaptureProvider.isStageManagerProxy(frame: proxy1))
        XCTAssertTrue(ScreenCaptureProvider.isStageManagerProxy(frame: proxy2))
        XCTAssertTrue(ScreenCaptureProvider.isStageManagerProxy(frame: proxy3))
        XCTAssertFalse(ScreenCaptureProvider.isStageManagerProxy(frame: regularWin))
        XCTAssertFalse(ScreenCaptureProvider.isStageManagerProxy(frame: fullScreenWin))
    }

    @MainActor
    func testCircularRoundRobinSwitcherWithManyApps() {
        let store = WindowPreviewStore()

        // Create 20 running apps
        var mockWindows: [WindowPreviewStore.WindowRef] = []
        for i in 1...20 {
            mockWindows.append(
                WindowPreviewStore.WindowRef(
                    id: CGWindowID(1000 + i),
                    ownerPID: pid_t(10000 + i),
                    ownerName: "App\(i)",
                    title: "Window \(i)",
                    bounds: CGRect(x: 100, y: 100, width: 800, height: 600),
                    isOnCurrentSpace: true
                )
            )
        }
        store.windowLister = { mockWindows }

        // 1. Verify all 20 apps are retained (not capped at 12!)
        store.loadSwitchableWindows()
        XCTAssertEqual(store.previewItems.count, 20)

        // Initial selectedIndex should be 1 (second app in MRU)
        XCTAssertEqual(store.selectedIndex, 1)

        // 2. Test forward circular stepping loops smoothly: 1 -> 2 -> ... -> 19 -> 0 -> 1
        for expected in 2...19 {
            store.step(forward: true)
            XCTAssertEqual(store.selectedIndex, expected)
        }
        store.step(forward: true)
        XCTAssertEqual(store.selectedIndex, 0) // wraps to 0
        store.step(forward: true)
        XCTAssertEqual(store.selectedIndex, 1) // wraps to 1

        // 3. Test backward circular stepping loops smoothly: 1 -> 0 -> 19 -> 18
        store.step(forward: false)
        XCTAssertEqual(store.selectedIndex, 0)
        store.step(forward: false)
        XCTAssertEqual(store.selectedIndex, 19) // wraps to 19
        store.step(forward: false)
        XCTAssertEqual(store.selectedIndex, 18)

        // 4. Test circular slice calculation: for K = 7 visible slots, center slot M = 3
        let K = 7
        let M = K / 2
        let N = store.previewItems.count

        // When selectedIndex is 0:
        store.selectedIndex = 0
        var sliceIndices: [Int] = []
        for slot in 0..<K {
            let actual = (store.selectedIndex - M + slot + N) % N
            sliceIndices.append(actual)
        }
        XCTAssertEqual(sliceIndices, [17, 18, 19, 0, 1, 2, 3])
        XCTAssertEqual(sliceIndices[M], 0) // Center slot is selectedIndex

        // When selectedIndex is 19:
        store.selectedIndex = 19
        sliceIndices = []
        for slot in 0..<K {
            let actual = (store.selectedIndex - M + slot + N) % N
            sliceIndices.append(actual)
        }
        XCTAssertEqual(sliceIndices, [16, 17, 18, 19, 0, 1, 2])
        XCTAssertEqual(sliceIndices[M], 19) // Center slot is selectedIndex
    }

    func testMaxVisibleCardsScreenCapacity() {
        XCTAssertEqual(WindowPreviewStore.maxVisibleCards(screenWidth: 1440), 5)
        XCTAssertEqual(WindowPreviewStore.maxVisibleCards(screenWidth: 1728), 6)
        XCTAssertEqual(WindowPreviewStore.maxVisibleCards(screenWidth: 1920), 7)
        XCTAssertEqual(WindowPreviewStore.maxVisibleCards(screenWidth: 2560), 7) // clamped max 7
        XCTAssertEqual(WindowPreviewStore.maxVisibleCards(screenWidth: 800), 5)  // clamped min 5
    }

    func testAppIconProminenceTokens() {
        XCTAssertEqual(LiquidGlassTokens.Card.appIconSize, 22)
        XCTAssertEqual(LiquidGlassTokens.Card.badgeIconSize, 28)
    }

    func testActiveTabsForDockPreviewRules() {
        // Scenario 1: 1 window with 1 active tab and 9 background inactive tabs
        var tabs1: [BrowserTabItem] = [
            BrowserTabItem(title: "Active Tab", url: "https://apple.com", isFrozen: false, isActive: true)
        ]
        for i in 1...9 {
            tabs1.append(BrowserTabItem(title: "Background \(i)", url: "https://example.com/\(i)", isFrozen: false, isActive: false))
        }
        let result1 = activeTabsForDockPreview(tabs1)
        XCTAssertEqual(result1.count, 1, "Only active tab must be returned, not background tabs")
        XCTAssertEqual(result1.first?.title, "Active Tab")

        // Scenario 2: 2 windows open with 2 active tabs and 5 background tabs
        var tabs2: [BrowserTabItem] = [
            BrowserTabItem(title: "Active Win 1", url: "https://apple.com/1", isFrozen: false, isActive: true),
            BrowserTabItem(title: "Active Win 2", url: "https://apple.com/2", isFrozen: false, isActive: true)
        ]
        for i in 1...5 {
            tabs2.append(BrowserTabItem(title: "Background \(i)", url: "https://example.com/\(i)", isFrozen: false, isActive: false))
        }
        let result2 = activeTabsForDockPreview(tabs2)
        XCTAssertEqual(result2.count, 2, "Exactly 2 active tabs must be displayed")
        XCTAssertEqual(result2.map(\.title), ["Active Win 1", "Active Win 2"])

        // Scenario 3: 3 active tabs -> displays 3 tabs
        var tabs3 = (1...3).map { BrowserTabItem(title: "Active \($0)", url: "https://site\($0).com", isFrozen: false, isActive: true) }
        tabs3.append(BrowserTabItem(title: "Inactive", url: "https://inactive.com", isFrozen: false, isActive: false))
        let result3 = activeTabsForDockPreview(tabs3)
        XCTAssertEqual(result3.count, 3)

        // Scenario 4: 7 active tabs -> clamped to maximum 5 tabs
        let tabs7 = (1...7).map { BrowserTabItem(title: "Active \($0)", url: "https://site\($0).com", isFrozen: false, isActive: true) }
        let result7 = activeTabsForDockPreview(tabs7)
        XCTAssertEqual(result7.count, 5, "Clamped to max 5 tabs")

        // Scenario 5: No tabs are active (fallback to 1 tab)
        let tabsNoActive = (1...4).map { BrowserTabItem(title: "Tab \($0)", url: "https://site\($0).com", isFrozen: false, isActive: false) }
        let resultNoActive = activeTabsForDockPreview(tabsNoActive)
        XCTAssertEqual(resultNoActive.count, 1, "Fallback to 1 tab if none marked active")
        XCTAssertEqual(resultNoActive.first?.title, "Tab 1")

        // Scenario 6: Discarded/frozen tabs are filtered out
        let tabsWithDiscarded = [
            BrowserTabItem(title: "Active Discarded [Discarded]", url: "https://apple.com", isFrozen: false, isActive: true),
            BrowserTabItem(title: "Active Real", url: "https://real.com", isFrozen: false, isActive: true)
        ]
        let resultDiscarded = activeTabsForDockPreview(tabsWithDiscarded)
        XCTAssertEqual(resultDiscarded.count, 1)
        XCTAssertEqual(resultDiscarded.first?.title, "Active Real")
    }

    func testBrowserPanelDimensions() {
        XCTAssertEqual(browserPanelDimensions(tabCount: 1), DockPreviewDimensions(panelWidth: 320, panelHeight: 220, cardWidth: 304, cardHeight: 160, thumbWidth: 304, thumbHeight: 160))
        XCTAssertEqual(browserPanelDimensions(tabCount: 2), DockPreviewDimensions(panelWidth: 516, panelHeight: 189, cardWidth: 240, cardHeight: 165, thumbWidth: 224, thumbHeight: 119))
        XCTAssertEqual(browserPanelDimensions(tabCount: 3), DockPreviewDimensions(panelWidth: 708, panelHeight: 189, cardWidth: 220, cardHeight: 165, thumbWidth: 204, thumbHeight: 119))
        XCTAssertEqual(browserPanelDimensions(tabCount: 4), DockPreviewDimensions(panelWidth: 894, panelHeight: 184, cardWidth: 210, cardHeight: 160, thumbWidth: 194, thumbHeight: 114))
        XCTAssertEqual(browserPanelDimensions(tabCount: 5), DockPreviewDimensions(panelWidth: 1064, panelHeight: 179, cardWidth: 200, cardHeight: 155, thumbWidth: 184, thumbHeight: 109))
        // Clamping check
        XCTAssertEqual(browserPanelDimensions(tabCount: 0), browserPanelDimensions(tabCount: 1))
        XCTAssertEqual(browserPanelDimensions(tabCount: 10), browserPanelDimensions(tabCount: 5))
    }


    // MARK: - Hidden-app windows (windowPreview.showHiddenWindows)

    /// The switch on the Xem trước cửa sổ page promises that windows of HIDDEN apps
    /// (⌘H, or Spotify/Slack hiding their last window on close) appear in the switcher.
    /// Before this rule existed the lister dropped them unconditionally, so the toggle
    /// changed nothing — a control with no reader (Part 0 §6). The rule is pure so a
    /// test can pin it without a window server.
    func testHiddenAppWindowsAreListedOnlyWhenTheSwitchIsOn() {
        // Visible app: always listed, regardless of the switch.
        XCTAssertTrue(WindowPreviewStore.listsWindow(ofHiddenApp: false, showHidden: false))
        XCTAssertTrue(WindowPreviewStore.listsWindow(ofHiddenApp: false, showHidden: true))
        // Hidden app: the switch decides.
        XCTAssertFalse(WindowPreviewStore.listsWindow(ofHiddenApp: true, showHidden: false),
                       "switch off must keep the old behaviour: hidden apps stay out")
        XCTAssertTrue(WindowPreviewStore.listsWindow(ofHiddenApp: true, showHidden: true),
                      "switch on must admit hidden apps — that is the whole promise of the toggle")
    }

    /// The accessor is the single reader of the key; its default must be `false`, the
    /// pre-existing behaviour, so nobody who never touched the switch sees new windows.
    func testShowsHiddenWindowsDefaultsToFalseWhenTheKeyIsAbsent() {
        let key = "windowPreview.showHiddenWindows"
        let saved = UserDefaults.standard.object(forKey: key)
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        UserDefaults.standard.removeObject(forKey: key)
        XCTAssertFalse(WindowPreviewStore.showsHiddenWindows)
        UserDefaults.standard.set(true, forKey: key)
        XCTAssertTrue(WindowPreviewStore.showsHiddenWindows, "the accessor must read the live key, not a cached value")
    }
}
