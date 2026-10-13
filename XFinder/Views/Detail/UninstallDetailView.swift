import SwiftUI
import AppKit

/// F2 — Gỡ ứng dụng. The user comes here to remove ONE app and what it left in their Library. The list under the app
/// is the preview; the button moves only what is ticked, one item at a time, and each row then says what happened.
struct UninstallDetailView: View {
    @State private var apps: [AppUninstaller.InstalledApp] = []
    @State private var query = ""
    @State private var selected: AppUninstaller.InstalledApp?
    @State private var refusal: Uninstall.Refusal?
    @State private var candidates: [Uninstall.Candidate] = []
    @State private var sizes: [String: Int64] = [:]
    @State private var chosen: Set<String> = []
    @State private var outcomes: [String: Uninstall.ItemOutcome] = [:]
    @State private var working = false
    @State private var summary: String?

    private var filtered: [AppUninstaller.InstalledApp] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return apps }
        return apps.filter { $0.name.localizedCaseInsensitiveContains(q) || $0.bundleID.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: XFinderTokens.Space.section) {
                PageHeader(icon: "xmark.bin",
                           title: L10n.t("Gỡ ứng dụng"),
                           subtitle: L10n.t("Chuyển một app và những gì nó để lại trong Thư viện của bạn vào Thùng rác — xem từng mục trước."))
                pickerSection
                if let app = selected {
                    Divider().padding(.horizontal, XFinderTokens.Space.page)
                    detailSection(app)
                }
                Divider().padding(.horizontal, XFinderTokens.Space.page)
                InlineNote(text: L10n.t("XFinder chỉ chọn sẵn những gì mang đúng mã nhận dạng (bundle id) của app. Thư mục trùng tên app chỉ là đoán nên để trống. Container của app (Thư viện ▸ Containers) được macOS bảo vệ — XFinder không chuyển được (đã đo); bấm Hiện trong Finder rồi kéo vào Thùng rác. Không gỡ app của Apple, app đang chạy hay chính XFinder."))
                    .padding(.horizontal, XFinderTokens.Space.page)
            }
            .padding(.bottom, XFinderTokens.Space.section)
            .pageWidthSafe()
        }
        .task { await reloadApps() }
    }

    // MARK: Picking an app

    private var pickerSection: some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
            SectionHeader(icon: "app.dashed", title: L10n.t("Chọn ứng dụng"),
                          subtitle: "\(apps.count)\(L10n.t(" app trong Applications"))")
            VStack(alignment: .leading, spacing: XFinderTokens.Space.tight) {
                TextField(L10n.t("Tìm theo tên hoặc bundle id"), text: $query)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 320)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(filtered) { app in appRow(app) }
                    }
                }
                .frame(height: 220)
                .background(RoundedRectangle(cornerRadius: XFinderTokens.Radius.tile, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12)))
            }
            .padding(.horizontal, XFinderTokens.Space.page)
        }
    }

    private func appRow(_ app: AppUninstaller.InstalledApp) -> some View {
        Button { Task { await select(app) } } label: {
            HStack(spacing: XFinderTokens.Space.tight) {
                Image(nsImage: ClipboardAppIcon.fileIcon(forPath: app.url.path)).resizable().frame(width: 20, height: 20)
                Text(app.name).font(XFinderTokens.Font.row).lineLimit(1)
                Text(app.bundleID).font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                    .lineLimit(1).truncationMode(.middle)
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(selected == app ? Color.accentColor.opacity(0.15) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(app.name), \(app.bundleID)")
    }

    // MARK: One app

    @ViewBuilder private func detailSection(_ app: AppUninstaller.InstalledApp) -> some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
            SectionHeader(icon: "trash", title: "\(L10n.t("Gỡ "))\(app.name)",
                          subtitle: L10n.t("Bỏ chọn mục nào bạn muốn giữ lại."))
            VStack(alignment: .leading, spacing: XFinderTokens.Space.tight) {
                if let refusal {
                    refusalNote(refusal, app: app)
                } else {
                    itemRow(path: app.url.path, title: app.url.path, caption: L10n.t("Ứng dụng"), tickable: true, refusedAlways: false)
                    ForEach(Uninstall.Location.allCases, id: \.self) { loc in
                        let items = candidates.filter { $0.location == loc }
                        if !items.isEmpty {
                            Text(loc.rawValue).font(XFinderTokens.Font.caption).bold().foregroundColor(.secondary).padding(.top, 4)
                            ForEach(items, id: \.fileName) { c in
                                itemRow(path: AppUninstaller.url(of: c).path, title: c.fileName, caption: matchCaption(c),
                                        tickable: !c.location.alwaysRefused, refusedAlways: c.location.alwaysRefused)
                            }
                        }
                    }
                    if candidates.isEmpty {
                        Text(L10n.t("Không tìm thấy file nào app này để lại trong Thư viện."))
                            .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                    }
                    HStack {
                        Button("\(L10n.t("Chuyển "))\(chosen.count)\(L10n.t(" mục vào Thùng rác")) · \(ByteCountFormatter.string(fromByteCount: chosenBytes, countStyle: .file))") {
                            Task { await moveToTrash() }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(chosen.isEmpty || working)
                        if working { ProgressView().controlSize(.small) }
                    }
                    .padding(.top, 4)
                }
                if let summary {
                    InlineNote(kind: outcomes.values.contains { if case .trashed = $0 { return false } else { return true } } ? .warning : .success,
                               text: summary)
                }
            }
            .padding(.horizontal, XFinderTokens.Space.page)
        }
    }

    private var chosenBytes: Int64 { chosen.reduce(0) { $0 + (sizes[$1] ?? 0) } }

    private func itemRow(path: String, title: String, caption: String, tickable: Bool, refusedAlways: Bool) -> some View {
        HStack(spacing: XFinderTokens.Space.tight) {
            Toggle("", isOn: Binding(get: { chosen.contains(path) },
                                     set: { on in if on { chosen.insert(path) } else { chosen.remove(path) } }))
                .toggleStyle(.checkbox).labelsHidden()
                .disabled(!tickable || working || outcomes[path] == .trashed)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(XFinderTokens.Font.row).lineLimit(1).truncationMode(.middle)
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                Text(caption).font(XFinderTokens.Font.caption).foregroundColor(.secondary).lineLimit(1)
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            if let o = outcomes[path] {
                outcomeBadge(o)
            } else {
                Text(sizes[path].map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "—")
                    .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
            }
            if refusedAlways || outcomes[path] == .protected {
                Button(L10n.t("Hiện trong Finder")) {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                }
                .controlSize(.small)
            }
        }
    }

    @ViewBuilder private func outcomeBadge(_ o: Uninstall.ItemOutcome) -> some View {
        switch o {
        case .trashed: Text(L10n.t("Đã vào Thùng rác")).font(XFinderTokens.Font.caption).foregroundColor(.green)
        case .protected: Text(L10n.t("macOS chặn")).font(XFinderTokens.Font.caption).foregroundColor(.orange)
        case .missing: Text(L10n.t("Đã không còn")).font(XFinderTokens.Font.caption).foregroundColor(.secondary)
        case .failed(let m): Text(m).font(XFinderTokens.Font.caption).foregroundColor(.red).lineLimit(1).help(m)
        }
    }

    private func matchCaption(_ c: Uninstall.Candidate) -> String {
        var s: String
        switch c.match {
        case .exact: s = L10n.t("Đúng bundle id")
        case .helper: s = L10n.t("Thành phần phụ của app (helper, extension)")
        case .group: s = L10n.t("Nhóm dữ liệu dùng chung của app")
        case .name: s = L10n.t("Trùng tên app — chỉ là đoán")
        case .launchAgent: s = L10n.t("Tác vụ chạy nền của app")
        }
        if c.location.alwaysRefused { s += " · " + L10n.t("macOS bảo vệ — dùng Finder") }
        else if c.location.isProtected { s += " · " + L10n.t("macOS có thể chặn") }
        return s
    }

    @ViewBuilder private func refusalNote(_ r: Uninstall.Refusal, app: AppUninstaller.InstalledApp) -> some View {
        switch r {
        case .running:
            InlineNote(kind: .warning, text: L10n.t("App đang chạy. Thoát app trước để nó không ghi tiếp vào những file sắp chuyển đi."),
                       buttonTitle: L10n.t("Thoát app")) {
                AppUninstaller.requestQuit(bundleID: app.bundleID)
                Task { try? await Task.sleep(nanoseconds: 1_500_000_000); await select(app) }
            }
        case .apple: InlineNote(kind: .warning, text: L10n.t("Đây là app của Apple — XFinder không gỡ app hệ thống."))
        case .system: InlineNote(kind: .warning, text: L10n.t("App nằm trong thư mục hệ thống — XFinder không gỡ."))
        case .itself: InlineNote(kind: .warning, text: L10n.t("Không thể tự gỡ XFinder từ chính nó — kéo XFinder vào Thùng rác trong Finder."))
        case .notAnApp: InlineNote(kind: .warning, text: L10n.t("Không đọc được thông tin của app này."))
        }
    }

    // MARK: Actions

    private func reloadApps() async {
        apps = await Task.detached(priority: .userInitiated) { AppUninstaller.installedApps() }.value
    }

    private func select(_ app: AppUninstaller.InstalledApp) async {
        selected = app
        summary = nil
        outcomes = [:]
        sizes = [:]
        guard let info = AppUninstaller.info(for: app.url) else { refusal = .notAnApp; candidates = []; chosen = []; return }
        refusal = Uninstall.refusal(info, ownBundleID: Bundle.main.bundleIdentifier ?? "com.xfinder.app",
                                    running: AppUninstaller.runningBundleIDs())
        let installed = apps.map(\.bundleID)
        let found = await Task.detached(priority: .userInitiated) { AppUninstaller.leftovers(for: info, installed: installed) }.value
        guard selected == app else { return }
        candidates = found
        chosen = Set([app.url.path] + found.filter(\.selectedByDefault).map { AppUninstaller.url(of: $0).path })
        let paths = [app.url.path] + found.map { AppUninstaller.url(of: $0).path }
        let measured = await Task.detached(priority: .utility) {
            Dictionary(uniqueKeysWithValues: paths.compactMap { p in FileWalk.totalSize(URL(fileURLWithPath: p)).map { (p, $0) } })
        }.value
        guard selected == app else { return }
        sizes = measured
    }

    private func moveToTrash() async {
        guard let app = selected, refusal == nil else { return }
        // Re-check right before moving: the app may have been launched since it was selected.
        if AppUninstaller.runningBundleIDs().contains(app.bundleID) { refusal = .running; return }
        working = true
        let order = ([app.url.path] + candidates.map { AppUninstaller.url(of: $0).path }).filter { chosen.contains($0) }
        let result = await Task.detached(priority: .userInitiated) {
            AppUninstaller.moveToTrash(order.map { URL(fileURLWithPath: $0) })
        }.value
        working = false
        var byPath: [String: Uninstall.ItemOutcome] = [:]
        for (url, o) in result { byPath[url.path] = o }
        outcomes = byPath
        let trashed = result.filter { $0.value == .trashed }.map(\.key)
        ActionHistoryStore.shared.recordTrash(urls: trashed)
        chosen.subtract(trashed.map(\.path))
        let blocked = result.values.filter { $0 == .protected }.count
        var s = "\(L10n.t("Đã chuyển "))\(trashed.count)\(L10n.t(" mục vào Thùng rác — mở Thùng rác để khôi phục nếu cần."))"
        if blocked > 0 { s += " \(blocked)\(L10n.t(" mục bị macOS chặn — dùng Hiện trong Finder."))" }
        let failed = result.values.filter { if case .failed = $0 { return true } else { return false } }.count
        if failed > 0 { s += " \(failed)\(L10n.t(" mục không chuyển được."))" }
        summary = s
        if trashed.contains(app.url) { await reloadApps() }
    }
}
