import AppKit
import SwiftUI

/// XF-T30 W2 (was XF-T28 cluster D) — Gallery: a big preview of the selected item on top, a horizontal strip of
/// thumbnails below. `LazyHStack` so 100 000 entries in the strip only ever build the cells currently scrolled into
/// view (contract: "100 000 entries, no O(n) work per frame" — a plain `HStack` would materialize every thumbnail
/// request at once). W2 adds a cloud badge on each strip tile (contract: "Gallery: badge; chỉ Sắp theo" — no tag
/// dots and no Group By here, only the toolbar's Sort By, which `BrowserToolbar` already renders for this view mode)
/// and routes both the context menu and drag acceptance through the W2 shared helpers.
struct FileGalleryView: View {
    let pane: PaneState
    let model: BrowserWindowModel

    fileprivate static let stripItemSide: CGFloat = 64
    fileprivate static let largeSide: CGFloat = 512

    var body: some View {
        VStack(spacing: XFinderTokens.Space.row) {
            GalleryPreview(pane: pane)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            GalleryStrip(pane: pane, model: model)
                .frame(height: Self.stripItemSide + XFinderTokens.Space.row * 2)
        }
        .background(XFinderTokens.Fill.window)
        .onKeyPress(.leftArrow) { GalleryStrip.moveSelection(pane: pane, by: -1); return .handled }
        .onKeyPress(.rightArrow) { GalleryStrip.moveSelection(pane: pane, by: 1); return .handled }
    }
}

/// The large preview: `QLThumbnailGenerator` (via `FileIconCache.thumbnail`) at gallery size, falling back to the
/// plain file icon until the thumbnail arrives (or forever, for a kind QuickLook has no preview for).
private struct GalleryPreview: View {
    let pane: PaneState
    @State private var image: NSImage?
    @State private var loadedPath: String?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(nsImage: fallbackIcon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 128, height: 128)
            }
        }
        .padding(XFinderTokens.Space.section)
        .task(id: selectedPath) { await load(path: selectedPath) }
    }

    private var selectedPath: String? {
        pane.selection.count == 1 ? pane.selection.first : pane.entries.first?.path
    }

    private var fallbackIcon: NSImage {
        guard let path = selectedPath, let entry = pane.entries.first(where: { $0.path == path }) else {
            return NSWorkspace.shared.icon(for: .item)
        }
        return FileIconCache.shared.icon(for: entry)
    }

    /// A SwiftUI `@State` that outlives a single selection must be reset before the next fetch — CLAUDE.md §3.2 —
    /// otherwise a slow thumbnail for path A can land after the user has already moved to path B and overwrite its
    /// preview with A's image. `loadedPath` guards exactly that race.
    private func load(path: String?) async {
        guard let path else {
            image = nil
            loadedPath = nil
            return
        }
        image = nil
        loadedPath = path
        await withCheckedContinuation { continuation in
            FileIconCache.shared.thumbnail(forPath: path, side: FileGalleryView.largeSide, scale: 2) { thumbnail in
                if loadedPath == path { image = thumbnail }
                continuation.resume()
            }
        }
    }
}

/// The horizontal filmstrip: `LazyHStack` of fixed-size thumbnail tiles, selection synced both ways with
/// `pane.selection`, double-click/Return = open, ←/→ move the selection (handled by the parent `onKeyPress`).
private struct GalleryStrip: View {
    let pane: PaneState
    let model: BrowserWindowModel

    static func moveSelection(pane: PaneState, by delta: Int) {
        guard !pane.entries.isEmpty else { return }
        let currentIndex = pane.selection.count == 1
            ? pane.entries.firstIndex(where: { $0.path == pane.selection.first })
            : nil
        let nextIndex = min(max((currentIndex ?? -1) + delta, 0), pane.entries.count - 1)
        pane.selection = [pane.entries[nextIndex].path]
    }

    @State private var isTargeted = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: XFinderTokens.Space.tight) {
                    ForEach(pane.entries) { entry in
                        StripTile(entry: entry, isSelected: pane.selection.contains(entry.path))
                            .id(entry.path)
                            .onTapGesture(count: 2) { pane.open(entry) }
                            .onTapGesture(count: 1) { select(entry) }
                            .onDrag { dragProvider(for: entry) }
                            .modifier(TileDropModifier(entry: entry, pane: pane, model: model))
                            .contextMenu { StripContextMenu(entry: entry, pane: pane, model: model) }
                    }
                }
                .padding(.horizontal, XFinderTokens.Space.page)
            }
            // Drop onto empty strip background (not on a specific tile) lands in the pane's current folder,
            // same as the other three views' "drop outside any row" case.
            .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                GalleryDrop.accept(providers, into: pane.path, model: model)
                return true
            }
            .onChange(of: pane.selection) { _, newValue in
                guard newValue.count == 1, let path = newValue.first else { return }
                withAnimation(nil) { proxy.scrollTo(path, anchor: .center) }
            }
        }
    }

    /// Plain click replaces the selection; ⇧ extends a contiguous run from the last anchor; ⌘ toggles just this
    /// tile — same three behaviors `NSTableView`/`NSCollectionView` give the other three views for free.
    private func select(_ entry: DirectoryEntry) {
        let flags = NSEvent.modifierFlags
        if flags.contains(.shift), let anchor = pane.selection.first,
           let anchorIndex = pane.entries.firstIndex(where: { $0.path == anchor }),
           let targetIndex = pane.entries.firstIndex(where: { $0.path == entry.path }) {
            let range = anchorIndex < targetIndex ? anchorIndex...targetIndex : targetIndex...anchorIndex
            pane.selection = Set(range.map { pane.entries[$0].path })
        } else if flags.contains(.command) {
            if pane.selection.contains(entry.path) {
                pane.selection.remove(entry.path)
            } else {
                pane.selection.insert(entry.path)
            }
        } else {
            pane.selection = [entry.path]
        }
    }

    /// A multi-item drag starts from any tile that is part of the current selection: AppKit coalesces every
    /// selected view's own `.onDrag` item provider into one dragging session (same mechanism `QuickAccessCardView`
    /// relies on for its single-item case). A tile outside the selection drags just itself, matching Finder.
    private func dragProvider(for entry: DirectoryEntry) -> NSItemProvider {
        if !pane.selection.contains(entry.path) {
            pane.selection = [entry.path]
        }
        return NSItemProvider(contentsOf: URL(fileURLWithPath: entry.path)) ?? NSItemProvider()
    }
}

/// Drop target for one tile: a folder tile accepts files dropped onto it (contract: "drop validation into folder
/// rows"), a non-folder tile falls through to the strip's own background drop (current pane path).
private struct TileDropModifier: ViewModifier {
    let entry: DirectoryEntry
    let pane: PaneState
    let model: BrowserWindowModel
    @State private var isTargeted = false

    func body(content: Content) -> some View {
        if entry.isFolderLike {
            content
                .background(isTargeted ? XFinderTokens.Fill.focus : Color.clear)
                .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                    GalleryDrop.accept(providers, into: entry.path, model: model)
                    return true
                }
        } else {
            content
        }
    }
}

/// Shared drop-acceptance helper: `DragDropCoordinator.verb` decides copy vs. move by volume and modifier keys
/// (contract §3 — the same rule every view and the sidebar share), with `nil` for "no drop" (e.g. a nesting
/// violation) falling through to `model.drop`'s own safety check so the error banner still comes from one place.
@MainActor
private enum GalleryDrop {
    /// Already main-actor by the time it runs (every call site is a synchronous `.onDrop` closure, itself always
    /// invoked on main) — being `@MainActor` itself, rather than a bare `static func` capturing `providers` into a
    /// detached `Task`, is what lets Swift 6 see the resulting `Task { ... }` closure as running on the actor that
    /// already owns `providers`, instead of flagging the capture as an unsafe cross-actor send.
    static func accept(_ providers: [NSItemProvider], into destination: String, model: BrowserWindowModel) {
        let modifiers = NSEvent.modifierFlags
        Task { @MainActor in
            var paths: [String] = []
            for provider in providers {
                let url: URL? = await withCheckedContinuation { continuation in
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in continuation.resume(returning: url) }
                }
                if let url { paths.append(url.path) }
            }
            guard !paths.isEmpty else { return }
            let verb = DragDropCoordinator.verb(sources: paths, folder: destination, modifiers: modifiers)
            let copyFlag: Bool? = verb == .none ? nil : (verb == .copy)
            model.drop(paths, into: destination, copy: copyFlag)
        }
    }
}

/// XF-T30 W2 contract §3: ONE menu builder for all four views — rebuilt from `BrowserContextMenu.menu(for:pane:)`
/// on every open (selecting `entry` first, same as the other three views re-target the click before populating),
/// its `NSMenuItem`s read into plain SwiftUI `Button`s since this is the one view whose menu chrome is SwiftUI's own
/// `.contextMenu` rather than an `NSMenu` set directly on an `NSView`.
private struct StripContextMenu: View {
    let entry: DirectoryEntry
    let pane: PaneState
    let model: BrowserWindowModel

    var body: some View {
        let menu = BrowserContextMenu.menu(for: model, pane: pane)
        ForEach(Array(menu.items.enumerated()), id: \.offset) { _, item in
            if item.isSeparatorItem {
                Divider()
            } else if item.isEnabled {
                Button(item.title) {
                    pane.selection = [entry.path]
                    model.focus(pane.id)
                    if let command = BrowserCommand(rawValue: item.representedObject as? String ?? "") {
                        _ = model.perform(command)
                    }
                }
            }
        }
    }
}

/// One filmstrip tile: a small thumbnail (reusing `FileIconCache`'s 256-entry LRU, so a tile already rendered in
/// icon view or elsewhere in this gallery costs nothing extra), a cloud badge over its corner (contract: "Gallery:
/// badge"), and a single truncated-middle name line.
private struct StripTile: View {
    let entry: DirectoryEntry
    let isSelected: Bool
    @State private var thumbnail: NSImage?
    @State private var badgeSymbol: String?

    var body: some View {
        VStack(spacing: 2) {
            ZStack(alignment: .bottomTrailing) {
                Image(nsImage: thumbnail ?? FileIconCache.shared.icon(for: entry))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 48, height: 48)
                if let badgeSymbol {
                    Image(systemName: badgeSymbol)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .padding(1)
                        .background(XFinderTokens.Fill.surface, in: Circle())
                }
            }
            Text(BrowserWindowModel.displayName(for: entry, showAllExtensions: BrowserSettings.showAllExtensions))
                .font(XFinderTokens.Font.caption)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 60)
        }
        .padding(XFinderTokens.Space.tight)
        .background(
            RoundedRectangle(cornerRadius: XFinderTokens.Radius.control, style: .continuous)
                .fill(isSelected ? XFinderTokens.Fill.focus : Color.clear)
        )
        .task(id: entry.path) {
            // CLAUDE.md §3.3: no disk I/O in `body` — the cloud-facts read (same `URLResourceKey`s the other three
            // views' `cloudFactsCache` reads) runs off-main here, same as the thumbnail fetch below already did.
            badgeSymbol = await Self.readBadgeSymbol(for: entry.path)
            guard Self.isImageExtension(entry.ext) else { return }
            await withCheckedContinuation { continuation in
                FileIconCache.shared.thumbnail(forPath: entry.path, side: 48, scale: 2) { image in
                    thumbnail = image
                    continuation.resume()
                }
            }
        }
    }

    private static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "gif", "heic", "tiff", "bmp", "webp"]
    private static func isImageExtension(_ ext: String) -> Bool { imageExtensions.contains(ext) }

    /// No cache: a filmstrip only ever renders the handful of tiles scrolled into view at once (same reasoning as
    /// the thumbnail fetch above), so this costs nothing beyond what Icon/List/Column pay per visible row through
    /// their own `cloudFactsCache` — but, like that fetch, it must stay off the main actor (CLAUDE.md §3.3).
    private static func readBadgeSymbol(for path: String) async -> String? {
        await Task.detached(priority: .utility) {
            let url = URL(fileURLWithPath: path)
            let keys: Set<URLResourceKey> = [
                .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey, .ubiquitousItemIsDownloadingKey,
                .ubiquitousItemIsUploadingKey, .ubiquitousItemIsUploadedKey,
                .ubiquitousItemDownloadingErrorKey, .ubiquitousItemUploadingErrorKey,
            ]
            guard let values = try? url.resourceValues(forKeys: keys) else { return nil }
            let facts = CloudFacts(
                isUbiquitous: values.isUbiquitousItem,
                downloadingStatus: values.ubiquitousItemDownloadingStatus?.rawValue,
                isDownloading: values.ubiquitousItemIsDownloading,
                isUploading: values.ubiquitousItemIsUploading,
                isUploaded: values.ubiquitousItemIsUploaded,
                hasDownloadError: values.ubiquitousItemDownloadingError != nil,
                hasUploadError: values.ubiquitousItemUploadingError != nil)
            switch CloudRules.badge(facts) {
            case .none: return nil
            case .cloudOnly: return "icloud"
            case .downloading: return "icloud.and.arrow.down"
            case .uploading: return "icloud.and.arrow.up"
            case .downloadFailed, .uploadFailed: return "exclamationmark.icloud"
            }
        }.value
    }
}
