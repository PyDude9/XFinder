import Foundation

/// The pure half of "live numbers in the menu bar". Job: *"glance at the menu bar and know how the
/// machine is doing, without opening anything."*
///
/// Formatting is here, not in the controller, because the menu bar punishes two things that are
/// easy to get wrong and easy to test: **jitter** (a title whose width changes every tick shoves
/// every neighbouring icon left and right) and **fabrication** (a reading the machine does not
/// publish must render as "–", never as 0). Numbers are padded with FIGURE SPACE (U+2007), which
/// is exactly one digit wide in the system font, so "7%" and "99%" occupy the same width.
enum MenuBarReadouts {

    enum Kind: String, CaseIterable, Codable {
        case cpu, memory, gpu, socTemp, battery, netDown, netUp

        var titleKey: String {
            switch self {
            case .cpu:      return "CPU"
            case .memory:   return "Bộ nhớ đã dùng"
            case .gpu:      return "GPU"
            case .socTemp:  return "Nhiệt độ SoC"
            case .battery:  return "Pin"
            case .netDown:  return "Tải xuống"
            case .netUp:    return "Tải lên"
            }
        }
        var symbol: String {
            switch self {
            case .cpu: return "cpu"
            case .memory: return "memorychip"
            case .gpu: return "rectangle.3.group"
            case .socTemp: return "thermometer.medium"
            case .battery: return "battery.75"
            case .netDown: return "arrow.down"
            case .netUp: return "arrow.up"
            }
        }
        /// Label shown before the number. Stored as a store KEY (resolved by the caller through
        /// `L10n.t`); "" means the value is self-explanatory.
        var labelKey: String {
            switch self {
            case .cpu: return "CPU"
            case .memory: return "RAM"
            case .gpu: return "GPU"
            case .socTemp: return ""
            case .battery: return "PIN"
            case .netDown: return "↓"
            case .netUp: return "↑"
            }
        }
    }

    static let selectionKey = "menubar.readouts"
    static let defaultSelection: [Kind] = [.cpu, .memory]
    static let intervalChoices: [Int] = [5, 15, 30, 60]
    static let defaultInterval = 15

    // MARK: Selection persistence

    static func encode(_ kinds: [Kind]) -> String { kinds.map(\.rawValue).joined(separator: ",") }

    /// Order is kept (it is the display order); unknown ids and duplicates are dropped.
    static func decode(_ s: String?) -> [Kind] {
        guard let s else { return defaultSelection }
        var seen = Set<Kind>(), out: [Kind] = []
        for part in s.split(separator: ",") {
            guard let k = Kind(rawValue: part.trimmingCharacters(in: .whitespaces)), !seen.contains(k) else { continue }
            seen.insert(k); out.append(k)
        }
        return out
    }

    static func validInterval(_ seconds: Int) -> Int {
        intervalChoices.contains(seconds) ? seconds : defaultInterval
    }

    // MARK: Values

    struct Snapshot: Equatable {
        var cpuPercent: Double?
        var memoryUsedBytes: Int64?
        var gpuPercent: Double?
        var socTemperature: Double?
        var batteryPercent: Double?
        var downKBs: Double?
        var upKBs: Double?
    }

    static let figureSpace: Character = "\u{2007}"
    static let unavailable = "–"

    /// The value text for one readout, padded to a FIXED width per kind. nil reading ⇒ "–" padded
    /// to the same width, so an unavailable sensor neither fabricates a number nor changes layout.
    static func value(_ kind: Kind, in s: Snapshot) -> String {
        switch kind {
        case .cpu:     return percent(s.cpuPercent)
        case .gpu:     return percent(s.gpuPercent)
        case .battery: return percent(s.batteryPercent)
        case .socTemp: return s.socTemperature.map { pad(String(format: "%.0f", $0), to: 3) + "°" } ?? pad(unavailable, to: 3) + "°"
        case .memory:
            guard let b = s.memoryUsedBytes else { return pad(unavailable, to: 5) }
            let gb = Double(b) / 1_073_741_824
            return pad(gb >= 10 ? String(format: "%.0fG", gb) : String(format: "%.1fG", gb), to: 5)
        case .netDown: return rate(s.downKBs)
        case .netUp:   return rate(s.upKBs)
        }
    }

    /// "12%" padded to 4 ("  12%" style, figure spaces). 100 % is the widest honest value.
    static func percent(_ v: Double?) -> String {
        guard let v, v.isFinite else { return pad(unavailable, to: 3) + "%" }
        return pad(String(format: "%.0f", min(100, max(0, v))), to: 3) + "%"
    }

    /// KB/s below 1 MB/s, MB/s above — the same rule as the Mạng page — padded to 5.
    static func rate(_ kbs: Double?) -> String {
        guard let kbs, kbs.isFinite, kbs >= 0 else { return pad(unavailable, to: 5) }
        if kbs >= 1024 { return pad(String(format: "%.1fM", kbs / 1024), to: 5) }
        return pad(String(format: "%.0fK", kbs), to: 5)
    }

    static func pad(_ s: String, to width: Int) -> String {
        let n = s.count
        return n >= width ? s : String(repeating: figureSpace, count: width - n) + s
    }

    /// The whole title. `label` resolves a label key to display text (the controller passes
    /// `L10n.t`). Empty selection ⇒ empty title, so the item is icon-only again.
    static func title(for kinds: [Kind], snapshot: Snapshot, label: (String) -> String) -> String {
        kinds.map { k in
            let l = k.labelKey.isEmpty ? "" : label(k.labelKey) + " "
            return l + value(k, in: snapshot)
        }.joined(separator: "  ")
    }
}
