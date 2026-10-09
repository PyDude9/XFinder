import Foundation

/// The pure half of the sound-output switcher: which CoreAudio devices are real output choices,
/// in what order, with what icon. No CoreAudio here, so every rule is pinned by a test.
///
/// The job: *"play sound through the headphones/speaker I mean, without opening System Settings."*
struct RawAudioDevice: Equatable {
    var id: UInt32
    var uid: String
    var name: String
    /// Sum of `mNumberChannels` over the device's OUTPUT streams. 0 ⇒ an input-only device.
    var outputChannels: Int
    var isHidden: Bool
    var isAlive: Bool
    /// `kAudioDevicePropertyTransportType` as its four-character code, e.g. `bltn`, `blue`, `grup`.
    var transport: String
}

struct AudioOutputDevice: Identifiable, Equatable {
    let id: UInt32
    let uid: String
    let name: String
    let transport: String
    /// SF Symbol name — every one this can return is verified to exist by a test.
    var symbol: String { AudioOutputList.symbol(forTransport: transport) }
}

enum AudioOutputList {

    /// What may appear in the picker. On a machine with nothing plugged in, CoreAudio still
    /// lists the built-in *microphone* and Continuity microphones as devices — they have no output
    /// channels and must never be offered as somewhere to play sound (measured on this Mac: 3
    /// devices, only 1 an output).
    static func build(from raw: [RawAudioDevice]) -> [AudioOutputDevice] {
        var seen = Set<String>()
        var out: [AudioOutputDevice] = []
        for d in raw {
            guard d.outputChannels > 0,
                  !d.isHidden,
                  d.isAlive,
                  !d.name.trimmingCharacters(in: .whitespaces).isEmpty
            else { continue }
            // CoreAudio can report one physical device twice; the UID is its identity.
            guard seen.insert(d.uid).inserted else { continue }
            out.append(AudioOutputDevice(id: d.id, uid: d.uid, name: d.name, transport: d.transport))
        }
        // Alphabetical and stable: the list must not reorder itself when the selection changes.
        return out.sorted {
            let c = $0.name.localizedCaseInsensitiveCompare($1.name)
            return c == .orderedSame ? $0.id < $1.id : c == .orderedAscending
        }
    }

    // MARK: Icons

    /// Every symbol `symbol(forTransport:)` can return, for the existence test.
    static let allSymbols = ["laptopcomputer", "headphones", "cable.connector", "tv", "airplayaudio",
                             "waveform", "square.stack.3d.up", "speaker.wave.2"]

    static func symbol(forTransport transport: String) -> String {
        switch transport.trimmingCharacters(in: .whitespaces) {
        case "bltn":         return "laptopcomputer"
        case "blue", "bleL": return "headphones"
        case "usb":          return "cable.connector"
        case "hdmi", "dprt": return "tv"
        case "airp":         return "airplayaudio"
        case "virt":         return "waveform"
        case "grup":         return "square.stack.3d.up"
        default:             return "speaker.wave.2"
        }
    }

    // MARK: Which defaults to move

    /// macOS keeps two defaults: where sound plays, and where alert sounds ("system output") play.
    /// If the user left them unified, switching should move both — otherwise the Mac alert beeps
    /// from the old speaker. If they deliberately split them (alerts on a different device), that
    /// is a choice, and a switcher must not undo it.
    static func shouldMoveSystemOutput(previousDefault: UInt32, previousSystem: UInt32) -> Bool {
        previousDefault == previousSystem
    }
}
