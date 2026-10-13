import SwiftUI

/// Tính năng & Quyền — the one place to choose what XFinder runs and to see what it may do.
///
/// Two tabs. *Tính năng*: every switchable feature with its idle cost, three bundles, and
/// turn-all / turn-off-all. *Quyền*: each macOS permission, whether it is granted, which
/// features use it, and a warning when a granted permission is no longer needed.
///
/// A switch here writes the SAME UserDefaults key the feature's own page writes (see
/// `FeatureHub`), so there is no second source of truth to drift. The hub does not hide
/// sidebar rows: a feature that is off still has its page, which says it is off.
struct FeaturesHubView: View {
    private enum Tab: Hashable { case features, permissions }

    @State private var hub = FeatureHub.shared
    @State private var tab: Tab = .features

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: XFinderTokens.Space.section) {
                PageHeader(icon: "square.grid.2x2",
                           title: L10n.t("Tính năng & Quyền"),
                           subtitle: L10n.t("Chọn XFinder chạy những gì, chỉnh máy Mac và xem nó được phép làm gì."))

                Picker("", selection: $tab) {
                    Text(L10n.t("Tính năng")).tag(Tab.features)
                    Text(L10n.t("Quyền")).tag(Tab.permissions)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 260)
                .padding(.horizontal, XFinderTokens.Space.page)

                switch tab {
                case .features: featuresTab
                case .permissions: permissionsTab
                }
            }
            .padding(.bottom, XFinderTokens.Space.section)
            .pageWidthSafe()
        }
        .background(XFinderTokens.Settings.contentBackground)
        .onAppear { hub.retain() }
        .onDisappear { hub.release() }
    }

    // MARK: - Features tab

    private var featuresTab: some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.section) {
            // Machine-wide controls (volume, output, brightness, appearance…) used to be a tab of
            // their own; they live here so the page is one scroll, not two places to look.
            SystemControlsPanel()

            Divider().padding(.horizontal, XFinderTokens.Space.page)

            // Summary
            VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
                Text(L10n.t("Chỉ bật thứ bạn dùng. Tính năng đã tắt sẽ ngừng chạy nền."))
                    .font(XFinderTokens.Font.rowValue).foregroundColor(.secondary)
                Divider()
                HStack {
                    Text("\(hub.onCount) / \(FeatureCatalog.all.count)\(L10n.t(" tính năng đang bật"))")
                        .font(XFinderTokens.Font.rowValue).foregroundColor(.secondary)
                        .monospacedDigit()
                    Spacer()
                    Button(L10n.t("Chạy lại thiết lập")) { OnboardingWindow.shared.show() }
                    Button(L10n.t("Bật tất cả")) { hub.setAll(true) }
                        .disabled(hub.onCount == FeatureCatalog.all.count)
                    Button(L10n.t("Tắt tất cả")) { hub.setAll(false) }
                        .disabled(hub.onCount == 0)
                }
                .controlSize(.small)
            }
            .padding(.horizontal, XFinderTokens.Space.page)

            Divider().padding(.horizontal, XFinderTokens.Space.page)

            // Bundles
            VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
                SectionHeader(icon: "square.stack", title: L10n.t("Bắt đầu bằng một gói"))
                HStack(alignment: .top, spacing: XFinderTokens.Space.row) {
                    ForEach(FeatureCatalog.bundles, id: \.id) { bundle in
                        bundleCard(bundle)
                    }
                }
                .padding(.horizontal, XFinderTokens.Space.page)
                Text(L10n.t("Một cú bấm đặt sẵn theo cách bạn dùng máy. Mọi thứ còn lại vẫn cách một cú bấm."))
                    .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                    .padding(.horizontal, XFinderTokens.Space.page)
            }

            Divider().padding(.horizontal, XFinderTokens.Space.page)

            ForEach(FeatureGroup.allCases, id: \.self) { group in
                VStack(alignment: .leading, spacing: XFinderTokens.Space.tight) {
                    SectionHeader(icon: "square.grid.2x2", title: L10n.t(group.titleKey))
                    VStack(spacing: 0) {
                        let items = FeatureCatalog.features(in: group)
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, f in
                            featureRow(f)
                            if index < items.count - 1 { Divider().padding(.leading, XFinderTokens.Space.page) }
                        }
                    }
                    .padding(.horizontal, XFinderTokens.Space.page)
                }
                Divider().padding(.horizontal, XFinderTokens.Space.page)
            }

            backupSection
        }
    }

    // MARK: Backup

    @State private var transfer = SettingsTransferController.shared

    private var backupSection: some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
            SectionHeader(icon: "arrow.up.arrow.down.circle", title: L10n.t("Sao lưu cài đặt"))
            VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
                Text(L10n.t("Xuất cài đặt XFinder ra một tệp để chuyển sang máy Mac khác hoặc khôi phục sau khi cài lại. Không gồm lịch sử clipboard, ghi chú, khoá API (nằm trong Keychain) hay thứ riêng của máy này như vị trí cửa sổ."))
                    .font(XFinderTokens.Font.rowValue).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: XFinderTokens.Space.inline) {
                    Button(L10n.t("Xuất…")) { transfer.exportSettings() }
                    Button(L10n.t("Nhập…")) { transfer.importSettings() }
                }
                .controlSize(.small)
                if let status = transfer.status {
                    Text(status).font(XFinderTokens.Font.caption)
                        .foregroundColor(transfer.statusIsError ? .orange : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, XFinderTokens.Space.page)
        }
    }

    private func bundleCard(_ b: FeatureBundle) -> some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.tight) {
            Label(L10n.t(b.titleKey), systemImage: b.symbol)
                .font(XFinderTokens.Font.row)
                .lineLimit(1)
            Text(L10n.t(b.descriptionKey))
                .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(L10n.t("Áp dụng")) { hub.apply(b) }
                .controlSize(.small)
        }
        .padding(XFinderTokens.Space.inline)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: XFinderTokens.Radius.tile).fill(XFinderTokens.Fill.inset))
    }

    private func featureRow(_ f: FeatureDef) -> some View {
        let on = hub.isOn(f)
        let granted = hub.granted()
        let missing = on ? f.permissions.filter { !(granted[$0] ?? false) } : []
        return HStack(alignment: .center, spacing: XFinderTokens.Space.inline) {
            Image(systemName: f.symbol)
                .font(XFinderTokens.Font.sectionTitle)
                .foregroundColor(on ? .white : .secondary)
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: XFinderTokens.Radius.control).fill(on ? Color.accentColor : XFinderTokens.Fill.inset))

            VStack(alignment: .leading, spacing: XFinderTokens.Space.tight) {
                HStack(spacing: XFinderTokens.Space.inline) {
                    Text(L10n.t(f.titleKey)).font(XFinderTokens.Font.row).lineLimit(1)
                    Text(L10n.t(f.idle.badgeKey))
                        .font(XFinderTokens.Font.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, XFinderTokens.Space.tight).padding(.vertical, 2)
                        .background(Capsule().fill(XFinderTokens.Fill.inset))
                        .lineLimit(1)
                    if !missing.isEmpty {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(XFinderTokens.Font.caption).foregroundColor(.orange)
                            .help("\(L10n.t("Thiếu quyền: "))\(missing.map { L10n.t($0.titleKey) }.joined(separator: ", "))")
                    }
                }
                Text(L10n.t(f.subtitleKey))
                    .font(XFinderTokens.Font.rowValue).foregroundColor(.secondary)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

            Button(on ? L10n.t("Tắt") : L10n.t("Bật")) { hub.set(f.id, on: !on) }
                .controlSize(.small)
                .frame(minWidth: 52)
        }
        .padding(.vertical, XFinderTokens.Space.row)
    }

    // MARK: - Permissions tab

    private var permissionsTab: some View {
        let rows = FeatureCatalog.permissionRows(enabled: hub.enabledSet, granted: hub.granted())
        return VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
            Text(L10n.t("Mỗi quyền làm gì và tính năng nào dùng nó."))
                .font(XFinderTokens.Font.rowValue).foregroundColor(.secondary)
                .padding(.horizontal, XFinderTokens.Space.page)

            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.permission) { index, row in
                    permissionRow(row)
                    if index < rows.count - 1 { Divider().padding(.leading, XFinderTokens.Space.page) }
                }
            }
            .padding(.horizontal, XFinderTokens.Space.page)

            Text(L10n.t("Mọi quyền đều tùy chọn: bỏ qua một quyền thì tính năng cần nó đứng yên, phần còn lại vẫn chạy."))
                .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                .padding(.horizontal, XFinderTokens.Space.page)
        }
    }

    private func permissionRow(_ r: FeatureCatalog.PermissionRow) -> some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
            HStack(alignment: .top, spacing: XFinderTokens.Space.inline) {
                Image(systemName: r.permission.symbol)
                    .font(XFinderTokens.Font.sectionTitle).foregroundColor(.secondary)
                    .frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: XFinderTokens.Space.tight) {
                    HStack(spacing: XFinderTokens.Space.inline) {
                        Text(L10n.t(r.permission.titleKey)).font(XFinderTokens.Font.row)
                        HStack(spacing: 4) {
                            Circle().fill(r.granted ? Color.green : Color.orange).frame(width: 7, height: 7)
                            Text(r.granted ? L10n.t("Đã cấp") : L10n.t("Chưa cấp"))
                                .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                        }
                    }
                    Text(L10n.t(r.permission.purposeKey)).font(XFinderTokens.Font.rowValue).foregroundColor(.secondary)
                    Text(r.activeUsers == 0
                         ? L10n.t("Hiện không tính năng nào đang bật cần quyền này.")
                         : "\(L10n.t("Dùng bởi: "))\(r.usedBy.map { L10n.t($0) }.joined(separator: ", "))")
                        .font(XFinderTokens.Font.caption).foregroundColor(.secondary.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)

                    if r.isUnneeded {
                        InlineNote(kind: .warning,
                                   text: L10n.t("Bạn đã cấp quyền này nhưng không gì đang bật cần nó. Nếu muốn, hãy thu hồi trong Cài đặt hệ thống."))
                    }
                    if r.isMissingForActive {
                        InlineNote(kind: .warning,
                                   text: L10n.t("Có tính năng đang bật nhưng chưa có quyền này nên nó chưa hoạt động."))
                    }
                    HStack(spacing: XFinderTokens.Space.inline) {
                        if !r.granted {
                            Button(L10n.t("Cấp quyền…")) { hub.request(r.permission) }.controlSize(.small)
                        }
                        Button(L10n.t("Mở Cài đặt hệ thống")) { hub.openSettings(for: r.permission) }
                            .controlSize(.small)
                    }
                    .padding(.top, 2)
                }
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, XFinderTokens.Space.row)
    }
}
