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
    // P2 — Claude Code statusLine (5h/7d usage %), a settings-only opt-in.
    @State private var statusLineState: AgentSessionMonitor.StatusLineState = .notInstalled
    @State private var statusLineNotice: String?

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
                sessionsSection
                codexSection
                usageSection
            }
            .padding(.bottom, XFinderTokens.Space.section)
            .pageWidthSafe()
        }
        .background(XFinderTokens.Settings.contentBackground)
        .onAppear {
            refreshHookStates()
            statusLineState = AgentSessionMonitor.shared.statusLineState()
        }
    }

    private func refreshHookStates() {
        let m = AgentSessionMonitor.shared
        hookStatus = m.hookStatus(for: .claude)
        codexHookStatus = m.hookStatus(for: .codex)
        lastEventAt = m.lastEventAt
        otherPermissionHooks = Dictionary(uniqueKeysWithValues: AgentSessionMonitor.hookAgents.map { ($0, m.otherPermissionHookCount(for: $0)) })
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
            footer: L10n.t("Cài hook = thêm các mục \"Managed by XFinder\" vào ~/.claude/settings.json (có bản sao lưu đặt cạnh) và chép một script zsh vào Application Support. Hook của app khác giữ nguyên. Mỗi sự kiện của Claude Code chạy script đó vài mili-giây. Khi Claude Code xin quyền, script chờ bạn bấm Cho phép hoặc Từ chối trên notch; XFinder không chạy thì Claude Code hỏi ở terminal như thường. Chỉ Claude Code trong terminal — app Claude để bàn không chạy hook.")
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
