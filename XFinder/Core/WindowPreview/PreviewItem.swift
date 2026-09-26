import Foundation
import AppKit

/// Model representing a window preview item.
public struct PreviewItem: Identifiable, Equatable, Sendable {
    public var id: CGWindowID { windowID }
    public let windowID: CGWindowID
    public let bundleID: String
    public var title: String
    public var appName: String
    public var thumbnail: NSImage?
    public var isFrozen: Bool
    public var tabs: [BrowserTabItem]
    public var isOnOtherSpace: Bool
    public var isGroup: Bool
    public var windowCount: Int
    public var windowIDs: [CGWindowID]
    public var isStageMiniature: Bool

    public var subtitle: String {
        isOnOtherSpace ? "On another Space" : title
    }

    public init(
        windowID: CGWindowID,
        bundleID: String,
        title: String,
        appName: String = "",
        thumbnail: NSImage? = nil,
        isFrozen: Bool = false,
        tabs: [BrowserTabItem] = [],
        isOnOtherSpace: Bool = false,
        isGroup: Bool = false,
        windowCount: Int = 1,
        windowIDs: [CGWindowID] = [],
        isStageMiniature: Bool = false
    ) {
        self.windowID = windowID
        self.bundleID = bundleID
        self.title = title
        self.appName = appName
        self.thumbnail = thumbnail
        self.isFrozen = isFrozen
        self.tabs = tabs
        self.isOnOtherSpace = isOnOtherSpace
        self.isGroup = isGroup
        self.windowCount = windowCount
        self.windowIDs = windowIDs.isEmpty ? [windowID] : windowIDs
        self.isStageMiniature = isStageMiniature
    }
}

/// Model representing a collapsed group of windows on another Space for the same application.
public struct PreviewItemGroup: Identifiable, Equatable, Sendable {
    public var id: String { bundleID }
    public let bundleID: String
    public let appName: String
    public let count: Int
    public let windowIDs: [CGWindowID]
    public let isOnOtherSpace: Bool

    public init(
        bundleID: String,
        appName: String,
        count: Int,
        windowIDs: [CGWindowID],
        isOnOtherSpace: Bool = true
    ) {
        self.bundleID = bundleID
        self.appName = appName
        self.count = count
        self.windowIDs = windowIDs
        self.isOnOtherSpace = isOnOtherSpace
    }

    public func asPreviewItem() -> PreviewItem {
        PreviewItem(
            windowID: windowIDs.first ?? 0,
            bundleID: bundleID,
            title: "\(appName) • \(count) windows",
            appName: appName,
            thumbnail: nil,
            isFrozen: false,
            tabs: [],
            isOnOtherSpace: isOnOtherSpace,
            isGroup: true,
            windowCount: count,
            windowIDs: windowIDs
        )
    }
}
