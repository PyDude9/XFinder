import AppKit

/// XF-T30 W3 — Connect to Server (⌘K): smb / afp / nfs / ftp / webdav URLs, recent + favorite servers, mounting through
/// NetFS (the system asks for credentials — XFinder never reads or stores them). W3 builder (AppKit).
@MainActor
final class ConnectToServer {
    static let shared = ConnectToServer()

    /// Shows the sheet on `window`; a successful mount calls `opened(mountPath)`.
    func present(on window: NSWindow?, opened: @escaping @MainActor (String) -> Void) {}
}
