import AppKit
import Quartz
import UniformTypeIdentifiers

/// XF-T30 W7 — the Preview pane toggle (⇧⌘P) and the slideshow (⌥⌘Y). Contract docs/specs/XF-T30-w78-contract.md.
/// W7 builder (model). Deliberately independent of `BrowserWindowController`'s own `toggleQuickLook` (Space/⌘Y):
/// the spec calls out "Space/⌘Y unaffected" — the slideshow panel is driven by its own tiny data source here
/// rather than reusing that controller's private one (not a file this builder owns, per contract §6).
extension BrowserWindowModel {
    func performPreviewCommand(_ command: BrowserCommand) -> Bool {
        switch command {
        case .togglePreview:
            UserDefaults.standard.set(!BrowserSettings.showPreview, forKey: "fileBrowser.showPreview")
            return true
        case .slideshow:
            return PreviewSlideshow.shared.start(for: active)
        default:
            return false
        }
    }

    func canPerformPreviewCommand(_ command: BrowserCommand) -> Bool {
        switch command {
        case .togglePreview:
            return true
        case .slideshow:
            return !PreviewSlideshow.items(for: active).isEmpty
        default:
            return false
        }
    }
}

/// Full-screen `QLPreviewPanel` slideshow (⌥⌘Y): the selection when there is one, otherwise every image in the
/// pane's current folder (contract: "full screen over the selection or the folder images"). A singleton like
/// `BrowserWindowController`/`FileIconCache` — the panel itself is a system-wide singleton, so only one slideshow
/// can be driving it at a time regardless of which browser window is key.
@MainActor final class PreviewSlideshow {
    static let shared = PreviewSlideshow()

    private let dataSource = SlideshowDataSource()

    private init() {}

    /// The items a slideshow for `pane` would show, without starting anything — used by `canPerform` so the
    /// toolbar/menu/palette can grey the command out instead of opening an empty full-screen panel.
    static func items(for pane: PaneState) -> [URL] {
        if !pane.selectedEntries.isEmpty {
            return pane.selectedEntries.map { URL(fileURLWithPath: $0.path) }
        }
        return pane.entries.filter(Self.isImage).map { URL(fileURLWithPath: $0.path) }
    }

    @discardableResult
    func start(for pane: PaneState) -> Bool {
        let items = Self.items(for: pane)
        guard !items.isEmpty, let panel = QLPreviewPanel.shared() else { return false }
        dataSource.items = items
        panel.dataSource = dataSource
        panel.reloadData()
        _ = panel.enterFullScreenMode(NSScreen.main, withOptions: nil)
        return true
    }

    private static func isImage(_ entry: DirectoryEntry) -> Bool {
        guard !entry.ext.isEmpty, let type = UTType(filenameExtension: entry.ext) else { return false }
        return type.conforms(to: .image)
    }
}

/// Not `@MainActor`: `QLPreviewPanelDataSource` is a plain (non-isolated) AppKit protocol, and Swift 6 rejects a
/// main-actor type conforming to a non-isolated protocol — same reason `BrowserQuickLookController` (owned by
/// `BrowserWindowController.swift`) and `ClipboardQLController` are not `@MainActor` either. `items` is written
/// and read only from the main thread in practice (every caller above is `@MainActor`).
private final class SlideshowDataSource: NSObject, QLPreviewPanelDataSource {
    var items: [URL] = []

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { items.count }
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        guard items.indices.contains(index) else { return nil }
        return items[index] as QLPreviewItem
    }
}
