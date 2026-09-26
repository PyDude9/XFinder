import Foundation

public enum DeviceBatteryKind: String, Codable, Sendable, CaseIterable {
    case mac
    case mouse
    case keyboard
    case headphones
    case earbuds
    case caseCharging
    case watch
    case tablet
    case phone
    case other

    public var iconName: String {
        switch self {
        case .mac:          return "macbook"
        case .mouse:        return "magicmouse"
        case .keyboard:     return "keyboard"
        case .headphones:   return "headphones"
        case .earbuds:      return "airpodspro"
        case .caseCharging: return "airpodspro.chargingcase"
        case .watch:        return "applewatch"
        case .tablet:       return "ipad"
        case .phone:        return "iphone"
        case .other:        return "battery.100"
        }
    }

    public static func infer(from name: String, usagePage: Int? = nil, usage: Int? = nil) -> DeviceBatteryKind {
        let lower = name.lowercased()
        if lower.contains("case") {
            return .caseCharging
        }
        if lower.contains("airpods max") || lower.contains("beats studio") || lower.contains("headphone") || lower.contains("headset") {
            return .headphones
        }
        if lower.contains("airpods") || lower.contains("buds") || lower.contains("earbud") {
            return .earbuds
        }
        if lower.contains("watch") {
            return .watch
        }
        if lower.contains("ipad") {
            return .tablet
        }
        if lower.contains("iphone") {
            return .phone
        }
        if lower.contains("mouse") || lower.contains("trackpad") || lower.contains("bskv3p") || lower.contains("mx master") || (usagePage == 1 && (usage == 2 || usage == 1)) {
            return .mouse
        }
        if lower.contains("keyboard") || lower.contains("keychron") || (usagePage == 1 && usage == 6) {
            return .keyboard
        }
        if lower.contains("macbook") || lower.contains("internalbattery") {
            return .mac
        }
        return .other
    }
}

public enum BatterySource: String, Codable, Sendable {
    case mac
    case hid
    case bluetooth
}

public struct ConnectedDeviceBattery: Identifiable, Hashable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let kind: DeviceBatteryKind
    public let percent: Int
    public let isCharging: Bool
    public let source: BatterySource
    public let lastUpdated: Date
    public let isConnected: Bool
    public let leftPercent: Int?
    public let rightPercent: Int?
    public let casePercent: Int?

    public var isLowBattery: Bool {
        percent > 0 && percent < 20
    }

    public var hasMultiBattery: Bool {
        leftPercent != nil || rightPercent != nil || casePercent != nil
    }

    public var multiBatterySubtitle: String {
        let l = leftPercent.map { "\($0)%" } ?? "--"
        let r = rightPercent.map { "\($0)%" } ?? "--"
        let c = casePercent.map { "\($0)%" } ?? "--"
        return "L:\(l)  R:\(r)  Case:\(c)"
    }

    public init(
        id: String,
        name: String,
        kind: DeviceBatteryKind,
        percent: Int,
        isCharging: Bool = false,
        source: BatterySource,
        lastUpdated: Date = Date(),
        isConnected: Bool = true,
        leftPercent: Int? = nil,
        rightPercent: Int? = nil,
        casePercent: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.percent = percent == -1 ? -1 : max(0, min(100, percent))
        self.isCharging = isCharging
        self.source = source
        self.lastUpdated = lastUpdated
        self.isConnected = isConnected
        self.leftPercent = leftPercent.map { max(0, min(100, $0)) }
        self.rightPercent = rightPercent.map { max(0, min(100, $0)) }
        self.casePercent = casePercent.map { max(0, min(100, $0)) }
    }
}

