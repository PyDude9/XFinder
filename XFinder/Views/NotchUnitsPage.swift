import SwiftUI
import AppKit

/// Offline unit converter tool for the Dynamic Island notch body (fits narrow 354 × 140 pt and wide 584 × 140 pt).
/// Uses Foundation `Measurement` via `NotchUnitRules` for length, mass, and temperature only (no currency).
/// No polling timers; all state is local and event-driven.
struct NotchUnitsPage: View {
    var model: NotchSurfaceModel? = nil
    var localeOverride: Locale? = nil
    var onInputFocusChanged: ((Bool) -> Void)? = nil
    var onCopy: (String) -> Void = { text in
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    @State private var state = NotchUnitRules.State()
    @State private var copied = false
    @FocusState private var inputFocused: Bool
    @Environment(\.notchAccent) private var accent

    private typealias N = XFinderTokens.Notch

    private var activeLocale: Locale {
        localeOverride ?? Locale(identifier: L10n.isEnglish ? "en_US" : "vi_VN")
    }

    private var evaluation: NotchUnitRules.Evaluation {
        state.evaluate(locale: activeLocale)
    }

    private var copyPayload: String? {
        NotchUnitRules.copyPayload(for: evaluation)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.tight) {
            headerRow
            inputAndUnitsRow
            resultCard
            footerHintRow
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: state) { _, _ in
            if copied { copied = false }
        }
    }

    // MARK: - Row 1: Category switch + offline badge

    private var headerRow: some View {
        HStack(spacing: XFinderTokens.Space.tight) {
            categorySwitch
            Spacer(minLength: XFinderTokens.Space.tight)
            Text(L10n.t("Ngoại tuyến"))
                .font(XFinderTokens.Font.caption)
                .opacity(0.45)
                .lineLimit(1)
        }
        .frame(height: 24)
    }

    private var categorySwitch: some View {
        HStack(spacing: 2) {
            ForEach(NotchUnitRules.Category.allCases) { category in
                let selected = state.category == category
                Button {
                    state.selectCategory(category)
                } label: {
                    Text(categoryLabel(category))
                        .font(XFinderTokens.Font.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(selected ? Color.black : N.toolbarIcon)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.white.opacity(selected ? 1 : 0)))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Capsule().fill(N.capsule))
    }

    // MARK: - Row 2: Locale number input + From unit + Swap + To unit

    private var inputAndUnitsRow: some View {
        let hasError = evaluation.error != nil
        return HStack(spacing: XFinderTokens.Space.tight) {
            HStack(spacing: 4) {
                TextField(
                    "",
                    text: $state.inputText,
                    prompt: Text(L10n.t("Nhập số…")).foregroundColor(.white.opacity(0.4))
                )
                .textFieldStyle(.plain)
                .font(XFinderTokens.Font.mono)
                .monospacedDigit()
                .foregroundColor(.white)
                .focused($inputFocused)
                .onChange(of: inputFocused) { _, focused in onInputFocusChanged?(focused) }
                .onDisappear { onInputFocusChanged?(false) }
                .accessibilityLabel(L10n.t("Giá trị cần đổi"))

                if !state.inputText.isEmpty {
                    Button {
                        state.inputText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.45))
                    }
                    .buttonStyle(.plain)
                    .help(L10n.t("Xóa giá trị"))
                    .accessibilityLabel(L10n.t("Xóa giá trị"))
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: XFinderTokens.Radius.control)
                    .fill(N.capsule)
            )
            .overlay(
                RoundedRectangle(cornerRadius: XFinderTokens.Radius.control)
                    .strokeBorder(hasError ? Color(nsColor: .systemOrange).opacity(0.85) : N.cardStroke, lineWidth: 1)
            )

            unitMenu(
                selection: state.fromUnit,
                help: L10n.t("Đơn vị nguồn")
            ) { chosen in
                state.selectFromUnit(chosen)
            }

            Button {
                state.swapUnits()
            } label: {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(N.capsule))
                    .overlay(Circle().strokeBorder(N.cardStroke, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help(L10n.t("Hoán đổi đơn vị"))
            .accessibilityLabel(L10n.t("Hoán đổi đơn vị"))

            unitMenu(
                selection: state.toUnit,
                help: L10n.t("Đơn vị đích")
            ) { chosen in
                state.selectToUnit(chosen)
            }
        }
        .frame(height: 30)
    }

    private func unitMenu(
        selection: NotchUnitRules.UnitOption,
        help: String,
        onSelect: @escaping (NotchUnitRules.UnitOption) -> Void
    ) -> some View {
        Menu {
            ForEach(state.category.units) { unit in
                Button {
                    onSelect(unit)
                } label: {
                    if unit == selection {
                        Label("\(unitName(unit)) (\(unit.symbol))", systemImage: "checkmark")
                    } else {
                        Text("\(unitName(unit)) (\(unit.symbol))")
                    }
                }
            }
        } label: {
            HStack(spacing: 3) {
                Text(selection.symbol)
                    .font(XFinderTokens.Font.row)
                    .monospacedDigit()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .opacity(0.65)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: XFinderTokens.Radius.control)
                    .fill(N.capsule)
            )
            .overlay(
                RoundedRectangle(cornerRadius: XFinderTokens.Radius.control)
                    .strokeBorder(N.cardStroke, lineWidth: 1)
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(help)
        .accessibilityLabel(help)
    }

    // MARK: - Row 3: Result or inline error + Copy button

    private var resultCard: some View {
        HStack(spacing: XFinderTokens.Space.tight) {
            resultContent
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                guard let payload = copyPayload else { return }
                onCopy(payload)
                copied = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10, weight: .semibold))
                    Text(copied ? L10n.t("Đã sao chép") : L10n.t("Sao chép"))
                }
            }
            .buttonStyle(NotchPillButtonStyle(primary: copyPayload != nil))
            .disabled(copyPayload == nil)
            .opacity(copyPayload == nil ? 0.4 : 1)
            .help(L10n.t("Sao chép kết quả"))
            .accessibilityLabel(L10n.t("Sao chép kết quả"))
        }
        .padding(.horizontal, 10)
        .frame(height: 44)
        .background(
            RoundedRectangle(cornerRadius: XFinderTokens.Radius.control)
                .fill(N.capsule)
        )
        .overlay(
            RoundedRectangle(cornerRadius: XFinderTokens.Radius.control)
                .strokeBorder(evaluation.error != nil ? Color(nsColor: .systemOrange).opacity(0.6) : N.cardStroke, lineWidth: 1)
        )
    }

    @ViewBuilder private var resultContent: some View {
        switch evaluation {
        case .value(let result):
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(result.formattedOutput)
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                Text(result.toUnit.symbol)
                    .font(XFinderTokens.Font.row)
                    .foregroundColor(accent)
                    .lineLimit(1)
            }
        case .empty:
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("—")
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.35))
                Text(state.toUnit.symbol)
                    .font(XFinderTokens.Font.row)
                    .foregroundColor(.white.opacity(0.35))
            }
        case .incomplete:
            Text(L10n.t("Đang nhập…"))
                .font(XFinderTokens.Font.rowValue)
                .foregroundColor(.white.opacity(0.55))
                .lineLimit(1)
        case .error(let err):
            HStack(spacing: 5) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(nsColor: .systemOrange))
                Text(errorMessage(err))
                    .font(XFinderTokens.Font.caption)
                    .foregroundColor(Color(nsColor: .systemOrange))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Row 4: Stable footer summary

    private var footerHintRow: some View {
        HStack(spacing: XFinderTokens.Space.tight) {
            switch evaluation {
            case .value(let result):
                Text("\(result.formattedInput) \(result.fromUnit.symbol) = \(result.formattedOutput) \(result.toUnit.symbol)")
                    .font(XFinderTokens.Font.caption)
                    .monospacedDigit()
                    .opacity(0.55)
                    .lineLimit(1)
                    .truncationMode(.middle)
            case .empty, .incomplete:
                let sep = activeLocale.decimalSeparator ?? "."
                Text("\(L10n.t("Dấu thập phân: "))\(sep)")
                    .font(XFinderTokens.Font.caption)
                    .opacity(0.45)
                    .lineLimit(1)
            case .error:
                Text(L10n.t("Chỉnh lại số để tiếp tục đổi."))
                    .font(XFinderTokens.Font.caption)
                    .opacity(0.5)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(height: 16)
    }

    // MARK: - Localized Labels (each L10n.t argument is a literal for static L10n gates)

    private func categoryLabel(_ category: NotchUnitRules.Category) -> String {
        switch category {
        case .length: return L10n.t("Chiều dài")
        case .mass: return L10n.t("Khối lượng")
        case .temperature: return L10n.t("Nhiệt độ")
        }
    }

    private func unitName(_ unit: NotchUnitRules.UnitOption) -> String {
        switch unit {
        case .millimeter: return L10n.t("Milimét")
        case .centimeter: return L10n.t("Xentimét")
        case .meter: return L10n.t("Mét")
        case .kilometer: return L10n.t("Kilômét")
        case .inch: return L10n.t("Inch")
        case .foot: return L10n.t("Foot")
        case .yard: return L10n.t("Yard")
        case .mile: return L10n.t("Dặm")
        case .milligram: return L10n.t("Miligam")
        case .gram: return L10n.t("Gam")
        case .kilogram: return L10n.t("Kilogam")
        case .metricTon: return L10n.t("Tấn")
        case .ounce: return L10n.t("Ounce")
        case .pound: return L10n.t("Pound")
        case .celsius: return L10n.t("Độ C")
        case .fahrenheit: return L10n.t("Độ F")
        case .kelvin: return L10n.t("Kelvin")
        }
    }

    private func errorMessage(_ error: NotchUnitRules.ConversionError) -> String {
        switch error {
        case .invalidNumber:
            return L10n.t("Số không hợp lệ")
        case .outOfRange:
            return L10n.t("Số vượt giới hạn hỗ trợ")
        case .incompatibleUnits:
            return L10n.t("Đơn vị không thuộc cùng nhóm")
        }
    }
}
