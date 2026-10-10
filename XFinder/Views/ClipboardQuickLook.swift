import AppKit
import Quartz
import SwiftUI

/// Quick Look (Space) for clipboard cards. Lived inside the deleted ClipboardTabView.swift; the ⌘⇧V
/// shelf still uses it, so it moved to its own file when that page was removed (2026-10-10).
final class ClipboardQLController: NSObject, QLPreviewPanelDataSource {
    private var url: URL?
    func present(url: URL) {
        self.url = url
        guard let panel = QLPreviewPanel.shared() else { return }
        if !panel.isVisible { panel.makeKeyAndOrderFront(nil) }
        panel.reloadData()
    }
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { 1 }
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        url as QLPreviewItem?
    }
}
