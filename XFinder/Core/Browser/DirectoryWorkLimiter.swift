import Foundation

/// XF-T32 W0 — stub (builder `coordinator`): FIFO concurrency gate for disk reads. Contract §B.
actor DirectoryWorkLimiter {
    static let shared = DirectoryWorkLimiter(maxConcurrent: LoadCoordinatorRules.diskReadConcurrency)
    private let maxConcurrent: Int

    init(maxConcurrent: Int) { self.maxConcurrent = max(1, maxConcurrent) }

    func run<T: Sendable>(_ body: @Sendable @escaping () async -> T) async -> T { await body() }
    func inFlight() -> Int { 0 }
}
