import SwiftUI
import AppKit
import AVKit
import UniformTypeIdentifiers
import ImageIO
import CoreGraphics

/// XF-T30 W7 — the Preview pane (⇧⌘P) at the right of each pane: Information + Tags, Show More / Show Less, image
/// thumbnail out of process, video poster with Play, never downloads cloud bytes. W7 builder (preview). Contract
/// docs/specs/XF-T30-w78-contract.md: "a dải bên phải mỗi ngăn … mục 'Thông tin' … + 'Thẻ'; 'Hiện thêm / Hiện bớt'
/// nhớ toàn cục; ảnh qua QLThumbnailGenerator (ngoài tiến trình), video = khung poster + nút Phát (không tự phát),
/// không xem được ⇒ biểu tượng + giải thích, tệp đám mây chưa tải ⇒ không tải."
///
/// Deliberately its own tiny facts reader rather than `GetInfoWindow`'s `FileInfoFacts.readFacts` (private to that
/// file, not a shared API) — reuses the SHARED pure pieces instead (`FileInfoFacts`, `FileInfoRules.generalRows`/
/// `additionalRows`, `CloudRules`), per contract: builders only touch their own files, but calling another file's
/// already-public API is fine.
struct PreviewPaneView: View {
    let pane: PaneState
    let model: BrowserWindowModel

    @State private var previewModel = FilePreviewPaneModel()
    @AppStorage("fileBrowser.previewShowMore") private var showMore = false

    private static let width: CGFloat = 220

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: XFinderTokens.Space.section) {
                switch previewModel.content {
                case .empty:
                    emptyState
                case .loading:
                    ProgressView().frame(maxWidth: .infinity).padding(.top, XFinderTokens.Space.section)
                case .loaded(let item):
                    PreviewMediaView(item: item)
                    PreviewInformationSection(item: item, showMore: showMore) { showMore.toggle() }
                    PreviewTagsSection(item: item)
                }
            }
            .padding(XFinderTokens.Space.page)
        }
        .frame(width: Self.width)
        .background(XFinderTokens.Fill.window)
        .task(id: PreviewSelectionKey(paths: pane.selectedEntries.map(\.path))) {
            await previewModel.load(selection: pane.selectedEntries)
        }
    }

    private var emptyState: some View {
        VStack(spacing: XFinderTokens.Space.row) {
            Image(systemName: "sidebar.right")
                .font(XFinderTokens.Font.pageIcon)
                .foregroundColor(.secondary)
            Text(L10n.t("Chọn một mục để xem trước"))
                .font(XFinderTokens.Font.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, XFinderTokens.Space.section)
    }
}

/// `.task(id:)` needs an `Equatable` key; a plain `[String]` already is one, but a tiny named wrapper reads clearer
/// at the call site than a bare array literal and keeps the comparison to just the paths (not selection order).
private struct PreviewSelectionKey: Equatable {
    let paths: [String]
}

// MARK: - Model

/// One item's worth of preview content: the facts `Information`/`Tags` render from, plus what `PreviewMediaView`
/// should show for the thumbnail/poster area.
struct FilePreviewItem: Equatable {
    enum Media: Equatable {
        case image
        /// Cloud items never get decoded for a thumbnail (contract: "tệp đám mây chưa tải ⇒ không tải") — shown
        /// as the unsupported icon+explanation state instead, with its own message.
        case cloudOnly
        case video
        case unsupported
    }

    let path: String
    let name: String
    let kind: String
    let media: Media
    let facts: FileInfoFacts
    let pixelSize: (width: Int, height: Int)?
    let pdfPageCount: Int?
    let mediaDuration: TimeInterval?
    let tags: [String]

    static func == (lhs: FilePreviewItem, rhs: FilePreviewItem) -> Bool {
        lhs.path == rhs.path && lhs.facts == rhs.facts && lhs.media == rhs.media && lhs.tags == rhs.tags
    }
}

enum FilePreviewContent: Equatable {
    case empty
    case loading
    case loaded(FilePreviewItem)
}

/// Reads facts and classifies media off the main actor (CLAUDE.md: no disk I/O in `body`/on main), and caches the
/// result per "path@mtime" (contract: "metadata read off main and cached per path+mtime") so re-selecting the same
/// unchanged file never re-reads disk — except the tag list, which is re-read fresh on every lookup even on a cache
/// hit, since Get Info's tag editor writes `kMDItemUserTags` without touching `mtime` (a bug fixed during review:
/// the Preview pane's "Thẻ" section would otherwise keep showing the pre-edit tags for the life of the cache entry
/// while Get Info stayed open on the same file). Only the single-selection case renders a preview (contract shows
/// one item's Information/Tags/media at a time); a multi-selection or empty selection clears the pane.
@MainActor @Observable final class FilePreviewPaneModel {
    private(set) var content: FilePreviewContent = .empty

    /// Keyed by "path@mtime" — a changed mtime (edited file, replaced export) is a fresh cache entry rather than a
    /// stale hit; the previous entry simply ages out (capacity bound below).
    private var cache: [String: FilePreviewItem] = [:]
    private var cacheOrder: [String] = []
    private let cacheCapacity = 64
    private var generation = 0

    func load(selection: [DirectoryEntry]) async {
        generation += 1
        let myGeneration = generation
        guard selection.count == 1, let entry = selection.first else {
            content = .empty
            return
        }
        content = .loading
        let item = await Self.readItem(path: entry.path, cache: cache) { [weak self] key, item in
            guard let self else { return }
            self.store(key: key, item: item)
        }
        guard myGeneration == generation else { return }   // the selection moved on while this was reading
        content = item.map(FilePreviewContent.loaded) ?? .empty
    }

    private func store(key: String, item: FilePreviewItem) {
        if cache[key] == nil {
            if cacheOrder.count >= cacheCapacity, let oldest = cacheOrder.first {
                cacheOrder.removeFirst()
                cache.removeValue(forKey: oldest)
            }
            cacheOrder.append(key)
        }
        cache[key] = item
    }

    /// Off-main: `lstat`, resource values, image/PDF headers. `onFresh` reports a value just computed back to the
    /// (main-actor) cache; a cache hit still re-reads tags fresh (see below) before returning.
    nonisolated private static func readItem(
        path: String, cache: [String: FilePreviewItem], onFresh: @escaping @MainActor (String, FilePreviewItem) -> Void
    ) async -> FilePreviewItem? {
        var statInfo = stat()
        guard lstat(path, &statInfo) == 0 else { return nil }
        let mtime = statInfo.st_mtimespec.tv_sec
        let key = "\(path)@\(mtime)"
        if let cached = cache[key] {
            // Tags (Finder/Get Info `tagNamesKey`) can change without touching `mtime` — Get Info's `setTags`
            // writes `kMDItemUserTags` only. Re-reading just the tag list (one cheap resourceValues call, no
            // stat/image/PDF work) keeps the Preview pane's "Thẻ" section from going stale after an edit in the
            // still-open Get Info window, without paying for a full re-read of everything else.
            let freshTags = currentTags(path: path) ?? cached.tags
            return freshTags == cached.tags ? cached : FilePreviewItem(
                path: cached.path, name: cached.name, kind: cached.kind, media: cached.media, facts: cached.facts,
                pixelSize: cached.pixelSize, pdfPageCount: cached.pdfPageCount,
                mediaDuration: cached.mediaDuration, tags: freshTags
            )
        }

        guard let facts = readFacts(path: path, statInfo: statInfo) else { return nil }
        let cloudOnly = isCloudOnly(path: path)
        var media: FilePreviewItem.Media = .unsupported
        var pixelSize: (width: Int, height: Int)?
        var pdfPageCount: Int?

        if cloudOnly {
            media = .cloudOnly
        } else if !facts.isFolder {
            let ext = (path as NSString).pathExtension.lowercased()
            if let type = UTType(filenameExtension: ext) {
                if type.conforms(to: .image) {
                    media = .image
                    pixelSize = readPixelSize(path: path)
                } else if ext == "pdf" {
                    media = .image   // Quick Look renders a PDF's first page like an image thumbnail.
                    pdfPageCount = CGPDFDocument(URL(fileURLWithPath: path) as CFURL)?.numberOfPages
                } else if type.conforms(to: .audiovisualContent) {
                    media = .video
                }
            }
        }

        let item = FilePreviewItem(
            path: path, name: facts.name, kind: facts.kind, media: media, facts: facts,
            pixelSize: pixelSize, pdfPageCount: pdfPageCount,
            // Duration is loaded asynchronously by `PreviewMediaView` once AVFoundation has it (same reason
            // `GetInfoModel.loadMediaDuration` is async) — nil here is "not known yet", not "no duration".
            mediaDuration: nil, tags: facts.tags
        )
        await onFresh(key, item)
        return item
    }

    /// Just the tag list, for the cache-hit path above — cheap enough to call on every selection even when the
    /// rest of the item comes from cache. `nil` on a read failure leaves the cached tags as they were rather than
    /// clearing them.
    nonisolated private static func currentTags(path: String) -> [String]? {
        (try? URL(fileURLWithPath: path).resourceValues(forKeys: [.tagNamesKey]))?.tagNames
    }

    nonisolated private static func readFacts(path: String, statInfo: stat) -> FileInfoFacts? {
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
        return FileInfoFacts(
            name: name, path: path, isFolder: isFolder, isPackage: isPackage,
            logicalSize: logicalSize, physicalSize: physicalSize,
            created: Date(timeIntervalSince1970: TimeInterval(statInfo.st_birthtimespec.tv_sec)),
            modified: Date(timeIntervalSince1970: TimeInterval(statInfo.st_mtimespec.tv_sec)),
            accessed: values?.contentAccessDate,
            posixMode: UInt16(statInfo.st_mode & 0o777),
            ownerName: ownerName, groupName: groupName, ownerIsMe: statInfo.st_uid == getuid(),
            locked: values?.isUserImmutable ?? false, hidesExtension: values?.hasHiddenExtension ?? false,
            tags: values?.tagNames ?? [], kind: kindName
        )
    }

    /// Same check as `GetInfoModel.isLikelyNotDownloaded`/`CloudRules`: a not-yet-downloaded cloud item never gets
    /// opened to read pixel size, page count or duration — the preview pane shows the cloud-only state instead.
    nonisolated private static func isCloudOnly(path: String) -> Bool {
        guard let values = try? URL(fileURLWithPath: path)
            .resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]) else { return false }
        return values.ubiquitousItemDownloadingStatus == .notDownloaded
    }

    nonisolated private static func readPixelSize(path: String) -> (width: Int, height: Int)? {
        let url = URL(fileURLWithPath: path)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return (width, height)
    }
}

// MARK: - Media (thumbnail / poster / unsupported)

/// The top of the pane: an image/PDF thumbnail (QLThumbnailGenerator, out of process — `FileIconCache.thumbnail`),
/// a video poster frame with its own Play button (AVPlayerView is created only once Play is clicked — contract:
/// "video = khung poster + nút Phát (không tự phát)"), or an icon + explanation for anything else.
private struct PreviewMediaView: View {
    let item: FilePreviewItem

    @State private var thumbnail: NSImage?
    @State private var isPlaying = false

    private static let side: CGFloat = 180

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: XFinderTokens.Radius.tile, style: .continuous)
                .fill(XFinderTokens.Fill.inset)
            content
        }
        .frame(height: Self.side)
        .task(id: item.path) {
            isPlaying = false
            thumbnail = nil
            guard item.media == .image else { return }
            await loadThumbnail()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch item.media {
        case .image:
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(XFinderTokens.Space.tight)
            } else {
                ProgressView()
            }
        case .video:
            if isPlaying {
                AVPlayerViewRepresentable(url: URL(fileURLWithPath: item.path))
            } else {
                videoPoster
            }
        case .cloudOnly:
            unsupported(
                systemImage: "icloud",
                explanationKey: "Tệp chỉ có trên đám mây — xem trước không tải tệp về."
            )
        case .unsupported:
            unsupported(
                systemImage: "doc",
                explanationKey: "Không xem trước được loại tệp này."
            )
        }
    }

    private var videoPoster: some View {
        ZStack {
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "film")
                    .font(XFinderTokens.Font.pageIcon)
                    .foregroundColor(.secondary)
            }
            Button {
                isPlaying = true
            } label: {
                Image(systemName: "play.circle.fill")
                    .font(XFinderTokens.Font.pageIcon)
                    .foregroundStyle(.white, .black.opacity(0.4))
            }
            .buttonStyle(.plain)
        }
        .task(id: item.path) { await loadThumbnail() }
    }

    private func unsupported(systemImage: String, explanationKey: String) -> some View {
        VStack(spacing: XFinderTokens.Space.row) {
            Image(systemName: systemImage)
                .font(XFinderTokens.Font.pageIcon)
                .foregroundColor(.secondary)
            Text(L10n.t(explanationKey))
                .font(XFinderTokens.Font.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, XFinderTokens.Space.row)
        }
    }

    private func loadThumbnail() async {
        await withCheckedContinuation { continuation in
            FileIconCache.shared.thumbnail(forPath: item.path, side: Self.side, scale: 2) { image in
                thumbnail = image
                continuation.resume()
            }
        }
    }
}

/// `AVPlayerView` wrapped for SwiftUI — created (and so, only started) the moment the contract's Play button is
/// clicked, never before (no autoplay, no decode just to show a poster frame).
private struct AVPlayerViewRepresentable: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .inline
        view.player = AVPlayer(url: url)
        view.player?.play()
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if (nsView.player?.currentItem?.asset as? AVURLAsset)?.url != url {
            nsView.player = AVPlayer(url: url)
            nsView.player?.play()
        }
    }
}

// MARK: - Information

/// "Information": kind, size, created/modified/opened, plus (collapsed behind Show More) the per-kind extras
/// `FileInfoRules.additionalRows` already formats for Get Info (pixel size / PDF pages — media duration is loaded
/// lazily, same as Get Info's). Reuses `FileInfoRules` (shared, read-only call) rather than re-deriving the same
/// row rules a second time.
private struct PreviewInformationSection: View {
    let item: FilePreviewItem
    let showMore: Bool
    let toggleShowMore: () -> Void

    @State private var mediaDuration: TimeInterval?

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
            Text(L10n.t("Thông tin")).font(XFinderTokens.Font.sectionTitle)

            let rows = FileInfoRules.generalRows(item.facts, sizeText: sizeText, dateText: { dateFormatter.string(from: $0) })
            // "Hiện bớt": kind + size only. "Hiện thêm": the rest of Information plus the per-kind extras —
            // contract: "'Hiện thêm / Hiện bớt' nhớ toàn cục" (one persisted @AppStorage key, read by the caller).
            ForEach(Array(rows.prefix(showMore ? rows.count : min(2, rows.count)).enumerated()), id: \.offset) { _, row in
                LabeledContent(L10n.t(row.labelKey), value: row.value)
                    .font(XFinderTokens.Font.caption)
            }

            if showMore {
                let extras = FileInfoRules.additionalRows(
                    pixelSize: item.pixelSize, pdfPageCount: item.pdfPageCount,
                    mediaDuration: mediaDuration, durationText: Self.durationText
                )
                ForEach(Array(extras.enumerated()), id: \.offset) { _, row in
                    LabeledContent(L10n.t(row.labelKey), value: row.value)
                        .font(XFinderTokens.Font.caption)
                }
            }

            if rows.count > 2 {
                Button(showMore ? L10n.t("Hiện bớt") : L10n.t("Hiện thêm")) {
                    toggleShowMore()
                }
                .font(XFinderTokens.Font.caption)
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
            }
        }
        .task(id: item.path) {
            mediaDuration = nil
            guard item.media == .video else { return }
            mediaDuration = await Self.loadDuration(path: item.path)
        }
    }

    private func sizeText(_ bytes: Int64?) -> String {
        guard let bytes else { return L10n.t("Đang tính…") }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private static func durationText(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = seconds >= 3600 ? [.hour, .minute, .second] : [.minute, .second]
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: seconds) ?? "\(Int(seconds))s"
    }

    /// Off-main, like `GetInfoModel.loadMediaDuration` — cloud-only items never reach here (`item.media` is
    /// `.cloudOnly`, not `.video`, so this `task` never fires for them).
    private static func loadDuration(path: String) async -> TimeInterval? {
        let asset = AVURLAsset(url: URL(fileURLWithPath: path))
        guard let duration = try? await asset.load(.duration), duration.isValid, !duration.isIndefinite else { return nil }
        return CMTimeGetSeconds(duration)
    }
}

// MARK: - Tags

private struct PreviewTagsSection: View {
    let item: FilePreviewItem

    var body: some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
            Text(L10n.t("Thẻ")).font(XFinderTokens.Font.sectionTitle)
            if item.tags.isEmpty {
                Text(L10n.t("Không có thẻ"))
                    .font(XFinderTokens.Font.caption)
                    .foregroundColor(.secondary)
            } else {
                // A simple wrapping list of chips — editing tags is Get Info's job (contract: Preview pane shows
                // Information + Tags, read-only; `GetInfoWindow`'s own Tags section is where they're changed).
                FlowLayout(spacing: XFinderTokens.Space.tight) {
                    ForEach(item.tags, id: \.self) { tag in
                        Text(tag)
                            .font(XFinderTokens.Font.caption)
                            .padding(.horizontal, XFinderTokens.Space.tight)
                            .padding(.vertical, 2)
                            .background(XFinderTokens.Fill.inset)
                            .clipShape(RoundedRectangle(cornerRadius: XFinderTokens.Radius.badge, style: .continuous))
                    }
                }
            }
        }
    }
}

/// Minimal wrapping layout for tag chips — no dependency on any other file's flow-layout (none exists yet in this
/// module), kept tiny since this is the only user.
private struct FlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth.isFinite ? maxWidth : x, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX, y: CGFloat = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
