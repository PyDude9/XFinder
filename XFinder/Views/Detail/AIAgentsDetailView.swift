import SwiftUI

/// Agent AI — the user comes here to put their Claude Code sessions on the notch (and to install or
/// remove the hook that makes that possible), and to see Claude's own 5h/7d usage % via an opt-in
/// statusLine. Split off "Notch & Khay thả" (P3); both install paths edit files outside the app
/// (~/.claude/settings.json), so they are buttons, never switches.
struct AIAgentsDetailView: View {
    // N3
    @AppStorage("dropTray.notchEnabled") private var notchEnabled = true
    @AppStorage("agents.enabled") private var agentsEnabled = false
    @State private var hookStatus: AgentSessionMonitor.HookStatus = .notInstalled
    @State private var hookNotice: String?
    // P2 — Claude Code statusLine (5h/7d usage %), a settings-only opt-in.
    @State private var statusLineState: AgentSessionMonitor.StatusLineState = .notInstalled
    @State private var statusLineNotice: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: XFinderTokens.Settings.sectionGap) {
                PageHeader(title: L10n.t("Agent AI"),
                    subtitle: L10n.t("Các phiên Claude Code đang chạy trong terminal: đang làm gì, chờ bạn nhập hay chờ bạn duyệt quyền — duyệt ngay tại notch.")
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

                sessionsSection
                usageSection
            }
            .padding(.bottom, XFinderTokens.Space.section)
            .pageWidthSafe()
        }
        .background(XFinderTokens.Settings.contentBackground)
        .onAppear {
            hookStatus = AgentSessionMonitor.shared.hookStatus()
            statusLineState = AgentSessionMonitor.shared.statusLineState()
        }
    }

    private var sessionsSection: some View {
        SettingsSection(
            title: L10n.t("Phiên Claude Code"),
            footer: L10n.t("Cài hook = thêm các mục \"Managed by XFinder\" vào ~/.claude/settings.json (có bản sao lưu đặt cạnh) và chép một script zsh vào Application Support. Hook của app khác giữ nguyên. Mỗi sự kiện của Claude Code chạy script đó vài mili-giây. Khi Claude Code xin quyền, script chờ bạn bấm Cho phép hoặc Từ chối trên notch; XFinder không chạy thì Claude Code hỏi ở terminal như thường. Chỉ Claude Code trong terminal — app Claude để bàn không chạy hook.")
        ) {
            ToggleRow(title: L10n.t("Hiện phiên Claude Code ở notch"),
                      subtitle: L10n.t("Đọc nhật ký do hook của XFinder ghi: tên sự kiện, công cụ, thư mục, câu lệnh bạn gõ và tóm tắt việc công cụ làm (lệnh, đường dẫn tệp) để hiện trên notch. Không đọc câu trả lời của Claude, không gọi mạng. Mặc định tắt."),
                      isOn: $agentsEnabled)
                .onChange(of: agentsEnabled) { NotchSurfaceController.shared.applySettings() }
                .settingsRow()
            SettingsDivider()
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
            }
            .settingsRow()
        }
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
        hookStatus = AgentSessionMonitor.shared.hookStatus()
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
