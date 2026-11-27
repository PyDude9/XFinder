import Foundation
import Combine

@MainActor
public final class RevenueViewModel: ObservableObject {
    @Published public private(set) var snapshot: RevenueSnapshot
    @Published public var selectedChartSource: RevenueSourceKind = .stripe
    @Published public var selectedChartCurrency: String? = nil

    public var onOpenSettingsRequested: (() -> Void)?

    public let coordinator: RevenueCoordinator
    private let clock: @Sendable () -> Date
    private var activeTask: Task<Void, Never>?

    public init(coordinator: RevenueCoordinator, clock: @escaping @Sendable () -> Date = { Date() }) {
        self.coordinator = coordinator
        self.clock = clock
        self.snapshot = RevenueSnapshot(
            period: .today,
            stripeState: .unconfigured,
            shopifyState: .unconfigured,
            reconciliationStatus: .singleSourceOrNone,
            combinedTotalsByCurrency: nil
        )
        Task { [weak self] in
            guard let self else { return }
            await self.coordinator.setSnapshotChangeHandler { [weak self] newSnap in
                Task { @MainActor [weak self] in
                    self?.applySnapshot(newSnap)
                }
            }
            await self.syncState()
        }
    }

    public func syncState() async {
        let s = await coordinator.snapshot
        applySnapshot(s)
    }

    private func applySnapshot(_ next: RevenueSnapshot) {
        self.snapshot = next
        if next.stripeState.report == nil, next.shopifyState.report != nil {
            selectedChartSource = .shopify
        } else if next.shopifyState.report == nil, next.stripeState.report != nil {
            selectedChartSource = .stripe
        }
        if let activeRep = report(for: selectedChartSource) {
            let currencies = activeRep.currencyTotals.map(\.currency)
            if let cur = selectedChartCurrency, currencies.contains(cur) {
                // preserve selected currency
            } else {
                selectedChartCurrency = currencies.first
            }
        } else {
            selectedChartCurrency = nil
        }
    }

    public func onAppear() {
        activeTask?.cancel()
        activeTask = Task { [weak self] in
            guard let self else { return }
            await self.coordinator.openPage()
            await self.syncState()
        }
    }

    public func close() {
        activeTask?.cancel()
        activeTask = nil
        Task { await coordinator.close() }
    }

    public func refresh() {
        activeTask?.cancel()
        activeTask = Task { [weak self] in
            guard let self else { return }
            await self.coordinator.refresh(force: true)
            await self.syncState()
        }
    }

    public func selectPeriod(_ period: RevenuePeriod) {
        activeTask?.cancel()
        activeTask = Task { [weak self] in
            guard let self else { return }
            await self.coordinator.selectPeriod(period)
            await self.syncState()
        }
    }

    public func disconnectSource(_ source: RevenueSourceKind) {
        Task { [weak self] in
            guard let self else { return }
            await self.coordinator.disconnectSource(source)
            await self.syncState()
        }
    }

    public func state(for source: RevenueSourceKind) -> SourceSyncState {
        switch source {
        case .stripe: return snapshot.stripeState
        case .shopify: return snapshot.shopifyState
        }
    }

    public func report(for source: RevenueSourceKind) -> SourceRevenueReport? {
        state(for: source).report
    }

    public var isRefreshing: Bool {
        snapshot.stripeState.isRefreshing || snapshot.shopifyState.isRefreshing
    }

    public var isBothUnconfigured: Bool {
        if case .unconfigured = snapshot.stripeState, case .unconfigured = snapshot.shopifyState {
            return true
        }
        return false
    }

    public var activeChartCurrency: String? {
        guard let rep = report(for: selectedChartSource) else { return nil }
        let keys = rep.currencyTotals.map(\.currency)
        if let selectedChartCurrency, keys.contains(selectedChartCurrency) {
            return selectedChartCurrency
        }
        return keys.first
    }

    public var activeChartBuckets: [RevenueChartBucket] {
        guard let rep = report(for: selectedChartSource),
              let cur = activeChartCurrency else {
            return []
        }
        return rep.bucketsByCurrency[cur] ?? []
    }

    public func freshnessLabel(for source: RevenueSourceKind) -> String {
        guard let rep = report(for: source) else { return "" }
        let age = max(0, clock().timeIntervalSince(rep.fetchedAt))
        if age < 60 { return L10n.t("Vừa xong") }
        let mins = max(1, Int(age / 60))
        if mins < 60 {
            return "\(L10n.t("Cập nhật "))\(mins)\(L10n.t(" phút trước"))"
        }
        return "\(L10n.t("Cập nhật "))\(mins / 60)\(L10n.t(" giờ trước"))"
    }
}
