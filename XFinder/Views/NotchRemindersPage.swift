import SwiftUI
import AppKit

/// Dynamic Island Reminders module (EventKit).
/// Permissions are requested ONLY when the user explicitly clicks the grant CTA.
/// Adapts between Ref29 wide (`612 pt`) and narrow (`382 pt`) Island bodies using XFinder tokens.
struct NotchRemindersPage: View {
    @ObservedObject var viewModel: RemindersViewModel
    var embedsInIsland: Bool = true

    @Environment(\.notchAccent) private var accent
    @FocusState private var isDraftFocused: Bool

    private typealias N = XFinderTokens.Notch
    private var locale: Locale { Locale(identifier: L10n.isEnglish ? "en_US" : "vi_VN") }

    var body: some View {
        GeometryReader { geo in
            let isNarrow = geo.size.width < 460
            VStack(alignment: .leading, spacing: isNarrow ? 5 : 6) {
                headerBar(isNarrow: isNarrow)
                Divider().overlay(Color.white.opacity(0.10))
                contentBody(isNarrow: isNarrow)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .onAppear {
            if !embedsInIsland { viewModel.onAppear() }
        }
        .onDisappear {
            if !embedsInIsland { viewModel.close() }
        }
    }

    // MARK: - Header

    private func headerBar(isNarrow: Bool) -> some View {
        HStack(spacing: XFinderTokens.Space.tight) {
            Image(systemName: "checklist")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(accent)

            Text(L10n.t("Nhắc việc"))
                .font(.system(size: isNarrow ? 11.5 : 12.5, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)

            if viewModel.accessState == .authorized {
                Text("\(viewModel.incompleteCount)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(N.capsule))
            }

            Spacer(minLength: XFinderTokens.Space.tight)

            if viewModel.accessState == .authorized {
                if !isNarrow {
                    filterStrip
                }

                Button {
                    Task { await viewModel.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))
                }
                .buttonStyle(.plain)
                .help(L10n.t("Làm mới"))
                .accessibilityLabel(L10n.t("Làm mới"))

                Button {
                    if viewModel.isCreating {
                        viewModel.closeComposer()
                    } else {
                        viewModel.openComposer()
                        isDraftFocused = true
                    }
                } label: {
                    Image(systemName: viewModel.isCreating ? "xmark.circle.fill" : "plus.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(viewModel.isCreating ? .white.opacity(0.8) : accent)
                }
                .buttonStyle(.plain)
                .help(viewModel.isCreating ? L10n.t("Đóng tạo nhắc việc") : L10n.t("Thêm nhắc việc"))
                .accessibilityLabel(viewModel.isCreating ? L10n.t("Đóng tạo nhắc việc") : L10n.t("Thêm nhắc việc"))
            }
        }
    }

    private var filterStrip: some View {
        HStack(spacing: 2) {
            filterChip(.today, label: L10n.t("Hôm nay"))
            filterChip(.upcoming, label: L10n.t("Sắp tới"))
            filterChip(.all, label: L10n.t("Tất cả"))
            filterChip(.completed, label: L10n.t("Đã xong"))
        }
        .padding(2)
        .background(Capsule().fill(N.capsule))
    }

    private func filterChip(_ target: RemindersFilter, label: String) -> some View {
        let selected = viewModel.filter == target
        return Button {
            viewModel.filter = target
        } label: {
            Text(label)
                .font(.system(size: 9.5, weight: selected ? .semibold : .medium))
                .foregroundStyle(selected ? .black : .white.opacity(0.72))
                .padding(.horizontal, 6)
                .frame(height: 16)
                .background(Capsule().fill(selected ? Color.white : Color.clear))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    // MARK: - Body states

    @ViewBuilder private func contentBody(isNarrow: Bool) -> some View {
        switch viewModel.accessState {
        case .notDetermined:
            permissionState(
                symbol: "checklist",
                message: L10n.t("Chưa có quyền Nhắc việc. Cấp quyền để xem, tạo và hoàn thành lời nhắc ngay trên notch."),
                ctaTitle: L10n.t("Cấp quyền Nhắc việc")
            ) {
                Task { await viewModel.requestAccess() }
            }
        case .denied:
            permissionState(
                symbol: "exclamationmark.shield",
                message: L10n.t("Quyền Nhắc việc bị từ chối — mở Cài đặt hệ thống ▸ Quyền riêng tư ▸ Nhắc việc để bật lại."),
                ctaTitle: L10n.t("Mở Cài đặt hệ thống")
            ) {
                RemindersEventKitStore.openPrivacySettings()
            }
        case .restricted:
            unavailableState(
                symbol: "lock.fill",
                message: L10n.t("Quyền Nhắc việc bị giới hạn trên máy này.")
            )
        case .unavailable:
            unavailableState(
                symbol: "macbook.slash",
                message: L10n.t("Nhắc việc cần macOS 14 trở lên.")
            )
        case .authorized:
            authorizedBody(isNarrow: isNarrow)
        }
    }

    private func permissionState(symbol: String, message: String, ctaTitle: String, action: @escaping () -> Void) -> some View {
        VStack(spacing: XFinderTokens.Space.tight) {
            Image(systemName: symbol)
                .font(XFinderTokens.Font.pageIcon)
                .foregroundStyle(.white.opacity(0.65))
            Text(message)
                .font(XFinderTokens.Font.caption)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button(ctaTitle, action: action)
                .buttonStyle(.borderedProminent)
                .tint(accent)
                .controlSize(.mini)
                .disabled(viewModel.isRequestingAccess)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func unavailableState(symbol: String, message: String) -> some View {
        VStack(spacing: XFinderTokens.Space.tight) {
            Image(systemName: symbol)
                .font(XFinderTokens.Font.pageIcon)
                .foregroundStyle(.white.opacity(0.55))
            Text(message)
                .font(XFinderTokens.Font.caption)
                .foregroundStyle(.white.opacity(0.65))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private func authorizedBody(isNarrow: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            if isNarrow {
                filterStrip
            }

            if let errorKey = viewModel.errorMessageKey {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                    Text(L10n.t(errorKey))
                        .font(XFinderTokens.Font.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                }
            }

            if viewModel.isCreating {
                composerBar
            }

            let list = viewModel.visibleItems
            if viewModel.isLoading && list.isEmpty {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(L10n.t("Đang tải lời nhắc…"))
                        .font(XFinderTokens.Font.caption)
                        .foregroundStyle(.white.opacity(0.65))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if list.isEmpty {
                VStack(spacing: 5) {
                    Text(L10n.t("Không có lời nhắc nào trong mục này."))
                        .font(XFinderTokens.Font.caption)
                        .foregroundStyle(.white.opacity(0.6))
                    if !viewModel.isCreating && viewModel.filter != .completed {
                        Button(L10n.t("Thêm nhắc việc")) {
                            viewModel.openComposer()
                            isDraftFocused = true
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(list) { item in
                            reminderRow(item)
                        }
                    }
                }
            }
        }
    }

    private var composerBar: some View {
        HStack(spacing: XFinderTokens.Space.tight) {
            TextField(L10n.t("Nội dung nhắc việc…"), text: $viewModel.draftTitle)
                .textFieldStyle(.plain)
                .font(XFinderTokens.Font.caption)
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: XFinderTokens.Radius.badge).fill(N.capsule))
                .focused($isDraftFocused)
                .onSubmit {
                    Task { await viewModel.createReminder() }
                }

            duePresetPicker

            Button {
                Task { await viewModel.createReminder() }
            } label: {
                Text(L10n.t("Lưu"))
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.white))
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isSubmitting || viewModel.draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel(L10n.t("Lưu nhắc việc"))
        }
    }

    private var duePresetPicker: some View {
        HStack(spacing: 2) {
            dueChip(.none, label: L10n.t("Không hạn"))
            dueChip(.today, label: L10n.t("Hôm nay"))
            dueChip(.tomorrow, label: L10n.t("Ngày mai"))
        }
        .padding(2)
        .background(Capsule().fill(N.capsule))
    }

    private func dueChip(_ target: ReminderDuePreset, label: String) -> some View {
        let selected = viewModel.draftDuePreset == target
        return Button {
            viewModel.draftDuePreset = target
        } label: {
            Text(label)
                .font(.system(size: 9, weight: selected ? .semibold : .medium))
                .foregroundStyle(selected ? .black : .white.opacity(0.7))
                .padding(.horizontal, 5)
                .frame(height: 16)
                .background(Capsule().fill(selected ? Color.white : Color.clear))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func reminderRow(_ item: ReminderItem) -> some View {
        let overdue = RemindersRules.isOverdue(item, now: Date())
        return HStack(spacing: XFinderTokens.Space.tight) {
            Button {
                Task { await viewModel.toggleComplete(item) }
            } label: {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(item.isCompleted ? accent : .white.opacity(0.65))
            }
            .buttonStyle(.plain)
            .help(item.isCompleted ? L10n.t("Đánh dấu chưa xong") : L10n.t("Hoàn thành nhắc việc"))
            .accessibilityLabel(item.isCompleted ? L10n.t("Đánh dấu chưa xong") : L10n.t("Hoàn thành nhắc việc"))
            .accessibilityValue(item.title)

            Text(item.title.isEmpty ? L10n.t("Nhắc việc") : item.title)
                .font(XFinderTokens.Font.caption)
                .foregroundStyle(.white.opacity(item.isCompleted ? 0.45 : 0.92))
                .strikethrough(item.isCompleted, color: .white.opacity(0.45))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: XFinderTokens.Space.tight)

            if let due = item.dueDate {
                Text(due.formatted(.dateTime.day().month(.abbreviated).hour().minute().locale(locale)))
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(overdue ? Color.orange : Color.white.opacity(0.55))
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}
