import SwiftUI
import AppKit

/// Floating command palette panel
struct CommandPalettePanel: View {
    @StateObject private var engine = CommandPaletteEngine.shared
    @State private var searchText = ""
    @State private var selectedIndex = 0
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 16))

                TextField("Tìm ứng dụng, file, hoặc tính toán...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .focused($isSearchFocused)
                    .onChange(of: searchText) { _, newValue in
                        engine.search(query: newValue)
                        selectedIndex = 0
                    }

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                        engine.clear()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))

            Divider()

            // Results
            if engine.results.isEmpty && !searchText.isEmpty {
                emptyState
            } else if !engine.results.isEmpty {
                resultsList
            } else {
                placeholderState
            }
        }
        .frame(width: 600, height: 400)
        .background(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
        .onAppear {
            isSearchFocused = true
        }
    }

    private var resultsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(engine.results.enumerated()), id: \.offset) { index, result in
                        resultRow(result, index: index)
                            .id(index)
                    }
                }
            }
            .onChange(of: selectedIndex) { _, newIndex in
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(newIndex, anchor: .center)
                }
            }
        }
        .onKeyDown { event in
            handleKeyDown(event)
        }
    }

    private func resultRow(_ result: any CommandResult, index: Int) -> some View {
        HStack(spacing: 12) {
            if let icon = result.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 32, height: 32)
            } else {
                Image(systemName: iconName(for: result.resultType))
                    .font(.system(size: 20))
                    .foregroundColor(.secondary)
                    .frame(width: 32, height: 32)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(result.title)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)

                if let subtitle = result.subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Type badge
            typeBadge(for: result.resultType)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(selectedIndex == index ? Color.accentColor.opacity(0.15) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            selectedIndex = index
            executeSelected()
        }
    }

    private func typeBadge(for type: CommandResultType) -> some View {
        Text(badgeText(for: type))
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(4)
    }

    private func badgeText(for type: CommandResultType) -> String {
        switch type {
        case .app: return "APP"
        case .file: return "FILE"
        case .calculation: return "CALC"
        case .quicklink: return "LINK"
        case .raycastExtension: return "EXT"
        }
    }

    private func iconName(for type: CommandResultType) -> String {
        switch type {
        case .app: return "app.fill"
        case .file: return "doc.fill"
        case .calculation: return "equal.circle.fill"
        case .quicklink: return "link.circle.fill"
        case .raycastExtension: return "puzzlepiece.extension.fill"
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("Không tìm thấy kết quả")
                .font(.system(size: 14, weight: .medium))
            Text("Thử từ khóa khác")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var placeholderState: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 40))
                .foregroundColor(.accentColor)

            VStack(spacing: 8) {
                Text("Command Palette")
                    .font(.system(size: 18, weight: .semibold))
                Text("Tìm ứng dụng, file, tính toán, hoặc quicklink")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                shortcutHint(key: "↩", text: "Mở / Thực thi")
                shortcutHint(key: "↑↓", text: "Di chuyển")
                shortcutHint(key: "esc", text: "Đóng")
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func shortcutHint(key: String, text: String) -> some View {
        HStack(spacing: 8) {
            Text(key)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(4)
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        switch Int(event.keyCode) {
        case 125: // Down
            selectedIndex = min(selectedIndex + 1, engine.results.count - 1)
            return nil
        case 126: // Up
            selectedIndex = max(selectedIndex - 1, 0)
            return nil
        case 36: // Return
            executeSelected()
            return nil
        case 53: // Esc
            CommandPaletteController.shared.hide()
            return nil
        default:
            return event
        }
    }

    private func executeSelected() {
        guard selectedIndex < engine.results.count else { return }
        let result = engine.results[selectedIndex]
        result.execute()
        CommandPaletteController.shared.hide()
    }
}

// MARK: - VisualEffectView

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// MARK: - KeyDown Modifier

extension View {
    func onKeyDown(perform action: @escaping (NSEvent) -> NSEvent?) -> some View {
        background(KeyDownHandlerView(handler: action))
    }
}

struct KeyDownHandlerView: NSViewRepresentable {
    let handler: (NSEvent) -> NSEvent?

    func makeNSView(context: Context) -> KeyDownNSView {
        let view = KeyDownNSView()
        view.keyDownHandler = handler
        return view
    }

    func updateNSView(_ nsView: KeyDownNSView, context: Context) {
        nsView.keyDownHandler = handler
    }
}

class KeyDownNSView: NSView {
    var keyDownHandler: ((NSEvent) -> NSEvent?)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if let handler = keyDownHandler, handler(event) == nil {
            return
        }
        super.keyDown(with: event)
    }
}
