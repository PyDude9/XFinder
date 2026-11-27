import SwiftUI

/// Dynamic Island Website Analytics dashboard supporting independent DataFast and Google Analytics 4
/// read-only sources. Separate from `Core/Diagnostics/AnalyticsCenter.swift` (product telemetry).
/// Never displays demo/sample fixtures in production UI and never combines metrics across providers.
public struct NotchWebsiteAnalyticsPage: View {
    @ObservedObject public var viewModel: WebsiteAnalyticsViewModel
    public var embedsInIsland: Bool
    private let onConfigurationOpened: () -> Void
    @State private var selectedBreakdownTab: BreakdownTab = .pages

    private enum BreakdownTab: String, CaseIterable, Identifiable {
        case pages
        case referrers
        var id: String { rawValue }
    }

    public init(
        viewModel: WebsiteAnalyticsViewModel,
        embedsInIsland: Bool = true,
        onConfigurationOpened: @escaping () -> Void = {}
    ) {
        self.viewModel = viewModel
        self.embedsInIsland = embedsInIsland
        self.onConfigurationOpened = onConfigurationOpened
    }

    public var body: some View {
        GeometryReader { geo in
            let isNarrow = geo.size.width < 460
            VStack(alignment: .leading, spacing: isNarrow ? 5 : 6) {
                headerBar(isNarrow: isNarrow)
                Divider().overlay(Color.white.opacity(0.10))
                if viewModel.isShowingConfiguration {
                    configurationPanel
                } else {
                    contentBody(isNarrow: isNarrow)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .onAppear {
            if !embedsInIsland { viewModel.onAppear() }
        }
        .onDisappear {
            if !embedsInIsland { viewModel.close() }
        }
        .onChange(of: viewModel.isShowingConfiguration) { _, isOpen in
            if isOpen { onConfigurationOpened() }
        }
    }

    // MARK: - Header

    private func headerBar(isNarrow: Bool) -> some View {
        HStack(spacing: isNarrow ? 4 : 6) {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.cyan)

            if !isNarrow && !embedsInIsland {
                Text(L10n.t("Phân tích web"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }

            providerSelector(isNarrow: isNarrow)

            realtimePill(isNarrow: isNarrow)

            Spacer(minLength: 2)

            rangeSelector(isNarrow: isNarrow)

            Button {
                if viewModel.isShowingConfiguration {
                    viewModel.closeConfiguration()
                } else {
                    viewModel.openConfiguration()
                }
            } label: {
                Image(systemName: viewModel.isShowingConfiguration ? "xmark.circle.fill" : "key.horizontal")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.82))
            }
            .buttonStyle(.plain)
            .help(L10n.t("Cấu hình nguồn phân tích"))
            .accessibilityLabel(L10n.t("Cấu hình nguồn phân tích"))

            Button {
                viewModel.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(viewModel.isRefreshing ? 0.35 : 0.85))
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isRefreshing)
            .help(L10n.t("Làm mới"))
            .accessibilityLabel(L10n.t("Làm mới"))
        }
    }

    private func providerSelector(isNarrow: Bool) -> some View {
        HStack(spacing: 2) {
            ForEach(WebsiteAnalyticsProviderKind.allCases) { kind in
                let selected = viewModel.selectedProvider == kind
                Button {
                    viewModel.selectProvider(kind)
                } label: {
                    Text(isNarrow ? kind.shortName : kind.displayName)
                        .font(.system(size: isNarrow ? 9 : 9.5, weight: selected ? .bold : .medium))
                        .foregroundStyle(selected ? .black : .white.opacity(0.76))
                        .padding(.horizontal, isNarrow ? 5 : 6.5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.white.opacity(selected ? 0.92 : 0.0)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Capsule().fill(Color.white.opacity(0.09)))
    }

    private func rangeSelector(isNarrow: Bool) -> some View {
        HStack(spacing: 2) {
            ForEach(WebsiteAnalyticsRange.allCases) { range in
                let selected = viewModel.selectedRange == range
                Button {
                    viewModel.selectRange(range)
                } label: {
                    Text(range.shortLabel)
                        .font(.system(size: isNarrow ? 8.5 : 9, weight: selected ? .bold : .medium, design: .monospaced))
                        .foregroundStyle(selected ? .black : .white.opacity(0.75))
                        .padding(.horizontal, isNarrow ? 4.5 : 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.white.opacity(selected ? 0.92 : 0.0)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Capsule().fill(Color.white.opacity(0.09)))
    }

    @ViewBuilder
    private func realtimePill(isNarrow: Bool) -> some View {
        if let report = viewModel.activeReport, report.realtime.isSupported, let live = report.realtime.activeVisitors {
            HStack(spacing: 3.5) {
                Circle()
                    .fill(live > 0 ? Color.green : Color.white.opacity(0.4))
                    .frame(width: 5.5, height: 5.5)
                Text("\(live)")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.92))
                    .monospacedDigit()
                if !isNarrow {
                    Text(L10n.t("trực tuyến"))
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.65))
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.green.opacity(live > 0 ? 0.16 : 0.07)))
            .accessibilityLabel("\(live) \(L10n.t("trực tuyến"))")
        }
    }

    // MARK: - Main Content

    @ViewBuilder
    private func contentBody(isNarrow: Bool) -> some View {
        switch viewModel.activeState {
        case .unconfigured(let reason):
            unconfiguredView(reason: reason)
        case .loadingInitial:
            VStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text(L10n.t("Đang tải số liệu phân tích trang web..."))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        case .empty(let report, _):
            VStack(spacing: 6) {
                Image(systemName: "chart.bar.doc.horizontal")
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.45))
                Text(L10n.t("Không có dữ liệu trong kỳ đã chọn"))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                Text("\(report.siteLabel) · \(report.windowStartDateKey) → \(report.windowEndDateKey)")
                    .font(.system(size: 8.5, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.48))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        case .loaded(let report, _):
            dashboardBody(report: report, staleError: nil, isNarrow: isNarrow)
        case .failedWithCache(let report, let error):
            dashboardBody(report: report, staleError: error, isNarrow: isNarrow)
        case .failedNoCache(let error):
            errorOnlyView(error: error)
        }
    }

    @ViewBuilder
    private func dashboardBody(
        report: WebsiteAnalyticsReport,
        staleError: WebsiteAnalyticsError?,
        isNarrow: Bool
    ) -> some View {
        if isNarrow {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 6) {
                    if let staleError {
                        staleBanner(error: staleError, report: report)
                    }
                    kpiGridNarrow(report.kpis)
                    chartCard(report: report, compact: true)
                    breakdownCard(
                        title: L10n.t("Trang hàng đầu"),
                        items: Array(report.topPages.prefix(WebsiteAnalyticsLimits.maxTopDisplayRows))
                    )
                    breakdownCard(
                        title: L10n.t("Nguồn giới thiệu"),
                        items: Array(report.topReferrers.prefix(WebsiteAnalyticsLimits.maxTopDisplayRows))
                    )
                    footerLine(report: report)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 5) {
                if let staleError {
                    staleBanner(error: staleError, report: report)
                }
                kpiRowWide(report.kpis)
                HStack(alignment: .top, spacing: 8) {
                    chartCard(report: report, compact: false)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    tabbedBreakdownCard(report: report)
                        .frame(width: 224, alignment: .topLeading)
                }
                footerLine(report: report)
            }
        }
    }

    // MARK: - KPI Cards

    private func kpiRowWide(_ kpis: WebsiteAnalyticsKPIs) -> some View {
        HStack(spacing: 6) {
            kpiTile(title: L10n.t("Khách truy cập"), value: WebsiteAnalyticsFormatting.formatCount(kpis.visitors), tint: .cyan)
            kpiTile(title: L10n.t("Lượt xem"), value: WebsiteAnalyticsFormatting.formatCount(kpis.pageviews), tint: .mint)
            kpiTile(title: L10n.t("Tỷ lệ thoát"), value: WebsiteAnalyticsFormatting.formatBounceRate(kpis.bounceRatePercent), tint: .orange)
            kpiTile(title: L10n.t("Thời lượng TB"), value: WebsiteAnalyticsFormatting.formatDuration(seconds: kpis.averageSessionDurationSeconds), tint: .indigo)
        }
    }

    private func kpiGridNarrow(_ kpis: WebsiteAnalyticsKPIs) -> some View {
        VStack(spacing: 5) {
            HStack(spacing: 5) {
                kpiTile(title: L10n.t("Khách truy cập"), value: WebsiteAnalyticsFormatting.formatCount(kpis.visitors), tint: .cyan)
                kpiTile(title: L10n.t("Lượt xem"), value: WebsiteAnalyticsFormatting.formatCount(kpis.pageviews), tint: .mint)
            }
            HStack(spacing: 5) {
                kpiTile(title: L10n.t("Tỷ lệ thoát"), value: WebsiteAnalyticsFormatting.formatBounceRate(kpis.bounceRatePercent), tint: .orange)
                kpiTile(title: L10n.t("Thời lượng TB"), value: WebsiteAnalyticsFormatting.formatDuration(seconds: kpis.averageSessionDurationSeconds), tint: .indigo)
            }
        }
    }

    private func kpiTile(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 8.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.58))
                .lineLimit(1)
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(value == WebsiteAnalyticsFormatting.unavailablePlaceholder ? .white.opacity(0.45) : .white)
                .monospacedDigit()
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: XFinderTokens.Radius.control, style: .continuous)
                .fill(Color.white.opacity(0.055))
        )
        .overlay(
            RoundedRectangle(cornerRadius: XFinderTokens.Radius.control, style: .continuous)
                .strokeBorder(tint.opacity(0.22), lineWidth: 0.6)
        )
    }

    // MARK: - Chart & Breakdowns

    private func chartCard(report: WebsiteAnalyticsReport, compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Text(report.siteLabel)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("\(report.windowStartDateKey) → \(report.windowEndDateKey)")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
            }

            if report.timeseries.isEmpty {
                Text(L10n.t("Chưa có dữ liệu biểu đồ"))
                    .font(.system(size: 9.5))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, minHeight: compact ? 42 : 64, alignment: .center)
            } else {
                WebsiteAnalyticsBarsView(
                    points: report.timeseries,
                    tint: report.provider == .dataFast ? .cyan : .orange
                )
                .frame(height: compact ? 44 : 66)
            }
        }
        .padding(7)
        .background(
            RoundedRectangle(cornerRadius: XFinderTokens.Radius.control, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: XFinderTokens.Radius.control, style: .continuous)
                .strokeBorder(Color.white.opacity(0.09), lineWidth: 0.6)
        )
    }

    private func tabbedBreakdownCard(report: WebsiteAnalyticsReport) -> some View {
        let items = selectedBreakdownTab == .pages
            ? Array(report.topPages.prefix(WebsiteAnalyticsLimits.maxTopDisplayRows))
            : Array(report.topReferrers.prefix(WebsiteAnalyticsLimits.maxTopDisplayRows))

        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                breakdownTabButton(.pages, title: L10n.t("Trang hàng đầu"))
                breakdownTabButton(.referrers, title: L10n.t("Nguồn giới thiệu"))
                Spacer(minLength: 0)
            }
            breakdownList(items: items)
        }
        .padding(7)
        .background(
            RoundedRectangle(cornerRadius: XFinderTokens.Radius.control, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: XFinderTokens.Radius.control, style: .continuous)
                .strokeBorder(Color.white.opacity(0.09), lineWidth: 0.6)
        )
    }

    private func breakdownTabButton(_ tab: BreakdownTab, title: String) -> some View {
        let selected = selectedBreakdownTab == tab
        return Button {
            selectedBreakdownTab = tab
        } label: {
            Text(title)
                .font(.system(size: 8.5, weight: selected ? .bold : .medium))
                .foregroundStyle(selected ? .black : .white.opacity(0.72))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.white.opacity(selected ? 0.90 : 0.08)))
        }
        .buttonStyle(.plain)
    }

    private func breakdownCard(title: String, items: [WebsiteAnalyticsBreakdownItem]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
            breakdownList(items: items)
        }
        .padding(7)
        .background(
            RoundedRectangle(cornerRadius: XFinderTokens.Radius.control, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: XFinderTokens.Radius.control, style: .continuous)
                .strokeBorder(Color.white.opacity(0.09), lineWidth: 0.6)
        )
    }

    @ViewBuilder
    private func breakdownList(items: [WebsiteAnalyticsBreakdownItem]) -> some View {
        if items.isEmpty {
            Text(L10n.t("Chưa có mục nào"))
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.45))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
        } else {
            VStack(alignment: .leading, spacing: 2.5) {
                ForEach(items) { item in
                    HStack(spacing: 6) {
                        Text(item.name)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.86))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 4)
                        Text(WebsiteAnalyticsFormatting.formatCount(item.visitors ?? item.pageviews))
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.cyan.opacity(0.9))
                            .monospacedDigit()
                    }
                }
            }
        }
    }

    // MARK: - Banners, Unconfigured & Errors

    private func staleBanner(error: WebsiteAnalyticsError, report: WebsiteAnalyticsReport) -> some View {
        let pres = WebsiteAnalyticsErrorPresentation(for: error)
        return HStack(spacing: 5) {
            Image(systemName: pres.symbolName)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(.orange)
            Text(L10n.t(pres.titleKey))
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.88))
                .lineLimit(1)
            Spacer(minLength: 4)
            if pres.requiresReconnect {
                Button(L10n.t("Kết nối lại")) { viewModel.openConfiguration() }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
            } else if pres.canRetry {
                Button(L10n.t("Thử lại")) { viewModel.refresh() }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3.5)
        .background(RoundedRectangle(cornerRadius: XFinderTokens.Radius.badge).fill(Color.orange.opacity(0.14)))
    }

    private func unconfiguredView(reason: WebsiteAnalyticsUnconfiguredReason) -> some View {
        let pres = WebsiteAnalyticsErrorPresentation(for: .unconfigured(reason))
        return VStack(spacing: 6) {
            Image(systemName: pres.symbolName)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.cyan.opacity(0.85))
            Text(L10n.t(pres.titleKey))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
            Text(L10n.t(pres.hintKey))
                .font(.system(size: 9.5))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .lineLimit(2)
            HStack(spacing: 8) {
                Button(L10n.t("Cấu hình nguồn phân tích")) {
                    viewModel.openConfiguration()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                if let onSettings = viewModel.onOpenSettingsRequested {
                    Button(L10n.t("Cài đặt")) { onSettings() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.horizontal, 12)
    }

    private func errorOnlyView(error: WebsiteAnalyticsError) -> some View {
        let pres = WebsiteAnalyticsErrorPresentation(for: error)
        return VStack(spacing: 6) {
            Image(systemName: pres.symbolName)
                .font(.system(size: 16))
                .foregroundStyle(.orange)
            Text(L10n.t(pres.titleKey))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
            Text(L10n.t(pres.hintKey))
                .font(.system(size: 9.5))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .lineLimit(2)
            HStack(spacing: 8) {
                if pres.requiresReconnect {
                    Button(L10n.t("Kết nối lại")) { viewModel.openConfiguration() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
                if pres.canRetry {
                    Button(L10n.t("Thử lại")) { viewModel.refresh() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.horizontal, 12)
    }

    // MARK: - Inline Configuration Panel

    private var configurationPanel: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 6) {
                WebsiteAnalyticsConnectionForm(viewModel: viewModel, provider: viewModel.selectedProvider)
                WebsiteAnalyticsConnectionError(viewModel: viewModel)
                Button(L10n.t("Đóng")) { viewModel.closeConfiguration() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            .padding(6)
        }
    }

    private func footerLine(report: WebsiteAnalyticsReport) -> some View {
        let freshness = viewModel.freshnessLabel(for: report)
        return HStack(spacing: 6) {
            Text(report.provider.displayName)
                .font(.system(size: 8.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
            Text("·")
                .foregroundStyle(.white.opacity(0.3))
            Text(report.timeZoneIdentifier)
                .font(.system(size: 8.5, design: .monospaced))
                .foregroundStyle(.white.opacity(0.45))
                .lineLimit(1)
            Spacer(minLength: 4)
            if !freshness.isEmpty {
                Text(freshness)
                    .font(.system(size: 8.5))
                    .foregroundStyle(viewModel.activeState.isStale ? .orange : .white.opacity(0.48))
                    .lineLimit(1)
            }
        }
    }
}

private struct WebsiteAnalyticsBarsView: View {
    let points: [WebsiteAnalyticsSeriesPoint]
    let tint: Color

    var body: some View {
        let maxValue = max(1, points.map(\.primaryValue).max() ?? 1)
        HStack(alignment: .bottom, spacing: 2.5) {
            ForEach(points) { point in
                let fraction = Double(max(0, point.primaryValue)) / Double(maxValue)
                VStack(spacing: 1) {
                    Spacer(minLength: 0)
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(tint.opacity(point.primaryValue > 0 ? 0.85 : 0.16))
                        .frame(height: max(2, CGFloat(fraction) * 48))
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}


struct WebsiteAnalyticsSettingsPage: View {
    @StateObject private var viewModel = NotchSurfaceController.shared.ensureWebsiteAnalyticsViewModel()
    var inline = false

    var body: some View {
        Group {
            if inline {
                settingsContents
            } else {
                ScrollView { settingsContents }
            }
        }
        .background(XFinderTokens.Settings.contentBackground)
        .onDisappear { viewModel.dataFastAPIKeyInput = "" }
    }

    private var settingsContents: some View {
            VStack(alignment: .leading, spacing: XFinderTokens.Settings.sectionGap) {
                PageHeader(title: L10n.t("Phân tích web"), subtitle: L10n.t("Quản lý nguồn số liệu truy cập trên Dynamic Island."))
                connectionSection(.dataFast)
                connectionSection(.googleAnalytics4)
                WebsiteAnalyticsConnectionError(viewModel: viewModel)
            }
            .padding(.bottom, XFinderTokens.Space.section)
            .pageWidthSafe()
    }

    private func connectionSection(_ provider: WebsiteAnalyticsProviderKind) -> some View {
        SettingsSection(title: provider.displayName) {
            WebsiteAnalyticsConnectionForm(viewModel: viewModel, provider: provider)
                .settingsRow()
        }
    }
}

private struct WebsiteAnalyticsConnectionError: View {
    @ObservedObject var viewModel: WebsiteAnalyticsViewModel

    var body: some View {
        if let error = viewModel.configError {
            Text(L10n.t(WebsiteAnalyticsErrorPresentation(for: error).titleKey))
                .font(XFinderTokens.Font.caption)
                .foregroundStyle(.orange)
        }
    }
}

private struct WebsiteAnalyticsConnectionForm: View {
    @ObservedObject var viewModel: WebsiteAnalyticsViewModel
    let provider: WebsiteAnalyticsProviderKind

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if provider == .dataFast {
                Text(L10n.t("Kết nối DataFast (chỉ đọc)"))
                    .font(XFinderTokens.Font.row)
                    .foregroundStyle(.primary)
                TextField(L10n.t("Tên trang web"), text: $viewModel.dataFastSiteLabelInput)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.regular)
                SecureField(L10n.t("Khóa API trang web DataFast (df_...)"), text: $viewModel.dataFastAPIKeyInput)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.regular)
                HStack(spacing: 6) {
                    Button(L10n.t("Lưu kết nối")) { viewModel.saveDataFastConfiguration() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                    Button(L10n.t("Ngắt kết nối")) { viewModel.disconnect(.dataFast) }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                    Spacer()
                }
            } else {
                Text(L10n.t("Kết nối Google Analytics 4 (chỉ đọc)"))
                    .font(XFinderTokens.Font.row)
                    .foregroundStyle(.primary)
                TextField(L10n.t("Mã thuộc tính GA4 (chỉ gồm số)"), text: $viewModel.ga4PropertyIdInput)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.regular)
                TextField(L10n.t("Tên trang web"), text: $viewModel.ga4PropertyLabelInput)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.regular)
                TextField(L10n.t("Mã OAuth 2.0 Client ID"), text: $viewModel.ga4OAuthClientIdInput)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.regular)
                HStack(spacing: 6) {
                    Button(L10n.t("Lưu cấu hình")) { viewModel.saveGA4Configuration() }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                    if viewModel.oauthInProgress {
                        Button(L10n.t("Hủy đăng nhập")) { viewModel.cancelGA4OAuth() }
                            .buttonStyle(.bordered)
                            .controlSize(.regular)
                    } else {
                        Button(L10n.t("Đăng nhập Google")) { viewModel.startGA4OAuth() }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.regular)
                    }
                    Button(L10n.t("Ngắt kết nối")) { viewModel.disconnect(.googleAnalytics4) }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                }
            }

        }
    }
}
