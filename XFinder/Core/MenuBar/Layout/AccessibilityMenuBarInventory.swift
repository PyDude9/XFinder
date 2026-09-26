import AppKit
import ApplicationServices

@MainActor
public protocol MenuBarInventoryProviding: AnyObject {
    var isAuthorized: Bool { get }
    func requestAuthorization()
    func snapshot(completion: @escaping @MainActor ([MenuBarInventoryItem]) -> Void)
}

@MainActor
public final class AccessibilityMenuBarInventory: MenuBarInventoryProviding {
    private static let messagingTimeout: Float = 0.1
    private var hasRequestedAuthorization = false

    public init() {}

    public var isAuthorized: Bool {
        return AXIsProcessTrusted()
    }

    public func requestAuthorization() {
        guard !hasRequestedAuthorization else { return }
        hasRequestedAuthorization = true
        let key = "AXTrustedCheckOptionPrompt" as CFString
        let options = [key: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    public func snapshot(completion: @escaping @MainActor ([MenuBarInventoryItem]) -> Void) {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.processIdentifier != ownPID && $0.bundleURL?.pathExtension == "app" }
            .map { (pid: $0.processIdentifier, bundleIdentifier: $0.bundleIdentifier) }

        DispatchQueue.global(qos: .userInitiated).async {
            let items = Self.statusItems(of: apps)
            DispatchQueue.main.async { completion(items) }
        }
    }

    private static func statusItems(of apps: [(pid: pid_t, bundleIdentifier: String?)]) -> [MenuBarInventoryItem] {
        var items: [MenuBarInventoryItem] = []
        for app in apps {
            let element = AXUIElementCreateApplication(app.pid)
            AXUIElementSetMessagingTimeout(element, messagingTimeout)
            var barValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, "AXExtrasMenuBar" as CFString, &barValue) == .success,
                  let bar = barValue else { continue }
            var childrenValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(bar as! AXUIElement, kAXChildrenAttribute as CFString, &childrenValue) == .success,
                  let children = childrenValue as? [AXUIElement] else { continue }
            for child in children {
                guard let frame = frame(of: child) else { continue }
                items.append(MenuBarInventoryItem(bundleIdentifier: app.bundleIdentifier, frame: frame))
            }
        }
        return items
    }

    public static func ownStatusItemFrame(matching description: String? = nil) -> CGRect? {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let element = AXUIElementCreateApplication(ownPID)
        AXUIElementSetMessagingTimeout(element, messagingTimeout)
        var barValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXExtrasMenuBar" as CFString, &barValue) == .success,
              let bar = barValue else { return nil }
        var childrenValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(bar as! AXUIElement, kAXChildrenAttribute as CFString, &childrenValue) == .success,
              let children = childrenValue as? [AXUIElement], !children.isEmpty else { return nil }

        if let targetDesc = description {
            for child in children {
                var descVal: CFTypeRef?
                AXUIElementCopyAttributeValue(child, kAXDescriptionAttribute as CFString, &descVal)
                if let desc = descVal as? String, desc == targetDesc, let f = frame(of: child) {
                    return f
                }
            }
        }
        let frames = children.compactMap { frame(of: $0) }
        return frames.min(by: { $0.minX < $1.minX })
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(positionValue as! AXValue, .cgPoint, &position)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        return CGRect(origin: position, size: size)
    }
}
