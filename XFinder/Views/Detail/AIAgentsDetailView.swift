import SwiftUI

/// Agent AI — the user comes here to put their coding-agent sessions (Claude Code, Codex since P5) on the notch,
/// to install or remove the hook that makes that possible for each agent, and to see Claude's own 5h/7d usage %
/// via an opt-in statusLine. Split off "Notch & Khay thả" (P3); every install path edits a file outside the app
/// (~/.claude/settings.json, ~/.codex/hooks.json), so they are buttons, never switches.
struct AIAgentsDetailView: View {
    // N3
    @AppStorage("dropTray.notchEnabled") private var notchEnabled = true
    @AppStorage("agents.enabled") private var agentsEnabled = false
    @State private var hookStatus: AgentSessionMonitor.HookStatus = .notInstalled
    @State private var hookNotice: String?
    // P5a — Codex
    @State private var codexHookStatus: AgentSessionMonitor.HookStatus = .notInstalled
    @State private var codexNotice: String?
    @State private var lastEventAt: [AgentKind: Date] = [:]
    @State private var otherPermissionHooks: [AgentKind: Int] = [:]
    // P5b — OpenCode
    @AppStorage("agents.opencode") private var openCodeEnabled = false
    @State private var openCodeState: OpenCodeMonitor.State = .off
    @State private var openCodeBinary: String?
    // P5c — notices + recent sessions
    @AppStorage("agents.notify.permission") private var notifyPermission = true
    @AppStorage("agents.notify.finished") private var notifyFinished = true
    @AppStorage("agents.notify.sound") private var notifySound = false
    @AppStorage("agents.notify.quietWhenFront") private var notifyQuietWhenFront = true
    @AppStorage("agents.sortMode") private var sortMode = "priority"
    @AppStorage("agents.keepFinished") private var keepFinished = true
    @AppStorage("notch.agentEdgeHover") private var agentEdgeHover = true
    @State private var recent: [AgentRecent.Entry] = []
    @State private var copiedID: String?
    // P2 — Claude Code statusLine (5h/7d usage %), a settings-only opt-in.
    @State private var statusLineState: AgentSessionMonitor.StatusLineState = .notInstalled
    @State private var statusLineNotice: String?
    // P7a — windowless Claude Code sessions hosted by XFinder itself.
    @State private var windowlessFolder: URL?
    @State private var windowlessMessage = ""
    @State private var windowlessStarting = false
    @State private var windowlessClaudeOK: Bool?
    @State private var windowlessNotice: String?
    @State private var windowlessNoticeIsError = false
    // P7b — Crew
    @State private var crewTemplate: CrewRules.Template = .pipeline
    @State private var crewFolder: URL?
    @State private var crewGoal = ""
    @State private var crewStarting = false
    @State private var crewNotice: String?
    @State private var crewNoticeIsError = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: XFinderTokens.Settings.sectionGap) {
                PageHeader(title: L10n.t("Agent AI"),
                    subtitle: L10n.t("Các phiên Claude Code và Codex đang chạy trong terminal: đang làm gì, chờ bạn nhập hay chờ bạn duyệt quyền — duyệt ngay tại notch.")
                )

                // P3 review: the notch master switches this surface off with the rest of the notch — say so, here.
                if !notchEnabled {
                    SettingsSection {
                        SettingsLinkRow(
                            title: L10n.t("Notch đang tắt"),
                            subtitle: L10n.t("Mục này không hiện ở notch cho tới khi bạn bật lại notch ở Giao diện notch."),
                            destination: .notchInterface
                        )
                    }
                }

                notchSection
                replySection
                windowlessSection
                crewSection
                sessionsSection
                codexSection
                openCodeSection
                cursorSection
                notifySection
                listSection
                recentSection
                usageSection
            }
            .padding(.bottom, XFinderTokens.Space.section)
            .pageWidthSafe()
        }
        .background(XFinderTokens.Settings.contentBackground)
        .onAppear {
            refreshHookStates()
            statusLineState = AgentSessionMonitor.shared.statusLineState()
            loadRecent()
            Task { windowlessClaudeOK = await WindowlessSessionManager.shared.claudeAvailable() }
        }
    }

    private func refreshHookStates() {
        let m = AgentSessionMonitor.shared
        hookStatus = m.hookStatus(for: .claude)
        codexHookStatus = m.hookStatus(for: .codex)
        lastEventAt = m.lastEventAt
        otherPermissionHooks = Dictionary(uniqueKeysWithValues: AgentSessionMonitor.hookAgents.map { ($0, m.otherPermissionHookCount(for: $0)) })
        openCodeState = OpenCodeMonitor.shared.state
        openCodeBinary = OpenCodeMonitor.shared.binaryPath ?? OpenCodeMonitor.findBinary()
    }

    // MARK: - P5c

    private var cursorSection: some View {
        SettingsSection(
            title: "Cursor",                          // a product name, identical in both languages
            footer: L10n.t("Đo trên máy này (14/10/2026): cursor-agent 2025.09.17 chưa đăng nhập, không có ứng dụng Cursor. Theo tài liệu hook của Cursor, hook chỉ được hỏi TRƯỚC khi Cursor hiện câu hỏi duyệt — không có sự kiện nào báo lúc Cursor đang chờ bạn — và bản CLI chỉ nối một phần các sự kiện. Vì vậy notch không thể hiện thẻ duyệt cho Cursor một cách trung thực.")
        ) {
            Text(L10n.t("Chưa hỗ trợ."))
                .font(XFinderTokens.Font.row).foregroundColor(.secondary)
                .settingsRow()
        }
    }

    private var notifySection: some View {
        SettingsSection(
            title: L10n.t("Thông báo"),
            footer: L10n.t("Thông báo hiện ở notch (cùng chỗ với pin, mạng, cuộc họp), mỗi lần một cái, cái mới thay cái cũ. Không hiện khi bạn đang mở trang Agents trên notch. Mở XFinder không phát lại các phiên đang chờ.")
        ) {
            ToggleRow(title: L10n.t("Khi một phiên cần bạn duyệt quyền"), isOn: $notifyPermission)
                .settingsRow()
            SettingsDivider()
            ToggleRow(title: L10n.t("Khi một phiên xong lượt và tới lượt bạn"), isOn: $notifyFinished)
                .settingsRow()
            SettingsDivider()
            ToggleRow(title: L10n.t("Kèm âm thanh"), isOn: $notifySound)
                .settingsRow()
            SettingsDivider()
            ToggleRow(title: L10n.t("Im lặng khi terminal của phiên đang ở phía trước"),
                      subtitle: L10n.t("Bạn đang nhìn phiên đó (kitty, Terminal, app Claude…) thì notch không báo và không kêu. Phiên không ghi được app (OpenCode, phiên không cửa sổ) vẫn được báo."),
                      isOn: $notifyQuietWhenFront)
                .settingsRow()
        }
        .disabled(!agentsEnabled)
    }

    /// P10 — how the notch lists sessions (OneNotch: "Sort sessions by", "Keep finished sessions visible", the "AI edge").
    private var listSection: some View {
        SettingsSection(title: L10n.t("Danh sách phiên trên notch")) {
            HStack {
                Text(L10n.t("Sắp xếp phiên")).font(XFinderTokens.Font.row)
                Spacer()
                Picker("", selection: $sortMode) {
                    ForEach(AgentSessionRules.SortMode.allCases, id: \.rawValue) { m in
                        Text(L10n.t(m.labelKey)).tag(m.rawValue)
                    }
                }
                .pickerStyle(.menu).labelsHidden().frame(width: 190)
            }
            .settingsRow()
            .onChange(of: sortMode) { AgentSessionMonitor.shared.listSettingsChanged() }
            SettingsDivider()
            ToggleRow(title: L10n.t("Giữ phiên đã kết thúc trong danh sách"),
                      subtitle: L10n.t("Tắt thì phiên vừa kết thúc biến khỏi notch ngay; bật thì nó ở lại tối đa một giờ."),
                      isOn: $keepFinished)
                .settingsRow()
                .onChange(of: keepFinished) { AgentSessionMonitor.shared.listSettingsChanged() }
            SettingsDivider()
            ToggleRow(title: L10n.t("Rê chuột vào biểu tượng agent để mở trang Agents"),
                      subtitle: L10n.t("Dừng con trỏ trên ô agent ở cánh trái notch là mở danh sách phiên, dù “Rê chuột vào notch mở” đang chọn gì."),
                      isOn: $agentEdgeHover)
                .settingsRow()
        }
        .disabled(!agentsEnabled)
    }

    private var recentSection: some View {
        SettingsSection(
            title: L10n.t("Phiên gần đây"),
            footer: L10n.t("Phiên Claude Code và Codex chạy trong terminal (phiên của app desktop không được liệt kê) và phiên OpenCode, trong 14 ngày qua, đã không còn chạy. Từ tệp phiên (Claude Code, Codex) hoặc lệnh opencode (OpenCode), XFinder chỉ lấy mã phiên, thư mục, thời điểm và tiêu đề của OpenCode. \"Sao chép lệnh\" chép lệnh mở lại phiên đó trong đúng thư mục để bạn dán vào terminal.")
        ) {
            if recent.isEmpty {
                Text(L10n.t("Chưa có phiên nào."))
                    .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                    .settingsRow()
            } else {
                ForEach(Array(recent.enumerated()), id: \.element.id) { index, entry in
                    if index > 0 { SettingsDivider() }
                    recentRow(entry).settingsRow()
                }
            }
        }
    }

    private func recentRow(_ e: AgentRecent.Entry) -> some View {
        HStack(spacing: XFinderTokens.Space.inline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(e.displayName).font(XFinderTokens.Font.row).lineLimit(1).truncationMode(.middle)
                Text("\(e.agent.displayName) · \(e.updated.formatted(.relative(presentation: .named).locale(Locale(identifier: L10n.isEnglish ? "en_US" : "vi_VN"))))")
                    .font(XFinderTokens.Font.caption).foregroundColor(.secondary).lineLimit(1)
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            if let cwd = e.cwd {
                Button {
                    NSWorkspace.shared.open(URL(fileURLWithPath: cwd, isDirectory: true))
                } label: { Image(systemName: "folder") }
                .buttonStyle(.borderless)
                .help(L10n.t("Mở thư mục"))
                .accessibilityLabel(L10n.t("Mở thư mục"))
            }
            if e.agent == .claude, let cwd = e.cwd {
                Button(L10n.t("Mở không cửa sổ")) { resumeWindowless(e, cwd: cwd) }
                    .controlSize(.small)
            }
            Button(copiedID == e.id ? L10n.t("Đã chép") : L10n.t("Sao chép lệnh")) {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(e.resumeCommand, forType: .string)
                copiedID = e.id
            }
            .controlSize(.small)
            .help(e.resumeCommand)
        }
    }

    private func resumeWindowless(_ e: AgentRecent.Entry, cwd: String) {
        Task {
            do {
                try await WindowlessSessionManager.shared.resumeClaude(
                    sessionID: e.sessionID, folder: URL(fileURLWithPath: cwd, isDirectory: true),
                    liveSessions: AgentSessionMonitor.shared.sessions)
                windowlessNoticeIsError = false
                windowlessNotice = L10n.t("Đã bắt đầu — xem ở trang Agents trên notch.")
            } catch let error as WindowlessSessionManager.StartError {
                windowlessNoticeIsError = true
                if let detail = error.detail {
                    windowlessNotice = "\(L10n.t(error.key)) · \(detail)"
                } else {
                    windowlessNotice = L10n.t(error.key)
                }
            } catch {
                windowlessNoticeIsError = true
                windowlessNotice = L10n.t("Không chạy được claude.")
            }
        }
    }

    private func loadRecent() {
        let m = AgentSessionMonitor.shared
        recent = m.recent
        m.refreshRecent { recent = AgentSessionMonitor.shared.recent }
    }

    private var openCodeSection: some View {
        SettingsSection(
            title: "OpenCode",                        // a product name, identical in both languages
            footer: L10n.t("OpenCode 2 không còn nạp plugin kiểu cũ (chính OpenCode ghi lỗi đó khi khởi động), nên XFinder không cài plugin nào và không sửa cấu hình OpenCode. Mật khẩu của dịch vụ OpenCode nằm ở chỗ chỉ lệnh opencode đọc — XFinder không đọc nó. Cho phép trên notch trả lời \"once\" (chỉ lần này), không bao giờ \"always\", để không có luật nào bị ghi vào cấu hình của bạn.")
        ) {
            ToggleRow(title: L10n.t("Theo dõi phiên OpenCode"),
                      subtitle: L10n.t("Khi cơ sở dữ liệu của OpenCode vừa được ghi, XFinder chạy chính lệnh opencode của bạn (opencode api) để biết phiên nào đang chạy và yêu cầu quyền nào đang chờ. Không đọc nội dung hội thoại. Không có ghi thì không chạy gì. Mặc định tắt."),
                      isOn: $openCodeEnabled)
                .onChange(of: openCodeEnabled) {
                    NotchSurfaceController.shared.applySettings()
                    refreshHookStates()
                }
                .disabled(!agentsEnabled)
                .settingsRow()
            SettingsDivider()
            openCodeStatusLine.settingsRow()
        }
    }

    @ViewBuilder private var openCodeStatusLine: some View {
        if let bin = openCodeBinary {
            VStack(alignment: .leading, spacing: 2) {
                switch openCodeState {
                case .failed(let msg):
                    Text("\(L10n.t("OpenCode không trả lời: "))\(msg)")
                        .font(XFinderTokens.Font.caption).foregroundColor(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                case .ready where openCodeEnabled && agentsEnabled:
                    Text(L10n.t("Đang theo dõi.")).font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                default:
                    EmptyView()
                }
                Text(bin).font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                    .lineLimit(1).truncationMode(.middle).frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            }
        } else {
            Text(L10n.t("Không tìm thấy lệnh opencode (~/.opencode/bin, Homebrew, ~/.local/bin, ~/.bun/bin)."))
                .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
        }
    }

    private var notchSection: some View {
        SettingsSection(title: L10n.t("Phiên agent trên notch")) {
            ToggleRow(title: L10n.t("Hiện phiên agent ở notch"),
                      subtitle: L10n.t("Đọc nhật ký do hook của XFinder ghi (Claude Code, Codex): tên sự kiện, công cụ, thư mục, câu lệnh bạn gõ và tóm tắt việc công cụ làm (lệnh, đường dẫn tệp) để hiện trên notch. Không đọc câu trả lời của agent, không gọi mạng. Mặc định tắt."),
                      isOn: $agentsEnabled)
                .onChange(of: agentsEnabled) {
                    NotchSurfaceController.shared.applySettings()
                    refreshHookStates()
                }
                .settingsRow()
        }
    }

    // MARK: - P6 — Nhắn phiên

    private var replySection: some View {
        SettingsSection(
            title: L10n.t("Nhắn phiên"),
            footer: L10n.t("Mỗi tin chỉ một dòng; ký tự điều khiển bị bỏ trước khi gõ. Khi phiên đang hỏi quyền hay hỏi một câu có lựa chọn, XFinder không gõ gì (phím gõ vào sẽ trả lời hộp thoại). Phiên đang chạy thì tin được giữ lại và gửi khi phiên rảnh. Socket nhắn tin của Claude Code không được dùng: tin qua đó hiện là tin của một phiên khác, không phải của bạn.")
        ) {
            replyRow(title: "kitty",
                     subtitle: L10n.t("Gõ thẳng vào đúng cửa sổ của phiên. Cần allow_remote_control yes và listen_on unix:… trong kitty.conf; XFinder kiểm tra cửa sổ vẫn chạy agent trước khi gõ."))
                .settingsRow()
            SettingsDivider()
            replyRow(title: "tmux",
                     subtitle: L10n.t("Gõ thẳng vào đúng ô của phiên; XFinder kiểm tra ô vẫn là của phiên (cùng tty) trước khi gõ."))
                .settingsRow()
            SettingsDivider()
            replyRow(title: "OpenCode",
                     subtitle: L10n.t("Gửi qua chính lệnh opencode của bạn; khi phiên đang chạy, OpenCode xếp tin vào hàng đợi của phiên."))
                .settingsRow()
            SettingsDivider()
            replyRow(title: L10n.t("Terminal khác"),
                     subtitle: L10n.t("Terminal.app, iTerm2, Ghostty và WezTerm chưa được đo để gõ tự động, nên XFinder chép tin vào clipboard và đưa terminal lên trước để bạn dán. Phiên Claude Code hay Codex chạy trong kitty hoặc tmux thì vẫn được gõ thẳng."))
                .settingsRow()
        }
    }

    private func replyRow(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(XFinderTokens.Font.row)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            Text(subtitle)
                .font(XFinderTokens.Font.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - P7a — Phiên không cửa sổ

    private var windowlessSection: some View {
        SettingsSection(
            title: L10n.t("Phiên không cửa sổ"),
            footer: L10n.t("XFinder chạy claude -p ở chế độ luồng trong thư mục bạn chọn, không mở terminal. Mỗi tin bạn gửi là một lượt dùng gói Claude của bạn. Phiên dừng khi bạn dừng nó hoặc thoát XFinder; hội thoại vẫn nằm trong Claude Code và mở lại được ở Phiên gần đây, hoặc bằng claude --resume trong terminal. XFinder chỉ giữ ~40 tin gần nhất trong bộ nhớ để hiện ở notch.")
        ) {
            windowlessFolderRow.settingsRow()
            SettingsDivider()
            windowlessMessageRow.settingsRow()
            SettingsDivider()
            windowlessStartRow.settingsRow()
            if windowlessClaudeOK == false {
                SettingsDivider()
                Text(L10n.t("Không tìm thấy lệnh claude."))
                    .font(XFinderTokens.Font.caption).foregroundColor(.orange)
                    .settingsRow()
            }
            if hookStatus != .installed {
                SettingsDivider()
                Text(L10n.t("Chưa cài hook Claude Code của XFinder: lệnh cần duyệt quyền trong phiên không cửa sổ không hỏi được qua notch (cài ở mục Claude Code bên dưới)."))
                    .font(XFinderTokens.Font.caption).foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .settingsRow()
            }
            if let windowlessNotice {
                SettingsDivider()
                Text(windowlessNotice)
                    .font(XFinderTokens.Font.caption)
                    .foregroundColor(windowlessNoticeIsError ? .orange : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .settingsRow()
            }
            if !WindowlessSessionManager.shared.orderedRecords.isEmpty {
                SettingsDivider()
                windowlessList.settingsRow()
            }
            SettingsDivider()
            windowlessOtherAgentsRow.settingsRow()
        }
    }

    private var windowlessFolderRow: some View {
        HStack(spacing: XFinderTokens.Space.inline) {
            Text(windowlessFolder?.path ?? L10n.t("Chưa chọn thư mục"))
                .font(XFinderTokens.Font.row)
                .foregroundColor(windowlessFolder == nil ? .secondary : .primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            Button(L10n.t("Chọn thư mục…")) { pickWindowlessFolder() }
                .controlSize(.small)
        }
    }

    private var windowlessMessageRow: some View {
        TextField(L10n.t("Việc đầu tiên cho Claude Code (không bắt buộc)…"), text: $windowlessMessage)
            .textFieldStyle(.plain)
            .font(XFinderTokens.Font.row)
    }

    private var windowlessStartRow: some View {
        HStack(spacing: XFinderTokens.Space.inline) {
            Text(L10n.t("Bắt đầu một phiên mới trong thư mục đã chọn."))
                .font(XFinderTokens.Font.caption)
                .foregroundColor(.secondary)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            Button(L10n.t("Bắt đầu phiên")) { startWindowless() }
                .controlSize(.small)
                .disabled(windowlessStarting || windowlessFolder == nil || windowlessClaudeOK == false)
        }
    }

    private var windowlessOtherAgentsRow: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(L10n.t("Codex và OpenCode"))
                .font(XFinderTokens.Font.row)
            Text(L10n.t("Chưa có phiên không cửa sổ cho hai agent này: Codex cần giao thức app-server của nó, XFinder chưa dựng; phiên OpenCode đã chạy trên server của chính bạn — tạo bằng lệnh opencode."))
                .font(XFinderTokens.Font.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var windowlessList: some View {
        let records = WindowlessSessionManager.shared.orderedRecords
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(records.enumerated()), id: \.element.sessionID) { index, record in
                if index > 0 { SettingsDivider() }
                windowlessRow(record).settingsRow()
            }
        }
    }

    private func windowlessRow(_ r: WindowlessRules.Record) -> some View {
        HStack(spacing: XFinderTokens.Space.inline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(URL(fileURLWithPath: r.cwd).lastPathComponent)
                    .font(XFinderTokens.Font.row)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(L10n.t(WindowlessRules.phaseKey(r.phase))) · \(r.turns)\(L10n.t(" tin"))")
                    .font(XFinderTokens.Font.caption)
                    .foregroundColor(.secondary)
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            if !r.isEnded {
                Button(L10n.t("Dừng")) { WindowlessSessionManager.shared.stop(r.sessionID) }
                    .controlSize(.small)
            }
            Button(L10n.t("Sao chép lệnh mở lại")) {
                let cmd = AgentKind.claude.resumeCommand(sessionID: r.sessionID, cwd: r.cwd)
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(cmd, forType: .string)
            }
            .controlSize(.small)
            if r.isEnded {
                Button(L10n.t("Xoá")) { WindowlessSessionManager.shared.forget(r.sessionID) }
                    .controlSize(.small)
            }
        }
    }

    private func pickWindowlessFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK { windowlessFolder = panel.url }
    }

    private func startWindowless() {
        guard let folder = windowlessFolder else { return }
        windowlessStarting = true
        windowlessNotice = nil
        let message = windowlessMessage
        Task {
            do {
                _ = try await WindowlessSessionManager.shared.startClaude(
                    folder: folder, firstMessage: message.isEmpty ? nil : message)
                windowlessMessage = ""
                windowlessNoticeIsError = false
                windowlessNotice = L10n.t("Đã bắt đầu — xem ở trang Agents trên notch.")
            } catch let error as WindowlessSessionManager.StartError {
                windowlessNoticeIsError = true
                if let detail = error.detail {
                    windowlessNotice = "\(L10n.t(error.key)) · \(detail)"
                } else {
                    windowlessNotice = L10n.t(error.key)
                }
            } catch {
                windowlessNoticeIsError = true
                windowlessNotice = "\(L10n.t("Không chạy được claude."))"
            }
            windowlessStarting = false
        }
    }

    // MARK: - P7b — Nhóm agent (crew)

    private var crewSection: some View {
        SettingsSection(
            title: L10n.t("Nhóm agent (crew)"),
            footer: L10n.t("Crew là vài phiên Claude Code không cửa sổ có vai trò, nhắn nhau qua XFinder bằng lệnh xfinder-crew. Các thành viên luôn chạy ở chế độ hỏi quyền: bạn duyệt từng tin giữa họ và từng lệnh cần duyệt. Người duyệt không có công cụ sửa tệp. Claude Code vẫn tự chạy một nhóm lệnh chỉ đọc mà không hỏi (như cat, grep, git diff); lệnh nhắn thành viên khác và lệnh có thể thay đổi máy thì vẫn hỏi bạn. Quy tắc cho phép sẵn trong cài đặt Claude Code của bạn hoặc của thư mục đó vẫn có hiệu lực: lệnh nào đã được cho phép ở đó sẽ không hỏi lại. Mọi thành viên làm chung một thư mục — chưa có nhánh git riêng cho từng người. Thành viên dừng khi crew dừng hoặc khi thoát XFinder. Người gửi được nhận ra bằng token riêng của từng thành viên; chương trình nào chạy dưới tài khoản của bạn cũng đọc được token đó.")
        ) {
            crewTemplateRow.settingsRow()
            SettingsDivider()
            crewFolderRow.settingsRow()
            SettingsDivider()
            crewGoalRow.settingsRow()
            SettingsDivider()
            crewCostCaption.settingsRow()
            SettingsDivider()
            crewStartRow.settingsRow()
            if let crewNotice {
                SettingsDivider()
                Text(crewNotice)
                    .font(XFinderTokens.Font.caption)
                    .foregroundColor(crewNoticeIsError ? .orange : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .settingsRow()
            }
            if hookStatus != .installed {
                SettingsDivider()
                Text(L10n.t("Chưa cài hook Claude Code của XFinder: tin giữa các thành viên và lệnh cần duyệt không hỏi được qua notch (cài ở mục Claude Code bên dưới)."))
                    .font(XFinderTokens.Font.caption).foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .settingsRow()
            }
            if !CrewManager.shared.crews.isEmpty {
                SettingsDivider()
                crewList.settingsRow()
            }
        }
    }

    private var crewTemplateRow: some View {
        HStack(spacing: XFinderTokens.Space.inline) {
            VStack(alignment: .leading, spacing: 2) {
                Picker(L10n.t("Mẫu crew"), selection: $crewTemplate) {
                    ForEach(CrewRules.Template.allCases, id: \.self) { t in
                        Text(L10n.t(t.titleKey)).tag(t)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                Text(crewTemplate.roles.map(\.name).joined(separator: " · "))
                    .font(XFinderTokens.Font.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        }
    }

    private var crewFolderRow: some View {
        HStack(spacing: XFinderTokens.Space.inline) {
            Text(crewFolder?.path ?? L10n.t("Chưa chọn thư mục"))
                .font(XFinderTokens.Font.row)
                .foregroundColor(crewFolder == nil ? .secondary : .primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            Button(L10n.t("Chọn thư mục…")) { pickCrewFolder() }
                .controlSize(.small)
        }
    }

    private var crewGoalRow: some View {
        TextField(L10n.t("Mục tiêu cho cả crew…"), text: $crewGoal)
            .textFieldStyle(.plain)
            .font(XFinderTokens.Font.row)
    }

    private var crewCostCaption: some View {
        Text("\(L10n.t("Sẽ chạy "))\(crewTemplate.roles.count)\(L10n.t(" phiên Claude Code. Người dẫn đầu dùng một lượt ngay với mục tiêu; mỗi tin giữa các thành viên cũng là một lượt. XFinder tạm dừng crew sau "))\(CrewRules.defaultCap)\(L10n.t(" chặng tin để hỏi bạn."))")
            .font(XFinderTokens.Font.caption)
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var crewStartRow: some View {
        HStack(spacing: XFinderTokens.Space.inline) {
            Text(L10n.t("Bắt đầu crew trong thư mục đã chọn."))
                .font(XFinderTokens.Font.caption)
                .foregroundColor(.secondary)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            Button(L10n.t("Bắt đầu crew")) { startCrew() }
                .controlSize(.small)
                .disabled(crewStarting || crewFolder == nil || crewGoal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func pickCrewFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK { crewFolder = panel.url }
    }

    private func startCrew() {
        guard let folder = crewFolder else { return }
        crewStarting = true
        crewNotice = nil
        let template = crewTemplate
        let goal = crewGoal
        Task {
            do {
                _ = try await CrewManager.shared.start(template: template, folder: folder, goal: goal)
                crewGoal = ""
                crewNoticeIsError = false
                crewNotice = L10n.t("Đã bắt đầu crew — xem ở trang Agents trên notch.")
            } catch let error as CrewManager.StartError {
                crewNoticeIsError = true
                if case .member(let e) = error, let detail = e.detail {
                    crewNotice = "\(L10n.t(error.key)) · \(detail)"
                } else {
                    crewNotice = L10n.t(error.key)
                }
            } catch {
                crewNoticeIsError = true
                crewNotice = L10n.t("Không tạo được crew.")
            }
            crewStarting = false
        }
    }

    @ViewBuilder private var crewList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(CrewManager.shared.crews.enumerated()), id: \.element.id) { index, crew in
                if index > 0 { SettingsDivider() }
                crewRow(crew).settingsRow()
            }
        }
    }

    private func crewRow(_ crew: CrewManager.Crew) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: XFinderTokens.Space.inline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(L10n.t(crew.template.titleKey)) — \(URL(fileURLWithPath: crew.folder).lastPathComponent)")
                        .font(XFinderTokens.Font.row)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(crewStatusLine(crew))
                        .font(XFinderTokens.Font.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(CrewManager.shared.costUSD(crew) == nil ? "" : L10n.t("Ước tính của Claude Code, không phải hoá đơn"))
                }
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                if !crew.stopped {
                    Button(crew.relay.pause == nil ? L10n.t("Tạm dừng") : L10n.t("Chạy tiếp")) {
                        crew.relay.pause == nil ? CrewManager.shared.pause(crew.id) : CrewManager.shared.resume(crew.id)
                    }
                    .controlSize(.small)
                    Button(L10n.t("Dừng")) { CrewManager.shared.stop(crew.id) }
                        .controlSize(.small)
                } else {
                    Button(L10n.t("Xoá")) {
                        NotchSurfaceController.shared.closeCrewIfShowing(crew.id)
                        CrewManager.shared.forget(crew.id)
                    }
                        .controlSize(.small)
                }
            }
            ForEach(crew.relay.board.suffix(5)) { entry in
                Text(crewBoardLine(entry))
                    .font(XFinderTokens.Font.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    private func crewStatusLine(_ crew: CrewManager.Crew) -> String {
        let status: String
        if crew.stopped { status = L10n.t("Đã dừng") }
        else if crew.relay.pause != nil { status = L10n.t("Tạm dừng") }
        else { status = L10n.t("Đang chạy") }
        var line = "\(status) · \(crew.relay.relays)/\(crew.relay.cap)\(L10n.t(" chặng tin"))"
        if let cost = CrewManager.shared.costUSD(crew) {
            line += " · ≈ $\(String(format: "%.2f", cost))"
        }
        return line
    }

    private func crewBoardLine(_ entry: CrewRules.BoardEntry) -> String {
        switch entry.kind {
        case .message:
            return "\(entry.from ?? "") \(L10n.t(CrewRules.boardKindKey(.message))) \(entry.to ?? ""): \(entry.text)"
        case .reply:
            return "\(entry.from ?? "") \(L10n.t(CrewRules.boardKindKey(.reply))) \(entry.to ?? ""): \(entry.text)"
        case .failed:
            return L10n.t(CrewRules.boardKindKey(.failed)) + (entry.to.map { " (\($0))" } ?? "")
        default:
            return L10n.t(CrewRules.boardKindKey(entry.kind))
        }
    }

    /// "Sự kiện gần nhất" is the only proof a hook really runs — Codex skips a new hook until it is trusted.
    @ViewBuilder private func lastEventLine(_ agent: AgentKind) -> some View {
        if agentsEnabled {
            if let at = lastEventAt[agent] {
                Text("\(L10n.t("Sự kiện gần nhất: "))\(at.formatted(.relative(presentation: .named).locale(Locale(identifier: L10n.isEnglish ? "en_US" : "vi_VN"))))")
                    .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
            } else {
                Text(L10n.t("Chưa nhận sự kiện nào trong hai ngày qua."))
                    .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
            }
        }
    }

    /// Other tools' PermissionRequest hooks in the same file: the agent runs them all, so a second notch app can
    /// hold a request open after XFinder answered it.
    @ViewBuilder private func otherHooksLine(_ agent: AgentKind) -> some View {
        if let n = otherPermissionHooks[agent], n > 0 {
            Text("\(L10n.t("Tệp này còn "))\(n)\(L10n.t(" hook duyệt quyền của công cụ khác. Agent chạy tất cả cùng lúc — nếu nút trên notch không có tác dụng ngay, hãy tắt app kia hoặc gỡ hook của nó."))")
                .font(XFinderTokens.Font.caption).foregroundColor(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var sessionsSection: some View {
        SettingsSection(
            title: "Claude Code",                     // a product name, identical in both languages
            footer: L10n.t("Cài hook = thêm các mục \"Managed by XFinder\" vào ~/.claude/settings.json (có bản sao lưu đặt cạnh) và chép một script zsh vào Application Support. Hook của app khác giữ nguyên. Mỗi sự kiện của Claude Code chạy script đó vài mili-giây. Khi Claude Code xin quyền, script chờ bạn bấm Cho phép hoặc Từ chối trên notch; XFinder không chạy thì Claude Code hỏi ở terminal như thường. Claude Code trong terminal và phiên không cửa sổ do XFinder chạy dùng hook này — app Claude để bàn không chạy hook.")
        ) {
            VStack(alignment: .leading, spacing: XFinderTokens.Space.tight) {
                HStack(spacing: XFinderTokens.Space.tight) {
                    Text(L10n.t("Hook Claude Code: ")).font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                    Text(hookStatusText).font(XFinderTokens.Font.caption)
                    Spacer()
                    if hookStatus == .installed {
                        Button(L10n.t("Gỡ hook")) { changeHook(install: false) }.controlSize(.small)
                    } else {
                        Button(L10n.t("Cài hook vào ~/.claude/settings.json")) { changeHook(install: true) }.controlSize(.small)
                    }
                }
                if let hookNotice {
                    Text(hookNotice).font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                }
                lastEventLine(.claude)
                otherHooksLine(.claude)
            }
            .settingsRow()
        }
    }

    private var codexSection: some View {
        SettingsSection(
            title: "Codex",                           // a product name, identical in both languages
            footer: L10n.t("Cài hook = thêm các mục \"Managed by XFinder\" vào cuối ~/.codex/hooks.json (có bản sao lưu đặt cạnh) và chép cùng script zsh vào Application Support. Codex chỉ chạy một hook sau khi bạn duyệt nó: mở Codex, gõ /hooks và chọn tin cậy các hook của XFinder — XFinder không tự duyệt thay bạn. Codex ghi nhận việc duyệt theo vị trí của hook trong tệp, nên gỡ hook của XFinder có thể khiến Codex hỏi duyệt lại các hook đứng sau nó. Câu trả lời của Codex (last_assistant_message) không được ghi lại.")
        ) {
            VStack(alignment: .leading, spacing: XFinderTokens.Space.tight) {
                HStack(spacing: XFinderTokens.Space.tight) {
                    Text(L10n.t("Trạng thái hook: ")).font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                    Text(statusText(codexHookStatus, file: "~/.codex/hooks.json")).font(XFinderTokens.Font.caption)
                    Spacer()
                    if codexHookStatus == .installed {
                        Button(L10n.t("Gỡ hook")) { changeCodexHook(install: false) }.controlSize(.small)
                    } else {
                        Button(L10n.t("Cài hook vào ~/.codex/hooks.json")) { changeCodexHook(install: true) }.controlSize(.small)
                    }
                }
                if let codexNotice {
                    Text(codexNotice).font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                lastEventLine(.codex)
                otherHooksLine(.codex)
            }
            .settingsRow()
        }
    }

    private func statusText(_ s: AgentSessionMonitor.HookStatus, file: String) -> String {
        switch s {
        case .installed: return L10n.t("Đã cài")
        case .notInstalled: return L10n.t("Chưa cài")
        case .partial(let missing): return L10n.t("Thiếu một phần") + " (" + missing.joined(separator: ", ") + ")"
        case .settingsUnreadable: return "\(L10n.t("Không đọc được "))\(file)"
        }
    }

    private func changeCodexHook(install: Bool) {
        do {
            if install { try AgentSessionMonitor.shared.installHook(for: .codex) } else { try AgentSessionMonitor.shared.removeHook(for: .codex) }
            codexNotice = install
                ? L10n.t("Đã cài hook. Mở Codex, gõ /hooks và chọn tin cậy các hook của XFinder — trước đó Codex bỏ qua chúng.")
                : L10n.t("Đã gỡ hook.")
        } catch {
            codexNotice = "\(L10n.t("Không đổi được hook: "))\(error)"
        }
        refreshHookStates()
        NotchSurfaceController.shared.applySettings()
    }

    private var usageSection: some View {
        SettingsSection(
            title: L10n.t("Hạn mức Claude"),
            footer: L10n.t("Claude Code chỉ đưa % hạn mức 5 giờ / 7 ngày cho dòng trạng thái (statusLine) của chính nó. statusLine của XFinder chỉ lưu lại đúng con số đó rồi chạy tiếp dòng trạng thái bạn đang có — những gì bạn thấy ở terminal không đổi. Cài sẽ ghi bản sao lưu ~/.claude/settings.json có ngày giờ trước khi sửa; Gỡ statusLine khôi phục đúng lệnh cũ. Chỉ có số khi: đang ở phiên Claude Code trong terminal (app Claude để bàn không chạy statusLine), tài khoản Pro/Max đăng nhập bằng claude.ai, và sau câu trả lời đầu tiên của phiên đó.")
        ) {
            VStack(alignment: .leading, spacing: XFinderTokens.Space.tight) {
                HStack(spacing: XFinderTokens.Space.tight) {
                    // a setting name + product name, identical in both languages — not a key
                    Text("statusLine Claude Code: ").font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                    Text(statusLineStatusText).font(XFinderTokens.Font.caption)
                    Spacer()
                    if statusLineState == .installed {
                        Button(L10n.t("Gỡ statusLine")) { changeStatusLine(install: false) }.controlSize(.small)
                    } else {
                        Button(L10n.t("Cài statusLine")) { changeStatusLine(install: true) }.controlSize(.small)
                    }
                }
                if let statusLineNotice {
                    Text(statusLineNotice).font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                }
            }
            .settingsRow()
        }
    }

    private var hookStatusText: String {
        switch hookStatus {
        case .installed: return L10n.t("Đã cài")
        case .notInstalled: return L10n.t("Chưa cài")
        case .partial(let missing): return L10n.t("Thiếu một phần") + " (" + missing.joined(separator: ", ") + ")"
        case .settingsUnreadable: return L10n.t("Không đọc được ~/.claude/settings.json")
        }
    }

    private func changeHook(install: Bool) {
        do {
            if install { try AgentSessionMonitor.shared.installHook() } else { try AgentSessionMonitor.shared.removeHook() }
            hookNotice = install ? L10n.t("Đã cài hook. Phiên Claude Code mới sẽ hiện trên notch.") : L10n.t("Đã gỡ hook.")
        } catch {
            hookNotice = "\(L10n.t("Không đổi được hook: "))\(error)"
        }
        refreshHookStates()
        NotchSurfaceController.shared.applySettings()
    }

    private var statusLineStatusText: String {
        switch statusLineState {
        case .installed: return L10n.t("Đã cài")
        case .notInstalled: return L10n.t("Chưa cài")
        case .replaced: return L10n.t("Cài đặt đang trỏ sang lệnh khác")
        case .settingsUnreadable: return L10n.t("Không đọc được ~/.claude/settings.json")
        }
    }

    private func changeStatusLine(install: Bool) {
        do {
            if install {
                try AgentSessionMonitor.shared.installStatusLine()
                statusLineNotice = L10n.t("Đã cài statusLine. Phiên Claude Code mới sẽ ghi % hạn mức vào bộ nhớ đệm của XFinder.")
            } else {
                try AgentSessionMonitor.shared.removeStatusLine()
                statusLineNotice = L10n.t("Đã gỡ statusLine.")
            }
        } catch AgentSessionMonitor.StatusLineError.pointsAtAnotherCommand {
            statusLineNotice = L10n.t("Cài đặt statusLine hiện đang trỏ sang một lệnh khác (có thể là của một công cụ khác bọc quanh statusLine của XFinder). Gỡ ở đây sẽ làm đứt chuỗi lệnh đó — hãy gỡ statusLine ở công cụ kia trước, rồi quay lại đây.")
        } catch AgentSessionMonitor.StatusLineError.previousUnreadable {
            statusLineNotice = L10n.t("Không đọc được bản lưu statusLine cũ, nên XFinder không gỡ — gỡ bây giờ sẽ làm mất cài đặt cũ của bạn. Các bản sao lưu settings.json có ngày giờ vẫn nằm trong ~/.claude.")
        } catch AgentSessionMonitor.StatusLineError.settingsUnreadable {
            statusLineNotice = L10n.t("Không đọc được ~/.claude/settings.json")
        } catch AgentSessionMonitor.StatusLineError.bundleResourceMissing {
            statusLineNotice = L10n.t("Bản cài XFinder thiếu script statusLine — hãy cài lại XFinder.")
        } catch {
            statusLineNotice = "\(L10n.t("Không đổi được statusLine: "))\(error)"
        }
        statusLineState = AgentSessionMonitor.shared.statusLineState()
    }
}
