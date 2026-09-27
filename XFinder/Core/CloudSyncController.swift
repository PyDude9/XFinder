import Foundation
import AppKit

/// Clipboard sync over iCloud key-value storage, for a future iPhone client.
///
/// **What this is.** `NSUbiquitousKeyValueStore` is Apple's built-in
/// key-value iCloud store: no server, no account handling, no CloudKit schema.
/// It syncs a small dictionary between every device signed into the same Apple
/// ID and running an app with the same iCloud container. That is exactly the
/// shape of a clipboard history head.
///
/// **Hard limits (Apple's, not ours) — the UI states these plainly:**
/// - 1 MB total, 1024 keys. So only *text* items are synced, capped and
///   truncated; images and files stay on the Mac.
/// - Delivery is best-effort and can lag; it is not a live channel.
///
/// **Requires an entitlement.** `com.apple.developer.ubiquity-kvstore-identifier`
/// must be in the app's entitlements and the bundle ID registered to a paid
/// Apple Developer account. Until that exists this reports "chưa cấu hình"
/// instead of pretending to sync — `isAvailable` is a real runtime check.
@MainActor
@Observable
final class CloudSyncController {
    static let shared = CloudSyncController()

    enum Status: Equatable {
        case disabled
        case unavailable(String)
        case ready(itemCount: Int, lastSync: Date?)
    }

    private(set) var status: Status = .disabled

    private let store = NSUbiquitousKeyValueStore.default
    private let payloadKey = "clipboard.items"
    private let stampKey = "clipboard.updatedAt"
    /// Well under the 1 MB ceiling, leaving room for metadata.
    private let maxItems = 60
    private let maxCharsPerItem = 2000

    private init() {}

    var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "sync.icloudClipboard") as? Bool ?? false
    }

    /// The only honest availability test: iCloud KVS returns a nil ubiquity
    /// token when the entitlement is missing or the user is not signed in.
    var isAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    func applySettings() {
        guard isEnabled else {
            NotificationCenter.default.removeObserver(self)
            status = .disabled
            return
        }
        guard isAvailable else {
            status = .unavailable(L10n.t("Chưa đăng nhập iCloud, hoặc XFinder chưa có entitlement iCloud (cần tài khoản Apple Developer trả phí)."))
            return
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(remoteChanged),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store)
        store.synchronize()
        refreshStatus()
    }

    /// Pushes the newest text items. Images/files are intentionally skipped —
    /// they would blow the 1 MB budget in a single item.
    func push(_ records: [ClipboardRecord]) {
        guard isEnabled, isAvailable else { return }
        let payload: [[String: String]] = records
            .filter { $0.type == .text || $0.type == .code || $0.type == .link }
            .prefix(maxItems)
            .compactMap { record in
                guard let text = record.textSnippet, !text.isEmpty else { return nil }
                return [
                    "id": record.id.uuidString,
                    "text": String(text.prefix(maxCharsPerItem)),
                    "app": record.sourceAppName ?? "",
                    "at": String(record.timestamp.timeIntervalSince1970),
                ]
            }
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              data.count < 900_000 else { return }
        store.set(data, forKey: payloadKey)
        store.set(Date().timeIntervalSince1970, forKey: stampKey)
        store.synchronize()
        refreshStatus()
    }

    /// Items pushed by another device.
    func pull() -> [(id: String, text: String, app: String, at: Date)] {
        guard isEnabled, isAvailable,
              let data = store.data(forKey: payloadKey),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: String]]
        else { return [] }
        return raw.compactMap { dict in
            guard let id = dict["id"], let text = dict["text"] else { return nil }
            let at = Double(dict["at"] ?? "") ?? 0
            return (id, text, dict["app"] ?? "", Date(timeIntervalSince1970: at))
        }
    }

    @objc private func remoteChanged(_ note: Notification) {
        Task { @MainActor in refreshStatus() }
    }

    private func refreshStatus() {
        let count = pull().count
        let stamp = store.double(forKey: stampKey)
        status = .ready(itemCount: count,
                        lastSync: stamp > 0 ? Date(timeIntervalSince1970: stamp) : nil)
    }
}
