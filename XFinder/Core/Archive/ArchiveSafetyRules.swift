import Foundation

/// One entry as the archive declares it, before anything touches the disk.
///
/// This type exists so the dangerous decisions — is this path allowed, is the batch too big, do the
/// links escape — can be answered from metadata alone, before a decoder materialises a single byte.
/// Measured 2026-11-07 (macOS 27.2): system libarchive 3.7.4 hands back the raw `../escaped.txt`,
/// the absolute entry, the absolute symlink target and duplicate names through this shape, none of
/// which `ditto`/`tar` reveal before they have already written. See
/// `docs/specs/XF-MFGAP-03-archive-safety.md` §2 and `docs/reviews/XF-MFGAP-03-archive-safety-review.md`.
///
/// `declaredSize` is untrusted: it comes from the archive's own header. The runtime must still count
/// bytes as they are decoded (stage 03B). These rules only refuse what is *already* impossible.
struct ArchiveManifestEntry: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case regular
        case directory
        case symlink
        case hardlink
        /// Device, FIFO, socket, sparse or anything the reader cannot classify.
        case unsupported
    }

    /// Exactly as the archive spells it — never pre-normalised, so a caller cannot accidentally
    /// validate a cleaned path while extracting the original one.
    var rawPath: String
    var declaredSize: Int64
    /// A false `sizeIsSet` means the format did not declare a size (streamed tar, for instance).
    var sizeIsSet: Bool
    var kind: Kind
    /// Symlink target or hardlink target, verbatim.
    var linkTarget: String?
}

/// The answer for one archive. Rejection is whole-archive: a partially-trusted batch is how a
/// hostile entry slips in behind three harmless ones.
enum ArchiveSafetyVerdict: Sendable, Equatable {
    case accepted(ArchivePlan)
    case rejected([ArchiveSafetyRules.Reason])

    var isAccepted: Bool { if case .accepted = self { return true }; return false }
    var reasons: [ArchiveSafetyRules.Reason] { if case .rejected(let r) = self { return r }; return [] }
}

/// What a caller may safely do with an accepted manifest. Sizes are conservative bounds, not
/// promises: `peakBytes` assumes every declared byte is real, which is the only safe assumption.
struct ArchivePlan: Sendable, Equatable {
    /// Entries to write, in dependency order: ordinary content first, links last.
    var orderedEntries: [ArchiveManifestEntry]
    /// Sum of declared regular-file bytes. Untrusted — enforce again while decoding.
    var declaredPayloadBytes: Int64
    /// Payload plus placement/metadata overhead and the operational reserve.
    var peakBytes: Int64
    /// Declared payload relative to compressed input size, when the input size is known.
    var expansionRatio: Double?

    var links: [ArchiveManifestEntry] { orderedEntries.filter { $0.kind == .symlink || $0.kind == .hardlink } }
}

/// Pure rules over an archive manifest. No filesystem effects, no UI strings (the view maps cases in
/// the placement stage), so every decision here is unit-testable and cannot be reached around.
enum ArchiveSafetyRules {

    // MARK: Policy

    /// Boss-reviewable numbers in one place. The spec (§5) proposes exactly these; changing one is a
    /// one-line change here plus a test row, never a scattered constant.
    struct Limits: Sendable, Equatable {
        var maxEntries = 100_000
        var maxBytesPerFile: Int64 = 8 * 1024 * 1024 * 1024          // 8 GiB
        var maxCumulativeBytes: Int64 = 16 * 1024 * 1024 * 1024      // 16 GiB
        var maxPathComponents = 128
        var maxPathBytes = 4 * 1024
        /// Ratios are only suspicious once the payload is worth the trouble; a 8 KiB fixture at
        /// 1,014× is not an attack (measured, §2).
        var expansionRatioFloorBytes: Int64 = 256 * 1024 * 1024       // 256 MiB
        var maxExpansionRatio = 1_000.0
        var capacityReserveBytes: Int64 = 64 * 1024 * 1024            // 64 MiB
        /// Per-entry placement overhead counted against capacity (name, directory entries, metadata).
        var perEntryOverheadBytes: Int64 = 4 * 1024
        var maxLinkChainDepth = 32

        static let proposed = Limits()
    }

    enum Reason: Sendable, Equatable, Hashable {
        case absolutePath(String)
        case driveOrUNCPath(String)
        case escapesRoot(String)
        case emptyPath
        case controlCharacter(String)
        case ambiguousSeparator(String)
        case pathTooLong(String, bytes: Int)
        case tooManyComponents(String, count: Int)
        case duplicatePath(String)
        /// Two names that differ only by case or Unicode composition but land on one APFS file.
        case aliasedPath(String, String)
        case fileUsedAsParent(String)
        case duplicateAfterNormalisation(String, String)
        case unsupportedEntry(String)
        /// A path that normalises to the archive root — "." or "./" — but is not a directory. The root
        /// denotes the staging directory the caller already owns, so only a directory may claim it.
        case rootEntryIsNotADirectory(String)
        case tooManyEntries(count: Int, limit: Int)
        case fileTooLarge(String, declared: Int64, limit: Int64)
        case payloadTooLarge(declared: Int64, limit: Int64)
        case sizeOverflow
        case undeclaredSize(String)
        case expansionRatioTooHigh(ratio: Double, limit: Double)
        case absoluteLink(String, target: String)
        case escapingLink(String, target: String)
        case linkCycle([String])
        case linkTargetMissing(String, target: String)
        case hardLinkOutside(String, target: String)
        case insufficientSpace(required: Int64, available: Int64)
        case spaceUnknown
    }

    // MARK: Entry point

    /// Validate one archive's declared manifest against the destination volume.
    ///
    /// `compressedSize` and `availableBytes` are optional because the caller may legitimately not
    /// know them yet; an unknown *available* size is a refusal, not a pass (never treat unknown as
    /// infinite). Pass `compressedSize` to have the ratio check applied.
    static func validate(manifest: [ArchiveManifestEntry],
                         compressedSize: Int64? = nil,
                         availableBytes: Int64? = nil,
                         limits: Limits = .proposed) -> ArchiveSafetyVerdict {

        guard !manifest.isEmpty else { return .rejected([.emptyPath]) }
        guard manifest.count <= limits.maxEntries else {
            return .rejected([.tooManyEntries(count: manifest.count, limit: limits.maxEntries)])
        }

        var reasons: [Reason] = []
        var normalised: [String: ArchiveManifestEntry] = [:]   // normalised path → entry
        var folded: [String: String] = [:]                     // APFS-collision key → first path
        var parents = Set<String>()
        var declared: Int64 = 0

        for entry in manifest {
            guard let components = components(of: entry.rawPath, limits: limits, into: &reasons) else { continue }

            // An empty component list means the path denoted the archive root itself: "." or "./".
            // `tar -cf out.tar .` is an ordinary command and emits exactly this, so it must not be
            // refused — but it also must not be allowed to turn the caller's staging root into a
            // file or a link. Only a directory may name the root, and it names something that is
            // already there.
            if components.isEmpty {
                if entry.kind != .directory { reasons.append(.rootEntryIsNotADirectory(entry.rawPath)) }
                continue
            }

            if entry.rawPath.utf8.count > limits.maxPathBytes {
                reasons.append(.pathTooLong(entry.rawPath, bytes: entry.rawPath.utf8.count))
            }

            let key = components.joined(separator: "/")
            if let existing = normalised[key] {
                // Swift `String` compares by canonical equivalence, so NFC and NFD spellings of one
                // name land on the same key *and* compare equal. Only the raw bytes separate a true
                // duplicate from an alias.
                if existing.rawPath.utf8.elementsEqual(entry.rawPath.utf8) { reasons.append(.duplicatePath(key)) }
                else { reasons.append(.aliasedPath(existing.rawPath, entry.rawPath)) }
            }
            normalised[key] = entry

            // APFS is case-insensitive and canonical-equivalence-insensitive by default. Two entries
            // that collide there would overwrite one another during staging with no rule seeing it.
            let foldKey = asciiFold(key)
            if let first = folded[foldKey], first != key { reasons.append(.aliasedPath(first, key)) }
            else { folded[foldKey] = key }

            // A path that is also a parent of another entry cannot be a file.
            for i in 1..<max(1, components.count) {
                parents.insert(components[0..<i].joined(separator: "/"))
            }

            switch entry.kind {
            case .unsupported:
                reasons.append(.unsupportedEntry(key))
            case .regular:
                guard entry.sizeIsSet else { reasons.append(.undeclaredSize(key)); continue }
                guard entry.declaredSize >= 0 else { reasons.append(.fileTooLarge(key, declared: entry.declaredSize, limit: limits.maxBytesPerFile)); continue }
                if entry.declaredSize > limits.maxBytesPerFile {
                    reasons.append(.fileTooLarge(key, declared: entry.declaredSize, limit: limits.maxBytesPerFile))
                }
                let (sum, overflow) = declared.addingReportingOverflow(entry.declaredSize)
                if overflow { reasons.append(.sizeOverflow) } else { declared = sum }
            case .symlink, .hardlink, .directory:
                break
            }
        }

        for path in parents.sorted() where normalised[path]?.kind == .regular {
            reasons.append(.fileUsedAsParent(path))
        }

        if declared > limits.maxCumulativeBytes {
            reasons.append(.payloadTooLarge(declared: declared, limit: limits.maxCumulativeBytes))
        }

        reasons.append(contentsOf: linkReasons(manifest: manifest, normalised: normalised, limits: limits))

        let ratio: Double? = {
            guard let compressedSize, compressedSize > 0, declared > limits.expansionRatioFloorBytes else { return nil }
            return Double(declared) / Double(compressedSize)
        }()
        if let ratio, ratio > limits.maxExpansionRatio {
            reasons.append(.expansionRatioTooHigh(ratio: ratio, limit: limits.maxExpansionRatio))
        }

        let (perEntry, e1) = limits.perEntryOverheadBytes.multipliedReportingOverflow(by: Int64(manifest.count))
        let (payloadPlusOverhead, e2) = declared.addingReportingOverflow(perEntry)
        let (peak, e3) = payloadPlusOverhead.addingReportingOverflow(limits.capacityReserveBytes)
        if e1 || e2 || e3 { reasons.append(.sizeOverflow) }

        // An overflowed peak is already recorded; comparing against a wrapped number would be worse
        // than not comparing at all.
        let peakIsTrustworthy = !(e1 || e2 || e3)
        if let availableBytes, peakIsTrustworthy {
            if availableBytes < peak {
                reasons.append(.insufficientSpace(required: peak, available: availableBytes))
            }
        } else if availableBytes == nil, reasons.isEmpty {
            // Never treat unknown capacity as infinite. When the archive is already rejected the
            // actionable archive reasons are reported instead of a second, vaguer one.
            reasons.append(.spaceUnknown)
        }

        guard reasons.isEmpty else { return .rejected(dedupe(reasons)) }
        // The root entry ("./") names the staging directory the caller already owns. It is legitimate
        // input but there is nothing to create for it, so it never reaches the ordered plan.
        let ordered = manifest.filter { entry in
            var scratch: [Reason] = []
            return components(of: entry.rawPath, limits: limits, into: &scratch).map { !$0.isEmpty } ?? false
        }
        return .accepted(ArchivePlan(orderedEntries: dependencyOrder(ordered),
                                     declaredPayloadBytes: declared,
                                     peakBytes: peak,
                                     expansionRatio: ratio))
    }

    /// Content first, links last: a link materialised before its target can be used as a write
    /// primitive for the entries that follow it.
    static func dependencyOrder(_ manifest: [ArchiveManifestEntry]) -> [ArchiveManifestEntry] {
        let links = manifest.filter { $0.kind == .symlink || $0.kind == .hardlink }
        let rest = manifest.filter { $0.kind != .symlink && $0.kind != .hardlink }
        return rest + links
    }

    // MARK: Paths

    /// Split a raw archive path into safe components, or return nil and record why.
    ///
    /// Deliberately rejects rather than repairs. `ditto` silently strips a leading `/` and
    /// normalises `..` (measured, §2) — that is a tool accident, not a policy, and relying on it
    /// would mean the app's guarantee changes with the OS.
    static func components(of raw: String, limits: Limits, into reasons: inout [Reason]) -> [String]? {
        guard !raw.isEmpty else { reasons.append(.emptyPath); return nil }

        if raw.utf8.contains(0) { reasons.append(.controlCharacter(raw)); return nil }
        if raw.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }) {
            reasons.append(.controlCharacter(raw)); return nil
        }
        // UNC before the absolute check, or "//server/share" reports as a plain absolute path.
        if raw.hasPrefix("//") || raw.hasPrefix("\\\\") { reasons.append(.driveOrUNCPath(raw)); return nil }
        if raw.hasPrefix("/") { reasons.append(.absolutePath(raw)); return nil }
        // A colon is legal on APFS but Finder renders it as a path separator, and this app already
        // treats it as unsafe when building archive names (`ArchiveEngine.archiveName`).
        if raw.contains(":") { reasons.append(.ambiguousSeparator(raw)); return nil }
        if raw.contains("\\") { reasons.append(.ambiguousSeparator(raw)); return nil }

        var out: [String] = []
        for part in raw.split(separator: "/", omittingEmptySubsequences: true) {
            if part == "." { continue }
            if part == ".." {
                // Any `..` refuses the entry, including one an in-order resolution would cancel out.
                // Resolving it correctly depends on the decoder, and the decoders disagree (measured:
                // ditto normalises, bsdtar refuses); no legitimate archive needs `..` at all.
                reasons.append(.escapesRoot(raw))
                return nil
            }
            out.append(String(part))
        }

        // An empty list is a legitimate answer for a path that denotes the archive root (".", "./",
        // "a/.." already refused above). The caller decides whether the root may be claimed: only a
        // directory may, and it must not overwrite anything. An entry whose *name* is empty is still
        // an error, and was caught above.
        if out.count > limits.maxPathComponents {
            reasons.append(.tooManyComponents(raw, count: out.count))
            return nil
        }
        return out
    }

    /// Case- and canonical-equivalence-insensitive key, matching APFS default behaviour.
    /// Diacritics are *not* folded: `tệp` and `tep` are different files and must stay different.
    static func asciiFold(_ path: String) -> String {
        path.precomposedStringWithCanonicalMapping.lowercased()
    }

    // MARK: Links

    static func linkReasons(manifest: [ArchiveManifestEntry],
                            normalised: [String: ArchiveManifestEntry],
                            limits: Limits) -> [Reason] {
        var reasons: [Reason] = []

        for entry in manifest {
            guard entry.kind == .symlink || entry.kind == .hardlink else { continue }
            guard let target = entry.linkTarget, !target.isEmpty else {
                reasons.append(.linkTargetMissing(entry.rawPath, target: ""))
                continue
            }
            guard let parentComponents = components(of: entry.rawPath, limits: limits, into: &reasons) else { continue }
            let parent = parentComponents.dropLast()

            if entry.kind == .hardlink {
                // A hard link is a path inside this archive, never an absolute or `~` path, so it is
                // reported as a missing/outside link rather than an absolute symlink target.
                var scratch: [Reason] = []
                guard !target.hasPrefix("/"), !target.hasPrefix("~"),
                      let targetComponents = components(of: target, limits: limits, into: &scratch),
                      let targetEntry = normalised[targetComponents.joined(separator: "/")],
                      targetEntry.kind == .regular
                else {
                    reasons.append(.hardLinkOutside(entry.rawPath, target: target))
                    continue
                }
                continue
            }

            if target.hasPrefix("/") || target.hasPrefix("~") {
                reasons.append(.absoluteLink(entry.rawPath, target: target))
                continue
            }

            // Symlink: resolve lexically relative to its own directory and require containment.
            var resolved = Array(parent)
            var escaped = false
            for part in target.split(separator: "/", omittingEmptySubsequences: true) {
                if part == "." { continue }
                if part == ".." {
                    if resolved.isEmpty { escaped = true; break }
                    resolved.removeLast()
                } else { resolved.append(String(part)) }
            }
            if escaped { reasons.append(.escapingLink(entry.rawPath, target: target)); continue }
            _ = resolved
        }

        if let cycle = firstCycle(manifest: manifest, normalised: normalised, limits: limits) {
            reasons.append(.linkCycle(cycle))
        }
        return reasons
    }

    /// A link graph that revisits a path while resolving is a cycle; creating it would hang or loop
    /// any tool that later walks the tree.
    private static func firstCycle(manifest: [ArchiveManifestEntry],
                                   normalised: [String: ArchiveManifestEntry],
                                   limits: Limits) -> [String]? {
        var symlinks: [String: (parent: [String], target: String)] = [:]
        var scratch: [Reason] = []
        for entry in manifest where entry.kind == .symlink {
            guard let target = entry.linkTarget, !target.hasPrefix("/"),
                  let comps = components(of: entry.rawPath, limits: limits, into: &scratch) else { continue }
            symlinks[comps.joined(separator: "/")] = (Array(comps.dropLast()), target)
        }
        guard !symlinks.isEmpty else { return nil }

        for start in symlinks.keys.sorted() {
            var visited: [String] = []
            var current = start
            var depth = 0
            while let link = symlinks[current] {
                if visited.contains(current) { return visited + [current] }
                visited.append(current)
                depth += 1
                if depth > limits.maxLinkChainDepth { return visited }

                var resolved = link.parent
                var escaped = false
                for part in link.target.split(separator: "/", omittingEmptySubsequences: true) {
                    if part == "." { continue }
                    if part == ".." { if resolved.isEmpty { escaped = true; break }; resolved.removeLast() }
                    else { resolved.append(String(part)) }
                }
                if escaped { break }
                let next = resolved.joined(separator: "/")
                guard symlinks[next] != nil else { break }
                current = next
            }
        }
        return nil
    }

    // MARK: Helpers

    private static func dedupe(_ reasons: [Reason]) -> [Reason] {
        var seen = Set<Reason>()
        return reasons.filter { seen.insert($0).inserted }
    }
}
