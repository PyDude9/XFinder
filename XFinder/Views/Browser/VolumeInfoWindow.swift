import SwiftUI

/// XF-T30 W7 — Get Info for a disk: format, capacity, available (purgeable apart), used, mount point; read in the
/// background with a 2 s cap so an unresponsive server never blocks. W7 builder (info).
@MainActor
final class VolumeInfoWindowController {
    static let shared = VolumeInfoWindowController()
    func show(volumePath: String) {}
}
