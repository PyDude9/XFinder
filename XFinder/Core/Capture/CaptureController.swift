import AppKit
import SwiftUI
import Carbon
import ImageIO
import UniformTypeIdentifiers

/// F4 — "Chụp & chú thích", built like OneNotch's Quick Access: a capture lands on the clipboard at
/// once, a small card offers to mark it up / save it / pin it / drag it out, and marking up is quick
/// (Return copies the result). This file owns the engine: hotkeys (Carbon, like
/// `QuickSearchPanelController` — no Accessibility needed, no CGEvent tap to steal from anyone else),
/// `/usr/sbin/screencapture` for the actual pixels (the same public tool `ScreenTextCopier` already
/// uses), the on-disk history, and every action a card/editor/settings row can invoke.
///
/// One Core reader per `UserDefaults` key, in the exact grep-able forms CLAUDE.md requires — every
/// other file (the settings page, the editor) only BINDS the same keys with `@AppStorage`.
@MainActor
@Observable
final class CaptureController {
    static let shared = CaptureController()

    private(set) var history: [CaptureItem] = []
    private(set) var recordingMode: CaptureMode?
    private(set) var lastConflict: (mode: CaptureMode, conflict: CaptureRules.Conflict)?
    private(set) var lastError: String?

    var isScreenRecordingGranted: Bool { CGPreflightScreenCaptureAccess() }

    // MARK: - Reader state (one reader per key)

    /// The menu-bar menu asks here too: it draws a mode's chord only while the hotkeys are registered.
    var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "capture.enabled") as? Bool ?? true
    }
    private var after: CaptureAfter {
        CaptureAfter(rawValue: UserDefaults.standard.string(forKey: "capture.after") ?? "copyAndCard") ?? .copyAndCard
    }
    // capture.cardSeconds / capture.cardEdge / capture.pauseOnHover / capture.swipeDismiss are read by
    // QuickAccessController (the card lifecycle owner) — exactly one Core reader per key.
    private var soundEnabled: Bool {
        UserDefaults.standard.object(forKey: "capture.sound") as? Bool ?? true
    }
    private var savedFolderRaw: String {
        UserDefaults.standard.string(forKey: "capture.saveFolder") ?? ""
    }
    private var format: CaptureFormat {
        CaptureFormat(rawValue: UserDefaults.standard.string(forKey: "capture.format") ?? "png") ?? .png
    }
    private var keepHistory: Bool {
        UserDefaults.standard.object(forKey: "capture.keepHistory") as? Bool ?? true
    }
    /// The editor's one reader form for its own defaults (CONTRACT: CORE must expose these so the
    /// default-agreement gate has one reader; the editor itself uses `@AppStorage` with the same keys).
    var defaultColor: MarkColor {
        MarkColor(rawValue: UserDefaults.standard.string(forKey: "capture.annotate.color") ?? "red") ?? .red
    }
    var defaultWidth: StrokeWidth {
        StrokeWidth(rawValue: UserDefaults.standard.string(forKey: "capture.annotate.width") ?? "medium") ?? .medium
    }

    var capturesFolder: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("XFinder", isDirectory: true)
            .appendingPathComponent("Captures", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    var saveFolder: URL {
        let raw = savedFolderRaw
        if !raw.isEmpty {
            let url = URL(fileURLWithPath: raw, isDirectory: true)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
    }

    // MARK: - Hotkeys (Carbon — same mechanism as QuickSearchPanelController)

    /// 'XFcp' — XFinder capture hotkey signature.
    private static let hotKeySignature: OSType = 0x58466370
    private var hotKeyRefs: [CaptureMode: EventHotKeyRef] = [:]
    private var carbonHandler: EventHandlerRef?
    private var recordMonitor: Any?
    private var historyLoaded = false

    private init() {}

    // MARK: - Settings application

    func applySettings() {
        loadHistoryIfNeeded()
        guard isEnabled else { unregisterAllHotkeys(); return }
        installCarbonHandlerIfNeeded()
        for mode in CaptureMode.allCases {
            registerHotkey(for: mode)
        }
    }

    func shortcut(for mode: CaptureMode) -> CaptureShortcut? {
        CaptureShortcut.decode(UserDefaults.standard.string(forKey: mode.shortcutKey))
    }

    private func assignedShortcuts() -> [CaptureMode: CaptureShortcut] {
        var out: [CaptureMode: CaptureShortcut] = [:]
        for mode in CaptureMode.allCases {
            if let s = shortcut(for: mode) { out[mode] = s }
        }
        return out
    }

    private func registerHotkey(for mode: CaptureMode) {
        unregisterHotkey(for: mode)
        guard let shortcut = shortcut(for: mode) else { return }
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: Self.hotKeySignature, id: UInt32(modeIndex(mode)))
        let status = RegisterEventHotKey(UInt32(shortcut.keyCode), shortcut.carbonModifiers,
                                          id, GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref { hotKeyRefs[mode] = ref }
    }

    private func unregisterHotkey(for mode: CaptureMode) {
        if let ref = hotKeyRefs[mode] { UnregisterEventHotKey(ref) }
        hotKeyRefs[mode] = nil
    }

    private func unregisterAllHotkeys() {
        for mode in CaptureMode.allCases { unregisterHotkey(for: mode) }
    }

    private func modeIndex(_ mode: CaptureMode) -> Int {
        (CaptureMode.allCases.firstIndex(of: mode) ?? 0) + 1
    }

    private func mode(forIndex index: Int) -> CaptureMode? {
        let i = index - 1
        guard CaptureMode.allCases.indices.contains(i) else { return nil }
        return CaptureMode.allCases[i]
    }

    private func installCarbonHandlerIfNeeded() {
        guard carbonHandler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var hkID = EventHotKeyID()
            GetEventParameter(event, UInt32(kEventParamDirectObject), UInt32(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            guard hkID.signature == CaptureController.hotKeySignature else { return OSStatus(eventNotHandledErr) }
            let c = Unmanaged<CaptureController>.fromOpaque(userData).takeUnretainedValue()
            let fired = Int(hkID.id)
            Task { @MainActor in
                if let mode = c.mode(forIndex: fired) { c.capture(mode) }
            }
            return noErr
        }
        InstallEventHandler(GetApplicationEventTarget(), callback, 1, &spec,
                            Unmanaged.passUnretained(self).toOpaque(), &carbonHandler)
    }

    // MARK: - Shortcut recording

    func beginRecording(_ mode: CaptureMode) {
        guard recordingMode == nil else { return }
        recordingMode = mode
        unregisterAllHotkeys()
        recordMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 { // Esc
                Task { @MainActor in self.cancelRecording() }
                return nil
            }
            let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
            let shortcut = CaptureShortcut(keyCode: Int(event.keyCode), modifiers: Int(mods.rawValue))
            guard shortcut.hasRequiredModifier else { return event }
            Task { @MainActor in self.finishRecording(mode: mode, shortcut: shortcut) }
            return nil
        }
    }

    func cancelRecording() {
        releaseRecordMonitor()
        recordingMode = nil
        applySettings()
    }

    private func finishRecording(mode: CaptureMode, shortcut: CaptureShortcut) {
        UserDefaults.standard.set(shortcut.encoded, forKey: mode.shortcutKey)
        let assigned = assignedShortcuts()
        if let conflict = CaptureRules.conflict(for: shortcut, mode: mode, assigned: assigned) {
            lastConflict = (mode, conflict)
        } else if lastConflict?.mode == mode {
            lastConflict = nil
        }
        releaseRecordMonitor()
        recordingMode = nil
        applySettings()
    }

    func clearShortcut(_ mode: CaptureMode) {
        UserDefaults.standard.removeObject(forKey: mode.shortcutKey)
        if lastConflict?.mode == mode { lastConflict = nil }
        applySettings()
    }

    func applyOneNotchPreset() {
        for (mode, shortcut) in CaptureRules.oneNotchPreset {
            UserDefaults.standard.set(shortcut.encoded, forKey: mode.shortcutKey)
        }
        lastConflict = nil
        let assigned = assignedShortcuts()
        for (mode, shortcut) in assigned {
            if let conflict = CaptureRules.conflict(for: shortcut, mode: mode, assigned: assigned) {
                lastConflict = (mode, conflict)
                break
            }
        }
        applySettings()
    }

    private func releaseRecordMonitor() {
        if let recordMonitor { NSEvent.removeMonitor(recordMonitor) }
        recordMonitor = nil
    }

    // MARK: - Capture

    func capture(_ mode: CaptureMode) {
        switch mode {
        case .text:
            ScreenTextCopier.shared.start()
        case .color:
            ScreenColorPicker.shared.pick()
        case .area, .window, .fullscreen, .areaAnnotate:
            captureScreen(mode)
        }
    }

    private func captureScreen(_ mode: CaptureMode) {
        guard CGPreflightScreenCaptureAccess() else {
            _ = CGRequestScreenCaptureAccess()
            lastError = L10n.t("Cần quyền Ghi màn hình để chụp ảnh.")
            // A hotkey press must answer where the user is looking, not only on the settings page.
            Self.copyTextToast.show(symbol: "exclamationmark.triangle.fill", title: L10n.t("Cần quyền Ghi màn hình để chụp ảnh."),
                                    detail: L10n.t("Cấp quyền trong Tính năng & Quyền rồi thử lại."), duration: 3.0)
            return
        }
        let sound = soundEnabled
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("xfinder-capture-\(UUID().uuidString).png")
        let windowID = (mode == .window) ? Self.frontmostOtherWindowID() : nil
        let display = Self.displayIndexUnderPointer()
        let args = CaptureRules.screencaptureArguments(mode: mode, output: tmp.path, sound: sound,
                                                        windowID: windowID, display: display)
        Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = args
            guard (try? process.run()) != nil else {
                DiagnosticsLog.record("capture", "toolNotRun")
                await MainActor.run { [weak self] in self?.lastError = L10n.t("Không chạy được công cụ chụp màn hình.") }
                return
            }
            process.waitUntilExit()
            await MainActor.run { [weak self] in
                self?.finishCapture(mode: mode, tempURL: tmp)
            }
        }
    }

    private func finishCapture(mode: CaptureMode, tempURL: URL) {
        defer { try? FileManager.default.removeItem(at: tempURL) }
        guard let size = (try? tempURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size > 0,
              let src = CGImageSourceCreateWithURL(tempURL as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(src, 0, nil)
        else { return } // Esc — cancelled silently, like ScreenTextCopier.

        let date = Date()
        let name = CaptureRules.uniqueName(
            CaptureRules.fileName(prefix: L10n.t("Ảnh chụp"), at: L10n.t(" lúc "), date: date, ext: "png"),
            existing: existingFileNames())
        let destURL = capturesFolder.appendingPathComponent(name)
        // MOVE screencapture's own file: re-encoding would drop its DPI (144 on Retina), and the editor and the pin
        // window derive the pixel→point scale from that DPI.
        do {
            try FileManager.default.moveItem(at: tempURL, to: destURL)
        } catch {
            lastError = L10n.t("Không lưu được ảnh chụp.")
            return
        }
        let item = CaptureItem(url: destURL, date: date, pixelWidth: image.width, pixelHeight: image.height)
        history.insert(item, at: 0)
        pruneHistory()
        if !keepHistory {
            // Keep the file on disk only while a card/editor still needs it; nothing else retains it.
        }
        copy(item)

        if mode == .areaAnnotate {
            annotate(item)
        } else {
            switch after {
            case .copyAndCard: QuickAccessController.shared.show(item)
            case .copyOnly: break
            case .annotate: annotate(item)
            }
        }
    }

    private func existingFileNames() -> Set<String> {
        (try? FileManager.default.contentsOfDirectory(atPath: capturesFolder.path)).map(Set.init) ?? []
    }

    private func pruneHistory() {
        guard keepHistory else {
            // History disabled: keep only what is still referenced by a visible card or an open editor.
            let toRemove = history.filter { !QuickAccessController.shared.isShowing($0) && !AnnotateWindowController.shared.isOpen($0) }
            for item in toRemove { try? FileManager.default.removeItem(at: item.url) }
            history.removeAll { toRemove.contains($0) }
            return
        }
        let prune = CaptureRules.toPrune(history, limit: CaptureRules.historyLimit)
        guard !prune.isEmpty else { return }
        for item in prune { try? FileManager.default.removeItem(at: item.url) }
        let pruneSet = Set(prune.map(\.id))
        history.removeAll { pruneSet.contains($0.id) }
    }

    private func loadHistoryIfNeeded() {
        guard !historyLoaded else { return }
        historyLoaded = true
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: capturesFolder.path) else { return }
        var items: [CaptureItem] = []
        for name in names where name.lowercased().hasSuffix(".png") {
            let url = capturesFolder.appendingPathComponent(name)
            guard let attrs = try? fm.attributesOfItem(atPath: url.path) else { continue }
            let date = (attrs[.creationDate] as? Date) ?? Date()
            var w = 0, h = 0
            if let src = CGImageSourceCreateWithURL(url as CFURL, nil),
               let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] {
                w = (props[kCGImagePropertyPixelWidth] as? Int) ?? 0
                h = (props[kCGImagePropertyPixelHeight] as? Int) ?? 0
            }
            items.append(CaptureItem(url: url, date: date, pixelWidth: w, pixelHeight: h))
        }
        history = items.sorted { $0.date > $1.date }
    }

    // MARK: - Window/display targeting

    /// The frontmost OTHER app's frontmost on-screen layer-0 window id. Never XFinder's own window.
    private static func frontmostOtherWindowID() -> Int? {
        guard let raw = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return nil }
        let ownPID = Int(ProcessInfo.processInfo.processIdentifier)
        for dict in raw {
            let layer = (dict[kCGWindowLayer as String] as? Int) ?? -1
            guard layer == 0 else { continue }
            guard (dict[kCGWindowOwnerPID as String] as? Int) != ownPID else { continue }
            // Part 3c: SharingState 0 = a window nothing can capture (Stage Manager's gesture overlays) — skip it.
            guard (dict[kCGWindowSharingState as String] as? Int) != 0 else { continue }
            guard ((dict[kCGWindowAlpha as String] as? Double) ?? 1) > 0 else { continue }
            guard let num = dict[kCGWindowNumber as String] as? Int else { continue }
            return num
        }
        return nil
    }

    /// 1-based index (screencapture's `-D`) of the screen under the pointer, matched by `CGDirectDisplayID`.
    private static func displayIndexUnderPointer() -> Int {
        let screen = WindowManager.screenUnderPointer()
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return 1 }
        let targetID = CGDirectDisplayID(number.uint32Value)
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(16, &ids, &count) == .success else { return 1 }
        for i in 0..<Int(count) where ids[i] == targetID {
            return i + 1
        }
        return 1
    }

    // MARK: - Item actions

    func annotate(_ item: CaptureItem) {
        AnnotateWindowController.shared.open(item)
        QuickAccessController.shared.editorDidChange()
    }

    func copy(_ item: CaptureItem) {
        guard let src = CGImageSourceCreateWithURL(item.url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return }
        copyImage(image, scale: 1)
    }

    func copyImage(_ image: CGImage, scale: CGFloat) {
        let rep = NSBitmapImageRep(cgImage: image)
        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        let nsImage = NSImage(cgImage: image, size: NSSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale))
        let pb = NSPasteboard.general
        pb.clearContents()
        let item = NSPasteboardItem()
        item.setData(png, forType: .png)
        if let tiff = nsImage.tiffRepresentation {
            item.setData(tiff, forType: .tiff)
        }
        pb.writeObjects([item])
    }

    @discardableResult
    func save(_ item: CaptureItem) -> URL? {
        guard let src = CGImageSourceCreateWithURL(item.url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            lastError = L10n.t("Không đọc được ảnh chụp.")
            return nil
        }
        let base = item.url.deletingPathExtension().lastPathComponent
        return save(image: image, scale: 1, suggestedName: base)
    }

    @discardableResult
    func save(image: CGImage, scale: CGFloat, suggestedName: String) -> URL? {
        let fmt = format
        guard let data = AnnotationRenderer.encode(image, format: fmt.utType, scale: scale) else {
            lastError = L10n.t("Không mã hoá được ảnh chụp.")
            return nil
        }
        let folder = saveFolder
        let existing = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)).map(Set.init) ?? []
        let name = CaptureRules.uniqueName("\(suggestedName).\(fmt.fileExtension)", existing: existing)
        let destURL = folder.appendingPathComponent(name)
        do {
            try data.write(to: destURL)
            return destURL
        } catch {
            lastError = L10n.t("Không lưu được ảnh chụp.")
            return nil
        }
    }

    func pin(_ item: CaptureItem) {
        PinnedImageController.shared.pin(item)
    }

    private static let copyTextToast = ToastSurface(style: .toast)

    func copyText(_ item: CaptureItem) {
        guard let src = CGImageSourceCreateWithURL(item.url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return }
        Task.detached(priority: .userInitiated) {
            let lines = ScreenTextRecognizer.recognize(image)
            let text = OCRText.assemble(lines)
            await MainActor.run {
                guard let text else {
                    Self.copyTextToast.show(symbol: "text.viewfinder", title: L10n.t("Không tìm thấy chữ"), duration: 2.4)
                    return
                }
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(text, forType: .string)
                Self.copyTextToast.show(symbol: "doc.on.clipboard",
                    title: "\(L10n.t("Đã sao chép "))\(OCRText.lineCount(text))\(L10n.t(" dòng"))", duration: 2.4)
            }
        }
    }

    func reveal(_ item: CaptureItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    func delete(_ item: CaptureItem) {
        try? FileManager.default.removeItem(at: item.url)
        history.removeAll { $0.id == item.id }
        QuickAccessController.shared.dismiss(item)
    }

    func clearHistory() {
        for item in history { try? FileManager.default.removeItem(at: item.url) }
        history.removeAll()
    }

    // MARK: - Thumbnails

    private static let thumbnailCache: NSCache<NSString, CGImageBox> = {
        let c = NSCache<NSString, CGImageBox>()
        c.countLimit = 120
        return c
    }()

    func thumbnail(for item: CaptureItem, maxPixel: Int) -> CGImage? {
        let key = "\(item.url.path)#\(maxPixel)" as NSString
        if let hit = Self.thumbnailCache.object(forKey: key) { return hit.image }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceShouldCache: false
        ]
        guard let src = CGImageSourceCreateWithURL(item.url as CFURL, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else {
            Self.thumbnailCache.setObject(CGImageBox(image: nil), forKey: key)
            return nil
        }
        Self.thumbnailCache.setObject(CGImageBox(image: cg), forKey: key)
        return cg
    }

    func chooseSaveFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = saveFolder
        guard panel.runModal() == .OK, let url = panel.url else { return }
        UserDefaults.standard.set(url.path, forKey: CaptureRules.saveFolderKey)
    }
}

/// `NSCache` needs a class, and `CGImage` is not one.
private final class CGImageBox {
    let image: CGImage?
    init(image: CGImage?) { self.image = image }
}

// MARK: - Quick Access cards

/// OneNotch's "floating overlay" Quick Access card, one per recent capture, stacked. Built like the
/// Notch surface pieces: a `SurfacePanel` prepared once and shown/hidden, never rebuilt on the hot
/// path (0.15–0.65 s per `NSHostingController`, measured in QuitProtection).
@MainActor
@Observable
final class QuickAccessController {
    static let shared = QuickAccessController()

    private(set) var items: [CaptureItem] = []
    private(set) var countdowns: [String: CardCountdown] = [:]
    private(set) var pausedPointerInside: Set<String> = []

    private var panels: [String: SurfacePanel] = [:]
    private var tickTimer: Timer?
    private var swipeMonitor: Any?

    private init() {}

    private var cardSecondsSetting: TimeInterval {
        TimeInterval(UserDefaults.standard.object(forKey: "capture.cardSeconds") as? Int ?? 10)
    }
    private var edge: CaptureCardEdge {
        CaptureCardEdge(rawValue: UserDefaults.standard.string(forKey: "capture.cardEdge") ?? "left") ?? .left
    }
    private var pauseOnHover: Bool {
        UserDefaults.standard.object(forKey: "capture.pauseOnHover") as? Bool ?? true
    }
    private var swipeDismissEnabled: Bool {
        UserDefaults.standard.object(forKey: "capture.swipeDismiss") as? Bool ?? true
    }

    func isShowing(_ item: CaptureItem) -> Bool { items.contains(item) }

    func show(_ item: CaptureItem) {
        items.removeAll { $0.id == item.id }
        items.insert(item, at: 0)
        countdowns[item.id] = CardCountdown(total: cardSecondsSetting, start: Date())
        reflow()
        armSwipeMonitorIfNeeded()
        armTickTimerIfNeeded()
    }

    func dismiss(_ item: CaptureItem) {
        items.removeAll { $0.id == item.id }
        countdowns.removeValue(forKey: item.id)
        pausedPointerInside.remove(item.id)
        panels[item.id]?.hide()
        panels.removeValue(forKey: item.id)
        reflow()
        disarmIfIdle()
    }

    func dismissAll() {
        for item in items { panels[item.id]?.hide() }
        items.removeAll()
        countdowns.removeAll()
        pausedPointerInside.removeAll()
        panels.removeAll()
        disarmIfIdle()
    }

    /// AnnotateWindowController calls this when an editor opens/closes — "Tuck Away Open Items".
    /// Re-evaluate visibility here instead of polling.
    func editorDidChange() {
        reflow()
    }

    func pointerEntered(_ item: CaptureItem) {
        guard pauseOnHover else { return }
        pausedPointerInside.insert(item.id)
        if var c = countdowns[item.id] { c.pause(at: Date()); countdowns[item.id] = c }
    }

    func pointerExited(_ item: CaptureItem) {
        pausedPointerInside.remove(item.id)
        if var c = countdowns[item.id] { c.resume(at: Date()); countdowns[item.id] = c }
    }

    private func reflow() {
        let visible = items.filter { !AnnotateWindowController.shared.isOpen($0) }
        for (index, item) in visible.enumerated() {
            let panel = panel(for: item)
            let size = CaptureRules.cardSize(pixelWidth: item.pixelWidth, pixelHeight: item.pixelHeight)
            let screen = WindowManager.screenUnderPointer()
            let frame = CaptureRules.cardFrame(visible: screen.visibleFrame, edge: edge, size: size, index: index)
            panel.setFrame(frame, display: true)
            if panel.isVisible == false { panel.orderFrontRegardless() }
        }
        let visibleIDs = Set(visible.map(\.id))
        for item in items where !visibleIDs.contains(item.id) {
            panels[item.id]?.hide()
        }
    }

    private func panel(for item: CaptureItem) -> SurfacePanel {
        if let p = panels[item.id] { return p }
        let size = CaptureRules.cardSize(pixelWidth: item.pixelWidth, pixelHeight: item.pixelHeight)
        let p = SurfacePanel(kind: .interactive, size: size)
        // A hosting VIEW subclass, not a controller: it must answer acceptsFirstMouse = true or every
        // control needs two clicks while another app is frontmost (the card is ordered front, never key).
        let host = FirstMouseHostingView(rootView: QuickAccessCardView(item: item))
        host.sizingOptions = []
        host.frame = NSRect(origin: .zero, size: size)
        host.autoresizingMask = [.width, .height]
        p.contentView = host
        panels[item.id] = p
        return p
    }

    // MARK: - Countdown ticking (one repeating timer only while something is counting)

    private func armTickTimerIfNeeded() {
        guard tickTimer == nil else { return }
        guard items.contains(where: { countdowns[$0.id]?.total ?? 0 > 0 }) else { return }
        tickTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            runOnMainActor { self?.tick() }
        }
    }

    private func tick() {
        let now = Date()
        var expired: [CaptureItem] = []
        for item in items {
            guard let c = countdowns[item.id], c.total > 0 else { continue }
            if c.isExpired(at: now) { expired.append(item) }
        }
        for item in expired { dismiss(item) }
        disarmIfIdle()
    }

    private func disarmIfIdle() {
        let anyCounting = items.contains { countdowns[$0.id]?.total ?? 0 > 0 }
        if !anyCounting {
            tickTimer?.invalidate()
            tickTimer = nil
        }
        if items.isEmpty {
            releaseSwipeMonitor()
        }
    }

    // MARK: - Two-finger swipe dismiss (local monitor only while ≥1 card is shown)

    private func armSwipeMonitorIfNeeded() {
        guard swipeDismissEnabled, swipeMonitor == nil else { return }
        swipeMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self else { return event }
            guard abs(event.scrollingDeltaX) > 12, abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) else { return event }
            let p = NSEvent.mouseLocation
            for item in self.items {
                guard let frame = self.panels[item.id]?.frame, frame.contains(p) else { continue }
                Task { @MainActor in self.dismiss(item) }
                break
            }
            return event
        }
    }

    private func releaseSwipeMonitor() {
        if let swipeMonitor { NSEvent.removeMonitor(swipeMonitor) }
        swipeMonitor = nil
    }

    func countdown(for item: CaptureItem) -> CardCountdown? { countdowns[item.id] }
}

// MARK: - Pinned images

/// "Stick on Screen": a borderless floating window holding the capture, draggable by its background,
/// scalable with a pinch or ⌘+/⌘−. Several pins can be open at once.
@MainActor
final class PinnedImageController {
    static let shared = PinnedImageController()

    private var windows: [PinnedImageWindow] = []

    private init() {}

    func pin(_ item: CaptureItem) {
        guard let src = CGImageSourceCreateWithURL(item.url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return }
        let scale: CGFloat = 2 // assume Retina source; the view clamps to screen bounds regardless
        let pointSize = NSSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
        let screen = WindowManager.screenUnderPointer().visibleFrame
        let maxSize = NSSize(width: screen.width * 0.6, height: screen.height * 0.6)
        var size = pointSize
        if size.width > maxSize.width || size.height > maxSize.height {
            let ratio = min(maxSize.width / max(size.width, 1), maxSize.height / max(size.height, 1))
            size = NSSize(width: size.width * ratio, height: size.height * ratio)
        }
        let origin = NSPoint(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2)
        let window = PinnedImageWindow(image: image, pointSize: size)
        window.setFrame(NSRect(origin: origin, size: size), display: true)
        window.orderFront(nil)
        windows.append(window)
        window.onClose = { [weak self] in
            self?.windows.removeAll { $0 === window }
        }
    }
}

/// Borderless `.floating` panel that hosts `PinnedImageView`. The window itself is movable by its
/// background, and the view handles pinch/⌘+/⌘− scaling and the hover ✕.
@MainActor
final class PinnedImageWindow: NSPanel {
    var onClose: (() -> Void)?

    init(image: CGImage, pointSize: NSSize) {
        super.init(contentRect: NSRect(origin: .zero, size: pointSize),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        level = .floating
        hasShadow = true
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let nsImage = NSImage(cgImage: image, size: pointSize)
        contentView = NSHostingView(rootView: PinnedImageView(image: nsImage, onClose: { [weak self] in
            self?.close()
        }))
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func close() {
        onClose?()
        super.close()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { close(); return } // Esc
        super.keyDown(with: event)
    }
}
