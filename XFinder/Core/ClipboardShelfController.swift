import AppKit
import SwiftUI

/// PasteApp-style floating clipboard shelf: ⌘⇧V anywhere pops a horizontal
/// card deck along the bottom of the active screen, over whatever app the user
/// is in — *not* the in-app Clipboard page (which is for browsing/管理).
///
/// - Panel: `.nonactivatingPanel` + `.floating` so the previously-active app
///   keeps focus and the paste can be delivered straight back to it.
/// - Hotkey: a `.cgSessionEventTap`, so it fires system-wide. That needs
///   Accessibility trust — the same grant pasting already requires, since
///   `ClipboardPasteEngine` synthesizes ⌘V.
/// - Keys while open: ←/→ select · Return paste · ⇧Return plain text ·
///   ⌘1–9 direct paste · Space Quick Look · Esc close.
@MainActor
@Observable
final class ClipboardShelfController {
    static let shared = ClipboardShelfController()

    private(set) var isOpen = false
    var selectedIndex = 0
    var searchText = ""
    /// nil = full history; otherwise the pinboard being shown.
    var selectedBoardID: UUID?

    private var panel: NSPanel?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    /// The app to paste back into — captured before the shelf appears.
    private var targetPID: pid_t?
    private var dismissMonitor: Any?
    private var localDismissMonitor: Any?

    private init() {}

    private var hotkeyEnabled: Bool {
        UserDefaults.standard.object(forKey: "clipboard.globalHotkey") as? Bool ?? true
    }

    func applySettings() {
        guard hotkeyEnabled, WindowManager.isTrusted else {
            teardownTap()
            return
        }
        setupTap()
    }

    // MARK: - Global hotkey

    private func setupTap() {
        guard eventTap == nil else { return }
        let mask = 1 << CGEventType.keyDown.rawValue
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let c = Unmanaged<ClipboardShelfController>.fromOpaque(refcon).takeUnretainedValue()
            return c.handle(type: type, event: event)
        }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                          place: .headInsertEventTap,
                                          options: .defaultTap,
                                          eventsOfInterest: CGEventMask(mask),
                                          callback: callback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque())
        else { return }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        runLoopSource = source
    }

    private func teardownTap() {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        close()
    }

    private nonisolated func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            Task { @MainActor in
                if let tap = self.eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            }
            return Unmanaged.passUnretained(event)
        }

        let flags = event.flags
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let cmd = flags.contains(.maskCommand)
        let shift = flags.contains(.maskShift)

        // ⌘⇧V — toggle the shelf.
        if cmd, shift, keyCode == 9 { // V
            Task { @MainActor in self.toggle() }
            return nil
        }

        // Everything below only applies while the shelf is showing. `isOpen`
        // is main-actor state, so mirror it in a nonisolated snapshot.
        guard openSnapshot else { return Unmanaged.passUnretained(event) }

        switch keyCode {
        case 53: // Esc
            Task { @MainActor in self.close() }
            return nil
        case 123: // ←
            Task { @MainActor in self.move(-1) }
            return nil
        case 124: // →
            Task { @MainActor in self.move(1) }
            return nil
        case 36: // Return
            Task { @MainActor in self.pasteSelected(plainText: shift) }
            return nil
        case 49: // Space
            Task { @MainActor in self.quickLookSelected() }
            return nil
        case 18...25 where cmd: // ⌘1–⌘9 switch pinboards (⌘1 = history)
            let slots: [Int64: Int] = [18: 0, 19: 1, 20: 2, 21: 3, 23: 4, 22: 5, 26: 6, 28: 7, 25: 8]
            if let idx = slots[keyCode] {
                Task { @MainActor in self.selectBoard(at: idx) }
                return nil
            }
            return Unmanaged.passUnretained(event)
        case 35 where cmd: // ⌘P — pin to the current board
            Task { @MainActor in self.pinSelected() }
            return nil
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    /// Lock-free mirror of `isOpen` readable from the event-tap thread.
    private nonisolated(unsafe) var openSnapshot = false

    // MARK: - Presentation

    func toggle() { isOpen ? close() : open() }

    func open() {
        guard !isOpen else { return }
        // Remember who to paste back into before we show anything.
        targetPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        selectedIndex = 0
        searchText = ""

        let screen = WindowManager.screenUnderPointer()
        let height: CGFloat = 340
        let margin: CGFloat = 10
        let frame = NSRect(x: screen.visibleFrame.minX + margin,
                           y: screen.visibleFrame.minY + margin,
                           width: screen.visibleFrame.width - margin * 2,
                           height: height)

        let p = NSPanel(contentRect: frame,
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.level = .floating
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.contentView = NSHostingView(rootView: ClipboardShelfView())
        p.orderFrontRegardless()
        panel = p

        isOpen = true
        openSnapshot = true
        armDismissMonitor()
    }

    /// Click anywhere outside the shelf closes it — matching PasteApp, and the
    /// macOS convention for any transient popover. Requiring a second ⌘⇧V to
    /// dismiss was a bug, not a design choice.
    ///
    /// Needs BOTH monitors: the global one never fires while XFinder itself is
    /// frontmost, so clicking on our own Settings window left the shelf stuck
    /// open. The local one sees clicks into XFinder's windows — including the
    /// shelf panel itself, which is why the frame check runs in both paths.
    private func armDismissMonitor() {
        if dismissMonitor == nil {
            dismissMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown]
            ) { [weak self] _ in
                Task { @MainActor in self?.dismissIfClickedOutside() }
            }
        }
        if localDismissMonitor == nil {
            localDismissMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown]
            ) { [weak self] event in
                Task { @MainActor in self?.dismissIfClickedOutside() }
                return event
            }
        }
    }

    private func dismissIfClickedOutside() {
        guard isOpen, let panel else { return }
        if !panel.frame.contains(NSEvent.mouseLocation) { close() }
    }

    private func releaseDismissMonitor() {
        if let dismissMonitor { NSEvent.removeMonitor(dismissMonitor) }
        dismissMonitor = nil
        if let localDismissMonitor { NSEvent.removeMonitor(localDismissMonitor) }
        localDismissMonitor = nil
    }

    func close() {
        releaseDismissMonitor()
        panel?.orderOut(nil)
        panel = nil
        isOpen = false
        openSnapshot = false
    }

    // MARK: - Actions

    var items: [ClipboardRecord] {
        var all = ClipboardManager.shared.history
        // Board membership lives in `Pinboard.itemIDs`, not on the record.
        if let boardID = selectedBoardID,
           let board = ClipboardManager.shared.pinboards.first(where: { $0.id == boardID }) {
            let ids = Set(board.itemIDs)
            all = all.filter { ids.contains($0.id) }
        }
        guard !searchText.isEmpty else { return all }
        return all.filter { record in
            (record.textSnippet?.localizedCaseInsensitiveContains(searchText) ?? false)
                || (record.ocrText?.localizedCaseInsensitiveContains(searchText) ?? false)
                || (record.sourceAppName?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    /// Slot 0 is the full history; 1…n map onto the user's pinboards.
    private func selectBoard(at index: Int) {
        let boards = ClipboardManager.shared.pinboards
        if index == 0 {
            selectedBoardID = nil
        } else if boards.indices.contains(index - 1) {
            selectedBoardID = boards[index - 1].id
        } else {
            return
        }
        selectedIndex = 0
    }

    private func pinSelected() {
        let list = items
        guard list.indices.contains(selectedIndex) else { return }
        let board = selectedBoardID ?? ClipboardManager.shared.pinboards.first?.id
        guard let board else { return }
        ClipboardManager.shared.addItemToPinboard(list[selectedIndex].id, pinboardID: board)
    }

    private func move(_ delta: Int) {
        let count = items.count
        guard count > 0 else { return }
        selectedIndex = (selectedIndex + delta + count) % count
    }

    func pasteSelected(plainText: Bool) {
        pasteAt(selectedIndex, plainText: plainText)
    }

    func pasteAt(_ index: Int, plainText: Bool = false) {
        let list = items
        guard list.indices.contains(index) else { return }
        let record = list[index]
        let pid = targetPID
        close()
        // Let the panel actually go away before the keystroke is delivered,
        // otherwise the paste can land back in the shelf.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            ClipboardPasteEngine.paste(record: record, to: pid, plainText: plainText)
        }
    }

    private let quickLook = ClipboardQLController()

    /// Quick Look only has something to show for payloads that live on disk.
    private func quickLookSelected() {
        let list = items
        guard list.indices.contains(selectedIndex),
              let path = list[selectedIndex].payloadPath ?? list[selectedIndex].thumbnailPath,
              FileManager.default.fileExists(atPath: path)
        else { return }
        quickLook.present(url: URL(fileURLWithPath: path))
    }
}

/// The shelf's content: search field plus a horizontal deck of cards.
private struct ClipboardShelfView: View {
    @State private var controller = ClipboardShelfController.shared
    @State private var manager = ClipboardManager.shared

    var body: some View {
        VStack(spacing: 0) {
            boardTabs
            Divider().opacity(0.5)
            searchBar
            Divider().opacity(0.5)
            deck
            Divider().opacity(0.5)
            hintBar
        }
        .background(VisualEffectBackground())
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
    }

    /// Pinboard selector — history plus every user board, each with a count
    /// and its ⌘-number shortcut, as in the reference screenshot.
    private var boardTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                boardChip(title: "Clipboard History",
                          icon: "clock.fill",
                          dot: nil,
                          count: manager.history.count,
                          shortcut: "⌘1",
                          selected: controller.selectedBoardID == nil) {
                    controller.selectedBoardID = nil
                    controller.selectedIndex = 0
                }

                ForEach(Array(manager.pinboards.enumerated()), id: \.element.id) { index, board in
                    boardChip(title: board.name,
                              icon: board.icon,
                              dot: board.color.color,
                              count: board.itemIDs.count,
                              shortcut: "⌘\(index + 2)",
                              selected: controller.selectedBoardID == board.id) {
                        controller.selectedBoardID = board.id
                        controller.selectedIndex = 0
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private func boardChip(title: String, icon: String, dot: Color?,
                           count: Int, shortcut: String, selected: Bool,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let dot {
                    Circle().fill(dot).frame(width: 7, height: 7)
                }
                Image(systemName: icon).font(.system(size: 11))
                Text(title).font(.system(size: 12, weight: .medium))
                Text("\(count)")
                    .font(.system(size: 11))
                    .foregroundColor(selected ? .white.opacity(0.8) : .secondary)
                Text(shortcut)
                    .font(.system(size: 10))
                    .foregroundColor(selected ? .white.opacity(0.7) : .secondary.opacity(0.7))
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(selected ? Color.accentColor : Color.clear)
            )
            .foregroundColor(selected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundColor(.secondary)
            TextField("Tìm kiếm (⌘F) — gồm chữ trong ảnh OCR…",
                      text: Binding(get: { controller.searchText },
                                    set: { controller.searchText = $0; controller.selectedIndex = 0 }))
                .textFieldStyle(.plain)
                .font(.system(size: 13))
            if !controller.searchText.isEmpty {
                Button {
                    controller.searchText = ""
                    controller.selectedIndex = 0
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
    }

    private var hintBar: some View {
        Text("←/→ chọn · Return dán · ⇧Return dán thuần · Space xem · ⌘P ghim · ⌘1-9 bảng · Esc")
            .font(.system(size: 10))
            .foregroundColor(.secondary)
            .padding(.horizontal, 14).padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var deck: some View {
        if controller.items.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 26)).foregroundColor(.secondary)
                Text("Chưa có mục nào trong clipboard")
                    .font(.system(size: 12)).foregroundColor(.secondary)
                Text("Sao chép gì đó (⌘C) rồi mở lại bằng ⌘⇧V.")
                    .font(.system(size: 11)).foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            realDeck
        }
    }

    private var realDeck: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(Array(controller.items.enumerated()), id: \.element.id) { index, record in
                        ShelfCard(record: record, isSelected: index == controller.selectedIndex)
                            .id(index)
                            .onTapGesture { controller.pasteAt(index) }
                    }
                }
                .padding(14)
            }
            .onChange(of: controller.selectedIndex) { _, idx in
                withAnimation(.easeOut(duration: 0.18)) { proxy.scrollTo(idx, anchor: .center) }
            }
        }
    }
}

private struct ShelfCard: View {
    let record: ClipboardRecord
    let isSelected: Bool

    private var typeIcon: String {
        switch record.type {
        case .text:  return "text.alignleft"
        case .code:  return "chevron.left.forwardslash.chevron.right"
        case .image: return "photo"
        case .link:  return "link"
        case .color: return "paintpalette"
        case .file:  return "doc"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                // Source-app icon makes a card identifiable at a glance —
                // "Screenshot 1 / 2" text alone says nothing about origin.
                if let icon = ClipboardAppIcon.icon(forBundleID: record.sourceBundleID) {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 16, height: 16)
                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 0) {
                    if let name = record.sourceAppName {
                        Text(name).font(.system(size: 10, weight: .semibold)).lineLimit(1)
                    }
                    Text(record.timeString).font(.system(size: 9)).foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: typeIcon)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Color.accentColor.opacity(0.16))

            Group {
                if record.type == .image,
                   let path = record.thumbnailPath ?? record.payloadPath,
                   let img = NSImage(contentsOfFile: path) {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Text(record.textSnippet ?? record.ocrText ?? "—")
                        .font(.system(size: 11, design: record.type == .code ? .monospaced : .default))
                        .lineLimit(9)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
            .padding(10)

            HStack {
                Text(record.type.rawValue.uppercased())
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
                if let s = record.textSnippet {
                    Text("\(s.count) ký tự")
                        .font(.system(size: 9)).foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Color.primary.opacity(0.04))
        }
        .frame(width: 210, height: 236, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color(.controlBackgroundColor)))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.08),
                              lineWidth: isSelected ? 2 : 1)
        )
        .scaleEffect(isSelected ? 1.03 : 1)
        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: isSelected)
    }
}

/// `NSVisualEffectView` bridge — the shelf sits over other apps, so it needs
/// real vibrancy rather than a flat fill.
struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
