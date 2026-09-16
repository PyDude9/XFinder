import SwiftUI

/// Shared note editor sheet, used by the Ghi chú page. (The old SideNotesPanel
/// column and NoteCardView were removed once notes moved to the screen-edge
/// panel — the column repeated the same notes on every settings page.)

struct NoteEditorSheet: View {
    @Binding var isPresented: Bool
    let note: QuickNote?

    @State private var title = ""
    @State private var content = ""
    @State private var selectedColor: Color = .yellow
    @FocusState private var contentFocused: Bool

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text(note == nil ? "Ghi chú mới" : "Sửa ghi chú")
                    .font(.headline)

                Spacer()

                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Tiêu đề (không bắt buộc)")
                    .font(.caption)
                    .fontWeight(.semibold)

                TextField("Tiêu đề", text: $title)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Nội dung")
                    .font(.caption)
                    .fontWeight(.semibold)

                TextEditor(text: $content)
                    .font(NoteStore.noteFont(13))
                    .focused($contentFocused)
                    .border(Color.gray.opacity(0.3))
                    .cornerRadius(6)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Màu")
                    .font(.caption)
                    .fontWeight(.semibold)

                HStack {
                    ForEach(NoteColor.presets, id: \.id) { noteColor in
                        Circle()
                            .fill(noteColor.color)
                            .frame(width: 24, height: 24)
                            .overlay(
                                Circle()
                                    .stroke(selectedColor == noteColor.color ? Color.white : Color.clear, lineWidth: 2)
                            )
                            .onTapGesture {
                                selectedColor = noteColor.color
                            }
                    }
                    Spacer()
                }
            }

            HStack(spacing: 12) {
                Spacer()

                Button("Hủy") {
                    isPresented = false
                }

                Button("Lưu") {
                    if let existing = note {
                        NoteStore.shared.update(existing, title: title, content: content,
                                                color: CodableColor(color: selectedColor))
                    } else {
                        NoteStore.shared.create(title: title, content: content,
                                                color: CodableColor(color: selectedColor))
                    }
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
            }

            Spacer()
        }
        .padding()
        .frame(minWidth: 400, minHeight: 500)
        .onAppear {
            if let note = note {
                title = note.title ?? ""
                content = note.content
                selectedColor = note.color.color
            }
            // Mở thẳng vào ô nội dung để gõ ngay (kiểu quick-note).
            contentFocused = true
        }
    }
}
