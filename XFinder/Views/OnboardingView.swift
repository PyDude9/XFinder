import SwiftUI
import AppKit

/// First-run setup: (1) choose what XFinder runs, (2) grant only the permissions that choice needs.
/// Shown once per `Onboarding.currentVersion`, and again on demand from Features & Permissions.
struct OnboardingView: View {
    var onFinish: () -> Void

    private enum Step { case choose, permissions }

    @State private var hub = FeatureHub.shared
    @State private var step: Step = .choose
    @State private var selection: Set<FeatureID> = FeatureHub.shared.enabledSet

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch step {
            case .choose: chooseStep
            case .permissions: permissionsStep
            }
        }
        .frame(width: 560, height: 560)
        .onAppear { hub.retain() }
        .onDisappear { hub.release() }
    }

    // MARK: Step 1

    private var chooseStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.t("Chào mừng đến XFinder")).font(.system(size: 22, weight: .bold))
                Text(L10n.t("Chọn thứ bạn muốn dùng. Bạn đổi lại bất cứ lúc nào ở Tính năng & Quyền."))
                    .font(.system(size: 12)).foregroundColor(.secondary)
            }
            .padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 14)

            HStack(alignment: .top, spacing: 10) {
                ForEach(Onboarding.presets, id: \.id) { p in presetCard(p) }
            }
            .padding(.horizontal, 24).padding(.bottom, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(FeatureGroup.allCases, id: \.self) { group in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(L10n.t(group.titleKey)).font(.system(size: 12, weight: .semibold)).foregroundColor(.secondary)
                            ForEach(FeatureCatalog.features(in: group), id: \.id) { f in featureRow(f) }
                        }
                    }
                }
                .padding(.horizontal, 24).padding(.bottom, 12)
            }

            Divider()
            HStack {
                Button(L10n.t("Bỏ qua")) { onFinish() }
                Spacer()
                Button(L10n.t("Tiếp tục")) { applyAndContinue() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(16)
        }
    }

    private func presetCard(_ p: Onboarding.Preset) -> some View {
        let active = Onboarding.matchingPreset(selection) == p.id
        return Button { selection = p.features } label: {
            VStack(alignment: .leading, spacing: 6) {
                Label(L10n.t(p.titleKey), systemImage: p.symbol).font(.system(size: 13, weight: .semibold))
                Text(L10n.t(p.descriptionKey)).font(.system(size: 11)).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 10).fill(active ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(active ? Color.accentColor : Color.clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }

    private func featureRow(_ f: FeatureDef) -> some View {
        HStack(spacing: 10) {
            Image(systemName: f.symbol).frame(width: 22).foregroundColor(.accentColor)
            VStack(alignment: .leading, spacing: 1) {
                Text(L10n.t(f.titleKey)).font(.system(size: 13))
                Text(L10n.t(f.subtitleKey)).font(.system(size: 11)).foregroundColor(.secondary).lineLimit(1)
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            Toggle("", isOn: Binding(get: { selection.contains(f.id) },
                                     set: { on in if on { selection.insert(f.id) } else { selection.remove(f.id) } }))
                .toggleStyle(.switch).labelsHidden().controlSize(.small)
        }
    }

    private func applyAndContinue() {
        // Only the features whose state actually changes are touched.
        for f in FeatureCatalog.all where selection.contains(f.id) != hub.isOn(f) {
            hub.set(f.id, on: selection.contains(f.id))
        }
        step = .permissions
    }

    // MARK: Step 2

    private var permissionsStep: some View {
        let needed = Onboarding.neededPermissions(for: selection)
        let granted = hub.granted()
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.t("Quyền cần cho lựa chọn của bạn")).font(.system(size: 22, weight: .bold))
                Text(L10n.t("Chỉ những quyền mà tính năng bạn bật thật sự dùng. Bỏ qua cũng được: tính năng cần quyền đó sẽ đứng yên, phần còn lại vẫn chạy."))
                    .font(.system(size: 12)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 14)

            ScrollView {
                VStack(spacing: 8) {
                    if needed.isEmpty {
                        Text(L10n.t("Lựa chọn của bạn không cần quyền nào."))
                            .font(.system(size: 13)).foregroundColor(.secondary).padding(.top, 20)
                    }
                    ForEach(needed, id: \.self) { p in permissionRow(p, granted: granted[p] ?? false) }
                }
                .padding(.horizontal, 24)
            }

            Divider()
            HStack {
                Button(L10n.t("Quay lại")) { step = .choose }
                Spacer()
                Button(L10n.t("Xong")) { onFinish() }.buttonStyle(.borderedProminent)
            }
            .padding(16)
        }
    }

    private func permissionRow(_ p: AppPermission, granted: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: p.symbol).font(.system(size: 18)).foregroundColor(.secondary).frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(L10n.t(p.titleKey)).font(.system(size: 14, weight: .semibold))
                    HStack(spacing: 4) {
                        Circle().fill(granted ? Color.green : Color.orange).frame(width: 7, height: 7)
                        Text(granted ? L10n.t("Đã cấp") : L10n.t("Chưa cấp")).font(.system(size: 11)).foregroundColor(.secondary)
                    }
                }
                Text(L10n.t(p.purposeKey)).font(.system(size: 12)).foregroundColor(.secondary)
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            if !granted {
                Button(L10n.t("Cấp quyền…")) { hub.request(p) }.controlSize(.small)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
    }
}

/// Setup lives in its OWN window, not a `.sheet`: measured on macOS 27, an open SwiftUI sheet makes
/// `NSApp.terminate` refuse (⌘Q and the Apple Event quit both answered "User canceled" until the
/// sheet was dismissed), so a first-run user could not even quit the app.
@MainActor
final class OnboardingWindow: NSObject, NSWindowDelegate {
    static let shared = OnboardingWindow()
    private var window: NSWindow?

    func show() {
        if let window { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let host = NSHostingController(rootView: OnboardingView { [weak self] in self?.finish() })
        let w = NSWindow(contentViewController: host)
        w.title = "XFinder"
        w.styleMask = [.titled, .closable]
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.center()
        window = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    /// Done, Skip, or closing the window all count as finished: closing is never a reason to nag
    /// again on the next launch.
    private func finish() {
        UserDefaults.standard.set(Onboarding.currentVersion, forKey: Onboarding.completedKey)
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        UserDefaults.standard.set(Onboarding.currentVersion, forKey: Onboarding.completedKey)
        window?.delegate = nil
        window = nil
    }
}
