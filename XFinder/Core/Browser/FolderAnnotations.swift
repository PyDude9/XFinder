import Foundation

/// XF-T32 W1 (builder `pins`) — pure rules for per-folder pins, item nicknames, folder emoji, path rewrites after a
/// rename/move, and two-way folder relations. Contract `docs/specs/XF-T32-w1-contract.md` §B. Foundation only, no disk,
/// no display strings.

// MARK: - Path keys

/// The one spelling of a path used as a storage/comparison key: trailing slashes dropped ("/a/b/" == "/a/b"), the root
/// stays "/". Nothing else is rewritten (no `..` resolution, no case folding — APFS case rules belong to the disk).
fileprivate enum AnnotationPathKey {
    static func normalized(_ path: String) -> String {
        var key: Substring = Substring(path)
        while key.count > 1, key.hasSuffix("/") {
            key = key.dropLast()
        }
        return String(key)
    }

    /// The remainder of `path` below `ancestor` ("" when they are the same path), or nil when `path` is neither
    /// `ancestor` nor inside it. Component-wise: "/a/bc" is NOT inside "/a/b". Both inputs must already be normalized.
    static func remainder(of path: String, below ancestor: String) -> Substring? {
        if path == ancestor { return Substring("") }
        let prefix: String = ancestor == "/" ? "/" : ancestor + "/"
        guard path.hasPrefix(prefix) else { return nil }
        let rest: Substring = path.dropFirst(prefix.count)
        return rest.isEmpty ? nil : rest
    }
}

// MARK: - Pins

/// Pins inside one folder (Tilde "Pin in 'Projects'"): pinned paths show in a "Pinned" block at the top of that folder.
/// Pinning the folder itself ("This folder") is `path == folder`.
enum PinRules {
    static let maxPinsPerFolder: Int = 50

    /// Splits a listing into (pinned in pin order, the rest in listing order). A pin no longer in the listing is left out
    /// of the result and returned in `stale` (the integrator cleans the store). The "This folder" pin is never stale and,
    /// if the folder itself appears in the listing, stands first in `pinned`. Duplicate pins count once.
    static func split(_ entries: [DirectoryEntry], folder: String, pins: [String])
        -> (pinned: [DirectoryEntry], rest: [DirectoryEntry], stale: [String], pinsFolderItself: Bool) {
        let folderKey: String = AnnotationPathKey.normalized(folder)
        let index: [String: DirectoryEntry] = firstEntryByKey(entries)
        var pinsFolderItself: Bool = false
        var seen: Set<String> = []
        var pinnedKeys: [String] = []
        var stale: [String] = []

        for pin in pins {
            let key: String = AnnotationPathKey.normalized(pin)
            guard !key.isEmpty, seen.insert(key).inserted else { continue }
            if key == folderKey {
                pinsFolderItself = true
                continue
            }
            if index[key] != nil {
                pinnedKeys.append(key)
            } else {
                stale.append(pin)
            }
        }

        var pinned: [DirectoryEntry] = pinnedKeys.compactMap { (key: String) -> DirectoryEntry? in index[key] }
        if pinsFolderItself, let selfEntry = index[folderKey] {
            pinned.insert(selfEntry, at: 0)
            pinnedKeys.insert(folderKey, at: 0)
        }
        let pinnedSet: Set<String> = Set(pinnedKeys)
        let rest: [DirectoryEntry] = entries.filter { (entry: DirectoryEntry) -> Bool in
            !pinnedSet.contains(AnnotationPathKey.normalized(entry.path))
        }
        return (pinned, rest, stale, pinsFolderItself)
    }

    /// Adds `path` at the end, or removes it (every spelling of it) when already pinned. At the cap ⇒ unchanged.
    static func toggled(_ pins: [String], path: String) -> [String] {
        let key: String = AnnotationPathKey.normalized(path)
        guard !key.isEmpty else { return pins }
        let isPinned: Bool = pins.contains { (pin: String) -> Bool in AnnotationPathKey.normalized(pin) == key }
        if isPinned {
            return pins.filter { (pin: String) -> Bool in AnnotationPathKey.normalized(pin) != key }
        }
        let distinctCount: Int = Set(pins.map(AnnotationPathKey.normalized)).count
        guard distinctCount < maxPinsPerFolder else { return pins }
        return pins + [key]
    }

    /// Moves the pin at `from` so it ends up at index `to` (clamped to the end). Out-of-range `from` ⇒ unchanged.
    static func moved(_ pins: [String], from: Int, to: Int) -> [String] {
        guard pins.indices.contains(from), to >= 0, from != to else { return pins }
        var result: [String] = pins
        let item: String = result.remove(at: from)
        let target: Int = min(to, result.count)
        result.insert(item, at: target)
        return result
    }

    private static func firstEntryByKey(_ entries: [DirectoryEntry]) -> [String: DirectoryEntry] {
        var index: [String: DirectoryEntry] = [:]
        index.reserveCapacity(entries.count)
        for entry in entries {
            let key: String = AnnotationPathKey.normalized(entry.path)
            if index[key] == nil { index[key] = entry }
        }
        return index
    }
}

// MARK: - Nicknames

enum NicknameRules {
    static let maxLength: Int = 60

    /// Trims both ends, turns every whitespace run (newlines, tabs, spaces) into one space, drops other control
    /// characters, cuts at `maxLength` Characters; empty ⇒ nil (= remove the nickname).
    static func normalized(_ raw: String) -> String? {
        var out: String = ""
        var pendingSpace: Bool = false
        // NFC first: a pasted or HFS+-sourced NFD nickname would otherwise be stored, searched and compared apart.
        for character in raw.precomposedStringWithCanonicalMapping {
            if isWhitespace(character) {
                pendingSpace = !out.isEmpty
                continue
            }
            if isControl(character) { continue }
            if pendingSpace {
                out.append(" ")
                pendingSpace = false
            }
            out.append(character)
        }
        guard !out.isEmpty else { return nil }
        guard out.count > maxLength else { return out }
        let cut: String = String(out.prefix(maxLength))
        let trimmed: String = cut.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// The ⌘K/filter search key of an item: folded name, then (after a NUL byte — a file name can hold a newline but
    /// never NUL — so a query never matches across the two) the folded nickname. Same folding as `EntryRules.foldBytes`.
    static func searchKey(name: String, nickname: String?) -> [UInt8] {
        var key: [UInt8] = EntryRules.foldBytes(name)
        guard let nickname, let clean = normalized(nickname) else { return key }
        key.append(0x00)
        key.append(contentsOf: EntryRules.foldBytes(clean))
        return key
    }

    private static func isWhitespace(_ character: Character) -> Bool {
        character.isWhitespace
    }

    private static func isControl(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { (scalar: Unicode.Scalar) -> Bool in
            scalar.properties.generalCategory == .control || scalar.properties.generalCategory == .format
        }
    }
}

// MARK: - Emoji

enum EmojiRules {
    /// One emoji grapheme (ZWJ sequences, flags, skin tones, keycaps, VS16, tag flags); anything else ⇒ nil. Plain
    /// letters, digits, "#" without a keycap, text-presentation symbols ("©" without VS16) are rejected.
    static func normalized(_ raw: String) -> String? {
        let trimmed: String = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 1, let grapheme = trimmed.first else { return nil }
        let scalars: [Unicode.Scalar] = Array(grapheme.unicodeScalars)
        guard scalars.allSatisfy(isEmojiComponent) else { return nil }
        if scalars.contains(textPresentationSelector) { return nil }
        return qualifies(scalars) ? trimmed : nil
    }

    private static let zeroWidthJoiner: Unicode.Scalar = "\u{200D}"
    private static let emojiPresentationSelector: Unicode.Scalar = "\u{FE0F}"
    private static let textPresentationSelector: Unicode.Scalar = "\u{FE0E}"
    private static let combiningKeycap: Unicode.Scalar = "\u{20E3}"
    private static let regionalIndicators: ClosedRange<UInt32> = 0x1F1E6...0x1F1FF
    private static let tagCharacters: ClosedRange<UInt32> = 0xE0020...0xE007F

    private static func qualifies(_ scalars: [Unicode.Scalar]) -> Bool {
        if isKeycap(scalars) { return true }
        let indicators: Int = scalars.filter(isRegionalIndicator).count
        if indicators > 0 {
            return indicators == 2 && scalars.count == 2
        }
        let bases: [Unicode.Scalar] = scalars.filter { (scalar: Unicode.Scalar) -> Bool in
            scalar.properties.isEmoji && !isKeycapBase(scalar)
        }
        if bases.contains(where: { (scalar: Unicode.Scalar) -> Bool in scalar.properties.isEmojiPresentation }) {
            return true
        }
        guard !bases.isEmpty else { return false }
        return scalars.contains(emojiPresentationSelector) || scalars.contains(zeroWidthJoiner)
    }

    /// "1️⃣", "#⃣": a keycap base, an optional VS16, then U+20E3.
    private static func isKeycap(_ scalars: [Unicode.Scalar]) -> Bool {
        guard let first = scalars.first, isKeycapBase(first), scalars.last == combiningKeycap else { return false }
        switch scalars.count {
        case 2: return true
        case 3: return scalars[1] == emojiPresentationSelector
        default: return false
        }
    }

    private static func isKeycapBase(_ scalar: Unicode.Scalar) -> Bool {
        (scalar.value >= 0x30 && scalar.value <= 0x39) || scalar == "#" || scalar == "*"
    }

    private static func isRegionalIndicator(_ scalar: Unicode.Scalar) -> Bool {
        regionalIndicators.contains(scalar.value)
    }

    private static func isEmojiComponent(_ scalar: Unicode.Scalar) -> Bool {
        let properties: Unicode.Scalar.Properties = scalar.properties
        return properties.isEmoji || properties.isEmojiModifier || scalar == zeroWidthJoiner
            || scalar == emojiPresentationSelector || scalar == textPresentationSelector || scalar == combiningKeycap
            || tagCharacters.contains(scalar.value)
    }
}

// MARK: - Path rewrite

/// Renaming/moving an item ⇒ every path key equal to `from` or below it moves to `to`.
enum PathRewrite {
    /// `path` rewritten from `from` to `to`, or nil when unrelated ("/a/bc" is unrelated to "/a/b"). Trailing slashes
    /// on any argument are ignored; the result is normalized. Empty `from`/`to` ⇒ nil.
    static func rewritten(_ path: String, from: String, to: String) -> String? {
        let pathKey: String = AnnotationPathKey.normalized(path)
        let fromKey: String = AnnotationPathKey.normalized(from)
        let toKey: String = AnnotationPathKey.normalized(to)
        guard !pathKey.isEmpty, !fromKey.isEmpty, !toKey.isEmpty else { return nil }
        guard let rest = AnnotationPathKey.remainder(of: pathKey, below: fromKey) else { return nil }
        if rest.isEmpty { return toKey }
        return toKey == "/" ? "/" + rest : toKey + "/" + rest
    }
}

// MARK: - Relations

struct FolderRelation: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var a: String
    var b: String
}

enum RelationRules {
    /// Two-way relation: no self-link, no duplicate (a,b) ~ (b,a). Stored paths are normalized.
    static func adding(_ relations: [FolderRelation], a: String, b: String) -> [FolderRelation] {
        let aKey: String = AnnotationPathKey.normalized(a)
        let bKey: String = AnnotationPathKey.normalized(b)
        guard !aKey.isEmpty, !bKey.isEmpty, aKey != bKey else { return relations }
        let exists: Bool = relations.contains { (relation: FolderRelation) -> Bool in
            let ra: String = AnnotationPathKey.normalized(relation.a)
            let rb: String = AnnotationPathKey.normalized(relation.b)
            return (ra == aKey && rb == bKey) || (ra == bKey && rb == aKey)
        }
        guard !exists else { return relations }
        return relations + [FolderRelation(id: UUID(), a: aKey, b: bKey)]
    }

    /// The other side of every relation touching `folder`, in relation order, each once; self-links ignored.
    static func related(to folder: String, in relations: [FolderRelation]) -> [String] {
        let key: String = AnnotationPathKey.normalized(folder)
        guard !key.isEmpty else { return [] }
        var seen: Set<String> = []
        var result: [String] = []
        for relation in relations {
            let ra: String = AnnotationPathKey.normalized(relation.a)
            let rb: String = AnnotationPathKey.normalized(relation.b)
            let other: String
            if ra == key { other = rb } else if rb == key { other = ra } else { continue }
            guard other != key, !other.isEmpty, seen.insert(other).inserted else { continue }
            result.append(other)
        }
        return result
    }
}
