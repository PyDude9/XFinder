import AppKit

/// XF-T32 W3 (contract XF-T32-w23 §F) — the row `⋯` menu (pin, property values, add property, nickname, emoji) and
/// the folder `⋯` menu (filter, sort, properties, group). STUB — builder `menus`.
enum RowActionsMenu {
    @MainActor static func menu(for entries: [DirectoryEntry], pane: PaneState, model: BrowserWindowModel) -> NSMenu {
        NSMenu()
    }

    @MainActor static func folderMenu(pane: PaneState, model: BrowserWindowModel) -> NSMenu {
        NSMenu()
    }
}
