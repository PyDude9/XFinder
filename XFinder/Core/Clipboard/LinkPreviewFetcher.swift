import AppKit
import LinkPresentation
import ImageIO
import UniformTypeIdentifiers

/// D4b — the network half of link previews. ONE reader of `clipboard.linkPreviews` (default off: this is the only
/// place a copy can cause a network request). Fetches one link at a time through Apple's `LPMetadataProvider`
/// (title + representative image), stores the image downscaled in `Clipboard/LinkPreviews/<sha256>.png`, and patches
/// the record's metadata through `ClipboardManager.applyLinkPreview` — so the same row shows the preview on the shelf,
/// the notch and the Library. A failure is recorded too (`linkFetched` without a title) and retried after a day, never
/// on every render. Turning the switch off cancels the queue; turning it on backfills the newest 50 link clips.
@MainActor
final class LinkPreviewFetcher {
    static let shared = LinkPreviewFetcher()
    private init() {}

    var isEnabled: Bool { UserDefaults.standard.object(forKey: "clipboard.linkPreviews") as? Bool ?? false }

    private var queue: [UUID] = []
    private var pending: [UUID: URL] = [:]
    private var running = false
    private var inFlight: LPMetadataProvider?

    nonisolated static var cacheDir: URL { ClipboardPayloadStore.baseDir().appendingPathComponent("LinkPreviews", isDirectory: true) }

    func applySettings() {
        if isEnabled { backfill() } else { cancelAll() }
    }

    /// Queue a record if it is a link worth fetching. Safe to call for every capture: everything that should not
    /// be fetched (switch off, not a link, locked, private host, fetched recently) returns at once.
    func enqueue(_ r: ClipboardRecord) {
        guard isEnabled, r.type == .link, !r.isLocked,
              let url = LinkPreviewRules.url(of: r.metadata, preview: r.displayPreview),
              LinkPreviewRules.isEligible(url),
              LinkPreviewRules.needsFetch(fetched: LinkPreviewRules.fetchedDate(from: r.metadata),
                                          hasTitle: r.metadata[LinkPreviewRules.titleKey] != nil, now: Date()),
              pending[r.id] == nil else { return }
        pending[r.id] = url
        queue.append(r.id)
        pump()
    }

    private func backfill() {
        for r in ClipboardManager.shared.history.filter({ $0.type == .link }).prefix(LinkPreviewRules.backfillLimit) { enqueue(r) }
    }

    private func cancelAll() {
        queue.removeAll(); pending.removeAll()
        inFlight?.cancel(); inFlight = nil
        running = false
    }

    private func pump() {
        guard !running, let id = queue.first, let url = pending[id] else { return }
        queue.removeFirst()
        running = true
        let provider = LPMetadataProvider()
        provider.timeout = LinkPreviewRules.fetchTimeout
        inFlight = provider
        Task { @MainActor [weak self] in
            var title: String?
            var imagePath: String?
            if let meta = try? await provider.startFetchingMetadata(for: url) {
                title = meta.title
                if let prov = meta.imageProvider, let data = try? await Self.loadImageData(prov) {
                    imagePath = Self.cacheImage(data, stem: LinkPreviewRules.cacheStem(for: url))
                }
            }
            let patch = LinkPreviewRules.metadataPatch(title: title, imagePath: imagePath, fetched: Date())
            ClipboardManager.shared.applyLinkPreview(id: id, patch: patch)
            guard let self else { return }
            self.pending[id] = nil
            self.running = false
            self.inFlight = nil
            self.pump()
        }
    }

    // Main-actor isolated on purpose: NSItemProvider is not Sendable, so it must not cross into a nonisolated function.
    static func loadImageData(_ p: NSItemProvider) async throws -> Data {
        try await withCheckedThrowingContinuation { c in
            _ = p.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, error in
                if let data { c.resume(returning: data) } else { c.resume(throwing: error ?? CocoaError(.fileReadUnknown)) }
            }
        }
    }

    /// Decode through ImageIO at ≤ `maxImageEdge` px (never the full bitmap of a 4 000-px hero image) and write a PNG.
    nonisolated static func cacheImage(_ data: Data, stem: String) -> String? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                     kCGImageSourceCreateThumbnailWithTransform: true,
                                     kCGImageSourceThumbnailMaxPixelSize: LinkPreviewRules.maxImageEdge]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        let fm = FileManager.default
        try? fm.createDirectory(at: cacheDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let url = cacheDir.appendingPathComponent("\(stem).png")
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, cg, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return url.path
    }
}
