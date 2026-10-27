import SwiftUI

/// XF-T32 W3 (contract XF-T32-w23 §F) — Edit Properties popover, Tilde layout (scratchpad/claude/tilde/
/// sheet-properties.png): ‹ · "Sửa thuộc tính" · ⋯ (Xoá thuộc tính) / "Thuộc tính" caption + name field / "Hiện trong
/// danh sách" switch / "Lựa chọn" caption + option pills with drag handles; clicking a pill opens it inline (title field
/// + the 7 colour rows Gray…Purple, × removes it) / "+ Thêm lựa chọn".
///
/// Every edit writes through `BrowserMetadata` at once (Tilde has no Save button); the name is committed on Return and
/// when the popover closes. Presented by `RowActionsMenu` in an NSPopover; `onClose` closes it.
struct PropertyEditorPopover: View {
    let propertyID: UUID
    let folder: String
    let metadata: BrowserMetadata
    /// Set by the presenter: the ‹ button and "Xoá thuộc tính" close the popover through it.
    var onClose: () -> Void = {}

    @State private var nameDraft: String = ""
    @State private var nameLoaded: Bool = false
    @State private var editingOptionID: UUID?
    @State private var optionTitleDraft: String = ""
    @State private var isAddingOption: Bool = false
    @State private var newOptionTitle: String = ""
    @State private var newOptionColor: PropertyColor = .gray
    @FocusState private var focusedField: EditorField?

    private enum EditorField: Hashable { case name, optionTitle, newOption }

    private var definition: PropertyDefinition? { metadata.catalog.definition(propertyID) }

    var body: some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
            PropertyEditorHeader(onBack: close, onDelete: deleteProperty, canDelete: definition != nil)
            if let definition: PropertyDefinition = definition {
                nameSection
                showInViewRow
                optionsSection(definition)
            } else {
                Text(L10n.t("Thuộc tính này không còn nữa"))
                    .font(XFinderTokens.Font.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(XFinderTokens.Space.inline)
        .frame(width: XFinderTokens.Settings.sidebarWidth, alignment: .leading)
        .onAppear(perform: loadName)
        .onDisappear(perform: commitName)
    }

    // MARK: - Name

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.tight) {
            PropertyEditorCaption(text: L10n.t("Thuộc tính"))
            HStack(spacing: XFinderTokens.Space.tight) {
                Image(systemName: "list.bullet")
                    .font(XFinderTokens.Font.caption)
                    .foregroundStyle(.secondary)
                TextField(L10n.t("Tên thuộc tính"), text: $nameDraft)
                    .textFieldStyle(.plain)
                    .font(XFinderTokens.Font.rowValue)
                    .focused($focusedField, equals: .name)
                    .onSubmit(commitName)
            }
            .padding(.horizontal, XFinderTokens.Space.tight)
            .padding(.vertical, XFinderTokens.Space.hairline)
            .background(RoundedRectangle(cornerRadius: XFinderTokens.Radius.badge).fill(XFinderTokens.Fill.inset))
        }
    }

    private func loadName() {
        guard !nameLoaded, let definition: PropertyDefinition = definition else { return }
        nameDraft = definition.name
        nameLoaded = true
        focusedField = .name
    }

    /// Empty / unchanged ⇒ no write; an empty field snaps back to the stored name.
    private func commitName() {
        guard let definition: PropertyDefinition = definition else { return }
        let trimmed: String = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            nameDraft = definition.name
            return
        }
        guard trimmed != definition.name else { return }
        let id: UUID = propertyID
        metadata.updateCatalog { (catalog: inout PropertyCatalog) in
            _ = catalog.rename(id, to: trimmed)
        }
        nameDraft = metadata.catalog.definition(id)?.name ?? trimmed
    }

    // MARK: - Show in view

    private var showInViewRow: some View {
        Toggle(isOn: showInViewBinding) {
            Text(L10n.t("Hiện trong danh sách"))
                .font(XFinderTokens.Font.rowValue)
        }
        .toggleStyle(.switch)
        .controlSize(.small)
    }

    private var showInViewBinding: Binding<Bool> {
        Binding<Bool>(
            get: { metadata.shownProperties(in: folder).first { $0.definition.id == propertyID }?.showInView ?? false },
            set: { (shown: Bool) in setShowInView(shown) }
        )
    }

    /// Keeps the folder's property order; a property the folder does not list yet is appended.
    private func setShowInView(_ shown: Bool) {
        var list: [(property: UUID, showInView: Bool)] = metadata.shownProperties(in: folder).map {
            (property: $0.definition.id, showInView: $0.showInView)
        }
        if let index: Int = list.firstIndex(where: { $0.property == propertyID }) {
            guard list[index].showInView != shown else { return }
            list[index].showInView = shown
        } else {
            list.append((property: propertyID, showInView: shown))
        }
        metadata.setFolderProperties(folder, list)
    }

    // MARK: - Options

    private func optionsSection(_ definition: PropertyDefinition) -> some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.tight) {
            PropertyEditorCaption(text: L10n.t("Lựa chọn"))
            ForEach(definition.options) { (option: PropertyOption) in
                optionRow(option, in: definition)
            }
            if isAddingOption {
                newOptionEditor
            } else {
                addOptionButton(definition)
            }
        }
    }

    @ViewBuilder
    private func optionRow(_ option: PropertyOption, in definition: PropertyDefinition) -> some View {
        let isEditing: Bool = editingOptionID == option.id
        VStack(alignment: .leading, spacing: XFinderTokens.Space.tight) {
            HStack(spacing: XFinderTokens.Space.tight) {
                Image(systemName: "line.3.horizontal")
                    .font(XFinderTokens.Font.caption)
                    .foregroundStyle(.tertiary)
                Button(action: { toggleEditing(option) }) {
                    PropertyOptionPill(title: option.title, color: option.color)
                }
                .buttonStyle(.plain)
                Spacer(minLength: .zero)
                if isEditing {
                    Button(action: { removeOption(option.id) }) {
                        Image(systemName: "xmark")
                            .font(XFinderTokens.Font.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(L10n.t("Xoá lựa chọn"))
                }
            }
            .padding(.horizontal, XFinderTokens.Space.hairline)
            .padding(.vertical, XFinderTokens.Space.hairline)
            .background(RoundedRectangle(cornerRadius: XFinderTokens.Radius.badge)
                .fill(isEditing ? XFinderTokens.Fill.inset : Color.clear))
            .contentShape(Rectangle())
            .draggable(option.id.uuidString)
            .dropDestination(for: String.self) { (items: [String], _: CGPoint) -> Bool in
                moveOption(items.first, onto: option.id, in: definition)
            }
            if isEditing {
                PropertyOptionColorEditor(
                    title: $optionTitleDraft,
                    selected: option.color,
                    focus: $focusedField,
                    focusValue: EditorField.optionTitle,
                    onTitleChange: { (title: String) in updateOption(option.id, title: title, color: nil) },
                    onSubmit: { editingOptionID = nil },
                    onPick: { (color: PropertyColor) in updateOption(option.id, title: nil, color: color) }
                )
            }
        }
    }

    private func addOptionButton(_ definition: PropertyDefinition) -> some View {
        Button(action: { startAddingOption(definition) }) {
            Label(L10n.t("Thêm lựa chọn"), systemImage: "plus")
                .font(XFinderTokens.Font.rowValue)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }

    private var newOptionEditor: some View {
        PropertyOptionColorEditor(
            title: $newOptionTitle,
            selected: newOptionColor,
            focus: $focusedField,
            focusValue: EditorField.newOption,
            onTitleChange: { (_: String) in },
            onSubmit: commitNewOption,
            onPick: { (color: PropertyColor) in newOptionColor = color }
        )
    }

    private func toggleEditing(_ option: PropertyOption) {
        if editingOptionID == option.id {
            editingOptionID = nil
            return
        }
        isAddingOption = false
        optionTitleDraft = option.title
        editingOptionID = option.id
        focusedField = .optionTitle
    }

    /// The next colour in Tilde's palette order, so consecutive new options are told apart at a glance.
    private func startAddingOption(_ definition: PropertyDefinition) {
        editingOptionID = nil
        newOptionTitle = ""
        let palette: [PropertyColor] = PropertyColor.allCases
        newOptionColor = palette[definition.options.count % palette.count]
        isAddingOption = true
        focusedField = .newOption
    }

    /// Empty title ⇒ the draft is dropped (an option needs a title); otherwise the new option opens for editing.
    private func commitNewOption() {
        let title: String = newOptionTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        isAddingOption = false
        guard !title.isEmpty else { return }
        let id: UUID = propertyID
        let color: PropertyColor = newOptionColor
        var created: PropertyOption?
        metadata.updateCatalog { (catalog: inout PropertyCatalog) in
            created = catalog.addOption(id, title: title, color: color)
        }
        newOptionTitle = ""
        guard let option: PropertyOption = created else { return }
        optionTitleDraft = option.title
        editingOptionID = option.id
        focusedField = .optionTitle
    }

    /// Live title edits: an empty field is not written (the stored title stays until a non-empty one is typed).
    private func updateOption(_ optionID: UUID, title: String?, color: PropertyColor?) {
        guard let current: PropertyOption = definition?.options.first(where: { $0.id == optionID }) else { return }
        let newTitle: String = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? current.title
        guard !newTitle.isEmpty else { return }
        let updated: PropertyOption = PropertyOption(id: optionID, title: newTitle, color: color ?? current.color)
        guard updated != current else { return }
        let id: UUID = propertyID
        metadata.updateCatalog { (catalog: inout PropertyCatalog) in
            _ = catalog.updateOption(id, option: updated)
        }
    }

    private func removeOption(_ optionID: UUID) {
        editingOptionID = nil
        let id: UUID = propertyID
        metadata.updateCatalog { (catalog: inout PropertyCatalog) in
            catalog.removeOption(id, option: optionID)
        }
    }

    /// Drop of a dragged option (its id string) onto `target`: the dragged option takes the target's index.
    private func moveOption(_ dragged: String?, onto target: UUID, in definition: PropertyDefinition) -> Bool {
        guard let raw: String = dragged, let draggedID: UUID = UUID(uuidString: raw), draggedID != target,
              let from: Int = definition.options.firstIndex(where: { $0.id == draggedID }),
              let to: Int = definition.options.firstIndex(where: { $0.id == target }) else { return false }
        let id: UUID = propertyID
        metadata.updateCatalog { (catalog: inout PropertyCatalog) in
            catalog.moveOption(id, from: from, to: to)
        }
        return true
    }

    // MARK: - Close / delete

    private func close() {
        commitName()
        onClose()
    }

    /// Removes the property from the catalog (its selections go with it, `MetadataStore`) and from this folder's list.
    private func deleteProperty() {
        let id: UUID = propertyID
        let remaining: [(property: UUID, showInView: Bool)] = metadata.shownProperties(in: folder)
            .filter { $0.definition.id != id }
            .map { (property: $0.definition.id, showInView: $0.showInView) }
        metadata.setFolderProperties(folder, remaining)
        metadata.updateCatalog { (catalog: inout PropertyCatalog) in
            catalog.delete(id)
        }
        onClose()
    }
}

// MARK: - Pieces

/// ‹ · title · ⋯ menu (Xoá thuộc tính).
private struct PropertyEditorHeader: View {
    let onBack: () -> Void
    let onDelete: () -> Void
    let canDelete: Bool

    var body: some View {
        HStack(spacing: XFinderTokens.Space.tight) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(XFinderTokens.Font.caption)
            }
            .buttonStyle(.plain)
            .help(L10n.t("Quay lại"))
            Text(L10n.t("Sửa thuộc tính"))
                .font(XFinderTokens.Font.sectionTitle)
            Spacer(minLength: .zero)
            Menu {
                Button(L10n.t("Xoá thuộc tính"), role: .destructive, action: onDelete)
                    .disabled(!canDelete)
            } label: {
                Image(systemName: "ellipsis")
                    .font(XFinderTokens.Font.caption)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }
}

private struct PropertyEditorCaption: View {
    let text: String

    var body: some View {
        Text(text)
            .font(XFinderTokens.Font.caption)
            .foregroundStyle(.secondary)
    }
}

/// The coloured option pill (same chip as the list: tint at `chipFill` behind semibold tint text).
private struct PropertyOptionPill: View {
    let title: String
    let color: PropertyColor

    var body: some View {
        let tint: Color = XFinderTokens.PropertyTint.color(color)
        Text(title)
            .font(XFinderTokens.Font.caption.weight(.semibold))
            .lineLimit(1)
            .truncationMode(.middle)
            .foregroundStyle(tint)
            .padding(.horizontal, XFinderTokens.Space.tight)
            .padding(.vertical, XFinderTokens.Space.hairline)
            .background(Capsule().fill(tint.opacity(XFinderTokens.PropertyTint.chipFill)))
    }
}

/// Inline option editor: a title field, then one row per colour (dot + name), the current colour highlighted.
private struct PropertyOptionColorEditor<Field: Hashable>: View {
    @Binding var title: String
    let selected: PropertyColor
    let focus: FocusState<Field?>.Binding
    let focusValue: Field
    let onTitleChange: (String) -> Void
    let onSubmit: () -> Void
    let onPick: (PropertyColor) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.hairline) {
            TextField(L10n.t("Tên lựa chọn"), text: $title)
                .textFieldStyle(.roundedBorder)
                .font(XFinderTokens.Font.rowValue)
                .focused(focus, equals: focusValue)
                .onSubmit(onSubmit)
                .onChange(of: title) { (_: String, newValue: String) in onTitleChange(newValue) }
                .padding(.bottom, XFinderTokens.Space.hairline)
            ForEach(PropertyColor.allCases, id: \.self) { (color: PropertyColor) in
                Button(action: { onPick(color) }) {
                    HStack(spacing: XFinderTokens.Space.tight) {
                        Circle()
                            .fill(XFinderTokens.PropertyTint.color(color))
                            .frame(width: XFinderTokens.Space.row, height: XFinderTokens.Space.row)
                        Text(L10n.t(color.titleKey))
                            .font(XFinderTokens.Font.rowValue)
                        Spacer(minLength: .zero)
                    }
                    .padding(.horizontal, XFinderTokens.Space.tight)
                    .padding(.vertical, XFinderTokens.Space.hairline)
                    .background(RoundedRectangle(cornerRadius: XFinderTokens.Radius.badge)
                        .fill(color == selected ? XFinderTokens.Fill.inset : Color.clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.leading, XFinderTokens.Space.inline)
    }
}
