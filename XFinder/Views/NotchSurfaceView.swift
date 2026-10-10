import SwiftUI
import AppKit
import QuickLookThumbnailing

/// What the Notch surface shows. Mutated only by `NotchSurfaceController.render()`.
@MainActor
@Observable
final class NotchSurfaceModel {
    var state: NotchSurfaceMachine.State = .collapsed
    var anchor: NotchSurfaceMachine.Anchor = .notch
    var itemCount = 0
    /// Size of the physical notch (height 0 on a screen without one).
    var notchSize = CGSize(width: 185, height: 32)
    /// The hub action that is running or last finished (B2d).
    var task: NotchTask?
    /// A one-line store key shown under the action row (e.g. AirDrop unavailable).
    var notice: String?
    /// The live activity on screen (B4).
    var activity: LiveActivity.Item?
    /// Remaining time of a running countdown ("12:34"), shown in the collapsed badge (B4b).
    var timerText: String?
    /// The clipboard page's own state (B5).
    let clipboard = NotchClipboardModel()
}

/// Root of the Notch surface window. The window is sized by `NotchSurfaceLayout`; this view draws
/// a black shape of the SAME layout size for the current state and animates between states with
/// `Motion.surface`, so the surface appears to grow out of the notch. Everything is white-on-black
/// on purpose — it must read as part of the notch, not as a floating card.
struct NotchSurfaceView: View {
    var model: NotchSurfaceModel
    @State private var store = DropTrayStore.shared
    @State private var isTargeted = false

    private var size: CGSize {
        let notch = CGRect(origin: .zero, size: model.notchSize)
        return NotchSurfaceLayout.size(for: model.state, anchor: model.anchor,
                                       itemCount: model.itemCount, notch: notch,
                                       timerActive: model.timerText != nil) ?? .zero
    }

    /// At the notch the top edge is flush with the screen (the notch has no top edge); a tray opened
    /// at the pointer is a free-standing card, rounded on all four corners.
    private var atNotch: Bool { model.anchor == .notch }
    private var shape: NotchShape {
        NotchShape(bottomRadius: bottomRadius, topRadius: atNotch ? 0 : bottomRadius)
    }

    private var bottomRadius: CGFloat {
        switch model.state {
        case .collapsed: return 9
        case .peek, .activity: return 14
        case .expanded: return XFinderTokens.Radius.surface
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            shape.fill(Color.black)
            shape.strokeBorder(isTargeted ? Color.accentColor : Color.white.opacity(0.12), lineWidth: isTargeted ? 2 : 1)
            content
                .padding(.top, atNotch ? model.notchSize.height : 0)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(shape)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(XFinderTokens.Motion.surface, value: model.state)
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            ClipboardSounds.playCopy()
            // The URLs load asynchronously; report the drop only once they are in the store, so the
            // machine sees the real count (a shaken tray with files must not think it is empty).
            // Dropping keeps the surface open: it is the START of the task.
            store.add(providers: providers) { NotchSurfaceController.shared.filesDropped() }
            return true
        }
    }

    @ViewBuilder private var content: some View {
        switch model.state {
        case .collapsed: badge
        case .peek: peek
        case .activity: activityStrip
        case .expanded(let page): hubShell(page)
        }
    }

    /// Count hanging under the notch while files are held and the surface is collapsed.
    private var badge: some View {
        HStack(spacing: XFinderTokens.Space.tight) {
            if model.itemCount > 0 {
                Image(systemName: "tray.fill").font(XFinderTokens.Font.caption)
                Text("\(model.itemCount)").font(XFinderTokens.Font.caption).monospacedDigit()
            }
            if let t = model.timerText {
                Image(systemName: "timer").font(XFinderTokens.Font.caption)
                Text(t).font(XFinderTokens.Font.caption).monospacedDigit()
            }
        }
        .foregroundColor(.white)
        .frame(maxWidth: .infinity)
        .frame(height: NotchSurfaceLayout.Metrics.standard.badgeLip)
        .contentShape(Rectangle())
        .onTapGesture { if model.itemCount > 0 { NotchSurfaceController.shared.reveal() } }
        .help(model.itemCount > 0 ? L10n.t("Bấm để mở") : "")
    }

    /// Peek only exists while files are held (the machine never peeks an empty tray). The left icon
    /// is a drag handle for EVERY held file — so files stay one drag away even collapsed — and the
    /// text opens the hub. They are separate regions because one press cannot be both a drag and a click.
    private var peek: some View {
        HStack(spacing: XFinderTokens.Space.tight + 2) {
            Image(systemName: "tray.full.fill")
                .font(XFinderTokens.Font.row)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: XFinderTokens.Radius.badge).fill(Color.white.opacity(0.12)))
                .overlay(MultiFileDragSource(paths: store.items.map(\.path)))
                .help(L10n.t("Kéo cả chồng ra để dùng một lần."))
            HStack(spacing: XFinderTokens.Space.tight) {
                Text("\(model.itemCount)\(L10n.t(" tệp đang giữ"))").font(XFinderTokens.Font.row)
                Text(L10n.t("Bấm để mở")).font(XFinderTokens.Font.caption).opacity(0.65)
            }
            .contentShape(Rectangle())
            .onTapGesture { NotchSurfaceController.shared.reveal() }
        }
        .foregroundColor(.white)
        .frame(maxWidth: .infinity)
        .frame(height: NotchSurfaceLayout.Metrics.standard.peekDrop)
    }

    /// A live activity: icon, headline, detail — one line under the notch, white on black.
    private var activityStrip: some View {
        HStack(spacing: XFinderTokens.Space.tight + 2) {
            if let a = model.activity {
                Image(systemName: a.symbol).font(XFinderTokens.Font.row).foregroundColor(tint(a.tint))
                Text(L10n.t(a.titleKey)).font(XFinderTokens.Font.row).lineLimit(1)
                if let d = a.detail { Text(d).font(XFinderTokens.Font.caption).opacity(0.7).lineLimit(1).truncationMode(.middle) }
                if let level = a.level {
                    ProgressView(value: level).progressViewStyle(.linear).tint(.white).frame(width: 90)
                }
            }
        }
        .foregroundColor(.white)
        .frame(maxWidth: .infinity)
        .frame(height: NotchSurfaceLayout.Metrics.standard.activityDrop)
        .padding(.horizontal, XFinderTokens.Space.inline)
    }

    private func tint(_ t: LiveActivity.Tint) -> Color {
        switch t {
        case .neutral: return .white
        case .good: return .green
        case .warning: return .orange
        case .bad: return .red
        }
    }

    /// The hub: one header with two page tabs (files / clipboard) and the close button, then the page.
    private func hubShell(_ page: NotchSurfaceMachine.Page) -> some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
            HStack(spacing: XFinderTokens.Space.tight) {
                HStack(spacing: XFinderTokens.Space.tight) {
                    pageTab(.files, icon: "tray.and.arrow.down.fill", title: L10n.t("Khay"),
                            badge: store.items.isEmpty ? nil : "\(store.items.count)", current: page)
                    pageTab(.clipboard, icon: "doc.on.clipboard.fill", title: "Clipboard", badge: nil, current: page)
                    Spacer()
                }
                // A tray opened at the pointer often lands on the very window the files are going to;
                // its title strip moves it out of the way (the old tray could, the B1 rewrite had lost
                // it). Only the strip — never the deck — so a file drag out still starts normally.
                .overlay { if !atNotch { WindowDragHandle().help(L10n.t("Kéo để dời khay")) } }
                Button { NotchSurfaceController.shared.dismiss() } label: {
                    Image(systemName: "xmark.circle.fill").opacity(0.65)
                }
                .buttonStyle(.plain)
                .help(L10n.t("Đóng"))
            }

            switch page {
            case .files: filesPage
            case .clipboard: NotchClipboardView(model: model.clipboard)
            }
        }
        .foregroundColor(.white)
        .padding(XFinderTokens.Space.inline)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func pageTab(_ page: NotchSurfaceMachine.Page, icon: String, title: String, badge: String?,
                         current: NotchSurfaceMachine.Page) -> some View {
        Button { NotchSurfaceController.shared.switchPage(page) } label: {
            HStack(spacing: 4) {
                Image(systemName: icon).font(XFinderTokens.Font.caption)
                Text(title).font(XFinderTokens.Font.caption)
                if let badge { Text(badge).font(XFinderTokens.Font.caption).opacity(0.7).monospacedDigit() }
            }
            .padding(.horizontal, XFinderTokens.Space.tight + 2).padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: XFinderTokens.Radius.badge)
                .fill(current == page ? Color.white.opacity(0.18) : Color.clear))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var filesPage: some View {
        if store.items.isEmpty {
            VStack(spacing: XFinderTokens.Space.tight) {
                Image(systemName: "arrow.down.doc").font(XFinderTokens.Font.pageIcon).opacity(0.65)
                Text(L10n.t("Thả file vào đây để giữ tạm"))
                    .font(XFinderTokens.Font.caption).opacity(0.65)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            stackedDeck
            actionArea
        }
    }

    /// Overlapping deck + a count; dragging the deck hands over EVERY held file at once, which is
    /// the whole point of staging them together.
    private var stackedDeck: some View {
        HStack(spacing: XFinderTokens.Space.inline + 2) {
            ZStack {
                ForEach(Array(store.items.prefix(4).enumerated().reversed()), id: \.element.id) { index, item in
                    Image(nsImage: NSWorkspace.shared.icon(forFile: item.path))
                        .resizable()
                        .frame(width: 46, height: 46)
                        .background(RoundedRectangle(cornerRadius: XFinderTokens.Radius.control).fill(Color.white.opacity(0.08)))
                        .rotationEffect(.degrees(Double(index) * -4))
                        .offset(x: CGFloat(index) * 7, y: CGFloat(index) * -3)
                        .shadow(color: .black.opacity(0.4), radius: 3, x: 0, y: 1)
                }
            }
            .frame(width: 78, height: 62)
            // SwiftUI's `.onDrag` vends ONE provider and `.itemProviders` does not exist on
            // macOS 14 — the whole stack needs an AppKit drag session.
            .overlay(MultiFileDragSource(paths: store.items.map(\.path)))

            VStack(alignment: .leading, spacing: XFinderTokens.Space.tight) {
                Text("\(store.items.count)\(L10n.t(" tệp đang giữ"))")
                    .font(XFinderTokens.Font.row)
                Text(L10n.t("Kéo cả chồng ra để dùng một lần."))
                    .font(XFinderTokens.Font.caption).opacity(0.65)
                HStack(spacing: XFinderTokens.Space.tight + 2) {
                    Button(L10n.t("Xem chi tiết")) { NotchSurfaceController.shared.toggleDetail() }
                        .buttonStyle(.bordered).controlSize(.mini)
                    Button(L10n.t("Xóa hết")) { store.removePaths(store.items.map(\.path)) }
                        .buttonStyle(.plain)
                        .font(XFinderTokens.Font.caption)
                        .opacity(0.65)
                }
            }
            Spacer()
        }
        .contentShape(Rectangle())
    }

    // MARK: Action row (B2d)

    private var actions: [NotchActions.Action] {
        NotchActions.available(for: store.items.filter { !$0.isMissing }.map { URL(fileURLWithPath: $0.path) },
                               encodable: ImageRunner.encodableTypes)
    }

    private func title(_ a: NotchActions.Action) -> String {
        switch a {
        case .zip: return L10n.t("Nén ZIP")
        case .mergePDFs: return L10n.t("Gộp PDF")
        case .convert(let t): return "\(L10n.t("Sang "))\(t.label)"
        case .removeBackground: return L10n.t("Tách nền")
        case .airDrop: return "AirDrop"
        }
    }

    private func symbol(_ a: NotchActions.Action) -> String {
        switch a {
        case .zip: return "archivebox"
        case .mergePDFs: return "doc.on.doc"
        case .convert: return "photo"
        case .removeBackground: return "person.crop.rectangle"
        case .airDrop: return "airplayaudio"
        }
    }

    @ViewBuilder private var actionArea: some View {
        if let t = model.task, t.isRunning {
            HStack(spacing: XFinderTokens.Space.tight + 2) {
                ProgressView(value: t.fraction).progressViewStyle(.linear).tint(.white)
                Text("\(t.done + t.failed)/\(t.total)").font(XFinderTokens.Font.caption).monospacedDigit()
                Button(L10n.t("Hủy")) { NotchSurfaceController.shared.cancelTask() }
                    .buttonStyle(.bordered).controlSize(.mini)
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: XFinderTokens.Space.tight) {
                    ForEach(actions, id: \.self) { a in
                        Button { NotchSurfaceController.shared.run(a) } label: {
                            Label(title(a), systemImage: symbol(a)).labelStyle(.iconOnly)
                        }
                        .buttonStyle(.bordered).controlSize(.small)
                        .help(title(a))
                    }
                }
                if let t = model.task {
                    resultLine(t)
                } else if let n = model.notice {
                    Text(L10n.t(n)).font(XFinderTokens.Font.caption).opacity(0.65)
                }
            }
        }
    }

    @ViewBuilder private func resultLine(_ t: NotchTask) -> some View {
        HStack(spacing: XFinderTokens.Space.tight) {
            if t.phase == .cancelled {
                Text(L10n.t("Đã hủy.")).font(XFinderTokens.Font.caption).opacity(0.65)
            } else {
                Text("\(L10n.t("Xong: "))\(t.outputs.count)/\(t.total)").font(XFinderTokens.Font.caption)
                if let f = t.firstFailure {
                    Text("\(L10n.t(f.key))\(f.detail)").font(XFinderTokens.Font.caption).foregroundColor(.orange).lineLimit(1)
                }
            }
            if !t.outputs.isEmpty {
                Button(L10n.t("Hiện trong Finder")) { NotchSurfaceController.shared.revealResults() }
                    .buttonStyle(.plain).font(XFinderTokens.Font.caption).underline()
            }
        }
    }
}

/// Flush with the top of the screen at the notch (`topRadius` 0); fully rounded at the pointer.
struct NotchShape: InsettableShape {
    var bottomRadius: CGFloat
    var topRadius: CGFloat = 0
    var inset: CGFloat = 0

    var animatableData: CGFloat {
        get { bottomRadius }
        set { bottomRadius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        UnevenRoundedRectangle(topLeadingRadius: topRadius, bottomLeadingRadius: bottomRadius,
                               bottomTrailingRadius: bottomRadius, topTrailingRadius: topRadius,
                               style: .continuous)
            .path(in: rect.insetBy(dx: inset, dy: inset))
    }

    func inset(by amount: CGFloat) -> NotchShape {
        var s = self
        s.inset += amount
        return s
    }
}

/// Moves its window when pressed and dragged. A separate view so the window drag is confined to the
/// strip it covers: blanket-forwarding `mouseDown` swallowed every file drag once (CLAUDE.md Part 3c).
struct WindowDragHandle: NSViewRepresentable {
    final class HandleView: NSView {
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }
    func makeNSView(context: Context) -> HandleView { HandleView() }
    func updateNSView(_ nsView: HandleView, context: Context) {}
}

/// The surface's hosting view. `NSHostingView.acceptsFirstMouse` is `false` (measured by the B1
/// review), and the panel is ordered front without becoming key, so every control needed TWO clicks
/// while another app was frontmost. The deleted tray overrode this on its container; so does this.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// MARK: - Shared tray pieces (also used by the detail grid window)

/// Drags every staged file at once via `beginDraggingSession(with:)`.
struct MultiFileDragSource: NSViewRepresentable {
    let paths: [String]

    func makeNSView(context: Context) -> DragSourceView {
        let v = DragSourceView()
        v.paths = paths
        return v
    }

    func updateNSView(_ nsView: DragSourceView, context: Context) {
        nsView.paths = paths
    }

    final class DragSourceView: NSView {
        var paths: [String] = []

        override func mouseDown(with event: NSEvent) {
            guard !paths.isEmpty else { return super.mouseDown(with: event) }
            let items: [NSDraggingItem] = paths.compactMap { path in
                let url = URL(fileURLWithPath: path) as NSURL
                let item = NSDraggingItem(pasteboardWriter: url)
                let icon = NSWorkspace.shared.icon(forFile: path)
                // Every item needs a frame + image or the session shows nothing.
                item.setDraggingFrame(NSRect(x: 0, y: 0, width: 48, height: 48), contents: icon)
                return item
            }
            guard !items.isEmpty else { return }
            beginDraggingSession(with: items, event: event, source: self)
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }
}

extension MultiFileDragSource.DragSourceView: NSDraggingSource {
    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        // `.copy` outside the app: the tray keeps its files — "Kéo ra sẽ sao chép file và giữ các mục trong khay".
        [.copy]
    }
}

/// One staged file with a real QuickLook thumbnail, so "Screenshot 1, Screenshot 2" stay tellable apart.
struct TrayFileTile: View {
    let item: DropTrayStore.Item
    let url: URL
    let onRemove: () -> Void

    @State private var thumb: NSImage?

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: XFinderTokens.Radius.badge)
                    .fill(Color.primary.opacity(0.05))
                if let thumb {
                    Image(nsImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: XFinderTokens.Radius.badge))
                } else {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: item.path))
                        .resizable().frame(width: 30, height: 30)
                }
            }
            .frame(width: 62, height: 62)

            Text(item.name)
                .font(XFinderTokens.Font.caption)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 66)
        }
        .padding(5)
        .background(RoundedRectangle(cornerRadius: XFinderTokens.Radius.control).fill(XFinderTokens.Fill.inset))
        .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
        .contextMenu {
            Button(L10n.t("Hiện trong Finder")) {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
            Button(L10n.t("Mở")) { NSWorkspace.shared.open(url) }
            Divider()
            Button(L10n.t("Bỏ khỏi khay"), action: onRemove)
        }
        .help(item.path)
        .task { thumb = await FileThumbnailer.thumbnail(for: url) }
    }
}

/// QuickLook thumbnails, off the main thread; falls back to the type icon when a format has no previewer.
enum FileThumbnailer {
    static func thumbnail(for url: URL) async -> NSImage? {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: 120, height: 120),
            scale: scale,
            representationTypes: .all)
        return await withCheckedContinuation { continuation in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { rep, _ in
                continuation.resume(returning: rep?.nsImage)
            }
        }
    }
}

/// Detail window of the tray — a grid of every file (each draggable on its own). Capped so a
/// thousand-file tray does not draw a thousand tiles at once.
struct DropTrayDetailGrid: View {
    @State private var store = DropTrayStore.shared
    private let cap = 400

    private let columns = [GridItem(.adaptive(minimum: 110, maximum: 160), spacing: 10)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(store.items.prefix(cap)) { item in
                    TrayFileTile(item: item, url: URL(fileURLWithPath: item.path)) {
                        store.remove(item)
                    }
                }
            }
            .padding(XFinderTokens.Space.inline)
        }
        .frame(minWidth: 480, minHeight: 360)
        .overlay(alignment: .bottom) {
            if store.items.count > cap {
                Text("\(L10n.t("Hiện "))\(cap)/\(store.items.count)\(L10n.t(" mục — kéo cả chồng ở khay để thao tác cả lô."))")
                    .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                    .padding(.vertical, XFinderTokens.Space.tight)
                    .frame(maxWidth: .infinity)
                    .background(XFinderTokens.Fill.surface.opacity(0.9))
            }
        }
    }
}
