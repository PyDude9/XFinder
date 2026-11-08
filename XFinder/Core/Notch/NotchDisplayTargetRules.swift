import Foundation

/// Chooses the single display that owns the interactive notch surface.
/// This is deliberately pure so screen-removal and fallback behavior can be tested without AppKit.
enum NotchDisplayTargetRules {
    enum Target: String, Equatable {
        case automatic
        case builtIn
        case main
        case specific

        static func parse(_ raw: String?) -> Target {
            raw.flatMap(Target.init(rawValue:)) ?? .automatic
        }
    }

    struct Display: Equatable {
        let id: UInt32
        let isMain: Bool
        let hasPhysicalNotch: Bool
    }

    enum Fallback: Equatable {
        case builtInUnavailable
        case mainUnavailable
        case selectedDisplayUnavailable
    }

    struct Resolution: Equatable {
        let displayID: UInt32
        let fallback: Fallback?
    }

    /// `busy` preserves the current display while the user is interacting with an open surface or a running task.
    /// If that display was disconnected, selection resumes through the requested policy and returns a fallback.
    static func resolve(target: Target, selectedDisplayID: UInt32?, displays: [Display],
                        pointerDisplayID: UInt32? = nil, activeDisplayID: UInt32? = nil,
                        busy: Bool = false) -> Resolution? {
        let connected = uniqueDisplays(displays)
        guard !connected.isEmpty else { return nil }

        if busy, let activeDisplayID, connected.contains(where: { $0.id == activeDisplayID }) {
            return Resolution(displayID: activeDisplayID, fallback: nil)
        }

        switch target {
        case .automatic:
            if let pointerDisplayID, connected.contains(where: { $0.id == pointerDisplayID }) {
                return Resolution(displayID: pointerDisplayID, fallback: nil)
            }
            if let activeDisplayID, connected.contains(where: { $0.id == activeDisplayID }) {
                return Resolution(displayID: activeDisplayID, fallback: nil)
            }
            if let builtIn = connected.first(where: \.hasPhysicalNotch) {
                return Resolution(displayID: builtIn.id, fallback: nil)
            }
            return Resolution(displayID: mainOrFirst(in: connected).id, fallback: nil)

        case .builtIn:
            if let builtIn = connected.first(where: \.hasPhysicalNotch) {
                return Resolution(displayID: builtIn.id, fallback: nil)
            }
            return Resolution(displayID: mainOrFirst(in: connected).id, fallback: .builtInUnavailable)

        case .main:
            if let main = connected.first(where: \.isMain) {
                return Resolution(displayID: main.id, fallback: nil)
            }
            return Resolution(displayID: connected[0].id, fallback: .mainUnavailable)

        case .specific:
            if let selectedDisplayID, connected.contains(where: { $0.id == selectedDisplayID }) {
                return Resolution(displayID: selectedDisplayID, fallback: nil)
            }
            return Resolution(displayID: mainOrFirst(in: connected).id, fallback: .selectedDisplayUnavailable)
        }
    }

    private static func uniqueDisplays(_ displays: [Display]) -> [Display] {
        var seen = Set<UInt32>()
        return displays
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.id < $1.id }
    }

    private static func mainOrFirst(in displays: [Display]) -> Display {
        displays.first(where: \.isMain) ?? displays[0]
    }
}
