import Foundation

/// The pure half of first-run setup. Job: *"on first launch, let me choose what XFinder runs and
/// ask me only for the permissions that choice needs."*
///
/// This replaces the old behaviour of requesting Accessibility, Screen Recording and Bluetooth the
/// moment the main window appeared — whether or not any feature that uses them was on.
enum Onboarding {

    static let completedKey = "onboarding.completedVersion"
    /// Bump to show setup again to everyone (a new permission-bearing feature, a changed default).
    static let currentVersion = 1

    static func shouldShow(completedVersion: Int?) -> Bool { (completedVersion ?? 0) < currentVersion }

    struct Preset: Equatable {
        var id: String
        var titleKey: String
        var descriptionKey: String
        var symbol: String
        var features: Set<FeatureID>
    }

    /// Derived from the catalogue, never listed by hand: a feature added later lands in the right
    /// preset by its idle cost instead of silently missing from all of them.
    static var presets: [Preset] {
        // Minimal = nothing running AND nothing to grant (F4: capture is idle at rest but needs Screen Recording).
        let quiet = Set(FeatureCatalog.all.filter { !$0.idle.isBackgroundActive && $0.permissions.isEmpty }.map(\.id))
        let everyday = quiet.union([.clipboardShelf, .dockPreview, .snapZones, .capture])
        return [
            Preset(id: "minimal", titleKey: "Tối giản",
                   descriptionKey: "Chỉ những gì không chạy nền: gợi ý clipboard, làm sạch liên kết, bảng lệnh ⌘K.",
                   symbol: "leaf", features: quiet),
            Preset(id: "everyday", titleKey: "Hằng ngày",
                   descriptionKey: "Thêm khay ⌘⇧V, xem trước Dock và vùng bắt dính.",
                   symbol: "sun.max", features: everyday),
            Preset(id: "everything", titleKey: "Tất cả",
                   descriptionKey: "Bật mọi tính năng, kể cả giọng nói và giữ ⌘Q.",
                   symbol: "square.grid.2x2", features: Set(FeatureCatalog.all.map(\.id))),
        ]
    }

    /// The permissions the chosen features can use, in the order the Permissions tab lists them.
    static func neededPermissions(for selection: Set<FeatureID>) -> [AppPermission] {
        let used = Set(FeatureCatalog.all.filter { selection.contains($0.id) }.flatMap(\.permissions))
        return AppPermission.allCases.filter { used.contains($0) }
    }

    /// The id of the preset the selection exactly equals, if any (to highlight it).
    static func matchingPreset(_ selection: Set<FeatureID>) -> String? {
        presets.first { $0.features == selection }?.id
    }
}
