import SwiftUI

/// Standalone Dynamic Island Weather View (Phase 2).
/// Displays active city forecast for the upcoming 12 hours, search with debounce,
/// cache age indicators, offline fallback, error handling with retry, and provider attribution.
/// Respects VoiceOver and Reduce Motion.

public struct NotchWeatherPage: View {
    @ObservedObject public var viewModel: WeatherViewModel
    public var embedsInIsland: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isSearchFieldFocused: Bool

    public init(viewModel: WeatherViewModel, embedsInIsland: Bool = false) {
        self.viewModel = viewModel
        self.embedsInIsland = embedsInIsland
    }

    public var body: some View {
        VStack(spacing: embedsInIsland ? 5 : 8) {
            headerBar

            Divider().overlay(Color.white.opacity(0.10))

            if viewModel.isShowingSearch {
                searchOverlay
            } else {
                contentBody
            }

            attributionFooter
        }
        .padding(embedsInIsland ? 0 : 10)
        .background(embedsInIsland ? Color.clear : Color.black.opacity(0.75))
        .cornerRadius(embedsInIsland ? 0 : 14)
        .onAppear {
            if !embedsInIsland {
                viewModel.onAppear()
            }
        }
        .onDisappear {
            if !embedsInIsland {
                viewModel.close()
            }
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "cloud.sun.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.blue)

            switch viewModel.state {
            case .loaded(let snapshot, _), .refreshing(let snapshot), .offlineWithStale(let snapshot, _),
                 .failedWithStale(let snapshot, _, _):
                Text(snapshot.location.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            case .loadingInitial(let location), .offlineNoData(let location), .failed(let location, _, _):
                Text(location.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            case .unselected, .locationDenied:
                Text(L10n.t("Thời tiết"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
            }

            Spacer()

            if !viewModel.freshnessDescription.isEmpty {
                Text(viewModel.freshnessDescription)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }

            // Change city button
            Button {
                viewModel.toggleSearch()
            } label: {
                Image(systemName: viewModel.isShowingSearch ? "xmark.circle.fill" : "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(viewModel.isShowingSearch ? L10n.t("Đóng") : L10n.t("Đổi thành phố"))
            .help(L10n.t("Đổi thành phố"))

            // Refresh button
            Button {
                viewModel.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.t("Làm mới"))
            .help(L10n.t("Làm mới"))
        }
    }

    // MARK: - Content Body

    @ViewBuilder
    private var contentBody: some View {
        switch viewModel.state {
        case .loaded(let snapshot, _), .refreshing(let snapshot), .offlineWithStale(let snapshot, _):
            let upcoming = snapshot.upcoming12Hours(from: Date())
            if upcoming.isEmpty {
                noDataView
            } else {
                forecastRibbon(upcoming: upcoming, timeZone: snapshot.location.timeZone)
            }
        case .failedWithStale(let snapshot, _, let error):
            // Keep the cached ribbon on screen — a failed request does not invalidate six hours of good
            // data — and attach the failure above it as one compact row. The strip takes the height the
            // 140-pt body cannot spare from the ribbon, so it is a single line plus the icon and a Retry
            // that only appears when repeating the request can help.
            VStack(spacing: 4) {
                staleFailureStrip(error)
                let upcoming = snapshot.upcoming12Hours(from: Date())
                if upcoming.isEmpty {
                    noDataView
                } else {
                    forecastRibbon(upcoming: upcoming, timeZone: snapshot.location.timeZone)
                }
            }
        case .loadingInitial:
            VStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(L10n.t("Đang tải dự báo thời tiết..."))
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .frame(maxWidth: .infinity, minHeight: 64)
        case .offlineNoData:
            noDataView
        case .failed(_, let error, let canRetry):
            failureView(error, canRetry: canRetry)
        case .locationDenied:
            VStack(spacing: 6) {
                Image(systemName: "location.slash.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.yellow)
                Text(L10n.t("Định vị bị từ chối hoặc không khả dụng"))
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.7))
                Button(L10n.t("Chọn thành phố")) {
                    viewModel.openSearch()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .frame(maxWidth: .infinity, minHeight: 64)
        case .unselected:
            VStack(spacing: 8) {
                Text(L10n.t("Chọn thành phố"))
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))

                HStack(spacing: 8) {
                    Button(L10n.t("Chọn thành phố")) {
                        viewModel.openSearch()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Button {
                        viewModel.requestCurrentLocation()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "location.fill")
                            Text(L10n.t("Dùng vị trí"))
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help(L10n.t("Dùng vị trí hiện tại của máy để xem thời tiết mà không lưu toạ độ."))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 64)
        }
    }

    /// A failed fetch, grouped into what a person can act on (network / timeout / quota / data / permission).
    ///
    /// The body is 140 pt tall inside the Island and the header, ribbon and attribution already take their
    /// share, so this is one compact block, never a paragraph: a symbol, the headline, an optional one-line
    /// next step and — only for `canRetry` — Retry. Both texts are fixed strings chosen by
    /// `WeatherErrorPresentation` (measured worst case 222 pt wide at 10.5 pt across a 380-pt body), so a
    /// `.lineLimit(2)` never truncates; no URL, HTTP status, provider name or Swift error text is shown.
    ///
    /// Retry re-reads `canRetry` from the state rather than trusting the presentation: the coordinator
    /// already decided it, and a button that cannot work must not be drawn.
    private func failureView(_ error: WeatherError, canRetry: Bool) -> some View {
        let presentation = WeatherErrorPresentation(for: error)
        return VStack(spacing: 5) {
            Image(systemName: presentation.symbol)
                .font(.system(size: 17))
                .foregroundStyle(canRetry ? Color.orange : Color.red)
                .accessibilityHidden(true)

            Text(L10n.t(presentation.titleKey))
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            if let hintKey = presentation.hintKey {
                Text(L10n.t(hintKey))
                    .font(.system(size: 9.5))
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if canRetry {
                Button(L10n.t("Thử lại")) {
                    viewModel.refresh()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 64)
        // Deliberately NOT `.accessibilityElement(children: .combine)`: that folds Retry into the group and
        // leaves VoiceOver nothing separately focusable to press. The symbol is hidden instead, so the
        // headline, the hint and the button are each read and reachable on their own.
    }

    /// The failure attached to a still-valid cached forecast, as one compact row.
    ///
    /// This is the `failedWithStale` twin of `failureView`, and it is one line on purpose: the ribbon below
    /// it is the reason the person opened the page, and the 140-pt Island body cannot hold a centred block
    /// plus twelve hourly cards. The headline names the group; Retry appears only where it can help.
    private func staleFailureStrip(_ error: WeatherError) -> some View {
        let presentation = WeatherErrorPresentation(for: error)
        return HStack(spacing: 5) {
            Image(systemName: presentation.symbol)
                .font(.system(size: 10))
                .foregroundStyle(presentation.canRetry ? Color.orange : Color.red)
                .accessibilityHidden(true)

            Text(L10n.t(presentation.titleKey))
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 2)

            if presentation.canRetry {
                Button(L10n.t("Thử lại")) {
                    viewModel.refresh()
                }
                .buttonStyle(.plain)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(.blue.opacity(0.9))
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color.orange.opacity(0.10))
        .cornerRadius(5)
        // The cached forecast keeps its own accessibility; this row is a separate, readable notice.
    }

    private var noDataView: some View {
        VStack(spacing: 6) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 18))
                .foregroundStyle(.orange)
            Text(L10n.t("Không có dữ liệu thời tiết"))
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.7))
            Button(L10n.t("Thử lại")) {
                viewModel.refresh()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, minHeight: 64)
    }

    // MARK: - 12-Hour Forecast Ribbon

    private func forecastRibbon(upcoming: [HourlyForecast], timeZone: TimeZone) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(upcoming, id: \.date) { item in
                    hourlyCard(item: item, timeZone: timeZone)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func hourlyCard(item: HourlyForecast, timeZone: TimeZone) -> some View {
        let hourString = item.formattedHour(using: timeZone)
        let tempString = item.formattedTemperature()
        let conditionDesc = L10n.t(item.condition.accessibilityLabelKey)

        let precipLabel = item.precipitationProbability.map { "\(Int(round($0)))%" } ?? ""
        let a11yText = "\(hourString), \(conditionDesc), \(tempString)\(precipLabel.isEmpty ? "" : ", \(L10n.t("Mưa: "))\(precipLabel)")"

        return VStack(spacing: 4) {
            Text(hourString)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.6))
                .monospacedDigit()

            Image(systemName: item.condition.sfSymbol)
                .font(.system(size: 14))
                .foregroundStyle(.white)
                .frame(height: 18)

            Text(tempString)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)

            if let p = item.precipitationProbability, p > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "drop.fill")
                        .font(.system(size: 7))
                        .foregroundStyle(.blue)
                    Text("\(Int(round(p)))%")
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundStyle(.blue)
                }
            } else {
                Spacer().frame(height: 10)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.06))
        .cornerRadius(8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(a11yText)
    }

    // MARK: - Search Overlay

    private var searchOverlay: some View {
        VStack(spacing: 6) {
            HStack {
                Button {
                    viewModel.requestCurrentLocation()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "location.fill")
                            .font(.system(size: 10))
                        Text(L10n.t("Dùng vị trí hiện tại"))
                            .font(.system(size: 10.5))
                    }
                    .foregroundStyle(.blue.opacity(0.9))
                }
                .buttonStyle(.plain)
                .help(L10n.t("Dùng vị trí hiện tại của máy để xem thời tiết mà không lưu toạ độ."))

                Spacer()
            }
            .padding(.horizontal, 2)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))

                TextField(L10n.t("Nhập tên thành phố..."), text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .focused($isSearchFieldFocused)
                    .onChange(of: viewModel.searchText) { _, newText in
                        viewModel.onSearchTextChanged(newText)
                    }

                if !viewModel.searchText.isEmpty {
                    Button {
                        viewModel.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.t("Xoá tìm kiếm"))
                }
            }
            .padding(6)
            .background(Color.white.opacity(0.08))
            .cornerRadius(6)

            if viewModel.isSearching {
                ProgressView()
                    .controlSize(.small)
                    .padding(.vertical, 6)
            } else if !viewModel.searchResults.isEmpty {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(viewModel.searchResults) { loc in
                            Button {
                                viewModel.selectLocation(loc)
                            } label: {
                                HStack {
                                    Text(loc.displayName)
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(.white)
                                        .lineLimit(1)
                                    Spacer()
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 4)
                                .background(Color.white.opacity(0.04))
                                .cornerRadius(4)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: embedsInIsland ? 54 : 100)
            } else if let error = viewModel.searchError {
                // A failed lookup is not an empty result. Saying "no cities found" here would blame the
                // query for a network, quota or backend failure the person can actually fix.
                searchFailureRow(error)
            } else if viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 {
                Text(L10n.t("Không tìm thấy thành phố"))
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.vertical, 6)
            }
        }
        .onAppear {
            isSearchFieldFocused = true
        }
        .onExitCommand {
            viewModel.closeSearch()
        }
    }

    /// One row for a failed city search: the group, plus Retry that re-runs the same query.
    private func searchFailureRow(_ error: WeatherError) -> some View {
        let presentation = WeatherErrorPresentation(for: error, context: .search)
        return HStack(spacing: 5) {
            Image(systemName: presentation.symbol)
                .font(.system(size: 10))
                .foregroundStyle(presentation.canRetry ? Color.orange : Color.red)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(L10n.t(presentation.titleKey))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(2)

                if let hintKey = presentation.hintKey {
                    Text(L10n.t(hintKey))
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 2)

            if presentation.canRetry {
                Button(L10n.t("Thử lại")) {
                    // No debounce: this is an explicit press, not typing.
                    viewModel.retrySearch()
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Attribution Footer

    private var attributionFooter: some View {
        HStack(spacing: 4) {
            Spacer()
            switch viewModel.state {
            case .loaded(let snapshot, _), .refreshing(let snapshot), .offlineWithStale(let snapshot, _),
                 .failedWithStale(let snapshot, _, _):
                // Attribution must stay while cached data is shown, even after a failed refresh.
                attributionLink(attribution: snapshot.attribution)
            default:
                EmptyView()
            }
        }
    }

    private func attributionLink(attribution: WeatherAttribution) -> some View {
        HStack(spacing: 3) {
            Text(L10n.t("Dữ liệu thời tiết bởi "))
                .font(.system(size: 8.5))
                .foregroundStyle(.white.opacity(0.4))
            if let url = attribution.legalURL {
                Link(attribution.serviceName, destination: url)
                    .font(.system(size: 8.5, weight: .medium))
                    .foregroundStyle(.blue.opacity(0.8))
            } else {
                Text(attribution.serviceName)
                    .font(.system(size: 8.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
    }
}

// MARK: - Previews

#Preview("Loaded 12-Hour Forecast") {
    let loc = WeatherLocation(
        id: "loc-preview",
        name: "Hà Nội",
        region: "Hà Nội",
        country: "Việt Nam",
        latitude: 21.0285,
        longitude: 105.8542,
        timeZoneIdentifier: "Asia/Bangkok"
    )
    let attribution = WeatherAttribution(
        providerId: "mock-preview",
        serviceName: "Open-Meteo",
        legalURL: URL(string: "https://open-meteo.com/"),
        markSymbol: "cloud.sun.fill"
    )
    var hourly: [HourlyForecast] = []
    let now = Date()
    for i in 0..<12 {
        hourly.append(
            HourlyForecast(
                date: now.addingTimeInterval(TimeInterval(i * 3600)),
                temperatureCelsius: 26.0 + Double(i % 4),
                precipitationProbability: (i % 3 == 0) ? 35.0 : nil,
                condition: (i % 2 == 0) ? .partlyCloudy : .rain
            )
        )
    }
    let snapshot = WeatherSnapshot(
        location: loc,
        fetchedAt: now,
        attribution: attribution,
        hourly: hourly
    )

    let mockProvider = MockWeatherProvider(stubbedSnapshots: [loc.id: snapshot])
    let coordinator = WeatherCoordinator(provider: mockProvider)
    let vm = WeatherViewModel(coordinator: coordinator)
    vm.selectLocation(loc)

    return NotchWeatherPage(viewModel: vm)
        .frame(width: 480)
        .padding()
        .background(Color.black)
}

#Preview("Search Cities") {
    let mockProvider = MockWeatherProvider(stubbedLocations: [
        WeatherLocation(id: "1", name: "Đà Nẵng", region: "Đà Nẵng", country: "Việt Nam", latitude: 16.0, longitude: 108.0, timeZoneIdentifier: "Asia/Ho_Chi_Minh"),
        WeatherLocation(id: "2", name: "Hồ Chí Minh", region: "Thành phố Hồ Chí Minh", country: "Việt Nam", latitude: 10.8, longitude: 106.6, timeZoneIdentifier: "Asia/Ho_Chi_Minh")
    ])
    let coordinator = WeatherCoordinator(provider: mockProvider)
    let vm = WeatherViewModel(coordinator: coordinator)
    vm.isShowingSearch = true
    vm.searchText = "Đà"
    vm.onSearchTextChanged("Đà")

    return NotchWeatherPage(viewModel: vm)
        .frame(width: 480)
        .padding()
        .background(Color.black)
}

#Preview("Offline with Stale Cache") {
    let loc = WeatherLocation(
        id: "loc-offline",
        name: "Paris",
        region: "Île-de-France",
        country: "Pháp",
        latitude: 48.85,
        longitude: 2.35,
        timeZoneIdentifier: "Europe/Paris"
    )
    let attribution = WeatherAttribution(
        providerId: "mock-provider",
        serviceName: "Open-Meteo",
        legalURL: URL(string: "https://open-meteo.com/")
    )
    let snapshot = WeatherSnapshot(
        location: loc,
        fetchedAt: Date().addingTimeInterval(-3600), // 1 hour ago
        attribution: attribution,
        hourly: [
            HourlyForecast(date: Date(), temperatureCelsius: 18, condition: .cloudy),
            HourlyForecast(date: Date().addingTimeInterval(3600), temperatureCelsius: 19, condition: .rain)
        ]
    )
    let mockProvider = MockWeatherProvider(errorToThrow: .networkUnavailable)
    let cache = WeatherCacheStore()
    cache.set(snapshot: snapshot)
    let coordinator = WeatherCoordinator(provider: mockProvider, cache: cache)
    let vm = WeatherViewModel(coordinator: coordinator)
    vm.selectLocation(loc)

    return NotchWeatherPage(viewModel: vm)
        .frame(width: 480)
        .padding()
        .background(Color.black)
}
