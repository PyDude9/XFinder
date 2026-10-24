import Foundation
import DiskArbitration

/// XF-T28 cluster B. Blocks `diskutil unmount`/`eject` (and Finder's own eject) on a volume that a running
/// FileOperationQueue job is reading from or writing to — measured 2026-10-24: `DARegisterDiskUnmountApprovalCallback`
/// / `DARegisterDiskEjectApprovalCallback` returning a dissenter makes `diskutil unmount`/`eject` fail with
/// `kDAReturnBusy` ("XFinder: a file operation is running"), confirmed from an ordinary (non-root, non-entitled)
/// process; a positive control with no dissenter let the same unmount through. Matching is by the disk's **mounted
/// volume path** (`kDADiskDescriptionVolumePathKey`), never by BSD name — an APFS volume is a synthesized disk whose
/// BSD name (e.g. `disk7s1`) does not correspond to the physical disk a user thinks of (`disk6`); the mount path is
/// the one identifier that is stable and meaningful to both XFinder and the user.
@MainActor final class EjectGuard {
    static let shared = EjectGuard()

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
}
