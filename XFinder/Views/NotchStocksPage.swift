import SwiftUI
import AppKit

/// The watchlist is usable independently of the optional market-data adapter.
struct NotchStocksSetupPage: View {
    private let assets = UserDefaultsStocksWatchlistStore().loadWatchlist()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(L10n.t("Chưa cấu hình nguồn giá chứng khoán"), systemImage: "chart.line.uptrend.xyaxis")
                .font(.system(size: 12, weight: .semibold))
            if !assets.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(assets) { asset in
                            Text(asset.shortTicker)
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background(.white.opacity(0.10), in: Capsule())
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
            HStack {
                Button(L10n.t("Quản lý danh sách theo dõi")) {
                    NotchSurfaceController.shared.openInlineNotchSettings(showStocks: true)
                }
                .buttonStyle(NotchPillButtonStyle(primary: true))
                if let stocks = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.stocks") {
                    Button(L10n.t("Mở Apple Stocks")) { NSWorkspace.shared.open(stocks) }
                        .buttonStyle(NotchPillButtonStyle(primary: false))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

/// Compact watchlist with one price chart per symbol and expandable details.
public struct NotchStocksPage: View {
    @ObservedObject public var viewModel: StocksViewModel
    public var embedsInIsland: Bool
    @FocusState private var isSearchFieldFocused: Bool
    @State private var expandedAssetID: String?

    public init(viewModel: StocksViewModel, embedsInIsland: Bool = true) {
        self.viewModel = viewModel
        self.embedsInIsland = embedsInIsland
    }

    public var body: some View {
        GeometryReader { geo in
            let isNarrow = geo.size.width < 460
            VStack(alignment: .leading, spacing: isNarrow ? 5 : 6) {
                headerBar(isNarrow: isNarrow)
                if viewModel.isShowingSearch {
                    searchOverlay
                } else {
                    contentBody(isNarrow: isNarrow)
                }
                HStack {
                    Text("\(viewModel.coordinator.attribution.serviceName) · \(L10n.t(viewModel.coordinator.attribution.noticeKey))")
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if let openSettings = viewModel.onOpenSettingsRequested {
                        Button(action: openSettings) {
                            Image(systemName: "gearshape")
                        }
                        .buttonStyle(.plain)
                        .help(L10n.t("Cài đặt nguồn giá"))
                        .accessibilityLabel(L10n.t("Cài đặt nguồn giá"))
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .onAppear {
            if !embedsInIsland { viewModel.onAppear() }
        }
        .onDisappear {
            if !embedsInIsland { viewModel.close() }
        }
    }

    // MARK: - Header

    private func headerBar(isNarrow: Bool) -> some View {
        HStack(spacing: 6) {
            if !viewModel.isShowingSearch {
                Button { viewModel.openSearch() } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "magnifyingglass")
                        Text(L10n.t("Tìm mã (AAPL, NVDA, BTC/USD)"))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Image(systemName: "plus.circle")
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: XFinderTokens.Radius.control))
                }
                .buttonStyle(.plain)
            } else {
                Spacer(minLength: 0)
            }

            if case .ready(_, _, let bannerErr, _) = viewModel.state, let bannerErr {
                let pres = StocksErrorPresentation(for: bannerErr, isDemoAccess: viewModel.coordinator.isDemoAccess)
                Label(L10n.t(pres.titleKey), systemImage: pres.symbolName)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            } else if !isNarrow, let quote = viewModel.selectedQuote ?? viewModel.watchlist.lazy
                .compactMap({ viewModel.rowState(for: $0.id)?.quote }).first {
                Text(quoteDate(quote))
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.60))
                    .lineLimit(1)
            }

            if viewModel.isShowingSearch {
                Button { viewModel.closeSearch() } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .help(L10n.t("Đóng tìm mã"))
                .accessibilityLabel(L10n.t("Đóng tìm mã"))
            }

            Button {
                viewModel.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.white.opacity(viewModel.isRefreshing ? 0.35 : 0.85))
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isRefreshing)
            .help(L10n.t("Làm mới"))
            .accessibilityLabel(L10n.t("Làm mới"))
        }
    }

    // MARK: - Content Routing

    @ViewBuilder
    private func contentBody(isNarrow: Bool) -> some View {
        switch viewModel.state {
        case .unconfigured:
            VStack(spacing: 7) {
                Text(L10n.t("Chưa chọn nguồn giá hoặc mã theo dõi"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.80))
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Button(L10n.t("Thêm mã")) { viewModel.openSearch() }
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

        case .empty:
            VStack(spacing: 7) {
                Text(L10n.t("Danh sách theo dõi chưa có mã nào"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(1)
                Button(L10n.t("Thêm mã")) { viewModel.openSearch() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

        case .loadingInitial(let wl):
            let loadingRows = Dictionary(uniqueKeysWithValues: wl.map { ($0.id, StocksRowState.loading) })
            readyBody(rows: loadingRows, isNarrow: isNarrow)

        case .offlineNoData(let err), .failedNoData(let err):
            let pres = StocksErrorPresentation(for: err, context: .quote, isDemoAccess: viewModel.coordinator.isDemoAccess)
            VStack(spacing: 5) {
                Image(systemName: pres.symbolName)
                    .font(.system(size: 16))
                    .foregroundStyle(.orange)
                Text(L10n.t(pres.titleKey))
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let hint = pres.hintKey {
                    Text(L10n.t(hint))
                        .font(.system(size: 9.5))
                        .foregroundStyle(.white.opacity(0.65))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 6) {
                    if pres.canRetry {
                        Button(L10n.t("Thử lại")) { viewModel.refresh() }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                    }
                    if case .accessRequired = err, let openSettings = viewModel.onOpenSettingsRequested {
                        Button(L10n.t("Thêm khóa API trong Cài đặt"), action: openSettings)
                            .buttonStyle(NotchPillButtonStyle(primary: !pres.canRetry))
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

        case .ready(let rows, _, _, _):
            readyBody(rows: rows, isNarrow: isNarrow)
        }
    }

    private func readyBody(rows: [String: StocksRowState], isNarrow: Bool) -> some View {
        ScrollView {
            VStack(spacing: 3) {
                ForEach(viewModel.watchlist) { asset in
                    let row = rows[asset.id] ?? .loading
                    watchlistRow(asset: asset, row: row, isNarrow: isNarrow)
                    if expandedAssetID == asset.id {
                        detailPanel(asset: asset, rowState: row, compact: isNarrow)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func watchlistRow(asset: StockAssetDescriptor, row: StocksRowState, isNarrow: Bool) -> some View {
        let quote = row.quote
        let delta = quote?.changeAmount
        let tint: Color = delta.map { $0 == 0 ? .secondary : ($0 > 0 ? .green : .red) } ?? .secondary
        let points = quote?.series(for: .oneWeek) ?? []
        let expanded = expandedAssetID == asset.id

        return HStack(spacing: 7) {
            Button {
                viewModel.selectedAssetId = asset.id
                expandedAssetID = expanded ? nil : asset.id
            } label: {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(asset.shortTicker).font(.system(size: 11, weight: .semibold, design: .monospaced))
                        Text(asset.displayName).font(.caption2).foregroundStyle(.secondary)
                    }
                    .lineLimit(1)
                    .frame(width: isNarrow ? 78 : 112, alignment: .leading)

                    if points.count >= 2 {
                        StockSparklineView(points: points.map(\.price), tint: tint)
                            .frame(height: 19)
                            .accessibilityHidden(true)
                    } else {
                        Spacer(minLength: 4)
                    }
                    Spacer(minLength: 2)
                    VStack(alignment: .trailing, spacing: 1) {
                        if let quote {
                            Text(quote.formattedPrice())
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            if let percent = quote.formattedChangePercent() {
                                Text(percent)
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(tint)
                            }
                            if row.error != nil {
                                Text(L10n.t("Giá đã lưu")).font(.caption2).foregroundStyle(.orange)
                            }
                        } else if let error = row.error {
                            let pres = StocksErrorPresentation(for: error, isDemoAccess: viewModel.coordinator.isDemoAccess)
                            Text(L10n.t(pres.titleKey))
                                .font(.caption2).foregroundStyle(.orange)
                        } else {
                            Text(L10n.t("Đang tải...")).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .lineLimit(1)
                }
                .frame(maxWidth: .infinity, minHeight: 30)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(rowAccessibilityLabel(asset: asset, rowState: row))
            .help(rowHelpText(asset: asset, row: row))

            if case .accessRequired = row.error, let openSettings = viewModel.onOpenSettingsRequested {
                Button(action: openSettings) {
                    Image(systemName: "key.fill")
                        .font(.system(size: 10))
                        .frame(width: 20, height: 22)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.orange)
                .help(L10n.t("Thêm khóa API trong Cài đặt"))
                .accessibilityLabel(L10n.t("Thêm khóa API trong Cài đặt") + " · " + asset.shortTicker)
            }

            if row.error != nil, let url = asset.publicQuoteURL {
                Link(destination: url) {
                    Image(systemName: "arrow.up.right.square")
                        .frame(width: 20, height: 22)
                }
                .foregroundStyle(.secondary)
                .help(L10n.t("Xem trên Yahoo Finance"))
                .accessibilityLabel(L10n.t("Xem trên Yahoo Finance") + " · " + asset.shortTicker)
            }

            Button {
                if expanded { expandedAssetID = nil }
                viewModel.removeAsset(id: asset.id)
            } label: {
                Image(systemName: "minus.circle")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 22)
            }
            .buttonStyle(.plain)
            .help(L10n.t("Xóa mã"))
            .accessibilityLabel(L10n.t("Xóa mã"))
        }
        .padding(.horizontal, 6)
        .background(.white.opacity(expanded ? 0.10 : 0.045), in: RoundedRectangle(cornerRadius: XFinderTokens.Radius.control))
    }

    // MARK: - Detail Chart Panel

    private func detailPanel(asset: StockAssetDescriptor, rowState: StocksRowState, compact: Bool) -> some View {
        let quote = rowState.quote
        let deltaPct = quote?.formattedChangePercent()
        let deltaAmt = quote?.formattedChangeAmount()
        let isPositive = (quote?.changeAmount ?? 0) >= 0
        let tint: Color = isPositive ? .green : .red
        let points = quote?.series(for: viewModel.selectedRange) ?? []

        return VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(asset.displayName)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(asset.providerCode)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.55))
                            .lineLimit(1)
                    }
                    if let quote {
                        Text("\(viewModel.sessionBadgeText(for: quote)) · \(viewModel.changeBasisText(for: quote))")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.white.opacity(0.6))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                if let quote {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(quote.formattedPrice())
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white)
                            .monospacedDigit()
                            .lineLimit(1)
                        if let deltaPct {
                            Text("\(deltaAmt ?? "") (\(deltaPct))")
                                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                                .foregroundStyle(tint)
                                .monospacedDigit()
                                .lineLimit(1)
                        } else {
                            Text("—")
                                .font(.system(size: 9.5, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.45))
                        }
                    }
                }
            }

            if quote != nil && !viewModel.availableRanges.isEmpty {
                HStack(spacing: 4) {
                    ForEach(viewModel.availableRanges) { r in
                        let active = viewModel.selectedRange == r
                        Button { viewModel.selectedRange = r } label: {
                            Text(r.rawValue)
                                .font(.system(size: 9, weight: active ? .bold : .medium, design: .monospaced))
                                .foregroundStyle(active ? .black : .white.opacity(0.75))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.white.opacity(active ? 0.92 : 0.08)))
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
            }

            if let err = rowState.error {
                let pres = StocksErrorPresentation(for: err, context: .quote, isDemoAccess: viewModel.coordinator.isDemoAccess)
                Label(L10n.t(pres.titleKey), systemImage: pres.symbolName)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.orange)
                    .lineLimit(1)
                if let hint = pres.hintKey {
                    Text(L10n.t(hint))
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.70))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if case .accessRequired = err, let openSettings = viewModel.onOpenSettingsRequested {
                    Button(L10n.t("Thêm khóa API trong Cài đặt"), action: openSettings)
                        .buttonStyle(NotchPillButtonStyle(primary: false))
                }
            } else if points.count >= 2 {
                StockSparklineView(points: points.map(\.price), tint: tint)
                    .frame(height: compact ? 36 : 46)
            } else {
                Text(L10n.t("Chưa có dữ liệu biểu đồ cho kỳ này"))
                    .font(.system(size: 9.5))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, minHeight: compact ? 30 : 40, alignment: .center)
            }

            let sourceLabel = quote.map { viewModel.sourceDisplayName(for: $0) } ?? viewModel.coordinator.attribution.serviceName
            Text("\(sourceLabel) · \(L10n.t(viewModel.coordinator.attribution.noticeKey))")
                .font(.system(size: 8.5))
                .foregroundStyle(.white.opacity(0.45))
                .lineLimit(1)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: XFinderTokens.Radius.control, style: .continuous)
                .fill(Color.white.opacity(0.055))
        )
        .overlay(
            RoundedRectangle(cornerRadius: XFinderTokens.Radius.control, style: .continuous)
                .strokeBorder(Color.white.opacity(0.09), lineWidth: 0.6)
        )
    }

    private func quoteDate(_ quote: StockQuote) -> String {
        quote.quotedAt.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, timeZone: quote.asset.timeZone))
    }

    private func rowHelpText(asset: StockAssetDescriptor, row: StocksRowState) -> String {
        if let quote = row.quote { return quoteDate(quote) }
        if let error = row.error {
            let pres = StocksErrorPresentation(for: error, isDemoAccess: viewModel.coordinator.isDemoAccess)
            if let hint = pres.hintKey { return L10n.t(hint) }
            return L10n.t(pres.titleKey)
        }
        return asset.displayName
    }

    // MARK: - Search Overlay

    private var searchOverlay: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.55))
                TextField(L10n.t("Tìm mã Mỹ (S&P 500, AAPL, NVDA, ETF)..."), text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.white)
                    .focused($isSearchFieldFocused)
                    .onChange(of: viewModel.searchText) { _, newValue in
                        viewModel.onSearchTextChanged(newValue)
                    }
                    .onAppear { isSearchFieldFocused = true }
                if !viewModel.searchText.isEmpty {
                    Button { viewModel.onSearchTextChanged("") } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: XFinderTokens.Radius.control).fill(Color.white.opacity(0.10)))

            if viewModel.isSearching {
                ProgressView().controlSize(.small)
                    .frame(maxWidth: .infinity, minHeight: 50)
            } else if let searchErr = viewModel.searchError {
                let pres = StocksErrorPresentation(for: searchErr, context: .search)
                HStack(spacing: 6) {
                    Label(L10n.t(pres.titleKey), systemImage: pres.symbolName)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.orange)
                    Spacer()
                    if pres.canRetry {
                        Button(L10n.t("Thử lại")) { viewModel.onSearchTextChanged(viewModel.searchText) }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                    }
                }
                .padding(.top, 8)
            } else if viewModel.searchResults.isEmpty {
                let trimmed = viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                Text(trimmed.isEmpty ? L10n.t("Nhập mã cổ phiếu hoặc chỉ số để thêm") : L10n.t("Không tìm thấy mã phù hợp"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(maxWidth: .infinity, minHeight: 50)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 3) {
                        ForEach(viewModel.searchResults) { hit in
                            Button {
                                viewModel.addAsset(hit)
                            } label: {
                                HStack(spacing: 6) {
                                    Text(hit.displayName)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .lineLimit(1)
                                    Text(L10n.t(hit.kind.badgeKey))
                                        .font(.system(size: 8.5, weight: .bold))
                                        .foregroundStyle(.cyan)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(RoundedRectangle(cornerRadius: XFinderTokens.Radius.badge).fill(Color.cyan.opacity(0.16)))
                                    Spacer()
                                    Text("\(hit.shortTicker) · \(hit.exchange)")
                                        .font(.system(size: 9.5, design: .monospaced))
                                        .foregroundStyle(.white.opacity(0.6))
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(RoundedRectangle(cornerRadius: XFinderTokens.Radius.badge).fill(Color.white.opacity(0.06)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func rowAccessibilityLabel(asset: StockAssetDescriptor, rowState: StocksRowState) -> String {
        let kindLabel = L10n.t(asset.kind.badgeKey)
        switch rowState {
        case .loading:
            return "\(asset.displayName), \(kindLabel), \(asset.exchange), \(L10n.t("Đang tải..."))"
        case .loaded(let q):
            let delta = q.formattedChangePercent() ?? L10n.t("Chưa có biến động")
            return "\(asset.displayName), \(kindLabel), \(asset.exchange), \(q.formattedPrice()), \(delta), \(viewModel.sessionBadgeText(for: q))"
        case .failed(let err, let cached):
            let pres = StocksErrorPresentation(for: err, context: .quote, isDemoAccess: viewModel.coordinator.isDemoAccess)
            if let cached {
                return "\(asset.displayName), \(cached.formattedPrice()), \(L10n.t(pres.titleKey))"
            }
            return "\(asset.displayName), \(L10n.t(pres.titleKey))"
        }
    }
}

private struct StockSparklineView: View {
    let points: [Double]
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            let w = max(1, geo.size.width)
            let h = max(1, geo.size.height)
            let minVal = points.min() ?? 0
            let maxVal = points.max() ?? 1
            let span = max(0.0001, maxVal - minVal)
            let step = points.count > 1 ? w / CGFloat(points.count - 1) : w

            Path { path in
                for (idx, val) in points.enumerated() {
                    let x = CGFloat(idx) * step
                    let norm = CGFloat((val - minVal) / span)
                    let y = h - (norm * (h - 4) + 2)
                    if idx == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            .stroke(tint, style: StrokeStyle(lineWidth: 1.75, lineCap: .round, lineJoin: .round))
        }
    }
}
