import SwiftUI

/// Cảnh báo — *"tell me when the machine is in trouble while I am not looking."*
/// Rules and thresholds live in `AlertRules`; this page edits them and shows what was last read.
struct AlertsDetailView: View {
    @State private var monitor = AlertMonitor.shared
    @State private var hub = FeatureHub.shared
    // MUST match `AlertMonitor`'s reader default (false) — FeatureKeyDefaultsTests pins it.
    @AppStorage("alerts.enabled") private var enabled = false
    @State private var thresholds = AlertMonitor.shared.thresholds

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: XFinderTokens.Space.section) {
                PageHeader(icon: "bell.badge", title: L10n.t("Cảnh báo"),
                           subtitle: L10n.t("Một thông báo khi máy gặp vấn đề kéo dài — không lặp lại mỗi 30 giây."))

                VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
                    ToggleRow(title: L10n.t("Bật cảnh báo"),
                              subtitle: L10n.t("Kiểm tra mỗi 30 giây khi bật; tắt thì không có bộ hẹn giờ nào."),
                              isOn: $enabled)
                        .onChange(of: enabled) { monitor.applySettings() }
                    authorizationRow
                }
                .padding(.horizontal, XFinderTokens.Space.page)

                Divider().padding(.horizontal, XFinderTokens.Space.page)

                VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
                    SectionHeader(icon: "slider.horizontal.3", title: L10n.t("Quy tắc"),
                                  subtitle: L10n.t("Điều kiện phải kéo dài đủ lâu mới báo; báo rồi phải hạ xuống mới báo lại."))
                    VStack(spacing: XFinderTokens.Space.inline) {
                        ruleRow(.cpu, value: $thresholds.cpuPercent, range: 10...100, step: 5, unit: "%", current: monitor.lastSample?.cpuPercent.map { String(format: "%.0f%%", $0) })
                        pressureRow
                        ruleRow(.diskSpace, value: $thresholds.diskFreePercent, range: 1...50, step: 1, unit: "%", current: monitor.lastSample?.diskFreePercent.map { "\(L10n.t("còn trống "))\(String(format: "%.0f%%", $0))" })
                        ruleRow(.temperature, value: $thresholds.socTemperature, range: 50...120, step: 5, unit: " °C", current: monitor.lastSample?.socTemperature.map { String(format: "%.0f °C", $0) })
                        ruleRow(.battery, value: $thresholds.batteryPercent, range: 5...50, step: 5, unit: "%", current: monitor.lastSample?.batteryPercent.map { String(format: "%.0f%%", $0) })
                        Divider()
                        PickerRow(title: L10n.t("Phải kéo dài"), selection: $thresholds.sustainedSeconds) {
                            Text(L10n.t("Ngay lập tức")).tag(0.0)
                            Text("1" + L10n.t(" phút")).tag(60.0)
                            Text("2" + L10n.t(" phút")).tag(120.0)
                            Text("5" + L10n.t(" phút")).tag(300.0)
                        }
                        PickerRow(title: L10n.t("Không báo lại trong"), selection: $thresholds.cooldownSeconds) {
                            Text("5" + L10n.t(" phút")).tag(300.0)
                            Text("30" + L10n.t(" phút")).tag(1800.0)
                            Text("2" + L10n.t(" giờ")).tag(7200.0)
                        }
                    }
                    .padding(.horizontal, XFinderTokens.Space.page)
                    .onChange(of: thresholds) { _, new in monitor.thresholds = new }
                }

                Divider().padding(.horizontal, XFinderTokens.Space.page)

                VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
                    SectionHeader(icon: "clock.arrow.circlepath", title: L10n.t("Gần đây"),
                                  subtitle: lastTickText)
                    VStack(alignment: .leading, spacing: XFinderTokens.Space.tight) {
                        if monitor.recent.isEmpty {
                            Text(L10n.t("Chưa có cảnh báo nào trong phiên này.")).font(XFinderTokens.Font.rowValue).foregroundColor(.secondary)
                        }
                        ForEach(Array(monitor.recent.enumerated()), id: \.offset) { _, e in
                            let (k, v) = AlertRules.bodyKeyAndValue(for: e)
                            HStack(spacing: XFinderTokens.Space.inline) {
                                Image(systemName: e.kind.symbol).foregroundColor(.orange).frame(width: 18)
                                Text("\(L10n.t(e.kind.titleKey)) — \(L10n.t(k))\(v)").font(XFinderTokens.Font.rowValue)
                                Spacer()
                                Text(e.at.formatted(date: .omitted, time: .shortened)).font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                            }
                        }
                        Button(L10n.t("Gửi thông báo thử")) { monitor.sendTest() }
                            .controlSize(.small).padding(.top, 4)
                    }
                    .padding(.horizontal, XFinderTokens.Space.page)
                }
            }
            .padding(.bottom, XFinderTokens.Space.section)
            .pageWidthSafe()
        }
        .background(XFinderTokens.Settings.contentBackground)
        .onAppear { thresholds = monitor.thresholds; if enabled { monitor.requestAuthorizationIfNeeded() } }
    }

    private var lastTickText: String {
        guard let t = monitor.lastTick else { return L10n.t("Chưa đọc lần nào — bật cảnh báo để bắt đầu.") }
        return "\(L10n.t("Lần đọc cuối "))\(t.formatted(date: .omitted, time: .standard))"
    }

    @ViewBuilder private var authorizationRow: some View {
        if enabled {
            HStack(alignment: .top, spacing: XFinderTokens.Space.inline) {
                switch monitor.notificationsAuthorized {
                case true:
                    Circle().fill(Color.green).frame(width: 7, height: 7).padding(.top, 4)
                    Text(L10n.t("Cảnh báo hiện dưới dạng biểu ngữ của XFinder và trong Trung tâm thông báo."))
                        .font(XFinderTokens.Font.rowValue).foregroundColor(.secondary)
                case false:
                    Circle().fill(Color.secondary).frame(width: 7, height: 7).padding(.top, 4)
                    Text(L10n.t("Cảnh báo hiện dưới dạng biểu ngữ của XFinder. Trung tâm thông báo của macOS từ chối bản ký bằng chứng chỉ tự tạo, nên không có thông báo hệ thống."))
                        .font(XFinderTokens.Font.rowValue).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                default:
                    ProgressView().controlSize(.small)
                    Text(L10n.t("Đang hỏi quyền thông báo…")).font(XFinderTokens.Font.rowValue).foregroundColor(.secondary)
                }
                Spacer()
            }
        }
    }

    private func ruleRow(_ kind: AlertRules.Kind, value: Binding<Double>, range: ClosedRange<Double>, step: Double, unit: String, current: String?) -> some View {
        let on = Binding(get: { thresholds.enabled.contains(kind) },
                         set: { if $0 { thresholds.enabled.insert(kind) } else { thresholds.enabled.remove(kind) } })
        return HStack(spacing: XFinderTokens.Space.inline) {
            Toggle("", isOn: on).toggleStyle(.switch).labelsHidden().controlSize(.small)
            Image(systemName: kind.symbol).foregroundColor(.secondary).frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.t(kind.titleKey)).font(XFinderTokens.Font.row)
                if let current {
                    Text("\(L10n.t("Hiện tại: "))\(current)").font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                } else if monitor.lastSample != nil {
                    Text(L10n.t("Không đọc được trên máy này — quy tắc bị bỏ qua.")).font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            Stepper(value: value, in: range, step: step) {
                Text("\(String(format: "%.0f", value.wrappedValue))\(unit)")
                    .font(XFinderTokens.Font.mono).frame(width: 56, alignment: .trailing)
            }
            .disabled(!on.wrappedValue)
        }
    }

    private var pressureRow: some View {
        let kind = AlertRules.Kind.memoryPressure
        let on = Binding(get: { thresholds.enabled.contains(kind) },
                         set: { if $0 { thresholds.enabled.insert(kind) } else { thresholds.enabled.remove(kind) } })
        return HStack(spacing: XFinderTokens.Space.inline) {
            Toggle("", isOn: on).toggleStyle(.switch).labelsHidden().controlSize(.small)
            Image(systemName: kind.symbol).foregroundColor(.secondary).frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.t(kind.titleKey)).font(XFinderTokens.Font.row)
                if let lvl = monitor.lastSample?.memoryPressureLevel {
                    Text("\(L10n.t("Hiện tại: "))\(lvl >= 4 ? "critical" : lvl >= 2 ? "warning" : "normal")").font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            Picker("", selection: $thresholds.memoryPressureLevel) {
                Text("warning").tag(2)
                Text("critical").tag(4)
            }.pickerStyle(.menu).labelsHidden().frame(width: 110).disabled(!on.wrappedValue)
        }
    }
}
