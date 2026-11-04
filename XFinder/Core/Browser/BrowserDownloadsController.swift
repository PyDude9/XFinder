import AppKit
import SwiftUI
import Carbon.HIToolbox

/// One Downloads surface at a time; subscriptions exist only while its content is visible.
@MainActor @Observable
final class BrowserDownloadsController: NSObject, NSPopoverDelegate, NSWindowDelegate {
    static let shared = BrowserDownloadsController()
    private(set) var entries: [DirectoryEntry] = []
    private(set) var loading = true
    private(set) var errorKey: String?
    private(set) var hotkeyRegistered = false
    @ObservationIgnored private var subscription: ListingSubscription?
    @ObservationIgnored private var ranking: Task<Void, Never>?
    @ObservationIgnored private var generation: UUID?
    @ObservationIgnored private var popover: NSPopover?
    @ObservationIgnored private var panel: NSPanel?
    @ObservationIgnored private weak var anchor: NSView?
    @ObservationIgnored private var hotKeyRef: EventHotKeyRef?
    @ObservationIgnored private var carbonHandler: EventHandlerRef?
    private static let signature: OSType = 0x5846444C // XFDL

    var path: String { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads").path }

    func applySettings() {
        guard BrowserSettings.isEnabled && BrowserSettings.downloadsHotkeyEnabled else {
            if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
            hotKeyRef = nil
            hotkeyRegistered = false
            return
        }
        guard hotKeyRef == nil else { return }
        if carbonHandler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let callback: EventHandlerUPP = { _, event, _ in
                guard let event else { return OSStatus(eventNotHandledErr) }
                var id = EventHotKeyID()
                GetEventParameter(event, UInt32(kEventParamDirectObject), UInt32(typeEventHotKeyID), nil,
                                  MemoryLayout<EventHotKeyID>.size, nil, &id)
                guard id.signature == BrowserDownloadsController.signature, id.id == 1 else { return OSStatus(eventNotHandledErr) }
                Task { @MainActor in
                    guard BrowserSettings.isEnabled && BrowserSettings.downloadsHotkeyEnabled else { return }
                    BrowserDownloadsController.shared.togglePanel()
                }
                return noErr
            }
            InstallEventHandler(GetApplicationEventTarget(), callback, 1, &spec, nil, &carbonHandler)
        }
        guard carbonHandler != nil else { return }
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(2, UInt32(controlKey | optionKey | cmdKey),
                                        EventHotKeyID(signature: Self.signature, id: 1), GetApplicationEventTarget(), 0, &ref)
        hotKeyRef = status == noErr ? ref : nil
        hotkeyRegistered = hotKeyRef != nil
    }

    func show(relativeTo view: NSView) {
        if popover?.isShown == true, anchor === view { close(); return }
        close()
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 420, height: 500)
        popover.contentViewController = NSHostingController(rootView: BrowserDownloadsView(controller: self))
        popover.delegate = self
        self.popover = popover
        anchor = view
        popover.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }

    func togglePanel() {
        if panel?.isVisible == true || popover?.isShown == true { close(); return }
        close()
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 500),
                            styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false)
        panel.title = L10n.t("Khay Tải về")
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.level = .floating
        panel.contentView = NSHostingView(rootView: BrowserDownloadsView(controller: self))
        self.panel = panel
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        let oldPopover = popover
        let oldPanel = panel
        popover = nil
        panel = nil
        anchor = nil
        stop()
        oldPopover?.performClose(nil)
        oldPanel?.close()
    }

    func begin() -> UUID {
        stop()
        let token = UUID()
        generation = token
        entries = []
        loading = true
        errorKey = nil
        subscription = DirectoryLoadCoordinator.shared.subscribe(path: path) { [weak self] result in
            guard let self, self.generation == token else { return }
            self.ranking?.cancel()
            switch result {
            case .failure(let error):
                self.entries = []
                self.loading = false
                self.errorKey = error.messageKey
            case .success(let delivery):
                self.ranking = Task { @MainActor [weak self] in
                    let recent = await Task.detached(priority: .userInitiated) { BrowserDownloadsRules.recent(delivery.entries) }.value
                    guard !Task.isCancelled, let self, self.generation == token else { return }
                    self.entries = recent
                    self.errorKey = nil
                    self.loading = !delivery.isFinal && recent.isEmpty
                }
            }
        } onGone: { [weak self] in
            guard let self, self.generation == token else { return }
            self.ranking?.cancel()
            self.entries = []
            self.loading = false
            self.errorKey = "Thư mục không còn tồn tại"
        }
        return token
    }

    func end(_ token: UUID?) { if token == generation { stop() } }
    private func stop() {
        generation = nil
        ranking?.cancel()
        ranking = nil
        subscription?.cancel()
        subscription = nil
    }

    func open(_ entry: DirectoryEntry) {
        let token = generation
        Task { @MainActor in
            let exists = await Task.detached(priority: .userInitiated) { FileManager.default.fileExists(atPath: entry.path) }.value
            guard generation == token, token != nil else { return }
            guard exists else { errorKey = "Không mở được mục này. Tệp có thể đã bị xoá hoặc thiếu quyền truy cập."; return }
            if entry.isFolderLike {
                close()
                BrowserWindowController.shared.openWindow(path: entry.path)
            } else if NSWorkspace.shared.open(URL(fileURLWithPath: entry.path)) { close() }
            else { errorKey = "Không mở được mục này. Tệp có thể đã bị xoá hoặc thiếu quyền truy cập." }
        }
    }

    func reveal(_ entry: DirectoryEntry) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: entry.path)])
        close()
    }
    func openFolder() { close(); BrowserWindowController.shared.openWindow(path: path) }

    nonisolated func popoverDidClose(_ notification: Notification) {
        let identity = (notification.object as AnyObject?).map(ObjectIdentifier.init)
        Task { @MainActor [weak self] in
            guard let self, self.popover.map(ObjectIdentifier.init) == identity else { return }
            self.popover = nil
            self.stop()
        }
    }
    nonisolated func windowWillClose(_ notification: Notification) {
        let identity = (notification.object as AnyObject?).map(ObjectIdentifier.init)
        Task { @MainActor [weak self] in
            guard let self, self.panel.map(ObjectIdentifier.init) == identity else { return }
            self.panel = nil
            self.stop()
        }
    }
}

private struct BrowserDownloadsView: View {
    let controller: BrowserDownloadsController
    @State private var token: UUID?
    var body: some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
            HStack {
                Text(L10n.t("Khay Tải về")).font(XFinderTokens.Font.sectionTitle)
                Spacer()
                Button { controller.close() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).accessibilityLabel(L10n.t("Đóng"))
            }
            Text(L10n.t("20 mục mới nhất theo ngày sửa đổi")).font(XFinderTokens.Font.caption).foregroundStyle(.secondary)
            SettingsDivider()
            if let error = controller.errorKey {
                Text(L10n.t(error)).font(XFinderTokens.Font.row)
            }
            if controller.loading { ProgressView().frame(maxWidth: .infinity) }
            else if controller.entries.isEmpty && controller.errorKey == nil {
                Text(L10n.t("Chưa có mục nào trong thư mục Tải về.")).font(XFinderTokens.Font.row)
            }
            ScrollView {
                VStack(spacing: XFinderTokens.Space.row) {
                    ForEach(controller.entries) { entry in
                        HStack {
                            Button { controller.open(entry) } label: {
                                Label(entry.name, systemImage: entry.isFolderLike ? "folder" : "doc")
                                    .lineLimit(1).truncationMode(.middle).frame(maxWidth: .infinity, alignment: .leading)
                            }.buttonStyle(.plain).help(entry.path)
                            Button { controller.reveal(entry) } label: { Image(systemName: "magnifyingglass") }
                                .buttonStyle(.plain).help(L10n.t("Hiện trong Finder"))
                                .accessibilityLabel(L10n.t("Hiện trong Finder") + ": " + entry.name)
                        }.font(XFinderTokens.Font.row).padding(.vertical, XFinderTokens.Space.tight)
                    }
                }
            }
            Spacer(minLength: 0)
            SettingsDivider()
            Button(L10n.t("Mở thư mục Tải về")) { controller.openFolder() }
        }
        .padding(XFinderTokens.Space.section)
        .frame(width: 420, height: 500)
        .onAppear { token = controller.begin() }
        .onDisappear { controller.end(token) }
        .onExitCommand { controller.close() }
    }
}
