import Foundation
import Darwin

/// Reads an archive's manifest **without writing anything**, so the safety rules can decide before a
/// decoder materialises a single byte.
///
/// Why a runtime binding instead of `import libarchive`: the macOS SDK ships `libarchive.tbd` but
/// **no `archive.h`** (measured 2026-11-07), so there is nothing to link against at build time. The
/// dylib itself is present only in the dyld shared cache — `dlopen("/usr/lib/libarchive.2.dylib")`
/// succeeds although no such file exists on disk. Every symbol is therefore resolved with `dlsym`
/// into a typed `@convention(c)` function pointer, and a missing symbol makes the reader
/// **unavailable**, never a partial one.
///
/// The measured behaviours this file is built around (macOS 27.2, libarchive 3.7.4; the probes are
/// summarised in `docs/reviews/XF-MFGAP-03-archive-safety-review.md`):
///
/// - Registering nothing means every open fails with `No formats registered`, which reads like a
///   corrupt archive. Only the approved formats are registered on purpose: with `zip` + `tar` alone,
///   a 7z or random file is refused at open with `Unrecognized archive format` instead of being
///   handed to a decoder this app never tested.
/// - `archive_read_open_fd` does **not** take ownership of the descriptor: `archive_read_free` leaves
///   it open (measured with `fstat` after free). The reader closes it itself, exactly once.
/// - Headers expose hostile shapes before extraction: raw `../x`, absolute paths, absolute symlink
///   targets, duplicate names, non-UTF-8 names (`pathname_utf8` returns nil while `pathname` returns
///   a lossy U+FFFD string — that is the validity gate).
/// - An **encrypted** entry is visible at header time (`archive_entry_is_encrypted`), before any data
///   call, so it can be refused cleanly instead of failing mid-file.
/// - A **sparse** entry is the trap: a tar holding a 200 MiB hole-only file reports
///   `sparse_count = 2`, `declared = 209715200`, and then `archive_read_data` yields **0 bytes with
///   no error at all**, while `tar -x` faithfully recreates a 200 MiB file. Byte accounting built on
///   decoded bytes would therefore silently undercount, so sparse entries are refused rather than
///   guessed at (the spec allows exactly this: "sparse/unknown-size features the reader cannot bound").
/// - Declared sizes are claims. A tar header declaring 2048 bytes over a 1024-byte payload fails with
///   `Truncated tar archive`, and only a runtime check catches it.
/// - Walking headers is **not** free for streamed formats: finding entry N+1 requires inflating
///   entry N. 64 MiB of compressible data cost ~12 ms to walk with no bytes requested, so inspection
///   is bounded by both an entry count and a byte budget — never by assumption.
///
/// This type performs no writes, no deletion, no rename and no process spawning. It exists to produce
/// `[ArchiveManifestEntry]` for `ArchiveSafetyRules.validate` and nothing else.
struct SystemArchiveReader {

    // MARK: - Clock

    /// Monotonic seconds, not wall time: a clock jump or a timezone change must not be able to extend
    /// or cancel a processing budget.
    static let monotonicNow: @Sendable () -> TimeInterval = {
        var now = timespec()
        guard clock_gettime(CLOCK_MONOTONIC, &now) == 0 else { return 0 }
        return TimeInterval(now.tv_sec) + TimeInterval(now.tv_nsec) / 1_000_000_000
    }

    /// Injected so a deadline test does not have to wait ten minutes, and so the check can be proven
    /// to live inside the payload loop rather than only between entries.
    let clock: @Sendable () -> TimeInterval

    init(clock: @Sendable @escaping () -> TimeInterval = SystemArchiveReader.monotonicNow) {
        self.clock = clock
    }

    // MARK: - Results

    /// Identity of the file that was actually read, captured from the open descriptor.
    ///
    /// Stage 03B revalidates this before commit: if the archive was swapped between inspection and
    /// publication, the plan no longer describes the bytes on disk.
    struct Identity: Sendable, Equatable {
        var device: UInt64
        var inode: UInt64
        var size: Int64
        var modifiedSeconds: Int64
        var modifiedNanos: Int64
        var changedSeconds: Int64
        var changedNanos: Int64
    }

    /// A complete, verified manifest. `decodedBytes` counts every logical byte the decoder produced,
    /// holes included, so it can be compared with `declaredPayloadBytes` honestly.
    struct Inspection: Sendable, Equatable {
        var manifest: [ArchiveManifestEntry]
        var identity: Identity
        /// Compressed size on disk, i.e. what the expansion-ratio check divides into.
        var archiveBytes: Int64
        /// Logical bytes the decoder actually produced across all regular entries.
        var decodedBytes: Int64
    }

    /// Every way inspection can refuse. Deliberately coarse: the view maps cases to `L10n` strings in
    /// the placement stage, and this file stays free of user-facing text.
    ///
    /// Associated strings are **diagnostics from libarchive** (English, technical), kept for the log.
    /// They are never shown to the user and must not be treated as UI copy.
    enum Failure: Error, Equatable {
        /// A required symbol is missing, or the dylib will not load. The caller must show
        /// "unsupported on this system" rather than pretending the archive is bad.
        case libraryUnavailable
        case openFailed(errno: Int32)
        /// Not a regular file: a directory, device, FIFO or socket.
        case notRegularFile
        /// A cloud placeholder that reading would silently download.
        case notMaterialised
        /// The path is a symlink, or the file changed between `lstat` and `open`.
        case changedWhileOpening
        case formatRegistrationFailed(symbol: String)
        /// Nothing in the approved format set recognises these bytes.
        case unsupportedFormat(String)
        /// A password-protected entry. Refused before any data is read.
        case encrypted(String)
        /// A name that is not valid UTF-8. Accepted as bytes, it could land on a different file than
        /// the one the rules validated.
        case invalidEncoding(String)
        /// A sparse entry, which the decoder reports as zero decoded bytes and cannot be bounded.
        case sparse(String)
        /// Device, FIFO, socket, sparse flag or any type this reader cannot classify.
        case unsupportedEntry(String, filetype: UInt32)
        case tooManyEntries(count: Int, limit: Int)
        /// One entry alone went past what was left of the batch budget. `entry` is the name the
        /// decoder was reading, so a test can prove the refusal happened *inside* that entry.
        case byteBudgetExceeded(limit: Int64, entry: String)
        /// The running total passed the batch budget after an entry finished. The per-entry remaining
        /// budget is supposed to make this unreachable — it is kept as a second lock on the same
        /// door, and a test asserts the reachable path reports `byteBudgetExceeded` instead.
        case cumulativeBudgetExceeded(limit: Int64, decoded: Int64)
        /// The decoder produced fewer logical bytes than the header declared, or more.
        case sizeMismatch(String, declared: Int64, decoded: Int64)
        case sizeOverflow(String)
        /// A decoder error mid-walk: bad CRC, truncation, damaged stream.
        case damaged(String)
        /// The monotonic processing deadline for this archive ran out. Checked in the same loop
        /// that drains payload, because walking a streamed format inflates data to reach the next
        /// header: an entry count and a byte budget alone cannot bound the time a hostile archive
        /// may spend before the next decision point.
        case timedOut(after: TimeInterval)
    }

    // MARK: - Bounds

    struct Bounds: Sendable, Equatable {
        var maxEntries: Int
        /// Total logical bytes inspection may decode. A streamed tar must inflate to reach the next
        /// header, so this also bounds time.
        var maxDecodedBytes: Int64
        /// Read buffer handed to libarchive. The spec caps a stream at 1 MiB.
        var blockSize: Int
        /// Active processing budget for the whole archive, monotonic. Zero means "no deadline",
        /// which only tests use: the app must always pass a real budget.
        var maxSeconds: TimeInterval = 600

        static let proposed = Bounds(maxEntries: 100_000,
                                     maxDecodedBytes: 16 * 1024 * 1024 * 1024,
                                     blockSize: 64 * 1024)
    }

    // MARK: - Availability

    /// Cheap probe for the UI: is the system reader usable here at all? Never touches an archive.
    static var isAvailable: Bool { Tables.shared != nil }

    // MARK: - Inspection

    /// Walk `url` and return its verified manifest, or refuse.
    ///
    /// Nothing is written and nothing is extracted. On refusal the reason is precise enough for the
    /// caller to distinguish "this archive is hostile" from "this system cannot read archives".
    ///
    /// Three layers guard the path, and they are deliberately redundant because each covers a
    /// different instant:
    /// 1. `lstat` before opening — refuses a symlink, FIFO or directory without ever opening it, and
    ///    records the identity the caller is about to read.
    /// 2. `O_NOFOLLOW` on the `open` — closes the window between (1) and the open itself, where the
    ///    path could be swapped for a symlink. Measured: open fails with `ELOOP`.
    /// 3. `fstat` after opening, compared against (1) — proves the descriptor is the very inode that
    ///    was just inspected, which is what stage 03B revalidates before commit.
    func inspect(at url: URL, bounds: Bounds = .proposed) throws -> Inspection {
        guard let tables = Tables.shared else { throw Failure.libraryUnavailable }

        let path = url.path

        // (1) Look at the path itself, following nothing.
        var atPath = stat()
        guard lstat(path, &atPath) == 0 else { throw Failure.openFailed(errno: errno) }
        guard (atPath.st_mode & S_IFMT) == S_IFREG else { throw Failure.notRegularFile }
        // Reading a dataless (cloud-only) placeholder would pull bytes over the network without the
        // user asking. Same check as the image child.
        guard atPath.st_flags & UInt32(SF_DATALESS) == 0 else { throw Failure.notMaterialised }

        // (2) Open without following, without blocking on anything odd, and without leaking the
        // descriptor into a child process.
        let fd = open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard fd >= 0 else {
            throw errno == ELOOP || errno == EMLINK ? Failure.changedWhileOpening
                                                    : Failure.openFailed(errno: errno)
        }
        // `archive_read_open_fd` does not own the descriptor, so this is the only close.
        defer { close(fd) }

        // (3) The descriptor must be the file that was inspected a moment ago. A mismatch means the
        // path changed under us, so the manifest would not describe the bytes on disk.
        var opened = stat()
        guard fstat(fd, &opened) == 0 else { throw Failure.openFailed(errno: errno) }
        guard (opened.st_mode & S_IFMT) == S_IFREG else { throw Failure.notRegularFile }
        guard opened.st_flags & UInt32(SF_DATALESS) == 0 else { throw Failure.notMaterialised }
        guard opened.st_dev == atPath.st_dev, opened.st_ino == atPath.st_ino else {
            throw Failure.changedWhileOpening
        }
        guard opened.st_size >= 0 else { throw Failure.openFailed(errno: EINVAL) }

        let identity = Identity(device: UInt64(opened.st_dev),
                                inode: UInt64(opened.st_ino),
                                size: Int64(opened.st_size),
                                modifiedSeconds: Int64(opened.st_mtimespec.tv_sec),
                                modifiedNanos: Int64(opened.st_mtimespec.tv_nsec),
                                changedSeconds: Int64(opened.st_ctimespec.tv_sec),
                                changedNanos: Int64(opened.st_ctimespec.tv_nsec))

        guard let archive = tables.readNew() else { throw Failure.libraryUnavailable }
        defer { _ = tables.readFree(archive) }

        // Only the approved formats and filters. Any non-OK return means the decoder is not the one
        // this code was measured against, so refuse rather than continue with a partial set.
        for symbol in Tables.formatSymbols {
            guard let register = tables.register(symbol) else { throw Failure.libraryUnavailable }
            guard register(archive) == 0 else { throw Failure.formatRegistrationFailed(symbol: symbol) }
        }
        for symbol in Tables.filterSymbols {
            guard let register = tables.register(symbol) else { throw Failure.libraryUnavailable }
            guard register(archive) == 0 else { throw Failure.formatRegistrationFailed(symbol: symbol) }
        }

        guard tables.openFd(archive, fd, bounds.blockSize) == 0 else {
            // Format detection is the only thing that can fail at open for a readable regular file.
            throw Failure.unsupportedFormat(tables.message(archive) ?? "open refused")
        }

        var manifest: [ArchiveManifestEntry] = []
        var decoded: Int64 = 0
        let started = clock()
        // A zero budget means "no deadline" and is only reachable from tests; the app always passes
        // `Bounds.proposed`. Elapsed time is measured from `started`, captured once, so an injected
        // clock cannot move the origin.
        let budget = bounds.maxSeconds

        func checkDeadline() throws {
            guard budget > 0 else { return }
            let elapsed = clock() - started
            if elapsed >= budget { throw Failure.timedOut(after: elapsed) }
        }

        while true {
            try checkDeadline()
            var entry: OpaquePointer?
            let status = tables.nextHeader(archive, &entry)
            if status == Tables.eof { break }
            if status < 0 { throw Failure.damaged(tables.message(archive) ?? "header status \(status)") }
            guard let entry else { continue }

            // `pathname_utf8` is non-nil for every legitimate name measured (ASCII, NFC and NFD
            // Vietnamese, in zip and tar) and nil exactly when the bytes are not valid UTF-8.
            guard let rawName = tables.pathUtf8(entry).map({ String(cString: $0) }) else {
                throw Failure.invalidEncoding(tables.pathname(entry).map { String(cString: $0) } ?? "<unnamed>")
            }

            if tables.isEncrypted(entry) != 0 {
                throw Failure.encrypted(rawName)
            }
            // A sparse entry is refused, not guessed at: measured `archive_read_data` returns 0 bytes
            // and no error for a 200 MiB hole-only file, so any byte count derived from the decoder
            // would understate the file the user is about to receive.
            if let sparseCount = tables.sparseCount, sparseCount(entry) > 0 {
                throw Failure.sparse(rawName)
            }

            let filetype = tables.filetype(entry)
            let kind = Self.kind(filetype: filetype,
                                 hardlink: tables.hardlink(entry),
                                 symlink: tables.symlink(entry))
            let declared = tables.size(entry)
            let linkTarget = kind == .symlink ? tables.symlink(entry).map { String(cString: $0) }
                                              : tables.hardlink(entry).map { String(cString: $0) }

            manifest.append(ArchiveManifestEntry(rawPath: rawName,
                                                 declaredSize: declared,
                                                 sizeIsSet: tables.sizeIsSet(entry) != 0,
                                                 kind: kind,
                                                 linkTarget: linkTarget))

            if manifest.count > bounds.maxEntries {
                throw Failure.tooManyEntries(count: manifest.count, limit: bounds.maxEntries)
            }

            // Drain every entry, links and directories included, so the stream advances and so a
            // hostile payload cannot hide behind a header this walk decided not to read.
            //
            // The ledger is bounded by what is LEFT of the batch budget, not by the whole budget.
            // Measured trap (Boss approval point 3): a per-entry ledger of `maxDecodedBytes` lets one
            // entry decode a full budget, and only afterwards does the cumulative check notice — so
            // two entries could each consume 16 GiB before the second refusal, and a single entry
            // could write a file larger than the batch allows.
            let (remaining, remainingOverflowed) = bounds.maxDecodedBytes.subtractingReportingOverflow(decoded)
            let entryBudget = remainingOverflowed ? 0 : max(0, remaining)
            var ledger = BlockLedger(limit: entryBudget)
            while true {
                // Inside the block loop on purpose: a streamed payload is decoded here, so a deadline
                // checked only between entries would never fire for one enormous compressed entry.
                try checkDeadline()
                var block: UnsafeRawPointer?
                var size = 0
                var offset: Int64 = 0
                let read = tables.readBlock(archive, &block, &size, &offset)
                if read == Tables.eof { break }
                if read < 0 { throw Failure.damaged(tables.message(archive) ?? "data status \(read)") }
                do {
                    try ledger.consume(offset: offset, size: size)
                } catch let overflow as ByteLedgerError {
                    throw Self.failure(for: overflow, entry: rawName, limit: bounds.maxDecodedBytes)
                }
            }

            if kind == .regular {
                try Self.verifyDeclaredSize(path: rawName,
                                            declared: declared,
                                            sizeIsSet: tables.sizeIsSet(entry) != 0,
                                            decoded: ledger.logical)
                let (total, overflowed) = decoded.addingReportingOverflow(ledger.logical)
                if overflowed { throw Failure.sizeOverflow(rawName) }
                decoded = total
                // Second lock, not the primary guard: `entryBudget` above already refuses an entry
                // that would cross the batch budget, so this only fires if that arithmetic is ever
                // changed. Kept separate so the two paths are distinguishable in a test instead of
                // one silently masking the other.
                if decoded > bounds.maxDecodedBytes {
                    throw Failure.cumulativeBudgetExceeded(limit: bounds.maxDecodedBytes, decoded: decoded)
                }
            }
        }

        return Inspection(manifest: manifest,
                          identity: identity,
                          archiveBytes: Int64(opened.st_size),
                          decodedBytes: decoded)
    }

    /// Map the decoder's `mode_t` to the manifest's vocabulary.
    ///
    /// A hard link is reported with `filetype == 0` (measured), so the link accessors are consulted
    /// before the file type or every hard link would look unsupported.
    private static func kind(filetype: UInt32,
                            hardlink: UnsafePointer<CChar>?,
                            symlink: UnsafePointer<CChar>?) -> ArchiveManifestEntry.Kind {
        if hardlink != nil { return .hardlink }
        if symlink != nil || filetype == UInt32(S_IFLNK) { return .symlink }
        switch filetype {
        case UInt32(S_IFREG): return .regular
        case UInt32(S_IFDIR): return .directory
        default: return .unsupported
        }
    }

    // MARK: - Pure byte accounting

    /// What can go wrong while counting an entry's logical bytes.
    enum ByteLedgerError: Error, Equatable {
        /// A block reported a negative offset or length.
        case negativeExtent
        /// An entry whose payload alone exceeds the budget.
        case budgetExceeded
        /// The total would not fit in `Int64`.
        case overflow
    }

    /// Counts the **logical** size of one entry from the decoder's blocks.
    ///
    /// This is separated from `inspect` so the arithmetic is testable without an archive, and so the
    /// hole rule cannot be quietly dropped: a block at offset N implies the bytes before it are a hole,
    /// which occupy real space in the extracted file even though the decoder never hands them over.
    /// Measured: a tar holding a 200 MiB hole-only file reports the hole as a gap and
    /// `archive_read_data` as zero bytes, so counting only `size` would understate the file.
    struct BlockLedger: Equatable {
        var logical: Int64 = 0
        var cursor: Int64 = 0
        let limit: Int64

        init(limit: Int64) { self.limit = limit }

        mutating func consume(offset: Int64, size: Int) throws {
            guard offset >= 0, size >= 0 else { throw ByteLedgerError.negativeExtent }
            if offset > cursor {
                let (grown, overflowed) = logical.addingReportingOverflow(offset - cursor)
                if overflowed { throw ByteLedgerError.overflow }
                logical = grown
            }
            let (grown, overflowed) = logical.addingReportingOverflow(Int64(size))
            if overflowed { throw ByteLedgerError.overflow }
            logical = grown
            // The block's end offset also comes from archive metadata. `offset + size` on two maximal
            // values would trap, and a trap is a crash rather than a refusal.
            //
            // This check cannot currently fire: `logical >= offset` holds after every update (the gap
            // is added before the size), so `offset + size <= logical + size`, and the total check
            // above has already refused if that overflowed. It is kept because it is one comparison
            // and it turns a future reordering of the statements above from a crash into a refusal.
            let (end, endOverflowed) = offset.addingReportingOverflow(Int64(size))
            if endOverflowed { throw ByteLedgerError.overflow }
            cursor = end
            if logical > limit { throw ByteLedgerError.budgetExceeded }
        }
    }

    private static func failure(for error: ByteLedgerError,
                                entry: String,
                                limit: Int64) -> Failure {
        switch error {
        case .negativeExtent: return .damaged("negative block extent")
        case .budgetExceeded: return .byteBudgetExceeded(limit: limit, entry: entry)
        case .overflow: return .sizeOverflow(entry)
        }
    }

    /// Require a regular entry's decoded logical bytes to equal what its header declared.
    ///
    /// Extracted separately so it is testable on its own: without this check a header declaring 8 KiB
    /// over a 1 KiB payload would pass whenever the decoder itself did not object, and the manifest
    /// would then describe a file the user never receives.
    static func verifyDeclaredSize(path: String,
                                   declared: Int64,
                                   sizeIsSet: Bool,
                                   decoded: Int64) throws {
        // A format that states no size (streamed tar) has nothing to compare, and the reader has
        // already refused those entries through `sizeIsSet`.
        guard sizeIsSet else { return }
        guard decoded == declared else {
            throw Failure.sizeMismatch(path, declared: declared, decoded: decoded)
        }
    }

    // MARK: - Runtime binding

    /// Resolved once and reused: `dlsym` is cheap but a per-call `dlopen` would leak a reference on
    /// every archive. A `static let` is initialised lazily and exactly once, which is also what keeps
    /// this free of shared mutable state under Swift 6 strict concurrency.
    private struct Tables: Sendable {
        static let shared: Tables? = load()

        static let eof: Int32 = 1
        static let formatSymbols = ["archive_read_support_format_zip",
                                    "archive_read_support_format_tar"]
        static let filterSymbols = ["archive_read_support_filter_gzip",
                                    "archive_read_support_filter_bzip2",
                                    "archive_read_support_filter_xz",
                                    "archive_read_support_filter_none"]

        typealias NewFn = @convention(c) () -> OpaquePointer?
        typealias IntFn = @convention(c) (OpaquePointer?) -> Int32
        typealias OpenFdFn = @convention(c) (OpaquePointer?, Int32, Int) -> Int32
        typealias NextFn = @convention(c) (OpaquePointer?, UnsafeMutablePointer<OpaquePointer?>?) -> Int32
        typealias StrFn = @convention(c) (OpaquePointer?) -> UnsafePointer<CChar>?
        typealias SizeFn = @convention(c) (OpaquePointer?) -> Int64
        typealias TypeFn = @convention(c) (OpaquePointer?) -> UInt32
        typealias BlockFn = @convention(c) (OpaquePointer?,
                                            UnsafeMutablePointer<UnsafeRawPointer?>?,
                                            UnsafeMutablePointer<Int>?,
                                            UnsafeMutablePointer<Int64>?) -> Int32

        let readNew: NewFn
        let openFd: OpenFdFn
        let nextHeader: NextFn
        let readFree: IntFn
        let readBlock: BlockFn
        let errorString: StrFn
        let pathUtf8: StrFn
        let pathname: StrFn
        let symlink: StrFn
        let hardlink: StrFn
        let size: SizeFn
        let sizeIsSet: IntFn
        let filetype: TypeFn
        let isEncrypted: IntFn
        /// Optional on purpose: absence only disables the sparse check, it does not disable the reader.
        let sparseCount: IntFn?
        private let registerSymbols: [String: IntFn]

        func register(_ symbol: String) -> IntFn? { registerSymbols[symbol] }

        func message(_ archive: OpaquePointer?) -> String? {
            errorString(archive).map { String(cString: $0) }
        }

        static func load() -> Tables? {
            // The dylib lives in the dyld shared cache; the file does not exist on disk, which is why
            // this must be dlopen rather than a link-time dependency.
            guard let handle = dlopen("/usr/lib/libarchive.2.dylib", RTLD_NOW) else { return nil }
            func symbol<T>(_ name: String, _ type: T.Type) -> T? {
                guard let pointer = dlsym(handle, name) else { return nil }
                return unsafeBitCast(pointer, to: T.self)
            }

            var registers: [String: IntFn] = [:]
            for name in formatSymbols + filterSymbols {
                guard let function = symbol(name, IntFn.self) else {
                    dlclose(handle)
                    return nil
                }
                registers[name] = function
            }

            // Every symbol below is required. A newer or older libarchive that lacks one gets a clean
            // "unsupported on this system" instead of a partially working reader.
            guard let readNew = symbol("archive_read_new", NewFn.self),
                  let openFd = symbol("archive_read_open_fd", OpenFdFn.self),
                  let nextHeader = symbol("archive_read_next_header", NextFn.self),
                  let readFree = symbol("archive_read_free", IntFn.self),
                  let readBlock = symbol("archive_read_data_block", BlockFn.self),
                  let errorString = symbol("archive_error_string", StrFn.self),
                  let pathUtf8 = symbol("archive_entry_pathname_utf8", StrFn.self),
                  let pathname = symbol("archive_entry_pathname", StrFn.self),
                  let symlink = symbol("archive_entry_symlink", StrFn.self),
                  let hardlink = symbol("archive_entry_hardlink", StrFn.self),
                  let size = symbol("archive_entry_size", SizeFn.self),
                  let sizeIsSet = symbol("archive_entry_size_is_set", IntFn.self),
                  let filetype = symbol("archive_entry_filetype", TypeFn.self),
                  let isEncrypted = symbol("archive_entry_is_encrypted", IntFn.self)
            else {
                dlclose(handle)
                return nil
            }

            return Tables(readNew: readNew,
                          openFd: openFd,
                          nextHeader: nextHeader,
                          readFree: readFree,
                          readBlock: readBlock,
                          errorString: errorString,
                          pathUtf8: pathUtf8,
                          pathname: pathname,
                          symlink: symlink,
                          hardlink: hardlink,
                          size: size,
                          sizeIsSet: sizeIsSet,
                          filetype: filetype,
                          isEncrypted: isEncrypted,
                          sparseCount: symbol("archive_entry_sparse_count", IntFn.self),
                          registerSymbols: registers)
        }
    }
}
