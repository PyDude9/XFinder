import Foundation

/// Applies and restores macOS's `com.apple.dock mru-spaces` preference using `SpacesOrderRules`.
@MainActor
enum SpacesOrderController {
    static var isFixedEnabled: Bool {
        UserDefaults.standard.bool(forKey: SpacesOrderRules.enabledKey)
    }

    static func currentDockMRUSpaces() -> Bool? {
        guard let raw = CFPreferencesCopyAppValue(
            SpacesOrderRules.dockMRUSpacesKey as CFString,
            SpacesOrderRules.dockDomain as CFString
        ) else { return nil }
        return (raw as? Bool) ?? (raw as? NSNumber)?.boolValue
    }

    @discardableResult
    static func setFixedOrder(_ enable: Bool) -> Bool {
        let defaults = UserDefaults.standard
        let savedPrevious = defaults.object(forKey: SpacesOrderRules.savedPreviousKey) as? Bool
        let current = currentDockMRUSpaces()
        let transition = SpacesOrderRules.transition(
            enable: enable,
            currentDockMRUSpaces: current,
            savedPrevious: savedPrevious
        )

        defaults.set(enable, forKey: SpacesOrderRules.enabledKey)
        if let updated = transition.updatedSavedPrevious {
            defaults.set(updated, forKey: SpacesOrderRules.savedPreviousKey)
        } else {
            defaults.removeObject(forKey: SpacesOrderRules.savedPreviousKey)
        }

        guard transition.needsDockUpdate else { return true }
        return writeDockMRUSpaces(transition.targetDockMRUSpaces)
    }

    private static func writeDockMRUSpaces(_ value: Bool) -> Bool {
        let defaultsProc = Process()
        defaultsProc.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        defaultsProc.arguments = [
            "write",
            SpacesOrderRules.dockDomain,
            SpacesOrderRules.dockMRUSpacesKey,
            "-bool",
            value ? "true" : "false",
        ]
        defaultsProc.standardOutput = FileHandle.nullDevice
        defaultsProc.standardError = FileHandle.nullDevice
        do {
            try defaultsProc.run()
            defaultsProc.waitUntilExit()
            guard defaultsProc.terminationStatus == 0 else { return false }
        } catch {
            return false
        }

        let killProc = Process()
        killProc.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        killProc.arguments = ["Dock"]
        killProc.standardOutput = FileHandle.nullDevice
        killProc.standardError = FileHandle.nullDevice
        try? killProc.run()
        killProc.waitUntilExit()
        return true
    }
}
