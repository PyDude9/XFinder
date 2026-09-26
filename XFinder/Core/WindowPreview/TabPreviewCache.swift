import Foundation
import AppKit

/// In-memory cache for browser tab previews captured via Native Messaging or Tab Capture.
public final class TabPreviewCache: @unchecked Sendable {
    public static let shared = TabPreviewCache()
    private let lock = NSLock()
    private var tabImages: [String: (image: NSImage, lastAccess: Date)] = [:]
    public let capacity: Int

    public init(capacity: Int = 100) {
        self.capacity = capacity
    }

    public func setPreview(tabId: String, image: NSImage) {
        lock.lock()
        defer { lock.unlock() }
        if tabImages.count >= capacity, tabImages[tabId] == nil {
            if let oldest = tabImages.min(by: { $0.value.lastAccess < $1.value.lastAccess })?.key {
                tabImages.removeValue(forKey: oldest)
            }
        }
        tabImages[tabId] = (image, Date())
    }

    public func getPreview(tabId: String) -> NSImage? {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = tabImages[tabId] else { return nil }
        tabImages[tabId] = (entry.image, Date())
        return entry.image
    }

    public func remove(tabId: String) {
        lock.lock()
        defer { lock.unlock() }
        tabImages.removeValue(forKey: tabId)
    }

    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        tabImages.removeAll()
    }
}
