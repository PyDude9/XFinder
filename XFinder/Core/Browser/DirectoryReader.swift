import Foundation

/// XF-T28 cluster A — STUB written by the integrator; the cluster agent replaces the bodies (contract:
/// docs/specs/XF-T28-ui-contract.md). Public signatures are binding.
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
}

enum DirectoryReader {
    static func list(_ path: String) -> Result<[DirectoryEntry], DirectoryReadError> { .success([]) }
    static func list(_ path: String, timeout: TimeInterval) async -> Result<[DirectoryEntry], DirectoryReadError> { list(path) }
    static func subfolders(of path: String, showHidden: Bool, timeout: TimeInterval) async -> Result<[String], DirectoryReadError> { .success([]) }
    static func volumeID(of path: String) -> Int32? { nil }
    static func volumePath(of path: String) -> String? { nil }
    static func hasCoarseTimestamps(_ path: String) -> Bool { false }
    static func freeSpace(of path: String) -> Int64? { nil }
}

@MainActor final class DirectoryWatcher {
    init?(path: String, onChange: @escaping @MainActor () -> Void, onGone: @escaping @MainActor () -> Void) { return nil }
    func cancel() {}
}
