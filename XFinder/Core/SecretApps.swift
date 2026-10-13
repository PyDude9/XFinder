import Foundation

/// Password managers and secret stores, matched as lowercase FRAGMENTS of a bundle id, app name or executable name.
/// One list for every surface that must stay away from secrets: the clipboard capture filter (`ClipboardManager`),
/// the Clipboard MCP fence (`MCPProtocol`) and Smart Selection's badge. Before this file the MCP copy had drifted —
/// it lacked `onepassword`, `keychain`, `passwords`, `strongbox`, `proton.pass`, `roboform` (harmless only because the
/// capture filter had already kept those clips out).
enum SecretApps {
    static let fragments: [String] = [
        "1password", "onepassword", "bitwarden", "keepass", "lastpass", "dashlane", "keychain", "passwords",
        "enpass", "strongbox", "proton.pass", "roboform", "nordpass",
    ]

    /// True when any of the given identifiers (bundle id, app name, executable name) contains a fragment.
    static func matches(_ identifiers: String?...) -> Bool {
        let hay = identifiers.compactMap { $0?.lowercased() }.filter { !$0.isEmpty }
        return fragments.contains { f in hay.contains { $0.contains(f) } }
    }
}
