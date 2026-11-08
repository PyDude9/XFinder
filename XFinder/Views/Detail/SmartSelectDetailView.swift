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
    @AppStorage("translate.showGoogle") private var showGoogle = true
    @AppStorage("translate.showDictionary") private var showDictionary = true
    @AppStorage("translate.showAI") private var showAI = false
    @State private var trusted = WindowManager.isTrusted
    // E6 — ONE reader: CurrencyRateStore.
    @AppStorage("smartSelect.currency") private var currencyEnabled = false
    private var rates: CurrencyRateStore { CurrencyRateStore.shared }

    // AI Provider configuration (unified with Voice keys)
    @AppStorage(VoiceSettingsKey.apiProvider) private var providerRaw = VoiceSettingsSnapshot.defaults.provider.rawValue
    @AppStorage(VoiceSettingsKey.apiBaseURL) private var apiBaseURL = VoiceSettingsSnapshot.defaults.apiBaseURL
    @State private var apiModel = ""
    @State private var apiKeyInput = ""
    @State private var storedKeyMask: String?
    @State private var keySaveStatus: String?

    private var provider: APIProviderKind {
        APIProviderKind(rawValue: providerRaw) ?? .openai
    }

    private var excluded: [String] { SmartSelectionRules.parseExcluded(excludedRaw).sorted() }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: XFinderTokens.Settings.sectionGap) {
                PageHeader(title: L10n.t("Chọn văn bản thông minh"),
                           subtitle: L10n.t("Bôi đen chữ ở app khác: một nút nhỏ hiện cạnh đó để đổi đơn vị, đổi múi giờ, tính, thêm vào Lịch hoặc dịch."))
                Button(L10n.t("Mở Dịch & Sổ từ vựng")) { VocabularyWorkspaceController.shared.show() }
                    .buttonStyle(.borderedProminent)
                badgeSection
                excludedSection
                actionsSection
                hotkeySection
            }
            .padding(.bottom, 24)
            .pageWidthSafe()
        }
        .background(XFinderTokens.Settings.contentBackground)
        .onAppear {
            trusted = WindowManager.isTrusted
            if showAI { reloadAIState() }
        }
    }

    private var badgeSection: some View {
        SettingsSection(title: L10n.t("Nút trên vùng chọn"),
                        footer: L10n.t("Chỉ hiện khi bạn bôi đen bằng chuột và vùng chọn đã đứng yên.")) {
            ToggleRow(title: L10n.t("Hiện nút khi bôi đen chữ"),
                      subtitle: L10n.t("Đọc vùng chọn của app đang dùng qua Trợ năng. Không ghi lại, không gửi đi; chữ chỉ được giữ tới lần bôi đen kế tiếp."),
                      isOn: $enabled)
                .onChange(of: enabled) { SelectionWatcher.shared.applySettings() }
                .settingsRow()
            if enabled && !trusted {
                SettingsDivider()
                InlineNote(kind: .warning,
                           text: L10n.t("Cần quyền Trợ năng để đọc vùng chọn của app khác."),
                           buttonTitle: L10n.t("Cấp quyền Trợ năng")) {
                    WindowManager.requestAccessibilityTrust()
                }
                .settingsRow()
            }
            SettingsDivider()
            PickerRow(title: L10n.t("Độ dài tối thiểu (ký tự)"),
                      subtitle: L10n.t("Bỏ qua vùng chọn ngắn hơn để nút không hiện khi bấm nhầm."),
                      selection: $minLength, width: 90) {
                ForEach(SmartSelectionRules.minLengthChoices, id: \.self) { n in Text("\(n)").tag(n) }
            }
            .disabled(!enabled)
            .settingsRow()
            SettingsDivider()
            InlineNote(text: L10n.t("Vùng chọn bằng bàn phím không hiện nút vì không biết nó nằm đâu trên màn hình — dùng ⇧⌘G. Một số app không cho Trợ năng đọc vùng chọn; khi đó nút không hiện."))
                .settingsRow()
        }
    }

    private var excludedSection: some View {
        SettingsSection(title: L10n.t("Không hiện trong các app này"),
                        footer: L10n.t("Trình chỉnh ảnh, bảng vẽ, game — nơi kéo chuột không phải là bôi đen chữ. Trình quản lý mật khẩu luôn bị bỏ qua.")) {
            if excluded.isEmpty {
                Text(L10n.t("Chưa loại trừ app nào.")).font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                    .settingsRow()
            }
            ForEach(Array(excluded.enumerated()), id: \.element) { entry in
                if excluded.isEmpty == false, entry.offset > 0 { SettingsDivider() }
                HStack {
                    Text(appName(entry.element)).font(XFinderTokens.Font.row)
                        .lineLimit(1).truncationMode(.middle).frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                    Button(L10n.t("Bỏ")) { remove(entry.element) }.controlSize(.small)
                }
                .settingsRow()
            }
            if !excluded.isEmpty { SettingsDivider() }
            HStack {
                Menu(L10n.t("Thêm app đang chạy")) {
                    ForEach(runningApps(), id: \.0) { bid, name in
                        Button(name) { add(bid) }
                    }
                }
                .frame(width: 200)
                Spacer()
            }
            .settingsRow()
        }
    }

    private var actionsSection: some View {
        SettingsSection(title: L10n.t("Nút làm được gì"),
                        footer: L10n.t("Chỉ hiện những việc hợp với chữ đã chọn, việc cụ thể nhất lên đầu.")) {
            LabeledLine(label: L10n.t("Đổi đơn vị"), value: "5 km ≈ 3.11 mi · 72°F ≈ 22.22°C")
                .settingsRow()
            SettingsDivider()
            LabeledLine(label: L10n.t("Đổi múi giờ"), value: "3pm PST = 06:00")
                .settingsRow()
            SettingsDivider()
            LabeledLine(label: L10n.t("Tính"), value: "12 * (3 + 4) = 84")
                .settingsRow()
            SettingsDivider()
            LabeledLine(label: L10n.t("Đổi tiền tệ"), value: "$20 ≈ 522,200 VND")
                .settingsRow()
            SettingsDivider()
            LabeledLine(label: L10n.t("Thêm vào Lịch"), value: L10n.t("Họp nhóm thứ Sáu 9 giờ"))
                .settingsRow()
            SettingsDivider()
            LabeledLine(label: L10n.t("Dịch"), value: L10n.t("macOS 15 trở lên, ngay trên máy"))
                .settingsRow()
            SettingsDivider()
            currencyControls
            SettingsDivider()
            InlineNote(text: L10n.t("Múi giờ viết tắt có nhiều nghĩa (CST, IST, BST…) bị bỏ qua thay vì đoán. EST, PST… dùng đúng định nghĩa; nếu vùng đó đang dùng giờ mùa hè, panel ghi chú. Thêm vào Lịch chỉ ghi khi bạn bấm nút, và hỏi quyền Lịch lần đầu."))
                .settingsRow()
        }
    }

    /// E6 — the only network action of Smart Selection, so its label says what is sent and where.
    @ViewBuilder private var currencyControls: some View {
        if let local = rates.localCurrency, let source = rates.source {
            VStack(alignment: .leading, spacing: XFinderTokens.Space.tight) {
                ToggleRow(title: L10n.t("Đổi tiền tệ (cần mạng)"),
                          subtitle: source == .vietcombank
                            ? L10n.t("Khi bạn bôi đen một số tiền, tải bảng tỷ giá công khai từ portal.vietcombank.com.vn, tối đa 12 giờ một lần. Không gửi chữ bạn chọn. Đổi ra VND theo giá bán của Vietcombank.")
                            : "\(L10n.t("Khi bạn bôi đen một số tiền, tải tỷ giá tham chiếu công khai của Ngân hàng Trung ương châu Âu (www.ecb.europa.eu), tối đa 12 giờ một lần. Không gửi chữ bạn chọn. Đổi ra: "))\(local)",
                          isOn: $currencyEnabled)
                    .onChange(of: currencyEnabled) { rates.applySettings() }
                    .disabled(!enabled)
                if currencyEnabled {
                    Text(rateStatus).font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                }
            }
            .settingsRow()
        } else {
            InlineNote(text: "\(L10n.t("Vùng của macOS dùng "))\(rates.localCurrency ?? "?")\(L10n.t(" — chưa có nguồn tỷ giá công khai cho đồng này, nên không có đổi tiền tệ."))")
                .settingsRow()
        }
    }

    private var rateStatus: String {
        if rates.inFlight { return L10n.t("Đang tải bảng tỷ giá…") }
        guard let t = rates.table, t.source == rates.source else {
            return rates.lastFailure == nil ? L10n.t("Chưa tải bảng tỷ giá — sẽ tải khi bạn bôi đen một số tiền.")
                                            : L10n.t("Lần tải gần nhất thất bại; XFinder thử lại sau ít phút.")
        }
        let f = DateFormatter()
        f.locale = Locale(identifier: L10n.isEnglish ? "en_US" : "vi_VN")
        f.dateFormat = t.publishedHasTime ? "dd/MM/yyyy HH:mm" : "dd/MM/yyyy"
        if !t.publishedHasTime { f.timeZone = TimeZone(identifier: "UTC") }
        return "\(L10n.t("Bảng tỷ giá đang dùng: "))\(f.string(from: t.published)), \(t.rates.count)\(L10n.t(" đồng tiền."))"
    }

    /// N5a — moved from the Voice page.
    private var hotkeySection: some View {
        SettingsSection(title: L10n.t("Dịch vùng chọn (⇧⌘G)"),
                        footer: L10n.t("Bôi đen chữ ở app bất kỳ, bấm ⇧⌘G hoặc bấm nút Dịch trên vùng chọn để xem các bản dịch đồng thời.")) {
            ToggleRow(title: L10n.t("Bật phím ⇧⌘G dịch vùng chọn"),
                      subtitle: L10n.t("Đọc chữ đang bôi đen qua Trợ năng rồi mở thẻ dịch. Từ điển macOS chạy trên máy; Google Dịch và Dịch AI, khi bật, gửi chữ bạn chọn tới dịch vụ đó. App nào không cho Trợ năng đọc vùng chọn thì panel nói rõ."),
                      isOn: $translateEnabled)
                .onChange(of: translateEnabled) { TranslateSelectionController.shared.applySettings() }
                .settingsRow()
            if translateEnabled {
                SettingsDivider()
                Text(L10n.t("Dịch vụ hiển thị khi dịch"))
                    .font(XFinderTokens.Font.row)
                    .bold()
                    .settingsRow()
                ToggleRow(title: L10n.t("Google Dịch (Miễn phí, nhanh)"),
                          subtitle: L10n.t("Gửi chữ bạn bôi đen tới Google qua một địa chỉ không chính thức (không cần khoá API, ~200 ms). Google có thể chặn hay đổi địa chỉ này bất cứ lúc nào; tắt nếu chữ bạn chọn không được rời máy."),
                          isOn: $showGoogle)
                    .settingsRow()
                SettingsDivider()
                ToggleRow(title: L10n.t("Từ điển macOS (Nhanh trên máy, tra từ loại)"),
                          subtitle: L10n.t("Tra cứu từ điển tích hợp sẵn trên macOS, hiển thị phân loại danh từ, động từ, tính từ."),
                          isOn: $showDictionary)
                    .settingsRow()
                SettingsDivider()
                ToggleRow(title: L10n.t("Dịch bằng AI (Mô hình ngôn ngữ lớn)"),
                          subtitle: L10n.t("Dịch ngữ cảnh, phân tích sâu và gợi ý từ đồng nghĩa bằng OpenAI, Claude, DeepSeek hoặc Bedrock."),
                          isOn: $showAI)
                    .onChange(of: showAI) {
                        if showAI {
                            reloadAIState()
                        }
                    }
                    .settingsRow()
                if showAI {
                    SettingsDivider()
                    aiConfigSection
                }
                SettingsDivider()
                InlineNote(kind: .warning,
                           text: L10n.t("Khi bật, ⇧⌘G sẽ thay thế \"Find Next\" (tìm tiếp) trong mọi ứng dụng khác trên máy."))
                    .settingsRow()
            }
            SettingsDivider()
            SettingsLinkRow(title: L10n.t("Xem trong Phím tắt"), destination: .shortcuts)
        }
    }

    private var aiConfigSection: some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
            HStack(spacing: 8) {
                Text(L10n.t("Nhà cung cấp"))
                    .font(XFinderTokens.Font.row)
                    .frame(width: 110, alignment: .leading)
                Picker("", selection: $providerRaw) {
                    ForEach(APIProviderKind.allCases) { Text(L10n.t($0.labelKey)).tag($0.rawValue) }
                }
                .labelsHidden()
                .frame(width: 280)
                .onChange(of: providerRaw) {
                    reloadAIState()
                }
                Spacer(minLength: 0)
            }

            if provider == .custom {
                HStack(spacing: 8) {
                    Text(L10n.t("Địa chỉ API"))
                        .font(XFinderTokens.Font.row)
                        .frame(width: 110, alignment: .leading)
                    TextField("https://…/v1", text: $apiBaseURL)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            UserDefaults.standard.set(apiBaseURL, forKey: VoiceSettingsKey.apiBaseURL)
                        }
                        .onChange(of: apiBaseURL) {
                            UserDefaults.standard.set(apiBaseURL, forKey: VoiceSettingsKey.apiBaseURL)
                        }
                    Spacer(minLength: 0)
                }
            }

            HStack(spacing: 8) {
                Text(L10n.t("Khoá API"))
                    .font(XFinderTokens.Font.row)
                    .frame(width: 110, alignment: .leading)
                SecureField(storedKeyMask ?? L10n.t("Dán khoá API"), text: $apiKeyInput)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { saveAPIKey() }
                Button(L10n.t("Lưu")) { saveAPIKey() }
                    .disabled(apiKeyInput.trimmingCharacters(in: .whitespaces).isEmpty)
                if storedKeyMask != nil {
                    Button(L10n.t("Xóa")) { clearAPIKey() }
                }
            }

            if let status = keySaveStatus {
                Text(status)
                    .font(XFinderTokens.Font.caption)
                    .foregroundColor(.accentColor)
                    .padding(.leading, 118)
            }

            HStack(spacing: 8) {
                Text(L10n.t("Mô hình"))
                    .font(XFinderTokens.Font.row)
                    .frame(width: 110, alignment: .leading)
                TextField(provider.defaultModel.isEmpty ? L10n.t("ví dụ: qwen2.5:7b") : provider.defaultModel, text: $apiModel)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 260)
                    .onSubmit { persistAPIModel() }
                    .onChange(of: apiModel) { persistAPIModel() }
                if !provider.suggestedModels.isEmpty {
                    Menu(L10n.t("Gợi ý")) {
                        ForEach(provider.suggestedModels, id: \.self) { name in
                            Button(name) { apiModel = name; persistAPIModel() }
                        }
                    }
                    .frame(width: 90)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 6) {
                Image(systemName: "lock.fill").font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                Text(L10n.t("Khoá được lưu trong Keychain của macOS, không nằm trong tệp cấu hình."))
                    .font(XFinderTokens.Font.caption)
                    .foregroundColor(.secondary)
                if !provider.consoleURL.isEmpty, let url = URL(string: provider.consoleURL) {
                    Button(L10n.t("Lấy khoá")) { NSWorkspace.shared.open(url) }
                        .buttonStyle(.link)
                }
            }
        }
        .padding(.vertical, 4)
        .settingsRow()
    }

    private func reloadAIState() {
        apiModel = UserDefaults.standard.string(forKey: VoiceSettingsKey.apiModel(for: provider)) ?? ""
        storedKeyMask = VoiceKeychain.maskedKey(for: provider)
        apiKeyInput = ""
        keySaveStatus = nil
    }

    private func persistAPIModel() {
        UserDefaults.standard.set(apiModel, forKey: VoiceSettingsKey.apiModel(for: provider))
    }

    private func saveAPIKey() {
        let trimmed = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard VoiceConfig.looksLikeAPIKey(trimmed) else {
            keySaveStatus = L10n.t("Chuỗi vừa dán không giống một khoá API.")
            return
        }
        if VoiceKeychain.setAPIKey(trimmed, for: provider) {
            apiKeyInput = ""
            storedKeyMask = VoiceKeychain.maskedKey(for: provider)
            keySaveStatus = L10n.t("Đã lưu khoá API vào Keychain.")
        } else {
            keySaveStatus = L10n.t("Không ghi được vào Keychain.")
        }
    }

    private func clearAPIKey() {
        VoiceKeychain.deleteAPIKey(for: provider)
        storedKeyMask = nil
        keySaveStatus = L10n.t("Đã xóa khoá API.")
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
