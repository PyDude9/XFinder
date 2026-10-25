import AppKit
import SwiftUI

/// XF-T30 W7 — Get Info for a disk (spec §5/§6: format, capacity, available with purgeable apart, used, mount
/// point). Read in the background with a 2 s cap so an unresponsive network volume never blocks the window — it
/// still opens immediately, just without the "Còn trống" row (spec: "a network disk that doesn't answer leaves
/// free space out instead of making the app wait"). One window per volume path, same reuse-on-second-⌘I pattern
/// `GetInfoWindowController` already uses for files.
@MainActor final class VolumeInfoWindowController: NSObject, NSWindowDelegate {
    static let shared = VolumeInfoWindowController()

    private static let contentSize = NSSize(width: 320, height: 260)

    private var windows: [ObjectIdentifier: (window: NSWindow, model: VolumeInfoModel)] = [:]

    private override init() { super.init() }

    func show(volumePath: String) {
        if let existing = windows.first(where: { $0.value.model.volumePath == volumePath }) {
            existing.value.window.makeKeyAndOrderFront(nil)
            return
        }
        let model = VolumeInfoModel(volumePath: volumePath)
        let window = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.contentSize),
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.title = (volumePath as NSString).lastPathComponent
        window.delegate = self
        let hosting = NSHostingView(rootView: VolumeInfoRootView(model: model))
        hosting.sizingOptions = []
        window.contentView = hosting
        window.contentMinSize = Self.contentSize
        window.center()
        windows[ObjectIdentifier(window)] = (window, model)
        model.start()
        window.makeKeyAndOrderFront(nil)
    }

    nonisolated func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow else { return }
        let id = ObjectIdentifier(closing)
        runOnMainActor { [weak self] in
            self?.windows.removeValue(forKey: id)
        }
    }
}

// MARK: - Model

@MainActor @Observable final class VolumeInfoModel {
    struct Facts: Equatable, Sendable {
        let format: String?
        let capacity: Int64?
        /// nil when the background read never finished within the cap (spec §6: left out, never blocks).
        let available: Int64?
        let purgeable: Int64?
        let mountPoint: String
    }

    static let backgroundReadTimeout: Duration = .seconds(2)

    let volumePath: String
    private(set) var facts: Facts?
    private(set) var timedOut = false

    init(volumePath: String) {
        self.volumePath = volumePath
    }

    func start() {
        let path = volumePath
        Task.detached(priority: .userInitiated) {
            // The format/capacity/mount-point read never blocks (those resource keys are cheap even on a stuck
            // network share); only `.volumeAvailableCapacityKey` can hang waiting on a round trip. Reading it on
            // its own task and racing that against a 2 s timer means the window always shows everything else
            // immediately, with "Còn trống" simply absent if the volume never answers in time (spec §6).
            let base = Self.readFactsSync(path: path, includeAvailable: false)
            let available = await Self.readAvailableWithTimeout(path: path)
            let withAvailable = Facts(format: base.format, capacity: base.capacity, available: available.value,
                                      purgeable: available.purgeable, mountPoint: base.mountPoint)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.facts = withAvailable
                self.timedOut = available.value == nil
            }
        }
    }

    /// Reads just the available/purgeable pair, racing it against `backgroundReadTimeout` via `withTaskGroup` —
    /// the first task to finish (the real read, or the timer returning `nil`) wins and the other is cancelled.
    nonisolated private static func readAvailableWithTimeout(path: String) async -> (value: Int64?, purgeable: Int64?) {
        await withTaskGroup(of: (Int64?, Int64?).self) { group in
            group.addTask { Self.readAvailable(path: path) }
            group.addTask {
                try? await Task.sleep(for: VolumeInfoModel.backgroundReadTimeout)
                return (nil, nil)
            }
            let result = await group.next() ?? (nil, nil)
            group.cancelAll()
            return result
        }
    }

    nonisolated private static func readAvailable(path: String) -> (Int64?, Int64?) {
        let url = URL(fileURLWithPath: path)
        guard let values = try? url.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey,
        ]) else { return (nil, nil) }
        let importantAvailable = values.volumeAvailableCapacityForImportantUsage.map { Int64($0) }
        let totalAvailable = values.volumeAvailableCapacity.map { Int64($0) }
        // `volumeAvailableCapacityForImportantUsage` already excludes purgeable space (Apple's own "important
        // usage" definition); `volumeAvailableCapacity` includes it — the difference is what Finder calls
        // "purgeable" (spec §6: "available space, purgeable called out separately").
        let purgeable: Int64?
        if let importantAvailable, let totalAvailable, totalAvailable >= importantAvailable {
            purgeable = totalAvailable - importantAvailable
        } else {
            purgeable = nil
        }
        return (importantAvailable ?? totalAvailable, purgeable)
    }

    /// Format/capacity/mount point only — cheap resource keys that never hang even on a stuck network share;
    /// `available`/`purgeable` are read separately and raced against the 2 s cap (see `readAvailableWithTimeout`).
    nonisolated private static func readFactsSync(path: String, includeAvailable: Bool) -> Facts {
        let url = URL(fileURLWithPath: path)
        guard let values = try? url.resourceValues(forKeys: [
            .volumeLocalizedFormatDescriptionKey, .volumeTotalCapacityKey, .volumeURLKey,
        ]) else {
            return Facts(format: nil, capacity: nil, available: nil, purgeable: nil, mountPoint: path)
        }
        return Facts(
            format: values.volumeLocalizedFormatDescription,
            capacity: values.volumeTotalCapacity.map { Int64($0) },
            available: nil,
            purgeable: nil,
            mountPoint: values.volume?.path ?? path
        )
    }
}

// MARK: - View

struct VolumeInfoRootView: View {
    @Bindable var model: VolumeInfoModel

    var body: some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
            if let facts = model.facts {
                LabeledContent(L10n.t("Định dạng:"), value: facts.format ?? L10n.t("Không rõ"))
                if let capacity = facts.capacity {
                    LabeledContent(L10n.t("Dung lượng:"), value: sizeText(capacity))
                }
                if let used = usedSize(facts) {
                    LabeledContent(L10n.t("Đã dùng:"), value: sizeText(used))
                }
                if let available = facts.available {
                    LabeledContent(L10n.t("Còn trống:"), value: sizeText(available))
                } else {
                    LabeledContent(L10n.t("Còn trống:"), value: L10n.t("Không lấy được (ổ mạng không phản hồi)"))
                }
                if let purgeable = facts.purgeable, purgeable > 0 {
                    LabeledContent(L10n.t("Có thể giải phóng:"), value: sizeText(purgeable))
                }
                LabeledContent(L10n.t("Điểm gắn:"), value: facts.mountPoint)
            } else {
                ProgressView().padding(.top, XFinderTokens.Space.section)
            }
        }
        .padding(XFinderTokens.Space.page)
        .frame(minWidth: 320, minHeight: 200)
    }

    private func usedSize(_ facts: VolumeInfoModel.Facts) -> Int64? {
        guard let capacity = facts.capacity, let available = facts.available, capacity >= available else { return nil }
        return capacity - available
    }

    private func sizeText(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
