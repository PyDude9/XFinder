import SwiftUI
import AppKit
import Foundation

/// XF-T32 W2 (contract XF-T32-w23 §C) — one sidebar section per Live Group of the active Space (Tilde: "In Progress •"
/// small secondary title with the option's colour dot after the name; rows = every item set to that option, icon 16 pt +
/// nickname or last path component, 28 pt, selected = gray rounded 8). A group whose property or option was deleted is
/// dropped by `BrowserMetadata.liveGroups`; an empty group still shows its section with a secondary "Trống" row.
/// No refs ⇒ nothing is rendered.
struct SidebarLiveGroupsSection: View {
    let spaces: SpaceController
    let metadata: BrowserMetadata
    let onOpen: (String) -> Void
    let isSelected: (String) -> Bool

    private struct RefreshKey: Equatable {
        var revision: Int
        var refs: [LiveGroupRef]
    }
    private struct IdentifiedGroup: Identifiable {
        var value: PropertyRules.LiveGroup
        var id: LiveGroupRef { LiveGroupRef(propertyID: value.property.id, optionID: value.option.id) }
    }
    @State private var directoryPaths: Set<String> = []
    @State private var loadedKey: RefreshKey?

    var body: some View {
        let refs = spaces.active.liveGroups
        let key = RefreshKey(revision: metadata.revision, refs: refs)
        let groups = metadata.liveGroups(refs)
        if !refs.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(groups.map { IdentifiedGroup(value: $0) }) { identified in
                    let group = identified.value
                    let folders = PropertyRules.LiveGroup(property: group.property, option: group.option,
                                                         paths: group.paths.filter { directoryPaths.contains($0) })
                    LiveGroupBlock(group: folders, metadata: metadata, onOpen: onOpen,
                                   isSelected: isSelected, loading: loadedKey != key) {
                        spaces.toggleLiveGroup(identified.id)
                    }
                }
            }
            .task(id: key) {
                let paths = Set(groups.flatMap(\.paths))
                let directories = await Task.detached(priority: .utility) {
                    Set(paths.filter { path in
                        let facts = try? URL(fileURLWithPath: path).resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
                        return facts?.isDirectory == true && facts?.isPackage != true
                    })
                }.value
                guard !Task.isCancelled else { return }
                directoryPaths = directories
                loadedKey = key
            }
        }
    }
}

// MARK: - One group

private struct LiveGroupBlock: View {
    let group: PropertyRules.LiveGroup
    let metadata: BrowserMetadata
    let onOpen: (String) -> Void
    let isSelected: (String) -> Bool
    let loading: Bool
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            title
            if loading || group.paths.isEmpty {
                Text(loading ? L10n.t("Đang tải…") : L10n.t("Trống"))
                    .font(XFinderTokens.BrowserSidebar.row)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, XFinderTokens.Space.row)
                    .frame(maxWidth: .infinity, minHeight: XFinderTokens.BrowserSidebar.rowHeight,
                           maxHeight: XFinderTokens.BrowserSidebar.rowHeight, alignment: .leading)
            } else {
                ForEach(group.paths, id: \.self) { (path: String) in
                    LiveGroupRow(path: path, name: displayName(path), selected: isSelected(path)) { onOpen(path) }
                }
            }
        }
    }

    private var title: some View {
        HStack(spacing: XFinderTokens.Space.tight) {
            Text(group.option.title)
                .font(XFinderTokens.BrowserSidebar.sectionTitle)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Circle()
                .fill(XFinderTokens.PropertyTint.color(group.option.color))
                .frame(width: XFinderTokens.BrowserSidebar.groupDot, height: XFinderTokens.BrowserSidebar.groupDot)
                .accessibilityHidden(true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, XFinderTokens.Space.row)
        .padding(.top, XFinderTokens.BrowserSidebar.sectionTopGap)
        .padding(.bottom, XFinderTokens.Space.hairline)
        .contentShape(Rectangle())
        .contextMenu {
            Button(L10n.t("Bỏ khỏi thanh bên"), action: onRemove)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    /// Nickname when set, else the last path component (a root "/" keeps "/" rather than an empty label).
    private func displayName(_ path: String) -> String {
        if let nickname: String = metadata.nickname(for: path), !nickname.isEmpty { return nickname }
        let last: String = (path as NSString).lastPathComponent
        return last.isEmpty ? path : last
    }
}

// MARK: - One row

fileprivate struct LiveGroupRow: View {
    let path: String
    let name: String
    let selected: Bool
    let onOpen: () -> Void

    @State private var hovering: Bool = false

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: XFinderTokens.Space.tight) {
                Image(nsImage: FileIconCache.shared.icon(forPath: path))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: XFinderTokens.BrowserSidebar.iconSize, height: XFinderTokens.BrowserSidebar.iconSize)
                    .accessibilityHidden(true)
                Text(name)
                    .font(XFinderTokens.BrowserSidebar.row)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, XFinderTokens.Space.row)
            .frame(height: XFinderTokens.BrowserSidebar.rowHeight)
            .background(background)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { (inside: Bool) in hovering = inside }
        .help(path)
        .accessibilityLabel(name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder private var background: some View {
        if selected {
            RoundedRectangle(cornerRadius: XFinderTokens.BrowserSidebar.rowRadius, style: .continuous)
                .fill(XFinderTokens.BrowserSidebar.selectedFill)
        } else if hovering {
            RoundedRectangle(cornerRadius: XFinderTokens.BrowserSidebar.rowRadius, style: .continuous)
                .fill(XFinderTokens.Fill.hover)
        }
    }
}

// MARK: - Folder-based Live Groups (Space scoped)

struct FolderLiveGroupSidebarBlock: View {
    let group: FolderLiveGroup
    let isSelected: (String) -> Bool
    let onOpen: (DirectoryEntry) -> Void
    let onEdit: () -> Void
    let onRemove: () -> Void

    @State private var entries: [DirectoryEntry] = []
    @State private var loading: Bool = true
    @State private var subscription: ListingSubscription?
    @State private var projectionID: Int = 0
    @State private var subscriptionID: UUID?
    @State private var sourceErrorKey: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if loading {
                Text(L10n.t("Đang tải…"))
                    .font(XFinderTokens.BrowserSidebar.row)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, XFinderTokens.Space.row)
                    .frame(maxWidth: .infinity, minHeight: XFinderTokens.BrowserSidebar.rowHeight,
                           maxHeight: XFinderTokens.BrowserSidebar.rowHeight, alignment: .leading)
            } else if let sourceErrorKey {
                Text(L10n.t(sourceErrorKey))
                    .font(XFinderTokens.BrowserSidebar.row)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, XFinderTokens.Space.row)
            } else if entries.isEmpty {
                Text(L10n.t("Trống"))
                    .font(XFinderTokens.BrowserSidebar.row)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, XFinderTokens.Space.row)
                    .frame(maxWidth: .infinity, minHeight: XFinderTokens.BrowserSidebar.rowHeight,
                           maxHeight: XFinderTokens.BrowserSidebar.rowHeight, alignment: .leading)
            } else {
                ForEach(entries) { entry in
                    LiveGroupRow(path: entry.path, name: entry.name, selected: isSelected(entry.path)) {
                        onOpen(entry)
                    }
                }
            }
        }
        .task(id: group) {
            subscribe()
        }
        .onDisappear {
            subscriptionID = nil
            projectionID += 1
            subscription?.cancel()
            subscription = nil
        }
    }

    private var header: some View {
        HStack(spacing: XFinderTokens.Space.tight) {
            Text(group.name)
                .font(XFinderTokens.BrowserSidebar.sectionTitle)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Circle()
                .fill(Color.blue)
                .frame(width: XFinderTokens.BrowserSidebar.groupDot, height: XFinderTokens.BrowserSidebar.groupDot)
                .accessibilityHidden(true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, XFinderTokens.Space.row)
        .padding(.top, XFinderTokens.BrowserSidebar.sectionTopGap)
        .padding(.bottom, XFinderTokens.Space.hairline)
        .contentShape(Rectangle())
        .contextMenu {
            Button(L10n.t("Chỉnh sửa Live Group…"), action: onEdit)
            Button(L10n.t("Bỏ khỏi thanh bên"), action: onRemove)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private func subscribe() {
        subscription?.cancel()
        loading = true
        projectionID += 1
        let token = UUID()
        subscriptionID = token
        sourceErrorKey = nil
        let currentGroup = group

        subscription = DirectoryLoadCoordinator.shared.subscribe(
            path: group.sourcePath,
            onListing: { result in
                guard self.subscriptionID == token else { return }
                self.projectionID += 1
                let currentProjectionID = self.projectionID
                switch result {
                case .success(let delivery):
                    self.sourceErrorKey = nil
                    Task.detached(priority: .userInitiated) {
                        let candidates = delivery.entries.map {
                            FolderLiveGroup.Candidate(path: $0.path, name: $0.name, isDirectory: $0.isFolderLike, modifiedDate: $0.modified)
                        }
                        let matched = currentGroup.matching(candidates)
                        let matchedPaths = Set(matched.map(\.path))
                        let order = Dictionary(uniqueKeysWithValues: matched.enumerated().map { ($1.path, $0) })
                        let filtered = delivery.entries.filter { matchedPaths.contains($0.path) }
                            .sorted { (order[$0.path] ?? 0) < (order[$1.path] ?? 0) }

                        await MainActor.run {
                            guard self.projectionID == currentProjectionID else { return }
                            self.entries = filtered
                            self.loading = false
                        }
                    }
                case .failure(let error):
                    self.sourceErrorKey = error.messageKey
                    self.entries = []
                    self.loading = false
                }
            },
            onGone: {
                guard self.subscriptionID == token else { return }
                self.projectionID += 1
                self.sourceErrorKey = "Thư mục không còn tồn tại"
                self.entries = []
                self.loading = false
            }
        )
    }
}

// MARK: - Folder Live Group Editor Sheet

struct FolderLiveGroupEditor: View {
    let group: FolderLiveGroup
    let onSave: (FolderLiveGroup) -> Bool
    let onClose: () -> Void

    @State private var name: String
    @State private var sourcePath: String
    @State private var filters: [FolderLiveGroup.Filter]
    @State private var sort: FolderLiveGroup.Sort
    @State private var sourceEntries: [DirectoryEntry] = []
    @State private var previewEntries: [DirectoryEntry] = []
    @State private var previewLoading: Bool = false
    @State private var subscription: ListingSubscription?
    @State private var projectionID: Int = 0
    @State private var subscriptionID: UUID?
    @State private var sourceErrorKey: String?
    @State private var validatedSourcePath: String?
    @State private var saveFailed = false
    @FocusState private var nameFocused: Bool

    init(group: FolderLiveGroup, onSave: @escaping (FolderLiveGroup) -> Bool, onClose: @escaping () -> Void) {
        self.group = group
        self.onSave = onSave
        self.onClose = onClose
        _name = State(initialValue: group.name)
        _sourcePath = State(initialValue: group.sourcePath)
        _filters = State(initialValue: group.filters.isEmpty ? [FolderLiveGroup.Filter(field: .name, operation: .contains, value: "")] : group.filters)
        _sort = State(initialValue: group.sort)
    }

    private var expandedSourcePath: String {
        (sourcePath as NSString).expandingTildeInPath
    }

    private var candidateGroup: FolderLiveGroup? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, expandedSourcePath.hasPrefix("/") else { return nil }
        let g = FolderLiveGroup(id: group.id, name: trimmedName, sourcePath: expandedSourcePath, filters: filters, sort: sort)
        return g.normalized
    }

    private var isSourcePathValid: Bool {
        validatedSourcePath == expandedSourcePath && sourceErrorKey == nil
    }

    private var canSave: Bool {
        candidateGroup != nil && isSourcePathValid && !previewLoading
    }

    var body: some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
            header
            Divider()
            HStack(alignment: .top, spacing: XFinderTokens.Space.section) {
                leftForm
                    .frame(maxWidth: .infinity, alignment: .leading)
                Divider()
                rightPreview
                    .frame(width: XFinderTokens.BrowserSidebar.liveGroupPreviewWidth)
            }
            .frame(maxHeight: .infinity)
            Divider()
            footerBar
        }
        .padding(XFinderTokens.Space.page)
        .frame(width: XFinderTokens.BrowserSidebar.liveGroupSheetWidth,
               height: XFinderTokens.BrowserSidebar.liveGroupSheetHeight)
        .task {
            await Task.yield()
            nameFocused = true
        }
        .task(id: expandedSourcePath) {
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            guard !Task.isCancelled else { return }
            subscribeToSource()
        }
        .onDisappear {
            subscriptionID = nil
            projectionID += 1
            subscription?.cancel()
            subscription = nil
        }
        .onChange(of: sourcePath) { _, _ in
            subscriptionID = nil
            projectionID += 1
            subscription?.cancel()
            subscription = nil
            validatedSourcePath = nil
            sourceErrorKey = nil
            sourceEntries = []
            previewEntries = []
            previewLoading = true
        }
        .onChange(of: name) { _, _ in updatePreview(entries: sourceEntries) }
        .onChange(of: sort) { _, _ in
            updatePreview(entries: sourceEntries)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.hairline) {
            Text(L10n.t("Live Group mới"))
                .font(XFinderTokens.Font.pageTitle)
            Text(L10n.t("Live Group tự động đồng bộ với thư mục nguồn, chỉ hiển thị các mục khớp với bộ lọc của bạn."))
                .font(XFinderTokens.Font.sectionSubtitle)
                .foregroundColor(.secondary)
        }
    }

    private var leftForm: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: XFinderTokens.Space.section) {
                nameSection
                sourceSection
                filtersSection
                sortingSection
            }
            .padding(.trailing, XFinderTokens.Space.tight)
        }
    }

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.tight) {
            Text(L10n.t("Tên"))
                .font(XFinderTokens.Font.caption)
                .foregroundColor(.secondary)
            TextField(L10n.t("Live Group"), text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($nameFocused)
        }
    }

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.tight) {
            Text(L10n.t("Thư mục nguồn"))
                .font(XFinderTokens.Font.caption)
                .foregroundColor(.secondary)
            HStack(spacing: XFinderTokens.Space.tight) {
                TextField(L10n.t("Đường dẫn thư mục"), text: $sourcePath)
                    .textFieldStyle(.roundedBorder)
                Button(L10n.t("Chọn…")) {
                    chooseSourceFolder()
                }
            }
        }
    }

    private var filtersSection: some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.tight) {
            Text(L10n.t("Bộ lọc"))
                .font(XFinderTokens.Font.caption)
                .foregroundColor(.secondary)

            VStack(spacing: XFinderTokens.Space.tight) {
                ForEach(filters.indices, id: \.self) { index in
                    filterRow(index: index)
                }
            }

            HStack(spacing: XFinderTokens.Space.page) {
                Button {
                    addFilter()
                } label: {
                    Label(L10n.t("Thêm bộ lọc"), systemImage: "plus")
                }
                .buttonStyle(.borderless)

                Button {
                    clearFilters()
                } label: {
                    Label(L10n.t("Xoá bộ lọc"), systemImage: "trash")
                }
                .buttonStyle(.borderless)
                .foregroundColor(.red)

                Spacer()
            }
            .padding(.top, XFinderTokens.Space.hairline)
        }
    }

    @ViewBuilder
    private func filterRow(index: Int) -> some View {
        HStack(spacing: XFinderTokens.Space.tight) {
            Picker("", selection: Binding(
                get: { filters[index].field },
                set: { newField in
                    filters[index].field = newField
                    if newField == .kind {
                        filters[index].operation = .equals
                        filters[index].value = "folder"
                    } else if filters[index].value == "folder" || filters[index].value == "file" {
                        filters[index].value = ""
                    }
                    updatePreview(entries: sourceEntries)
                }
            )) {
                Text(L10n.t("Tên")).tag(FolderLiveGroup.Field.name)
                Text(L10n.t("Phần mở rộng")).tag(FolderLiveGroup.Field.fileExtension)
                Text(L10n.t("Loại")).tag(FolderLiveGroup.Field.kind)
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 120)

            if filters[index].field == .kind {
                Picker("", selection: $filters[index].operation) {
                    Text(L10n.t("Là")).tag(FolderLiveGroup.MatchOperator.equals)
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 100)
                .disabled(true)

                Picker("", selection: Binding(
                    get: { filters[index].value },
                    set: { newVal in
                        filters[index].value = newVal
                        updatePreview(entries: sourceEntries)
                    }
                )) {
                    Text(L10n.t("Thư mục")).tag("folder")
                    Text(L10n.t("Tệp")).tag("file")
                }
                .labelsHidden()
                .pickerStyle(.menu)
            } else {
                Picker("", selection: Binding(
                    get: { filters[index].operation },
                    set: { newOp in
                        filters[index].operation = newOp
                        updatePreview(entries: sourceEntries)
                    }
                )) {
                    Text(L10n.t("Chứa")).tag(FolderLiveGroup.MatchOperator.contains)
                    Text(L10n.t("Bằng")).tag(FolderLiveGroup.MatchOperator.equals)
                    Text(L10n.t("Bắt đầu bằng")).tag(FolderLiveGroup.MatchOperator.beginsWith)
                    Text(L10n.t("Kết thúc bằng")).tag(FolderLiveGroup.MatchOperator.endsWith)
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 130)

                TextField(L10n.t("Giá trị"), text: Binding(
                    get: { filters[index].value },
                    set: { newVal in
                        filters[index].value = newVal
                        updatePreview(entries: sourceEntries)
                    }
                ))
                .textFieldStyle(.roundedBorder)
            }

            Button {
                filters.remove(at: index)
                updatePreview(entries: sourceEntries)
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .disabled(filters.count <= 1)
        }
    }

    private var sortingSection: some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.tight) {
            Text(L10n.t("Sắp xếp"))
                .font(XFinderTokens.Font.caption)
                .foregroundColor(.secondary)
            Picker("", selection: $sort) {
                Text(L10n.t("Tên (A đến Z)")).tag(FolderLiveGroup.Sort.nameAscending)
                Text(L10n.t("Tên (Z đến A)")).tag(FolderLiveGroup.Sort.nameDescending)
                Text(L10n.t("Mới nhất")).tag(FolderLiveGroup.Sort.modifiedNewest)
                Text(L10n.t("Cũ nhất")).tag(FolderLiveGroup.Sort.modifiedOldest)
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
    }

    private var rightPreview: some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.tight) {
            HStack {
                Text(L10n.t("Xem trước"))
                    .font(XFinderTokens.Font.sectionTitle)
                Spacer()
                Text("\(previewEntries.count)\(L10n.t(" mục"))")
                    .font(XFinderTokens.Font.caption)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: XFinderTokens.Space.tight) {
                Text(name.isEmpty ? L10n.t("Live Group") : name)
                    .font(XFinderTokens.Font.caption)
                    .bold()
                    .lineLimit(1)
                Circle()
                    .fill(Color.blue)
                    .frame(width: 6, height: 6)
                Spacer()
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if previewLoading {
                        Text(L10n.t("Đang tải…"))
                            .font(XFinderTokens.Font.caption)
                            .foregroundColor(.secondary)
                            .padding()
                    } else if let sourceErrorKey {
                        Text(L10n.t(sourceErrorKey))
                            .font(XFinderTokens.Font.caption)
                            .foregroundColor(.secondary)
                            .padding()
                    } else if previewEntries.isEmpty {
                        Text(L10n.t("Không có mục nào khớp bộ lọc."))
                            .font(XFinderTokens.Font.caption)
                            .foregroundColor(.secondary)
                            .padding()
                    } else {
                        ForEach(previewEntries) { entry in
                            HStack(spacing: XFinderTokens.Space.tight) {
                                Image(nsImage: FileIconCache.shared.icon(forPath: entry.path))
                                    .resizable()
                                    .interpolation(.high)
                                    .frame(width: 16, height: 16)
                                Text(entry.name)
                                    .font(XFinderTokens.Font.row)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            .frame(height: 22)
                            .padding(.horizontal, 4)
                        }
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: XFinderTokens.Radius.badge).fill(XFinderTokens.Fill.surface))
            .overlay(RoundedRectangle(cornerRadius: XFinderTokens.Radius.badge).stroke(XFinderTokens.Fill.hairline))
        }
    }

    private var footerBar: some View {
        HStack {
            if filters.isEmpty || !filters.allSatisfy(\.isValid) {
                Text(L10n.t("Thêm ít nhất một bộ lọc để lưu Live Group này."))
                    .font(XFinderTokens.Font.caption)
                    .foregroundColor(.secondary)
            } else if let sourceErrorKey {
                Text(L10n.t(sourceErrorKey))
                    .font(XFinderTokens.Font.caption)
                    .foregroundColor(.red)
            } else if !isSourcePathValid && !previewLoading {
                Text(L10n.t("Thư mục nguồn không hợp lệ."))
                    .font(XFinderTokens.Font.caption)
                    .foregroundColor(.red)
            }
            if saveFailed {
                Text(L10n.t("Không lưu được nhóm. Space có thể đã bị xoá."))
                    .font(XFinderTokens.Font.caption).foregroundColor(.red)
            }
            Spacer()
            Button(L10n.t("Huỷ")) {
                onClose()
            }
            .keyboardShortcut(.cancelAction)

            Button(L10n.t("Lưu")) {
                saveGroup()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!canSave)
        }
    }

    private func addFilter() {
        filters.append(FolderLiveGroup.Filter(field: .name, operation: .contains, value: ""))
        updatePreview(entries: sourceEntries)
    }

    private func clearFilters() {
        filters = [FolderLiveGroup.Filter(field: .name, operation: .contains, value: "")]
        updatePreview(entries: sourceEntries)
    }

    private func chooseSourceFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = L10n.t("Chọn")
        panel.begin { response in
            guard response == .OK, let path = panel.url?.path else { return }
            Task { @MainActor in sourcePath = path }
        }
    }

    private func subscribeToSource() {
        subscription?.cancel()
        subscription = nil
        projectionID += 1
        let token = UUID()
        subscriptionID = token
        validatedSourcePath = nil
        sourceErrorKey = nil
        let path = expandedSourcePath
        guard path.hasPrefix("/"), !path.contains("\0") else {
            sourceErrorKey = "Thư mục nguồn không hợp lệ."
            sourceEntries = []
            previewEntries = []
            previewLoading = false
            return
        }

        previewLoading = true
        subscription = DirectoryLoadCoordinator.shared.subscribe(
            path: path,
            onListing: { result in
                guard self.subscriptionID == token else { return }
                switch result {
                case .success(let delivery):
                    self.sourceErrorKey = nil
                    self.validatedSourcePath = delivery.isFinal ? path : nil
                    self.sourceEntries = delivery.entries
                    self.updatePreview(entries: delivery.entries)
                case .failure(let error):
                    self.projectionID += 1
                    self.validatedSourcePath = nil
                    self.sourceErrorKey = error.messageKey
                    self.sourceEntries = []
                    self.previewEntries = []
                    self.previewLoading = false
                }
            },
            onGone: {
                guard self.subscriptionID == token else { return }
                self.projectionID += 1
                self.validatedSourcePath = nil
                self.sourceErrorKey = "Thư mục không còn tồn tại"
                self.sourceEntries = []
                self.previewEntries = []
                self.previewLoading = false
            }
        )
    }

    private func updatePreview(entries: [DirectoryEntry]) {
        previewLoading = true
        projectionID += 1
        let currentID = projectionID
        let currentExpanded = expandedSourcePath
        let currentName = name
        let currentFilters = filters
        let currentSort = sort

        Task.detached(priority: .userInitiated) {
            let tempGroup = FolderLiveGroup(name: currentName, sourcePath: currentExpanded, filters: currentFilters, sort: currentSort)
            let candidates = entries.map {
                FolderLiveGroup.Candidate(path: $0.path, name: $0.name, isDirectory: $0.isFolderLike, modifiedDate: $0.modified)
            }
            let matched = tempGroup.matching(candidates)
            let matchedPaths = Set(matched.map(\.path))
            let order = Dictionary(uniqueKeysWithValues: matched.enumerated().map { ($1.path, $0) })
            let filtered = entries.filter { matchedPaths.contains($0.path) }
                .sorted { (order[$0.path] ?? 0) < (order[$1.path] ?? 0) }

            await MainActor.run {
                guard self.projectionID == currentID else { return }
                self.previewEntries = filtered
                self.previewLoading = false
            }
        }
    }

    private func saveGroup() {
        guard let valid = candidateGroup else { return }
        if onSave(valid) {
            onClose()
        } else {
            saveFailed = true
        }
    }
}
