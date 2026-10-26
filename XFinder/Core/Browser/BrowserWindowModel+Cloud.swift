import AppKit

/// XF-T30 W8 — cloud actions: Download Now / Remove Download for one or many items (background,
/// `startDownloadingUbiquitousItem`/`evictUbiquitousItem`, refusing eviction while an upload is still in flight),
/// blocking copy/move of cloud-only items out of a provider's folder with a "Tải về ngay" suggestion, and a Google
/// Drive trash confirmation. Contract docs/specs/XF-T30-w5b-w8-contract.md §W8. W8 builder (this file + the model's
/// `.downloadNow`/`.removeDownload`/`drop`/trash call sites).
///
/// `cloudProvider(for:)` reads `SidebarSources.shared.cloud` rather than re-scanning `~/Library/CloudStorage` itself
/// — one scan (reference-counted to open browser windows, CLAUDE.md IdleCost) feeds both the sidebar rows and every
/// window's cloud-awareness, instead of every `BrowserWindowModel` instance doing its own `contentsOfDirectory` disk
/// read on every drop/trash. `SidebarSources` is `@MainActor`, same isolation as this extension.
extension BrowserWindowModel {
    /// The provider holding `path`, if any (checked against the live list `SidebarSources` already maintains).
    func cloudProvider(for path: String) -> CloudProvider? {
        CloudProviders.provider(containing: path, in: SidebarSources.shared.cloud)
    }

    /// Whether `path` sits inside a cloud provider's folder (iCloud Drive counts too, via its own well-known root —
    /// `SidebarSources.cloud` only tracks `~/Library/CloudStorage` entries, which never include iCloud Drive itself,
    /// per contract "iCloud Drive riêng").
    func isInsideAnyCloudFolder(_ path: String) -> Bool {
        if cloudProvider(for: path) != nil { return true }
        if let iCloudRoot = SidebarSources.shared.iCloudDrive {
            return path == iCloudRoot || path.hasPrefix(iCloudRoot + "/")
        }
        return false
    }

    // MARK: - Download Now / Remove Download

    /// `.downloadNow` is enabled when at least one selected item is actually eligible per `CloudRules.canDownload`
    /// — a plain local file, or a cloud item already downloaded/in flight, contributes nothing to enable it. Not
    /// gated on find-results/Recents panes specially: the contract excludes Download Now/Remove Download from
    /// those two surfaces by them simply never showing `DirectoryEntry`s backed by a cloud path there in practice
    /// (Recents/Find list arbitrary paths, not a single provider folder's listing) — no further rule is needed.
    var canDownloadNowCloudAware: Bool {
        active.selectedEntries.contains { CloudRules.canDownload(CloudFactsReader.read(path: $0.path)) }
    }

    /// `.removeDownload` mirrors `canDownloadNowCloudAware` with `CloudRules.canEvict` (refuses while uploading).
    var canRemoveDownloadCloudAware: Bool {
        active.selectedEntries.contains { CloudRules.canEvict(CloudFactsReader.read(path: $0.path)) }
    }

    /// Starts a background download for every selected cloud-only item that is actually eligible
    /// (`CloudRules.canDownload`) — items already local or mid-transfer are silently skipped rather than erroring,
    /// same as Finder's own "Download Now" which simply has nothing to do for an already-downloaded file.
    func downloadSelectionNowCloudAware() {
        let paths = active.selectedEntries.map(\.path)
        CloudActions.downloadNow(paths: paths)
    }

    /// Evicts the local copy of every selected item that is safely evictable (`CloudRules.canEvict`: downloaded,
    /// uploaded, not mid-upload) — refusing silently (not an alert) for the rest, same low-ceremony behavior as
    /// Download Now above; the menu item itself is already disabled via `canPerform` when NOTHING in the selection
    /// qualifies (spec: "Gỡ bản tải từ chối khi chưa tải lên xong").
    func removeDownloadForSelectionCloudAware() {
        let paths = active.selectedEntries.map(\.path)
        CloudActions.removeDownload(paths: paths)
    }

    // MARK: - Cross-boundary copy/move guard (hooked from `drop(_:into:copy:)`)

    /// Refuses (banner only, no file operation enqueued) a copy/move that would take a cloud-only item OUT of its
    /// provider's folder — contract: "chặn + 'Tải về ngay'". A destination that is itself inside the SAME provider
    /// (an intra-cloud-folder move/rename) is unaffected; only a boundary crossing matters. Returns `true` when the
    /// drop was blocked here (caller must not enqueue anything), `false` when it is clear to proceed as normal.
    func blockCrossBoundaryCloudDrop(paths: [String], destination: String) -> Bool {
        let offendingPaths = paths.filter { source in
            guard let sourceProvider = cloudProviderOrICloud(for: source) else { return false }
            // Leaving the SAME provider root is the only boundary that matters — staying inside it is a normal
            // intra-cloud move (contract §7: "Operations staying fully inside one cloud folder use normal...UI").
            let stillInsideSameRoot = destination == sourceProvider.root || destination.hasPrefix(sourceProvider.root + "/")
            guard !stillInsideSameRoot else { return false }
            let facts = CloudFactsReader.read(path: source)
            return CloudRules.badge(facts) == .cloudOnly
        }
        guard !offendingPaths.isEmpty else { return false }
        banner = "Một số mục chỉ có trên đám mây — bấm \"Tải về ngay\" trước khi chép ra ngoài"
        return true
    }

    /// `cloudProvider(for:)` plus a synthetic root for iCloud Drive, so the cross-boundary check above treats both
    /// kinds of cloud root the same way without `CloudProviders` itself having to know about iCloud's different
    /// path shape (contract: "iCloud Drive riêng").
    private func cloudProviderOrICloud(for path: String) -> (root: String, kind: CloudProvider.Kind)? {
        if let provider = cloudProvider(for: path) {
            return (provider.rootPath, provider.kind)
        }
        if let iCloudRoot = SidebarSources.shared.iCloudDrive, path == iCloudRoot || path.hasPrefix(iCloudRoot + "/") {
            return (iCloudRoot, .iCloud)
        }
        return nil
    }

    // MARK: - Trash confirmation (Google Drive items get an extra confirm; everything else is unaffected here)

    /// Whether trashing `paths` needs the Google Drive confirmation (contract §7: "Thùng rác mục Google Drive ⇒ xác
    /// nhận" — moving a Drive item to the Trash also moves it into Drive's own trash, so the person is told that up
    /// front, once per batch, not once per file).
    func trashNeedsGoogleDriveConfirmation(paths: [String]) -> Bool {
        paths.contains { cloudProvider(for: $0)?.kind == .googleDrive }
    }

    /// Runs the confirmation alert (modal, same `NSAlert.runModal()` pattern as
    /// `BrowserWindowController.confirmQuit()`) and returns whether the trash should proceed. Always `true` when
    /// nothing in the selection is a Google Drive item — the alert never appears for a plain local or
    /// non-Google-Drive-cloud trash.
    func confirmTrashIfGoogleDrive(paths: [String]) -> Bool {
        guard trashNeedsGoogleDriveConfirmation(paths: paths) else { return true }
        let alert = NSAlert()
        alert.messageText = paths.count == 1
            ? L10n.t("Bạn có chắc muốn xoá mục này khỏi Google Drive?")
            : L10n.t("Bạn có chắc muốn xoá các mục này khỏi Google Drive?")
        alert.informativeText = L10n.t("Mục này cũng sẽ chuyển vào thùng rác của Google Drive, không chỉ Thùng rác trên máy.")
        alert.addButton(withTitle: L10n.t("Chuyển vào Thùng rác"))
        alert.addButton(withTitle: L10n.t("Huỷ"))
        return alert.runModal() == .alertFirstButtonReturn
    }
}

/// Background Download Now / Remove Download — off the main actor (disk/iCloud daemon round trip), one item at a
/// time so a huge selection never blocks on the slowest item before starting the next (contract: "chạy nền").
enum CloudActions {
    static func downloadNow(paths: [String]) {
        guard !paths.isEmpty else { return }
        Task.detached(priority: .utility) {
            for path in paths {
                let facts = CloudFactsReader.read(path: path)
                guard CloudRules.canDownload(facts) else { continue }
                try? FileManager.default.startDownloadingUbiquitousItem(at: URL(fileURLWithPath: path))
            }
        }
    }

    static func removeDownload(paths: [String]) {
        guard !paths.isEmpty else { return }
        Task.detached(priority: .utility) {
            for path in paths {
                let facts = CloudFactsReader.read(path: path)
                guard CloudRules.canEvict(facts) else { continue }
                try? FileManager.default.evictUbiquitousItem(at: URL(fileURLWithPath: path))
            }
        }
    }
}
