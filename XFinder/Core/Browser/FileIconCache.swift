import AppKit
import UniformTypeIdentifiers
import QuickLookThumbnailing

/// XF-T28 cluster A. Measured (evidence doc §5): `NSWorkspace.icon(forFile:)` alone is already ~0.06 ms/call, but
/// paying for a per-file `contentType` resourceValues lookup costs ~60 ms/1000 files — the win is caching by
/// UTType (derived from the extension the listing pass already has, no extra syscall) and never re-deriving it.
/// `QLThumbnailGenerator` is for real image/document previews (~5-7 ms each even concurrently, out-of-process,
/// +3.7 MB/60 thumbnails, not retained by this process) — requested lazily per visible cell, never eagerly.
@MainActor final class FileIconCache {
    static let shared = FileIconCache()

    /// One `NSImage` per UTType identifier (folders/packages/apps/volumes are NOT keyed this way — see `icon(forPath:)`).
    private var byType: [String: NSImage] = [:]
    /// One `localizedDescription` per lowercased extension (folders use `kindFolder` instead, never cached by ext).
    private var kindByExt: [String: String] = [:]
    private let kindFolder = "Thư mục"

    /// LRU of real per-path icons (packages, `.app`s, mounted volumes, anything `isPackage`) — these can carry a
    /// custom icon baked into the bundle, so they're never collapsed into the shared per-type image.
    private var pathIconOrder: [String] = []
    private var pathIcons: [String: NSImage] = [:]
    private let pathIconCapacity = 512

    /// LRU of QuickLook thumbnails, keyed by "path@side@scale" (a cell resized/rescaled needs a fresh render).
    private var thumbOrder: [String] = []
    private var thumbs: [String: NSImage] = [:]
    private let thumbCapacity = 256
    /// In-flight requests, so a cell that re-renders while its own request is pending doesn't fire a second one.
    private var pendingThumbs: Set<String> = []

    private init() {}

    func icon(for entry: DirectoryEntry) -> NSImage {
        if entry.isPackage || entry.kind == .directory && isVolumeRoot(entry.path) {
            return icon(forPath: entry.path)
        }
        if entry.kind == .directory {
            return sharedIcon(forType: .folder)
        }
        guard let type = utType(forExtension: entry.ext) else {
            return icon(forPath: entry.path)
        }
        return sharedIcon(forType: type)
    }

    func icon(forPath path: String) -> NSImage {
        if let cached = pathIcons[path] {
            touchPathIcon(path)
            return cached
        }
        let image = NSWorkspace.shared.icon(forFile: path)
        storePathIcon(path, image: image)
        return image
    }

    func kindName(for entry: DirectoryEntry) -> String {
        if entry.kind == .directory && !entry.isPackage { return L10n.t(kindFolder) }
        let ext = entry.ext
        if ext.isEmpty {
            return utType(forExtension: ext)?.localizedDescription ?? ""
        }
        if let cached = kindByExt[ext] { return cached }
        let name = utType(forExtension: ext)?.localizedDescription ?? ext.uppercased()
        kindByExt[ext] = name
        return name
    }

    /// Lazy, per-visible-cell only — never call this for an entire folder eagerly (evidence doc §5).
    func thumbnail(forPath path: String, side: CGFloat, scale: CGFloat, completion: @escaping @MainActor (NSImage?) -> Void) {
        let key = "\(path)@\(side)@\(scale)"
        if let cached = thumbs[key] {
            touchThumb(key)
            completion(cached)
            return
        }
        guard !pendingThumbs.contains(key) else {
            completion(nil)
            return
        }
        pendingThumbs.insert(key)
        let url = URL(fileURLWithPath: path)
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: side, height: side),
            scale: scale,
            representationTypes: .thumbnail)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] representation, _ in
            // `QLThumbnailRepresentation` is not `Sendable`; pull the `NSImage` out on whatever thread
            // this callback arrived on (not guaranteed to be main — the generator runs out-of-process)
            // before hopping, so only a value that's safe to send crosses the actor boundary.
            let image = representation?.nsImage
            Task { @MainActor in
                guard let self else { return }
                self.pendingThumbs.remove(key)
                guard let image else {
                    completion(nil)
                    return
                }
                self.storeThumb(key, image: image)
                completion(image)
            }
        }
    }

    /// Closing the last browser window: drop everything so a long session doesn't hold onto thumbnails/icons
    /// for folders no longer being viewed.
    func purge() {
        byType.removeAll()
        kindByExt.removeAll()
        pathIconOrder.removeAll()
        pathIcons.removeAll()
        thumbOrder.removeAll()
        thumbs.removeAll()
        pendingThumbs.removeAll()
    }

    // MARK: - Private

    private func utType(forExtension ext: String) -> UTType? {
        guard !ext.isEmpty else { return nil }
        return UTType(filenameExtension: ext)
    }

    private func sharedIcon(forType type: UTType) -> NSImage {
        if let cached = byType[type.identifier] { return cached }
        let image = NSWorkspace.shared.icon(for: type)
        byType[type.identifier] = image
        return image
    }

    /// A directory that is itself a mount point (statfs reports it as its own mount point) gets a disk icon,
    /// not the shared folder glyph.
    private func isVolumeRoot(_ path: String) -> Bool {
        DirectoryReader.volumePath(of: path) == path
    }

    private func touchPathIcon(_ path: String) {
        guard let index = pathIconOrder.firstIndex(of: path) else { return }
        pathIconOrder.remove(at: index)
        pathIconOrder.append(path)
    }

    private func storePathIcon(_ path: String, image: NSImage) {
        if pathIcons[path] != nil {
            touchPathIcon(path)
            pathIcons[path] = image
            return
        }
        if pathIconOrder.count >= pathIconCapacity, let oldest = pathIconOrder.first {
            pathIconOrder.removeFirst()
            pathIcons.removeValue(forKey: oldest)
        }
        pathIconOrder.append(path)
        pathIcons[path] = image
    }

    private func touchThumb(_ key: String) {
        guard let index = thumbOrder.firstIndex(of: key) else { return }
        thumbOrder.remove(at: index)
        thumbOrder.append(key)
    }

    private func storeThumb(_ key: String, image: NSImage) {
        if thumbs[key] != nil {
            touchThumb(key)
            thumbs[key] = image
            return
        }
        if thumbOrder.count >= thumbCapacity, let oldest = thumbOrder.first {
            thumbOrder.removeFirst()
            thumbs.removeValue(forKey: oldest)
        }
        thumbOrder.append(key)
        thumbs[key] = image
    }
}
