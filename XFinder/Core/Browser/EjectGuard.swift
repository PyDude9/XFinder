import AppKit
import DiskArbitration

/// XF-T28 cluster B / XF-T30 W3 (contract §2, spec-file-operations.md §11 R66–R70). Blocks `diskutil unmount`/`eject`
/// (and Finder's own eject) on a volume that a running FileOperationQueue job is reading from or writing to —
/// measured 2026-10-24: `DARegisterDiskUnmountApprovalCallback` / `DARegisterDiskEjectApprovalCallback` returning a
/// dissenter makes `diskutil unmount`/`eject` fail with `kDAReturnBusy` ("XFinder: a file operation is running"),
/// confirmed from an ordinary (non-root, non-entitled) process; a positive control with no dissenter let the same
/// unmount through. Matching is by the disk's **mounted volume path** (`kDADiskDescriptionVolumePathKey`), never by
/// BSD name — an APFS volume is a synthesized disk whose BSD name (e.g. `disk7s1`) does not correspond to the
/// physical disk a user thinks of (`disk6`); the mount path is the one identifier that is stable and meaningful to
/// both XFinder and the user.
///
/// XF-T30 W3 additions (measured 2026-10-25, this machine — `scratchpad/b-w3v/probe-eject.swift`): `kDADiskDescriptionDeviceInternalKey`
/// reliably separates the boot volume (`internal=true`) from an external USB/Thunderbolt disk (`internal=false`) —
/// positive control: "/" on this Mac reads `internal=true`, two actually-attached external disks both read
/// `internal=false`. `DADiskCopyWholeDisk` groups sibling volumes of one physical disk (e.g. "Macintosh HD" and
/// "Macintosh HD - Data" both report whole disk `disk3`) — this is how R69's multi-volume prompt and R70's
/// never-cascade-to-another-disk guard are built, never by a positional index into `diskutil list` (spec's own
/// R36 pitfall). The busy-app name (R67) comes from `lsof +D <mountpath>`, the one process-level API that can name
/// an open file's owner without TCC/root (CLAUDE.md rule 21: no `timeout(1)` on this machine — a watchdog timer
/// kills the child instead).
@MainActor final class EjectGuard {
    static let shared = EjectGuard()

    /// What a volume looks like to the sidebar's eject flow — grouped by physical disk so the "eject one vs. eject
    /// all" prompt (R69) can be built without any further DiskArbitration calls.
    struct VolumeInfo: Equatable {
        let mountPath: String
        let name: String
        let wholeDiskBSDName: String
        let isInternal: Bool
    }

    /// Why an eject attempt cannot proceed as asked.
    enum EjectRefusal: Equatable {
        /// An XFinder file operation is reading/writing this volume (contract: "refuse while XFinder file
        /// operations run there" — applies to every disk, not just the one being ejected, same as R68).
        case xfinderBusy
        /// Another app has an open file on the volume; `appName` is the first match `lsof` names (nil when it ran
        /// but could not attribute a name, e.g. a kernel-held mount).
        case appBusy(appName: String?)
        /// The volume could not be located (already ejected, or never existed) by the time the eject ran.
        case notFound
        /// Force Eject refuses an internal disk outright (R70) — this code path should be unreachable from the UI
        /// (the sidebar never offers eject on an internal disk), kept as the same defence-in-depth as the
        /// unmount/eject approval callbacks below.
        case internalDisk
    }

    private var session: DASession?
    private(set) var busyVolumes: Set<String> = []

    private init() {}

    /// `mountPoints` are volume mount paths (e.g. "/", "/Volumes/Backup") currently read from or written to by an
    /// active job. An empty set tears the whole session down — no callback stays registered while nothing is busy,
    /// so this feature costs nothing at rest (CLAUDE.md IdleCost rule).
    func setBusyVolumes(_ mountPoints: Set<String>) {
        busyVolumes = mountPoints
        if mountPoints.isEmpty {
            teardownSession()
        } else {
            ensureSession()
        }
    }

    private func ensureSession() {
        guard session == nil else { return }
        guard let session = DASessionCreate(kCFAllocatorDefault) else { return }
        self.session = session
        DASessionScheduleWithRunLoop(session, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        let context = Unmanaged.passUnretained(self).toOpaque()
        DARegisterDiskUnmountApprovalCallback(session, nil, EjectGuard.unmountApproval, context)
        DARegisterDiskEjectApprovalCallback(session, nil, EjectGuard.ejectApproval, context)
    }

    private func teardownSession() {
        guard let session else { return }
        DASessionUnscheduleFromRunLoop(session, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        self.session = nil
    }

    /// Reads the disk's mounted volume path (if any) and returns a dissenter when that path is one XFinder is
    /// currently working on. `DADiskCopyDescription` is nil for a disk that has already vanished (race with a
    /// physical removal) — nothing to dissent against in that case.
    fileprivate func dissenter(for disk: DADisk) -> Unmanaged<DADissenter>? {
        guard let description = DADiskCopyDescription(disk) as? [String: Any] else { return nil }
        guard let volumeURL = description[kDADiskDescriptionVolumePathKey as String] as? URL else { return nil }
        let path = volumeURL.standardizedFileURL.path
        guard busyVolumes.contains(where: { ($0 as NSString).standardizingPath == path }) else { return nil }
        let reason = L10n.t("XFinder đang thực hiện một thao tác tệp trên ổ đĩa này")
        let dissenter = DADissenterCreate(kCFAllocatorDefault, DAReturn(kDAReturnBusy), reason as CFString)
        return Unmanaged.passRetained(dissenter)
    }

    /// C function pointers (not closures) — DiskArbitration calls these directly, so the context carries `self`.
    private static let unmountApproval: DADiskUnmountApprovalCallback = { disk, context in
        guard let context else { return nil }
        let guardInstance = Unmanaged<EjectGuard>.fromOpaque(context).takeUnretainedValue()
        return guardInstance.dissenter(for: disk)
    }

    private static let ejectApproval: DADiskEjectApprovalCallback = { disk, context in
        guard let context else { return nil }
        let guardInstance = Unmanaged<EjectGuard>.fromOpaque(context).takeUnretainedValue()
        return guardInstance.dissenter(for: disk)
    }

    // MARK: - XF-T30 W3: volume lookup for the sidebar eject flow

    /// Describes `mountPath`'s volume — nil when DiskArbitration has no disk for it (already ejected, or not a
    /// real mount point).
    nonisolated func info(for mountPath: String) -> VolumeInfo? {
        guard let session = DASessionCreate(kCFAllocatorDefault) else { return nil }
        guard let disk = DADiskCreateFromVolumePath(kCFAllocatorDefault, session, URL(fileURLWithPath: mountPath) as CFURL)
        else { return nil }
        guard let description = DADiskCopyDescription(disk) as? [String: Any] else { return nil }
        let name = (description[kDADiskDescriptionVolumeNameKey as String] as? String)
            ?? (mountPath as NSString).lastPathComponent
        let isInternal = (description[kDADiskDescriptionDeviceInternalKey as String] as? Bool) ?? true
        guard let whole = DADiskCopyWholeDisk(disk), let bsdName = DADiskGetBSDName(whole) else {
            return VolumeInfo(mountPath: mountPath, name: name, wholeDiskBSDName: "", isInternal: isInternal)
        }
        return VolumeInfo(mountPath: mountPath, name: name, wholeDiskBSDName: String(cString: bsdName), isInternal: isInternal)
    }

    /// Every OTHER mounted volume that shares `mountPath`'s physical disk (R69's "eject all volumes on this disk").
    /// Never includes `mountPath` itself. Matches by whole-disk BSD name, not by any positional index (spec R36).
    nonisolated func siblingVolumes(of mountPath: String) -> [VolumeInfo] {
        guard let target = info(for: mountPath), !target.wholeDiskBSDName.isEmpty else { return [] }
        let keys: [URLResourceKey] = [.volumeNameKey]
        guard let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes])
        else { return [] }
        return urls.compactMap { url -> VolumeInfo? in
            let path = url.path
            guard path != mountPath else { return nil }
            guard let candidate = info(for: path), candidate.wholeDiskBSDName == target.wholeDiskBSDName else { return nil }
            return candidate
        }
    }

    /// The name of a process holding a file open under `mountPath`, via `lsof +D` scoped to that path — the only
    /// way to name a busy app without root or an entitlement (measured 2026-10-25). A watchdog kills `lsof` after 5 s
    /// instead of blocking forever (CLAUDE.md rule 21: no `timeout(1)` binary on this machine) — `nonisolated` and
    /// synchronous because the caller already runs this off the main actor (`attemptEject`'s `Task.detached`).
    nonisolated func busyApplicationName(mountPath: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        // `-t`: process ids only (a few bytes — the pipe can never fill before we read it, unlike full `+D` output on
        // a busy volume), names resolved below. Review 2026-10-25: the COMMAND column is truncated by lsof.
        process.arguments = ["-t", "+D", mountPath]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        guard (try? process.run()) != nil else { return nil }
        let deadline = DispatchTime.now() + 5
        while process.isRunning && DispatchTime.now() < deadline {
            usleep(50_000)
        }
        if process.isRunning {
            process.terminate()
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        // First data line (after the header) names the process holding something open; XFinder's own handles on a
        // folder it is merely displaying would show as "XFinder" too, so the caller already excludes mounts
        // `busyVolumes` covers (an XFinder file-operation job) before ever asking this question.
        let ownPID: pid_t = ProcessInfo.processInfo.processIdentifier
        let pids: [pid_t] = text.split(separator: "\n").compactMap { pid_t($0.trimmingCharacters(in: .whitespaces)) }
        guard let pid: pid_t = pids.first(where: { $0 != ownPID }) else { return nil }
        return Self.displayName(of: pid)
    }

    /// The app's own name when it is an app (NSRunningApplication), else the executable's full file name.
    private nonisolated static func displayName(of pid: pid_t) -> String? {
        if let name: String = NSRunningApplication(processIdentifier: pid)?.localizedName, !name.isEmpty { return name }
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return (String(cString: buffer) as NSString).lastPathComponent
    }

    // MARK: - XF-T30 W3: actually ejecting

    /// Ejects `mountPaths` (one for "just this volume", several for "all volumes on this disk" — R69).
    /// `force: true` uses `kDADiskUnmountOptionForce` (R67's "may lose unsaved changes" warning belongs to the
    /// caller, shown before this runs) but NEVER on a volume `info(for:)` reports as internal (R70) — checked here
    /// too, not just by the UI only offering eject on external/network volumes, so a stale sidebar row can never
    /// force-eject a boot disk. Runs off the main actor (DiskArbitration callbacks still land on the main run
    /// loop via a dedicated session scheduled there) and reports one refusal per path that failed.
    func attemptEject(mountPaths: [String], force: Bool) async -> [String: EjectRefusal] {
        var refusals: [String: EjectRefusal] = [:]
        for mountPath in mountPaths {
            guard let info = info(for: mountPath) else {
                refusals[mountPath] = .notFound
                continue
            }
            if force && info.isInternal {
                refusals[mountPath] = .internalDisk
                continue
            }
            if busyVolumes.contains(where: { ($0 as NSString).standardizingPath == mountPath }) {
                refusals[mountPath] = .xfinderBusy
                continue
            }
            let result = await ejectOne(mountPath: mountPath, force: force)
            if let result {
                if result == DAReturn(kDAReturnBusy), force == false {
                    let appName = busyApplicationName(mountPath: mountPath)
                    refusals[mountPath] = .appBusy(appName: appName)
                } else if result != DAReturn(kDAReturnSuccess) {
                    refusals[mountPath] = .appBusy(appName: busyApplicationName(mountPath: mountPath))
                }
            }
        }
        return refusals
    }

    /// `kDADiskUnmountOptionForce` ejects files-still-active volumes; `kDADiskUnmountOptionWhole` is deliberately
    /// NOT passed even for "eject all volumes" (R70: a single `Whole` unmount of one disk's volume must never be
    /// trusted to leave siblings on a DIFFERENT disk untouched — explicit per-volume calls, one per `mountPaths`
    /// entry from the caller, are the only way `attemptEject` can promise that).
    private func ejectOne(mountPath: String, force: Bool) async -> DAReturn? {
        guard let session = DASessionCreate(kCFAllocatorDefault) else { return DAReturn(kDAReturnError) }
        // Bug fix (verify pass, 2026-10-25): `DADiskUnmount`'s completion callback is delivered by this session's
        // run loop — an unscheduled session never pumps it, so the continuation below would hang forever (measured:
        // a real eject attempt never returned). Scheduled on the main run loop, same as `ensureSession()` above, and
        // unscheduled again once this one-shot call completes (nothing else uses this private session).
        DASessionScheduleWithRunLoop(session, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        defer { DASessionUnscheduleFromRunLoop(session, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue) }
        guard let disk = DADiskCreateFromVolumePath(kCFAllocatorDefault, session, URL(fileURLWithPath: mountPath) as CFURL)
        else { return nil }
        return await withCheckedContinuation { continuation in
            let options: DADiskUnmountOptions = force ? DADiskUnmountOptions(kDADiskUnmountOptionForce) : DADiskUnmountOptions(kDADiskUnmountOptionDefault)
            DADiskUnmount(disk, options, { _, dissenter, context in
                let box = Unmanaged<ContinuationBox>.fromOpaque(context!).takeRetainedValue()
                let status = dissenter.map { DADissenterGetStatus($0) } ?? DAReturn(kDAReturnSuccess)
                box.continuation.resume(returning: status)
            }, Unmanaged.passRetained(ContinuationBox(continuation: continuation)).toOpaque())
        }
    }
}

/// Carries a `CheckedContinuation` across the C callback boundary — DiskArbitration's `DADiskUnmountCallback`
/// takes an untyped `void *` context, so the continuation (not `Sendable` on its own in this shape) is boxed in a
/// plain class and passed via `Unmanaged`, matching the same pattern `EjectGuard`'s own approval callbacks already
/// use for `self`.
private final class ContinuationBox {
    let continuation: CheckedContinuation<DAReturn, Never>
    init(continuation: CheckedContinuation<DAReturn, Never>) {
        self.continuation = continuation
    }
}
