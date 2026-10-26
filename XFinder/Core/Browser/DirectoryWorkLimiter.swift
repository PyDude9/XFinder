import Foundation

/// XF-T32 W0 — FIFO concurrency gate for folder reads (contract §B). At most `maxConcurrent` bodies run at once;
/// the rest wait in arrival order. A freed slot is handed straight to the oldest waiter (no barging).
///
/// Cancellation: a task cancelled before it gets a slot leaves the queue at once and never takes a slot. Because
/// `run` must return a `T`, its body is then called immediately with `Task.isCancelled == true` and is expected to
/// return a cheap placeholder without doing the real work (the coordinator's body does exactly that).
actor DirectoryWorkLimiter {
    static let shared: DirectoryWorkLimiter = DirectoryWorkLimiter(maxConcurrent: LoadCoordinatorRules.diskReadConcurrency)

    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Bool, Never>
    }

    private let maxConcurrent: Int
    private var running: Int = 0
    private var waiters: [Waiter] = []

    init(maxConcurrent: Int) { self.maxConcurrent = max(1, maxConcurrent) }

    func run<T: Sendable>(_ body: @Sendable @escaping () async -> T) async -> T {
        let acquired: Bool = await acquireSlot()
        guard acquired else { return await body() }
        let value: T = await body()
        releaseSlot()
        return value
    }

    func inFlight() -> Int { running }

    // MARK: - Slots

    /// `true` once a slot is held; `false` when the calling task was cancelled before it got one.
    private func acquireSlot() async -> Bool {
        if Task.isCancelled { return false }
        if running < maxConcurrent && waiters.isEmpty {
            running += 1
            return true
        }
        let id: UUID = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                // Cancelled between the check above and here: the cancel handler may already have run (and found
                // nothing to remove), so do not enqueue.
                if Task.isCancelled {
                    continuation.resume(returning: false)
                    return
                }
                waiters.append(Waiter(id: id, continuation: continuation))
            }
        } onCancel: {
            Task { await self.cancelWaiter(id) }
        }
    }

    /// Hands the slot to the oldest waiter (the running count stays the same) or frees it.
    private func releaseSlot() {
        if waiters.isEmpty {
            running = max(0, running - 1)
            return
        }
        let next: Waiter = waiters.removeFirst()
        next.continuation.resume(returning: true)
    }

    /// Removes a cancelled waiter; a waiter that already received a slot is no longer in the queue and is left alone.
    private func cancelWaiter(_ id: UUID) {
        guard let index: Int = waiters.firstIndex(where: { $0.id == id }) else { return }
        let waiter: Waiter = waiters.remove(at: index)
        waiter.continuation.resume(returning: false)
    }
}
