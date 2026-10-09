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
            VStack(alignment: .leading, spacing: 18) {
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
                .padding(.horizontal, 20)

                switch tab {
                case .features: featuresTab
                case .permissions: permissionsTab
                }
            }
            .padding(.bottom, 24)
            .pageWidthSafe()
        }
        .background(Color(.windowBackgroundColor))
        .onAppear { hub.retain() }
        .onDisappear { hub.release() }
    }

    // MARK: - Features tab

    private var featuresTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Machine-wide controls (volume, output, brightness, appearance…) used to be a tab of
            // their own; they live here so the page is one scroll, not two places to look.
            SystemControlsPanel()

            Divider().padding(.horizontal, 20)

            // Summary
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.t("Chỉ bật thứ bạn dùng. Tính năng đã tắt sẽ ngừng chạy nền."))
                    .font(.system(size: 12)).foregroundColor(.secondary)
                Divider()
                HStack {
                    Text("\(hub.onCount) / \(FeatureCatalog.all.count)\(L10n.t(" tính năng đang bật"))")
                        .font(.system(size: 12)).foregroundColor(.secondary)
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
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.05)))
            .padding(.horizontal, 20)

            // Bundles
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.t("Bắt đầu bằng một gói")).font(.system(size: 15, weight: .semibold))
                    .padding(.horizontal, 20)
                HStack(alignment: .top, spacing: 10) {
                    ForEach(FeatureCatalog.bundles, id: \.id) { bundle in
                        bundleCard(bundle)
                    }
                }
                .padding(.horizontal, 20)
                Text(L10n.t("Một cú bấm đặt sẵn theo cách bạn dùng máy. Mọi thứ còn lại vẫn cách một cú bấm."))
                    .font(.system(size: 11)).foregroundColor(.secondary)
                    .padding(.horizontal, 20)
            }

            ForEach(FeatureGroup.allCases, id: \.self) { group in
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.t(group.titleKey)).font(.system(size: 15, weight: .semibold))
                        .padding(.horizontal, 20)
                    VStack(spacing: 0) {
                        let items = FeatureCatalog.features(in: group)
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, f in
                            featureRow(f)
                            if index < items.count - 1 { Divider().padding(.leading, 60) }
                        }
                    }
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.05)))
                    .padding(.horizontal, 20)
                }
            }
        }
    }

    private func bundleCard(_ b: FeatureBundle) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(L10n.t(b.titleKey), systemImage: b.symbol)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
            Text(L10n.t(b.descriptionKey))
                .font(.system(size: 11)).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(L10n.t("Áp dụng")) { hub.apply(b) }
                .controlSize(.small)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.06)))
    }

    private func featureRow(_ f: FeatureDef) -> some View {
        let on = hub.isOn(f)
        let granted = hub.granted()
        let missing = on ? f.permissions.filter { !(granted[$0] ?? false) } : []
        return HStack(alignment: .center, spacing: 12) {
            Image(systemName: f.symbol)
                .font(.system(size: 17))
                .foregroundColor(on ? .white : .secondary)
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: 9).fill(on ? Color.accentColor : Color.primary.opacity(0.10)))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(L10n.t(f.titleKey)).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    Text(L10n.t(f.idle.badgeKey))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill(Color.primary.opacity(0.08)))
                        .lineLimit(1)
                    if !missing.isEmpty {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11)).foregroundColor(.orange)
                            .help("\(L10n.t("Thiếu quyền: "))\(missing.map { L10n.t($0.titleKey) }.joined(separator: ", "))")
                    }
                }
                Text(L10n.t(f.subtitleKey))
                    .font(.system(size: 12)).foregroundColor(.secondary)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

            Button(on ? L10n.t("Tắt") : L10n.t("Bật")) { hub.set(f.id, on: !on) }
                .controlSize(.small)
                .frame(minWidth: 52)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
    }

    // MARK: - Permissions tab

    private var permissionsTab: some View {
        let rows = FeatureCatalog.permissionRows(enabled: hub.enabledSet, granted: hub.granted())
        return VStack(alignment: .leading, spacing: 14) {
            Text(L10n.t("Mỗi quyền làm gì và tính năng nào dùng nó."))
                .font(.system(size: 12)).foregroundColor(.secondary)
                .padding(.horizontal, 20)

            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.permission) { index, row in
                    permissionRow(row)
                    if index < rows.count - 1 { Divider().padding(.leading, 56) }
                }
            }
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.05)))
            .padding(.horizontal, 20)

            Text(L10n.t("Mọi quyền đều tùy chọn: bỏ qua một quyền thì tính năng cần nó đứng yên, phần còn lại vẫn chạy."))
                .font(.system(size: 11)).foregroundColor(.secondary)
                .padding(.horizontal, 20)
        }
    }

    private func permissionRow(_ r: FeatureCatalog.PermissionRow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: r.permission.symbol)
                    .font(.system(size: 18)).foregroundColor(.secondary)
                    .frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(L10n.t(r.permission.titleKey)).font(.system(size: 14, weight: .semibold))
                        HStack(spacing: 4) {
                            Circle().fill(r.granted ? Color.green : Color.orange).frame(width: 7, height: 7)
                            Text(r.granted ? L10n.t("Đã cấp") : L10n.t("Chưa cấp"))
                                .font(.system(size: 11)).foregroundColor(.secondary)
                        }
                    }
                    Text(L10n.t(r.permission.purposeKey)).font(.system(size: 12)).foregroundColor(.secondary)
                    Text(r.activeUsers == 0
                         ? L10n.t("Hiện không tính năng nào đang bật cần quyền này.")
                         : "\(L10n.t("Dùng bởi: "))\(r.usedBy.map { L10n.t($0) }.joined(separator: ", "))")
                        .font(.system(size: 11)).foregroundColor(.secondary.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)

                    if r.isUnneeded {
                        Text(L10n.t("Bạn đã cấp quyền này nhưng không gì đang bật cần nó. Nếu muốn, hãy thu hồi trong Cài đặt hệ thống."))
                            .font(.system(size: 11))
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.07)))
                    }
                    if r.isMissingForActive {
                        Text(L10n.t("Có tính năng đang bật nhưng chưa có quyền này nên nó chưa hoạt động."))
                            .font(.system(size: 11)).foregroundColor(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(spacing: 8) {
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
        .padding(.horizontal, 12).padding(.vertical, 12)
    }
}
