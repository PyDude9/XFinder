import Foundation

/// XF-T30 W8 — cloud providers as `~/Library/CloudStorage/<Provider>-<account>` folders (Google Drive per account, Dropbox,
/// OneDrive, Box…) plus iCloud Drive (handled separately — `SidebarSources.loadICloudDrivePath`, not this parser). Pure
/// parsing, symlinked into the test package.
///
/// Measured (2026-10-25, this machine's own `~/Library/CloudStorage`, positive control): `OneDrive-Personal` and
/// `iCloudDrive-iCloudDrive (21-4-25 21:57)` are the on-disk folder names macOS itself creates — confirming the
/// `<Provider>[-<suffix>]` shape this parser splits on. Google Drive and Dropbox account/team suffixes are documented in
/// `docs/specs/XF-T30-w5b-w8-contract.md` §W8 and `spec-cloud.md` §1 (not reproducible on this machine — no Drive/Dropbox
/// app installed — so those names are parsed from the documented shape, not an on-disk sample).
struct CloudProvider: Equatable, Hashable, Sendable {
    enum Kind: String, Sendable { case iCloud, googleDrive, dropbox, oneDrive, box, other }
    var kind: Kind
    var account: String?
    var displayName: String
    var rootPath: String
}

enum CloudProviders {
    /// One folder name under `~/Library/CloudStorage` → provider (nil for names that are not provider roots, e.g. the
    /// `iCloudDrive-*` folder macOS also places there — iCloud Drive is surfaced through its own dedicated path, not
    /// through this generic CloudStorage enumeration, per spec §1 "iCloud Drive riêng").
    ///
    /// Recognized shapes (spec §W8, `CloudProvider.Kind` order): `GoogleDrive-<email>` (account = the email, kept
    /// verbatim — it is itself the sidebar label per spec §2), `Dropbox` (no account, single-account only),
    /// `Dropbox-<team>` (account = team name — multiple Dropbox team spaces mount side by side), `OneDrive-<name>`
    /// (account = the business/org name OneDrive mounts under), `OneDrive-Personal` (the literal personal-account
    /// folder name OneDrive itself creates — account left `nil`, matching Dropbox's single-account shape rather than
    /// surfacing the literal word "Personal" as an account label), `Box-Box` (Box's folder literally doubles its own
    /// name — account `nil`). Anything else under CloudStorage that is not the iCloud Drive folder becomes `.other`
    /// with the raw folder name as both account and display name, per spec §1 "generic ~/Library/CloudStorage
    /// provider enumeration, Finder-style" — an unrecognized/future provider still shows up rather than vanishing.
    static func parse(folderName: String, root: String) -> CloudProvider? {
        guard !folderName.isEmpty else { return nil }
        let rootPath = root + "/" + folderName
        if folderName.hasPrefix("iCloudDrive") { return nil }

        if let email = suffix(of: folderName, afterPrefix: "GoogleDrive-"), !email.isEmpty {
            return CloudProvider(kind: .googleDrive, account: email, displayName: email, rootPath: rootPath)
        }
        if folderName == "Dropbox" {
            return CloudProvider(kind: .dropbox, account: nil, displayName: "Dropbox", rootPath: rootPath)
        }
        if let team = suffix(of: folderName, afterPrefix: "Dropbox-"), !team.isEmpty {
            return CloudProvider(kind: .dropbox, account: team, displayName: "Dropbox – \(team)", rootPath: rootPath)
        }
        if folderName == "OneDrive-Personal" {
            return CloudProvider(kind: .oneDrive, account: nil, displayName: "OneDrive", rootPath: rootPath)
        }
        if let org = suffix(of: folderName, afterPrefix: "OneDrive-"), !org.isEmpty {
            return CloudProvider(kind: .oneDrive, account: org, displayName: "OneDrive – \(org)", rootPath: rootPath)
        }
        if folderName == "Box-Box" {
            return CloudProvider(kind: .box, account: nil, displayName: "Box", rootPath: rootPath)
        }
        return CloudProvider(kind: .other, account: folderName, displayName: folderName, rootPath: rootPath)
    }

    /// Whether `path` is inside any provider root (cloud rules apply). Checked on path components, not a bare prefix
    /// match, so a sibling folder whose name merely starts with a provider's folder name — e.g.
    /// `.../CloudStorage/Dropbox2` next to `.../CloudStorage/Dropbox` — is never mistaken for being inside it.
    static func provider(containing path: String, in providers: [CloudProvider]) -> CloudProvider? {
        let pathComponents = (path as NSString).pathComponents
        for provider in providers {
            let rootComponents = (provider.rootPath as NSString).pathComponents
            guard pathComponents.count >= rootComponents.count else { continue }
            if Array(pathComponents.prefix(rootComponents.count)) == rootComponents {
                return provider
            }
        }
        return nil
    }

    /// `folderName == "<prefix>something"` → `"something"`; nil when `folderName` is exactly `prefix` with nothing
    /// after it (an empty suffix is not a valid account/team/org name) or does not start with `prefix` at all.
    private static func suffix(of folderName: String, afterPrefix prefix: String) -> String? {
        guard folderName.hasPrefix(prefix) else { return nil }
        let rest = String(folderName.dropFirst(prefix.count))
        return rest.isEmpty ? nil : rest
    }
}
