import Foundation
import Darwin
import os

/// XF-T28 cluster A — `getattrlistbulk(2)` is the measured listing engine (spec/evidence: 100 000 files
/// 97 ms vs. `FileManager` 813 ms, and `FileManager` hides "._*" regular files on macOS 27 — the probe
/// in this cluster's scratch folder reconfirmed both facts on this machine before this file was written).
enum DirectoryReadError: Error, Equatable, Sendable {
    case notPermitted, notFound, notDirectory, timedOut, other(Int32)

    var messageKey: String {
        switch self {
        case .notPermitted: return "XFinder chưa được phép đọc thư mục này"
        case .notFound: return "Thư mục không còn tồn tại"
        case .notDirectory: return "Đây không phải là thư mục"
        case .timedOut: return "Thư mục phản hồi quá chậm"
        case .other: return "Không đọc được thư mục này"
        }
    }

    /// Maps an `errno` from `open`/`getattrlistbulk` to the user-facing case.
    fileprivate static func from(errno code: Int32) -> DirectoryReadError {
        switch code {
        case EACCES, EPERM: return .notPermitted
        case ENOENT: return .notFound
        case ENOTDIR: return .notDirectory
        case EINTR: return .other(EINTR)   // caller already retries EINTR; reaching here means retries exhausted
        default: return .other(code)
        }
    }
}

enum DirectoryReader {

    /// Known package/bundle extensions (lowercased, no dot) Finder treats as a single double-click
    /// target rather than a folder to navigate into. Checked in addition to the Finder "has bundle"
    /// flag in `ATTR_CMN_FNDRINFO`, since many package types (e.g. `.xcodeproj`) never set that bit.
    private static let packageExtensions: Set<String> = [
        "app", "bundle", "framework", "pages", "numbers", "key", "rtfd",
        "photoslibrary", "xcodeproj", "playground"
    ]

    /// `kHasBundle` — bit 0x2000 of the Finder flags word (`FileInfo.finderFlags`/`FolderInfo.finderFlags`,
    /// both at byte offset 8 of the 32-byte `ATTR_CMN_FNDRINFO` blob, stored big-endian on disk).
    private static let finderFlagHasBundle: UInt16 = 0x2000

    /// One level of `getattrlistbulk(2)`. Synchronous — always call this off the main thread (the
    /// `timeout` overload below does that for you).
    static func list(_ path: String) -> Result<[DirectoryEntry], DirectoryReadError> {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else {
            return .failure(.notFound)
        }
        guard isDir.boolValue else { return .failure(.notDirectory) }

        let dirfd = openDirRetryingEINTR(path)
        if dirfd < 0 {
            return .failure(.from(errno: errno))
        }
        defer { close(dirfd) }

        let volumeID = Self.volumeID(of: path)
        var entries: [DirectoryEntry] = []
        entries.reserveCapacity(256)

        var attrList = attrlist()
        attrList.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        var commonMask: attrgroup_t = 0
        commonMask |= attrgroup_t(ATTR_CMN_RETURNED_ATTRS)
        commonMask |= attrgroup_t(ATTR_CMN_NAME)
        commonMask |= attrgroup_t(ATTR_CMN_OBJTYPE)
        commonMask |= attrgroup_t(ATTR_CMN_DEVID)
        commonMask |= attrgroup_t(ATTR_CMN_MODTIME)
        commonMask |= attrgroup_t(ATTR_CMN_CRTIME)
        commonMask |= attrgroup_t(ATTR_CMN_FLAGS)
        commonMask |= attrgroup_t(ATTR_CMN_FNDRINFO)
        commonMask |= attrgroup_t(ATTR_CMN_ERROR)
        attrList.commonattr = commonMask
        attrList.fileattr = attrgroup_t(ATTR_FILE_DATALENGTH)

        let bufSize = 1 << 16   // 64 KiB: comfortably holds a full batch of ~300-entry-sized groups.
        var buffer = [UInt8](repeating: 0, count: bufSize)

        while true {
            var count: Int32 = 0
            while true {
                count = buffer.withUnsafeMutableBytes { raw -> Int32 in
                    getattrlistbulk(dirfd, &attrList, raw.baseAddress, bufSize, 0)
                }
                if count >= 0 || errno != EINTR { break }
            }
            if count < 0 {
                return .failure(.from(errno: errno))
            }
            if count == 0 { break }

            buffer.withUnsafeBytes { raw in
                var cursor = raw.baseAddress!
                for _ in 0..<count {
                    let entryLength = cursor.loadUnaligned(as: UInt32.self)
                    let entryStart = cursor
                    defer { cursor = entryStart + Int(entryLength) }
                    var field = cursor + MemoryLayout<UInt32>.size

                    let returned = field.loadUnaligned(as: attribute_set_t.self)
                    field += MemoryLayout<attribute_set_t>.size

                    var entryError: UInt32 = 0
                    if returned.commonattr & attrgroup_t(ATTR_CMN_ERROR) != 0 {
                        entryError = field.loadUnaligned(as: UInt32.self)
                        field += MemoryLayout<UInt32>.size
                    }

                    var name = ""
                    if returned.commonattr & attrgroup_t(ATTR_CMN_NAME) != 0 {
                        let ref = field.loadUnaligned(as: attrreference_t.self)
                        let namePtr = (field + Int(ref.attr_dataoffset)).assumingMemoryBound(to: CChar.self)
                        name = String(cString: namePtr)
                        field += MemoryLayout<attrreference_t>.size
                    }

                    // Per-entry errors (e.g. a file removed mid-scan) are skipped, not fatal to the
                    // whole listing — getattrlistbulk still advances past the entry's declared length.
                    guard entryError == 0, !name.isEmpty else { return }

                    // Fixed packing order within a group: ascending attribute-bit value (getattrlist(2)
                    // "ORDER OF ATTRIBUTES"). After NAME (0x1) the remaining common bits we asked for
                    // sort as DEVID(0x2), OBJTYPE(0x8), CRTIME(0x200), MODTIME(0x400), FNDRINFO(0x4000),
                    // FLAGS(0x40000) — NOT the order they were OR'd into the request mask.
                    var devID: Int32 = 0
                    if returned.commonattr & attrgroup_t(ATTR_CMN_DEVID) != 0 {
                        devID = field.loadUnaligned(as: dev_t.self)
                        field += MemoryLayout<dev_t>.size
                    }
                    var objType: fsobj_type_t = 0
                    if returned.commonattr & attrgroup_t(ATTR_CMN_OBJTYPE) != 0 {
                        objType = field.loadUnaligned(as: fsobj_type_t.self)
                        field += MemoryLayout<fsobj_type_t>.size
                    }
                    var created = Date(timeIntervalSince1970: 0)
                    if returned.commonattr & attrgroup_t(ATTR_CMN_CRTIME) != 0 {
                        let ts = field.loadUnaligned(as: timespec.self)
                        created = Date(timeIntervalSince1970: Double(ts.tv_sec) + Double(ts.tv_nsec) / 1e9)
                        field += MemoryLayout<timespec>.size
                    }
                    var modified = Date(timeIntervalSince1970: 0)
                    if returned.commonattr & attrgroup_t(ATTR_CMN_MODTIME) != 0 {
                        let ts = field.loadUnaligned(as: timespec.self)
                        modified = Date(timeIntervalSince1970: Double(ts.tv_sec) + Double(ts.tv_nsec) / 1e9)
                        field += MemoryLayout<timespec>.size
                    }
                    var hasFinderBundleFlag = false
                    if returned.commonattr & attrgroup_t(ATTR_CMN_FNDRINFO) != 0 {
                        // 32-byte opaque Finder-info blob; `finderFlags`/`fdFlags` is a big-endian
                        // UInt16 at byte offset 8 for both `FileInfo` and `FolderInfo` (same layout
                        // for the first 8 bytes: a 4-byte type/creator pair, then the flags word).
                        let rawFlags = field.loadUnaligned(fromByteOffset: 8, as: UInt16.self)
                        hasFinderBundleFlag = (UInt16(bigEndian: rawFlags) & finderFlagHasBundle) != 0
                        field += 32
                    }
                    var stFlags: UInt32 = 0
                    if returned.commonattr & attrgroup_t(ATTR_CMN_FLAGS) != 0 {
                        stFlags = field.loadUnaligned(as: UInt32.self)
                        field += MemoryLayout<UInt32>.size
                    }
                    var dataLength: Int64 = 0
                    if returned.fileattr & attrgroup_t(ATTR_FILE_DATALENGTH) != 0 {
                        dataLength = field.loadUnaligned(as: off_t.self)
                        field += MemoryLayout<off_t>.size
                    }

                    let kind: DirectoryEntry.Kind
                    switch objType {
                    case fsobj_type_t(VREG.rawValue): kind = .file
                    case fsobj_type_t(VDIR.rawValue): kind = .directory
                    case fsobj_type_t(VLNK.rawValue): kind = .symlink
                    default: kind = .other
                    }

                    let ext = Self.extensionOf(name)
                    let isPackage = kind == .directory
                        && (hasFinderBundleFlag || packageExtensions.contains(ext))
                    let isHidden = name.hasPrefix(".") || (stFlags & UInt32(UF_HIDDEN)) != 0

                    let entryPath = path.hasSuffix("/") ? path + name : path + "/" + name
                    entries.append(DirectoryEntry(
                        name: name,
                        path: entryPath,
                        kind: kind,
                        isPackage: isPackage,
                        isHidden: isHidden,
                        size: kind == .directory ? -1 : dataLength,
                        modified: modified,
                        created: created,
                        volumeID: volumeID ?? devID
                    ))
                }
            }
        }

        return .success(entries)
    }

    /// Runs `list(path)` on a detached thread and races it against `timeout`; a hung network share
    /// can't block the caller. The read is NOT cancelled on timeout (there is no safe way to abort a
    /// blocked syscall) — it keeps running on its own thread and its result is simply dropped.
    static func list(_ path: String, timeout: TimeInterval) async -> Result<[DirectoryEntry], DirectoryReadError> {
        await withCheckedContinuation { (continuation: CheckedContinuation<Result<[DirectoryEntry], DirectoryReadError>, Never>) in
            let resumed = OSAllocatedUnfairLock(initialState: false)
            let workItem = DispatchWorkItem {
                let result = Self.list(path)
                let shouldResume = resumed.withLock { already -> Bool in
                    guard !already else { return false }
                    already = true
                    return true
                }
                if shouldResume { continuation.resume(returning: result) }
            }
            DispatchQueue.global(qos: .userInitiated).async(execute: workItem)
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + timeout) {
                let shouldResume = resumed.withLock { already -> Bool in
                    guard !already else { return false }
                    already = true
                    return true
                }
                if shouldResume { continuation.resume(returning: .failure(.timedOut)) }
            }
        }
    }

    /// Subfolder names only (no packages), for the location bar's chevron menu and Tab completion.
    static func subfolders(of path: String, showHidden: Bool, timeout: TimeInterval) async -> Result<[String], DirectoryReadError> {
        switch await list(path, timeout: timeout) {
        case .failure(let error): return .failure(error)
        case .success(let entries):
            let names = entries
                .filter { $0.isFolderLike && (showHidden || !$0.isHidden) }
                .map(\.name)
            return .success(names)
        }
    }

    static func volumeID(of path: String) -> Int32? {
        var s = stat()
        guard stat(path, &s) == 0 else { return nil }
        return Int32(truncatingIfNeeded: s.st_dev)
    }

    /// The mount point (`statfs.f_mntonname`) that `path` lives under.
    static func volumePath(of path: String) -> String? {
        var fs = statfs()
        guard statfs(path, &fs) == 0 else { return nil }
        return withUnsafePointer(to: fs.f_mntonname) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
        }
    }

    /// Whether `path`'s volume stores timestamps at 2-second (FAT/exFAT) rather than sub-second
    /// granularity — callers use this to widen the "is this file newer" comparison window.
    static func hasCoarseTimestamps(_ path: String) -> Bool {
        var fs = statfs()
        guard statfs(path, &fs) == 0 else { return false }
        let fsType = withUnsafePointer(to: fs.f_fstypename) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: Int(MFSTYPENAMELEN)) { String(cString: $0) }
        }
        let coarse: Set<String> = ["msdos", "exfat"]
        return coarse.contains(fsType.lowercased())
    }

    static func freeSpace(of path: String) -> Int64? {
        var fs = statfs()
        guard statfs(path, &fs) == 0 else { return nil }
        let free = Int64(fs.f_bfree) * Int64(fs.f_bsize)
        return free >= 0 ? free : nil
    }

    /// Lowercased extension, matching `DirectoryEntry.ext`'s own rule (no leading dot, dotfiles have none).
    private static func extensionOf(_ name: String) -> String {
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return "" }
        let start = name.index(after: dot)
        guard start < name.endIndex else { return "" }
        return name[start...].lowercased()
    }

    /// `open(2)` on a directory, transparently retrying on `EINTR` (a signal arriving mid-syscall is
    /// not a real failure).
    private static func openDirRetryingEINTR(_ path: String) -> Int32 {
        while true {
            let fd = open(path, O_RDONLY)
            if fd >= 0 { return fd }
            if errno != EINTR { return fd }
        }
    }
}

/// A single `open(path, O_EVTONLY)` + `DispatchSource.makeFileSystemObjectSource` on the main queue
/// (measured: 0.52 ms create→callback latency). Coalesces bursts of events 80 ms apart into one
/// `onChange` call; a `.delete`/`.rename` on the watched directory itself fires `onGone` instead.
@MainActor final class DirectoryWatcher {
    private static let coalesceInterval: TimeInterval = 0.08

    private let fd: Int32
    private var source: DispatchSourceFileSystemObject?
    private var pendingWorkItem: DispatchWorkItem?
    private let onChange: @MainActor () -> Void
    private let onGone: @MainActor () -> Void

    init?(path: String, onChange: @escaping @MainActor () -> Void, onGone: @escaping @MainActor () -> Void) {
        let descriptor = open(path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }
        self.fd = descriptor
        self.onChange = onChange
        self.onGone = onGone

        let mask: DispatchSource.FileSystemEvent = [.write, .delete, .rename, .extend, .attrib, .link]
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: mask, queue: .main)
        src.setEventHandler { [weak self] in
            guard let self else { return }
            let flags = src.data
            if flags.contains(.delete) || flags.contains(.rename) {
                self.onGone()
                return
            }
            self.scheduleCoalescedChange()
        }
        src.setCancelHandler { [fd = descriptor] in close(fd) }
        self.source = src
        src.resume()
    }

    private func scheduleCoalescedChange() {
        pendingWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.onChange() }
        pendingWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.coalesceInterval, execute: work)
    }

    func cancel() {
        pendingWorkItem?.cancel()
        pendingWorkItem = nil
        source?.cancel()
        source = nil
    }

    deinit {
        // A `DispatchSourceFileSystemObject` is not cancelled by ARC deallocation — GCD keeps a resumed
        // source (and the fd its cancel handler will eventually close) alive until `.cancel()` is called
        // explicitly (measured: a `Watched` dropped without calling `cancel()` leaves its fd open with
        // `F_GETFD` still succeeding). Cancelling here is what actually runs the handler that closes `fd`
        // if a caller forgets to call `cancel()` before releasing its last reference.
        source?.cancel()
    }
}
