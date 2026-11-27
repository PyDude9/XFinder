import SwiftUI

// MARK: - Tab 7: Utilities

struct UtilitiesPanelTabView: View {
    let onClose: () -> Void
    @State private var snippetStore = TextSnippetStore.shared

    var body: some View {
        VStack(spacing: 8) {
            utilityCard(
                icon: "command",
                title: L10n.t("Bảng lệnh"),
                subtitle: L10n.t("Tìm ứng dụng, tệp, cài đặt, snippet và tính toán."),
                shortcut: "⌘K"
            ) {
                onClose()
                QuickSearchPanelController.shared.toggle()
            }
            utilityCard(
                icon: "camera.viewfinder",
                title: L10n.t("Chụp vùng màn hình"),
                subtitle: L10n.t("Chụp một vùng màn hình để chú thích hoặc lưu nhanh.")
            ) {
                onClose()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    CaptureController.shared.capture(.area)
                }
            }
            utilityCard(
                icon: "text.viewfinder",
                title: L10n.t("Sao chép chữ từ màn hình"),
                subtitle: L10n.t("Nhận dạng chữ (OCR) ngay trên máy từ vùng bạn chọn.")
            ) {
                onClose()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    CaptureController.shared.capture(.text)
                }
            }
            utilityCard(
                icon: "eyedropper",
                title: L10n.t("Lấy màu màn hình"),
                subtitle: L10n.t("Chấm màu bất kỳ trên màn hình và chép mã HEX.")
            ) {
                onClose()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    CaptureController.shared.capture(.color)
                }
            }
            if BrowserSettings.isEnabled {
                utilityCard(
                    icon: "square.split.2x2",
                    title: L10n.t("Trình duyệt tệp"),
                    subtitle: L10n.t("Mở trình duyệt tệp nhiều ngăn của XFinder.")
                ) {
                    onClose()
                    BrowserWindowController.shared.openWindow(path: nil)
                }
            }
            utilityCard(
                icon: "doc.on.clipboard",
                title: L10n.t("Thư viện Clipboard"),
                subtitle: L10n.t("Xem, tìm kiếm và dán lại lịch sử đã sao chép."),
                shortcut: "⌘⇧V"
            ) {
                onClose()
                AppState.shared.navigate(to: .clipboard)
            }
            utilityCard(
                icon: "text.badge.plus",
                title: L10n.t("Đoạn văn bản nhanh"),
                subtitle: L10n.t("Quản lý gõ tắt và tự động mở rộng nội dung."),
                shortcut: snippetStore.snippets.isEmpty ? nil : "\(snippetStore.snippets.count)"
            ) {
                onClose()
                AppState.shared.navigate(to: .settingsClipboard)
            }
            utilityCard(
                icon: "rectangle.split.3x1",
                title: L10n.t("Vùng bắt dính"),
                subtitle: L10n.t("Sắp xếp cửa sổ vào nửa, phần ba hoặc góc màn hình.")
            ) {
                onClose()
                AppState.shared.navigate(to: .snapZones)
            }
            utilityCard(
                icon: "keyboard.badge.eye",
                title: L10n.t("Lau bàn phím…"),
                subtitle: L10n.t("Tạm khóa bàn phím để lau chùi an toàn.")
            ) {
                onClose()
                CleaningModeController.shared.start()
            }
            utilityCard(
                icon: "note.text.badge.plus",
                title: L10n.t("Ghi chú mới"),
                subtitle: L10n.t("Tạo nhanh một ghi chú nổi ở mép màn hình.")
            ) {
                onClose()
                EdgeNotesController.shared.createNote()
            }
            utilityCard(
                icon: "bubbles.and.sparkles",
                title: L10n.t("Dọn rác thư mục"),
                subtitle: L10n.t("Tìm và dọn bộ nhớ đệm, tệp tạm cục bộ.")
            ) {
                onClose()
                AppState.shared.navigate(to: .junkCleanup)
            }
            utilityCard(
                icon: "xmark.bin",
                title: L10n.t("Gỡ ứng dụng"),
                subtitle: L10n.t("Gỡ ứng dụng kèm toàn bộ tệp thừa liên quan.")
            ) {
                onClose()
                AppState.shared.navigate(to: .uninstaller)
            }
            utilityCard(
                icon: "point.3.connected.trianglepath.dotted",
                title: L10n.t("Cổng đang mở"),
                subtitle: L10n.t("Xem tiến trình đang lắng nghe cổng mạng và dừng nhanh.")
            ) {
                onClose()
                AppState.shared.navigate(to: .ports)
            }
        }
    }

    private func utilityCard(icon: String, title: String, subtitle: String, shortcut: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.accentColor)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(.primary)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 4)
                if let shortcut {
                    Text(shortcut)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.primary.opacity(0.08)))
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary.opacity(0.7))
            }
            .menubarPanelCard()
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Tab 8: Controls (retains FeatureHub ONLY while visible)

struct ControlsPanelTabView: View {
    @AppStorage("menubar.collapsedControlGroups") private var collapsedRaw = ""
    @State private var hub = FeatureHub.shared

    private var collapsedGroups: Set<String> {
        MenubarPanelRules.parseCollapsedHeaders(collapsedRaw)
    }

    private func toggleGroup(_ key: String) {
        var next = collapsedGroups
        if next.contains(key) { next.remove(key) } else { next.insert(key) }
        collapsedRaw = MenubarPanelRules.encodeCollapsedHeaders(next)
    }

    var body: some View {
        VStack(spacing: 8) {
            ForEach(FeatureGroup.allCases, id: \.self) { group in
                let items = FeatureCatalog.features(in: group)
                let onCount = items.filter { hub.isOn($0) }.count
                let isCollapsed = collapsedGroups.contains(group.titleKey)

                VStack(spacing: 6) {
                    Button {
                        toggleGroup(group.titleKey)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.secondary)
                            Text(L10n.t(group.titleKey).uppercased())
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(onCount)/\(items.count)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.accentColor)
                                .monospacedDigit()
                        }
                        .padding(.horizontal, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if !isCollapsed {
                        ForEach(items, id: \.id) { feature in
                            featureCard(feature)
                        }
                    }
                }
            }
        }
        .onAppear { hub.retain() }
        .onDisappear { hub.release() }
    }

    private func featureCard(_ feature: FeatureDef) -> some View {
        let binding = Binding<Bool>(
            get: { hub.isOn(feature) },
            set: { hub.set(feature.id, on: $0) }
        )
        return HStack(spacing: 10) {
            Image(systemName: feature.symbol)
                .font(.system(size: 13.5, weight: .medium))
                .foregroundColor(.accentColor)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.t(feature.titleKey))
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(1)
                Text(L10n.t(feature.subtitleKey))
                    .font(.system(size: 10.5))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 4)
            Toggle("", isOn: binding)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
        }
        .menubarPanelCard()
    }
}
