import AppKit
import SwiftUI
import ScreenCaptureKit
import ImageIO

/// XF-T26 — scrolling capture: pick an area, scroll (by hand or automatically), and get ONE long image through the normal
/// capture pipeline. Decisions (what moved, which rows to keep) are `ScrollStitch`; this file captures, scrolls, draws the
/// session's frame and bar, writes the strips and hands the final file to `CaptureController.finishCapture`.
@MainActor
final class ScrollCaptureController {
    static let shared = ScrollCaptureController()
    private init() {}

    /// The session bar's state (SwiftUI reads it).
    @MainActor @Observable final class Model {
        var heightPx = 0
        var message: String?
        var auto = false
        var canAuto = true
        var finishing = false
    }

    private enum Phase { case idle, selecting, capturing }
    private var phase = Phase.idle
    private var selector: ScrollAreaSelector?
    private var session: Session?

    var isActive: Bool { phase != .idle }

    func start() {
        guard phase == .idle else { return }
        guard CGPreflightScreenCaptureAccess() else {
            _ = CGRequestScreenCaptureAccess()
            ScrollCaptureController.toast.show(symbol: "exclamationmark.triangle.fill", title: L10n.t("Cần quyền Ghi màn hình để chụp ảnh."),
                                               detail: L10n.t("Cấp quyền trong Tính năng & Quyền rồi thử lại."), duration: 3.0)
            return
        }
        phase = .selecting
        let selector = ScrollAreaSelector { [weak self] result in
            guard let self else { return }
            self.selector = nil
            guard let (rect, screen) = result else { self.phase = .idle; return }
            self.begin(rect: rect, screen: screen)
        }
        self.selector = selector
        selector.show()
    }

    private func begin(rect: CGRect, screen: NSScreen) {
        phase = .capturing
        SmoothScrollController.shared.setCapturePaused(true)
        let session = Session(rect: rect, screen: screen) { [weak self] in
            self?.session = nil
            self?.phase = .idle
            SmoothScrollController.shared.setCapturePaused(false)
        }
        self.session = session
        session.run()
    }

    static let toast = ToastSurface(style: .toast)

    /// At launch: strips of a session that never ended (a crash, a force quit) are screen content — remove them. No
    /// session can be running in a process that just started.
    nonisolated static func sweepLeftovers() {
        let tmp = FileManager.default.temporaryDirectory
        for url in (try? FileManager.default.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil)) ?? []
        where url.lastPathComponent.hasPrefix(folderPrefix) {
            try? FileManager.default.removeItem(at: url)
        }
    }
    nonisolated static let folderPrefix = "xfinder-scroll-"
}

// MARK: - Area selection

/// A dim layer over the screen under the pointer: drag a rectangle, Esc cancels. The rect is returned in global AppKit
/// coordinates (bottom-left origin) with its screen.
@MainActor
final class ScrollAreaSelector {
    private let panel: KeyablePanel
    private let screen: NSScreen
    private let done: (((CGRect, NSScreen))?) -> Void
    private var finished = false

    init(done: @escaping (((CGRect, NSScreen))?) -> Void) {
        let screen = WindowManager.screenUnderPointer()
        self.screen = screen
        self.done = done
        panel = KeyablePanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .screenSaver
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let view = SelectionView(frame: CGRect(origin: .zero, size: screen.frame.size))
        view.onFinish = { [weak self] rect in self?.finish(rect) }
        panel.contentView = view
    }

    func show() {
        panel.setFrame(screen.frame, display: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(panel.contentView)
        NSCursor.crosshair.push()
    }

    private func finish(_ local: CGRect?) {
        guard !finished else { return }
        if let local, !ScrollStitch.isLargeEnough(width: local.width, height: local.height) {
            (panel.contentView as? SelectionView)?.hint = L10n.t("Chọn vùng ít nhất 48 × 48 điểm.")
            return
        }
        finished = true
        NSCursor.pop()
        panel.orderOut(nil)
        done(local.map { (CGRect(x: $0.minX + screen.frame.minX, y: $0.minY + screen.frame.minY, width: $0.width, height: $0.height), screen) })
    }

    final class SelectionView: NSView {
        var onFinish: ((CGRect?) -> Void)?
        var hint: String? { didSet { needsDisplay = true } }
        private var start: CGPoint?
        private var current: CGPoint?

        override var acceptsFirstResponder: Bool { true }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        private var selection: CGRect? {
            guard let start, let current else { return nil }
            return CGRect(x: min(start.x, current.x), y: min(start.y, current.y),
                          width: abs(current.x - start.x), height: abs(current.y - start.y)).integral
        }

        override func draw(_ dirtyRect: NSRect) {
            NSColor.black.withAlphaComponent(0.28).setFill()
            bounds.fill()
            if let r = selection {
                NSColor.clear.setFill()
                r.fill(using: .copy)
                NSColor.white.setStroke()
                let path = NSBezierPath(rect: r.insetBy(dx: -0.5, dy: -0.5)); path.lineWidth = 1; path.stroke()
                let label = "\(Int(r.width)) × \(Int(r.height))" as NSString
                label.draw(at: CGPoint(x: r.minX, y: r.maxY + 4),
                           withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium), .foregroundColor: NSColor.white])
            }
            let text = (hint ?? L10n.t("Kéo để chọn vùng sẽ cuộn · Esc để huỷ")) as NSString
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: NSColor.white]
            let size = text.size(withAttributes: attrs)
            text.draw(at: CGPoint(x: bounds.midX - size.width / 2, y: bounds.maxY - 80), withAttributes: attrs)
        }

        override func mouseDown(with event: NSEvent) {
            start = convert(event.locationInWindow, from: nil); current = start; hint = nil; needsDisplay = true
        }
        override func mouseDragged(with event: NSEvent) {
            current = convert(event.locationInWindow, from: nil); needsDisplay = true
        }
        override func mouseUp(with event: NSEvent) {
            current = convert(event.locationInWindow, from: nil)
            let r = selection
            start = nil; current = nil; needsDisplay = true
            onFinish?(r)
        }
        override func keyDown(with event: NSEvent) {
            if event.keyCode == 53 { onFinish?(nil) } else { super.keyDown(with: event) }   // Esc
        }
        override func cancelOperation(_ sender: Any?) { onFinish?(nil) }
    }
}

// MARK: - Capturing the area

/// 8-bit RGBA pixels of one capture — Sendable, so ScreenCaptureKit's work stays off the main actor.
struct ScrollBitmap: Sendable {
    var width: Int
    var height: Int
    var bytesPerRow: Int
    var pixels: [UInt8]

    /// A copy of some rows (a strip).
    func rows(_ range: Range<Int>) -> ScrollBitmap {
        let r = range.clamped(to: 0..<height)
        return ScrollBitmap(width: width, height: r.count, bytesPerRow: bytesPerRow,
                            pixels: Array(pixels[(r.lowerBound * bytesPerRow)..<(r.upperBound * bytesPerRow)]))
    }

    func cgImage() -> CGImage? {
        guard height > 0, let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}

/// Owns the ScreenCaptureKit filter for one session (its types never leave this actor).
actor ScrollShooter {
    private var filter: SCContentFilter?

    func prepare(displayID: CGDirectDisplayID, excluding windowNumbers: [Int]) async -> Bool {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true),
              let display = content.displays.first(where: { $0.displayID == displayID }) else { return false }
        let excluded = content.windows.filter { w in windowNumbers.contains(Int(w.windowID)) }
        filter = SCContentFilter(display: display, excludingWindows: excluded)
        return true
    }

    /// Capture until two consecutive captures are identical (the page stopped moving) or `seconds` passed.
    func settled(rect: CGRect, scale: CGFloat, within seconds: Double) async -> ScrollBitmap? {
        var previous = await shot(rect: rect, scale: scale)
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            try? await Task.sleep(nanoseconds: 90_000_000)
            guard let next = await shot(rect: rect, scale: scale) else { break }
            if let p = previous, p.pixels == next.pixels { return next }
            previous = next
        }
        return previous
    }

    /// `rect` in the display's own points, top-left origin.
    func shot(rect: CGRect, scale: CGFloat) async -> ScrollBitmap? {
        guard let filter else { return nil }
        let config = SCStreamConfiguration()
        config.sourceRect = rect
        config.width = Int((rect.width * scale).rounded())
        config.height = Int((rect.height * scale).rounded())
        config.showsCursor = false
        config.capturesAudio = false
        // sRGB BGRA straight from ScreenCaptureKit, copied byte for byte — never drawn (ScrollStitch.rgba: drawing left a
        // 10 MB converted copy per capture in CoreGraphics' caches).
        config.colorSpaceName = CGColorSpace.sRGB
        config.pixelFormat = kCVPixelFormatType_32BGRA
        guard let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config),
              image.bitsPerPixel == 32, image.bitmapInfo.contains(.byteOrder32Little),     // B, G, R, A in memory
              let data = image.dataProvider?.data, let base = CFDataGetBytePtr(data) else { return nil }
        let w = image.width, h = image.height
        let pixels = ScrollStitch.rgba(fromBGRA: UnsafeRawBufferPointer(start: base, count: CFDataGetLength(data)),
                                       width: w, height: h, bytesPerRow: image.bytesPerRow)
        return pixels.map { ScrollBitmap(width: w, height: h, bytesPerRow: w * 4, pixels: $0) }
    }
}

// MARK: - The session

@MainActor
private final class Session {
    let rect: CGRect            // global AppKit points
    let screen: NSScreen
    let onEnd: () -> Void
    let model = ScrollCaptureController.Model()
    private let shooter = ScrollShooter()
    private let border: NSPanel
    private let bar: NSPanel
    private var keyMonitors: [Any] = []
    private var loop: Task<Void, Never>?
    private let folder: URL
    private var strips: [URL] = []
    private var writes: [Task<Void, Never>] = []
    private var last: (bitmap: ScrollBitmap, frame: ScrollStitch.Frame)?
    private var assembly: ScrollStitch.Assembly?
    private var pendingBody: ScrollBitmap?
    private var footer: ScrollBitmap?
    private var ended = false

    init(rect: CGRect, screen: NSScreen, onEnd: @escaping () -> Void) {
        self.rect = rect; self.screen = screen; self.onEnd = onEnd
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(ScrollCaptureController.folderPrefix + UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        // A thin frame just OUTSIDE the area, click-through, excluded from the captures.
        border = NSPanel(contentRect: rect.insetBy(dx: -3, dy: -3), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        border.level = .statusBar
        border.isOpaque = false
        border.backgroundColor = .clear
        border.hasShadow = false
        border.ignoresMouseEvents = true
        border.animationBehavior = .none
        border.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        border.contentView = BorderView()

        let barSize = CGSize(width: 440, height: 52)
        var origin = CGPoint(x: rect.midX - barSize.width / 2, y: rect.minY - barSize.height - 10)
        if origin.y < screen.visibleFrame.minY { origin.y = rect.maxY + 10 }
        if origin.y + barSize.height > screen.visibleFrame.maxY { origin.y = rect.minY + 10 }   // tall area: inside, at the bottom
        origin.x = min(max(origin.x, screen.visibleFrame.minX + 8), screen.visibleFrame.maxX - barSize.width - 8)
        bar = NSPanel(contentRect: CGRect(origin: origin, size: barSize), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        bar.level = .statusBar
        bar.isOpaque = false
        bar.backgroundColor = .clear
        bar.hasShadow = true
        bar.animationBehavior = .none
        bar.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        model.canAuto = AXIsProcessTrusted()
    }

    func run() {
        let host = NSHostingView(rootView: ScrollCaptureBar(model: model,
            onAuto: { [weak self] in self?.toggleAuto() },
            onDone: { [weak self] in self?.finish() },
            onCancel: { [weak self] in self?.cancel() }))
        host.sizingOptions = []
        bar.contentView = host
        border.orderFrontRegardless()
        bar.orderFrontRegardless()
        // Enter = done, Esc = cancel — while the person scrolls in another app (global) or clicks the bar (local).
        let handle: (NSEvent) -> Bool = { [weak self] e in
            guard let self else { return false }
            switch e.keyCode {
            case 36, 76: self.finish(); return true
            case 53: self.cancel(); return true
            default: return false
            }
        }
        if let g = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { e in MainActor.assumeIsolated { _ = handle(e) } }) {
            keyMonitors.append(g)
        }
        if let l = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { e in handle(e) ? nil : e }) {
            keyMonitors.append(l)
        }
        let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? CGMainDisplayID()
        let windows = [border.windowNumber, bar.windowNumber]
        loop = Task { [weak self] in
            guard let self else { return }
            guard await self.shooter.prepare(displayID: displayID, excluding: windows) else {
                // Clean up exactly like a cancel: smooth scrolling resumes, the key monitors and panels go away.
                ScrollCaptureController.toast.show(symbol: "exclamationmark.triangle.fill", title: L10n.t("Không chụp được vùng này."), duration: 3.0)
                self.cancel()
                return
            }
            await self.captureLoop()
        }
    }

    /// The area in the display's own points, top-left origin (what ScreenCaptureKit wants).
    private var displayRect: CGRect {
        CGRect(x: rect.minX - screen.frame.minX, y: screen.frame.maxY - rect.maxY, width: rect.width, height: rect.height)
    }

    private func shoot() async -> ScrollBitmap? { await shooter.shot(rect: displayRect, scale: screen.backingScaleFactor) }

    // MARK: Loop

    private func captureLoop() async {
        // The top of the area first, before any automatic scroll can move it away.
        if let first = await shoot() { take(first) }
        var unchangedScrolls = 0
        while !ended, !Task.isCancelled {
            if model.auto {
                scrollOnce()
                try? await Task.sleep(nanoseconds: 180_000_000)
                guard let bitmap = await settledShot() else { continue }
                switch take(bitmap) {
                case .same:
                    unchangedScrolls += 1
                    if unchangedScrolls >= ScrollStitch.unchangedScrollsToStop {
                        model.message = L10n.t("Đã đến cuối trang.")
                        finish(); return
                    }
                case .moved: unchangedScrolls = 0
                case .lost: model.auto = false; unchangedScrolls = 0
                }
            } else {
                unchangedScrolls = 0
                if let bitmap = await shoot() { _ = take(bitmap) }
                try? await Task.sleep(nanoseconds: 120_000_000)
            }
            if let assembly, assembly.height >= ScrollStitch.heightLimit {
                model.message = L10n.t("Đã đến giới hạn chiều cao.")
                finish(); return
            }
        }
    }

    /// After an automatic scroll: wait until two captures agree (the page stopped moving) or 600 ms passed. The
    /// multi-megabyte comparison runs in the shooter actor, not on the main actor.
    private func settledShot() async -> ScrollBitmap? {
        await shooter.settled(rect: displayRect, scale: screen.backingScaleFactor, within: 0.6)
    }

    /// Feed one capture to the stitcher; returns what happened.
    @discardableResult
    private func take(_ bitmap: ScrollBitmap) -> ScrollStitch.Outcome {
        let frame = ScrollStitch.frame(pixels: bitmap.pixels, width: bitmap.width, height: bitmap.height, bytesPerRow: bitmap.bytesPerRow)
        guard let previous = last, var assembly else {
            last = (bitmap, frame)
            assembly = ScrollStitch.Assembly(first: frame)
            pendingBody = bitmap
            model.heightPx = bitmap.height
            return .moved(ScrollStitch.Match(shift: 0, top: 0, bottom: 0))
        }
        let outcome = ScrollStitch.compare(previous.frame, frame)
        switch outcome {
        case .same:
            break
        case .lost:
            model.message = L10n.t("Không ghép được đoạn mới — cuộn ngược lên một chút.")
        case .moved(let match):
            let step = assembly.add(match, frameHeight: frame.height)
            self.assembly = assembly
            apply(step, from: bitmap)
            last = (bitmap, frame)
            model.heightPx = assembly.height
            model.message = nil
        }
        return outcome
    }

    /// Drop the old footer, flush the previous body strip to disk, keep the new body and footer in memory.
    private func apply(_ step: ScrollStitch.Step, from bitmap: ScrollBitmap) {
        var drop = step.dropFooter
        if let f = footer { drop -= f.height; footer = nil }
        if var body = pendingBody {
            if drop > 0 { body = body.rows(0..<max(0, body.height - drop)) }
            write(body)
        }
        pendingBody = step.append.isEmpty ? nil : bitmap.rows(step.append)
        footer = step.footer.isEmpty ? nil : bitmap.rows(step.footer)
    }

    private func write(_ strip: ScrollBitmap) {
        guard strip.height > 0 else { return }
        let url = folder.appendingPathComponent(String(format: "strip-%05d.png", strips.count))
        strips.append(url)
        let scale = screen.backingScaleFactor
        writes.append(Task.detached(priority: .utility) { _ = ScrollStitch.writePNG(strip.cgImage(), to: url, scale: Double(scale)) })
    }

    // MARK: Automatic scrolling

    private func toggleAuto() {
        guard model.canAuto else { return }
        model.auto.toggle()
        model.message = nil
    }

    /// One step down the page: pixel scroll events at the middle of the area, tagged as our own. Measured 2026-10-23 with
    /// a probe whose positive control passed (pointer warped onto the window: moved 240 pt): a session-tap event with
    /// `.location` set scrolls the window at that location while the pointer is elsewhere (moved 240 pt), whereas
    /// `postToPid` to the window's process moved it 0 pt. The pointer is never moved.
    private func scrollOnce() {
        let pinned = Double((assembly?.footer ?? 0)) / screen.backingScaleFactor
        let step = ScrollStitch.autoScrollStep(areaHeightPoints: rect.height, pinnedPoints: pinned)
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY
        let location = CGPoint(x: rect.midX, y: primaryTop - rect.midY)     // Quartz: top-left origin
        let pieces = 6
        for _ in 0..<pieces {
            guard let e = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
                                  wheel1: Int32(-(step / Double(pieces)).rounded()), wheel2: 0, wheel3: 0) else { continue }
            e.location = location
            e.setIntegerValueField(.eventSourceUserData, value: ScrollStitch.autoScrollTag)
            e.post(tap: .cgSessionEventTap)
        }
    }

    // MARK: End

    private func finish() {
        guard !ended else { return }
        ended = true
        loop?.cancel()
        model.finishing = true
        if let body = pendingBody { write(body) }
        if let f = footer { write(f) }
        pendingBody = nil; footer = nil
        let strips = self.strips, writes = self.writes, folder = self.folder, scale = Double(screen.backingScaleFactor)
        Task { [weak self] in
            for w in writes { await w.value }
            let out = folder.appendingPathComponent("scroll-capture.png")
            let ok = await Task.detached(priority: .userInitiated) { ScrollStitch.composeInChild(strips: strips, output: out, scale: scale) }.value
            self?.tearDown()
            if ok {
                CaptureController.shared.finishCapture(mode: .scrolling, tempURL: out)
            } else {
                ScrollCaptureController.toast.show(symbol: "exclamationmark.triangle.fill", title: L10n.t("Không ghép được ảnh chụp cuộn."), duration: 3.0)
            }
            try? FileManager.default.removeItem(at: folder)
        }
    }

    private func cancel() {
        guard !ended else { return }
        ended = true
        loop?.cancel()
        tearDown()
        let folder = self.folder, writes = self.writes
        Task.detached { for w in writes { await w.value }; try? FileManager.default.removeItem(at: folder) }
    }

    private func tearDown() {
        for m in keyMonitors { NSEvent.removeMonitor(m) }
        keyMonitors = []
        border.orderOut(nil)
        bar.orderOut(nil)
        onEnd()
    }

    final class BorderView: NSView {
        override func draw(_ dirtyRect: NSRect) {
            NSColor.controlAccentColor.setStroke()
            let path = NSBezierPath(rect: bounds.insetBy(dx: 1.5, dy: 1.5))
            path.lineWidth = 2
            path.setLineDash([6, 4], count: 2, phase: 0)
            path.stroke()
        }
    }
}

// MARK: - The bar

private struct ScrollCaptureBar: View {
    let model: ScrollCaptureController.Model
    let onAuto: () -> Void
    let onDone: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: XFinderTokens.Space.inline) {
            Image(systemName: "rectangle.expand.vertical").foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(model.finishing ? L10n.t("Đang ghép ảnh…") : L10n.t("Cuộn trong vùng để chụp tiếp"))
                    .font(XFinderTokens.Font.row).lineLimit(1)
                Text(model.message ?? "\(model.heightPx) px · \(L10n.t("Enter: xong · Esc: huỷ"))")
                    .font(XFinderTokens.Font.caption).foregroundColor(.secondary).lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            Button(model.auto ? L10n.t("Dừng tự cuộn") : L10n.t("Tự cuộn"), action: onAuto)
                .disabled(!model.canAuto || model.finishing)
                .help(model.canAuto ? L10n.t("XFinder tự cuộn xuống tới cuối trang.") : L10n.t("Cần quyền Trợ năng để tự cuộn."))
            Button(L10n.t("Xong"), action: onDone).keyboardShortcut(.defaultAction).disabled(model.finishing)
            Button(L10n.t("Huỷ"), action: onCancel).disabled(model.finishing)
        }
        .controlSize(.small)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.regularMaterial))
    }
}
