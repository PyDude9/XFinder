import AppKit
import SwiftUI
import ImageIO
import CoreGraphics
import AVFoundation
import UniformTypeIdentifiers
import os

/// XF-T28 Wave 4 §A (`docs/specs/XF-T28-wave4.md`) — ⌘I "Get Info": one window per selected item, or one summary
/// window when several are selected. AppKit owns the window and the disk reads (`stat`, `FileWalk`, `CGImageSource`,
/// `CGPDFDocument`, `AVURLAsset`); the pure rules in `FileInfoRules.swift` decide what the rows say.
@MainActor final class GetInfoWindowController: NSObject, NSWindowDelegate {
    static let shared = GetInfoWindowController()

    private static let contentSize = NSSize(width: 360, height: 420)

    /// One entry per open window, keyed by its own identity so closing one never touches another.
    private var windows: [ObjectIdentifier: (window: NSWindow, model: GetInfoModel)] = [:]

    private override init() { super.init() }

    /// One window per item, or a single summary window when `paths.count > 1`. `readOnly` is set for search
    /// results and anything else that should show facts without offering edits (spec §A "kết quả tìm kiếm ⇒ chỉ đọc").
    func show(paths: [String], readOnly: Bool) {
        guard !paths.isEmpty else { return }
        if paths.count == 1 {
            presentSingle(path: paths[0], readOnly: readOnly)
        } else {
            presentSummary(paths: paths, readOnly: readOnly)
        }
    }

    private func presentSingle(path: String, readOnly: Bool) {
        // Re-using an already-open window for the same item avoids Finder's own quirk of stacking identical
        // Get Info panels — a second ⌘I on the same file brings the existing window forward instead.
        if let existing = windows.first(where: { $0.value.model.kind == .single(path) }) {
            existing.value.window.makeKeyAndOrderFront(nil)
            return
        }
        let model = GetInfoModel(kind: .single(path), readOnly: readOnly)
        presentWindow(for: model)
    }

    private func presentSummary(paths: [String], readOnly: Bool) {
        let model = GetInfoModel(kind: .summary(paths), readOnly: readOnly)
        presentWindow(for: model)
    }

    private func presentWindow(for model: GetInfoModel) {
        let window = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.contentSize),
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.title = model.windowTitle
        window.delegate = self
        let hosting = NSHostingView(rootView: GetInfoRootView(model: model))
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
            guard let self else { return }
            self.windows[id]?.model.tearDown()
            self.windows.removeValue(forKey: id)
        }
    }
}

// MARK: - Model

/// Everything one Get Info window needs: the facts (loaded once, refreshed if the item changes underneath it), a
/// background folder-size walk with a Stop button, and the small set of edits the window allows (rename, hide
/// extension, lock, tags, owner/group/everyone permissions) — each one immediately written to disk and, when it is
/// reversible, recorded in `ActionHistoryStore`.
@MainActor @Observable final class GetInfoModel {
    enum Kind: Equatable {
        case single(String)
        case summary([String])
    }

    enum SizingState: Equatable {
        case computing
        case done(logical: Int64, physical: Int64)
        case stopped(logical: Int64, physical: Int64)
    }

    /// One inline banner: an L10n key (never built with `\(…)` — rule 8) plus an optional raw technical detail
    /// (an OS error string) that the VIEW appends after translating the key, same pattern as
    /// `FileJob.errorKey`/`errorDetail` elsewhere in this module.
    enum MessageKind: Equatable { case rename, hideExtension, lock, tags, permission }
    struct InlineMessage: Equatable {
        let kind: MessageKind
        let key: String
        let detail: String?
    }

    let kind: Kind
    let readOnly: Bool

    private(set) var facts: FileInfoFacts?
    private(set) var summary: FileInfoRules.Summary?
    private(set) var sizing: SizingState = .computing
    /// Becomes true the moment the item this window is about is renamed or removed out from under it
    /// (spec: "Không còn ở đây").
    private(set) var isGone = false
    private(set) var pixelSize: (width: Int, height: Int)?
    private(set) var colorSpace: String?
    private(set) var camera: String?
    private(set) var pdfPageCount: Int?
    private(set) var mediaDuration: TimeInterval?
    private(set) var codecs: [String] = []
    /// Cloud badge for the item (spec §5.2 "Cloud status:" row); nil for a plain local item — the row is omitted.
    private(set) var cloudBadge: CloudBadge?
    /// Apps `NSWorkspace` reports can open this item, default handler first (spec §5 "Open With", no "Change All").
    private(set) var openWithApps: [FileInfoRules.OpenWithApp] = []
    private(set) var defaultOpenWithBundleID: String?

    private(set) var message: InlineMessage?

    private var watcher: DirectoryWatcher?
    private var sizingTask: Task<Void, Never>?
    private let sizingCancelled = OSAllocatedUnfairLock(initialState: false)

    init(kind: Kind, readOnly: Bool) {
        self.kind = kind
        self.readOnly = readOnly
    }

    var singlePath: String? {
        if case .single(let path) = kind { return path }
        return nil
    }

    var windowTitle: String {
        switch kind {
        case .single(let path): return (path as NSString).lastPathComponent
        case .summary(let paths): return "\(paths.count)\(L10n.t(" mục"))"
        }
    }

    func start() {
        switch kind {
        case .single(let path):
            loadSingle(path)
            watcher = DirectoryWatcher(
                path: path,
                onChange: { [weak self] in self?.reload() },
                onGone: { [weak self] in self?.isGone = true }
            )
        case .summary(let paths):
            loadSummary(paths)
        }
    }

    func tearDown() {
        sizingCancelled.withLock { $0 = true }
        sizingTask?.cancel()
        watcher?.cancel()
        watcher = nil
    }

    private func reload() {
        guard case .single(let path) = kind, !isGone else { return }
        loadSingle(path)
    }

    // MARK: Single item

    /// Bumped on every load so a slow read for a previous path never overwrites a newer one.
    private var loadGeneration = 0

    /// Every disk read (lstat, resource values, the PDF / image headers) happens off the main actor — a large PDF or a
    /// slow network volume must not freeze the window (CLAUDE.md: no disk I/O on the main actor).
    private func loadSingle(_ path: String) {
        loadGeneration += 1
        let generation = loadGeneration
        pixelSize = nil
        colorSpace = nil
        camera = nil
        pdfPageCount = nil
        mediaDuration = nil
        codecs = []
        Task.detached(priority: .userInitiated) {
            let loaded = Self.readFacts(at: path)
            let extra = loaded.map { Self.readAdditionalInfo(path: path, isFolder: $0.isFolder) }
            let badge = loaded.map { _ in Self.readCloudBadge(path: path) }
            let apps = loaded.map { _ in Self.readOpenWithApps(path: path) } ?? []
            let defaultBundleID = loaded != nil ? Self.readDefaultOpenWithBundleID(path: path) : nil
            await MainActor.run { [weak self] in
                guard let self, generation == self.loadGeneration else { return }
                guard let loaded else {
                    self.isGone = true
                    return
                }
                self.facts = loaded
                self.cloudBadge = badge
                self.openWithApps = apps
                self.defaultOpenWithBundleID = defaultBundleID
                if loaded.isFolder {
                    self.startFolderWalk(path)
                } else {
                    self.sizing = .done(logical: loaded.logicalSize ?? 0, physical: loaded.physicalSize ?? 0)
                }
                if let extra {
                    self.pixelSize = extra.pixelSize
                    self.colorSpace = extra.colorSpace
                    self.camera = extra.camera
                    self.pdfPageCount = extra.pdfPages
                    if extra.isMedia { self.loadMediaDuration(path) }
                }
            }
        }
    }

    /// Folder size is walked on a background thread (`FileWalk.walk`, same `fts` engine as `FileWalk.totalSize` but
    /// called directly so both the logical AND on-disk size can be totalled in one pass) so the window opens
    /// instantly even for a 500 000-entry tree (spec §A ca hỏng); `Stop` cancels the walk and keeps whatever
    /// partial total it reached.
    private func startFolderWalk(_ path: String) {
        sizing = .computing
        sizingCancelled.withLock { $0 = false }
        sizingTask?.cancel()
        sizingTask = Task.detached(priority: .utility) { [sizingCancelled] in
            let (logical, physical) = Self.walkSize(path, isCancelled: { sizingCancelled.withLock { $0 } })
            let stopped = sizingCancelled.withLock { $0 }
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.sizing = stopped ? .stopped(logical: logical, physical: physical) : .done(logical: logical, physical: physical)
            }
        }
    }

    /// Totals both logical size and on-disk (allocated-block) size for a folder tree in one `fts` pass.
    nonisolated private static func walkSize(_ path: String, isCancelled: () -> Bool) -> (logical: Int64, physical: Int64) {
        var logical: Int64 = 0
        var physical: Int64 = 0
        _ = FileWalk.walk(URL(fileURLWithPath: path), limit: 500_000, isCancelled: isCancelled) { url, isDirectory, size in
            guard !isDirectory else { return .descend }
            logical += size
            physical += Self.physicalSize(of: url.path) ?? size
            return .descend
        }
        return (logical, physical)
    }

    func stopSizing() {
        sizingCancelled.withLock { $0 = true }
        sizingTask?.cancel()
    }

    /// Image pixel size/colour space/camera (`CGImageSource`), PDF page count (`CGPDFDocument`) and "is a
    /// playable media file" (duration + codecs are loaded separately — AVFoundation's track metadata needs
    /// async/synchronous calls this synchronous reader shouldn't block on) — spec §5.3 "Thêm thông tin theo loại".
    /// A cloud placeholder is never downloaded just to read these (spec: "A file that is only in the cloud is
    /// never downloaded to fill this in") — `isLikelyNotDownloaded` is checked first.
    nonisolated private static func readAdditionalInfo(path: String, isFolder: Bool)
        -> (pixelSize: (Int, Int)?, colorSpace: String?, camera: String?, pdfPages: Int?, isMedia: Bool) {
        guard !isFolder, !isLikelyNotDownloaded(path) else { return (nil, nil, nil, nil, false) }
        let url = URL(fileURLWithPath: path)
        let ext = url.pathExtension.lowercased()
        if ext == "pdf" {
            return (nil, nil, nil, CGPDFDocument(url as CFURL)?.numberOfPages, false)
        }
        guard let type = UTType(filenameExtension: ext) else { return (nil, nil, nil, nil, false) }
        if type.conforms(to: .image) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
                return (nil, nil, nil, nil, false)
            }
            var pixelSize: (Int, Int)?
            if let width = props[kCGImagePropertyPixelWidth] as? Int, let height = props[kCGImagePropertyPixelHeight] as? Int {
                pixelSize = (width, height)
            }
            let colorSpace = (props[kCGImagePropertyProfileName] as? String)
                ?? (props[kCGImagePropertyColorModel] as? String)
            var camera: String?
            if let exif = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
                let make = (exif[kCGImagePropertyTIFFMake] as? String)?.trimmingCharacters(in: .whitespaces)
                let model = (exif[kCGImagePropertyTIFFModel] as? String)?.trimmingCharacters(in: .whitespaces)
                camera = [make, model].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
                if camera?.isEmpty == true { camera = nil }
            }
            return (pixelSize, colorSpace, camera, nil, false)
        }
        return (nil, nil, nil, nil, type.conforms(to: .audiovisualContent))
    }

    /// AVFoundation loads duration and per-track codec FourCCs asynchronously (same `formatDescriptions` +
    /// `fourCC` approach `FinderToolDetailViews.inspect` already uses for the compatibility checker — kept here
    /// as its own small helper since that file isn't this builder's to touch).
    private func loadMediaDuration(_ path: String) {
        let asset = AVURLAsset(url: URL(fileURLWithPath: path))
        Task { [weak self] in
            let duration = try? await asset.load(.duration)
            let tracks = (try? await asset.load(.tracks)) ?? []
            var fourCCs: [String] = []
            for track in tracks {
                if let descriptions = try? await track.load(.formatDescriptions), let first = descriptions.first {
                    fourCCs.append(Self.fourCCString(CMFormatDescriptionGetMediaSubType(first)))
                }
            }
            await MainActor.run { [weak self] in
                guard let self else { return }
                if let duration, duration.isValid, !duration.isIndefinite {
                    self.mediaDuration = CMTimeGetSeconds(duration)
                }
                self.codecs = Array(Set(fourCCs)).sorted()
            }
        }
    }

    // MARK: Multi-selection summary

    /// One pass off the main actor: each item's facts are read once (a 1 000-item selection must not stall the window),
    /// then folder sizes are walked one at a time. `kinds` and `sizes` stay index-aligned with the readable items only —
    /// the earlier version zipped `paths` with `kinds` and mislabelled folders once any item failed to read.
    private func loadSummary(_ paths: [String]) {
        sizingCancelled.withLock { $0 = false }
        sizingTask?.cancel()
        sizingTask = Task.detached(priority: .userInitiated) { [sizingCancelled] in
            let readable = paths.compactMap { path in Self.readFacts(at: path).map { (path, $0) } }
            let kinds = readable.map(\.1.kind)
            var sizes: [Int64?] = readable.map { $0.1.isFolder ? nil : $0.1.logicalSize }
            let initial = sizes
            await MainActor.run { [weak self] in
                self?.summary = FileInfoRules.summary(kinds: kinds, sizes: initial)
            }
            for (index, item) in readable.enumerated() where item.1.isFolder {
                if sizingCancelled.withLock({ $0 }) { break }
                let (logical, _) = Self.walkSize(item.0, isCancelled: { sizingCancelled.withLock { $0 } })
                sizes[index] = logical
                let snapshot = sizes
                await MainActor.run { [weak self] in
                    self?.summary = FileInfoRules.summary(kinds: kinds, sizes: snapshot)
                }
            }
        }
    }

    // MARK: Edits

    /// Renames the item on disk, reusing the same rejection rule the in-pane inline rename uses. Records the
    /// change in `ActionHistoryStore` so ⌘Z in the browser window can undo it.
    @discardableResult func rename(to newName: String) -> Bool {
        guard let path = singlePath, !readOnly else { return false }
        if let rejection = FileInfoRules.renameRejectionKey(for: newName) {
            message = InlineMessage(kind: .rename, key: rejection, detail: nil)
            return false
        }
        message = nil
        let directory = (path as NSString).deletingLastPathComponent
        let destination = (directory as NSString).appendingPathComponent(newName.trimmingCharacters(in: .whitespacesAndNewlines))
        guard destination != path else { return true }
        guard !FileManager.default.fileExists(atPath: destination) else {
            message = InlineMessage(kind: .rename, key: "Đã có mục khác tên này", detail: nil)
            return false
        }
        do {
            try FileManager.default.moveItem(atPath: path, toPath: destination)
            ActionHistoryStore.shared.recordRenames(pairs: [(old: URL(fileURLWithPath: path), new: URL(fileURLWithPath: destination))])
            loadSingle(destination)
            watcher?.cancel()
            watcher = DirectoryWatcher(
                path: destination,
                onChange: { [weak self] in self?.reload() },
                onGone: { [weak self] in self?.isGone = true }
            )
            return true
        } catch {
            message = InlineMessage(kind: .rename, key: "Không đổi được tên — ", detail: error.localizedDescription)
            return false
        }
    }

    func setHidesExtension(_ hide: Bool) {
        guard let path = singlePath, !readOnly else { return }
        var url = URL(fileURLWithPath: path)
        var values = URLResourceValues()
        values.hasHiddenExtension = hide
        do {
            try url.setResourceValues(values)
            loadSingle(path)
        } catch {
            message = InlineMessage(kind: .hideExtension, key: "Không đổi được — ", detail: error.localizedDescription)
        }
    }

    func setLocked(_ locked: Bool) {
        guard let path = singlePath, !readOnly else { return }
        var url = URL(fileURLWithPath: path)
        var values = URLResourceValues()
        values.isUserImmutable = locked
        do {
            try url.setResourceValues(values)
            loadSingle(path)
        } catch {
            message = InlineMessage(kind: .lock, key: "Không đổi được — ", detail: error.localizedDescription)
        }
    }

    func setTags(_ tags: [String]) {
        guard let path = singlePath, !readOnly else { return }
        // `URLResourceValues.tagNames`'s SETTER needs a newer SDK than this app's 14.0 deployment target (measured:
        // `swiftc -O` against this SDK marks it macOS 26+-only even though the underlying mechanism is much older);
        // the plain `NSURL` bridge to the same resource key has no such restriction (measured: compiles and round
        // trips a tag list on 14.0+ — see scratchpad probe).
        let nsURL = NSURL(fileURLWithPath: path)
        do {
            try nsURL.setResourceValue(tags, forKey: .tagNamesKey)
            loadSingle(path)
        } catch {
            message = InlineMessage(kind: .tags, key: "Không đổi được — ", detail: error.localizedDescription)
        }
    }

    /// Changes one who's triad on the item's own `posixMode` — never recursive, and never prompts for an admin
    /// password: a failure (not the owner, read-only volume…) renders inline instead (spec §A).
    func setPermission(_ access: Access, for who: PermissionWho) {
        guard let path = singlePath, !readOnly, let facts else { return }
        let newMode = FileInfoRules.mode(setting: access, for: who, in: facts.posixMode)
        do {
            try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: newMode)], ofItemAtPath: path)
            loadSingle(path)
        } catch {
            message = InlineMessage(kind: .permission, key: "Không đổi được quyền — ", detail: error.localizedDescription)
        }
    }

    // MARK: Reading facts off disk

    nonisolated private static func readFacts(at path: String) -> FileInfoFacts? {
        var statInfo = stat()
        guard lstat(path, &statInfo) == 0 else { return nil }
        let isFolder = (statInfo.st_mode & S_IFMT) == S_IFDIR
        let url = URL(fileURLWithPath: path)
        let name = url.lastPathComponent
        let values = try? url.resourceValues(forKeys: [
            .isPackageKey, .hasHiddenExtensionKey, .isUserImmutableKey, .tagNamesKey,
            .localizedTypeDescriptionKey, .contentAccessDateKey,
        ])
        let isPackage = values?.isPackage ?? false
        let kindName: String
        if isFolder && !isPackage {
            kindName = L10n.t("Thư mục")
        } else {
            kindName = values?.localizedTypeDescription ?? L10n.t("Tài liệu")
        }
        let ownerName = (try? FileManager.default.attributesOfItem(atPath: path)[.ownerAccountName] as? String) ?? ""
        let groupName = (try? FileManager.default.attributesOfItem(atPath: path)[.groupOwnerAccountName] as? String) ?? ""
        let logicalSize: Int64? = isFolder ? nil : Int64(statInfo.st_size)
        let physicalSize: Int64? = isFolder ? nil : Int64(statInfo.st_blocks) * 512
        let appVersion: String? = (ext(of: path) == "app")
            ? (Bundle(url: url)?.infoDictionary?["CFBundleShortVersionString"] as? String)
            : nil
        return FileInfoFacts(
            name: name,
            path: path,
            isFolder: isFolder,
            isPackage: isPackage,
            logicalSize: logicalSize,
            physicalSize: physicalSize,
            created: Date(timeIntervalSince1970: TimeInterval(statInfo.st_birthtimespec.tv_sec)),
            modified: Date(timeIntervalSince1970: TimeInterval(statInfo.st_mtimespec.tv_sec)),
            accessed: values?.contentAccessDate,
            posixMode: UInt16(statInfo.st_mode & 0o777),
            ownerName: ownerName,
            groupName: groupName,
            ownerIsMe: statInfo.st_uid == getuid(),
            locked: values?.isUserImmutable ?? false,
            hidesExtension: values?.hasHiddenExtension ?? false,
            tags: values?.tagNames ?? [],
            kind: kindName,
            appVersion: appVersion
        )
    }

    nonisolated private static func ext(of path: String) -> String {
        (path as NSString).pathExtension.lowercased()
    }

    nonisolated private static func physicalSize(of path: String) -> Int64? {
        var statInfo = stat()
        guard lstat(path, &statInfo) == 0 else { return nil }
        return Int64(statInfo.st_blocks) * 512
    }

    /// A placeholder iCloud/other-cloud item that has not been downloaded yet — reading pixel size/page
    /// count/duration would force a download, which the spec forbids.
    nonisolated private static func isLikelyNotDownloaded(_ path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        guard let values = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]) else { return false }
        return values.ubiquitousItemDownloadingStatus == .notDownloaded
    }

    /// Cloud badge for the General section's "Cloud status:" row — same `CloudFacts`/`CloudRules.badge` the file
    /// list's own badge overlay uses (`FileListView.cloudBadgeSymbol`), read fresh here rather than shared state
    /// since this window can outlive the row that opened it.
    nonisolated private static func readCloudBadge(path: String) -> CloudBadge {
        let url = URL(fileURLWithPath: path)
        guard let values = try? url.resourceValues(forKeys: [
            .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey, .ubiquitousItemIsDownloadingKey,
            .ubiquitousItemIsUploadingKey, .ubiquitousItemIsUploadedKey,
            .ubiquitousItemDownloadingErrorKey, .ubiquitousItemUploadingErrorKey,
        ]) else { return .none }
        let facts = CloudFacts(
            isUbiquitous: values.isUbiquitousItem,
            downloadingStatus: values.ubiquitousItemDownloadingStatus?.rawValue,
            isDownloading: values.ubiquitousItemIsDownloading,
            isUploading: values.ubiquitousItemIsUploading,
            isUploaded: values.ubiquitousItemIsUploaded,
            hasDownloadError: values.ubiquitousItemDownloadingError != nil,
            hasUploadError: values.ubiquitousItemUploadingError != nil
        )
        return CloudRules.badge(facts)
    }

    /// Apps that can open this item (spec §5 "Open With: shows the apps that can open it", no "Change All…" —
    /// Q-T30-15): `NSWorkspace.urlsForApplications(toOpen:)` never touches the file's bytes, so it is safe to call
    /// even for a cloud-only placeholder. Display names/icons are resolved by the view (AppKit, `@MainActor`).
    nonisolated private static func readOpenWithApps(path: String) -> [FileInfoRules.OpenWithApp] {
        let url = URL(fileURLWithPath: path)
        let urls = NSWorkspace.shared.urlsForApplications(toOpen: url)
        return urls.map { appURL in
            let bundle = Bundle(url: appURL)
            let name = (bundle?.infoDictionary?["CFBundleName"] as? String)
                ?? appURL.deletingPathExtension().lastPathComponent
            return FileInfoRules.OpenWithApp(name: name, path: appURL.path, bundleID: bundle?.bundleIdentifier)
        }
    }

    /// The app `LSCopyDefaultApplicationURLForURL` would hand the file to today — shown first in "Mở bằng" (spec
    /// §5 ordering) if it is present in `readOpenWithApps`' own list.
    nonisolated private static func readDefaultOpenWithBundleID(path: String) -> String? {
        guard let defaultURL = NSWorkspace.shared.urlForApplication(toOpen: URL(fileURLWithPath: path)) else { return nil }
        return Bundle(url: defaultURL)?.bundleIdentifier
    }

    nonisolated private static func fourCCString(_ code: FourCharCode) -> String {
        let bytes: [UInt8] = [
            UInt8((code >> 24) & 0xFF), UInt8((code >> 16) & 0xFF),
            UInt8((code >> 8) & 0xFF), UInt8(code & 0xFF),
        ]
        let scalars = bytes.map { byte -> Character in
            (32...126).contains(byte) ? Character(UnicodeScalar(byte)) : "?"
        }
        return String(scalars).trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - View

/// Root content: either one item's five foldable sections, in order — Chung (General) · Thêm thông tin (More
/// Info) · Tên & đuôi (Name & Extension) · Thẻ (Tags) · Chia sẻ & Quyền (Sharing & Permissions) — spec §5.1
/// "exactly five, no more"; or, for a multi-item selection, the summary row set. A window opened from a search
/// result shows a read-only banner with "Hiện trong thư mục chứa" (spec §5.8).
struct GetInfoRootView: View {
    @Bindable var model: GetInfoModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
                if model.isGone {
                    Text(L10n.t("Không còn ở đây"))
                        .font(XFinderTokens.Font.sectionTitle)
                        .foregroundColor(.secondary)
                        .padding(.top, XFinderTokens.Space.section)
                } else if case .summary = model.kind {
                    GetInfoSummarySection(model: model)
                } else if let facts = model.facts {
                    if model.readOnly {
                        GetInfoReadOnlyBanner(path: facts.path)
                    }
                    GetInfoFoldableSection(titleKey: "Chung") { GetInfoGeneralSection(model: model, facts: facts) }
                    GetInfoFoldableSection(titleKey: "Thêm thông tin") { GetInfoAdditionalSection(model: model) }
                    GetInfoFoldableSection(titleKey: "Mở bằng") { GetInfoOpenWithSection(model: model) }
                    GetInfoFoldableSection(titleKey: "Tên & đuôi") { GetInfoNameSection(model: model, facts: facts) }
                    GetInfoFoldableSection(titleKey: "Thẻ") { GetInfoTagsSection(model: model, facts: facts) }
                    GetInfoFoldableSection(titleKey: "Chia sẻ & Quyền") { GetInfoPermissionsSection(model: model, facts: facts) }
                } else {
                    ProgressView().padding(.top, XFinderTokens.Space.section)
                }
            }
            .padding(XFinderTokens.Space.page)
        }
        .frame(minWidth: 360, minHeight: 420)
    }
}

/// One disclosure triangle per section (spec §5.1/§5 "five foldable sections", §R23 "independent disclosure
/// triangle"); "Mở bằng" is this builder's own addition on top of the five named sections — folded inside "Thêm
/// thông tin" would have mixed two different jobs, so it gets its own triangle instead of a sixth required one.
private struct GetInfoFoldableSection<Content: View>: View {
    let titleKey: String
    @ViewBuilder let content: () -> Content
    @State private var isExpanded = true

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            content().padding(.top, XFinderTokens.Space.tight)
        } label: {
            Text(L10n.t(titleKey)).font(XFinderTokens.Font.sectionTitle)
        }
    }
}

/// Spec §5.8: "Search-result items open a read-only Info window; use 'Show in Enclosing Folder' to change them."
private struct GetInfoReadOnlyBanner: View {
    let path: String

    var body: some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.tight) {
            Text(L10n.t("Chỉ đọc — mục này đến từ kết quả tìm kiếm."))
                .font(XFinderTokens.Font.caption)
                .foregroundColor(.secondary)
            Button(L10n.t("Hiện trong thư mục chứa")) {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            }
            .font(XFinderTokens.Font.caption)
        }
    }
}

private struct GetInfoSummarySection: View {
    @Bindable var model: GetInfoModel

    var body: some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
            Text(L10n.t("Tổng quan")).font(XFinderTokens.Font.sectionTitle)
            if let summary = model.summary {
                LabeledContent(L10n.t("Số mục:"), value: "\(summary.count)")
                LabeledContent(L10n.t("Loại:"), value: summary.kindSummary)
                LabeledContent(L10n.t("Tổng kích thước:"),
                               value: ByteCountFormatter.string(fromByteCount: summary.totalLogicalSize, countStyle: .file)
                               + (summary.isComplete ? "" : L10n.t(" (đang tính…)")))
            } else {
                ProgressView()
            }
        }
    }
}

private struct GetInfoGeneralSection: View {
    @Bindable var model: GetInfoModel
    let facts: FileInfoFacts

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
            let rows = FileInfoRules.generalRows(facts, sizeText: sizeText, dateText: { dateFormatter.string(from: $0) },
                                                  cloudBadge: model.cloudBadge)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                LabeledContent(L10n.t(row.labelKey), value: row.value)
            }
            if facts.isFolder, model.sizing == .computing {
                Button(L10n.t("Dừng")) { model.stopSizing() }
                    .font(XFinderTokens.Font.caption)
            }
        }
    }

    private func sizeText(_ bytes: Int64?) -> String {
        guard let bytes else { return L10n.t("Đang tính…") }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

private struct GetInfoAdditionalSection: View {
    let model: GetInfoModel

    var body: some View {
        let rows = FileInfoRules.additionalRows(
            pixelSize: model.pixelSize, colorSpace: model.colorSpace, camera: model.camera,
            pdfPageCount: model.pdfPageCount, mediaDuration: model.mediaDuration, codecs: model.codecs,
            durationText: Self.durationText
        )
        if rows.isEmpty {
            Text(L10n.t("Không có thêm thông tin cho loại tệp này."))
                .font(XFinderTokens.Font.caption)
                .foregroundColor(.secondary)
        } else {
            VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    LabeledContent(L10n.t(row.labelKey), value: row.value)
                }
            }
        }
    }

    private static func durationText(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = seconds >= 3600 ? [.hour, .minute, .second] : [.minute, .second]
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: seconds) ?? "\(Int(seconds))s"
    }
}

/// "Mở bằng": the apps `NSWorkspace` reports can open this item, default handler first, each with its own icon —
/// through `FileIconCache.shared.icon(forPath:)` (CLAUDE.md §3.3: every AppKit lookup in `body` goes through a
/// `@MainActor` cache, never a raw `NSWorkspace` call per row). No "Change All…" control (spec §5/Q-T30-15:
/// changing the system default handler is a machine-config change, out of scope unless the owner asks for it).
private struct GetInfoOpenWithSection: View {
    private static let iconSize: CGFloat = 16

    let model: GetInfoModel

    var body: some View {
        let apps = FileInfoRules.orderedOpenWithApps(model.openWithApps, defaultBundleID: model.defaultOpenWithBundleID)
        if apps.isEmpty {
            Text(L10n.t("Không tìm thấy ứng dụng mở được tệp này."))
                .font(XFinderTokens.Font.caption)
                .foregroundColor(.secondary)
        } else {
            VStack(alignment: .leading, spacing: XFinderTokens.Space.tight) {
                ForEach(apps) { app in
                    HStack(spacing: XFinderTokens.Space.tight) {
                        Image(nsImage: FileIconCache.shared.icon(forPath: app.path))
                            .resizable()
                            .frame(width: Self.iconSize, height: Self.iconSize)
                        Text(app.name)
                            .font(XFinderTokens.Font.rowValue)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
        }
    }
}

/// Renders an `InlineMessage` as "translated key" + (optional) raw OS detail appended verbatim — the same
/// key-plus-detail split `FileJob.errorKey`/`errorDetail` already uses elsewhere in this module, so the detail
/// (an `Error.localizedDescription`, already in the user's OS language) never has to be folded into an L10n key.
private func inlineMessageText(_ message: GetInfoModel.InlineMessage) -> String {
    guard let detail = message.detail else { return L10n.t(message.key) }
    return "\(L10n.t(message.key))\(detail)"
}

private struct GetInfoNameSection: View {
    let model: GetInfoModel
    let facts: FileInfoFacts
    @State private var name: String = ""
    @State private var hidesExtension = false

    var body: some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
            TextField(L10n.t("Tên"), text: $name)
                .disabled(!FileInfoRules.isControlEnabled(.rename, readOnly: model.readOnly, locked: facts.locked))
                .onSubmit { model.rename(to: name) }
            if let message = model.message, message.kind == .rename {
                Text(inlineMessageText(message)).font(XFinderTokens.Font.caption).foregroundColor(.red)
            }
            Toggle(L10n.t("Ẩn đuôi tệp"), isOn: $hidesExtension)
                .disabled(facts.isFolder || !FileInfoRules.isControlEnabled(.hideExtension, readOnly: model.readOnly, locked: facts.locked))
                .onChange(of: hidesExtension) { _, newValue in model.setHidesExtension(newValue) }
            if let message = model.message, message.kind == .hideExtension {
                Text(inlineMessageText(message)).font(XFinderTokens.Font.caption).foregroundColor(.red)
            }
            Toggle(L10n.t("Khoá"), isOn: Binding(
                get: { facts.locked },
                set: { model.setLocked($0) }
            ))
            .disabled(!FileInfoRules.isControlEnabled(.lock, readOnly: model.readOnly, locked: facts.locked))
            if let message = model.message, message.kind == .lock {
                Text(inlineMessageText(message)).font(XFinderTokens.Font.caption).foregroundColor(.red)
            }
        }
        .onAppear {
            name = facts.name
            hidesExtension = facts.hidesExtension
        }
    }
}

private struct GetInfoTagsSection: View {
    private static let dotSize: CGFloat = 8

    let model: GetInfoModel
    let facts: FileInfoFacts
    @State private var tagsText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
            TextField(L10n.t("Thẻ, cách nhau bằng dấu phẩy"), text: $tagsText)
                .disabled(!FileInfoRules.isControlEnabled(.tags, readOnly: model.readOnly, locked: facts.locked))
                .onSubmit {
                    let tags = tagsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                    model.setTags(tags)
                }
            if let message = model.message, message.kind == .tags {
                Text(inlineMessageText(message)).font(XFinderTokens.Font.caption).foregroundColor(.red)
            }
            // Finder tag colours (spec §5.5 "Tags look like Finder's" — 1.0.4 fixed the wrong/missing round trip):
            // `FinderTags.parse` decodes the stored "Name\n<colour number>" string, this view only picks the dot.
            if !facts.tags.isEmpty {
                HStack(spacing: XFinderTokens.Space.tight) {
                    ForEach(facts.tags, id: \.self) { tag in
                        let parsed = FinderTags.parse(tag)
                        Circle()
                            .fill(Self.dotColor(parsed.color))
                            .frame(width: Self.dotSize, height: Self.dotSize)
                        Text(parsed.name).font(XFinderTokens.Font.caption)
                    }
                }
            }
        }
        .onAppear { tagsText = facts.tags.joined(separator: ", ") }
    }

    private static func dotColor(_ color: TagColor) -> Color {
        switch color {
        case .none: return .clear
        case .gray: return .gray
        case .green: return .green
        case .purple: return .purple
        case .blue: return .blue
        case .yellow: return .yellow
        case .red: return .red
        case .orange: return .orange
        }
    }
}

private struct GetInfoPermissionsSection: View {
    let model: GetInfoModel
    let facts: FileInfoFacts

    var body: some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
            // Owner is marked "(Tôi)" only when the current user actually owns the item (spec §5.6 "(Me)"), not
            // unconditionally — the original label here always said "(Chủ sở hữu)" regardless of `ownerIsMe`.
            permissionRow(label: facts.ownerIsMe ? "\(facts.ownerName) \(L10n.t("(Tôi)"))" : facts.ownerName, who: .owner)
            permissionRow(label: facts.groupName, who: .group)
            permissionRow(label: L10n.t("Mọi người khác"), who: .everyone)
            if let message = model.message, message.kind == .permission {
                Text(inlineMessageText(message)).font(XFinderTokens.Font.caption).foregroundColor(.red)
            }
        }
    }

    private func permissionRow(label: String, who: PermissionWho) -> some View {
        let current = FileInfoRules.access(mode: facts.posixMode, who: who)
        return Picker(label, selection: Binding(
            get: { current },
            set: { model.setPermission($0, for: who) }
        )) {
            ForEach(Access.allCases, id: \.self) { access in
                Text(L10n.t(access.titleKey)).tag(access)
            }
        }
        .disabled(!FileInfoRules.isControlEnabled(.permissions, readOnly: model.readOnly, locked: facts.locked))
    }
}
