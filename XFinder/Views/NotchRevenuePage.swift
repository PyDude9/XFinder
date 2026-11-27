import SwiftUI

/// Dynamic Island App Revenue view (Stripe & Shopify kept independent unless cross-source deduplication is proven).
/// Displays Today / 7 days / 30 days per reporting currency in integer minor units, handles narrow stacked scrolling,
/// and distinguishes refunds, fees, net, payouts, permission scope limits, and empty/error states cleanly.
public struct NotchRevenuePage: View {
    @ObservedObject public var viewModel: RevenueViewModel
    public var embedsInIsland: Bool

    public init(viewModel: RevenueViewModel, embedsInIsland: Bool = true) {
        self.viewModel = viewModel
        self.embedsInIsland = embedsInIsland
    }

    public var body: some View {
        GeometryReader { geo in
            let isNarrow = geo.size.width < 460
            VStack(alignment: .leading, spacing: isNarrow ? 5 : 6) {
                headerBar(isNarrow: isNarrow)
                Divider().overlay(Color.white.opacity(0.10))
                contentBody(isNarrow: isNarrow)
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

    // MARK: - Header (Period Picker stays interactive even during initial load & empty states)

    private func headerBar(isNarrow: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "banknote.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.mint)

            Text(L10n.t("Doanh thu"))
                .font(.system(size: isNarrow ? 11.5 : 12.5, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)

            Spacer(minLength: 4)

            HStack(spacing: 2) {
                ForEach(RevenuePeriod.allCases) { p in
                    let selected = viewModel.snapshot.period == p
                    Button {
                        viewModel.selectPeriod(p)
                    } label: {
                        Text(L10n.t(p.titleKey))
                            .font(.system(size: isNarrow ? 9 : 9.5, weight: selected ? .bold : .medium))
                            .foregroundStyle(selected ? .black : .white.opacity(0.75))
                            .padding(.horizontal, isNarrow ? 5 : 7)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.white.opacity(selected ? 0.92 : 0.0)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(2)
            .background(Capsule().fill(Color.white.opacity(0.09)))

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

    // MARK: - Content

    @ViewBuilder
    private func contentBody(isNarrow: Bool) -> some View {
        if viewModel.isBothUnconfigured {
            VStack(spacing: 7) {
                Text(L10n.t("Chưa kết nối tài khoản Stripe hoặc Shopify"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(1)
                Text(L10n.t("Mỗi nguồn dùng quyền chỉ đọc riêng và đối soát độc lập."))
                    .font(.system(size: 9.5))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
                if let onSettings = viewModel.onOpenSettingsRequested {
                    Button(L10n.t("Kết nối trong Cài đặt")) { onSettings() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        } else if isNarrow {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 6) {
                    reconciliationStrip
                    sourceCard(source: .stripe, state: viewModel.snapshot.stripeState)
                    sourceCard(source: .shopify, state: viewModel.snapshot.shopifyState)
                    chartPanel(compact: true)
                    footerLine
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top, spacing: 10) {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 5) {
                            reconciliationStrip
                            sourceCard(source: .stripe, state: viewModel.snapshot.stripeState)
                            sourceCard(source: .shopify, state: viewModel.snapshot.shopifyState)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                    chartPanel(compact: false)
                        .frame(width: 248, alignment: .topLeading)
                }
                footerLine
            }
        }
    }

    @ViewBuilder
    private var reconciliationStrip: some View {
        switch viewModel.snapshot.reconciliationStatus {
        case .ambiguousOverlap:
            HStack(spacing: 5) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(.yellow)
                Text(L10n.t("Hiển thị riêng từng nguồn — chưa rõ trùng giao dịch"))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: XFinderTokens.Radius.badge).fill(Color.yellow.opacity(0.11)))
        case .verifiedDisjoint(let matches):
            if let combined = viewModel.snapshot.combinedTotalsByCurrency, !combined.isEmpty {
                let firstSummary = combined.map { "\($0.currency): \(MoneyFormatting.format(minorUnits: $0.grossMinor, currency: $0.currency))" }.joined(separator: " · ")
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.mint)
                    Text("\(L10n.t("Đã đối soát chéo")) (\(matches)) · \(firstSummary)")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.88))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: XFinderTokens.Radius.badge).fill(Color.mint.opacity(0.12)))
            }
        case .singleSourceOrNone:
            EmptyView()
        }
    }

    private func sourceCard(source: RevenueSourceKind, state: SourceSyncState) -> some View {
        let activeChart = viewModel.selectedChartSource == source
        let report = state.report
        let freshText = viewModel.freshnessLabel(for: source)

        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: source.sfSymbol)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(source == .stripe ? .indigo : .green)
                Text(source.displayName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)

                if let cfg = report?.config {
                    Text(cfg.accountLabel)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                if let err = state.error {
                    let pres = RevenueErrorPresentation(for: err)
                    Label(L10n.t(pres.titleKey), systemImage: pres.symbolName)
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                } else if !freshText.isEmpty {
                    Text(freshText)
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }
            }

            switch state {
            case .unconfigured:
                HStack {
                    Text(L10n.t("Chưa kết nối"))
                        .font(.system(size: 9.5))
                        .foregroundStyle(.white.opacity(0.5))
                    Spacer()
                    if let onSettings = viewModel.onOpenSettingsRequested {
                        Button(L10n.t("Kết nối")) { onSettings() }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                    }
                }
            case .loadingInitial:
                Text(L10n.t("Đang đồng bộ số liệu..."))
                    .font(.system(size: 9.5))
                    .foregroundStyle(.white.opacity(0.65))
            case .empty:
                Text(L10n.t("0 giao dịch trong kỳ đã chọn"))
                    .font(.system(size: 9.5))
                    .foregroundStyle(.white.opacity(0.6))
            case .loaded(let rep, _), .failedWithCache(let rep, _):
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(rep.currencyTotals) { row in
                        currencySummaryRow(row)
                    }
                    if let limitKey = rep.historyLimitedNoticeKey {
                        Text(L10n.t(limitKey))
                            .font(.system(size: 8.5, weight: .medium))
                            .foregroundStyle(.yellow.opacity(0.9))
                            .lineLimit(1)
                    }
                }
            case .failedNoCache(let err):
                let pres = RevenueErrorPresentation(for: err)
                HStack(spacing: 6) {
                    Text(L10n.t(pres.titleKey))
                        .font(.system(size: 9.5))
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                    Spacer()
                    if pres.canRetry {
                        Button(L10n.t("Thử lại")) { viewModel.refresh() }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: XFinderTokens.Radius.control, style: .continuous)
                .fill(Color.white.opacity(activeChart ? 0.11 : 0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: XFinderTokens.Radius.control, style: .continuous)
                .strokeBorder(state.error != nil ? Color.orange.opacity(0.5) : Color.white.opacity(activeChart ? 0.20 : 0.06), lineWidth: 0.6)
        )
        .contentShape(Rectangle())
        .onTapGesture { viewModel.selectedChartSource = source }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(sourceAccessibilityLabel(source: source, state: state))
    }

    private func currencySummaryRow(_ totals: CurrencyRevenueTotals) -> some View {
        let grossText = MoneyFormatting.format(minorUnits: totals.grossMinor, currency: totals.currency)
        let netText = totals.netMinor.map { MoneyFormatting.format(minorUnits: $0, currency: totals.currency) } ?? L10n.t("Chưa có dữ liệu")

        return HStack(spacing: 6) {
            Text(totals.currency)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.mint)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: XFinderTokens.Radius.badge).fill(Color.mint.opacity(0.14)))

            Text(grossText)
                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .monospacedDigit()
                .lineLimit(1)

            Text("·")
                .foregroundStyle(.white.opacity(0.4))

            Text("\(L10n.t("Thực nhận: "))\(netText)")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(totals.netMinor == nil ? .white.opacity(0.5) : .white.opacity(0.8))
                .lineLimit(1)

            Spacer(minLength: 2)

            Text("\(totals.transactionCount)\(L10n.t(" đơn"))")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
        }
    }

    private func chartPanel(compact: Bool) -> some View {
        let rep = viewModel.report(for: viewModel.selectedChartSource)
        let currencies = rep?.currencyTotals.map(\.currency) ?? []
        let activeCurrency = viewModel.activeChartCurrency
        let buckets = viewModel.activeChartBuckets
        let activeTotals = rep?.currencyTotals.first { $0.currency == activeCurrency }

        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Text(viewModel.selectedChartSource.displayName)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.white)
                if currencies.count > 1, let cur = activeCurrency {
                    ForEach(currencies, id: \.self) { code in
                        let selected = (code == cur)
                        Button { viewModel.selectedChartCurrency = code } label: {
                            Text(code)
                                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(selected ? .black : .white.opacity(0.75))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(Capsule().fill(Color.white.opacity(selected ? 0.90 : 0.10)))
                        }
                        .buttonStyle(.plain)
                    }
                } else if let cur = activeCurrency {
                    Text(cur)
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.mint)
                }
                Spacer(minLength: 0)
            }

            if buckets.isEmpty {
                Text(L10n.t("Chưa có biểu đồ doanh thu"))
                    .font(.system(size: 9.5))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, minHeight: compact ? 38 : 56, alignment: .center)
            } else {
                RevenueBarsView(buckets: buckets, tint: viewModel.selectedChartSource == .stripe ? .indigo : .mint)
                    .frame(height: compact ? 38 : 54)
            }

            if let totals = activeTotals {
                HStack(spacing: 8) {
                    if totals.refundMinor > 0 {
                        Text("\(L10n.t("Hoàn: "))\(MoneyFormatting.format(minorUnits: totals.refundMinor, currency: totals.currency))")
                            .font(.system(size: 8.5, design: .monospaced))
                            .foregroundStyle(.orange.opacity(0.9))
                            .lineLimit(1)
                    }
                    if let payout = totals.payoutMinor {
                        Text("\(L10n.t("Payout riêng: "))\(MoneyFormatting.format(minorUnits: payout, currency: totals.currency))")
                            .font(.system(size: 8.5, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.58))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
            }
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

    private var footerLine: some View {
        let rep = viewModel.report(for: viewModel.selectedChartSource) ?? viewModel.report(for: .stripe) ?? viewModel.report(for: .shopify)
        let boundary = rep?.windowBoundaryLabel ?? ""
        return HStack(spacing: 6) {
            Text(boundary.isEmpty ? L10n.t("Múi giờ theo tài khoản") : "\(L10n.t("Kỳ theo tài khoản: "))\(boundary)")
                .font(.system(size: 8.5, design: .monospaced))
                .foregroundStyle(.white.opacity(0.45))
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(L10n.t("Dữ liệu mẫu QA — chỉ đọc"))
                .font(.system(size: 8.5))
                .foregroundStyle(.white.opacity(0.45))
                .lineLimit(1)
        }
    }

    private func sourceAccessibilityLabel(source: RevenueSourceKind, state: SourceSyncState) -> String {
        switch state {
        case .unconfigured:
            return "\(source.displayName), \(L10n.t("Chưa kết nối"))"
        case .loadingInitial:
            return "\(source.displayName), \(L10n.t("Đang đồng bộ số liệu..."))"
        case .empty:
            return "\(source.displayName), \(L10n.t("0 giao dịch trong kỳ đã chọn"))"
        case .loaded(let rep, _), .failedWithCache(let rep, _):
            let amounts = rep.currencyTotals.map { MoneyFormatting.format(minorUnits: $0.grossMinor, currency: $0.currency) }.joined(separator: ", ")
            return "\(source.displayName), \(amounts)"
        case .failedNoCache(let err):
            return "\(source.displayName), \(L10n.t(RevenueErrorPresentation(for: err).titleKey))"
        }
    }
}

private struct RevenueBarsView: View {
    let buckets: [RevenueChartBucket]
    let tint: Color

    var body: some View {
        let maxMinor = max(1, buckets.map(\.grossMinor).max() ?? 1)
        HStack(alignment: .bottom, spacing: 2.5) {
            ForEach(buckets) { b in
                let fraction = Double(max(0, b.grossMinor)) / Double(maxMinor)
                VStack(spacing: 1) {
                    Spacer(minLength: 0)
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(tint.opacity(b.grossMinor > 0 ? 0.85 : 0.16))
                        .frame(height: max(2, CGFloat(fraction) * 34))
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}
