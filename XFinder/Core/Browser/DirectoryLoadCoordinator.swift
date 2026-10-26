import Foundation

/// XF-T32 W0 — stub (builder `coordinator`): one listing + one watcher per folder, shared by every pane. Contract §B.
@MainActor final class ListingSubscription {
    private var onCancel: (() -> Void)?
    init(onCancel: @escaping () -> Void) { self.onCancel = onCancel }
    func cancel() { onCancel?(); onCancel = nil }
    deinit { }
}

@MainActor final class DirectoryLoadCoordinator {
    typealias WatcherFactory = @MainActor (String, @escaping @MainActor () -> Void, @escaping @MainActor () -> Void) -> DirectoryWatcher?

    static let shared = DirectoryLoadCoordinator(cache: .shared, limiter: .shared,
                                                 watcherFactory: { path, onChange, onGone in DirectoryWatcher(path: path, onChange: onChange, onGone: onGone) })
    private let cache: ListingDiskCache
    private let limiter: DirectoryWorkLimiter
    private let watcherFactory: WatcherFactory

    init(cache: ListingDiskCache, limiter: DirectoryWorkLimiter, watcherFactory: @escaping WatcherFactory) {
        self.cache = cache; self.limiter = limiter; self.watcherFactory = watcherFactory
    }

    func subscribe(path: String,
                   onListing: @escaping @MainActor (Result<ListingDelivery, DirectoryReadError>) -> Void,
                   onGone: @escaping @MainActor () -> Void) -> ListingSubscription {
        ListingSubscription(onCancel: {})
    }

    func reload(path: String) {}
    func activeSessionCount() -> Int { 0 }
}
