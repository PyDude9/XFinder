import SwiftUI
import AppKit
import UniformTypeIdentifiers
import os

/// MainActor state owner for the Dynamic Island image converter page.
///
/// Lifecycle hooks for the integrator (`NotchSurfaceController` / `NotchSurfaceView`):
/// - Set `onRunningChanged` to dispatch `.taskStarted` / `.taskEnded` so the notch does not
///   auto-collapse while a batch is converting or while `NSOpenPanel` is open.
/// - Call `handleSurfaceClosed()` when the notch collapses, dismisses, or switches away while a
///   batch is running: cancels any unstarted files while keeping all source files and written outputs.
@MainActor
@Observable
final class NotchImageConvertModel {
    private(set) var state = NotchImageConvertRules.BatchState()
    var settings: NotchImageConvertRules.Settings
    private(set) var availableFormats: [ImageEngine.Target]
    private(set) var notice: String?
    private(set) var isPickingFiles = false

    /// Called when busy state changes (batch running or open panel active).
    var onRunningChanged: ((Bool) -> Void)?

    private var batchTask: Task<Void, Never>?
    private let cancelFlag = CancelFlag()

    init(encodable: [String] = ImageRunner.encodableTypes) {
        let formats = NotchImageConvertRules.availableFormats(encodable: encodable)
        self.availableFormats = formats
        let initialFormat = NotchImageConvertRules.resolvedFormat(.jpeg, encodable: encodable) ?? .jpeg
        self.settings = NotchImageConvertRules.Settings(format: initialFormat)
    }

    var canConvert: Bool {
        !availableFormats.isEmpty && state.canStart && batchTask == nil
    }

    var hasEncoders: Bool { !availableFormats.isEmpty }

    func refreshEncoders(encodable: [String] = ImageRunner.encodableTypes) {
        availableFormats = NotchImageConvertRules.availableFormats(encodable: encodable)
        if let resolved = NotchImageConvertRules.resolvedFormat(settings.format, encodable: encodable) {
            settings.format = resolved
        }
    }

    func setFormat(_ target: ImageEngine.Target) {
        guard !state.isRunning, availableFormats.contains(target) else { return }
        settings.format = target
    }

    func setQuality(_ value: Double) {
        guard !state.isRunning else { return }
        settings.quality = NotchImageConvertRules.clampedQuality(value)
    }

    func setMaxLongestEdge(_ pixels: Int?) {
        guard !state.isRunning else { return }
        settings.maxLongestEdge = NotchImageConvertRules.validatedMaxLongestEdge(pixels)
    }

    func enqueue(_ urls: [URL]) {
        guard batchTask == nil else { return }
        let fm = FileManager.default
        let result = state.enqueue(urls) { url in
            var isDir: ObjCBool = false
            return fm.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
        }
        notice = Self.intakeNotice(result)
    }

    func removeItem(id: String) {
        guard batchTask == nil else { return }
        state.remove(id: id)
        if state.items.isEmpty { notice = nil }
    }

    func clearItems() {
        guard batchTask == nil else { return }
        state.clear()
        notice = nil
    }

    func startBatch() {
        guard canConvert else { return }
        notice = nil
        let snapshot = state.beginRun()
        guard !snapshot.isEmpty else { return }
        let runSettings = settings
        let flag = cancelFlag
        flag.reset()
        notifyBusyChanged()

        let onStart: @Sendable (Int) async -> Void = { [weak self] index in
            await MainActor.run {
                self?.state.markItemRunning(at: index)
            }
        }
        let onFinish: @Sendable (Int, Result<URL, NotchImageConvertRules.ItemFailure>) async -> Void = { [weak self] index, result in
            await MainActor.run {
                self?.state.markItemFinished(at: index, result: result)
            }
        }
        let onDone: @Sendable () async -> Void = { [weak self] in
            await MainActor.run {
                guard let self else { return }
                self.state.finishIfRunning()
                self.batchTask = nil
                self.notifyBusyChanged()
            }
        }

        batchTask = Task.detached(priority: .userInitiated) {
            await NotchImageConvertRules.runBatch(
                items: snapshot,
                settings: runSettings,
                shouldContinue: { !flag.isCancelled },
                onItemStarted: onStart,
                onItemFinished: onFinish
            )
            await onDone()
        }
    }

    /// Stops any unstarted file from beginning. Source files and already-written outputs are preserved.
    func cancelBatch() {
        guard state.isRunning else { return }
        cancelFlag.cancel()
        batchTask?.cancel()
        state.cancel()
        notifyBusyChanged()
    }

    /// Lifecycle hook: call when the notch surface collapses or dismisses.
    func handleSurfaceClosed() {
        if state.isRunning {
            cancelBatch()
        }
    }

    func openFilePicker() {
        guard batchTask == nil, !isPickingFiles, state.remainingCapacity > 0 else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = Self.allowedImageContentTypes
        panel.prompt = L10n.t("Chọn ảnh")

        isPickingFiles = true
        notifyBusyChanged()
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { [weak self] response in
            runOnMainActor {
                guard let self else { return }
                self.isPickingFiles = false
                self.notifyBusyChanged()
                if response == .OK {
                    self.enqueue(panel.urls)
                }
            }
        }
    }

    func revealInFinder(_ urls: [URL]) {
        let existing = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !existing.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(existing)
    }

    private func notifyBusyChanged() {
        onRunningChanged?(state.isRunning || isPickingFiles)
    }

    private static var allowedImageContentTypes: [UTType] {
        let types = ImageEngine.inputExtensions.compactMap { UTType(filenameExtension: $0) }
        return types.isEmpty ? [.image] : types
    }

    private static func intakeNotice(_ r: NotchImageConvertRules.IntakeResult) -> String? {
        guard r.hasWarnings else { return nil }
        var parts: [String] = []
        if r.skippedDuplicates > 0 {
            parts.append("\(L10n.t("Bỏ qua "))\(r.skippedDuplicates)\(L10n.t(" tệp trùng"))")
        }
        if r.skippedUnsupported > 0 {
            parts.append("\(L10n.t("Bỏ qua "))\(r.skippedUnsupported)\(L10n.t(" tệp không hỗ trợ"))")
        }
        if r.droppedOverLimit > 0 {
            parts.append("\(L10n.t("Vượt giới hạn 50 ảnh, bỏ qua "))\(r.droppedOverLimit)\(L10n.t(" tệp"))")
        }
        return parts.joined(separator: " · ")
    }
}

/// Thread-safe one-way cancellation flag shared between MainActor and the detached batch loop.
private final class CancelFlag: Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: false)

    var isCancelled: Bool { lock.withLock { $0 } }
    func cancel() { lock.withLock { $0 = true } }
    func reset() { lock.withLock { $0 = false } }
}

/// Dynamic Island image converter page (wide tool body: 612 × 156, inner 584 × 140).
struct NotchImageConvertPage: View {
    var converter: NotchImageConvertModel
    @State private var isDropTargeted = false
    @Environment(\.notchAccent) private var accent

    private typealias N = XFinderTokens.Notch

    var body: some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.tight) {
            headerRow
            contentArea
            footerRow
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
        .onDisappear {
            converter.handleSurfaceClosed()
        }
    }

    // MARK: - Header (title + format + lossy quality + optional longest edge)

    private var headerRow: some View {
        HStack(spacing: XFinderTokens.Space.tight) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 12, weight: .medium))
                .opacity(0.8)
            Text(L10n.t("Chuyển ảnh"))
                .font(XFinderTokens.Font.row)
            if converter.state.totalCount > 0 {
                Text("\(converter.state.totalCount)/\(NotchImageConvertRules.maxBatchSize)")
                    .font(XFinderTokens.Font.caption)
                    .monospacedDigit()
                    .opacity(0.55)
            }

            Spacer(minLength: XFinderTokens.Space.tight)

            if converter.hasEncoders {
                formatMenu
                if converter.settings.showsQualityControl {
                    qualityMenu
                }
                maxEdgeMenu
            }
        }
        .frame(height: 22)
    }

    private var formatMenu: some View {
        Menu {
            ForEach(converter.availableFormats, id: \.rawValue) { target in
                Button {
                    converter.setFormat(target)
                } label: {
                    if target == converter.settings.format {
                        Label(target.label, systemImage: "checkmark")
                    } else {
                        Text(target.label)
                    }
                }
            }
        } label: {
            optionCapsule(text: converter.settings.format.label, systemImage: "doc.badge.gearshape")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(converter.state.isRunning)
        .help(L10n.t("Định dạng đầu ra"))
        .accessibilityLabel(L10n.t("Định dạng đầu ra"))
    }

    private var qualityMenu: some View {
        let pct = Int((converter.settings.quality * 100).rounded())
        return Menu {
            ForEach(NotchImageConvertRules.qualityPresets, id: \.self) { preset in
                let label = "\(Int((preset * 100).rounded()))%"
                Button {
                    converter.setQuality(preset)
                } label: {
                    if abs(preset - converter.settings.quality) < 0.005 {
                        Label(label, systemImage: "checkmark")
                    } else {
                        Text(label)
                    }
                }
            }
        } label: {
            optionCapsule(text: "\(L10n.t("Chất lượng "))\(pct)%", systemImage: "slider.horizontal.3")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(converter.state.isRunning)
        .help(L10n.t("Chất lượng nén"))
        .accessibilityLabel(L10n.t("Chất lượng nén"))
    }

    private var maxEdgeMenu: some View {
        let currentLabel: String
        if let px = converter.settings.maxLongestEdge {
            currentLabel = "\(px) px"
        } else {
            currentLabel = L10n.t("Giữ kích thước")
        }
        return Menu {
            Button {
                converter.setMaxLongestEdge(nil)
            } label: {
                if converter.settings.maxLongestEdge == nil {
                    Label(L10n.t("Giữ kích thước"), systemImage: "checkmark")
                } else {
                    Text(L10n.t("Giữ kích thước"))
                }
            }
            Divider()
            ForEach(NotchImageConvertRules.maxEdgePresets, id: \.self) { px in
                Button {
                    converter.setMaxLongestEdge(px)
                } label: {
                    if converter.settings.maxLongestEdge == px {
                        Label("\(px) px", systemImage: "checkmark")
                    } else {
                        Text("\(px) px")
                    }
                }
            }
        } label: {
            optionCapsule(text: currentLabel, systemImage: "arrow.up.left.and.arrow.down.right")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(converter.state.isRunning)
        .help(L10n.t("Cạnh dài tối đa"))
        .accessibilityLabel(L10n.t("Cạnh dài tối đa"))
    }

    private func optionCapsule(text: String, systemImage: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .medium))
                .opacity(0.75)
            Text(text)
                .font(XFinderTokens.Font.caption)
                .monospacedDigit()
                .lineLimit(1)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 7)
        .frame(height: 20)
        .background(Capsule().fill(N.capsule))
        .overlay(Capsule().strokeBorder(N.cardStroke, lineWidth: 1))
    }

    // MARK: - Content area (empty drop zone or per-file result list)

    @ViewBuilder private var contentArea: some View {
        if !converter.hasEncoders {
            emptyStateCard(
                icon: "exclamationmark.triangle",
                message: L10n.t("Máy này không có trình mã hóa ảnh khả dụng."),
                showPickButton: false
            )
        } else if converter.state.items.isEmpty {
            emptyStateCard(
                icon: "photo.badge.plus",
                message: L10n.t("Kéo thả hoặc chọn tối đa 50 ảnh để chuyển định dạng"),
                showPickButton: true
            )
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
                    ForEach(converter.state.items) { item in
                        itemRow(item)
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: XFinderTokens.Radius.control, style: .continuous)
                    .fill(N.capsule)
            )
            .overlay(
                RoundedRectangle(cornerRadius: XFinderTokens.Radius.control, style: .continuous)
                    .strokeBorder(isDropTargeted ? accent : N.cardStroke, lineWidth: isDropTargeted ? 1.5 : 1)
            )
        }
    }

    private func emptyStateCard(icon: String, message: String, showPickButton: Bool) -> some View {
        VStack(spacing: XFinderTokens.Space.tight) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(isDropTargeted ? accent : N.toolbarIcon)
            Text(message)
                .font(XFinderTokens.Font.caption)
                .opacity(0.75)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            if showPickButton {
                Button(L10n.t("Chọn ảnh")) {
                    converter.openFilePicker()
                }
                .buttonStyle(NotchPillButtonStyle(primary: true))
                .accessibilityLabel(L10n.t("Chọn ảnh"))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, XFinderTokens.Space.inline)
        .background(
            RoundedRectangle(cornerRadius: XFinderTokens.Radius.control, style: .continuous)
                .fill(N.capsule)
        )
        .overlay(
            RoundedRectangle(cornerRadius: XFinderTokens.Radius.control, style: .continuous)
                .strokeBorder(
                    isDropTargeted ? accent : N.cardStroke,
                    style: StrokeStyle(lineWidth: isDropTargeted ? 1.5 : 1, dash: [4, 3])
                )
        )
    }

    private func itemRow(_ item: NotchImageConvertRules.BatchItem) -> some View {
        HStack(spacing: XFinderTokens.Space.tight) {
            statusIcon(item.status)
                .frame(width: 14, height: 14)

            Text(item.fileName)
                .font(XFinderTokens.Font.caption)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 190, alignment: .leading)

            Spacer(minLength: 4)

            statusDetail(item)

            if !converter.state.isRunning {
                Button {
                    converter.removeItem(id: item.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(N.toolbarIcon)
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(L10n.t("Xóa khỏi danh sách"))
                .accessibilityLabel(L10n.t("Xóa khỏi danh sách"))
            }
        }
        .padding(.horizontal, 6)
        .frame(height: 22)
    }

    @ViewBuilder private func statusIcon(_ status: NotchImageConvertRules.ItemStatus) -> some View {
        switch status {
        case .pending:
            Circle()
                .fill(N.dotDim)
                .frame(width: 5, height: 5)
        case .running:
            ProgressView()
                .controlSize(.mini)
                .tint(.white)
        case .succeeded:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 11))
                .foregroundColor(Color(nsColor: .systemGreen))
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundColor(Color(nsColor: .systemOrange))
        case .cancelled:
            Image(systemName: "slash.circle")
                .font(.system(size: 11))
                .foregroundColor(N.toolbarIcon)
        }
    }

    @ViewBuilder private func statusDetail(_ item: NotchImageConvertRules.BatchItem) -> some View {
        switch item.status {
        case .pending:
            Text(L10n.t("Chờ"))
                .font(XFinderTokens.Font.caption)
                .opacity(0.45)
        case .running:
            Text(L10n.t("Đang chuyển"))
                .font(XFinderTokens.Font.caption)
                .foregroundColor(accent)
        case .succeeded(let output):
            HStack(spacing: 4) {
                Text(output.lastPathComponent)
                    .font(XFinderTokens.Font.caption)
                    .opacity(0.75)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Button {
                    converter.revealInFinder([output])
                } label: {
                    Image(systemName: "folder")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(Color.white.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .help(L10n.t("Hiện trong Finder"))
                .accessibilityLabel(L10n.t("Hiện trong Finder"))
            }
        case .failed(let failure):
            let text = "\(L10n.t(failure.messageKey))\(failure.detail)"
            Text(text)
                .font(XFinderTokens.Font.caption)
                .foregroundColor(Color(nsColor: .systemOrange))
                .lineLimit(1)
                .truncationMode(.tail)
                .help(text)
        case .cancelled:
            Text(L10n.t("Đã hủy"))
                .font(XFinderTokens.Font.caption)
                .opacity(0.5)
        }
    }

    // MARK: - Footer (progress/status + actions)

    private var footerRow: some View {
        HStack(spacing: XFinderTokens.Space.tight) {
            footerStatus
            Spacer(minLength: XFinderTokens.Space.tight)
            footerActions
        }
        .frame(height: 22)
    }

    @ViewBuilder private var footerStatus: some View {
        if converter.state.isRunning {
            HStack(spacing: XFinderTokens.Space.tight) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(N.progressTrack)
                        Capsule()
                            .fill(accent)
                            .frame(width: max(0, geo.size.width * CGFloat(converter.state.fraction)))
                    }
                }
                .frame(width: 84, height: 4)
                Text("\(converter.state.finishedCount)/\(converter.state.totalCount)")
                    .font(XFinderTokens.Font.caption)
                    .monospacedDigit()
                    .opacity(0.75)
            }
        } else if let notice = converter.notice {
            Text(notice)
                .font(XFinderTokens.Font.caption)
                .foregroundColor(Color(nsColor: .systemOrange))
                .lineLimit(1)
                .truncationMode(.tail)
                .help(notice)
        } else if converter.state.phase == .finished || converter.state.phase == .cancelled {
            let prefix = converter.state.phase == .cancelled ? L10n.t("Đã hủy · ") : ""
            Text("\(prefix)\(L10n.t("Hoàn tất "))\(converter.state.succeededCount)/\(converter.state.totalCount)")
                .font(XFinderTokens.Font.caption)
                .monospacedDigit()
                .opacity(0.75)
                .lineLimit(1)
        } else if converter.state.totalCount > 0 {
            Text(L10n.t("Giữ nguyên tệp nguồn"))
                .font(XFinderTokens.Font.caption)
                .opacity(0.5)
                .lineLimit(1)
        }
    }

    @ViewBuilder private var footerActions: some View {
        if converter.state.isRunning {
            Button(L10n.t("Hủy")) {
                converter.cancelBatch()
            }
            .buttonStyle(NotchPillButtonStyle(primary: false))
            .accessibilityLabel(L10n.t("Hủy"))
        } else {
            HStack(spacing: XFinderTokens.Space.tight) {
                if !converter.state.items.isEmpty && converter.state.remainingCapacity > 0 && converter.hasEncoders {
                    Button(L10n.t("Thêm")) {
                        converter.openFilePicker()
                    }
                    .buttonStyle(NotchPillButtonStyle(primary: false))
                    .accessibilityLabel(L10n.t("Thêm"))
                }
                if !converter.state.items.isEmpty {
                    Button(L10n.t("Xóa danh sách")) {
                        converter.clearItems()
                    }
                    .buttonStyle(NotchPillButtonStyle(primary: false))
                    .accessibilityLabel(L10n.t("Xóa danh sách"))
                }
                if !converter.state.outputs.isEmpty {
                    Button(L10n.t("Mở trong Finder")) {
                        converter.revealInFinder(converter.state.outputs)
                    }
                    .buttonStyle(NotchPillButtonStyle(primary: false))
                    .accessibilityLabel(L10n.t("Mở trong Finder"))
                }
                if converter.canConvert {
                    Button(L10n.t("Chuyển đổi")) {
                        converter.startBatch()
                    }
                    .buttonStyle(NotchPillButtonStyle(primary: true))
                    .accessibilityLabel(L10n.t("Chuyển đổi"))
                }
            }
        }
    }

    // MARK: - Drop Handling

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard !converter.state.isRunning, !providers.isEmpty else { return false }
        let fileProviders = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !fileProviders.isEmpty else { return false }

        let group = DispatchGroup()
        let collected = LockedURLs()
        for provider in fileProviders {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    collected.append(url)
                } else if let url = item as? URL {
                    collected.append(url)
                }
            }
        }
        group.notify(queue: .main) {
            converter.enqueue(collected.snapshot())
        }
        return true
    }
}

private final class LockedURLs: Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: [URL]())
    func append(_ url: URL) { lock.withLock { $0.append(url) } }
    func snapshot() -> [URL] { lock.withLock { $0 } }
}
