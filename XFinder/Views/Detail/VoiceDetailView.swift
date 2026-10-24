import SwiftUI
import Speech
import AVFoundation
import AppKit

/// The Nhập bằng giọng nói page.
///
/// Laid out as six flat sections in the app's System-Settings style, in the order a user
/// meets them: what turns a session on, what the words become, which model does the
/// rewriting, what the floating pill does, what context is sent, and finally the permissions
/// and a live test.
///
/// Two rules from CLAUDE.md govern this file. **Every user-facing string goes through
/// `L10n.t`** — including the ones reached through a variable, like `L10n.t(mode.labelKey)`,
/// which is why `VoiceL10nTests` enumerates the vocabulary rather than sweeping literals.
/// And **no switch may be stored without a reader**: each toggle below writes a key that
/// `VoiceSettingsSnapshot.read` consumes, and the engine is re-armed on every change.
struct VoiceDetailView: View {
    @State private var voiceManager = VoiceManager.shared

    // Activation
    // Default off since 2026-10-18 (Q-PRUNE-5) — must equal VoiceManager's reader and VoiceSettingsSnapshot.defaults.
    @AppStorage(VoiceSettingsKey.enabled) private var voiceEnabled = false
    @AppStorage(VoiceSettingsKey.language) private var voiceLanguage = "vi-VN"
    @AppStorage(VoiceSettingsKey.triggerKey) private var triggerKeyRaw = VoiceTriggerKey.rightOption.rawValue
    @AppStorage(VoiceSettingsKey.activationMode) private var activationModeRaw = VoiceActivationMode.hold.rawValue

    // Dictation
    @AppStorage(VoiceSettingsKey.dictationMode) private var modeRaw = DictationMode.cleanUp.rawValue
    @AppStorage(VoiceSettingsKey.customInstruction) private var customInstruction = ""
    @AppStorage(VoiceSettingsKey.stripFillers) private var stripFillers = true
    @AppStorage(VoiceSettingsKey.autoPunctuation) private var autoPunctuation = true

    // Provider
    @AppStorage(VoiceSettingsKey.refinerTier) private var tierRaw = VoiceRefinerTier.appleOnDevice.rawValue
    @AppStorage(VoiceSettingsKey.apiProvider) private var providerRaw = APIProviderKind.openai.rawValue
    @AppStorage(VoiceSettingsKey.apiBaseURL) private var apiBaseURL = ""
    @AppStorage(VoiceSettingsKey.ollamaBaseURL) private var ollamaBaseURL = "http://localhost:11434"
    @AppStorage(VoiceSettingsKey.ollamaModel) private var ollamaModel = ""

    // Context
    @AppStorage(VoiceSettingsKey.screenContext) private var screenContext = false
    @AppStorage(VoiceSettingsKey.selectionContext) private var selectionContext = false

    // Insert & review
    @AppStorage(VoiceSettingsKey.diffReview) private var diffReview = false
    @AppStorage(VoiceSettingsKey.restoreClipboard) private var restoreClipboard = true

    // HUD
    @AppStorage(VoiceSettingsKey.hudAnchor) private var hudAnchorRaw = VoiceHUDAnchor.caret.rawValue
    @AppStorage(VoiceSettingsKey.showWaveform) private var showWaveform = true
    @AppStorage(VoiceSettingsKey.audioCues) private var audioCues = false

    // Local UI state
    @State private var apiModel = ""
    @State private var apiKeyInput = ""
    @State private var storedKeyMask: String?
    @State private var ollamaModels: [String] = []
    @State private var connectionResult: ConnectionResult?
    @State private var isTestingConnection = false
    @State private var isTestingMic = false
    @State private var testRMS: Float = 0
    @State private var testText = ""
    @State private var newModeName = ""
    @State private var newModeInstruction = ""
    @State private var customModes: [DictationMode.Custom] = []
    @State private var license = LicenseManager.shared

    private enum ConnectionResult: Equatable {
        case ok(String)
        case failure(String)
    }

    private var mode: DictationMode { DictationMode(rawValue: modeRaw) ?? .cleanUp }
    private var tier: VoiceRefinerTier { VoiceRefinerTier(rawValue: tierRaw) ?? .appleOnDevice }
    private var provider: APIProviderKind { APIProviderKind(rawValue: providerRaw) ?? .openai }
    private var triggerKey: VoiceTriggerKey { VoiceTriggerKey(rawValue: triggerKeyRaw) ?? .rightOption }
    private var activationMode: VoiceActivationMode { VoiceActivationMode(rawValue: activationModeRaw) ?? .hold }
    private var hudAnchor: VoiceHUDAnchor { VoiceHUDAnchor(rawValue: hudAnchorRaw) ?? .caret }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: XFinderTokens.Settings.sectionGap) {
                PageHeader(title: L10n.t("Nhập bằng giọng nói"),
                    subtitle: L10n.t("Nói và chữ tự vào đúng ô đang gõ — kèm tút lại văn bản bằng AI.")
                )

                activationSection
                dictationSection
                providerSection
                hudSection
                contextSection
                permissionsSection
            }
            .padding(.bottom, XFinderTokens.Space.section)
            .pageWidthSafe()
        }
        .background(XFinderTokens.Settings.contentBackground)
        .onAppear { reloadLocalState() }
        .onDisappear {
            if isTestingMic { stopMicTest() }
        }
    }
    // MARK: - 1. Activation

    private var activationSection: some View {
        SettingsSection(
            title: L10n.t("Kích hoạt & phím tắt"),
            footer: L10n.t("Chọn phím để bắt đầu nói và cách nó hoạt động.")
        ) {
            ToggleRow(
                title: L10n.t("Bật nhập bằng giọng nói"),
                subtitle: L10n.t("Cần quyền Trợ năng để nghe phím tắt toàn hệ thống."),
                isOn: Binding(
                    get: { voiceEnabled },
                    set: { voiceEnabled = $0; voiceManager.isEnabled = $0 }
                )
            )
            .settingsRow()

            SettingsDivider()

            pickerRow(
                title: L10n.t("Cách kích hoạt"),
                subtitle: L10n.t(activationMode.detailKey),
                selection: $activationModeRaw,
                options: VoiceActivationMode.allCases.map { ($0.rawValue, L10n.t($0.labelKey)) },
                width: 200
            )
            .onChange(of: activationModeRaw) { _, _ in voiceManager.applySettings() }
            .settingsRow()

            SettingsDivider()

            pickerRow(
                title: L10n.t("Phím kích hoạt"),
                subtitle: triggerKey.hintKey.map { L10n.t($0) } ?? L10n.t("Phân biệt Option Phải và Option Trái."),
                selection: $triggerKeyRaw,
                options: VoiceTriggerKey.allCases.map { ($0.rawValue, L10n.t($0.labelKey)) },
                width: 220
            )
            .onChange(of: triggerKeyRaw) { _, _ in voiceManager.applySettings() }
            .settingsRow()

            SettingsDivider()

            pickerRow(
                title: L10n.t("Ngôn ngữ nhận dạng"),
                subtitle: L10n.t("Mô hình Apple Speech Recognizer tích hợp."),
                selection: $voiceLanguage,
                options: [("vi-VN", L10n.t("Tiếng Việt (vi-VN)")), ("en-US", L10n.t("Tiếng Anh (en-US)"))],
                width: 230
            )
            .settingsRow()

            SettingsDivider()

            StatusChecklistRow(
                state: voiceManager.isEventTapInstalled ? .ok : (voiceEnabled ? .warning : .neutral),
                title: L10n.t("Bộ nghe phím toàn hệ thống"),
                status: voiceManager.isEventTapInstalled
                    ? L10n.t("Đang chạy")
                    : (voiceEnabled ? L10n.t("Chưa chạy — cần quyền Trợ năng") : L10n.t("Đang tắt")),
                actionTitle: (!voiceManager.isEventTapInstalled && voiceEnabled) ? L10n.t("Cấp quyền") : nil,
                action: { WindowManager.requestAccessibilityTrust() }
            )
            .settingsRow()
        }
    }

    // MARK: - 2. Dictation mode

    private var dictationSection: some View {
        SettingsSection(
            title: L10n.t("Chế độ gõ"),
            footer: L10n.t("Chọn lời nói của bạn biến thành dạng văn bản nào.")
        ) {
            PickerRow(
                title: L10n.t("Chọn chế độ"),
                selection: $modeRaw,
                width: 200
            ) {
                ForEach(DictationMode.builtIn) { candidate in
                    Text(L10n.t(candidate.labelKey)).tag(candidate.rawValue)
                }
            }
            .settingsRow()

            SettingsDivider()

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: mode.icon)
                    .foregroundColor(.secondary)
                    .frame(width: 16)
                Text(L10n.t(mode.detailKey))
                    .font(XFinderTokens.Font.rowValue)
                    .foregroundColor(.secondary)
                Spacer(minLength: 0)
                if mode.usesLanguageModel, !license.allows(.voiceAIRefine) {
                    Button { AppState.shared.navigate(to: .pro) } label: { ProBadge() }
                        .buttonStyle(.plain)
                        .help(L10n.t("Cần XFinder Pro — bấm để xem"))
                }
            }
            .settingsRow()

            // XF-T29: `.voiceAIRefine` gates every mode but "Chép nguyên văn" — Free still gets its words,
            // just not tút lại by AI (VoiceManager falls back to inserting the raw transcription).
            if mode.usesLanguageModel, !license.allows(.voiceAIRefine) {
                SettingsDivider()
                InlineNote(kind: .warning,
                           text: L10n.t("Cần XFinder Pro để tút văn bản bằng AI — XFinder sẽ chèn nguyên văn bạn nói thay vì chế độ này."))
                    .settingsRow()
            }

            if mode == .cleanUp {
                SettingsDivider()
                ToggleRow(
                    title: L10n.t("Bỏ từ đệm"),
                    subtitle: L10n.t("Loại “à”, “ừm”, “kiểu như”, “um”, “uh”…"),
                    isOn: $stripFillers
                )
                .settingsRow()
                SettingsDivider()
                ToggleRow(
                    title: L10n.t("Tự động thêm dấu câu"),
                    subtitle: L10n.t("Sửa nói lắp, viết hoa đầu câu và tên riêng."),
                    isOn: $autoPunctuation
                )
                .settingsRow()
            }

            if mode == .custom {
                SettingsDivider()
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.t("Câu lệnh cho AI"))
                        .font(XFinderTokens.Font.row)
                    Text(L10n.t("Ví dụ: dịch sang tiếng Anh; viết chú thích cho mã nguồn; tóm tắt thành báo cáo cuối ngày."))
                        .font(XFinderTokens.Font.caption)
                        .foregroundColor(.secondary)
                    TextEditor(text: $customInstruction)
                        .font(XFinderTokens.Font.rowValue)
                        .frame(height: 70)
                        .padding(6)
                        .background(XFinderTokens.Fill.inset)
                        .clipShape(RoundedRectangle(cornerRadius: XFinderTokens.Radius.control))
                }
                .settingsRow()
                SettingsDivider()
                customModeLibrary
                    .settingsRow()
            }
        }
    }

    private var customModeLibrary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.t("Thư viện câu lệnh"))
                .font(XFinderTokens.Font.row)
            Text(L10n.t("Lưu sẵn những câu lệnh bạn hay dùng để chọn nhanh."))
                .font(XFinderTokens.Font.caption)
                .foregroundColor(.secondary)

            ForEach(customModes) { item in
                HStack(spacing: 8) {
                    Text(item.name)
                        .font(XFinderTokens.Font.rowValue)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    Text(item.instruction)
                        .font(XFinderTokens.Font.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                    Button(L10n.t("Dùng")) { customInstruction = item.instruction }
                        .buttonStyle(.link)
                    Button(L10n.t("Xóa")) { removeCustomMode(item) }
                        .buttonStyle(.link)
                }
            }

            HStack(spacing: 8) {
                TextField(L10n.t("Tên"), text: $newModeName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 140)
                TextField(L10n.t("Câu lệnh"), text: $newModeInstruction)
                    .textFieldStyle(.roundedBorder)
                Button(L10n.t("Thêm")) { addCustomMode() }
                    .disabled(newModeName.trimmingCharacters(in: .whitespaces).isEmpty
                              || newModeInstruction.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    // MARK: - 3. Provider

    private var providerSection: some View {
        SettingsSection(
            title: L10n.t("Mô hình AI tút văn bản"),
            footer: L10n.t("Chọn nơi xử lý văn bản. Chế độ “Chép nguyên văn” không cần mục này.")
        ) {
            Picker("", selection: $tierRaw) {
                ForEach(VoiceRefinerTier.allCases) { candidate in
                    Text(L10n.t(candidate.labelKey)).tag(candidate.rawValue)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 320, alignment: .leading)
            .settingsRow()

            SettingsDivider()

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: tier.icon).foregroundColor(.secondary).frame(width: 16)
                Text(L10n.t(tier.detailKey)).font(XFinderTokens.Font.rowValue).foregroundColor(.secondary)
                Spacer(minLength: 0)
            }
            .settingsRow()

            SettingsDivider()

            Group {
                switch tier {
                case .appleOnDevice: appleTierBody
                case .ollama: ollamaTierBody
                case .customAPI: apiTierBody
                case .subscription: subscriptionTierBody
                }
            }
            .settingsRow()

            if let connectionResult {
                SettingsDivider()
                connectionResultRow(connectionResult)
                    .settingsRow()
            }
        }
    }

    private var appleTierBody: some View {
        let reason = AppleOnDeviceRefiner().unavailableReason()
        return VStack(alignment: .leading, spacing: 8) {
            StatusChecklistRow(
                state: reason == nil ? .ok : .warning,
                title: L10n.t("Apple Intelligence trên máy"),
                status: reason == nil ? L10n.t("Sẵn sàng") : L10n.t(reason!),
                actionTitle: nil,
                action: {}
            )
            Text(L10n.t("Văn bản không rời khỏi máy này. Miễn phí và không cần mạng."))
                .font(XFinderTokens.Font.caption)
                .foregroundColor(.secondary)
        }
    }

    private var ollamaTierBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            labeledField(title: L10n.t("Địa chỉ Ollama"), text: $ollamaBaseURL, placeholder: "http://localhost:11434")

            HStack(spacing: 8) {
                Text(L10n.t("Mô hình"))
                    .font(XFinderTokens.Font.row)
                    .frame(width: 110, alignment: .leading)
                if ollamaModels.isEmpty {
                    TextField(L10n.t("ví dụ: qwen2.5:7b"), text: $ollamaModel)
                        .textFieldStyle(.roundedBorder)
                } else {
                    Picker("", selection: $ollamaModel) {
                        Text(L10n.t("Chưa chọn")).tag("")
                        ForEach(ollamaModels, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 260)
                }
                Button(L10n.t("Tải danh sách")) { loadOllamaModels() }
                    .disabled(isTestingConnection)
            }

            if ollamaModels.isEmpty {
                Text(L10n.t("Chưa đọc được danh sách mô hình. Hãy chắc rằng Ollama đang chạy."))
                    .font(XFinderTokens.Font.caption)
                    .foregroundColor(.secondary)
            }

            testButton
        }
    }

    private var apiTierBody: some View {
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
                Spacer(minLength: 0)
            }

            if provider == .custom {
                labeledField(title: L10n.t("Địa chỉ API"), text: $apiBaseURL, placeholder: "https://…/v1")
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

            HStack(spacing: 8) {
                Text(L10n.t("Mô hình"))
                    .font(XFinderTokens.Font.row)
                    .frame(width: 110, alignment: .leading)
                TextField(provider.defaultModel, text: $apiModel)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 260)
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
                Spacer(minLength: 0)
            }

            testButton
        }
        .onChange(of: apiModel) { _, _ in persistAPIModel() }
        .onChange(of: providerRaw) { _, _ in reloadLocalState() }
    }

    private var subscriptionTierBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            StatusChecklistRow(
                state: .warning,
                title: L10n.t("Chưa hỗ trợ đăng nhập tài khoản"),
                status: L10n.t("Không khả dụng"),
                actionTitle: nil,
                action: {}
            )
            Text(L10n.t("ChatGPT Plus và Claude Pro không cấp quyền dùng API qua đăng nhập. Cách duy nhất để dùng chúng một cách chính thức là tạo khoá API ở trang quản trị của nhà cung cấp — XFinder không đăng nhập hộ và không dùng phiên trình duyệt của bạn."))
                .font(XFinderTokens.Font.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Button(L10n.t("Dùng khoá API thay thế")) { tierRaw = VoiceRefinerTier.customAPI.rawValue }
                Spacer(minLength: 0)
            }
        }
    }

    private var testButton: some View {
        HStack(spacing: 10) {
            Button(action: testConnection) {
                HStack(spacing: 6) {
                    if isTestingConnection { ProgressView().controlSize(.small) }
                    Text(L10n.t("Kiểm tra kết nối"))
                }
            }
            .disabled(isTestingConnection)
            Spacer(minLength: 0)
        }
    }

    private func connectionResultRow(_ result: ConnectionResult) -> some View {
        HStack(alignment: .top, spacing: 8) {
            switch result {
            case .ok(let text):
                Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t("Kết nối thành công"))
                        .font(XFinderTokens.Font.rowValue)
                        .fontWeight(.semibold)
                    Text(text)
                        .font(XFinderTokens.Font.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(3)
                }
            case .failure(let text):
                Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t("Kết nối thất bại"))
                        .font(XFinderTokens.Font.rowValue)
                        .fontWeight(.semibold)
                    Text(text)
                        .font(XFinderTokens.Font.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - 4. HUD

    private var hudSection: some View {
        SettingsSection(
            title: L10n.t("Thanh trạng thái nổi"),
            footer: L10n.t("Vị trí và phản hồi khi đang nói.")
        ) {
            pickerRow(
                title: L10n.t("Vị trí hiển thị"),
                subtitle: L10n.t(hudAnchor.detailKey),
                selection: $hudAnchorRaw,
                options: VoiceHUDAnchor.allCases.map { ($0.rawValue, L10n.t($0.labelKey)) },
                width: 220
            )
            .onChange(of: hudAnchorRaw) { _, _ in voiceManager.applySettings() }
            .settingsRow()

            SettingsDivider()
            ToggleRow(
                title: L10n.t("Hiện sóng âm"),
                subtitle: L10n.t("Dải sóng nhấp nhô theo giọng nói thật."),
                isOn: $showWaveform
            )
            .settingsRow()

            SettingsDivider()
            ToggleRow(
                title: L10n.t("Âm báo bắt đầu / kết thúc"),
                subtitle: L10n.t("Một tiếng “tách” rất nhẹ để không phải nhìn màn hình."),
                isOn: $audioCues
            )
            .settingsRow()

            SettingsDivider()
            ToggleRow(
                title: L10n.t("Xem lại trước khi chèn"),
                subtitle: L10n.t("Hiện bảng so sánh chữ gốc và chữ đã tút. Return để chèn, Esc để hủy."),
                isOn: $diffReview
            )
            .settingsRow()

            SettingsDivider()
            ToggleRow(
                title: L10n.t("Khôi phục clipboard"),
                subtitle: L10n.t("Trả lại nội dung clipboard cũ sau khi dán. Tắt nếu bạn muốn giữ văn bản vừa nói."),
                isOn: $restoreClipboard
            )
            .onChange(of: restoreClipboard) { _, _ in voiceManager.applySettings() }
            .settingsRow()
        }
    }

    // MARK: - 5. Context

    private var contextSection: some View {
        SettingsSection(
            title: L10n.t("Ngữ cảnh màn hình"),
            footer: L10n.t("Cho AI biết bạn đang viết trong ứng dụng nào, để câu chữ hợp ngữ cảnh hơn.")
        ) {
            ToggleRow(
                title: L10n.t("Gửi tên ứng dụng và tiêu đề cửa sổ"),
                subtitle: L10n.t("Ví dụ: đang trả lời trong Mail thì AI biết đó là email."),
                isOn: $screenContext
            )
            .settingsRow()

            SettingsDivider()
            ToggleRow(
                title: L10n.t("Gửi đoạn văn bản đang bôi đen"),
                subtitle: L10n.t("Chỉ đọc khi bạn đã bôi đen. Nội dung này được gửi tới nhà cung cấp AI bạn chọn."),
                isOn: $selectionContext
            )
            .settingsRow()

            SettingsDivider()
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "lock.shield").font(XFinderTokens.Font.rowValue).foregroundColor(.secondary).frame(width: 16)
                Text(L10n.t("Không có ảnh chụp màn hình nào được gửi. XFinder chỉ đọc tên ứng dụng, tiêu đề cửa sổ và đoạn bạn bôi đen, và chỉ khi bạn bật ở trên."))
                    .font(XFinderTokens.Font.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .settingsRow()
        }
    }

    // MARK: - 6. Permissions & live test

    private var permissionsSection: some View {
        SettingsSection(
            title: L10n.t("Quyền & thử nghiệm"),
            footer: L10n.t("Kiểm tra quyền hệ thống và thử micro ngay tại đây.")
        ) {
            StatusChecklistRow(
                state: WindowManager.isTrusted ? .ok : .warning,
                title: L10n.t("Quyền Trợ năng (Accessibility)"),
                status: WindowManager.isTrusted ? L10n.t("Đã cấp") : L10n.t("Cần cấp quyền"),
                actionTitle: WindowManager.isTrusted ? nil : L10n.t("Cấp quyền"),
                action: { WindowManager.requestAccessibilityTrust() }
            )
            .settingsRow()

            SettingsDivider()
            StatusChecklistRow(
                state: voiceManager.hasMicrophonePermission ? .ok : .warning,
                title: L10n.t("Quyền Micro (Microphone)"),
                status: voiceManager.hasMicrophonePermission ? L10n.t("Đã cấp") : L10n.t("Cần cấp quyền"),
                actionTitle: voiceManager.hasMicrophonePermission ? nil : L10n.t("Yêu cầu"),
                action: { Task { _ = await voiceManager.checkAndRequestPermissions() } }
            )
            .settingsRow()

            SettingsDivider()
            StatusChecklistRow(
                state: voiceManager.hasSpeechPermission ? .ok : .warning,
                title: L10n.t("Quyền Nhận dạng giọng nói"),
                status: voiceManager.hasSpeechPermission ? L10n.t("Đã cấp") : L10n.t("Cần cấp quyền"),
                actionTitle: voiceManager.hasSpeechPermission ? nil : L10n.t("Yêu cầu"),
                action: { Task { _ = await voiceManager.checkAndRequestPermissions() } }
            )
            .settingsRow()

            SettingsDivider()
            VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
                HStack(spacing: 12) {
                    Button(action: toggleMicTest) {
                        HStack(spacing: 6) {
                            Image(systemName: isTestingMic ? "stop.fill" : "mic.fill")
                                .foregroundColor(isTestingMic ? .red : .blue)
                            Text(isTestingMic ? L10n.t("Dừng thử nghiệm") : L10n.t("Thử micro"))
                        }
                    }
                    .buttonStyle(.borderedProminent)

                    if isTestingMic {
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: XFinderTokens.Radius.badge).fill(XFinderTokens.Fill.inset)
                                RoundedRectangle(cornerRadius: XFinderTokens.Radius.badge)
                                    .fill(LinearGradient(colors: [.blue, .green, .red],
                                                         startPoint: .leading, endPoint: .trailing))
                                    .frame(width: max(4, geometry.size.width * CGFloat(testRMS)))
                            }
                        }
                        .frame(height: 12)
                        .frame(maxWidth: 180)
                    }
                    Spacer(minLength: 0)
                }

                if !testText.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.t("Kết quả nhận dạng:"))
                            .font(XFinderTokens.Font.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                        Text(testText)
                            .font(XFinderTokens.Font.row)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(XFinderTokens.Fill.inset)
                            .cornerRadius(XFinderTokens.Radius.control)
                    }
                }
            }
            .settingsRow()
        }
    }

    // MARK: - Shared row helpers

    private func pickerRow(
        title: String,
        subtitle: String,
        selection: Binding<String>,
        options: [(String, String)],
        width: CGFloat
    ) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(XFinderTokens.Font.row)
                Text(subtitle).font(XFinderTokens.Font.caption).foregroundColor(.secondary)
            }
            Spacer(minLength: 12)
            Picker("", selection: selection) {
                ForEach(options, id: \.0) { Text($0.1).tag($0.0) }
            }
            .labelsHidden()
            .frame(width: width)
        }
    }

    private func labeledField(title: String, text: Binding<String>, placeholder: String) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(XFinderTokens.Font.row)
                .frame(width: 110, alignment: .leading)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Local state

    private func reloadLocalState() {
        apiModel = UserDefaults.standard.string(forKey: VoiceSettingsKey.apiModel(for: provider)) ?? ""
        storedKeyMask = VoiceKeychain.maskedKey(for: provider)
        apiKeyInput = ""
        connectionResult = nil
        customModes = loadCustomModes()
    }

    private func persistAPIModel() {
        UserDefaults.standard.set(apiModel, forKey: VoiceSettingsKey.apiModel(for: provider))
    }

    private func saveAPIKey() {
        guard VoiceConfig.looksLikeAPIKey(apiKeyInput) else {
            connectionResult = .failure(L10n.t("Chuỗi vừa dán không giống một khoá API."))
            return
        }
        if VoiceKeychain.setAPIKey(apiKeyInput, for: provider) {
            apiKeyInput = ""
            storedKeyMask = VoiceKeychain.maskedKey(for: provider)
            connectionResult = nil
        } else {
            connectionResult = .failure(L10n.t("Không ghi được vào Keychain."))
        }
    }

    private func clearAPIKey() {
        VoiceKeychain.deleteAPIKey(for: provider)
        storedKeyMask = nil
        connectionResult = nil
    }

    // MARK: - Custom mode library

    private func loadCustomModes() -> [DictationMode.Custom] {
        guard let data = UserDefaults.standard.data(forKey: VoiceSettingsKey.customModes),
              let decoded = try? JSONDecoder().decode([DictationMode.Custom].self, from: data) else {
            return []
        }
        return decoded
    }

    private func persistCustomModes() {
        guard let data = try? JSONEncoder().encode(customModes) else { return }
        UserDefaults.standard.set(data, forKey: VoiceSettingsKey.customModes)
    }

    private func addCustomMode() {
        let name = newModeName.trimmingCharacters(in: .whitespacesAndNewlines)
        let instruction = newModeInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !instruction.isEmpty else { return }
        customModes.append(DictationMode.Custom(name: name, instruction: instruction))
        persistCustomModes()
        newModeName = ""
        newModeInstruction = ""
    }

    private func removeCustomMode(_ item: DictationMode.Custom) {
        customModes.removeAll { $0.id == item.id }
        persistCustomModes()
    }

    // MARK: - Connection test

    /// Prove the configured provider actually answers, with a real round trip.
    ///
    /// `isAvailable()` alone would only prove a key string exists — a wrong key would still
    /// look "available". Asking for one short rewrite is the only test that distinguishes
    /// "configured" from "working", and the provider's own error text is shown verbatim
    /// because that is what tells the user their key is wrong rather than their network.
    private func testConnection() {
        isTestingConnection = true
        connectionResult = nil
        let snapshot = VoiceSettingsSnapshot.read()

        Task {
            defer { isTestingConnection = false }

            if snapshot.mode == .raw {
                connectionResult = .ok(L10n.t("Chế độ “Chép nguyên văn” không dùng AI, không cần kiểm tra."))
                return
            }

            guard let refiner = VoiceRefinerFactory.make(
                tier: snapshot.tier,
                provider: snapshot.provider,
                apiBaseURL: snapshot.apiBaseURL,
                apiModel: snapshot.apiModel,
                ollamaBaseURL: snapshot.ollamaBaseURL,
                ollamaModel: snapshot.ollamaModel
            ) else {
                connectionResult = .failure(L10n.t("Chưa cấu hình đủ để kết nối. Hãy kiểm tra khoá API và tên mô hình."))
                return
            }

            let probe = RefineRequest(
                text: "xin chào đây là câu thử",
                messages: RefinePrompt.messages(
                    mode: .cleanUp, customInstruction: nil, stripFillers: true,
                    autoPunctuation: true, context: nil,
                    text: "xin chào đây là câu thử", locale: snapshot.language
                ),
                contextSummary: nil
            )

            do {
                let result = try await refiner.refine(probe)
                connectionResult = .ok(String(result.prefix(160)))
            } catch let error as RefinerError {
                // `messageKey` is a key; `detail` is either a key (the on-device reasons) or
                // already-localised/technical text. Both go through `L10n.t`, which returns
                // the input unchanged on a miss — so the provider's own error text is shown
                // verbatim while every app-authored string still translates.
                let detail = error.detail.map { L10n.t($0) } ?? L10n.t(error.messageKey)
                connectionResult = .failure(detail)
            } catch {
                connectionResult = .failure(error.localizedDescription)
            }
        }
    }

    // MARK: - Ollama models

    private func loadOllamaModels() {
        isTestingConnection = true
        let base = ollamaBaseURL
        Task {
            defer { isTestingConnection = false }
            let models = await OllamaRefiner(baseURL: base, model: "probe").listModels()
            ollamaModels = models ?? []
            if let first = ollamaModels.first, ollamaModel.isEmpty { ollamaModel = first }
            if ollamaModels.isEmpty {
                connectionResult = .failure(L10n.t("Không kết nối được Ollama tại địa chỉ đã nhập."))
            } else {
                connectionResult = .ok("\(ollamaModels.count)\(L10n.t(" mô hình đã tải"))")
            }
        }
    }

    // MARK: - Microphone test

    private func toggleMicTest() {
        if isTestingMic { stopMicTest() } else { startMicTest() }
    }

    private func startMicTest() {
        isTestingMic = true
        testText = ""
        AudioCapture.shared.onRMSUpdate = { _, normalized in
            Task { @MainActor in self.testRMS = normalized }
        }
        do {
            try AudioCapture.shared.start()
        } catch {
            testText = L10n.t("Không mở được Micro")
            isTestingMic = false
        }
    }

    private func stopMicTest() {
        isTestingMic = false
        _ = AudioCapture.shared.stop()
        AudioCapture.shared.onRMSUpdate = nil
        testRMS = 0
    }
}
