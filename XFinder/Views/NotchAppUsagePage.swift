import SwiftUI

/// Dynamic Island page for local foreground app usage ("Thời lượng ứng dụng").
///
/// Layout: designed for the wide Dynamic Island tool body (584 × 140 pt content area) while staying
/// responsive in narrower widths.
///
/// Lifecycle contract:
/// - Tab visibility only controls whether this page can be opened; `onDisappear` never stops tracking.
/// - Opening the page never auto-enables tracking; user must opt in explicitly.
/// - Starts no timers of its own; calls `tracker.refreshForDisplay()` on appear.
struct NotchAppUsagePage: View {
    var tracker: LocalAppUsageTracker = .shared
    @Environment(\.notchAccent) private var accent

    private typealias N = XFinderTokens.Notch

    private static let headerHeight: CGFloat = 22
    private static let sectionGap: CGFloat = 6
    private static let bodyHeight: CGFloat = 112

    var body: some View {
        VStack(alignment: .leading, spacing: Self.sectionGap) {
            headerRow
                .frame(height: Self.headerHeight, alignment: .center)

            Group {
                if tracker.isReadBlocked {
                    readErrorView
                } else if !tracker.isTrackingEnabled {
                    optInView
                } else {
                    dashboardView
                }
            }
            .frame(height: Self.bodyHeight, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            tracker.refreshForDisplay()
        }
    }

    // MARK: - Header Row (22 pt)

    private var headerRow: some View {
        HStack(spacing: XFinderTokens.Space.tight) {
            Image(systemName: tracker.isActivelyCollecting ? "hourglass.circle.fill" : "hourglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(tracker.isActivelyCollecting ? accent : .white.opacity(0.75))

            Text(L10n.t("Thời lượng ứng dụng"))
                .font(XFinderTokens.Font.row)
                .lineLimit(1)

            statusBadge

            Spacer(minLength: XFinderTokens.Space.tight)

            if tracker.saveError != nil && !tracker.isReadBlocked {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.orange)
                    .help(L10n.t("Không thể lưu dữ liệu thời lượng. Dữ liệu cũ trên máy vẫn được giữ."))
                    .accessibilityLabel(L10n.t("Lỗi lưu dữ liệu thời lượng"))
            }

            headerActions
        }
    }

    @ViewBuilder private var statusBadge: some View {
        if tracker.isReadBlocked {
            Text(L10n.t("Lỗi đọc tệp"))
                .font(XFinderTokens.Font.caption)
                .foregroundColor(.orange)
                .lineLimit(1)
        } else if !tracker.isTrackingEnabled {
            Text(L10n.t("Đang tắt"))
                .font(XFinderTokens.Font.caption)
                .opacity(0.55)
                .lineLimit(1)
        } else if tracker.isPaused {
            Text(L10n.t("Đang tạm dừng"))
                .font(XFinderTokens.Font.caption)
                .opacity(0.7)
                .lineLimit(1)
        } else if tracker.isSuspended {
            Text(L10n.t("Tạm hoãn"))
                .font(XFinderTokens.Font.caption)
                .opacity(0.6)
                .lineLimit(1)
        } else if tracker.isIdle {
            Text(L10n.t("Đang nhàn rỗi"))
                .font(XFinderTokens.Font.caption)
                .opacity(0.6)
                .lineLimit(1)
        } else {
            Text(L10n.t("Đang ghi"))
                .font(XFinderTokens.Font.caption)
                .foregroundColor(accent)
                .lineLimit(1)
        }
    }

    @ViewBuilder private var headerActions: some View {
        if tracker.isReadBlocked {
            Button(L10n.t("Thử lại")) {
                tracker.retryLoad()
            }
            .buttonStyle(NotchPillButtonStyle(primary: true))
            .accessibilityLabel(L10n.t("Thử đọc lại dữ liệu thời lượng"))
        } else if tracker.confirmingClear {
            HStack(spacing: 4) {
                Button(L10n.t("Xác nhận xóa")) {
                    tracker.confirmClearHistory()
                }
                .buttonStyle(NotchPillButtonStyle(primary: true))
                .accessibilityLabel(L10n.t("Xác nhận xóa lịch sử thời lượng"))

                Button(L10n.t("Hủy")) {
                    tracker.cancelClearHistory()
                }
                .buttonStyle(NotchPillButtonStyle(primary: false))
                .accessibilityLabel(L10n.t("Hủy xóa lịch sử"))
            }
        } else {
            HStack(spacing: 4) {
                if tracker.isTrackingEnabled {
                    if tracker.isPaused {
                        Button(L10n.t("Tiếp tục")) {
                            tracker.resumeTracking()
                        }
                        .buttonStyle(NotchPillButtonStyle(primary: true))
                        .help(L10n.t("Tiếp tục ghi thời lượng ứng dụng"))
                        .accessibilityLabel(L10n.t("Tiếp tục ghi thời lượng ứng dụng"))
                    } else {
                        Button(L10n.t("Tạm dừng")) {
                            tracker.pauseTracking()
                        }
                        .buttonStyle(NotchPillButtonStyle(primary: false))
                        .help(L10n.t("Tạm dừng ghi thời lượng ứng dụng"))
                        .accessibilityLabel(L10n.t("Tạm dừng ghi thời lượng ứng dụng"))
                    }

                    Button(L10n.t("Tắt")) {
                        tracker.stopTracking()
                    }
                    .buttonStyle(NotchPillButtonStyle(primary: false))
                    .help(L10n.t("Tắt theo dõi thời lượng ngay lập tức"))
                    .accessibilityLabel(L10n.t("Tắt theo dõi thời lượng"))
                }

                if tracker.hasHistory {
                    Button(L10n.t("Xóa lịch sử")) {
                        tracker.requestClearHistory()
                    }
                    .buttonStyle(NotchPillButtonStyle(primary: false))
                    .help(L10n.t("Xóa toàn bộ lịch sử thời lượng trên máy"))
                    .accessibilityLabel(L10n.t("Xóa lịch sử thời lượng"))
                }
            }
        }
    }

    // MARK: - Read Error State

    private var readErrorView: some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.tight) {
            HStack(spacing: XFinderTokens.Space.tight) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.orange)
                Text(L10n.t("Không thể đọc tệp dữ liệu thời lượng."))
                    .font(XFinderTokens.Font.row)
            }
            Text(L10n.t("Tệp hiện có trên máy được giữ nguyên để tránh mất dữ liệu. Hãy thử đọc lại sau khi khắc phục."))
                .font(XFinderTokens.Font.caption)
                .opacity(0.65)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.top, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Opt-In State (Tracking OFF)

    private var optInView: some View {
        HStack(spacing: XFinderTokens.Space.inline) {
            VStack(alignment: .leading, spacing: XFinderTokens.Space.tight) {
                Text(L10n.t("Chỉ tính thời gian ứng dụng ở trước khi XFinder đang chạy và bạn không nhàn rỗi."))
                    .font(XFinderTokens.Font.rowValue)
                    .fixedSize(horizontal: false, vertical: true)

                Text(L10n.t("Lưu riêng trên máy tối đa 30 ngày, chỉ gồm định danh, tên ứng dụng và số giây theo ngày. Không lưu tiêu đề cửa sổ, phím gõ, URL hay nội dung và không dùng lịch sử hệ thống."))
                    .font(XFinderTokens.Font.caption)
                    .opacity(0.6)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)

                HStack(spacing: XFinderTokens.Space.row) {
                    Button(L10n.t("Bật theo dõi")) {
                        tracker.startTracking()
                    }
                    .buttonStyle(NotchPillButtonStyle(primary: true))
                    .accessibilityLabel(L10n.t("Bật theo dõi thời lượng ứng dụng"))

                    if tracker.hasHistory {
                        Text("\(L10n.t("Hôm nay: "))\(formatDuration(tracker.snapshot.todayTotalSeconds))")
                            .font(XFinderTokens.Font.caption.monospacedDigit())
                            .opacity(0.65)
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, 2)
    }

    // MARK: - Active Dashboard (Two Columns)

    private var dashboardView: some View {
        HStack(spacing: 0) {
            summaryColumn
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, XFinderTokens.Space.row)

            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(width: 1)
                .padding(.vertical, 4)

            appsColumn
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, XFinderTokens.Space.row)
        }
    }

    // MARK: - Left Column: Today Total + 7-Day Chart

    private var summaryColumn: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: XFinderTokens.Space.tight) {
                Text(L10n.t("Hôm nay"))
                    .font(XFinderTokens.Font.caption)
                    .opacity(0.6)
                Text(formatDuration(tracker.snapshot.todayTotalSeconds))
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .monospacedDigit()
                Spacer(minLength: 0)
                Text("\(L10n.t("7 ngày: "))\(formatDuration(tracker.snapshot.sevenDayTotalSeconds))")
                    .font(XFinderTokens.Font.caption.monospacedDigit())
                    .opacity(0.55)
                    .lineLimit(1)
            }

            sevenDayChart
                .frame(height: 62)

            Text(L10n.t("Ứng dụng ở trước khi XFinder chạy, trừ lúc nhàn rỗi."))
                .font(XFinderTokens.Font.caption)
                .opacity(0.45)
                .lineLimit(1)
        }
    }

    private var sevenDayChart: some View {
        let days = tracker.snapshot.lastSevenDays
        let maxSeconds = max(1, days.map(\.totalSeconds).max() ?? 1)

        return HStack(alignment: .bottom, spacing: 6) {
            ForEach(days) { day in
                let ratio = CGFloat(day.totalSeconds) / CGFloat(maxSeconds)
                let barHeight = day.totalSeconds > 0 ? max(4, 42 * ratio) : 2

                VStack(spacing: 3) {
                    Spacer(minLength: 0)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(day.isToday ? accent : (day.totalSeconds > 0 ? Color.white.opacity(0.55) : N.progressTrack))
                        .frame(height: barHeight)
                    Text(shortWeekdayLabel(for: day.date))
                        .font(.system(size: 9, weight: day.isToday ? .semibold : .regular))
                        .opacity(day.isToday ? 0.95 : 0.5)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(shortWeekdayLabel(for: day.date))
                .accessibilityValue(formatDuration(day.totalSeconds))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.t("Biểu đồ thời lượng 7 ngày"))
    }

    // MARK: - Right Column: Per-App Breakdown

    private var appsColumn: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(L10n.t("Theo ứng dụng"))
                    .font(XFinderTokens.Font.caption)
                    .opacity(0.6)
                Spacer(minLength: 0)
                if !tracker.snapshot.todayApps.isEmpty {
                    Text("\(tracker.snapshot.todayApps.count)\(L10n.t(" ứng dụng"))")
                        .font(XFinderTokens.Font.caption.monospacedDigit())
                        .opacity(0.45)
                }
            }

            if tracker.snapshot.todayApps.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t("Chưa có dữ liệu hôm nay."))
                        .font(XFinderTokens.Font.caption)
                        .opacity(0.6)
                    Text(L10n.t("Chuyển giữa các ứng dụng khi theo dõi đang bật để bắt đầu ghi nhận."))
                        .font(XFinderTokens.Font.caption)
                        .opacity(0.45)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 4)
                Spacer(minLength: 0)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 5) {
                        ForEach(tracker.snapshot.todayApps) { row in
                            appRow(row)
                        }
                    }
                }
            }
        }
    }

    private func appRow(_ row: LocalAppUsageRules.AppUsageRow) -> some View {
        let name = row.displayName.isEmpty ? L10n.t("Ứng dụng không rõ") : row.displayName
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: XFinderTokens.Space.tight) {
                Text(name)
                    .font(XFinderTokens.Font.caption)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                Text(formatDuration(row.seconds))
                    .font(XFinderTokens.Font.caption.monospacedDigit())
                    .opacity(0.75)
                    .lineLimit(1)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(N.progressTrack)
                    Capsule()
                        .fill(accent.opacity(0.85))
                        .frame(width: max(3, geo.size.width * CGFloat(row.share)))
                }
            }
            .frame(height: 3)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
        .accessibilityValue(formatDuration(row.seconds))
    }

    // MARK: - Formatting Helpers

    private func formatDuration(_ totalSeconds: Int) -> String {
        let parts = LocalAppUsageRules.durationParts(seconds: totalSeconds)
        if parts.hours > 0 {
            if parts.minutes > 0 {
                return "\(parts.hours)\(L10n.t("g "))\(parts.minutes)\(L10n.t("p"))"
            }
            return "\(parts.hours)\(L10n.t("g"))"
        }
        if parts.minutes > 0 {
            return "\(parts.minutes)\(L10n.t("p"))"
        }
        if parts.seconds > 0 {
            return "\(parts.seconds)\(L10n.t("s"))"
        }
        return "0\(L10n.t("p"))"
    }

    private func shortWeekdayLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: L10n.isEnglish ? "en_US" : "vi_VN")
        formatter.setLocalizedDateFormatFromTemplate("EEE")
        return formatter.string(from: date)
    }
}
