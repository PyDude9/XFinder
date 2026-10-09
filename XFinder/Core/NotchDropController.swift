import AppKit
import SwiftUI
import UniformTypeIdentifiers
import QuickLookThumbnailing

/// Khay thả — ShakePin-style drop target at the notch / top edge.
///
/// Two ways to summon it while dragging files:
/// 1. **Shake** the drag (rapid direction reversals), like ShakePin.
/// 2. **Drag into the notch area** at the top-centre of the screen.
///
/// Dropped files are staged in the shared `DropTrayStore`, so the Khay thả
/// page and this panel show the same shelf. Dragging *out* of the panel hands
/// the original file URLs to the receiving app.
///
/// Implementation notes: detection polls the pointer only while a drag is in
/// progress, so idle CPU stays 0%. It needs no permission — `NSPanel` accepts
/// the drag directly through `registerForDraggedTypes`.
@MainActor
@Observable
final class NotchDropController {
    static let shared = NotchDropController()

    private(set) var isShowing = false

    private var panel: NSPanel?
    private var detailPanel: NSPanel?
    private var monitors: [Any] = []
    /// Only armed while the tray is open — auto-close fires on the *absence*
    /// of pointer movement, which a mouse monitor alone cannot detect.
    private var closeTimer: Timer?
    /// Recent pointer samples used for shake detection.
    private var samples: [(point: CGPoint, time: Date)] = []
    private var wasDragging = false
    private var lastInsidePanel = Date.distantPast
    /// Set when the user drops files in; cleared on `hide()`. Pins the tray
    /// open so the auto-close timer cannot take it away mid-task.
    private var holdOpen = false
    /// Notch summon anchors under the notch; a shake anchors at the cursor.
    private var openedFromNotch = false
    private var clickStartedOutsideTray = false

    private init() {}

    // MARK: Settings (read at point of use)

    private var enabled: Bool {
        UserDefaults.standard.object(forKey: "dropTray.notchEnabled") as? Bool ?? true
    }
    private var shakeEnabled: Bool {
        UserDefaults.standard.object(forKey: "dropTray.shakeEnabled") as? Bool ?? true
    }
    private var notchDropEnabled: Bool {
        UserDefaults.standard.object(forKey: "dropTray.notchDropEnabled") as? Bool ?? true
    }
    /// Hover the notch to open the tray without dragging anything.
    private var hoverEnabled: Bool {
        UserDefaults.standard.object(forKey: "dropTray.hoverEnabled") as? Bool ?? true
    }
    /// Seconds the pointer may stay away before the tray closes itself.
    private var autoCloseDelay: TimeInterval {
        UserDefaults.standard.object(forKey: "dropTray.autoCloseDelay") as? Double ?? 3
    }
    /// "low" | "medium" | "high" — how many reversals a shake needs.
    private var shakeSensitivity: String {
        UserDefaults.standard.string(forKey: "dropTray.shakeSensitivity") ?? "medium"
    }
    private var reversalsNeeded: Int {
        switch shakeSensitivity {
        case "low": return 6
        case "high": return 3
        default: return 4
        }
    }

    func applySettings() {
        if enabled { start() } else { stop() }
    }

    /// Event-driven: mouse monitors fire only when the pointer actually moves
    /// or a button changes. The previous 0.05 s timer ran 20×/s forever, which
    /// showed up directly in idle CPU samples.
    private func start() {
        guard monitors.isEmpty else { return }
        let mask: NSEvent.EventTypeMask = [
            .mouseMoved, .leftMouseDragged, .leftMouseDown, .leftMouseUp
        ]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }) {
            monitors.append(global)
        }
        // A global monitor never sees events delivered to our own panel, so a
        // local one keeps the auto-close logic correct while it is focused.
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            Task { @MainActor in self?.tick() }
            return event
        }) {
            monitors.append(local)
        }
    }

    func stop() {
        for m in monitors { NSEvent.removeMonitor(m) }
        monitors.removeAll()
        closeTimer?.invalidate()
        closeTimer = nil
        hide()
    }

    // MARK: Detection

    private func tick() {
        let point = NSEvent.mouseLocation
        let dragging = NSEvent.pressedMouseButtons & 1 == 1

        guard dragging else {
            if wasDragging {
                wasDragging = false
                samples.removeAll()
            }
            // Khay KHÔNG tự biến mất: chỉ đóng bằng nút Close (DropOver-style).
            return
        }

        wasDragging = true

        samples.append((point, Date()))
        // Keep only the last ~0.6s of movement.
        let cutoff = Date().addingTimeInterval(-0.6)
        samples.removeAll { $0.time < cutoff }

        // Every open path below requires a real FILE drag. Without this an
        // ordinary click-drag could summon the tray — the reported bug.
        guard dragCarriesFiles() else { return }

        // Shake là thao tác chủ đích để gọi khay; summon ở Notch đã tạm bỏ.
        if shakeEnabled, detectShake() {
            openedFromNotch = false
            show()
        }
    }

    /// True when the drag pasteboard holds file URLs. `NSPasteboard(name:.drag)`
    /// is the public way to inspect an in-flight drag without owning it.
    private func dragCarriesFiles() -> Bool {
        let pb = NSPasteboard(name: .drag)
        guard let types = pb.types else { return false }
        return types.contains(.fileURL) || types.contains(NSPasteboard.PasteboardType("NSFilenamesPboardType"))
    }

    /// The tray is holding files the user just dropped — pin it open.
    func keepOpenAfterDrop() {
        holdOpen = true
        lastInsidePanel = Date()
    }

    /// Closes the tray a few seconds after the pointer leaves it — but ONLY
    /// while it is empty.
    ///
    /// Once the tray holds files it stays until the user dismisses it. An
    /// auto-close here is destructive to the workflow: the user drops files in
    /// order to act on them next, and having the tray disappear on a timer
    /// (reported as "khay đóng nhanh quá") loses the staging they just did.
    /// An empty tray, by contrast, is pure clutter and should still get out of
    /// the way on its own.
    private func autoCloseIfPointerLeft(_ point: CGPoint) {
        guard isShowing, let panel else { return }
        let hot = panel.frame.insetBy(dx: -24, dy: -24)
        if hot.contains(point) || isInNotchZone(point) {
            lastInsidePanel = Date()
            return
        }
        // Holding files (or explicitly pinned by a drop) ⇒ never auto-close.
        if holdOpen || !DropTrayStore.shared.items.isEmpty { return }
        if Date().timeIntervalSince(lastInsidePanel) > autoCloseDelay { hide() }
    }

    /// Top-centre strip — the notch on notched Macs, and the same spot on the
    /// rest. Uses the real notch width when macOS reports one
    /// (`safeAreaInsets.top`), so the target matches what the user sees.
    private func isInNotchZone(_ point: CGPoint) -> Bool {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) else { return false }
        let f = screen.frame
        var zoneWidth: CGFloat = 220
        var zoneHeight: CGFloat = 8
        if #available(macOS 12.0, *), screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            // Notched display: the notch is the gap between the two auxiliary
            // areas, and is as tall as the menu bar.
            zoneWidth = max(f.width - left.width - right.width, 120)
            zoneHeight = screen.safeAreaInsets.top
        }
        let zone = CGRect(x: f.midX - zoneWidth / 2,
                          y: f.maxY - zoneHeight,
                          width: zoneWidth,
                          height: zoneHeight)
        return zone.contains(point)
    }

    /// A shake is N horizontal direction reversals with enough travel.
    private func detectShake() -> Bool {
        guard samples.count >= 6 else { return false }
        var reversals = 0
        var lastSign = 0
        for i in 1..<samples.count {
            let dx = samples[i].point.x - samples[i - 1].point.x
            guard abs(dx) > 6 else { continue }
            let sign = dx > 0 ? 1 : -1
            if lastSign != 0, sign != lastSign { reversals += 1 }
            lastSign = sign
        }
        return reversals >= reversalsNeeded
    }

    // MARK: Panel

    func show() {
        guard !isShowing else { return }
        let screen = WindowManager.screenUnderPointer()
        let size = NSSize(width: 420, height: 180)
        let origin: NSPoint
        if openedFromNotch {
            // Summoned at the notch → stay there, directly under it.
            origin = NSPoint(x: screen.frame.midX - size.width / 2,
                             y: screen.frame.maxY - size.height - 4)
        } else {
            // ShakePin behaviour: the tray appears where the hand already is,
            // so the in-flight drag has the shortest possible distance to go.
            let mouse = NSEvent.mouseLocation
            origin = NSPoint(
                x: min(max(mouse.x - size.width / 2, screen.visibleFrame.minX + 8),
                       screen.visibleFrame.maxX - size.width - 8),
                y: min(max(mouse.y - size.height - 24, screen.visibleFrame.minY + 8),
                       screen.visibleFrame.maxY - size.height - 8))
        }

        let p = NSPanel(contentRect: NSRect(origin: origin, size: size),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.level = .floating
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // The tray holds files the user is about to drag somewhere, and the
        // destination window is often underneath it. A borderless panel is
        // immovable by default, which trapped the tray wherever it opened —
        // so let it be dragged by its background like a real utility window.
        p.isMovableByWindowBackground = true

        let container = DropAcceptingView(frame: NSRect(origin: .zero, size: size))
        container.autoresizingMask = [.width, .height]
        let host = NSHostingView(rootView: NotchDropView())
        host.frame = container.bounds
        host.autoresizingMask = [.width, .height]
        container.addSubview(host)
        container.registerForDraggedTypes([.fileURL])
        p.contentView = container
        p.orderFrontRegardless()
        panel = p
        isShowing = true
        lastInsidePanel = Date()
        armCloseTimer()
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
        isShowing = false
        holdOpen = false
        samples.removeAll()
        closeTimer?.invalidate()
        closeTimer = nil
        detailPanel?.orderOut(nil)
    }

    // MARK: - Cửa sổ chi tiết (DropOver-style)

    func toggleDetail() {
        if let d = detailPanel, d.isVisible {
            d.orderOut(nil)
        } else {
            showDetailPanel()
        }
    }

    private func showDetailPanel() {
        if detailPanel == nil {
            let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
                            styleMask: [.titled, .closable, .resizable],
                            backing: .buffered, defer: false)
            p.title = "Khay thả"
            p.contentView = NSHostingView(rootView: DropTrayDetailGrid())
            p.isReleasedWhenClosed = false
            detailPanel = p
        }
        detailPanel?.center()
        detailPanel?.makeKeyAndOrderFront(nil)
    }

    /// 1 s tick, alive only while the tray is open.
    private func armCloseTimer() {
        guard closeTimer == nil else { return }
        let t = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isShowing else { return }
                self.autoCloseIfPointerLeft(NSEvent.mouseLocation)
            }
        }
        RunLoop.main.add(t, forMode: .common)
        closeTimer = t
    }
}

/// Drop handling lives on the *view*, not the window — `NSWindow` has no
/// `performDragOperation`. This view hosts the SwiftUI content and accepts the
/// file drag on its behalf.
/// Drags every staged file at once.
///
/// SwiftUI `.onDrag` returns a single `NSItemProvider`, so the deck could only
/// ever hand over one file — the rest were silently dropped. AppKit's
/// `beginDraggingSession(with:)` takes an array of dragging items, which is
/// what "drag the whole tray into a window" actually needs.
private struct MultiFileDragSource: NSViewRepresentable {
    let paths: [String]

    func makeNSView(context: Context) -> DragSourceView {
        let v = DragSourceView()
        v.paths = paths
        return v
    }

    func updateNSView(_ nsView: DragSourceView, context: Context) {
        nsView.paths = paths
    }

    final class DragSourceView: NSView {
        var paths: [String] = []

        override func mouseDown(with event: NSEvent) {
            guard !paths.isEmpty else { return super.mouseDown(with: event) }

            let items: [NSDraggingItem] = paths.compactMap { path in
                let url = URL(fileURLWithPath: path) as NSURL
                let item = NSDraggingItem(pasteboardWriter: url)
                let icon = NSWorkspace.shared.icon(forFile: path)
                // Every item needs a frame + image or the session shows nothing.
                item.setDraggingFrame(NSRect(x: 0, y: 0, width: 48, height: 48),
                                      contents: icon)
                return item
            }
            guard !items.isEmpty else { return }
            beginDraggingSession(with: items, event: event, source: self)
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }
}

extension MultiFileDragSource.DragSourceView: NSDraggingSource {
    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        // `.copy` outside the app: the tray keeps its files, matching the
        // "Kéo ra sẽ sao chép file và giữ các mục trong khay" contract.
        [.copy]
    }
}

private final class DropAcceptingView: NSView {
    /// Height of the header strip that acts as the window's drag handle.
    /// Matches the title row in `NotchDropView`.
    static let dragHandleHeight: CGFloat = 34

    /// Move the tray ONLY when the press starts on the header strip.
    ///
    /// The previous version forwarded *every* mouse-down to
    /// `window.performDrag`, which swallowed the press before SwiftUI's
    /// `.onDrag` could begin — so files could never be dragged OUT of the
    /// tray, the exact bug reported. A window drag and a file drag both start
    /// with a mouse-down, so they must be separated by where the press lands:
    /// header ⇒ move the window, anywhere else ⇒ let the file tiles have it.
    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        // `bounds` is bottom-left origin, so the header is the TOP strip.
        let headerStrip = NSRect(x: 0, y: bounds.maxY - Self.dragHandleHeight,
                                 width: bounds.width, height: Self.dragHandleHeight)
        if headerStrip.contains(p) {
            window?.performDrag(with: event)
        } else {
            super.mouseDown(with: event)
        }
    }

    /// Let a click reach the tray without first activating the panel — the
    /// tray is non-activating on purpose so the previous app keeps focus.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = sender.draggingPasteboard
            .readObjects(forClasses: [NSURL.self], options: nil) as? [URL] ?? []
        guard !urls.isEmpty else { return false }
        Task { @MainActor in
            DropTrayStore.shared.add(urls: urls)
            ClipboardSounds.playCopy()
            // Deliberately does NOT hide. Dropping a file is the *start* of the
            // user's task (they then drag it out, ZIP it, or add more), not the
            // end — closing here threw the tray away mid-workflow. It stays up
            // until the user dismisses it; see `autoCloseIfPointerLeft`.
            NotchDropController.shared.keepOpenAfterDrop()
        }
        return true
    }
}

/// One staged file. Shows a real QuickLook thumbnail (the actual image /
/// first PDF page / document preview) rather than a generic type icon, so a
/// shelf of "Screenshot 1, Screenshot 2" is still tellable apart at a glance.
private struct TrayFileTile: View {
    let item: DropTrayStore.Item
    let url: URL
    let onRemove: () -> Void

    @State private var thumb: NSImage?

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(0.05))
                if let thumb {
                    Image(nsImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: item.path))
                        .resizable().frame(width: 30, height: 30)
                }
            }
            .frame(width: 62, height: 62)

            Text(item.name)
                .font(.system(size: 9))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 66)
        }
        .padding(5)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
        .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
        .contextMenu {
            Button(L10n.t("Hiện trong Finder")) {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
            Button(L10n.t("Mở")) { NSWorkspace.shared.open(url) }
            Divider()
            Button("Bỏ khỏi khay", action: onRemove)
        }
        .help(item.path)
        .task { thumb = await FileThumbnailer.thumbnail(for: url) }
    }
}

/// QuickLook thumbnails, off the main thread. `QLThumbnailGenerator` renders
/// the real content (image, PDF page, document) and falls back to the file's
/// type icon when a format has no previewer.
enum FileThumbnailer {
    static func thumbnail(for url: URL) async -> NSImage? {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: 120, height: 120),
            scale: scale,
            representationTypes: .all)
        return await withCheckedContinuation { continuation in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { rep, _ in
                continuation.resume(returning: rep?.nsImage)
            }
        }
    }
}

/// Contents of the floating tray: staged items, drag-out support, quick clear.
private struct NotchDropView: View {
    @State private var store = DropTrayStore.shared

    /// Overlapping deck + a count badge; click to fan the files out. Dragging
    /// the deck hands over EVERY held file at once, which is the whole point
    /// of staging them together.
    private var stackedDeck: some View {
        HStack(spacing: 14) {
            ZStack {
                ForEach(Array(store.items.prefix(4).enumerated().reversed()), id: \.element.id) { index, item in
                    Image(nsImage: NSWorkspace.shared.icon(forFile: item.path))
                        .resizable()
                        .frame(width: 46, height: 46)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
                        .rotationEffect(.degrees(Double(index) * -4))
                        .offset(x: CGFloat(index) * 7, y: CGFloat(index) * -3)
                        .shadow(color: .black.opacity(0.18), radius: 3, x: 0, y: 1)
                }
            }
            .frame(width: 78, height: 62)
            // SwiftUI's `.onDrag` can only vend ONE provider, and there is no
            // multi-item variant on macOS 14 (`.itemProviders` does not exist
            // here). For the whole stack, hand off through an AppKit drag
            // session instead, which does support several items.
            .overlay(MultiFileDragSource(paths: store.items.map(\.path)))

            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.t("\(store.items.count) tệp đang giữ"))
                    .font(.system(size: 12, weight: .semibold))
                Text(L10n.t("Kéo cả chồng ra để dùng một lần."))
                    .font(.system(size: 10)).foregroundColor(.secondary)
                HStack(spacing: 8) {
                    Button(L10n.t("Xem chi tiết")) { NotchDropController.shared.toggleDetail() }
                        .buttonStyle(.bordered).controlSize(.mini)
                    Button(L10n.t("Xóa hết")) { store.removePaths(store.items.map(\.path)) }
                        .buttonStyle(.plain)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
        }
        .contentShape(Rectangle())
        .frame(maxHeight: .infinity)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "tray.and.arrow.down.fill").foregroundColor(.accentColor)
                Text(L10n.t("Khay thả")).font(.system(size: 13, weight: .semibold))
                Text("\(store.items.count)").font(.system(size: 11)).foregroundColor(.secondary)
                Spacer()
                Button {
                    NotchDropController.shared.hide()
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            if store.items.isEmpty {
                VStack(spacing: 4) {
                    Image(systemName: "arrow.down.doc").font(.system(size: 22)).foregroundColor(.secondary)
                    Text(L10n.t("Thả file vào đây để giữ tạm"))
                        .font(.system(size: 11)).foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // DropOver-style: luôn stack gọn; chi tiết từng file mở ở cửa sổ
                // riêng (nút "Xem chi tiết") nên hàng nghìn file vẫn mượt.
                stackedDeck
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(VisualEffectBackground())
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
    }
}

/// Cửa sổ chi tiết của Khay thả — lưới thẻ từng file (kéo riêng từng file ra).
/// Cắt bớt khi quá nhiều để không vẽ hàng nghìn ô cùng lúc.
private struct DropTrayDetailGrid: View {
    @State private var store = DropTrayStore.shared
    private let cap = 400

    private let columns = [GridItem(.adaptive(minimum: 110, maximum: 160), spacing: 10)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(store.items.prefix(cap)) { item in
                    TrayFileTile(item: item, url: URL(fileURLWithPath: item.path)) {
                        store.remove(item)
                    }
                }
            }
            .padding(12)
        }
        .frame(minWidth: 480, minHeight: 360)
        .overlay(alignment: .bottom) {
            if store.items.count > cap {
                Text(L10n.t("Hiện \(cap)/\(store.items.count) mục — kéo cả chồng ở khay để thao tác cả lô."))
                    .font(.system(size: 11)).foregroundColor(.secondary)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                    .background(Color(.controlBackgroundColor).opacity(0.9))
            }
        }
    }
}
