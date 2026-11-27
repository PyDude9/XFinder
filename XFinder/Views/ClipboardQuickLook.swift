import AppKit
import Quartz
import SwiftUI

/// Quick Look (Space) for clipboard cards and Drop Tray files. Reuses the system `QLPreviewPanel`
/// singleton for single or multi-file previews without spawning a second preview controller.
final class ClipboardQLController: NSObject, QLPreviewPanelDataSource {
    private var urls: [URL] = []

    func present(url: URL) {
        present(urls: [url])
    }

    func present(urls: [URL]) {
        guard !urls.isEmpty else { return }
        self.urls = urls
        guard let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = self
        if !panel.isVisible { panel.makeKeyAndOrderFront(nil) }
        panel.reloadData()
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { urls.count }
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        guard index >= 0, index < urls.count else { return nil }
        return urls[index] as QLPreviewItem
    }
}
