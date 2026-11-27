import XCTest
import Foundation

/// XF-ISLAND-C — Unified Dynamic Island tab catalog, migration, ordering, visibility,
/// availability gating, collapsed signals, deep links, and machine active-tab fallback.
final class NotchDestinationCatalogTests: XCTestCase {
    func testSettingsIsOutsideTheTabCatalogAndMovesKeepHiddenSlots() {
        XCTAssertNil(NotchDestinationID(extra: .settings))
        let start = NotchDestinationCatalog.defaultState.setting(.clipboard, enabled: false)
        let moved = start.movedWithinVisibilityGroup(.files, to: .nowPlaying)
        XCTAssertEqual(Array(moved.entries.prefix(3).map(\.id)), [.nowPlaying, .clipboard, .files])
        XCTAssertFalse(moved.isEnabled(.clipboard))
        XCTAssertEqual(moved.movedWithinVisibilityGroup(.files, to: .clipboard), moved)
    }
    typealias ID = NotchDestinationID
    typealias Catalog = NotchDestinationCatalog
    typealias Avail = NotchDestinationAvailability
    typealias M = NotchSurfaceMachine

    // MARK: - Migration & Missing vs Intentional All-Hidden

    func testMissingLegacyConfigUsesDefaultEnabledCatalog() {
        let state = Catalog.parse(catalogRaw: nil, legacyPagesRaw: nil)
        XCTAssertEqual(state, Catalog.defaultState)
        XCTAssertFalse(state.isAllHidden)
        XCTAssertEqual(state.entries.map(\.id), Catalog.canonicalOrder)
        XCTAssertTrue(state.isEnabled(.files))
        XCTAssertTrue(state.isEnabled(.system))
        XCTAssertTrue(state.isEnabled(.audio))
    }

    func testIntentionalAllHiddenIsDistinctFromMissingConfig() {
        let hidden = Catalog.allHiddenState
        let serialized = Catalog.serialize(hidden)
        XCTAssertFalse(serialized.isEmpty)

        let roundTrip = Catalog.parse(catalogRaw: serialized, legacyPagesRaw: nil)
        XCTAssertTrue(roundTrip.isAllHidden)
        XCTAssertTrue(roundTrip.enabledIDs.isEmpty)
        XCTAssertEqual(roundTrip.entries.map(\.id), Catalog.canonicalOrder)

        let sentinel = Catalog.parse(catalogRaw: Catalog.allHiddenSentinel, legacyPagesRaw: "files,clipboard")
        XCTAssertTrue(sentinel.isAllHidden)
        XCTAssertTrue(sentinel.enabledIDs.isEmpty)

        // Contrast with missing catalog + missing legacy ⇒ defaults enabled, NOT all-hidden.
        let missing = Catalog.parse(catalogRaw: "", legacyPagesRaw: nil)
        XCTAssertFalse(missing.isAllHidden)
        XCTAssertEqual(missing, Catalog.defaultState)
    }

    func testLegacyPagesMigrationPreservesOrderAndHiddenLegacyPages() {
        let migrated = Catalog.parse(catalogRaw: nil, legacyPagesRaw: "calendar,files,aiUsage")
        XCTAssertFalse(migrated.isAllHidden)
        XCTAssertEqual(migrated.enabledLegacyPages, [.calendar, .files, .aiUsage])
        XCTAssertTrue(migrated.isEnabled(.calendar))
        XCTAssertTrue(migrated.isEnabled(.files))
        XCTAssertTrue(migrated.isEnabled(.aiUsage))
        XCTAssertFalse(migrated.isEnabled(.clipboard), "omitted legacy page stays hidden after migration")
        XCTAssertFalse(migrated.isEnabled(.nowPlaying))
        XCTAssertFalse(migrated.isEnabled(.agents))
        XCTAssertFalse(migrated.isEnabled(.timer))
        // Extra modules are appended in canonical order
        XCTAssertTrue(migrated.isEnabled(.system))
        XCTAssertTrue(migrated.isEnabled(.audio))
        // Legacy enabled order stays first
        XCTAssertEqual(Array(migrated.entries.prefix(3).map(\.id)), [.calendar, .files, .aiUsage])
    }

    // MARK: - Unknown & Duplicate IDs

    func testUnknownAndDuplicateIDsAreDroppedAndCollapsed() {
        let raw = "v1:bogus:1,stocks:0,files:1,stocks:1,unknown_future:1,clipboard:0,files:0"
        let state = Catalog.parse(catalogRaw: raw, legacyPagesRaw: nil)
        XCTAssertEqual(state.entries.count, Catalog.canonicalOrder.count)
        XCTAssertEqual(Set(state.entries.map(\.id)).count, Catalog.canonicalOrder.count)
        // First occurrence wins for both order and enabled flag
        XCTAssertEqual(Array(state.entries.prefix(3).map(\.id)), [.stocks, .files, .clipboard])
        XCTAssertFalse(state.isEnabled(.stocks))
        XCTAssertTrue(state.isEnabled(.files))
        XCTAssertFalse(state.isEnabled(.clipboard))

        let legacyDirty = Catalog.parse(catalogRaw: nil, legacyPagesRaw: "bogus,timer,files,timer,ghost")
        XCTAssertEqual(legacyDirty.enabledLegacyPages, [.timer, .files])
    }

    // MARK: - Toggles & Persistent Order of Hidden Tabs

    func testTogglingOffPreservesPersistentPositionWhenReEnabled() {
        var state = Catalog.defaultState
        // Move `system` to index 1 (right after `files`)
        while state.entries[1].id != .system {
            state = state.moved(.system, by: -1)
        }
        XCTAssertEqual(state.entries[1].id, .system)

        // Hide `system`, serialize, reload, then re-enable it ⇒ stays at index 1!
        state = state.toggled(.system)
        XCTAssertFalse(state.isEnabled(.system))
        XCTAssertEqual(state.entries[1].id, .system, "hidden tab keeps its persistent index")

        let reloaded = Catalog.parse(catalogRaw: Catalog.serialize(state), legacyPagesRaw: nil)
        XCTAssertEqual(reloaded.entries[1].id, .system)
        XCTAssertFalse(reloaded.isEnabled(.system))

        let restored = reloaded.toggled(.system)
        XCTAssertTrue(restored.isEnabled(.system))
        XCTAssertEqual(restored.entries[1].id, .system, "re-enabling restores exact prior position")
    }

    func testFeedbackIsAnIndependentlyToggleableIslandDestination() {
        var state = Catalog.defaultState
        XCTAssertTrue(state.isEnabled(.feedback))
        XCTAssertTrue(state.visibleDestinations(availability: .builtInOnly).contains(.feedback))
        XCTAssertEqual(ID.feedback.destination, .extra(.feedback))

        state = state.toggled(.feedback)
        XCTAssertFalse(state.isEnabled(.feedback))
        XCTAssertFalse(state.visibleDestinations(availability: .builtInOnly).contains(.feedback))

        state = state.toggled(.feedback)
        XCTAssertTrue(state.isEnabled(.feedback))
        XCTAssertTrue(NotchGalleryRules.items(catalog: state, availability: .builtInOnly)
            .contains { $0.destination == .extra(.feedback) })
    }

    func testWebsiteAnalyticsIsAnIndependentlyToggleableIslandDestination() {
        var state = Catalog.defaultState
        XCTAssertTrue(state.isEnabled(.websiteAnalytics))
        XCTAssertTrue(state.visibleDestinations(availability: .builtInOnly).contains(.websiteAnalytics))
        XCTAssertEqual(ID.websiteAnalytics.destination, .extra(.websiteAnalytics))

        state = state.toggled(.websiteAnalytics)
        XCTAssertFalse(state.visibleDestinations(availability: .builtInOnly).contains(.websiteAnalytics))
        state = state.toggled(.websiteAnalytics)
        XCTAssertTrue(NotchGalleryRules.items(catalog: state, availability: .builtInOnly)
            .contains { $0.destination == .extra(.websiteAnalytics) })
    }

    func testProviderSettingsRemainReachableBeforeAndAfterConfiguration() {
        let builtInOnly = Avail.builtInOnly
        XCTAssertEqual(ID.stocks.settingsTarget(for: builtInOnly.readiness(for: .stocks)), "stocks")
        XCTAssertEqual(ID.revenue.settingsTarget(for: builtInOnly.readiness(for: .revenue)), "revenue")
        XCTAssertEqual(ID.websiteAnalytics.settingsTarget(for: builtInOnly.readiness(for: .websiteAnalytics)), "websiteAnalytics")

        var configured = builtInOnly
        configured.stocksConfigured = true
        configured.revenueConfigured = true
        XCTAssertEqual(ID.stocks.settingsTarget(for: configured.readiness(for: .stocks)), "stocks")
        XCTAssertEqual(ID.revenue.settingsTarget(for: configured.readiness(for: .revenue)), "revenue")
        XCTAssertNil(ID.timer.settingsTarget(for: .ready))
        XCTAssertEqual(ID.calendar.settingsTarget(for: .featureDisabled(settingsTarget: "calendar")), "calendar")
    }

    func testHiddenTabsCanBeReorderedAndAllTabsCanBeHidden() {
        var state = Catalog.allHiddenState
        XCTAssertTrue(state.isAllHidden)

        // Reorder while hidden
        state = state.moved(.clipboard, by: -1)
        XCTAssertEqual(state.entries[0].id, .clipboard)
        XCTAssertEqual(state.entries[1].id, .files)
        XCTAssertTrue(state.isAllHidden)

        // Drag reorder via IndexSet
        state = state.moved(fromOffsets: IndexSet(integer: 0), toOffset: 3)
        XCTAssertEqual(state.entries[2].id, .clipboard)

        // Toggling off the last enabled tab transitions cleanly to all-hidden
        var single = Catalog.allHiddenState.setting(.timer, enabled: true)
        XCTAssertEqual(single.enabledIDs, [.timer])
        single = single.toggled(.timer)
        XCTAssertTrue(single.isAllHidden)
        XCTAssertTrue(single.enabledIDs.isEmpty)
    }

    // MARK: - Unconfigured Stocks Opens Its Setup Page

    func testRetiredFinderTabIsRemovedFromSavedCatalog() {
        let state = Catalog.parse(catalogRaw: "v1:fileBrowser:1,files:1", legacyPagesRaw: nil)
        XCTAssertTrue(state.isEnabled(.files))
        XCTAssertFalse(state.entries.contains { $0.id == .fileBrowser })
    }

    func testUnconfiguredStocksCanOpenWhileOtherUnconfiguredModulesStayHidden() {
        let state = Catalog.defaultState
        let unconfigured = Avail.builtInOnly // weather/stocks/revenue unconfigured

        let visible = state.visibleDestinations(availability: unconfigured)
        XCTAssertFalse(visible.contains(.weather))
        XCTAssertTrue(visible.contains(.stocks))
        XCTAssertFalse(visible.contains(.revenue))
        XCTAssertEqual(unconfigured.readiness(for: .weather), .unconfigured)
        XCTAssertEqual(unconfigured.readiness(for: .stocks), .unconfigured)
        XCTAssertEqual(unconfigured.readiness(for: .revenue), .unconfigured)

        let nav = NotchNavLayout.unifiedPlan(
            catalog: state,
            availability: unconfigured,
            current: .files,
            isWide: true,
            hasPhysicalNotch: true
        )
        XCTAssertFalse(nav.pinned.contains(.weather))
        XCTAssertFalse(nav.overflowExtras.contains(.weather))
        XCTAssertTrue((nav.pinned + nav.overflowExtras).contains(.stocks))
        XCTAssertFalse(nav.overflowExtras.contains(.revenue))

        let gallery = NotchGalleryRules.items(catalog: state, availability: unconfigured)
        XCTAssertFalse(gallery.contains { $0.id == "weather" || $0.id == "revenue" })
        XCTAssertTrue(gallery.contains { $0.id == "stocks" })
        XCTAssertNil(NotchGalleryRules.destination(forKeyCharacter: "W", catalog: state, availability: unconfigured))
        XCTAssertEqual(NotchGalleryRules.destination(forKeyCharacter: "K", catalog: state, availability: unconfigured), .extra(.stocks))
        XCTAssertNil(NotchGalleryRules.destination(forKeyCharacter: "R", catalog: state, availability: unconfigured))

        XCTAssertEqual(Catalog.resolveDeepLink(pageParam: "stocks", catalog: state, availability: unconfigured), .stocks)
        let hidden = state.setting(.stocks, enabled: false)
        XCTAssertFalse(hidden.visibleDestinations(availability: unconfigured).contains(.stocks))
        XCTAssertNotEqual(Catalog.resolveDeepLink(pageParam: "stocks", catalog: hidden, availability: unconfigured), .stocks)

        // Once Stocks is configured (while Revenue stays unconfigured), user's preserved toggle takes effect
        var stocksOnly = unconfigured
        stocksOnly.stocksConfigured = true
        XCTAssertTrue(state.visibleDestinations(availability: stocksOnly).contains(.stocks))
        XCTAssertFalse(state.visibleDestinations(availability: stocksOnly).contains(.revenue))
        XCTAssertEqual(Catalog.resolveDeepLink(pageParam: "stocks", catalog: state, availability: stocksOnly), .stocks)
    }

    // MARK: - Active Tab Fallback, Lazy Cleanup & Active Drag Preservation

    func testActiveTabFallbackChoosesNearestVisibleAndCleansUpExtraModule() {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        var settings = M.Settings()
        var machine = M.Machine()
        machine.handle(.openExtra(.stocks), settings: settings, now: t0)
        XCTAssertEqual(machine.activeExtra, .stocks)

        // User hides Stocks while it is open ⇒ fallback to nearest enabled & ready destination (Revenue or Weather)
        let catalog = Catalog.defaultState.setting(.stocks, enabled: false)
        let fallback = catalog.fallbackDestination(from: .stocks, availability: .allReady)
        XCTAssertEqual(fallback, .revenue)

        machine.handle(.reconcileVisibility(fallback: fallback?.destination, allowAllHiddenRecovery: true), settings: settings, now: t0)
        XCTAssertEqual(machine.activeExtra, .revenue)
        XCTAssertFalse(machine.showingAllHiddenRecovery)

        // Now hide all destinations ⇒ active extra is cleared (lazy cleanup!) and recovery card opens
        let noneFallback = Catalog.allHiddenState.fallbackDestination(from: .revenue, availability: .allReady)
        XCTAssertNil(noneFallback)
        settings.allDestinationsHidden = true
        machine.handle(.reconcileVisibility(fallback: nil, allowAllHiddenRecovery: true), settings: settings, now: t0)
        XCTAssertNil(machine.activeExtra)
        XCTAssertTrue(machine.showingAllHiddenRecovery)
    }

    func testActiveFileDragAndDropIntakeArePreservedEvenWhenAllTabsHidden() {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        var settings = M.Settings()
        settings.shownPages = []
        settings.allDestinationsHidden = true
        settings.dragging = true

        var machine = M.Machine()
        // Hover must NOT open a dead hub when all tabs are hidden
        machine.handle(.hoverInZone(since: t0), settings: settings, now: t0.addingTimeInterval(1.0))
        XCTAssertEqual(machine.state, .collapsed)

        // File drag into notch STILL opens `.files` for drop intake
        machine.handle(.fileDragInZone, settings: settings, now: t0.addingTimeInterval(1.1))
        XCTAssertEqual(machine.state, .expanded(.files))
        XCTAssertNil(machine.activeExtra)
        XCTAssertFalse(machine.showingAllHiddenRecovery)

        // Reconciling visibility mid-drag MUST NOT kick the user off `.files`
        machine.handle(.reconcileVisibility(fallback: nil, allowAllHiddenRecovery: true), settings: settings, now: t0.addingTimeInterval(1.2))
        XCTAssertEqual(machine.state, .expanded(.files))
        XCTAssertFalse(machine.showingAllHiddenRecovery)

        // Drop completes cleanly
        machine.handle(.dropped(count: 2), settings: settings, now: t0.addingTimeInterval(1.3))
        XCTAssertEqual(machine.state, .expanded(.files))
        XCTAssertEqual(machine.itemCount, 2)
    }

    // MARK: - Collapsed Signals Honor Visibility

    func testCollapsedSignalSuppressesHiddenDestinations() {
        let hiddenAgentsAndTimer: Set<ID> = [.files, .nowPlaying]
        let signal = NotchCollapsedSignal.resolve(
            itemCount: 2,
            timerActive: true,
            timerPaused: false,
            nowPlayingActive: true,
            nowPlayingPlaying: true,
            agentActive: true,
            agentBusy: true,
            agentsNeedingYou: 1,
            visibleDestinations: hiddenAgentsAndTimer
        )
        XCTAssertEqual(signal, .files(2), "hidden agents & timer must not surface on collapsed wings")

        let allHidden = NotchCollapsedSignal.resolve(
            itemCount: 2,
            timerActive: true,
            timerPaused: false,
            nowPlayingActive: true,
            nowPlayingPlaying: true,
            agentActive: true,
            agentBusy: true,
            agentsNeedingYou: 1,
            visibleDestinations: []
        )
        XCTAssertEqual(allHidden, .none)
    }

    // MARK: - L10n Coverage

    func testEveryCatalogDestinationTitleIsTranslated() throws {
        let store = try L10nFixture.load()
        for id in ID.allCases {
            let key = id.titleKey
            if key == "Clipboard" { continue }
            guard let entry = store.entries[key] else {
                XCTFail("Missing L10n entry for catalog destination \(id.rawValue): \(key)")
                continue
            }
            XCTAssertFalse(entry.en.isEmpty, "Empty English translation for \(key)")
        }
    }
}
