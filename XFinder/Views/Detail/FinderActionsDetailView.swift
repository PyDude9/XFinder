import SwiftUI
import AppKit

/// Thao tác Finder — run XFinder's file tools on the files currently selected
/// in Finder, and reach the system panes that install them as Quick Actions.
///
/// The selection is read via a one-line AppleScript against Finder (needs
/// Automation for Finder the first time — the page says so and offers the
/// pane). Copy/Move/Trash/Compress then run on that selection through the same
/// engines the tool pages use, so behaviour is identical everywhere.
///
/// Honesty note: macOS has **no** public API to add items to Finder's own
/// context menu from a plain app — that requires a Finder Sync Extension
/// target. The page links to the Extensions pane instead of faking it.
struct FinderActionsDetailView: View {
    @State private var selection: [URL] = []
    @State private var status: String?
    @State private var busy = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PageHeader(icon: "contextualmenu.and.cursorarrow",
                           title: "Thao tác Finder",
                           subtitle: "Chạy thao tác của XFinder trên các tệp đang chọn trong Finder.")

                SectionHeader(icon: "cursorarrow.click.2",
                              title: "Tệp đang chọn trong Finder",
                              subtitle: selection.isEmpty
                                  ? "Chọn vài tệp trong Finder rồi bấm Đọc lựa chọn."
                                  : "\(selection.count) mục")

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Button("Đọc lựa chọn") { readSelection() }
                            .buttonStyle(.borderedProminent).controlSize(.small)
                            .disabled(busy)
                        if !selection.isEmpty {
                            Button("Bỏ chọn") { selection = []; status = nil }
                                .buttonStyle(.bordered).controlSize(.small)
                        }
                    }

                    if !selection.isEmpty {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(selection.prefix(8), id: \.self) { url in
                                Text(url.lastPathComponent)
                                    .font(.system(size: 12)).lineLimit(1)
                            }
                            if selection.count > 8 {
                                Text("… và \(selection.count - 8) mục nữa")
                                    .font(.system(size: 11)).foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)

                Divider().padding(.horizontal, 20)

                SectionHeader(icon: "bolt",
                              title: "Thao tác nhanh",
                              subtitle: "Áp dụng cho các mục vừa đọc ở trên.")

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 165), spacing: 8)], spacing: 8) {
                    actionButton("Sao chép đường dẫn", "doc.on.doc") { copyPaths() }
                    actionButton("Nén thành ZIP", "archivebox") { compress() }
                    actionButton("Đổi tên hàng loạt…", "textformat.abc") {
                        AppState.shared.navigate(to: .batchRename)
                    }
                    actionButton("Thêm vào Khay thả", "tray.and.arrow.down") { addToTray() }
                    actionButton("Chuyển vào Thùng rác", "trash", destructive: true) { trash() }
                    actionButton("Hiện trong Finder", "folder") { reveal() }
                }
                .padding(.horizontal, 20)

                if let status {
                    Text(status)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 20)
                }

                Divider().padding(.horizontal, 20)

                SectionHeader(icon: "puzzlepiece.extension",
                              title: "Menu chuột phải trong Finder",
                              subtitle: "Thêm mục vào menu ngữ cảnh của Finder.")

                VStack(alignment: .leading, spacing: 8) {
                    Text("macOS không có API công khai cho phép một ứng dụng thường thêm mục vào menu chuột phải của Finder. Cách được Apple hỗ trợ là Quick Action (Shortcuts/Automator) hoặc một Finder Sync Extension riêng.")
                        .font(.system(size: 12)).foregroundColor(.secondary)
                    HStack(spacing: 8) {
                        Button("Mở Tiện ích mở rộng…") { openExtensionsPane() }
                            .buttonStyle(.bordered).controlSize(.small)
                        Button("Mở Automator") {
                            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Automator.app"))
                        }
                        .buttonStyle(.bordered).controlSize(.small)
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 20)
        }
        .background(Color(.windowBackgroundColor))
    }

    private func actionButton(_ title: String, _ icon: String,
                              destructive: Bool = false,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 12))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
        }
        .buttonStyle(.bordered)
        .tint(destructive ? .red : nil)
        .disabled(selection.isEmpty || busy)
    }

    // MARK: Finder selection

    private func readSelection() {
        busy = true
        status = nil
        Task {
            let result = await Self.finderSelection()
            busy = false
            switch result {
            case .success(let urls):
                selection = urls
                status = urls.isEmpty ? "Finder không có mục nào đang chọn." : nil
            case .failure(let message):
                status = message
            }
        }
    }

    private enum SelectionResult {
        case success([URL])
        case failure(String)
    }

    private static func finderSelection() async -> SelectionResult {
        await Task.detached {
            let script = """
            tell application "Finder"
                set sel to selection as alias list
                set out to ""
                repeat with anItem in sel
                    set out to out & POSIX path of anItem & linefeed
                end repeat
                return out
            end tell
            """
            guard let apple = NSAppleScript(source: script) else {
                return .failure("Không tạo được AppleScript.")
            }
            var err: NSDictionary?
            let output = apple.executeAndReturnError(&err)
            if let err {
                let code = (err[NSAppleScript.errorNumber] as? Int) ?? 0
                if code == -1743 {
                    return .failure("Cần quyền Tự động hóa cho Finder — Cài đặt hệ thống → Quyền riêng tư & Bảo mật → Tự động hóa → XFinder → bật Finder.")
                }
                return .failure("Không đọc được lựa chọn: \((err[NSAppleScript.errorMessage] as? String) ?? "lỗi \(code)")")
            }
            let paths = (output.stringValue ?? "")
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            return .success(paths.map { URL(fileURLWithPath: $0) })
        }.value
    }

    // MARK: Actions

    private func copyPaths() {
        let text = selection.map(\.path).joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        status = "Đã sao chép \(selection.count) đường dẫn."
    }

    private func reveal() {
        NSWorkspace.shared.activateFileViewerSelecting(selection)
    }

    private func trash() {
        var moved = 0
        for url in selection {
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                moved += 1
            } catch {
                status = "Không xóa được \(url.lastPathComponent): \(error.localizedDescription)"
            }
        }
        if moved > 0 {
            ActionHistoryStore.shared.recordTrash(urls: selection)
            status = "Đã chuyển \(moved) mục vào Thùng rác."
            selection = []
        }
    }

    private func compress() {
        guard let first = selection.first else { return }
        busy = true
        let items = selection
        let output = first.deletingLastPathComponent()
            .appendingPathComponent("XFinder-\(Int(Date().timeIntervalSince1970)).zip")
        Task.detached {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            p.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent"]
                + items.map(\.path) + [output.path]
            p.standardOutput = Pipe(); p.standardError = Pipe()
            try? p.run()
            p.waitUntilExit()
            let ok = p.terminationStatus == 0
            await MainActor.run {
                busy = false
                status = ok ? "Đã nén thành \(output.lastPathComponent)."
                            : "Nén thất bại."
                if ok {
                    ActionHistoryStore.shared.record(
                        kind: "compress",
                        summary: "Nén \(items.count) mục → \(output.lastPathComponent)")
                }
            }
        }
    }

    private func addToTray() {
        DropTrayStore.shared.add(urls: selection)
        status = "Đã thêm \(selection.count) mục vào Khay thả."
    }

    private func openExtensionsPane() {
        WindowManager.openFinderExtensionsPane()
    }
}
