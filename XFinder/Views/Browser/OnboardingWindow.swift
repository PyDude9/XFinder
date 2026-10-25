import SwiftUI
import AppKit

/// XF-T30 W4 — the Welcome window (Q-T30-9: Welcome · Folder access · Full Disk Access (skippable) · Layout).
/// W4 builder (settings).
@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    static let shared = OnboardingWindowController()

    private static let contentSize = NSSize(width: 480, height: 420)
    private var window: NSWindow?

    private override init() { super.init() }

    /// First browser window of a fresh install, or Privacy ▸ "Show Welcome Window…". `opened(preset, folders)` lets
    /// the caller open the chosen layout with the panes pointed at whichever of the three onboarding folders were
    /// granted (in Desktop/Documents/Downloads order — "ngăn mở các thư mục đã cho phép", contract §3). Replaying
    /// never re-asks for an OS-level grant already held (FileOctopus R58) — step 2 shows every folder's CURRENT
    /// status instead of blindly re-prompting.
    func show(opened: @escaping @MainActor (PanePreset, [String]) -> Void) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let panel = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.contentSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.title = L10n.t("Chào mừng đến với XFinder")
        panel.delegate = self
        let model = OnboardingModel(
            finish: { [weak self] preset, folders in
                BrowserSettings2.setOnboardingDone(true)
                opened(preset, folders)
                self?.close()
            },
            close: { [weak self] in self?.close() }
        )
        let hosting = NSHostingView(rootView: OnboardingRootView(model: model))
        hosting.sizingOptions = []
        panel.contentView = hosting
        panel.contentMinSize = Self.contentSize
        panel.center()
        window = panel
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func close() {
        window?.close()
    }

    nonisolated func windowWillClose(_ notification: Notification) {
        runOnMainActor { [weak self] in self?.window = nil }
    }

    /// Opens a new browser window, switches it to `preset`'s layout, then points each resulting pane at one of
    /// `folders` in order (extra panes beyond `folders.count` keep whatever `applyPreset` gave them — the window's
    /// own Home default — since there is nothing left to assign them). The only public hook into W1's pane tree is
    /// `BrowserCommand.presetSingle/.../.presetGrid` through `perform` (`BrowserWindowModel.applyPreset` itself is
    /// private) — this file does not own `BrowserWindowModel.swift`, so it goes through that command surface rather
    /// than adding a new entry point to another builder's file.
    static func openWindow(preset: PanePreset, folders: [String]) {
        let model = BrowserWindowController.shared.openWindow(path: folders.first)
        let command: BrowserCommand
        switch preset {
        case .single: command = .presetSingle
        case .sideBySide: command = .presetSideBySide
        case .stacked: command = .presetStacked
        case .grid: command = .presetGrid
        }
        _ = model.perform(command)
        for (paneID, path) in zip(model.tree.panes, folders) {
            model.panes[paneID]?.navigate(to: path)
        }
    }
}

/// `BrowserSettings.onboardingDone` is a get-only static var on the shared W4-pure-contract type — this file does
/// not own `BrowserSettings.swift`, so the one write this window needs goes straight at the same UserDefaults key
/// the ONE reader already uses, keeping "one key" (CLAUDE.md rule 7) intact without touching another builder's file.
private enum BrowserSettings2 {
    static func setOnboardingDone(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: "fileBrowser.onboardingDone")
    }
}

// MARK: - Model

@MainActor @Observable
private final class OnboardingModel {
    enum Step: Int, CaseIterable { case welcome, folders, fullDiskAccess, layout }

    var step: Step = .welcome
    var folderStatus: [String: Bool] = [:]
    var fullDiskAccess: FullDiskAccessStatus = .couldNotCheck
    var selectedPreset: PanePreset = .single

    let finish: (PanePreset, [String]) -> Void
    let close: () -> Void

    static let folders: [(key: String, nameKey: String)] = [
        ("Desktop", "Màn hình nền"), ("Documents", "Tài liệu"), ("Downloads", "Thư mục Tải về"),
    ]

    /// The granted folders' full paths, in the fixed Desktop/Documents/Downloads order (feeds the opened window's
    /// panes — a folder never granted or still unchecked is left out, not guessed at).
    var grantedFolderPaths: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return Self.folders.filter { folderStatus[$0.key] == true }.map { home.appendingPathComponent($0.key).path }
    }

    init(finish: @escaping (PanePreset, [String]) -> Void, close: @escaping () -> Void) {
        self.finish = finish
        self.close = close
    }

    func advance() {
        guard let next = Step(rawValue: step.rawValue + 1) else { return }
        step = next
        if next == .fullDiskAccess { fullDiskAccess = FullDiskAccessProbe.check() }
    }

    /// Reading the folder is the real TCC prompt the first time only; a folder already granted in an earlier run
    /// just re-reads as granted without a second system dialog (R58: never fake-re-prompt an OS grant already held).
    func allow(_ folderKey: String) {
        Task.detached(priority: .utility) { [weak self] in
            let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(folderKey)
            let granted = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) != nil
            await MainActor.run { self?.folderStatus[folderKey] = granted }
        }
    }

    func allowAll() {
        for folder in Self.folders { allow(folder.key) }
    }
}

// MARK: - Views

private struct OnboardingRootView: View {
    let model: OnboardingModel

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch model.step {
                case .welcome: WelcomeStep(model: model)
                case .folders: FolderAccessStep(model: model)
                case .fullDiskAccess: FullDiskAccessStep(model: model)
                case .layout: LayoutStep(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(XFinderTokens.Space.section)

            stepDots
                .padding(.bottom, XFinderTokens.Space.row)
        }
        .background(XFinderTokens.Settings.contentBackground)
    }

    private var stepDots: some View {
        HStack(spacing: XFinderTokens.Space.tight) {
            ForEach(OnboardingModel.Step.allCases, id: \.self) { step in
                Circle()
                    .fill(step == model.step ? Color.accentColor : XFinderTokens.Fill.inset)
                    .frame(width: 6, height: 6)
            }
        }
    }
}

private struct WelcomeStep: View {
    let model: OnboardingModel

    var body: some View {
        VStack(spacing: XFinderTokens.Space.section) {
            Spacer()
            Image(systemName: "rectangle.split.2x2")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)
            Text(L10n.t("Chào mừng đến với XFinder")).font(XFinderTokens.Font.pageTitle)
            Text(L10n.t("Duyệt, gom và chép tệp giữa nhiều thư mục trong một cửa sổ — như Finder, chia được tới 16 ngăn."))
                .font(XFinderTokens.Font.pageSubtitle)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button(L10n.t("Tiếp tục")) { model.advance() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
    }
}

private struct FolderAccessStep: View {
    let model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.section) {
            Text(L10n.t("Quyền thư mục")).font(XFinderTokens.Font.pageTitle)
            Text(L10n.t("Cho phép XFinder đọc các thư mục hay dùng. Mỗi nút gọi đúng hộp thoại hệ thống — không gì tự cấp quyền."))
                .font(XFinderTokens.Font.pageSubtitle).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(OnboardingModel.folders.enumerated()), id: \.offset) { index, folder in
                    HStack {
                        Text(L10n.t(folder.nameKey)).font(XFinderTokens.Font.row)
                        Spacer()
                        if model.folderStatus[folder.key] == true {
                            Label(L10n.t("Đã cho phép"), systemImage: "checkmark.circle.fill")
                                .font(XFinderTokens.Font.caption).foregroundColor(.green)
                        } else {
                            Button(L10n.t("Cho phép")) { model.allow(folder.key) }.controlSize(.small)
                        }
                    }
                    .settingsRow()
                    if index != OnboardingModel.folders.count - 1 { SettingsDivider() }
                }
            }
            .padding(.horizontal, XFinderTokens.Settings.cardInset)
            .background(RoundedRectangle(cornerRadius: XFinderTokens.Settings.cardRadius, style: .continuous)
                .fill(XFinderTokens.Settings.cardFill))

            Button(L10n.t("Cho phép tất cả")) { model.allowAll() }.controlSize(.small)

            Spacer()
            HStack {
                Spacer()
                Button(L10n.t("Tiếp tục")) { model.advance() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        }
    }
}

private struct FullDiskAccessStep: View {
    let model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.section) {
            Text(L10n.t("Full Disk Access (tuỳ chọn)")).font(XFinderTokens.Font.pageTitle)
            Text(L10n.t("Cho mọi thư mục trên máy, kể cả thư mục của ứng dụng khác. Có thể bỏ qua và bật sau trong Cài đặt trình duyệt ▸ Quyền riêng tư."))
                .font(XFinderTokens.Font.pageSubtitle).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Text(L10n.t("Trạng thái hiện tại")).font(XFinderTokens.Font.row)
                Spacer()
                Text(L10n.t(FullDiskAccessStatus.titleKey(model.fullDiskAccess)))
                    .font(XFinderTokens.Font.rowValue).foregroundColor(.secondary)
            }
            .settingsRow()

            Button(L10n.t("Mở Cài đặt hệ thống…")) {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                    NSWorkspace.shared.open(url)
                }
            }
            .controlSize(.small)

            Spacer()
            HStack {
                Button(L10n.t("Tiếp tục không cần Full Disk Access")) { model.advance() }
                    .controlSize(.large)
                Spacer()
                Button(L10n.t("Tiếp tục")) { model.advance() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        }
    }
}

private struct LayoutStep: View {
    let model: OnboardingModel

    private let presets: [(preset: PanePreset, titleKey: String, symbol: String)] = [
        (.single, "Một ngăn", "square"),
        (.sideBySide, "Cạnh nhau", "rectangle.split.2x1"),
        (.stacked, "Chồng lên nhau", "rectangle.split.1x2"),
        (.grid, "Lưới 2×2", "square.grid.2x2"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.section) {
            Text(L10n.t("Chọn bố cục")).font(XFinderTokens.Font.pageTitle)
            Text(L10n.t("Cửa sổ đầu tiên sẽ mở các thư mục bạn vừa cho phép."))
                .font(XFinderTokens.Font.pageSubtitle).foregroundColor(.secondary)

            HStack(spacing: XFinderTokens.Space.inline) {
                ForEach(presets, id: \.preset) { entry in
                    layoutCard(entry)
                }
            }

            Spacer()
            HStack {
                Spacer()
                Button(L10n.t("Mở XFinder")) { model.finish(model.selectedPreset, model.grantedFolderPaths) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        }
    }

    private func layoutCard(_ entry: (preset: PanePreset, titleKey: String, symbol: String)) -> some View {
        let isSelected = model.selectedPreset == entry.preset
        return Button {
            model.selectedPreset = entry.preset
        } label: {
            VStack(spacing: XFinderTokens.Space.tight) {
                Image(systemName: entry.symbol).font(.system(size: 28))
                Text(L10n.t(entry.titleKey)).font(XFinderTokens.Font.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(XFinderTokens.Space.row)
            .background(RoundedRectangle(cornerRadius: XFinderTokens.Radius.tile, style: .continuous)
                .fill(isSelected ? XFinderTokens.Fill.focus : XFinderTokens.Fill.inset))
        }
        .buttonStyle(.plain)
    }
}
