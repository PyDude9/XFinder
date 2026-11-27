import SwiftUI

/// Dynamic Island personal to-do page.
///
/// Reuses XFinder's white-on-black notch tokens (`XFinderTokens.Notch`, `XFinderTokens.Font`,
/// `XFinderTokens.Space`, `XFinderTokens.Radius`, `NotchPillButtonStyle`) and focus contract
/// (`@FocusState` mirrored onto `NotchTodosModel`, focus-bump counters, `isComposing` lock).
/// Completely independent from EventKit Reminders (`NotchCalendarPage` / `CalendarGlanceMonitor`).
struct NotchTodosPage: View {
    var model: NotchTodosModel
    @Environment(\.notchAccent) private var accent
    @FocusState private var focusTarget: FocusTarget?

    private typealias N = XFinderTokens.Notch

    private enum FocusTarget: Hashable {
        case addInput
        case editRow(UUID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.tight) {
            headerRow
            if model.loadError != nil || model.lastWriteError != nil {
                errorBanner
            }
            addBar
            listSection
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: focusTarget) { _, target in
            let addFocused = (target == .addInput)
            if model.isAddFieldFocused != addFocused {
                model.isAddFieldFocused = addFocused
            }
        }
        .onChange(of: model.focusAddFieldRequest) { _, _ in
            focusTarget = .addInput
        }
        .onChange(of: model.focusEditFieldRequest) { _, _ in
            if let id = model.editingItemID {
                focusTarget = .editRow(id)
            }
        }
        .onChange(of: model.editingItemID) { _, editID in
            if let editID {
                focusTarget = .editRow(editID)
            } else if case .editRow = focusTarget {
                focusTarget = nil
            }
        }
        .onChange(of: model.isAddFieldFocused) { _, focused in
            if !focused, focusTarget == .addInput {
                focusTarget = nil
            }
        }
    }

    // MARK: - Header: filter switch ("Đang làm" | "Đã xong") + selected-item quick actions

    private var headerRow: some View {
        HStack(spacing: XFinderTokens.Space.tight) {
            filterSwitch
            Spacer(minLength: XFinderTokens.Space.tight)
            if let selected = model.selectedItem,
               model.editingItemID == nil,
               model.pendingDeleteID == nil,
               !model.isReadBlocked
            {
                Button {
                    model.beginEdit(id: selected.id)
                } label: {
                    Image(systemName: "pencil")
                        .font(XFinderTokens.Font.caption)
                }
                .buttonStyle(.plain)
                .foregroundColor(.white.opacity(0.65))
                .help(L10n.t("Sửa"))
                .accessibilityLabel(L10n.t("Sửa"))

                Button {
                    model.requestDelete(id: selected.id)
                } label: {
                    Image(systemName: "trash")
                        .font(XFinderTokens.Font.caption)
                }
                .buttonStyle(.plain)
                .foregroundColor(.white.opacity(0.65))
                .help(L10n.t("Xóa mục đã chọn"))
                .accessibilityLabel(L10n.t("Xóa mục đã chọn"))
            }
        }
    }

    private var filterSwitch: some View {
        HStack(spacing: 2) {
            filterButton(
                title: L10n.t("Đang làm"),
                count: model.activeCount,
                selected: model.filter == .active
            ) {
                model.setFilter(.active)
            }
            filterButton(
                title: L10n.t("Đã xong"),
                count: model.doneCount,
                selected: model.filter == .done
            ) {
                model.setFilter(.done)
            }
        }
        .padding(2)
        .background(Capsule().fill(N.capsule))
    }

    private func filterButton(
        title: String,
        count: Int,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                Text("\(count)")
                    .monospacedDigit()
                    .opacity(selected ? 0.7 : 0.6)
            }
            .font(XFinderTokens.Font.caption).fontWeight(.medium)
            .foregroundStyle(selected ? Color.black : N.toolbarIcon)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.white.opacity(selected ? 1 : 0)))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Honest Storage Error Banner

    @ViewBuilder private var errorBanner: some View {
        HStack(spacing: XFinderTokens.Space.tight) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(XFinderTokens.Font.caption)
                .foregroundColor(.orange)
            Text(model.loadError != nil
                 ? L10n.t("Không đọc được danh sách việc. Dữ liệu cũ vẫn được giữ nguyên trên đĩa.")
                 : L10n.t("Không lưu được danh sách việc."))
                .font(XFinderTokens.Font.caption)
                .foregroundColor(.orange)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            if model.loadError != nil {
                Button(L10n.t("Thử lại")) { model.reloadFromDisk() }
                    .buttonStyle(NotchPillButtonStyle(primary: false))
                    .fixedSize()
            } else {
                Button(L10n.t("Thử lại")) { _ = model.retrySave() }
                    .buttonStyle(NotchPillButtonStyle(primary: false))
                    .fixedSize()
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: XFinderTokens.Radius.badge)
                .fill(Color.orange.opacity(0.14))
        )
    }

    // MARK: - Add Task Bar

    private var addBar: some View {
        HStack(spacing: XFinderTokens.Space.tight) {
            TextField(
                "",
                text: Bindable(model).draftTitle,
                prompt: Text(L10n.t("Thêm việc mới…")).foregroundColor(.white.opacity(0.4))
            )
            .textFieldStyle(.plain)
            .font(XFinderTokens.Font.rowValue)
            .foregroundColor(.white)
            .focused($focusTarget, equals: .addInput)
            .disabled(model.isReadBlocked)
            .onSubmit { _ = model.submitDraft() }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: XFinderTokens.Radius.control)
                    .fill(Color.white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: XFinderTokens.Radius.control)
                    .strokeBorder(focusTarget == .addInput ? accent.opacity(0.8) : Color.clear, lineWidth: 1)
            )
            .onTapGesture {
                if !model.isReadBlocked {
                    model.requestAddFieldFocus()
                }
            }

            Button(L10n.t("Thêm")) {
                _ = model.submitDraft()
            }
            .buttonStyle(NotchPillButtonStyle(primary: true))
            .disabled(!model.canSubmitDraft)
            .fixedSize()
        }
    }

    // MARK: - Todo Rows

    @ViewBuilder private var listSection: some View {
        let visible = model.visibleItems
        if visible.isEmpty {
            VStack {
                Spacer(minLength: 0)
                Text(model.filter == .active
                     ? L10n.t("Chưa có việc đang làm.")
                     : L10n.t("Chưa có việc đã xong."))
                    .font(XFinderTokens.Font.caption)
                    .foregroundColor(.white.opacity(0.55))
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(visible) { item in
                        todoRow(item)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    @ViewBuilder private func todoRow(_ item: NotchTodoItem) -> some View {
        let isSelected = model.selectedID == item.id
        let isEditing = model.editingItemID == item.id
        let isConfirmingDelete = model.pendingDeleteID == item.id

        HStack(spacing: XFinderTokens.Space.tight) {
            Button {
                _ = model.toggleCompletion(id: item.id)
            } label: {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(XFinderTokens.Font.row)
                    .foregroundStyle(item.isCompleted ? accent : Color.white.opacity(0.55))
            }
            .buttonStyle(.plain)
            .disabled(model.isReadBlocked)
            .help(item.isCompleted ? L10n.t("Bỏ đánh dấu") : L10n.t("Đánh dấu hoàn thành"))
            .accessibilityLabel(item.isCompleted ? L10n.t("Bỏ đánh dấu") : L10n.t("Đánh dấu hoàn thành"))

            if isEditing {
                TextField("", text: Bindable(model).editingText)
                    .textFieldStyle(.plain)
                    .font(XFinderTokens.Font.rowValue)
                    .foregroundColor(.white)
                    .focused($focusTarget, equals: .editRow(item.id))
                    .onSubmit { _ = model.commitEdit() }
                    .frame(minWidth: 0, maxWidth: .infinity)

                Button(L10n.t("Lưu")) { _ = model.commitEdit() }
                    .buttonStyle(NotchPillButtonStyle(primary: true))
                    .disabled(NotchTodoRules.normalizeTitle(model.editingText) == nil)
                    .fixedSize()

                Button(L10n.t("Hủy")) { model.cancelEdit() }
                    .buttonStyle(NotchPillButtonStyle(primary: false))
                    .fixedSize()
            } else if isConfirmingDelete {
                Text(L10n.t("Xóa việc này?"))
                    .font(XFinderTokens.Font.caption)
                    .foregroundColor(.orange)
                    .lineLimit(1)
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

                Button(L10n.t("Xóa")) { _ = model.confirmDelete() }
                    .buttonStyle(NotchPillButtonStyle(primary: true))
                    .fixedSize()

                Button(L10n.t("Hủy")) { model.cancelDelete() }
                    .buttonStyle(NotchPillButtonStyle(primary: false))
                    .fixedSize()
            } else {
                Text(item.title)
                    .font(XFinderTokens.Font.rowValue)
                    .strikethrough(item.isCompleted)
                    .foregroundColor(.white.opacity(item.isCompleted ? 0.55 : 1.0))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        model.beginEdit(id: item.id)
                    }
                    .onTapGesture {
                        model.select(item.id)
                    }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: XFinderTokens.Radius.badge)
                .fill(Color.white.opacity(isSelected ? 0.11 : 0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: XFinderTokens.Radius.badge)
                .strokeBorder(isSelected ? accent.opacity(0.65) : Color.clear, lineWidth: 1)
        )
    }
}
