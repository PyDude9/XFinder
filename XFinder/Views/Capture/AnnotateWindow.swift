import AppKit
import SwiftUI
import ImageIO
import UniformTypeIdentifiers

/// F4 editor window — one per open `CaptureItem`, built by `AnnotateWindowController`. Toolbar
/// across the top (wireframe A, like Preview/Skitch): tools, colour, stroke width, undo/redo, a
/// drag handle, Lưu…, and a primary "Sao chép" that copies the rendered result and closes the
/// window (OneNotch's "Copy & Close"). The canvas and its gestures live in `AnnotateCanvas.swift`;
/// this file only owns the window chrome and the document/undo plumbing that the toolbar drives.
///
/// `NSApp.activate()` is fine here — unlike the Quick Access card (which must never steal focus
/// from whatever app the user is in), this is a real, user-opened document window.
@MainActor
final class AnnotateWindowController: NSWindowController, NSWindowDelegate {
    static let shared = AnnotateWindowController()

    private var windows: [String: NSWindow] = [:]   // keyed by CaptureItem.id (= file path)

    private override init(window: NSWindow?) { super.init(window: window) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// OneNotch "Tuck Away Open Items": a Quick Access card hides while its editor is open.
    func isOpen(_ item: CaptureItem) -> Bool { windows[item.id] != nil }

    func open(_ item: CaptureItem) {
        if let existing = windows[item.id] {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        guard let model = AnnotateDocumentModel(item: item) else { return }

        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 860, height: 620),
                            styleMask: [.titled, .closable, .resizable, .miniaturizable],
                            backing: .buffered, defer: false)
        win.minSize = NSSize(width: 640, height: 420)
        win.title = "\(L10n.t("Ảnh chụp "))\(model.titleDay)\(L10n.t(" lúc "))\(model.titleTime)"
        win.isReleasedWhenClosed = false
        win.delegate = self
        win.contentView = NSHostingView(rootView: AnnotateRootView(model: model))
        win.center()
        // Centre on the screen under the pointer rather than always the main screen.
        let screen = WindowManager.screenUnderPointer()
        let f = win.frame
        let x = screen.visibleFrame.midX - f.width / 2
        let y = screen.visibleFrame.midY - f.height / 2
        win.setFrameOrigin(NSPoint(x: x, y: y))

        windows[item.id] = win
        model.onClose = { [weak self, weak win, weak model] in
            guard let self, let win else { return }
            model?.releaseKeyMonitor()
            self.windows.removeValue(forKey: item.id)
            win.delegate = nil
            win.close()
            QuickAccessController.shared.editorDidChange()
        }

        win.makeKeyAndOrderFront(nil)
        NSApp.activate()
        QuickAccessController.shared.editorDidChange()
    }

    nonisolated func windowWillClose(_ notification: Notification) {
        // Only a Sendable identity crosses the hop; the window itself is found again on the main actor.
        guard let closing = notification.object as? NSWindow else { return }
        let id = ObjectIdentifier(closing)
        runOnMainActor { [weak self] in
            guard let self else { return }
            if let entry = self.windows.first(where: { ObjectIdentifier($0.value) == id }) {
                if let hosting = entry.value.contentView as? NSHostingView<AnnotateRootView> {
                    hosting.rootView.model.releaseKeyMonitor()
                }
                self.windows.removeValue(forKey: entry.key)
            }
            QuickAccessController.shared.editorDidChange()
        }
    }
}

/// Loads the base image once, tracks the pixel→point scale (DPI-derived, per contract), and owns
/// the undo stack + keyboard handling for one editor window.
@MainActor
@Observable
final class AnnotateDocumentModel {
    let item: CaptureItem
    let baseImage: CGImage
    private(set) var undo: UndoStack<AnnotationDocument>
    var selection: UUID?
    var activeTool: AnnotationTool = .select
    var editingText: UUID?          // mark id currently showing an inline TextField, or nil

    @ObservationIgnored var onCopy: (() -> Void)?
    @ObservationIgnored var onClose: (() -> Void)?

    var document: AnnotationDocument { undo.current }
    let titleDay: String
    let titleTime: String

    @ObservationIgnored private var keyMonitor: Any?

    init?(item: CaptureItem) {
        guard let src = CGImageSourceCreateWithURL(item.url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        self.item = item
        self.baseImage = image

        // Scale = pixels per point, derived from the PNG's own DPI (screencapture writes 144 on
        // Retina, 72 otherwise) rather than guessing from pixel dimensions alone.
        var dpi: CGFloat = 72
        if let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
           let dpiWidth = props[kCGImagePropertyDPIWidth] as? CGFloat, dpiWidth > 0 {
            dpi = dpiWidth
        }
        let scale: CGFloat = dpi >= 144 ? 2 : 1
        self.undo = UndoStack(AnnotationDocument(pixelSize: CGSize(width: image.width, height: image.height), scale: scale))

        let parts = CaptureRules.titleParts(date: item.date)
        self.titleDay = parts.day
        self.titleTime = parts.time
    }

    // MARK: - Document mutation (every call pushes a new undo snapshot)

    func commit(_ next: AnnotationDocument) { undo.push(next) }

    func performUndo() { undo.undo(); selection = nil }
    func performRedo() { undo.redo(); selection = nil }

    func deleteSelection() {
        guard let id = selection else { return }
        var doc = document
        doc.remove(id: id)
        commit(doc)
        selection = nil
    }

    func setCrop(_ rect: CGRect?) {
        var doc = document
        doc.crop = rect
        commit(doc)
    }

    // MARK: - Keyboard

    /// Local monitor scoped to this window being key; removed when the window closes. Tool letters,
    /// Delete, Esc, Return, ⌘Z/⇧⌘Z/⌘C/⌘S are handled here; a focused TextField (inline text editing)
    /// must see its own keystrokes, so everything is skipped while `editingText != nil`.
    func armKeyMonitor(for window: NSWindow) {
        releaseKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak window] event in
            guard let self, let window, event.window === window else { return event }
            if self.editingText != nil { return event }
            return self.handleKeyDown(event) ? nil : event
        }
    }

    func releaseKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    /// Returns true when the event was consumed.
    private func handleKeyDown(_ event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection([.command, .shift, .option, .control])
        switch event.keyCode {
        case 51, 117: // Delete / Forward Delete
            if selection != nil { deleteSelection(); return true }
            return false
        case 53: // Esc
            if selection != nil { selection = nil; return true }
            onClose?()
            return true
        case 36: // Return
            copyAndClose()
            return true
        case 6 where mods == .command: // Z
            performUndo(); return true
        case 6 where mods == [.command, .shift]: // ⇧⌘Z
            performRedo(); return true
        case 8 where mods == .command: // C
            copyAndClose(); return true
        case 1 where mods == .command: // S
            saveViaPanel(); return true
        default:
            break
        }
        guard mods.isEmpty, let chars = event.charactersIgnoringModifiers?.uppercased(), chars.count == 1 else { return false }
        if let tool = AnnotationTool.allCases.first(where: { $0.keyEquivalent == chars }) {
            activeTool = tool
            return true
        }
        return false
    }

    // MARK: - Export actions (toolbar + Return + ⌘C + ⌘S)

    func copyAndClose() {
        guard let image = AnnotationRenderer.render(base: baseImage, document: document) else { onClose?(); return }
        CaptureController.shared.copyImage(image, scale: document.scale)
        onCopy?()
    }

    @discardableResult
    func saveViaPanel() -> URL? {
        guard let image = AnnotationRenderer.render(base: baseImage, document: document) else { return nil }
        let name = (item.url.lastPathComponent as NSString).deletingPathExtension
        return CaptureController.shared.save(image: image, scale: document.scale, suggestedName: name)
    }

    /// For the drag handle: the rendered PNG written to a temp file so it can be vended as a
    /// plain file `NSItemProvider` to any drop target (Finder, Mail, Slack…).
    func renderedTempFileURL() -> URL? {
        guard let image = AnnotationRenderer.render(base: baseImage, document: document),
              let data = AnnotationRenderer.encode(image, format: UTType.png.identifier, scale: document.scale) else { return nil }
        let name = (item.url.lastPathComponent as NSString).deletingPathExtension + ".png"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("xfinder-drag-\(UUID().uuidString)-\(name)")
        do { try data.write(to: url) } catch { return nil }
        return url
    }
}

/// The window's SwiftUI root: toolbar + canvas + status bar.
struct AnnotateRootView: View {
    @Bindable var model: AnnotateDocumentModel
    @AppStorage("capture.annotate.color") private var colorRaw = "red"
    @AppStorage("capture.annotate.width") private var widthRaw = "medium"

    private var color: Binding<MarkColor> {
        Binding(get: { MarkColor(rawValue: colorRaw) ?? .red }, set: { colorRaw = $0.rawValue })
    }
    private var width: Binding<StrokeWidth> {
        Binding(get: { StrokeWidth(rawValue: widthRaw) ?? .medium }, set: { widthRaw = $0.rawValue })
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            AnnotateCanvasView(model: model, color: color, width: width)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            statusBar
        }
        .background(WindowKeyBridge(model: model))
    }

    private var toolbar: some View {
        HStack(spacing: XFinderTokens.Space.inline) {
            ForEach(AnnotationTool.allCases, id: \.self) { tool in
                Button {
                    model.activeTool = tool
                } label: {
                    Image(systemName: tool.symbol)
                        .frame(width: 26, height: 22)
                        .background(model.activeTool == tool ? XFinderTokens.Fill.focus : Color.clear)
                        .cornerRadius(XFinderTokens.Radius.control)
                }
                .buttonStyle(.plain)
                .help("\(L10n.t(tool.titleKey)) (\(tool.keyEquivalent))")
            }

            Divider().frame(height: 18)

            HStack(spacing: 4) {
                ForEach(MarkColor.allCases, id: \.self) { c in
                    Button { color.wrappedValue = c } label: {
                        Circle()
                            .fill(swatch(c))
                            .frame(width: 16, height: 16)
                            .overlay(Circle().stroke(Color.primary.opacity(color.wrappedValue == c ? 0.6 : 0.15),
                                                      lineWidth: color.wrappedValue == c ? 2 : 1))
                    }
                    .buttonStyle(.plain)
                }
            }

            Picker("", selection: width) {
                ForEach(StrokeWidth.allCases, id: \.self) { w in
                    Text(L10n.t(w.titleKey)).tag(w)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 150)
            .labelsHidden()

            Divider().frame(height: 18)

            Button { model.performUndo() } label: { Image(systemName: "arrow.uturn.backward") }
                .buttonStyle(.plain).disabled(!model.undo.canUndo).help(L10n.t("Hoàn tác"))
            Button { model.performRedo() } label: { Image(systemName: "arrow.uturn.forward") }
                .buttonStyle(.plain).disabled(!model.undo.canRedo).help(L10n.t("Làm lại"))

            Spacer(minLength: XFinderTokens.Space.inline)

            dragHandle

            Button(L10n.t("Lưu…")) { model.saveViaPanel() }
                .buttonStyle(.bordered)
            Button(L10n.t("Sao chép")) { model.copyAndClose() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
        .font(XFinderTokens.Font.row)
        .padding(.horizontal, XFinderTokens.Space.page)
        .padding(.vertical, XFinderTokens.Space.tight)
    }

    private var dragHandle: some View {
        Image(systemName: "line.3.horizontal")
            .frame(width: 24, height: 22)
            .contentShape(Rectangle())
            .background(DragHandleRepresentable(model: model))
            .help(L10n.t("Kéo ra để lưu vào nơi khác"))
    }

    private var statusBar: some View {
        HStack {
            Text("\(Int(model.document.outputPixelSize.width)) × \(Int(model.document.outputPixelSize.height))")
            Text("\(model.document.marks.count)\(L10n.t(" dấu"))")
            Spacer()
        }
        .font(XFinderTokens.Font.caption)
        .foregroundColor(.secondary)
        .padding(.horizontal, XFinderTokens.Space.page)
        .padding(.vertical, 4)
    }

    private func swatch(_ c: MarkColor) -> Color {
        let rgb = c.rgb
        return Color(red: rgb.r, green: rgb.g, blue: rgb.b)
    }
}

/// Arms the document's local key monitor once this view's window is known, releases it on teardown.
private struct WindowKeyBridge: NSViewRepresentable {
    let model: AnnotateDocumentModel

    func makeNSView(context: Context) -> NSView {
        let v = NSView(frame: .zero)
        DispatchQueue.main.async {
            if let window = v.window { model.armKeyMonitor(for: window) }
        }
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    // No `dismantleNSView` override: the model's key monitor is released by
    // `AnnotateWindowController`'s `onClose` / `windowWillClose`, which always runs before this
    // hosting view is torn down (the window owns both).
}

/// Drags the rendered PNG out as a real file (the temp file URL is the pasteboard writer).
private struct DragHandleRepresentable: NSViewRepresentable {
    let model: AnnotateDocumentModel

    final class HandleView: NSView {
        var model: AnnotateDocumentModel?

        override func mouseDown(with event: NSEvent) {
            guard let model, let url = model.renderedTempFileURL() else {
                super.mouseDown(with: event)
                return
            }
            // A file URL is the pasteboard writer AppKit drags take (NSItemProvider is not NSPasteboardWriting).
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            item.setDraggingFrame(NSRect(x: 0, y: 0, width: 48, height: 48), contents: icon)
            beginDraggingSession(with: [item], event: event, source: self)
        }
    }

    func makeNSView(context: Context) -> HandleView {
        let v = HandleView()
        v.model = model
        return v
    }

    func updateNSView(_ nsView: HandleView, context: Context) { nsView.model = model }
}

extension DragHandleRepresentable.HandleView: NSDraggingSource {
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }
}
