import Foundation
import os

/// XF-T32 W0 — one listing + one watcher per folder, shared by every pane (contract §B).

/// Handle returned by `DirectoryLoadCoordinator.subscribe`. `cancel()` is idempotent; dropping the last reference
/// cancels too.
@MainActor final class ListingSubscription {
    private var onCancel: (@MainActor @Sendable () -> Void)?

    init(onCancel: @escaping @MainActor @Sendable () -> Void) { self.onCancel = onCancel }

    func cancel() {
        let action: (@MainActor @Sendable () -> Void)? = onCancel
        onCancel = nil
        action?()
    }

    deinit {
        guard let action: @MainActor @Sendable () -> Void = onCancel else { return }
        if Thread.isMainThread {
            MainActor.assumeIsolated { action() }
        } else {
            Task { @MainActor in action() }
        }
    }
}

@MainActor final class DirectoryLoadCoordinator {
    typealias WatcherFactory = @MainActor (String, @escaping @MainActor () -> Void, @escaping @MainActor () -> Void) -> DirectoryWatcher?
    typealias ListingHandler = @MainActor (Result<ListingDelivery, DirectoryReadError>) -> Void
    typealias GoneHandler = @MainActor () -> Void

    static let shared: DirectoryLoadCoordinator = DirectoryLoadCoordinator(
        cache: .shared, limiter: .shared,
        watcherFactory: { path, onChange, onGone in DirectoryWatcher(path: path, onChange: onChange, onGone: onGone) })

    /// A folder read that does not answer within this many seconds is delivered as `.timedOut`.
    private static let readTimeout: TimeInterval = 5
    private static let log: Logger = Logger(subsystem: "com.xfinder.app", category: "listing")

    private let cache: ListingDiskCache
    private let limiter: DirectoryWorkLimiter
    private let watcherFactory: WatcherFactory
    private var book: LoadCoordinatorRules.SessionBook = LoadCoordinatorRules.SessionBook()
    private var sessions: [String: Session] = [:]

    init(cache: ListingDiskCache, limiter: DirectoryWorkLimiter, watcherFactory: @escaping WatcherFactory) {
        self.cache = cache; self.limiter = limiter; self.watcherFactory = watcherFactory
    }

    // MARK: - Public API

    func subscribe(path: String,
                   onListing: @escaping @MainActor (Result<ListingDelivery, DirectoryReadError>) -> Void,
                   onGone: @escaping @MainActor () -> Void) -> ListingSubscription {
        let key: String = Self.sessionKey(for: path)
        let id: UUID = UUID()
        let subscriber: Subscriber = Subscriber(onListing: onListing, onGone: onGone)
        switch book.subscribe(path: key, id: id) {
        case .started:
            let session: Session = Session(path: key)
            session.subscribers[id] = subscriber
            session.order.append(id)
            sessions[key] = session
            session.watcher = watcherFactory(key,
                                             { [weak self] in self?.reload(path: key) },
                                             { [weak self] in self?.handleGone(key: key) })
            startLoad(session, consultCache: true)
        case .joined, .left, .closed, .unknown:
            if let session: Session = sessions[key] {
                if session.subscribers[id] == nil { session.order.append(id) }
                session.subscribers[id] = subscriber
                if let last: Result<ListingDelivery, DirectoryReadError> = session.lastResult { onListing(last) }
            }
        }
        return ListingSubscription(onCancel: { [weak self] in self?.unsubscribe(key: key, id: id) })
    }

    func reload(path: String) {
        let key: String = Self.sessionKey(for: path)
        guard let session: Session = sessions[key] else { return }
        if session.isLoading {
            session.rereadPending = true
            return
        }
        startLoad(session, consultCache: false)
    }

    func activeSessionCount() -> Int { sessions.count }

    // MARK: - Session lifecycle

    private struct Subscriber {
        let onListing: ListingHandler
        let onGone: GoneHandler
    }

    @MainActor private final class Session {
        /// Lexical key (`LoadCoordinatorRules.lexicalPath`) — also the path that is read, watched and cached.
        let path: String
        var subscribers: [UUID: Subscriber] = [:]
        /// Subscription order, so deliveries reach panes in the order they subscribed.
        var order: [UUID] = []
        var watcher: DirectoryWatcher?
        var task: Task<Void, Never>?
        var isLoading: Bool = false
        var rereadPending: Bool = false
        var lastResult: Result<ListingDelivery, DirectoryReadError>?

        init(path: String) { self.path = path }
    }

    /// Same folder ⇒ same key. Lexical only (`~`, `.`, `..`, duplicate and trailing slashes): `standardizingPath`
    /// also strips `/private` from an EXISTING `/private/var/…`, and the key is the path that gets read, so entry
    /// paths would come back under a spelling the pane never asked for.
    private static func sessionKey(for path: String) -> String {
        LoadCoordinatorRules.lexicalPath((path as NSString).expandingTildeInPath)
    }

    private func isLive(_ session: Session) -> Bool { sessions[session.path] === session }

    private func unsubscribe(key: String, id: UUID) {
        let event: LoadCoordinatorRules.SessionBook.Event = book.unsubscribe(path: key, id: id)
        guard let session: Session = sessions[key] else { return }
        switch event {
        case .left:
            session.subscribers[id] = nil
            session.order.removeAll { $0 == id }
        case .closed:
            close(session)
        case .started, .joined, .unknown:
            break
        }
    }

    /// Stops the watcher and any load, and forgets the session (its subscribers must already be out of the book).
    private func close(_ session: Session) {
        session.watcher?.cancel()
        session.watcher = nil
        session.task?.cancel()
        session.task = nil
        session.subscribers.removeAll()
        session.order.removeAll()
        if isLive(session) { sessions[session.path] = nil }
    }

    /// The folder itself was deleted or renamed: every subscriber hears `onGone` once, then the session is gone and
    /// nothing more is delivered.
    private func handleGone(key: String) {
        guard let session: Session = sessions[key] else { return }
        let gone: [GoneHandler] = session.order.compactMap { session.subscribers[$0]?.onGone }
        for id in session.order { _ = book.unsubscribe(path: key, id: id) }
        close(session)
        Task { [cache] in await cache.invalidate(key) }
        for handler in gone { handler() }
    }

    // MARK: - Loading

    private func startLoad(_ session: Session, consultCache: Bool) {
        session.isLoading = true
        session.rereadPending = false
        session.task = Task { [weak self] in
            await self?.runLoad(session, consultCache: consultCache)
        }
    }

    /// Cache phase (first subscriber only) then disk reads until no reload arrived meanwhile — never two reads of
    /// the same folder at once.
    private func runLoad(_ session: Session, consultCache: Bool) async {
        defer { if isLive(session) { session.isLoading = false; session.task = nil } }
        var needsDisk: Bool = true
        if consultCache {
            needsDisk = await deliverFromCache(session)
            guard isLive(session), !Task.isCancelled else { return }
        }
        while needsDisk || session.rereadPending {
            needsDisk = false
            session.rereadPending = false
            await readDisk(session)
            guard isLive(session), !Task.isCancelled else { return }
        }
    }

    /// Delivers the cached listing if there is one; returns whether a disk read is still needed.
    private func deliverFromCache(_ session: Session) async -> Bool {
        let started: ContinuousClock.Instant = ContinuousClock.now
        let path: String = session.path
        let cached: (token: ListingToken, entries: [DirectoryEntry])? = await cache.lookup(path)
        guard isLive(session), !Task.isCancelled else { return false }
        guard let hit: (token: ListingToken, entries: [DirectoryEntry]) = cached else { return true }
        let current: ListingToken? = await Self.statToken(path)
        guard isLive(session), !Task.isCancelled else { return false }
        let decisions: [LoadCoordinatorRules.Decision] = LoadCoordinatorRules.plan(hasCache: true, stored: hit.token, current: current)
        var needsDisk: Bool = false
        for decision in decisions {
            switch decision {
            case .deliverCache(let final):
                let delivery: ListingDelivery = ListingDelivery(entries: hit.entries, source: .cache, token: hit.token, isFinal: final)
                deliver(.success(delivery), to: session, started: started)
            case .readDisk:
                needsDisk = true
            }
        }
        return needsDisk
    }

    private func readDisk(_ session: Session) async {
        let started: ContinuousClock.Instant = ContinuousClock.now
        let path: String = session.path
        // Token first: a change during the read then mismatches next time instead of hiding behind a fresh token.
        let token: ListingToken? = await Self.statToken(path)
        guard isLive(session), !Task.isCancelled else { return }
        let timeout: TimeInterval = Self.readTimeout
        let result: Result<[DirectoryEntry], DirectoryReadError> = await limiter.run {
            if Task.isCancelled { return .failure(.other(ECANCELED)) }
            return await DirectoryReader.list(path, timeout: timeout)
        }
        guard isLive(session), !Task.isCancelled else { return }
        switch result {
        case .success(let entries):
            let delivery: ListingDelivery = ListingDelivery(entries: entries, source: .disk, token: token, isFinal: true)
            deliver(.success(delivery), to: session, started: started)
            if let storedToken: ListingToken = token {
                Task { [cache] in await cache.store(path, token: storedToken, entries: entries) }
            }
        case .failure(let error):
            deliver(.failure(error), to: session, started: started)
            if error == .notFound || error == .notDirectory {
                Task { [cache] in await cache.invalidate(path) }
            }
        }
    }

    /// `stat` off the main thread (a dead network share must not freeze the UI).
    private static func statToken(_ path: String) async -> ListingToken? {
        await Task.detached(priority: .userInitiated) { ListingDiskCache.currentToken(for: path) }.value
    }

    /// Hands one result to every subscriber still attached at this moment and remembers it for late joiners.
    private func deliver(_ result: Result<ListingDelivery, DirectoryReadError>, to session: Session,
                         started: ContinuousClock.Instant) {
        guard isLive(session) else { return }
        session.lastResult = result
        logDelivery(result, path: session.path, started: started)
        for id in session.order {
            guard isLive(session), let subscriber: Subscriber = session.subscribers[id] else { continue }
            subscriber.onListing(result)
        }
    }

    private func logDelivery(_ result: Result<ListingDelivery, DirectoryReadError>, path: String,
                             started: ContinuousClock.Instant) {
        let elapsed: Duration = ContinuousClock.now - started
        let ms: Int64 = elapsed.components.seconds * 1_000 + elapsed.components.attoseconds / 1_000_000_000_000_000
        switch result {
        case .success(let delivery):
            let source: String = delivery.source == .cache ? "cache" : "disk"
            Self.log.info("\(path, privacy: .public) source=\(source, privacy: .public) count=\(delivery.entries.count) ms=\(ms)")
        case .failure(let error):
            Self.log.info("\(path, privacy: .public) source=disk error=\(String(describing: error), privacy: .public) ms=\(ms)")
        }
    }
}
