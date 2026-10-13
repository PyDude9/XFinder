import SwiftUI

/// The small pill beside a selection (Smart Selection E5). One click opens the panel.
struct SmartSelectBadgeView: View {
    var model: SmartSelectionModel

    var body: some View {
        Button { SmartSelectionBadge.shared.openPanel() } label: {
            Image(systemName: "wand.and.stars")
                .font(XFinderTokens.Font.row)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Capsule().fill(Color.accentColor))
        }
        .buttonStyle(.plain)
        .help(L10n.t("Việc XFinder làm được với vùng chọn này"))
        .accessibilityLabel(L10n.t("Việc XFinder làm được với vùng chọn này"))
    }
}

/// The panel the badge opens: one row per action, most specific first.
struct SmartSelectPanelView: View {
    var model: SmartSelectionModel
    private var decimalComma: Bool { !L10n.isEnglish }

    var body: some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.tight) {
            HStack(spacing: XFinderTokens.Space.tight) {
                Image(systemName: "wand.and.stars").foregroundColor(.accentColor)
                Text(model.sourceApp ?? L10n.t("Vùng chọn")).font(XFinderTokens.Font.row).bold().lineLimit(1)
                Spacer()
                Button { SmartSelectionBadge.shared.closePanel() } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundColor(.secondary)
                    .keyboardShortcut(.cancelAction).help(L10n.t("Đóng"))
                    .accessibilityLabel(L10n.t("Đóng"))
            }
            Text(model.text.replacingOccurrences(of: "\n", with: " "))
                .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                .lineLimit(2).truncationMode(.tail)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            Divider()
            ForEach(Array(model.actions.enumerated()), id: \.offset) { _, action in
                row(action)
            }
            if let n = model.notice {
                HStack(spacing: XFinderTokens.Space.tight) {
                    Text(L10n.t(n.key)).font(XFinderTokens.Font.caption)
                        .foregroundColor(n.kind == .success ? .green : (n.kind == .warning ? .orange : .red))
                    if n.opensCalendarPrivacy {
                        Button(L10n.t("Mở Cài đặt")) { SmartSelectionBadge.shared.openCalendarPrivacy() }.controlSize(.small)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(XFinderTokens.Space.inline + 2)
        .frame(width: 360)
        .background(RoundedRectangle(cornerRadius: XFinderTokens.Radius.tile, style: .continuous)
            .fill(Color(nsColor: .windowBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: XFinderTokens.Radius.tile, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.12)))
    }

    @ViewBuilder private func row(_ action: SmartSelectionRules.Action) -> some View {
        switch action {
        case .unit(let r):
            let src = "\(UnitConversion.format(r.source.value, decimalComma: decimalComma)) \(r.source.unit.symbol)"
            let dst = "\(UnitConversion.format(r.target.value, decimalComma: decimalComma)) \(r.target.unit.symbol)"
            resultRow(icon: "ruler", caption: "\(src) ≈", value: dst, copy: dst)
        case .time(let t):
            let src = "\(TimeZoneConversion.clockLabel(hour: t.sourceHour, minute: t.sourceMinute)) \(t.zoneLabel) (\(TimeZoneConversion.offsetLabel(t.sourceOffset)))"
            let local = TimeZoneConversion.clockLabel(hour: t.localHour, minute: t.localMinute)
            VStack(alignment: .leading, spacing: 2) {
                resultRow(icon: "globe", caption: "\(src) =",
                          value: "\(local)\(dayShiftLabel(t.dayShift))\(L10n.t(" · giờ máy "))(\(TimeZoneConversion.offsetLabel(t.localOffset)))",
                          copy: local)
                if let note = t.regionNote {
                    Text("\(L10n.t("Lưu ý: "))\(note.city)\(L10n.t(" hiện dùng "))\(TimeZoneConversion.offsetLabel(note.regionOffset))\(L10n.t(" lúc này."))")
                        .font(XFinderTokens.Font.caption).foregroundColor(.orange)
                        .padding(.leading, 26)
                }
            }
        case .arithmetic(let v):
            let s = SmartSelectionRules.formatResult(v, decimalComma: decimalComma)
            resultRow(icon: "equal.circle", caption: L10n.t("Kết quả"), value: "= \(s)", copy: s)
        case .calendar(let title, let date, let hasTime):
            HStack(alignment: .top, spacing: XFinderTokens.Space.tight) {
                Image(systemName: "calendar.badge.plus").frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title.isEmpty ? L10n.t("Sự kiện mới") : title).font(XFinderTokens.Font.row).lineLimit(1)
                    Text(dateLabel(date, hasTime: hasTime)).font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                }
                Spacer()
                if model.calendarAdded != nil {
                    Button(L10n.t("Mở Lịch")) { SmartSelectionBadge.shared.openCalendar(on: date) }.controlSize(.small)
                } else {
                    Button(L10n.t("Thêm vào Lịch")) {
                        SmartSelectionBadge.shared.addToCalendar(title: title, date: date, hasTime: hasTime)
                    }.controlSize(.small)
                }
            }
        case .translate:
            HStack(spacing: XFinderTokens.Space.tight) {
                Image(systemName: "character.bubble").frame(width: 18)
                Text(L10n.t("Dịch bằng bản dịch của Apple, ngay trên máy")).font(XFinderTokens.Font.caption)
                    .foregroundColor(.secondary).lineLimit(2)
                Spacer()
                if #available(macOS 15.0, *) {
                    Button(L10n.t("Dịch…")) { SmartSelectionBadge.shared.translate() }.controlSize(.small)
                } else {
                    Text(L10n.t("Cần macOS 15")).font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                }
            }
        }
    }

    private func resultRow(icon: String, caption: String, value: String, copy: String) -> some View {
        HStack(spacing: XFinderTokens.Space.tight) {
            Image(systemName: icon).frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(caption).font(XFinderTokens.Font.caption).foregroundColor(.secondary).lineLimit(1)
                Text(value).font(XFinderTokens.Font.row).bold().lineLimit(1).textSelection(.enabled)
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            Button(L10n.t("Sao chép")) { SmartSelectionBadge.shared.copy(copy) }.controlSize(.small)
        }
    }

    private func dayShiftLabel(_ shift: Int) -> String {
        switch shift {
        case 1: return L10n.t(" hôm sau")
        case -1: return L10n.t(" hôm trước")
        default: return ""
        }
    }

    private func dateLabel(_ date: Date, hasTime: Bool) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: L10n.isEnglish ? "en_US" : "vi_VN")
        f.dateStyle = .medium
        f.timeStyle = hasTime ? .short : .none
        return hasTime ? f.string(from: date) : "\(f.string(from: date))\(L10n.t(" (cả ngày)"))"
    }
}
