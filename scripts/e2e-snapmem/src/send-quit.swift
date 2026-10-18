import Foundation

// send-quit
// Posts the distributed notification com.xfinder.e2e.snapmem.quit, which
// SnapMemTarget.app listens for and terminates on. This is the harness's
// OWN cleanup signal to its OWN throw-away app — it has nothing to do with
// XFinder and touches no XFinder process, defaults domain, or window.

let name = Notification.Name("com.xfinder.e2e.snapmem.quit")
DistributedNotificationCenter.default().postNotificationName(
    name,
    object: nil,
    userInfo: nil,
    deliverImmediately: true
)
print("posted \(name.rawValue)")
