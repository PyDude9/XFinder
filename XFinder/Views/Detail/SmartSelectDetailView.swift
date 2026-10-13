import SwiftUI
import AppKit

/// Smart Selection (E5). The user comes here to decide whether a small button appears beside text they select in
/// other apps, and where it must never appear. ⇧⌘G lives here too: both act on "text I selected in another app".
struct SmartSelectDetailView: View {
    @AppStorage("smartSelect.enabled") private var enabled = false
    @AppStorage("smartSelect.minLength") private var minLength = 2
    @AppStorage("smartSelect.excludedApps") private var excludedRaw = ""
    // N5a — one key, one control: the switch moved here from the Voice page (same reader, TranslateSelectionController).
    @AppStorage("translate.hotkeyEnabled") private var translateEnabled = false
    @State private var trusted = WindowManager.isTrusted

    private var excluded: [String] { SmartSelectionRules.parseExcluded(excludedRaw).sorted() }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: XFinderTokens.Space.section) {
                PageHeader(icon: "wand.and.stars",
                           title: L10n.t("Chọn văn bản thông minh"),
                           subtitle: L10n.t("Bôi đen chữ ở app khác: một nút nhỏ hiện cạnh đó để đổi đơn vị, đổi múi giờ, tính, thêm vào Lịch hoặc dịch."))
                badgeSection
                Divider().padding(.horizontal, XFinderTokens.Space.page)
                excludedSection
                Divider().padding(.horizontal, XFinderTokens.Space.page)
                actionsSection
                Divider().padding(.horizontal, XFinderTokens.Space.page)
                hotkeySection
            }
            .padding(.bottom, XFinderTokens.Space.section)
            .pageWidthSafe()
        }
        .onAppear { trusted = WindowManager.isTrusted }
    }

    private var badgeSection: some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
            SectionHeader(icon: "cursorarrow.click.badge.clock", title: L10n.t("Nút trên vùng chọn"),
                          subtitle: L10n.t("Chỉ hiện khi bạn bôi đen bằng chuột và vùng chọn đã đứng yên."))
            VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
                ToggleRow(title: L10n.t("Hiện nút khi bôi đen chữ"),
                          subtitle: L10n.t("Đọc vùng chọn của app đang dùng qua Trợ năng. Không ghi lại, không gửi đi; chữ chỉ được giữ tới lần bôi đen kế tiếp."),
                          isOn: $enabled)
                    .onChange(of: enabled) { SelectionWatcher.shared.applySettings() }
                if enabled && !trusted {
                    InlineNote(kind: .warning,
                               text: L10n.t("Cần quyền Trợ năng để đọc vùng chọn của app khác."),
                               buttonTitle: L10n.t("Cấp quyền Trợ năng")) {
                        WindowManager.requestAccessibilityTrust()
                    }
                }
                PickerRow(title: L10n.t("Độ dài tối thiểu (ký tự)"),
                          subtitle: L10n.t("Bỏ qua vùng chọn ngắn hơn để nút không hiện khi bấm nhầm."),
                          selection: $minLength, width: 90) {
                    ForEach(SmartSelectionRules.minLengthChoices, id: \.self) { n in Text("\(n)").tag(n) }
                }
                .disabled(!enabled)
                InlineNote(text: L10n.t("Vùng chọn bằng bàn phím không hiện nút vì không biết nó nằm đâu trên màn hình — dùng ⇧⌘G. Một số app không cho Trợ năng đọc vùng chọn; khi đó nút không hiện."))
            }
            .padding(.horizontal, XFinderTokens.Space.page)
        }
    }

    private var excludedSection: some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
            SectionHeader(icon: "nosign", title: L10n.t("Không hiện trong các app này"),
                          subtitle: L10n.t("Trình chỉnh ảnh, bảng vẽ, game — nơi kéo chuột không phải là bôi đen chữ. Trình quản lý mật khẩu luôn bị bỏ qua."))
            VStack(alignment: .leading, spacing: XFinderTokens.Space.tight) {
                if excluded.isEmpty {
                    Text(L10n.t("Chưa loại trừ app nào.")).font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                }
                ForEach(excluded, id: \.self) { bid in
                    HStack {
                        Text(appName(bid)).font(XFinderTokens.Font.row)
                            .lineLimit(1).truncationMode(.middle).frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                        Button(L10n.t("Bỏ")) { remove(bid) }.controlSize(.small)
                    }
                }
                Menu(L10n.t("Thêm app đang chạy")) {
                    ForEach(runningApps(), id: \.0) { bid, name in
                        Button(name) { add(bid) }
                    }
                }
                .frame(width: 200)
            }
            .padding(.horizontal, XFinderTokens.Space.page)
        }
    }

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
            SectionHeader(icon: "list.bullet", title: L10n.t("Nút làm được gì"),
                          subtitle: L10n.t("Chỉ hiện những việc hợp với chữ đã chọn, việc cụ thể nhất lên đầu."))
            VStack(alignment: .leading, spacing: XFinderTokens.Space.tight) {
                LabeledLine(label: L10n.t("Đổi đơn vị"), value: "5 km ≈ 3.11 mi · 72°F ≈ 22.22°C")
                LabeledLine(label: L10n.t("Đổi múi giờ"), value: "3pm PST = 06:00")
                LabeledLine(label: L10n.t("Tính"), value: "12 * (3 + 4) = 84")
                LabeledLine(label: L10n.t("Thêm vào Lịch"), value: L10n.t("Họp nhóm thứ Sáu 9 giờ"))
                LabeledLine(label: L10n.t("Dịch"), value: L10n.t("macOS 15 trở lên, ngay trên máy"))
                InlineNote(text: L10n.t("Múi giờ viết tắt có nhiều nghĩa (CST, IST, BST…) bị bỏ qua thay vì đoán. EST, PST… dùng đúng định nghĩa; nếu vùng đó đang dùng giờ mùa hè, panel ghi chú. Thêm vào Lịch chỉ ghi khi bạn bấm nút, và hỏi quyền Lịch lần đầu."))
                    .padding(.horizontal, XFinderTokens.Space.page)
            }
        }
    }

    /// N5a — moved from the Voice page.
    private var hotkeySection: some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
            SectionHeader(icon: "character.bubble",
                          title: L10n.t("Dịch vùng chọn (⇧⌘G)"),
                          subtitle: L10n.t("Bôi đen chữ ở app bất kỳ, bấm ⇧⌘G: bản dịch của Apple ngay trên máy, không mạng."))
            VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
                ToggleRow(title: L10n.t("Bật phím ⇧⌘G dịch vùng chọn"),
                          subtitle: L10n.t("Đọc chữ đang bôi đen qua Trợ năng rồi mở hộp dịch của Apple (macOS 15+). Không gửi gì đi; gói ngôn ngữ tải một lần theo cặp. App nào không cho Trợ năng đọc vùng chọn thì panel nói rõ."),
                          isOn: $translateEnabled)
                    .onChange(of: translateEnabled) { TranslateSelectionController.shared.applySettings() }
            }
            .padding(.horizontal, XFinderTokens.Space.page)
        }
    }

    // MARK: Excluded list

    private func appName(_ bid: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) else { return bid }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    private func runningApps() -> [(String, String)] {
        let own = Bundle.main.bundleIdentifier
        var seen = Set(excluded)
        return NSWorkspace.shared.runningApplications.compactMap { app -> (String, String)? in
            guard app.activationPolicy == .regular, let bid = app.bundleIdentifier, bid != own, !seen.contains(bid) else { return nil }
            seen.insert(bid)
            return (bid, app.localizedName ?? bid)
        }.sorted { $0.1.localizedCaseInsensitiveCompare($1.1) == .orderedAscending }
    }

    private func add(_ bid: String) {
        var s = SmartSelectionRules.parseExcluded(excludedRaw); s.insert(bid)
        excludedRaw = SmartSelectionRules.encodeExcluded(s)
    }

    private func remove(_ bid: String) {
        var s = SmartSelectionRules.parseExcluded(excludedRaw); s.remove(bid)
        excludedRaw = SmartSelectionRules.encodeExcluded(s)
    }
}
