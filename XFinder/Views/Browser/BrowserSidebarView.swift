import SwiftUI
import AppKit

/// XF-T28 cluster E — the Browser window's own sidebar: Mục ưa thích (fixed list), Vị trí (mounted volumes +
/// CloudStorage providers + iCloud Drive). A click navigates the active pane; ejectable volumes get an eject button.
struct BrowserSidebarView: View {
    private static let iconSize: CGFloat = 16

    let model: BrowserWindowModel

    @State private var volumes: [VolumeRow] = []
    @State private var cloudFolders: [CloudRow] = []

    private struct VolumeRow: Identifiable {
        let id: String
        let name: String
        let path: String
        let isEjectable: Bool
    }

    private struct CloudRow: Identifiable {
        let id: String
        let name: String
        let path: String
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: XFinderTokens.Space.section) {
                section(title: L10n.t("Mục ưa thích")) {
                    ForEach(favorites, id: \.path) { favorite in
                        row(name: favorite.name, systemImage: favorite.icon, path: favorite.path)
                    }
                }

                section(title: L10n.t("Vị trí")) {
                    ForEach(volumes) { volume in
                        HStack {
                            row(name: volume.name, systemImage: "externaldrive", path: volume.path)
                            if volume.isEjectable {
                                Spacer(minLength: 0)
                                Button {
                                    eject(volume)
                                } label: {
                                    Image(systemName: "eject")
                                        .font(XFinderTokens.Font.caption)
                                }
                                .buttonStyle(.plain)
                                .padding(.trailing, XFinderTokens.Space.tight)
                            }
                        }
                    }
                    ForEach(cloudFolders) { cloud in
                        row(name: cloud.name, systemImage: "cloud", path: cloud.path)
                    }
                }
            }
            .padding(.vertical, XFinderTokens.Space.row)
        }
        .onAppear(perform: reload)
    }

    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(XFinderTokens.Settings.sidebarHeader)
                .foregroundColor(.secondary)
                .padding(.horizontal, XFinderTokens.Space.row)
            content()
        }
    }

    private func row(name: String, systemImage: String, path: String) -> some View {
        HStack(spacing: XFinderTokens.Space.tight) {
            Image(systemName: systemImage)
                .font(XFinderTokens.Font.caption)
                .foregroundColor(.secondary)
                .frame(width: Self.iconSize)
            Text(name)
                .font(XFinderTokens.Settings.sidebarRow)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, XFinderTokens.Space.row)
        .frame(minHeight: XFinderTokens.Settings.rowMinHeight)
        .contentShape(Rectangle())
        .onTapGesture {
            model.active.navigate(to: path)
        }
    }

    private var favorites: [(name: String, icon: String, path: String)] {
        let home = NSHomeDirectory()
        return [
            (L10n.t("Home"), "house", home),
            (L10n.t("Màn hình nền"), "menubar.dock.rectangle", home + "/Desktop"),
            (L10n.t("Tài liệu"), "doc", home + "/Documents"),
            (L10n.t("Tải về"), "arrow.down.circle", home + "/Downloads"),
            (L10n.t("Ứng dụng"), "square.grid.2x2", "/Applications"),
        ]
    }

    /// `mountedVolumeURLs` and `contentsOfDirectory` are disk I/O (stat-backed) — keep them off the main actor
    /// (CLAUDE.md: no disk I/O on main) by running the scan on a detached task and only hopping back to assign
    /// the published `@State` once results are in.
    private func reload() {
        Task.detached(priority: .userInitiated) {
            let volumes = Self.loadVolumes()
            let cloudFolders = Self.loadCloudFolders()
            await MainActor.run {
                self.volumes = volumes
                self.cloudFolders = cloudFolders
            }
        }
    }

    private nonisolated static func loadVolumes() -> [VolumeRow] {
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeIsEjectableKey]
        guard let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) else {
            return []
        }
        return urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
            let name = values.volumeName ?? url.lastPathComponent
            return VolumeRow(id: url.path, name: name, path: url.path, isEjectable: values.volumeIsEjectable ?? false)
        }
    }

    private nonisolated static func loadCloudFolders() -> [CloudRow] {
        var rows: [CloudRow] = []
        let home = NSHomeDirectory()
        let cloudStorageRoot = home + "/Library/CloudStorage"
        if let entries = try? FileManager.default.contentsOfDirectory(atPath: cloudStorageRoot) {
            for entry in entries.sorted() where !entry.hasPrefix(".") {
                let path = cloudStorageRoot + "/" + entry
                rows.append(CloudRow(id: path, name: entry, path: path))
            }
        }
        let iCloudPath = home + "/Library/Mobile Documents/com~apple~CloudDocs"
        if FileManager.default.fileExists(atPath: iCloudPath) {
            rows.append(CloudRow(id: iCloudPath, name: L10n.t("iCloud Drive"), path: iCloudPath))
        }
        return rows
    }

    private func eject(_ volume: VolumeRow) {
        let url = URL(fileURLWithPath: volume.path)
        try? NSWorkspace.shared.unmountAndEjectDevice(at: url)
    }
}
