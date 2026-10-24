import SwiftUI
import UniformTypeIdentifiers
import os

/// XF-T28 cluster E — the Shelf strip at the bottom of the window (⌥⌘B), a drop target that adds paths and a row of
/// actions working on `model.shelf.targets(selection:)`.
struct ShelfBarView: View {
    private static let rowHeight: CGFloat = 52
    private static let iconSize: CGFloat = 28

    let model: BrowserWindowModel

    @State private var isTargeted = false
    @State private var shelfSelection: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(XFinderTokens.Fill.hairline).frame(height: 1)
            HStack(spacing: XFinderTokens.Space.inline) {
                itemsRow
                Divider()
                summary
                Divider()
                actions
            }
            .padding(.horizontal, XFinderTokens.Space.row)
            .frame(height: Self.rowHeight)
            .background(XFinderTokens.Fill.surface)
        }
        .overlay(isTargeted ? RoundedRectangle(cornerRadius: 0).strokeBorder(Color.accentColor, lineWidth: 2) : nil)
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers)
            return true
        }
    }

    private var itemsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: XFinderTokens.Space.tight) {
                if model.shelf.items.isEmpty {
                    Text(L10n.t("Kéo tệp vào đây để thêm vào Shelf"))
                        .font(XFinderTokens.Font.caption)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(model.shelf.items) { item in
                        shelfItemView(item)
                    }
                }
            }
        }
    }

    private func shelfItemView(_ item: ShelfItem) -> some View {
        VStack(spacing: 2) {
            Image(nsImage: FileIconCache.shared.icon(forPath: item.path))
                .resizable()
                .frame(width: Self.iconSize, height: Self.iconSize)
                .opacity(item.missing ? 0.4 : 1.0)
            Text((item.path as NSString).lastPathComponent)
                .font(XFinderTokens.Font.caption)
                .foregroundColor(item.missing ? .secondary : .primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 64)
        }
        .padding(2)
        .background(
            shelfSelection.contains(item.path)
                ? RoundedRectangle(cornerRadius: XFinderTokens.Radius.badge, style: .continuous).fill(XFinderTokens.Fill.focus)
                : nil
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if shelfSelection.contains(item.path) {
                shelfSelection.remove(item.path)
            } else {
                shelfSelection.insert(item.path)
            }
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(model.shelf.count)\(L10n.t(" mục"))")
                .font(XFinderTokens.Font.caption)
            Text(ByteCountFormatter.string(fromByteCount: model.shelf.totalBytes, countStyle: .file))
                .font(XFinderTokens.Font.caption)
                .foregroundColor(.secondary)
        }
    }

    private var actions: some View {
        HStack(spacing: XFinderTokens.Space.tight) {
            Button(L10n.t("Chép vào ngăn đang chọn")) {
                let targets = model.shelf.targets(selection: shelfSelection)
                guard !targets.isEmpty else { return }
                model.drop(targets, into: model.active.path, copy: true)
            }
            .disabled(model.shelf.items.isEmpty)

            Button(L10n.t("Di chuyển vào ngăn đang chọn")) {
                let targets = model.shelf.targets(selection: shelfSelection)
                guard !targets.isEmpty else { return }
                model.drop(targets, into: model.active.path, copy: false)
            }
            .disabled(model.shelf.items.isEmpty)

            Button(L10n.t("Đổi tên hàng loạt")) {
                let targets = model.shelf.targets(selection: shelfSelection)
                guard !targets.isEmpty else { return }
                model.batchRenameSources = targets
            }
            .disabled(model.shelf.items.isEmpty)

            Button(L10n.t("Bỏ")) {
                model.shelf.remove(shelfSelection)
                shelfSelection.removeAll()
            }
            .disabled(shelfSelection.isEmpty)

            Button(L10n.t("Xoá hết")) {
                model.shelf.clear()
                shelfSelection.removeAll()
            }
            .foregroundColor(.red)
            .disabled(model.shelf.items.isEmpty)
        }
        .font(XFinderTokens.Font.caption)
        .buttonStyle(.borderless)
    }

    private func handleDrop(_ providers: [NSItemProvider]) {
        // `loadItem`'s completion can run on an arbitrary queue per provider, so results are collected into a lock-
        // protected box (one slot per provider, written at most once) instead of mutating a plain captured `var`
        // from concurrently-executing closures.
        let collector = DroppedPathCollector(count: providers.count)
        let group = DispatchGroup()
        for (index, provider) in providers.enumerated() where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                defer { group.leave() }
                guard let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                collector.set(url.path, at: index)
            }
        }
        group.notify(queue: .main) {
            let paths = collector.collected()
            guard !paths.isEmpty else { return }
            var sizes: [String: Int64] = [:]
            for path in paths {
                if let size = try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int64 {
                    sizes[path] = size
                }
            }
            model.shelf.add(paths, sizes: sizes)
        }
    }
}

/// Thread-safe fixed-slot collector for `ShelfBarView.handleDrop`: each `NSItemProvider`'s completion handler may run
/// on a different queue, so writes go through `OSAllocatedUnfairLock` (genuinely `Sendable` for a `Sendable` state,
/// unlike `@unchecked Sendable` over a plain array) rather than appending to a shared `var` from concurrent closures.
private final class DroppedPathCollector: Sendable {
    private let slots: OSAllocatedUnfairLock<[String?]>

    init(count: Int) {
        slots = OSAllocatedUnfairLock(initialState: Array(repeating: nil, count: count))
    }

    func set(_ path: String, at index: Int) {
        slots.withLock { slots in
            guard index >= 0, index < slots.count else { return }
            slots[index] = path
        }
    }

    func collected() -> [String] {
        slots.withLock { $0.compactMap { $0 } }
    }
}
