import Foundation
import Combine

@MainActor
public final class WebsiteAnalyticsViewModel: ObservableObject {
    @Published public private(set) var snapshot: WebsiteAnalyticsSnapshot
    @Published public var isShowingConfiguration: Bool = false
    @Published public var configError: WebsiteAnalyticsError? = nil

    // Non-sensitive form fields (API key input is cleared immediately after save/cancel/disconnect).
    @Published public var dataFastSiteLabelInput: String = ""
    @Published public var dataFastAPIKeyInput: String = ""
    @Published public var ga4PropertyIdInput: String = ""
    @Published public var ga4PropertyLabelInput: String = ""
    @Published public var ga4OAuthClientIdInput: String = ""

    public var onOpenSettingsRequested: (() -> Void)?

    public let coordinator: WebsiteAnalyticsCoordinator
    private let configStore: WebsiteAnalyticsConfigStore
    private let clock: @Sendable () -> Date
    private var activeTask: Task<Void, Never>?

    public init(
        coordinator: WebsiteAnalyticsCoordinator,
        configStore: WebsiteAnalyticsConfigStore = UserDefaultsWebsiteAnalyticsConfigStore(),
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.coordinator = coordinator
        self.configStore = configStore
        self.clock = clock
        let initialProvider = configStore.selectedProvider()
        self.snapshot = WebsiteAnalyticsSnapshot(
            selectedProvider: initialProvider,
            selectedRange: .sevenDays,
            dataFastState: .unconfigured(reason: .missingCredentials),
            ga4State: .unconfigured(reason: .missingProperty),
            oauthInProgress: false
        )
        loadFormFieldsFromConfig()

        Task { [weak self] in
            guard let self else { return }
            await self.coordinator.setSnapshotChangeHandler { [weak self] newSnap in
                Task { @MainActor [weak self] in
                    self?.snapshot = newSnap
                }
            }
            await self.syncState()
        }
    }

    public static func makeDefault() -> WebsiteAnalyticsViewModel {
        let configStore = UserDefaultsWebsiteAnalyticsConfigStore()
        let coordinator = WebsiteAnalyticsCoordinator.makeDefault(configStore: configStore)
        return WebsiteAnalyticsViewModel(coordinator: coordinator, configStore: configStore)
    }

    public func syncState() async {
        self.snapshot = await coordinator.snapshot
    }

    public var selectedProvider: WebsiteAnalyticsProviderKind { snapshot.selectedProvider }
    public var selectedRange: WebsiteAnalyticsRange { snapshot.selectedRange }
    public var activeState: WebsiteAnalyticsProviderState { snapshot.activeState }
    public var activeReport: WebsiteAnalyticsReport? { activeState.report }
    public var isRefreshing: Bool { activeState.isRefreshing }
    public var oauthInProgress: Bool { snapshot.oauthInProgress }

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
        isShowingConfiguration = false
        configError = nil
        clearSensitiveInputs()
        Task { await coordinator.close() }
    }

    public func setDestinationEnabled(_ enabled: Bool) {
        activeTask?.cancel()
        activeTask = Task { [weak self] in
            guard let self else { return }
            await self.coordinator.setDestinationEnabled(enabled)
            await self.syncState()
        }
    }

    public func prepareForTermination() {
        activeTask?.cancel()
        activeTask = nil
        isShowingConfiguration = false
        configError = nil
        clearSensitiveInputs()
        Task { await coordinator.prepareForTermination() }
    }

    public func selectProvider(_ provider: WebsiteAnalyticsProviderKind) {
        configError = nil
        isShowingConfiguration = false
        clearSensitiveInputs()
        activeTask?.cancel()
        activeTask = Task { [weak self] in
            guard let self else { return }
            await self.coordinator.selectProvider(provider)
            await self.syncState()
            if case .unconfigured = self.snapshot.activeState {
                self.loadFormFieldsFromConfig()
            }
        }
    }

    public func selectRange(_ range: WebsiteAnalyticsRange) {
        activeTask?.cancel()
        activeTask = Task { [weak self] in
            guard let self else { return }
            await self.coordinator.selectRange(range)
            await self.syncState()
        }
    }

    public func refresh() {
        activeTask?.cancel()
        activeTask = Task { [weak self] in
            guard let self else { return }
            await self.coordinator.refresh(force: true)
            await self.syncState()
        }
    }

    public func openConfiguration() {
        configError = nil
        loadFormFieldsFromConfig()
        isShowingConfiguration = true
    }

    public func closeConfiguration() {
        activeTask?.cancel()
        configError = nil
        clearSensitiveInputs()
        isShowingConfiguration = false
    }

    public func saveDataFastConfiguration() {
        configError = nil
        let label = dataFastSiteLabelInput
        let key = dataFastAPIKeyInput
        activeTask?.cancel()
        activeTask = Task { [weak self] in
            guard let self else { return }
            let result = await self.coordinator.saveDataFastConfiguration(siteLabel: label, apiKey: key)
            switch result {
            case .success:
                self.clearSensitiveInputs()
                self.isShowingConfiguration = false
            case .failure(let err):
                self.configError = err
            }
            await self.syncState()
        }
    }

    public func saveGA4Configuration() {
        configError = nil
        let propId = ga4PropertyIdInput
        let propLabel = ga4PropertyLabelInput
        let clientId = ga4OAuthClientIdInput
        activeTask?.cancel()
        activeTask = Task { [weak self] in
            guard let self else { return }
            let result = await self.coordinator.saveGA4Configuration(
                propertyId: propId,
                propertyLabel: propLabel,
                oauthClientId: clientId,
                redirectURI: nil
            )
            switch result {
            case .success:
                self.configError = nil
            case .failure(let err):
                self.configError = err
            }
            await self.syncState()
        }
    }

    public func startGA4OAuth() {
        configError = nil
        activeTask?.cancel()
        activeTask = Task { [weak self] in
            guard let self else { return }
            let result = await self.coordinator.startGA4OAuth()
            guard !Task.isCancelled else { return }
            switch result {
            case .success:
                self.isShowingConfiguration = false
                self.configError = nil
            case .failure(let err):
                self.configError = err
            }
            await self.syncState()
        }
    }

    public func cancelGA4OAuth() {
        Task { [weak self] in
            guard let self else { return }
            await self.coordinator.cancelGA4OAuth()
            await self.syncState()
        }
    }

    public func disconnect(_ provider: WebsiteAnalyticsProviderKind) {
        configError = nil
        clearSensitiveInputs()
        activeTask?.cancel()
        activeTask = Task { [weak self] in
            guard let self else { return }
            await self.coordinator.disconnect(provider: provider)
            await self.syncState()
            self.loadFormFieldsFromConfig()
        }
    }

    public func freshnessLabel(for report: WebsiteAnalyticsReport?) -> String {
        guard let report else { return "" }
        let age = max(0, clock().timeIntervalSince(report.fetchedAt))
        if age < 60 { return L10n.t("Vừa xong") }
        let mins = max(1, Int(age / 60))
        if mins < 60 {
            return "\(L10n.t("Cập nhật "))\(mins)\(L10n.t(" phút trước"))"
        }
        return "\(L10n.t("Cập nhật "))\(mins / 60)\(L10n.t(" giờ trước"))"
    }

    private func loadFormFieldsFromConfig() {
        if let df = configStore.loadDataFastConfig() {
            dataFastSiteLabelInput = df.siteLabel
        } else {
            dataFastSiteLabelInput = ""
        }
        if let ga = configStore.loadGA4Config() {
            ga4PropertyIdInput = ga.propertyId
            ga4PropertyLabelInput = ga.propertyLabel
            ga4OAuthClientIdInput = ga.oauthClientId
        } else {
            ga4PropertyIdInput = ""
            ga4PropertyLabelInput = ""
            ga4OAuthClientIdInput = ""
        }
        dataFastAPIKeyInput = ""
    }

    private func clearSensitiveInputs() {
        dataFastAPIKeyInput = ""
    }
}
