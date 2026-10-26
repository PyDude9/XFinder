import Foundation

/// How a pane's folder load presents itself. Pure (Foundation only), symlinked into the test package.
enum LoadRules {
    /// A load of the folder whose listing is already on screen is a refresh: keep showing that listing until the new
    /// one lands instead of swapping the view for a spinner. Anything else (another folder, nothing loaded yet, the
    /// last load failed) shows the spinner. Paths compare after `standardizingPath` (`/a/b/` and `/a/./b` are `/a/b`).
    static func isRefresh(of path: String, loadedPath: String?, isLoaded: Bool) -> Bool {
        guard isLoaded, let loadedPath, !path.isEmpty else { return false }
        return (path as NSString).standardizingPath == (loadedPath as NSString).standardizingPath
    }
}
