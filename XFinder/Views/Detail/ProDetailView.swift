import SwiftUI
import AppKit

/// XF-T29 — XFinder Pro. Job: "the person comes here to see which tier they are on, how long the trial lasts, enter a
/// licence key, and see what Pro adds".
struct ProDetailView: View {
    @State private var license = LicenseManager.shared
    @State private var keyText = ""
    @State private var keyRejected = false
    @AppStorage("pro.simulateTier") private var simulateTier = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: XFinderTokens.Settings.sectionGap) {
                PageHeader(title: L10n.t("XFinder Pro"),
                           subtitle: L10n.t("Bản miễn phí đủ dùng hằng ngày; Pro mở giới hạn cho việc nặng — quy mô, tự động hoá, bảo mật, AI agent."))

                SettingsSection(title: L10n.t("Trạng thái")) {
                    HStack(spacing: XFinderTokens.Space.inline) {
                        statusText.font(XFinderTokens.Font.row)
                        Spacer()
                        if license.tier == .pro, license.licensee == nil, !license.isEnforced {
                            Text(L10n.t("Bản phát triển: luôn đầy đủ"))
                                .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                        }
                    }
                    .settingsRow()
                }

                SettingsSection(title: L10n.t("Khoá giấy phép"),
                                footer: L10n.t("Khoá được kiểm ngay trên máy, không cần mạng và không cần tài khoản.")) {
                    VStack(alignment: .leading, spacing: XFinderTokens.Space.tight) {
                        if let who = license.licensee {
                            HStack {
                                Text("\(L10n.t("Đã kích hoạt cho "))\(who)").font(XFinderTokens.Font.rowValue)
                                Spacer()
                                Button(L10n.t("Gỡ khoá")) { license.deactivate() }.controlSize(.small)
                            }
                        } else {
                            TextField(L10n.t("Dán khoá XF1-…"), text: $keyText, axis: .vertical)
                                .textFieldStyle(.roundedBorder)
                                .font(XFinderTokens.Font.mono)
                                .lineLimit(1...4)
                            HStack {
                                Button(L10n.t("Kích hoạt")) { keyRejected = !license.activate(keyText) }
                                    .buttonStyle(.borderedProminent).controlSize(.small)
                                    .disabled(keyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                if keyRejected {
                                    Text(L10n.t("Khoá không hợp lệ.")).font(XFinderTokens.Font.caption).foregroundColor(.red)
                                }
                            }
                        }
                    }
                    .settingsRow()
                }

                SettingsSection(title: L10n.t("Bản miễn phí")) {
                    VStack(alignment: .leading, spacing: XFinderTokens.Space.tight) {
                        limitRow(L10n.t("Lịch sử Clipboard"), .clipboardItems, unit: L10n.t(" mục"))
                        limitRow(L10n.t("Lịch sử ảnh chụp"), .captures, unit: L10n.t(" ảnh"))
                        limitRow(L10n.t("Ngăn trong trình duyệt tệp"), .browserPanes, unit: L10n.t(" ngăn"))
                        limitRow(L10n.t("Liên kết Chia sẻ nhanh cùng lúc"), .quickShareLinks, unit: L10n.t(" liên kết"))
                        Text(L10n.t("Vượt giới hạn thì phần cũ hơn bị ẩn, không bị xoá — mở Pro là thấy lại."))
                            .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                    }
                    .settingsRow()
                }

                SettingsSection(title: L10n.t("Pro thêm gì")) {
                    VStack(alignment: .leading, spacing: XFinderTokens.Space.tight) {
                        ForEach(ProFeature.allCases, id: \.self) { f in
                            HStack(spacing: XFinderTokens.Space.tight) {
                                Image(systemName: license.allows(f) ? "checkmark.circle.fill" : "lock.fill")
                                    .foregroundColor(license.allows(f) ? .green : .secondary)
                                Text(L10n.t(f.titleKey)).font(XFinderTokens.Font.rowValue)
                            }
                        }
                    }
                    .settingsRow()
                }

                #if DEBUG
                SettingsSection(title: L10n.t("Thử giới hạn (bản phát triển)"),
                                footer: L10n.t("Bản phát triển luôn đầy đủ; chọn một bậc ở đây để thử các cổng giới hạn.")) {
                    Picker("", selection: $simulateTier) {
                        Text(L10n.t("Không giả lập")).tag("")
                        Text(L10n.t("Miễn phí")).tag("free")
                        Text(L10n.t("Dùng thử")).tag("trial")
                        Text("Pro").tag("pro")
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .settingsRow()
                    .onChange(of: simulateTier) { _, _ in license.refresh() }
                }
                #endif
            }
            .padding(.bottom, XFinderTokens.Space.section)
            .pageWidthSafe()
        }
        .background(XFinderTokens.Settings.contentBackground)
        .onAppear { license.refresh() }
    }

    private var statusText: Text {
        switch license.tier {
        case .pro: return Text(L10n.t("Pro"))
        case .trial(let days): return Text("\(L10n.t("Dùng thử Pro — còn "))\(days)\(L10n.t(" ngày"))")
        case .free: return Text(L10n.t("Miễn phí"))
        }
    }

    private func limitRow(_ title: String, _ limit: ProLimit, unit: String) -> some View {
        HStack {
            Text(title).font(XFinderTokens.Font.rowValue)
            Spacer()
            Text("\(Entitlement.freeLimits[limit] ?? 0)\(unit)")
                .font(XFinderTokens.Font.mono).foregroundColor(.secondary)
        }
    }
}
