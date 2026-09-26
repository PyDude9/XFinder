import Foundation
import AppKit

/// Helper supporting Browser Native Messaging protocol (`com.xfinder.helper`).
/// Reads 32-bit length-prefixed JSON payloads from standard input / extension communication,
/// decoding tab captures into TabPreviewCache.
public final class XFinderBrowserHelper: @unchecked Sendable {
    public static let shared = XFinderBrowserHelper()

    public struct TabMessage: Codable {
        public let tabId: String
        public let dataUrl: String?
        public let title: String?
        public let url: String?
    }

    public init() {}

    /// Process a received JSON payload from Chrome/Edge extension.
    public func processMessage(data: Data) -> Bool {
        guard let message = try? JSONDecoder().decode(TabMessage.self, from: data) else {
            return false
        }

        if let dataUrl = message.dataUrl,
           let base64String = dataUrl.components(separatedBy: ",").last,
           let imageData = Data(base64Encoded: base64String),
           let img = NSImage(data: imageData) {
            let scale = NSScreen.main?.backingScaleFactor ?? 2.0
            if let rep = img.representations.first, rep.pixelsWide > 0, rep.pixelsHigh > 0 {
                img.size = NSSize(width: CGFloat(rep.pixelsWide) / scale, height: CGFloat(rep.pixelsHigh) / scale)
            }
            TabPreviewCache.shared.setPreview(tabId: message.tabId, image: img)
            return true
        }

        return false
    }
}
