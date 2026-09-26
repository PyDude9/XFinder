import Foundation

@MainActor
public enum MenuBarEngineFactory {
    public static func make(items: MenuBarItemProvider) -> MenuBarEngine {
        #if XFinder_NATIVE_VISIBILITY
        if ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27 {
            return NativeVisibilityEngine(items: items)
        }
        #endif
        return LegacyLengthEngine(items: items)
    }
}
