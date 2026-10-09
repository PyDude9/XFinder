import AppKit
import LocalAuthentication
import QuickLookUI
import SwiftUI

/// PasteApp-style floating clipboard shelf: ⌘⇧V anywhere pops a horizontal
/// card deck along the bottom of the active screen, over whatever app the user
/// is in.
///
/// - Panel: `KeyablePanel` + `.nonactivatingPanel` + `.floating` so the
///   previously-active app keeps focus, while search and controls take typing.
/// - Hotkey: a `.cgSessionEventTap`, so it fires system-wide.
/// - Keys while open: ←/→ select · Return paste · ⇧Return plain text ·
///   ⌘1–9 direct board · ⌘P pin · ⌘⌫ delete · ⌘F search · Space Quick Look · Esc close.
@MainActor
@Observable
final class ClipboardShelfController {
    static let shared = ClipboardShelfController()

    private(set) var isOpen = false
    var selectedIndex = 0
    var shouldFocusSearch = false

    private let openSnapshot = Locked<Bool>(false)
    private let searchFocusSnapshot = Locked<Bool>(false)

    var isSearchFocused: Bool = false {
        didSet {
            searchFocusSnapshot.value = isSearchFocused
        }
    }

    var selectedBoardID: UUID? {
        get { ClipboardManager.shared.currentPinboardID }
        set { ClipboardManager.shared.currentPinboardID = newValue }
    }

    var showingSuggestions: Bool = false
    /// The app to paste back into — captured before the shelf appears.
    private(set) var targetPID: pid_t?

    var items: [ClipboardRecord] {
        if showingSuggestions {
            let all = ClipboardManager.shared.filteredHistory()
            return ClipboardIntelligenceEngine.shared.rankSuggestions(from: all, forTargetPID: targetPID)
        }
        return ClipboardManager.shared.boardItems()
    }

    private var panel: KeyablePanel?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private var dismissMonitor: Any?
    private var localDismissMonitor: Any?
    private let quickLook = ClipboardQLController()

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
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
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
                if let tap = self.eventTap, CFMachPortIsValid(tap) {
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
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
        guard openSnapshot.value else { return Unmanaged.passUnretained(event) }

        switch keyCode {
        case 53: // Esc
            Task { @MainActor in
                if !ClipboardManager.shared.searchText.isEmpty {
                    ClipboardManager.shared.searchText = ""
                } else if ClipboardManager.shared.isMultiSelectActive {
                    ClipboardManager.shared.isMultiSelectActive = false
                    ClipboardManager.shared.multiSelectedIDs.removeAll()
                } else {
                    self.close()
                }
            }
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
            if searchFocusSnapshot.value {
                return Unmanaged.passUnretained(event)
            }
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
        case 51 where cmd: // ⌘⌫ — delete selected
            Task { @MainActor in self.deleteSelected() }
            return nil
        case 3 where cmd: // ⌘F — focus search
            Task { @MainActor in self.focusSearch() }
            return nil
        case 0 where cmd: // ⌘A — select all if multi-select active
            Task { @MainActor in
                if ClipboardManager.shared.isMultiSelectActive {
                    self.selectAll()
                }
            }
            return nil
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    // MARK: - Presentation

    func toggle() { isOpen ? close() : open() }

    func open() {
        guard !isOpen else { return }
        // Remember who to paste back into before we show anything.
        targetPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        selectedIndex = 0
        showingSuggestions = false
        ClipboardManager.shared.searchText = ""
        isSearchFocused = false
        shouldFocusSearch = false

        let screen = WindowManager.screenUnderPointer()
        let height: CGFloat = 330
        let hMargin: CGFloat = 12

        // If Dock is at bottom and visible (screen.visibleFrame.minY > screen.frame.minY + 10):
        // Position shelf right above Dock with 2pt gap.
        // Otherwise (Dock autohidden or at left/right), position 6pt above bottom edge of screen.
        let yPos: CGFloat
        if screen.visibleFrame.minY > screen.frame.minY + 10 {
            yPos = screen.visibleFrame.minY + 2
        } else {
            yPos = screen.frame.minY + 6
        }

        let frame = NSRect(x: screen.visibleFrame.minX + hMargin,
                           y: yPos,
                           width: screen.visibleFrame.width - hMargin * 2,
                           height: height)

        let p = KeyablePanel(contentRect: frame,
                             styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        p.level = .floating
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.contentView = NSHostingView(rootView: ClipboardShelfView().environment(ClipboardManager.shared))
        p.orderFrontRegardless()
        panel = p

        isOpen = true
        openSnapshot.value = true
        armDismissMonitor()
    }

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
        openSnapshot.value = false
    }

    // MARK: - Actions

    func move(_ delta: Int) {
        let count = items.count
        guard count > 0 else { return }
        selectedIndex = (selectedIndex + delta + count) % count
    }

    func selectBoard(at index: Int) {
        if index == 0 {
            showingSuggestions = false
            ClipboardManager.shared.currentPinboardID = nil
            ClipboardManager.shared.selectedSlice = .all
            selectedIndex = 0
            return
        }
        if index == 1 {
            showingSuggestions = false
            ClipboardManager.shared.currentPinboardID = nil
            ClipboardManager.shared.selectedSlice = .pinned
            selectedIndex = 0
            return
        }
        let customBoards = ClipboardManager.shared.pinboards.filter { !$0.isBuiltIn }
        let customIndex = index - 2
        if customIndex >= 0 && customIndex < customBoards.count {
            showingSuggestions = false
            ClipboardManager.shared.currentPinboardID = customBoards[customIndex].id
            ClipboardManager.shared.selectedSlice = .all
            selectedIndex = 0
        }
    }

    func pinSelected() {
        let list = items
        guard list.indices.contains(selectedIndex) else { return }
        let id = list[selectedIndex].id
        ClipboardManager.shared.togglePin(id)
    }

    func deleteSelected() {
        let list = items
        guard list.indices.contains(selectedIndex) else { return }
        let id = list[selectedIndex].id
        ClipboardManager.shared.deleteRecord(id)
        let newCount = items.count
        if selectedIndex >= newCount && newCount > 0 {
            selectedIndex = newCount - 1
        }
    }

    func selectAll() {
        ClipboardManager.shared.isMultiSelectActive = true
        ClipboardManager.shared.multiSelectedIDs = Set(items.map(\.id))
    }

    func focusSearch() {
        shouldFocusSearch = true
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
        let autoPaste = UserDefaults.standard.object(forKey: "clipboard.autoPasteAfterSelection") as? Bool ?? true
        if autoPaste && WindowManager.isTrusted {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                ClipboardPasteEngine.paste(record: record, to: pid, plainText: plainText)
            }
        } else {
            ClipboardPasteEngine.writeToPasteboard(record: record, plainText: plainText)
            ClipboardSounds.playCopy()
        }
        ClipboardManager.shared.incrementUsage(record.id)
    }

    func quickLookSelected() {
        let list = items
        guard list.indices.contains(selectedIndex) else { return }
        let record = list[selectedIndex]
        if let path = record.payloadPath ?? record.thumbnailPath,
           FileManager.default.fileExists(atPath: path) {
            quickLook.present(url: URL(fileURLWithPath: path))
        }
    }
}

// MARK: - Shelf Content View

private struct ClipboardShelfView: View {
    @State private var controller = ClipboardShelfController.shared
    @State private var manager = ClipboardManager.shared
    @AppStorage("clipboard.touchIDLock") private var touchIDLock = false
    @State private var isUnlocked = false
    @FocusState private var isSearchFocused: Bool
    @State private var showCreateBoardOverlay = false
    @State private var showSaveSnippetOverlay = false
    @State private var snippetToSave: ClipboardRecord? = nil

    var body: some View {
        ZStack {
            if touchIDLock && !isUnlocked {
                touchIDLockView
            } else {
                mainShelfContent
            }

            if showCreateBoardOverlay {
                CreateBoardOverlay(isPresented: $showCreateBoardOverlay)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }

            if showSaveSnippetOverlay, let rec = snippetToSave {
                SaveSnippetOverlay(record: rec, isPresented: $showSaveSnippetOverlay)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .background(VisualEffectBackground())
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .animation(.easeOut(duration: 0.16), value: showCreateBoardOverlay)
        .animation(.easeOut(duration: 0.16), value: showSaveSnippetOverlay)
        .onAppear {
            if touchIDLock && !isUnlocked {
                authenticateWithBiometrics()
            } else if !touchIDLock {
                isUnlocked = true
            }
        }
        .onChange(of: isSearchFocused) { _, focused in
            controller.isSearchFocused = focused
        }
        .onChange(of: controller.shouldFocusSearch) { _, shouldFocus in
            if shouldFocus {
                isSearchFocused = true
                controller.shouldFocusSearch = false
            }
        }
    }

    private var touchIDLockView: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 40))
                .foregroundColor(.accentColor)
            Text(L10n.t("Mở khóa Clipboard"))
                .font(.system(size: 16, weight: .semibold))
            Text(L10n.t("Xác thực bằng Touch ID hoặc mật khẩu để xem lịch sử clipboard"))
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            Button(L10n.t("Mở khóa Clipboard")) {
                authenticateWithBiometrics()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func authenticateWithBiometrics() {
        let context = LAContext()
        var error: NSError?
        let reason = L10n.t("Xác thực bằng Touch ID hoặc mật khẩu để xem lịch sử clipboard")
        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, _ in
                Task { @MainActor in
                    if success { isUnlocked = true }
                }
            }
        } else {
            isUnlocked = true
        }
    }

    private var mainShelfContent: some View {
        VStack(spacing: 0) {
            topBar
            Divider().opacity(0.5)
            deck
            if manager.isMultiSelectActive {
                multiSelectActionBar
            }
            Divider().opacity(0.5)
            hintBar
        }
    }

    // MARK: - Unified Header Bar (Paste 7 style)

    private var topBar: some View {
        HStack(spacing: 10) {
            // Pinboards & Category Tabs (Scrollable)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    // 1. Suggestions Tab (✨ Gợi ý)
                    Button {
                        controller.showingSuggestions = true
                        controller.selectedIndex = 0
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 11, weight: .semibold))
                            Text(L10n.t("Gợi ý"))
                                .font(.system(size: 12, weight: .medium))
                        }
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(controller.showingSuggestions ? Color.purple.opacity(0.85) : Color.primary.opacity(0.06))
                        )
                        .foregroundColor(controller.showingSuggestions ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                    .help(L10n.t("Gợi ý thông minh"))

                    // 2. All History (🕒 Lịch sử Clipboard)
                    let isHistorySel = !controller.showingSuggestions && manager.currentPinboardID == nil && manager.selectedSlice == .all
                    boardChip(
                        title: L10n.t("Lịch sử Clipboard"),
                        icon: "clock.arrow.circlepath",
                        dot: nil,
                        count: manager.history.count,
                        shortcut: "⌘1",
                        selected: isHistorySel
                    ) {
                        controller.showingSuggestions = false
                        manager.currentPinboardID = nil
                        manager.selectedSlice = .all
                        controller.selectedIndex = 0
                    }

                    // 3. Pinned Tab (📌 Đã ghim)
                    let isPinnedSel = !controller.showingSuggestions && manager.currentPinboardID == nil && manager.selectedSlice == .pinned
                    boardChip(
                        title: L10n.t("Đã ghim"),
                        icon: "pin.fill",
                        dot: Color.orange,
                        count: manager.history.filter(\.isPinned).count,
                        shortcut: "⌘2",
                        selected: isPinnedSel
                    ) {
                        controller.showingSuggestions = false
                        manager.currentPinboardID = nil
                        manager.selectedSlice = .pinned
                        controller.selectedIndex = 0
                    }

                    // 4. Custom Pinboards
                    ForEach(Array(manager.pinboards.filter { !$0.isBuiltIn }.enumerated()), id: \.element.id) { index, board in
                        let isSel = !controller.showingSuggestions && manager.currentPinboardID == board.id
                        boardChip(
                            title: board.name,
                            icon: board.icon,
                            dot: board.color.color,
                            count: board.itemIDs.count,
                            shortcut: index < 7 ? "⌘\(index + 3)" : "",
                            selected: isSel
                        ) {
                            controller.showingSuggestions = false
                            manager.currentPinboardID = board.id
                            manager.selectedSlice = .all
                            controller.selectedIndex = 0
                        }
                    }

                    // Add board button (+)
                    Button {
                        showCreateBoardOverlay = true
                    } label: {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 15))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 4)
                    .help(L10n.t("Tạo bảng ghim mới"))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }

            Spacer(minLength: 6)

            // Right side: Quick Search + Filter Menu + Multi-select
            HStack(spacing: 8) {
                // Search Field
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    TextField(L10n.t("Tìm kiếm (⌘F)…"),
                              text: Binding(
                                get: { manager.searchText },
                                set: {
                                    manager.searchText = $0
                                    controller.selectedIndex = 0
                                }
                              ))
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .focused($isSearchFocused)
                        .frame(width: 155)
                    if !manager.searchText.isEmpty {
                        Button {
                            manager.searchText = ""
                            controller.selectedIndex = 0
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.primary.opacity(0.06))
                )

                if manager.pasteStack.active {
                    PasteStackHUD()
                }

                // Filter Menu
                let isFiltered = manager.selectedTypeFilter != nil || manager.dateFilter != .allTime || manager.sourceAppFilter != nil || manager.sortOrder != .newest
                Menu {
                    // Type Filter Section
                    Section(L10n.t("Loại nội dung")) {
                        Button {
                            manager.selectedTypeFilter = nil
                            controller.selectedIndex = 0
                        } label: {
                            HStack {
                                Text(L10n.t("Tất cả loại"))
                                if manager.selectedTypeFilter == nil { Image(systemName: "checkmark") }
                            }
                        }
                        ForEach(ContentType.allCases) { type in
                            if type != .merged {
                                Button {
                                    manager.selectedTypeFilter = type
                                    controller.selectedIndex = 0
                                } label: {
                                    HStack {
                                        Text(type.titleVI)
                                        if manager.selectedTypeFilter == type { Image(systemName: "checkmark") }
                                    }
                                }
                            }
                        }
                    }

                    // Date Filter Section
                    Section(L10n.t("Thời gian")) {
                        ForEach(ClipboardDateFilter.allCases) { df in
                            Button {
                                manager.dateFilter = df
                                controller.selectedIndex = 0
                            } label: {
                                HStack {
                                    Text(df.titleVI)
                                    if manager.dateFilter == df { Image(systemName: "checkmark") }
                                }
                            }
                        }
                    }

                    // Source App Section
                    if !manager.allSourceApps.isEmpty {
                        Section(L10n.t("Ứng dụng")) {
                            Button {
                                manager.sourceAppFilter = nil
                                controller.selectedIndex = 0
                            } label: {
                                HStack {
                                    Text(L10n.t("Mọi ứng dụng"))
                                    if manager.sourceAppFilter == nil { Image(systemName: "checkmark") }
                                }
                            }
                            ForEach(manager.allSourceApps, id: \.self) { app in
                                Button {
                                    manager.sourceAppFilter = app
                                    controller.selectedIndex = 0
                                } label: {
                                    HStack {
                                        Text(app)
                                        if manager.sourceAppFilter == app { Image(systemName: "checkmark") }
                                    }
                                }
                            }
                        }
                    }

                    // Sort Order Section
                    Section(L10n.t("Sắp xếp")) {
                        ForEach(ClipboardSortOrder.allCases) { so in
                            Button {
                                manager.sortOrder = so
                                controller.selectedIndex = 0
                            } label: {
                                HStack {
                                    Text(so.titleVI)
                                    if manager.sortOrder == so { Image(systemName: "checkmark") }
                                }
                            }
                        }
                    }

                    if isFiltered {
                        Divider()
                        Button(role: .destructive) {
                            manager.selectedTypeFilter = nil
                            manager.dateFilter = .allTime
                            manager.sourceAppFilter = nil
                            manager.sortOrder = .newest
                            controller.selectedIndex = 0
                        } label: {
                            Text(L10n.t("Đặt lại bộ lọc"))
                        }
                    }
                } label: {
                    Image(systemName: isFiltered ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                        .font(.system(size: 15))
                        .foregroundColor(isFiltered ? .accentColor : .secondary)
                }
                .menuStyle(.borderlessButton)
                .help(L10n.t("Bộ lọc"))

                // Multi-select toggle
                Button {
                    manager.isMultiSelectActive.toggle()
                    if !manager.isMultiSelectActive {
                        manager.multiSelectedIDs.removeAll()
                    }
                } label: {
                    Image(systemName: manager.isMultiSelectActive ? "checkmark.circle.fill" : "checkmark.circle")
                        .font(.system(size: 15))
                        .foregroundColor(manager.isMultiSelectActive ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .help(manager.isMultiSelectActive ? L10n.t("Hoàn tất") : L10n.t("Chọn nhiều"))
            }
            .padding(.trailing, 12)
        }
        .padding(.vertical, 4)
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
                if !shortcut.isEmpty {
                    Text(shortcut)
                        .font(.system(size: 10))
                        .foregroundColor(selected ? .white.opacity(0.7) : .secondary.opacity(0.7))
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(selected ? Color.accentColor : Color.clear)
            )
            .foregroundColor(selected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Deck

    @ViewBuilder
    private var deck: some View {
        if controller.items.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: controller.showingSuggestions ? "sparkles" : "doc.on.clipboard")
                    .font(.system(size: 26))
                    .foregroundColor(controller.showingSuggestions ? .purple : .secondary)
                Text(controller.showingSuggestions ? L10n.t("Không có gợi ý nào cho ứng dụng này") : L10n.t("Chưa có mục nào trong clipboard"))
                    .font(.system(size: 12)).foregroundColor(.secondary)
                if !controller.showingSuggestions {
                    Text(L10n.t("Sao chép gì đó (⌘C) rồi mở lại bằng ⌘⇧V."))
                        .font(.system(size: 11)).foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            realDeck
        }

    }

    private var realDeck: some View {
        VStack(alignment: .leading, spacing: 4) {
            if controller.showingSuggestions {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.purple)
                    Text("\(L10n.t("Gợi ý cho "))\(ClipboardIntelligenceEngine.shared.targetAppName(forTargetPID: controller.targetPID))")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.primary)
                    Text("· Apple Intelligence")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 3)
            }

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(Array(controller.items.enumerated()), id: \.element.id) { index, record in
                            ZStack(alignment: .topLeading) {
                                ClipboardCardView(
                                    record: record,
                                    selected: index == controller.selectedIndex,
                                    onSelect: {
                                        if manager.isMultiSelectActive {
                                            manager.toggleMultiSelect(record.id)
                                        } else {
                                            controller.pasteAt(index)
                                        }
                                    },
                                    onPreview: {
                                        controller.quickLookSelected()
                                    }
                                )
                                .frame(width: 215, height: 230)

                                if controller.showingSuggestions && index == 0 {
                                    HStack(spacing: 4) {
                                        Image(systemName: "sparkles")
                                        Text(L10n.t("Gợi ý hàng đầu"))
                                    }
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.purple))
                                    .offset(x: 10, y: -6)
                                    .shadow(color: Color.purple.opacity(0.4), radius: 3)
                                }
                            }
                            .id(index)
                            .contextMenu {
                                cardContextMenu(for: record, index: index)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
                .onChange(of: controller.selectedIndex) { _, idx in
                    withAnimation(.easeOut(duration: 0.18)) { proxy.scrollTo(idx, anchor: .center) }
                }
            }
        }
    }


    // MARK: - Multi-Select Action Bar

    private var multiSelectActionBar: some View {
        HStack(spacing: 12) {
            Text("\(L10n.t("Đã chọn "))\(manager.multiSelectedIDs.count)\(L10n.t(" mục"))")
                .font(.system(size: 12, weight: .medium))
            Spacer()
            Button {
                let selectedList = Array(manager.multiSelectedIDs)
                _ = manager.mergeRecords(selectedList)
                manager.multiSelectedIDs.removeAll()
                manager.isMultiSelectActive = false
                controller.selectedIndex = 0
            } label: {
                Label(L10n.t("Gộp các mục đã chọn"), systemImage: "arrow.triangle.merge")
                    .font(.system(size: 11))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(manager.multiSelectedIDs.count < 2)

            Button(role: .destructive) {
                for id in manager.multiSelectedIDs {
                    manager.deleteRecord(id)
                }
                manager.multiSelectedIDs.removeAll()
                manager.isMultiSelectActive = false
                controller.selectedIndex = 0
            } label: {
                Label(L10n.t("Xóa mục đã chọn"), systemImage: "trash")
                    .font(.system(size: 11))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(manager.multiSelectedIDs.isEmpty)

            Button(L10n.t("Bỏ chọn tất cả")) {
                manager.multiSelectedIDs.removeAll()
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundColor(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(Color.primary.opacity(0.04))
        .overlay(Divider().opacity(0.5), alignment: .top)
    }

    // MARK: - Hint Bar

    private var hintBar: some View {
        HStack {
            Text(L10n.t("←/→ chọn · Return dán · ⇧Return dán thuần · Space xem · ⌘P ghim · ⌘1-9 bảng · Esc"))
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            Spacer()
            if !WindowManager.isTrusted {
                Button(L10n.t("Bật Dán phím (cần Trợ năng)…")) {
                    WindowManager.openAccessibilityPane()
                }
                .font(.system(size: 10))
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func cardContextMenu(for record: ClipboardRecord, index: Int) -> some View {
        Button(L10n.t("Dán (Return)")) { controller.pasteAt(index, plainText: false) }
        Button(L10n.t("Dán dạng text thuần (⇧Return)")) { controller.pasteAt(index, plainText: true) }
        Button(L10n.t("Sao chép lại vào clipboard")) {
            ClipboardPasteEngine.writeToPasteboard(record: record)
            ClipboardSounds.playCopy()
        }
        if let ocr = record.ocrText, !ocr.isEmpty {
            Button(L10n.t("Sao chép chữ OCR trong ảnh")) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(ocr, forType: .string)
            }
        }
        Divider()
        Button(record.isPinned ? L10n.t("Bỏ ghim") : L10n.t("Ghim")) {
            manager.togglePin(record.id)
        }
        if record.isSavedSnippet {
            Button(L10n.t("Bỏ lưu Snippet")) {
                manager.removeSnippet(record.id)
            }
        } else {
            Button(L10n.t("Lưu dưới dạng Snippet…")) {
                snippetToSave = record
                showSaveSnippetOverlay = true
            }
        }
        if record.type == .merged {
            Button(L10n.t("Tách mục đã gộp")) {
                manager.unmergeRecord(record.id)
            }
        }
        if let curBoard = manager.currentPinboardID {
            Button(L10n.t("Ghim vào bảng hiện tại (⌘P)")) {
                manager.addItemToPinboard(record.id, pinboardID: curBoard)
            }
        }
        Button(L10n.t("Xem nhanh (Space)")) {
            controller.quickLookSelected()
        }
        Divider()
        Button(L10n.t("Bỏ qua ứng dụng này (không lưu vào Clipboard)")) {
            manager.excludeApp(bundleID: record.sourceBundleID, appName: record.sourceAppName)
        }
        Button(L10n.t("Xóa (⌘⌫)"), role: .destructive) {
            manager.deleteRecord(record.id)
        }
    }

}

// MARK: - Overlays

private struct SaveSnippetOverlay: View {
    let record: ClipboardRecord
    @Binding var isPresented: Bool
    @State private var title: String

    init(record: ClipboardRecord, isPresented: Binding<Bool>) {
        self.record = record
        self._isPresented = isPresented
        self._title = State(initialValue: record.displayTitle)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture { isPresented = false }

            VStack(spacing: 14) {
                Text(L10n.t("Lưu Snippet"))
                    .font(.headline)
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.t("Tiêu đề mẫu lưu"))
                        .font(.caption).foregroundColor(.secondary)
                    TextField(L10n.t("Tiêu đề mẫu lưu"), text: $title)
                        .textFieldStyle(.roundedBorder)
                }
                HStack {
                    Button(L10n.t("Hủy")) {
                        isPresented = false
                    }
                    .keyboardShortcut(.cancelAction)

                    Spacer()

                    Button(L10n.t("Lưu Snippet")) {
                        ClipboardManager.shared.saveSnippet(record.id, title: title.isEmpty ? nil : title)
                        isPresented = false
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
            .frame(width: 320)
            .background(VisualEffectBackground())
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)
            )
            .shadow(radius: 16)
        }
    }
}

private struct CreateBoardOverlay: View {
    @Binding var isPresented: Bool
    @State private var name = ""
    @State private var selectedColor = Color.blue
    @State private var selectedIcon = "star.fill"

    private let colors: [Color] = [.blue, .green, .purple, .orange, .red, .pink, .yellow, .gray]
    private let icons = ["star.fill", "bookmark.fill", "folder.fill", "tag.fill", "heart.fill", "tray.fill", "doc.text.fill", "terminal.fill"]

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture { isPresented = false }

            VStack(spacing: 14) {
                Text(L10n.t("Tạo bảng ghim mới"))
                    .font(.headline)

                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.t("Tên"))
                        .font(.caption).foregroundColor(.secondary)
                    TextField(L10n.t("Tên bảng"), text: $name)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.t("Màu"))
                        .font(.caption).foregroundColor(.secondary)
                    HStack(spacing: 8) {
                        ForEach(colors, id: \.self) { c in
                            Circle().fill(c).frame(width: 22, height: 22)
                                .overlay(
                                    Circle()
                                        .stroke(selectedColor == c ? Color.white : Color.clear, lineWidth: 2)
                                )
                                .shadow(radius: selectedColor == c ? 2 : 0)
                                .onTapGesture { selectedColor = c }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.t("Biểu tượng"))
                        .font(.caption).foregroundColor(.secondary)
                    HStack(spacing: 8) {
                        ForEach(icons, id: \.self) { ico in
                            Image(systemName: ico)
                                .font(.system(size: 13))
                                .frame(width: 26, height: 26)
                                .background(selectedIcon == ico ? Color.accentColor.opacity(0.2) : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(selectedIcon == ico ? Color.accentColor : Color.clear, lineWidth: 1)
                                )
                                .onTapGesture { selectedIcon = ico }
                        }
                    }
                }

                HStack {
                    Button(L10n.t("Hủy")) {
                        isPresented = false
                    }
                    .keyboardShortcut(.cancelAction)

                    Spacer()

                    Button(L10n.t("Tạo")) {
                        let finalName = name.isEmpty ? L10n.t("Bảng mới") : name
                        ClipboardManager.shared.createPinboard(name: finalName, color: selectedColor, icon: selectedIcon)
                        ClipboardManager.shared.currentPinboardID = ClipboardManager.shared.pinboards.last?.id
                        isPresented = false
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
            .frame(width: 320)
            .background(VisualEffectBackground())
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)
            )
            .shadow(radius: 16)
        }
    }
}

// MARK: - Paste Stack HUD

private struct PasteStackHUD: View {
    @Environment(ClipboardManager.self) var clipboardManager
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "square.stack.3d.up.fill").font(.caption).foregroundColor(.accentColor)
            Text("\(L10n.t("Còn lại")): \(clipboardManager.pasteStack.remaining)")
                .font(.caption).fontWeight(.medium)
            Button(L10n.t("Hủy")) { clipboardManager.stopPasteStack() }
                .font(.caption2).buttonStyle(.plain).foregroundColor(.secondary)
        }
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(Color.accentColor.opacity(0.12)).cornerRadius(8)
        .help(L10n.t("Paste Stack đang hoạt động — mỗi lần Dán lấy mục tiếp theo. Bấm Hủy để dừng."))
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
