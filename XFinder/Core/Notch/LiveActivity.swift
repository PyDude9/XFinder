import Foundation

/// Short-lived notices shown at the notch (B4): power, network, Caps Lock, Bluetooth, alerts.
/// Pure: every "did something change worth saying?" rule, and the queue that decides what shows
/// when several arrive together. Sources are event-driven (IOPS notification, NWPathMonitor,
/// flagsChanged, IOBluetooth connect notifications); nothing polls.
enum LiveActivity {

    enum Kind: String, CaseIterable { case power, network, capsLock, bluetooth, alert }

    enum Tint: Equatable { case neutral, good, warning, bad }

    struct Item: Equatable {
        let kind: Kind
        let symbol: String
        /// Store key for the headline (the view calls L10n.t).
        let titleKey: String
        /// Already-formatted detail shown verbatim: a percentage, a device name, or an alert body the caller localised.
        let detail: String?
        let tint: Tint
        var duration: TimeInterval = 3
    }

    // MARK: Power

    struct PowerState: Equatable {
        var onAC: Bool
        var percent: Int?
        var charging: Bool
        var charged: Bool
    }

    static let lowBattery = 20, criticalBattery = 10

    /// Measured on this Mac: on AC at 80 %, `IsCharging` false and `IsCharged` false — the battery is
    /// being HELD by optimised charging. So "plugged in" says whether it is charging or holding, and
    /// "full" fires only when the OS itself reports charged; nothing assumes 100 % will come.
    static func powerItems(old: PowerState?, new: PowerState) -> [Item] {
        guard let old else { return [] }                 // the first reading is a baseline, not news
        let pct = new.percent.map { "\($0)%" }
        var out: [Item] = []
        if !old.onAC && new.onAC {
            out.append(Item(kind: .power, symbol: new.charging ? "bolt.fill" : "powerplug.fill",
                            titleKey: new.charging ? "Đang sạc" : "Đã cắm sạc, đang giữ mức pin",
                            detail: pct, tint: .good))
        } else if old.onAC && !new.onAC {
            out.append(Item(kind: .power, symbol: "battery.75", titleKey: "Đang dùng pin", detail: pct, tint: .neutral))
        }
        if new.onAC && new.charged && !old.charged {
            out.append(Item(kind: .power, symbol: "battery.100.bolt", titleKey: "Pin đã đầy", detail: pct, tint: .good))
        }
        if !new.onAC, let n = new.percent, let o = old.percent {
            if n <= criticalBattery && o > criticalBattery {
                out.append(Item(kind: .power, symbol: "battery.0", titleKey: "Pin rất yếu", detail: pct, tint: .bad, duration: 5))
            } else if n <= lowBattery && o > lowBattery {
                out.append(Item(kind: .power, symbol: "battery.25", titleKey: "Pin yếu", detail: pct, tint: .warning, duration: 4))
            }
        }
        return out
    }

    // MARK: Network, Caps Lock, Bluetooth

    static func networkItem(wasOnline: Bool?, isOnline: Bool) -> Item? {
        guard let wasOnline, wasOnline != isOnline else { return nil }
        return isOnline
            ? Item(kind: .network, symbol: "wifi", titleKey: "Đã có mạng trở lại", detail: nil, tint: .good)
            : Item(kind: .network, symbol: "wifi.slash", titleKey: "Mất kết nối mạng", detail: nil, tint: .bad, duration: 4)
    }

    static func capsLockItem(wasOn: Bool?, isOn: Bool) -> Item? {
        guard let wasOn, wasOn != isOn else { return nil }
        return Item(kind: .capsLock, symbol: isOn ? "capslock.fill" : "capslock",
                    titleKey: isOn ? "Caps Lock đang bật" : "Caps Lock đã tắt", detail: nil,
                    tint: isOn ? .warning : .neutral, duration: 1.6)
    }

    static func bluetoothItem(name: String, connected: Bool) -> Item {
        Item(kind: .bluetooth, symbol: connected ? "headphones" : "headphones.slash" ,
             titleKey: connected ? "Đã kết nối" : "Đã ngắt kết nối", detail: name,
             tint: connected ? .good : .neutral)
    }

    // MARK: Queue

    /// What is on screen and what waits. Same-kind notices REPLACE each other — a network that drops
    /// and returns within a second shows only "back online", and Caps Lock tapped twice shows the
    /// final state — so a flapping source can never stack up a backlog.
    struct Queue: Equatable {
        private(set) var current: Item?
        private(set) var pending: [Item] = []
        static let maxPending = 4

        /// Returns true when `current` changed (the caller re-renders and restarts the timer).
        @discardableResult
        mutating func push(_ item: Item) -> Bool {
            if current == nil { current = item; return true }
            if current?.kind == item.kind { current = item; return true }
            if let i = pending.firstIndex(where: { $0.kind == item.kind }) { pending[i] = item; return false }
            pending.append(item)
            if pending.count > Self.maxPending { pending.removeFirst(pending.count - Self.maxPending) }
            return false
        }

        /// The shown item's time is up: advance. Returns the new current (nil ⇒ nothing left).
        @discardableResult
        mutating func advance() -> Item? {
            current = pending.isEmpty ? nil : pending.removeFirst()
            return current
        }

        mutating func clear() { current = nil; pending = [] }
    }
}
