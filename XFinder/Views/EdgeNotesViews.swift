import SwiftUI
import AppKit

/// Content of the screen-edge notes panel. Renders whichever of the three
/// states the controller is in: docked tabs, one peeking card, or the editor.
struct EdgeNotesRootView: View {
    @State private var controller = EdgeNotesController.shared
    @State private var store = NoteStore.shared

    private var notes: [QuickNote] { controller.visibleNotes }
    private var onLeft: Bool { controller.side == "Left" }

    var body: some View {
        ZStack(alignment: onLeft ? .topLeading : .topTrailing) {
            Color.clear
            if let openID = controller.openNoteID,
               let note = notes.first(where: { $0.id == openID }) {
                NoteEditorCard(note: note)
                    .transition(.opacity)
            } else {
                tabStack
            }
        }
        // Spring rather than easeOut — it settles instead of stopping dead,
        // which is what makes the slide read as "uyển chuyển".
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: controller.peekedNoteID)
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: controller.openNoteID)
    }

    /// Vertical stack of colour tabs, with the peeked note's card floating
    /// beside the strip.
    ///
    /// The card is an **overlay**, not a row in the stack. It is 118pt tall in
    /// a 28pt slot, so laying it out inline pushed it over the ~3 pills below
    /// and those notes became unreachable — the user had to leave the strip
    /// entirely and come back to read a different note. As an overlay the pill
    /// column keeps its exact geometry (which the controller's hit-testing
    /// depends on) and every note stays hoverable, so the pointer can slide
    /// straight down the strip from one preview to the next.
    ///
    /// Deliberately NO "+" button here. It sat directly under the last tab, so
    /// the peek card covered it and hovering it opened a preview instead of
    /// creating a note. New notes come from the menubar ("Ghi chú mới"); the
    /// edge strip only *shows* what exists.
    private var tabStack: some View {
        VStack(alignment: onLeft ? .leading : .trailing, spacing: controller.tabGap) {
            ForEach(Array(notes.enumerated()), id: \.element.id) { index, note in
                NoteTab(note: note,
                        isPeeking: controller.peekedNoteID == note.id,
                        onLeft: onLeft)
                    .onTapGesture { controller.open(note.id) }
                    .overlay(alignment: onLeft ? .topLeading : .topTrailing) {
                        if controller.peekedNoteID == note.id {
                            NotePreviewCard(note: note, onLeft: onLeft)
                                // Offset past the pill so the card sits beside
                                // the strip, never on top of it.
                                .offset(x: onLeft ? controller.tabWidth + 6
                                                  : -(controller.tabWidth + 6))
                                .onTapGesture { controller.open(note.id) }
                                .transition(.opacity.combined(with: .scale(scale: 0.96,
                                                                           anchor: onLeft ? .leading : .trailing)))
                        }
                    }
                    // The peeked row must paint above its neighbours, or the
                    // next pill in the stack draws over the card.
                    .zIndex(controller.peekedNoteID == note.id ? 1 : 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: onLeft ? .leading : .trailing)
    }
}

/// One docked tab. Collapsed it is a slim coloured strip with the title
/// One docked colour pill — always exactly `tabWidth × tabHeight`.
///
/// Its size must stay fixed regardless of peek state: `EdgeNotesController`
/// maps pointer Y to a row index using these constants, so a pill that grew
/// when hovered would desynchronise the hit-testing from what is drawn.
private struct NoteTab: View {
    let note: QuickNote
    let isPeeking: Bool
    let onLeft: Bool

    private var tint: Color { note.color.color }

    var body: some View {
        RoundedRectangle(cornerRadius: 4.5, style: .continuous)
            .fill(tint)
            .frame(width: EdgeNotesController.shared.tabWidth,
                   height: EdgeNotesController.shared.tabHeight)
            .overlay(
                RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                    .strokeBorder(Color.black.opacity(isPeeking ? 0.28 : 0.10),
                                  lineWidth: isPeeking ? 1 : 0.5)
            )
            // Widen on hover WITHOUT changing the laid-out frame: scaleEffect
            // is a render-time transform, so the row's geometry — and the
            // controller's row maths — are untouched.
            .scaleEffect(x: isPeeking ? 1.35 : 1, y: 1,
                         anchor: onLeft ? .leading : .trailing)
            .shadow(color: .black.opacity(isPeeking ? 0.22 : 0.10),
                    radius: isPeeking ? 5 : 3, x: 0, y: 1)
            .help(note.displayTitle)
            .contentShape(Rectangle())
    }
}

/// The note body shown while peeking, floated beside the strip as an overlay.
private struct NotePreviewCard: View {
    let note: QuickNote
    let onLeft: Bool

    private var tint: Color { note.color.color }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(note.displayTitle)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.black.opacity(0.85))
                .lineLimit(1)
            Divider().opacity(0.35)
            Text(note.content.isEmpty ? L10n.t("Ghi chú trống") : note.content)
                .font(.system(size: 10))
                .foregroundColor(.black.opacity(0.75))
                .lineLimit(6)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
        }
        .padding(9)
        .frame(width: 186, height: 118, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(tint.opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.22), radius: 10, x: 0, y: 3)
    }
}

/// The full editor shown after clicking a tab — mirrors the reference
/// screenshot: header with save state + tools, body, colour row, footer.
private struct NoteEditorCard: View {
    let note: QuickNote

    @State private var store = NoteStore.shared
    @State private var controller = EdgeNotesController.shared

    @State private var title: String = ""
    @State private var body_: String = ""
    @State private var color: CodableColor = CodableColor(color: .yellow)
    @State private var savedAt: Date?
    @State private var fontScale: CGFloat = 1
    @FocusState private var bodyFocused: Bool

    private var tint: Color { color.color }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.3)
            editor
            Divider().opacity(0.3)
            footer
        }
        .frame(width: 500, height: 400)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(tint.opacity(0.42))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.28), radius: 18, x: 0, y: 8)
        .padding(10)
        .onAppear(perform: load)
        // Autosave on every keystroke — a floating panel can be dismissed in
        // ways that never deliver a "closing" event, so an explicit Save
        // button would silently lose work.
        .onChange(of: title) { save() }
        .onChange(of: body_) { save() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            TextField(L10n.t("Tiêu đề"), text: $title)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.black.opacity(0.85))

            Text(savedAt == nil ? "" : L10n.t("Đã lưu"))
                .font(.system(size: 11))
                .foregroundColor(.black.opacity(0.45))

            Button { fontScale = max(0.85, fontScale - 0.1) } label: {
                Text("A").font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain).help(L10n.t("Chữ nhỏ hơn"))

            Button { fontScale = min(1.5, fontScale + 0.1) } label: {
                Text("A").font(.system(size: 15, weight: .medium))
            }
            .buttonStyle(.plain).help(L10n.t("Chữ lớn hơn"))

            Button { store.togglePin(note) } label: {
                Image(systemName: note.isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain).help(note.isPinned ? L10n.t("Bỏ ghim") : "Ghim")

            Button { insertChecklistItem() } label: {
                Image(systemName: "checklist").font(.system(size: 12))
            }
            .buttonStyle(.plain).help(L10n.t("Thêm ô đánh dấu (⌘T)"))
        }
        .foregroundColor(.black.opacity(0.7))
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private var editor: some View {
        TextEditor(text: $body_)
            .focused($bodyFocused)
            .font(.system(size: 13 * fontScale))
            .foregroundColor(.black.opacity(0.85))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.clear)
            .onAppear {
                // macOS 12 has no scrollContentBackground, so reach the NSTextView.
                DispatchQueue.main.async { makeTextViewTransparent() }
            }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            ForEach(NoteColor.presets) { preset in
                Circle()
                    .fill(preset.color)
                    .frame(width: 15, height: 15)
                    .overlay(
                        Circle().strokeBorder(Color.black.opacity(0.55),
                                              lineWidth: preset.color == tint ? 2 : 0)
                    )
                    .onTapGesture {
                        color = CodableColor(color: preset.color)
                        save()
                    }
            }

            Spacer()

            Button(L10n.t("Lưu trữ")) {
                store.toggleArchive(note)
                controller.closeEditor()
            }
            .buttonStyle(.plain)
            .font(.system(size: 12))

            Button {
                store.delete(note)
                controller.closeEditor()
            } label: {
                Image(systemName: "trash").font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .help(L10n.t("Xóa ghi chú"))

            Button(L10n.t("Đóng")) { controller.closeEditor() }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundColor(.black.opacity(0.7))
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    // MARK: Actions

    private func load() {
        title = note.title ?? ""
        body_ = note.content
        color = note.color
        bodyFocused = true
    }

    private func save() {
        store.update(note,
                     title: title.isEmpty ? nil : title,
                     content: body_,
                     color: color)
        savedAt = Date()
    }

    private func insertChecklistItem() {
        if !body_.isEmpty, !body_.hasSuffix("\n") { body_ += "\n" }
        body_ += "☐ "
    }

    /// `TextEditor` draws an opaque background and macOS 12 has no
    /// `.scrollContentBackground`, so clear it through the underlying
    /// `NSTextView` — otherwise a white box covers the note's colour.
    private func makeTextViewTransparent() {
        func walk(_ view: NSView) {
            if let tv = view as? NSTextView {
                tv.drawsBackground = false
                tv.enclosingScrollView?.drawsBackground = false
            }
            view.subviews.forEach(walk)
        }
        for window in NSApp.windows where window is NSPanel {
            if let content = window.contentView { walk(content) }
        }
    }
}
