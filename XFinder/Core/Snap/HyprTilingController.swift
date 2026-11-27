import AppKit
import ApplicationServices
import Carbon
import os

/// Event-driven HyprMac BSP Dwindle Tiling Engine inside XFinder (`SnapZones`).
/// Maintains per-display `BSPTree` layouts, handles `⌃⌥⇧` keyboard navigation/swaps/splits/resizes,
/// tiled drag-and-drop insertion, AX window lifecycle observers, and focus border rendering.
@MainActor
@Observable
final class HyprTilingController {
    static let shared = HyprTilingController()

    private(set) var isRunning = false
    private(set) var tiledWindowCount = 0
    var lastOutcome: String?

    private struct TrackedWindow {
        let id: CGWindowID
        let pid: pid_t
        let bundleID: String
        let axElement: AXUIElement
        var displayID: CGDirectDisplayID
    }

    private struct AppWatch {
        let observer: AXObserver
        let appElement: AXUIElement
    }

    private var trees: [CGDirectDisplayID: BSPTree] = [:]
    private var windowMap: [CGWindowID: TrackedWindow] = [:]
    private var floatingIDs: Set<CGWindowID> = []
    private var originalFrames: [CGWindowID: CGRect] = [:]
    private var maximizedByDisplay: [CGDirectDisplayID: CGWindowID] = [:]

    private let focusBorder = HyprFocusBorder()
    private var workspaceObservers: [NSObjectProtocol] = []
    private var screenObserver: NSObjectProtocol?
    private var appWatches: [pid_t: AppWatch] = [:]
    private nonisolated static let hotKeySignature: OSType = 0x58464854 // 'XFHT'
    private var carbonHandler: EventHandlerRef?
    private var hotKeyRefs: [UInt32: EventHotKeyRef] = [:]
    private(set) var registeredHotkeyCount = 0
    private(set) var failedHotkeyCount = 0
    private var masterEnabled = false
    private var lastFocusedWindowID: CGWindowID?

    private let log = Logger(subsystem: "com.xfinder.app", category: "HyprTiling")

    private init() {}

    // MARK: - Settings (ONE canonical reader per key — FeatureKeyDefaultsTests)

    var engineModeRaw: String {
        UserDefaults.standard.string(forKey: "snapzones.engineMode") ?? "tiling"
    }

    var isTilingMode: Bool { engineModeRaw == "tiling" }

    var gapSize: Int {
        UserDefaults.standard.object(forKey: "snapzones.tilingGap") as? Int ?? 8
    }

    var outerPadding: Int {
        UserDefaults.standard.object(forKey: "snapzones.tilingPadding") as? Int ?? 8
    }

    var focusBorderEnabled: Bool {
        UserDefaults.standard.object(forKey: "snapzones.focusBorder") as? Bool ?? true
    }

    var focusBorderWidth: Int {
        UserDefaults.standard.object(forKey: "snapzones.focusBorderWidth") as? Int ?? 3
    }

    var autoTileNewWindows: Bool {
        UserDefaults.standard.object(forKey: "snapzones.autoTileNewWindows") as? Bool ?? true
    }

    var tilingHotkeysEnabled: Bool {
        UserDefaults.standard.object(forKey: "snapzones.tilingHotkeys") as? Bool ?? true
    }

    var excludedBundleIDs: [String] {
        UserDefaults.standard.stringArray(forKey: "snapzones.tilingExcludedApps") ?? HyprTilingRules.defaultExcludedBundleIDs
    }

    func setExcludedBundleIDs(_ ids: [String]) {
        UserDefaults.standard.set(ids, forKey: "snapzones.tilingExcludedApps")
        applySettings(masterEnabled: masterEnabled)
    }

    // MARK: - Lifecycle

    func applySettings(masterEnabled: Bool) {
        self.masterEnabled = masterEnabled
        guard masterEnabled, isTilingMode, WindowManager.isTrusted else {
            stop()
            return
        }
        installWorkspaceObserversIfNeeded()
        if tilingHotkeysEnabled {
            registerCarbonHotkeys()
        } else {
            unregisterCarbonHotkeys()
        }
        if let front = NSWorkspace.shared.frontmostApplication {
            attachAXObserverIfNeeded(for: front.processIdentifier)
        }
        isRunning = true
        refreshFocusBorder()
    }

    func stop() {
        removeWorkspaceObservers()
        detachAllAXObservers()
        unregisterCarbonHotkeys()
        focusBorder.hide()
        isRunning = false
    }

    /// Re-applies layout after gap/padding slider changes when any tree already has tiled windows.
    func reapplyCurrentTreesIfNeeded() {
        guard masterEnabled, isTilingMode, WindowManager.isTrusted else { return }
        for (displayID, tree) in trees where !tree.windowIDs.isEmpty {
            if let screen = screen(for: displayID) {
                applyLayout(for: displayID, on: screen)
            }
        }
        refreshFocusBorder()
    }

    // MARK: - Actions (UI buttons + ⌃⌥⇧ hotkeys)

    func perform(_ action: HyprTilingAction) {
        guard masterEnabled, isTilingMode, WindowManager.isTrusted else { return }
        switch action {
        case .retileAll:
            retileAllOnPointerScreen()
        case .focus(let dir):
            moveFocus(dir)
        case .swap(let dir):
            swapFocused(dir)
        case .toggleSplit:
            toggleSplitFocused()
        case .toggleFloat:
            toggleFloatFocused()
        case .toggleMaximize:
            toggleMaximizeFocused()
        case .resizeGrow:
            resizeFocused(delta: BSPTree.resizeStep)
        case .resizeShrink:
            resizeFocused(delta: -BSPTree.resizeStep)
        case .balanceSplits:
            balanceActiveScreenSplits()
        }
    }

    func restoreAllOriginalFrames() {
        var restored = 0
        for (wid, axRect) in originalFrames {
            if let tw = windowMap[wid] {
                if writeWindowFrame(tw, axRect: axRect) { restored += 1 }
            } else if let tw = findLiveWindow(id: wid) {
                if writeWindowFrame(tw, axRect: axRect) { restored += 1 }
            }
        }
        trees.removeAll()
        maximizedByDisplay.removeAll()
        floatingIDs.removeAll()
        originalFrames.removeAll()
        tiledWindowCount = 0
        focusBorder.hide()
        lastOutcome = restored > 0
            ? "\(L10n.t("Đã khôi phục vị trí gốc cho "))\(restored)\(L10n.t(" cửa sổ."))"
            : L10n.t("Chưa có bố cục gốc nào được lưu.")
    }

    // MARK: - Action Implementations

    private func retileAllOnPointerScreen() {
        retileAll(on: WindowManager.screenUnderPointer())
    }

    private func retileAll(on screen: NSScreen) {
        let displayID = Self.displayID(for: screen)
        let usable = WindowManager.axVisibleFrame(for: screen)
        let discovered = discoverEligibleWindows(on: screen)

        var newTree = BSPTree()
        let excluded = Set(excludedBundleIDs)
        for win in discovered {
            guard !floatingIDs.contains(win.id), !excluded.contains(win.bundleID) else { continue }
            if originalFrames[win.id] == nil, let currentRect = readAXRect(win.axElement) {
                originalFrames[win.id] = currentRect
            }
            windowMap[win.id] = win
            newTree.insert(win.id, in: usable, gap: CGFloat(gapSize), padding: CGFloat(outerPadding))
        }

        maximizedByDisplay[displayID] = nil
        trees[displayID] = newTree
        applyLayout(for: displayID, on: screen)
        recomputeCount()
        refreshFocusBorder()

        let count = trees[displayID]?.windowIDs.count ?? 0
        lastOutcome = count > 0
            ? "\(L10n.t("Đã xếp lát "))\(count)\(L10n.t(" cửa sổ trên màn hình này."))"
            : L10n.t("Không tìm thấy cửa sổ đủ điều kiện để xếp lát.")
    }

    private func ensureTiledTree(for displayID: CGDirectDisplayID, including windowID: CGWindowID?) -> Bool {
        if trees[displayID]?.windowIDs.isEmpty ?? true {
            if let screen = screen(for: displayID) {
                retileAll(on: screen)
            } else {
                retileAllOnPointerScreen()
            }
        }
        guard let tree = trees[displayID], !tree.windowIDs.isEmpty else { return false }
        if let windowID { return tree.contains(windowID) }
        return true
    }

    private func moveFocus(_ dir: FocusDirection) {
        guard let current = targetWindowForAction(),
              let screen = screen(for: current.displayID) else { return }
        _ = ensureTiledTree(for: current.displayID, including: current.id)
        guard let tree = trees[current.displayID], tree.windowIDs.count >= 2 else {
            lastOutcome = L10n.t("Cần ít nhất 2 cửa sổ đang mở để thao tác lưới xếp lát.")
            return
        }
        let usable = WindowManager.axVisibleFrame(for: screen)
        guard let targetID = tree.neighbor(
            of: current.id,
            direction: dir,
            in: usable,
            gap: CGFloat(gapSize),
            padding: CGFloat(outerPadding)
        ), let targetWin = windowMap[targetID] ?? findLiveWindow(id: targetID) else {
            return
        }
        focusWindow(targetWin)
    }

    private func swapFocused(_ dir: FocusDirection) {
        guard let current = targetWindowForAction(),
              let screen = screen(for: current.displayID) else { return }
        _ = ensureTiledTree(for: current.displayID, including: current.id)
        guard var tree = trees[current.displayID], tree.windowIDs.count >= 2 else {
            lastOutcome = L10n.t("Cần ít nhất 2 cửa sổ đang mở để thao tác lưới xếp lát.")
            return
        }
        guard tree.contains(current.id) else { return }
        maximizedByDisplay[current.displayID] = nil
        let usable = WindowManager.axVisibleFrame(for: screen)
        guard let targetID = tree.neighbor(
            of: current.id,
            direction: dir,
            in: usable,
            gap: CGFloat(gapSize),
            padding: CGFloat(outerPadding)
        ) else { return }

        if tree.swap(current.id, targetID) {
            trees[current.displayID] = tree
            applyLayout(for: current.displayID, on: screen)
            refreshFocusBorder()
            lastOutcome = L10n.t("Đã hoán đổi hai cửa sổ.")
        }
    }

    private func toggleSplitFocused() {
        guard let current = targetWindowForAction(),
              let screen = screen(for: current.displayID) else { return }
        _ = ensureTiledTree(for: current.displayID, including: current.id)
        guard var tree = trees[current.displayID], tree.windowIDs.count >= 2 else {
            lastOutcome = L10n.t("Cần ít nhất 2 cửa sổ đang mở để thao tác lưới xếp lát.")
            return
        }
        guard tree.contains(current.id) else { return }
        maximizedByDisplay[current.displayID] = nil
        if tree.toggleSplit(for: current.id) {
            trees[current.displayID] = tree
            applyLayout(for: current.displayID, on: screen)
            refreshFocusBorder()
            lastOutcome = L10n.t("Đã đảo chiều chia ô.")
        }
    }

    private func toggleFloatFocused() {
        guard let current = targetWindowForAction() else { return }
        let wid = current.id
        let displayID = current.displayID
        guard let screen = screen(for: displayID) else { return }

        if var tree = trees[displayID], tree.contains(wid) {
            tree.remove(wid)
            trees[displayID] = tree
            floatingIDs.insert(wid)
            if maximizedByDisplay[displayID] == wid { maximizedByDisplay[displayID] = nil }
            if let orig = originalFrames[wid] {
                _ = writeWindowFrame(current, axRect: orig)
            }
            applyLayout(for: displayID, on: screen)
            recomputeCount()
            refreshFocusBorder()
            lastOutcome = L10n.t("Đã chuyển cửa sổ sang chế độ nổi.")
        } else {
            floatingIDs.remove(wid)
            if originalFrames[wid] == nil, let rect = readAXRect(current.axElement) {
                originalFrames[wid] = rect
            }
            windowMap[wid] = current
            var tree = trees[displayID] ?? BSPTree()
            let usable = WindowManager.axVisibleFrame(for: screen)
            tree.insert(wid, in: usable, gap: CGFloat(gapSize), padding: CGFloat(outerPadding))
            trees[displayID] = tree
            applyLayout(for: displayID, on: screen)
            recomputeCount()
            refreshFocusBorder()
            lastOutcome = L10n.t("Đã đưa cửa sổ vào lưới xếp lát.")
        }
    }

    private func toggleMaximizeFocused() {
        guard let current = targetWindowForAction(),
              let screen = screen(for: current.displayID) else { return }
        let displayID = current.displayID
        if maximizedByDisplay[displayID] == current.id {
            maximizedByDisplay[displayID] = nil
            applyLayout(for: displayID, on: screen)
            lastOutcome = L10n.t("Đã thu về bố cục xếp lát.")
        } else {
            maximizedByDisplay[displayID] = current.id
            let usable = WindowManager.axVisibleFrame(for: screen)
            let target = usable.insetBy(dx: CGFloat(outerPadding), dy: CGFloat(outerPadding))
            _ = writeWindowFrame(current, axRect: target)
            lastOutcome = L10n.t("Đã phóng đại cửa sổ trên không gian hiện tại.")
        }
        refreshFocusBorder()
    }

    private func resizeFocused(delta: CGFloat) {
        guard let current = targetWindowForAction(),
              let screen = screen(for: current.displayID) else { return }
        _ = ensureTiledTree(for: current.displayID, including: current.id)
        guard var tree = trees[current.displayID], tree.windowIDs.count >= 2 else {
            lastOutcome = L10n.t("Cần ít nhất 2 cửa sổ đang mở để thao tác lưới xếp lát.")
            return
        }
        guard tree.contains(current.id) else { return }
        maximizedByDisplay[current.displayID] = nil
        if tree.resize(windowID: current.id, delta: delta) {
            trees[current.displayID] = tree
            applyLayout(for: current.displayID, on: screen)
            refreshFocusBorder()
        }
    }

    private func balanceActiveScreenSplits() {
        let screen = WindowManager.screenUnderPointer()
        let displayID = Self.displayID(for: screen)
        _ = ensureTiledTree(for: displayID, including: nil)
        guard var tree = trees[displayID], !tree.windowIDs.isEmpty else { return }
        maximizedByDisplay[displayID] = nil
        tree.resetRatios()
        trees[displayID] = tree
        applyLayout(for: displayID, on: screen)
        refreshFocusBorder()
        lastOutcome = L10n.t("Đã cân bằng tỷ lệ các ô.")
    }

    // MARK: - Tiled Drag Integration (from SnapZoneController)

    func previewTiledDrag(pointerAppKit: CGPoint, draggedID: CGWindowID, on screen: NSScreen) -> TiledDropPlan? {
        guard masterEnabled, isTilingMode else { return nil }
        let displayID = Self.displayID(for: screen)
        guard let tree = trees[displayID], !tree.windowIDs.isEmpty else { return nil }
        let usable = WindowManager.axVisibleFrame(for: screen)
        let slots = tree.layout(in: usable, gap: CGFloat(gapSize), padding: CGFloat(outerPadding))
        let pointerAX = appKitPointToAX(pointerAppKit)
        return TiledDropResolver.resolve(pointerAX: pointerAX, draggedID: draggedID, slots: slots, gap: CGFloat(gapSize))
    }

    @discardableResult
    func commitTiledDrag(pointerAppKit: CGPoint, draggedID: CGWindowID, on screen: NSScreen) -> Bool {
        guard let plan = previewTiledDrag(pointerAppKit: pointerAppKit, draggedID: draggedID, on: screen) else {
            return false
        }
        let displayID = Self.displayID(for: screen)
        guard var tree = trees[displayID] else { return false }

        // Remove from any other display's tree first if dragged across monitors.
        for otherID in trees.keys where otherID != displayID {
            trees[otherID]?.remove(draggedID)
        }
        floatingIDs.remove(draggedID)
        if windowMap[draggedID] == nil, let found = findLiveWindow(id: draggedID) {
            windowMap[draggedID] = found
        }
        if let existing = windowMap[draggedID] {
            var updated = existing
            updated.displayID = displayID
            windowMap[draggedID] = updated
        }
        guard tree.insertBeside(draggedID, target: plan.targetID, edge: plan.edge) else { return false }
        maximizedByDisplay[displayID] = nil
        trees[displayID] = tree
        applyLayout(for: displayID, on: screen)
        recomputeCount()
        refreshFocusBorder()
        lastOutcome = plan.edge == .center
            ? L10n.t("Đã hoán đổi hai cửa sổ.")
            : L10n.t("Đã chèn cửa sổ vào lưới xếp lát.")
        return true
    }

    // MARK: - Layout Execution

    private func applyLayout(for displayID: CGDirectDisplayID, on screen: NSScreen) {
        guard var tree = trees[displayID] else { return }
        let usable = WindowManager.axVisibleFrame(for: screen)
        let slots = tree.layout(in: usable, gap: CGFloat(gapSize), padding: CGFloat(outerPadding))
        let maximizedID = maximizedByDisplay[displayID]

        var deadOrUnmovable: [CGWindowID] = []
        for (wid, rect) in slots {
            if maximizedID == wid { continue }
            guard let tw = windowMap[wid] else {
                deadOrUnmovable.append(wid)
                continue
            }
            if !writeWindowFrame(tw, axRect: rect) {
                log.notice("failed to move window \(wid); marking float")
                deadOrUnmovable.append(wid)
            }
        }

        if let maxID = maximizedID, let maxWin = windowMap[maxID] {
            let maxRect = usable.insetBy(dx: CGFloat(outerPadding), dy: CGFloat(outerPadding))
            _ = writeWindowFrame(maxWin, axRect: maxRect)
        }

        if !deadOrUnmovable.isEmpty {
            for wid in deadOrUnmovable {
                tree.remove(wid)
                floatingIDs.insert(wid)
            }
            trees[displayID] = tree
            let cleanSlots = tree.layout(in: usable, gap: CGFloat(gapSize), padding: CGFloat(outerPadding))
            for (wid, rect) in cleanSlots where maximizedID != wid {
                if let tw = windowMap[wid] { _ = writeWindowFrame(tw, axRect: rect) }
            }
        }
    }

    @discardableResult
    private func writeWindowFrame(_ tw: TrackedWindow, axRect: CGRect) -> Bool {
        if tw.pid == ProcessInfo.processInfo.processIdentifier,
           let browser = ownBrowserWindow(matching: tw.id) {
            guard !browser.styleMask.contains(.fullScreen) else { return false }
            let target = WindowManager.axRectToAppKit(axRect)
            browser.setFrame(target, display: true)
            return true
        }
        let appEl = AXUIElementCreateApplication(tw.pid)
        let enhancedKey = "AXEnhancedUserInterface" as CFString
        var enhancedRef: CFTypeRef?
        let wasEnhanced = AXUIElementCopyAttributeValue(appEl, enhancedKey, &enhancedRef) == .success
            && (enhancedRef as? Bool) == true
        if wasEnhanced {
            _ = AXUIElementSetAttributeValue(appEl, enhancedKey, kCFBooleanFalse)
        }
        defer {
            if wasEnhanced {
                _ = AXUIElementSetAttributeValue(appEl, enhancedKey, kCFBooleanTrue)
            }
        }

        var pos = CGPoint(x: axRect.minX, y: axRect.minY)
        var size = CGSize(width: axRect.width, height: axRect.height)
        guard let posVal = AXValueCreate(.cgPoint, &pos),
              let sizeVal = AXValueCreate(.cgSize, &size) else { return false }

        _ = AXUIElementSetAttributeValue(tw.axElement, kAXSizeAttribute as CFString, sizeVal)
        let posErr = AXUIElementSetAttributeValue(tw.axElement, kAXPositionAttribute as CFString, posVal)
        let sizeErr = AXUIElementSetAttributeValue(tw.axElement, kAXSizeAttribute as CFString, sizeVal)

        if posErr == .success && sizeErr == .success { return true }
        if posErr == .success { return true }
        if let actual = readAXRect(tw.axElement),
           abs(actual.minX - axRect.minX) <= 40,
           abs(actual.minY - axRect.minY) <= 40 {
            return true
        }
        DiagnosticsLog.record("snap", "axError", detail: "position \(posErr.rawValue) size \(sizeErr.rawValue)")
        return false
    }

    private func recomputeCount() {
        tiledWindowCount = trees.values.reduce(0) { $0 + $1.windowIDs.count }
    }

    // MARK: - Window Discovery & AX Queries

    private func discoverEligibleWindows(on screen: NSScreen) -> [TrackedWindow] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] else { return [] }
        let targetDisplay = Self.displayID(for: screen)
        let screenAX = Self.screenBoundsAX(for: screen)
        let me = ProcessInfo.processInfo.processIdentifier
        let excluded = Set(excludedBundleIDs)
        var result: [TrackedWindow] = []
        var axCacheByPID: [pid_t: [AXUIElement]] = [:]

        for dict in list {
            guard let pid = (dict[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  let num = (dict[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let layer = (dict[kCGWindowLayer as String] as? NSNumber)?.intValue,
                  let b = dict[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: b as CFDictionary) else { continue }
            let alpha = (dict[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1.0
            let wid = CGWindowID(num)
            let app = NSRunningApplication(processIdentifier: pid)
            let bundleID = app?.bundleIdentifier ?? ""

            var isOwnBrowser = false
            if pid == me {
                isOwnBrowser = ownBrowserWindow(matching: wid) != nil
                if !isOwnBrowser { continue }
            } else if app?.activationPolicy != .regular {
                continue
            }

            // Center must belong to `screen`
            let center = CGPoint(x: bounds.midX, y: bounds.midY)
            guard screenAX.contains(center) else { continue }

            let axWins = axCacheByPID[pid] ?? fetchAXWindows(pid: pid)
            axCacheByPID[pid] = axWins
            guard let axEl = matchAXElement(wid: wid, bounds: bounds, in: axWins) else { continue }

            let subrole = readStringAttribute(axEl, kAXSubroleAttribute as CFString)
            let resizable = isWindowResizable(axEl)
            let ownNonBrowser = (pid == me && !isOwnBrowser)
            guard HyprTilingRules.isEligibleWindow(
                layer: layer,
                alpha: alpha,
                bounds: bounds,
                subrole: subrole,
                isResizable: resizable,
                bundleID: bundleID,
                excludedBundleIDs: excluded,
                isOwnNonBrowser: ownNonBrowser
            ) else { continue }

            result.append(
                TrackedWindow(
                    id: wid,
                    pid: pid,
                    bundleID: bundleID,
                    axElement: axEl,
                    displayID: targetDisplay
                )
            )
        }
        return result
    }

    private func findLiveWindow(id wid: CGWindowID) -> TrackedWindow? {
        guard let list = CGWindowListCopyWindowInfo([.optionIncludingWindow], wid) as? [[String: Any]],
              let dict = list.first,
              let pid = (dict[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
              let b = dict[kCGWindowBounds as String] as? [String: Any],
              let bounds = CGRect(dictionaryRepresentation: b as CFDictionary) else { return nil }
        let app = NSRunningApplication(processIdentifier: pid)
        let bundleID = app?.bundleIdentifier ?? ""
        let axWins = fetchAXWindows(pid: pid)
        guard let axEl = matchAXElement(wid: wid, bounds: bounds, in: axWins) else { return nil }
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let screen = NSScreen.screens.first { Self.screenBoundsAX(for: $0).contains(center) } ?? WindowManager.screenUnderPointer()
        return TrackedWindow(id: wid, pid: pid, bundleID: bundleID, axElement: axEl, displayID: Self.displayID(for: screen))
    }

    private func currentFocusedWindow() -> TrackedWindow? {
        guard let front = NSWorkspace.shared.frontmostApplication else { return nil }
        return focusedOrFirstWindow(of: front)
    }

    private func ownBrowserWindow(matching wid: CGWindowID) -> BrowserWindow? {
        NSApp.windows.first(where: {
            HyprTilingRules.windowID(fromNSWindowNumber: $0.windowNumber) == wid
        }) as? BrowserWindow
    }

    private func targetWindowForAction() -> TrackedWindow? {
        guard let front = NSWorkspace.shared.frontmostApplication else { return nil }
        let me = ProcessInfo.processInfo.processIdentifier
        if front.processIdentifier == me {
            if let browser = NSApp.keyWindow as? BrowserWindow,
               let wid = HyprTilingRules.windowID(fromNSWindowNumber: browser.windowNumber) {
                if let existing = windowMap[wid] { return existing }
                let bundleID = front.bundleIdentifier ?? ""
                let bounds = appKitRectToAX(browser.frame)
                if let axEl = matchAXElement(wid: wid, bounds: bounds, in: fetchAXWindows(pid: me)) {
                    let center = CGPoint(x: bounds.midX, y: bounds.midY)
                    let screen = NSScreen.screens.first { Self.screenBoundsAX(for: $0).contains(center) } ?? WindowManager.screenUnderPointer()
                    return TrackedWindow(id: wid, pid: me, bundleID: bundleID, axElement: axEl, displayID: Self.displayID(for: screen))
                }
            }
            if let lastID = lastFocusedWindowID,
               let live = windowMap[lastID] ?? findLiveWindow(id: lastID),
               readAXRect(live.axElement) != nil {
                return live
            }
            if let other = WindowManager.frontmostOtherApp(), let win = focusedOrFirstWindow(of: other) {
                return win
            }
            return discoverEligibleWindows(on: WindowManager.screenUnderPointer()).first
        }
        return focusedOrFirstWindow(of: front)
    }

    private func focusedOrFirstWindow(of app: NSRunningApplication) -> TrackedWindow? {
        let pid = app.processIdentifier
        let bundleID = app.bundleIdentifier ?? ""
        let appEl = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appEl, 0.35)
        var focusedRef: CFTypeRef?
        let axWin: AXUIElement
        if AXUIElementCopyAttributeValue(appEl, kAXFocusedWindowAttribute as CFString, &focusedRef) == .success,
           let focused = focusedRef, CFGetTypeID(focused) == AXUIElementGetTypeID() {
            axWin = focused as! AXUIElement
        } else if let first = fetchAXWindows(pid: pid).first {
            axWin = first
        } else {
            return nil
        }
        var wid: CGWindowID = 0
        guard axGetWindowID(axWin, &wid) == .success, wid != 0 else { return nil }
        if let existing = windowMap[wid] { return existing }
        guard let rect = readAXRect(axWin) else { return nil }
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let screen = NSScreen.screens.first { Self.screenBoundsAX(for: $0).contains(center) } ?? WindowManager.screenUnderPointer()
        return TrackedWindow(id: wid, pid: pid, bundleID: bundleID, axElement: axWin, displayID: Self.displayID(for: screen))
    }

    private func focusWindow(_ tw: TrackedWindow) {
        AXUIElementPerformAction(tw.axElement, kAXRaiseAction as CFString)
        let appEl = AXUIElementCreateApplication(tw.pid)
        AXUIElementSetAttributeValue(appEl, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        if let app = NSRunningApplication(processIdentifier: tw.pid), let url = app.bundleURL {
            let cfg = NSWorkspace.OpenConfiguration()
            cfg.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: cfg) { _, _ in }
        }
        lastFocusedWindowID = tw.id
        if focusBorderEnabled, let rect = readAXRect(tw.axElement) {
            focusBorder.show(aroundAXRect: rect, borderWidth: CGFloat(focusBorderWidth))
        }
    }

    func refreshFocusBorder() {
        guard masterEnabled, isTilingMode, WindowManager.isTrusted,
              let current = currentFocusedWindow() else {
            focusBorder.hide()
            return
        }
        let me = ProcessInfo.processInfo.processIdentifier
        let isOwnNonBrowser = current.pid == me && ownBrowserWindow(matching: current.id) == nil
        guard !isOwnNonBrowser, !excludedBundleIDs.contains(current.bundleID),
              let rect = readAXRect(current.axElement) else {
            focusBorder.hide()
            return
        }
        lastFocusedWindowID = current.id
        if focusBorderEnabled {
            focusBorder.show(aroundAXRect: rect, borderWidth: CGFloat(focusBorderWidth))
        } else {
            focusBorder.hide()
        }
    }

    // MARK: - Event-Driven Workspace & AX Observers

    private func installWorkspaceObserversIfNeeded() {
        guard workspaceObservers.isEmpty else { return }
        let nc = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(
            nc.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
                let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
                runOnMainActor {
                    guard let self else { return }
                    if let pid { self.attachAXObserverIfNeeded(for: pid) }
                    self.refreshFocusBorder()
                }
            }
        )
        workspaceObservers.append(
            nc.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
                let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
                runOnMainActor {
                    guard let self, let pid else { return }
                    self.detachAXObserver(for: pid)
                    self.pruneWindows(for: pid)
                }
            }
        )
        workspaceObservers.append(
            nc.addObserver(forName: NSWorkspace.didHideApplicationNotification, object: nil, queue: .main) { [weak self] note in
                let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
                runOnMainActor {
                    guard let self, let pid else { return }
                    self.pruneWindows(for: pid)
                }
            }
        )
        workspaceObservers.append(
            nc.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
                runOnMainActor { self?.refreshFocusBorder() }
            }
        )
        if screenObserver == nil {
            screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
                runOnMainActor { self?.refreshFocusBorder() }
            }
        }
    }

    private func removeWorkspaceObservers() {
        let nc = NSWorkspace.shared.notificationCenter
        for obs in workspaceObservers { nc.removeObserver(obs) }
        workspaceObservers.removeAll()
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
    }

    private func attachAXObserverIfNeeded(for pid: pid_t) {
        guard appWatches[pid] == nil, pid != ProcessInfo.processInfo.processIdentifier else { return }
        let callback: AXObserverCallback = { _, element, notification, refcon in
            guard let refcon else { return }
            let controller = Unmanaged<HyprTilingController>.fromOpaque(refcon).takeUnretainedValue()
            let notif = notification as String
            var wid: CGWindowID = 0
            _ = axGetWindowID(element, &wid)
            Task { @MainActor in
                controller.handleAXNotification(notif, element: element, windowID: wid)
            }
        }
        var obs: AXObserver?
        guard AXObserverCreate(pid, callback, &obs) == .success, let observer = obs else { return }
        let appEl = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appEl, 0.35)
        let ref = Unmanaged.passUnretained(self).toOpaque()
        _ = AXObserverAddNotification(observer, appEl, kAXFocusedWindowChangedNotification as CFString, ref)
        _ = AXObserverAddNotification(observer, appEl, kAXWindowCreatedNotification as CFString, ref)
        _ = AXObserverAddNotification(observer, appEl, kAXUIElementDestroyedNotification as CFString, ref)
        _ = AXObserverAddNotification(observer, appEl, kAXWindowMiniaturizedNotification as CFString, ref)
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        appWatches[pid] = AppWatch(observer: observer, appElement: appEl)
    }

    private func detachAXObserver(for pid: pid_t) {
        guard let watch = appWatches.removeValue(forKey: pid) else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(watch.observer), .defaultMode)
    }

    private func detachAllAXObservers() {
        for pid in Array(appWatches.keys) { detachAXObserver(for: pid) }
    }

    private func handleAXNotification(_ name: String, element: AXUIElement, windowID wid: CGWindowID) {
        guard masterEnabled, isTilingMode else { return }
        if name == (kAXFocusedWindowChangedNotification as String) {
            refreshFocusBorder()
            return
        }
        if name == (kAXWindowCreatedNotification as String), autoTileNewWindows {
            admitNewlyCreatedWindow(element: element, hintID: wid)
            return
        }
        if name == (kAXUIElementDestroyedNotification as String) || name == (kAXWindowMiniaturizedNotification as String),
           wid != 0 {
            removeAndReflowWindow(id: wid)
        }
    }

    private func admitNewlyCreatedWindow(element: AXUIElement, hintID: CGWindowID) {
        var wid = hintID
        if wid == 0 { _ = axGetWindowID(element, &wid) }
        guard wid != 0, windowMap[wid] == nil, !floatingIDs.contains(wid) else { return }
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        let app = NSRunningApplication(processIdentifier: pid)
        let bundleID = app?.bundleIdentifier ?? ""
        let excluded = Set(excludedBundleIDs)
        guard let rect = readAXRect(element),
              HyprTilingRules.isEligibleWindow(
                  layer: 0,
                  alpha: 1,
                  bounds: rect,
                  subrole: readStringAttribute(element, kAXSubroleAttribute as CFString),
                  isResizable: isWindowResizable(element),
                  bundleID: bundleID,
                  excludedBundleIDs: excluded,
                  isOwnNonBrowser: pid == ProcessInfo.processInfo.processIdentifier
              ) else { return }

        let center = CGPoint(x: rect.midX, y: rect.midY)
        let screen = NSScreen.screens.first { Self.screenBoundsAX(for: $0).contains(center) } ?? WindowManager.screenUnderPointer()
        let displayID = Self.displayID(for: screen)
        // Auto-admit only into displays where the user already initiated tiling (`!tree.windowIDs.isEmpty`),
        // so unrelated floating apps are never scrambled unexpectedly until "Xếp lát ngay" runs.
        guard var tree = trees[displayID], !tree.windowIDs.isEmpty else { return }

        let tw = TrackedWindow(id: wid, pid: pid, bundleID: bundleID, axElement: element, displayID: displayID)
        windowMap[wid] = tw
        originalFrames[wid] = rect
        let usable = WindowManager.axVisibleFrame(for: screen)
        tree.insert(wid, in: usable, gap: CGFloat(gapSize), padding: CGFloat(outerPadding), preferredTarget: lastFocusedWindowID)
        trees[displayID] = tree
        maximizedByDisplay[displayID] = nil
        applyLayout(for: displayID, on: screen)
        recomputeCount()
        refreshFocusBorder()
    }

    private func removeAndReflowWindow(id wid: CGWindowID) {
        guard let tw = windowMap.removeValue(forKey: wid) else { return }
        let displayID = tw.displayID
        guard var tree = trees[displayID], tree.contains(wid) else { return }
        tree.remove(wid)
        trees[displayID] = tree
        if maximizedByDisplay[displayID] == wid { maximizedByDisplay[displayID] = nil }
        if let screen = screen(for: displayID) {
            applyLayout(for: displayID, on: screen)
        }
        recomputeCount()
        refreshFocusBorder()
    }

    private func pruneWindows(for pid: pid_t) {
        let doomed = windowMap.values.filter { $0.pid == pid }.map(\.id)
        for wid in doomed { removeAndReflowWindow(id: wid) }
    }

    // MARK: - ⌃⌥⇧ Carbon Global Hotkeys

    private func registerCarbonHotkeys() {
        installCarbonHandlerIfNeeded()
        if hotKeyRefs.count == HyprTilingRules.hotkeyBindings.count && failedHotkeyCount == 0 {
            return
        }
        unregisterCarbonHotkeys()
        let modifiers = UInt32(controlKey | optionKey | shiftKey)
        var registered = 0
        var failed = 0
        for binding in HyprTilingRules.hotkeyBindings {
            var ref: EventHotKeyRef?
            let hkID = EventHotKeyID(signature: Self.hotKeySignature, id: binding.id)
            let status = RegisterEventHotKey(binding.keyCode, modifiers, hkID, GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref {
                hotKeyRefs[binding.id] = ref
                registered += 1
            } else {
                failed += 1
                log.notice("failed to register hotkey \(binding.label, privacy: .public) status=\(status)")
            }
        }
        registeredHotkeyCount = registered
        failedHotkeyCount = failed
        log.notice("registered \(registered)/\(HyprTilingRules.hotkeyBindings.count) HyprTiling Carbon hotkeys")
    }

    private func unregisterCarbonHotkeys() {
        for ref in hotKeyRefs.values {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()
        registeredHotkeyCount = 0
        failedHotkeyCount = 0
    }

    private func installCarbonHandlerIfNeeded() {
        guard carbonHandler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var hkID = EventHotKeyID()
            GetEventParameter(event, UInt32(kEventParamDirectObject), UInt32(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            guard hkID.signature == HyprTilingController.hotKeySignature else {
                return OSStatus(eventNotHandledErr)
            }
            let controller = Unmanaged<HyprTilingController>.fromOpaque(userData).takeUnretainedValue()
            let firedID = hkID.id
            Task { @MainActor in
                controller.handleCarbonHotKey(id: firedID)
            }
            return noErr
        }
        InstallEventHandler(GetApplicationEventTarget(), callback, 1, &spec,
                            Unmanaged.passUnretained(self).toOpaque(), &carbonHandler)
    }

    private func handleCarbonHotKey(id: UInt32) {
        guard let binding = HyprTilingRules.hotkeyBindings.first(where: { $0.id == id }) else { return }
        log.notice("hotkey fired: \(binding.label, privacy: .public)")
        perform(binding.action)
    }

    // MARK: - Coordinate & AX Utilities

    private func fetchAXWindows(pid: pid_t) -> [AXUIElement] {
        let appEl = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appEl, 0.35)
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appEl, kAXWindowsAttribute as CFString, &ref) == .success,
              let arr = ref as? [AXUIElement] else { return [] }
        return arr
    }

    private func matchAXElement(wid: CGWindowID, bounds: CGRect, in elements: [AXUIElement]) -> AXUIElement? {
        if let byID = elements.first(where: { el in var id: CGWindowID = 0; return axGetWindowID(el, &id) == .success && id == wid }) {
            return byID
        }
        return elements.first { el in
            guard let r = readAXRect(el) else { return false }
            return abs(r.minX - bounds.minX) < 4 && abs(r.minY - bounds.minY) < 4
        }
    }

    private func readAXRect(_ el: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(el, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let pv = posRef, let sv = sizeRef,
              CFGetTypeID(pv) == AXValueGetTypeID(),
              CFGetTypeID(sv) == AXValueGetTypeID() else { return nil }
        var pos = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(pv as! AXValue, .cgPoint, &pos),
              AXValueGetValue(sv as! AXValue, .cgSize, &size),
              pos.x.isFinite, pos.y.isFinite, size.width.isFinite, size.height.isFinite else { return nil }
        return CGRect(origin: pos, size: size)
    }

    private func readStringAttribute(_ el: AXUIElement, _ key: CFString) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, key, &ref) == .success else { return nil }
        return ref as? String
    }

    private func isWindowResizable(_ el: AXUIElement) -> Bool {
        var settable: DarwinBoolean = false
        let err = AXUIElementIsAttributeSettable(el, kAXSizeAttribute as CFString, &settable)
        return err == .success ? settable.boolValue : true
    }

    private func appKitPointToAX(_ p: CGPoint) -> CGPoint {
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        return CGPoint(x: p.x, y: top - p.y)
    }

    private func appKitRectToAX(_ rect: CGRect) -> CGRect {
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        return CGRect(x: rect.minX, y: top - rect.maxY, width: rect.width, height: rect.height)
    }

    private static func displayID(for screen: NSScreen) -> CGDirectDisplayID {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? CGMainDisplayID()
    }

    private func screen(for displayID: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first { Self.displayID(for: $0) == displayID }
    }

    private static func screenBoundsAX(for screen: NSScreen) -> CGRect {
        let primaryMaxY = NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY
        return CGRect(
            x: screen.frame.minX,
            y: primaryMaxY - screen.frame.maxY,
            width: screen.frame.width,
            height: screen.frame.height
        )
    }
}
