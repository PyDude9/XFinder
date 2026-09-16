import Cocoa
import FinderSync

/// Finder Sync Extension cho XFinder.
///
/// Thêm một mục vào menu chuột phải của Finder (và nút toolbar) để chuyển
/// file/thư mục đang chọn sang XFinder — ví dụ thêm vào Khay thả.
///
/// Cơ chế nói chuyện với app chính: URL scheme `xfinder://<host>?path=…` mà
/// app chính đã đăng ký và xử lý trong `AppDelegate.application(_:open:)`.
///
/// Lưu ý khi tạo target bằng Xcode (File ▸ New ▸ Target ▸ Finder Sync
/// Extension): Xcode sinh sẵn một `FinderSync.swift` — thay TOÀN BỘ nội dung
/// của nó bằng file này.
class FinderSync: FIFinderSync {

    override init() {
        super.init()
        // Theo dõi toàn bộ máy để menu hiện cho mọi file/thư mục đang chọn.
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/")]
    }

    // MARK: - Toolbar item

    override var toolbarItemName: String { "XFinder" }
    override var toolbarItemToolTip: String { "Gửi tới XFinder" }
    override var toolbarItemImage: NSImage {
        NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil) ?? NSImage()
    }

    // MARK: - Menu

    override func menu(for menuKind: FIMenuKind) -> NSMenu {
        switch menuKind {
        case .contextualMenuForItems, .contextualMenuForContainer, .toolbarItemMenu:
            return buildMenu()
        default:
            return NSMenu(title: "")
        }
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu(title: "XFinder")

        let tray = NSMenuItem(title: "Thêm vào Khay thả XFinder",
                              action: #selector(addToDropTray(_:)), keyEquivalent: "")
        tray.target = self
        tray.image = NSImage(systemSymbolName: "tray.and.arrow.down", accessibilityDescription: nil)
        menu.addItem(tray)

        let reveal = NSMenuItem(title: "Hiện trong Finder",
                                action: #selector(reveal(_:)), keyEquivalent: "")
        reveal.target = self
        reveal.image = NSImage(systemSymbolName: "arrow.up.doc", accessibilityDescription: nil)
        menu.addItem(reveal)

        return menu
    }

    // MARK: - Actions

    @objc private func addToDropTray(_ sender: Any?) {
        for url in selectedURLs() {
            openMainApp(host: "droptray-add", path: url.path)
        }
    }

    @objc private func reveal(_ sender: Any?) {
        let urls = selectedURLs()
        if !urls.isEmpty {
            NSWorkspace.shared.activateFileViewerSelecting(urls)
        }
    }

    // MARK: - Helpers

    private func selectedURLs() -> [URL] {
        (FIFinderSyncController.default().selectedItemURLs() as? [URL]) ?? []
    }

    /// Gọi app chính qua URL scheme đã đăng ký: xfinder://<host>?path=…
    private func openMainApp(host: String, path: String) {
        let q = path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? path
        if let url = URL(string: "xfinder://\(host)?path=\(q)") {
            NSWorkspace.shared.open(url)
        }
    }
}
