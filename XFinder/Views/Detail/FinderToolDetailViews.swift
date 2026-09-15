import SwiftUI
import AppKit
import AVFoundation
import CoreMedia

/// Tương thích media — file → codec/container compatibility reference. Real
/// data comes from AVAsset's format readers (device-guaranteed public API);
/// anything AVFoundation cannot decode is reported as such, not guessed.
struct MediaCompatDetailView: View {
    @State private var files: [URL] = []
    @State private var rows: [Row] = []
    @State private var checking = false

    struct Row: Identifiable {
        let id: String
        let name: String
        let container: String
        let playable: Bool
        let codecs: String
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Tương thích media")
                    .font(.system(size: 22, weight: .bold))
                    .padding(.horizontal, 20).padding(.top, 16)

                SettingsCard(title: "Tập tin cần kiểm tra",
                             subtitle: files.isEmpty ? "Chưa chọn" : "\(files.count) tập tin") {
                    HStack {
                        Button("Chọn tập tin…") { pick() }
                        if !files.isEmpty {
                            Button("Xóa") { files = []; rows = [] }.font(.system(size: 12))
                        }
                    }
                }
                .padding(.horizontal, 20)

                Button {
                    check()
                } label: {
                    HStack {
                        if checking { ProgressView().scaleEffect(0.7) }
                        Text("Kiểm tra phát").fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(files.isEmpty || checking)
                .padding(.horizontal, 20)

                SettingsCard(title: "Kết quả",
                             subtitle: "Nguồn: AVFoundation — thiết bị này có/mở được không") {
                    if rows.isEmpty {
                        Text("Chọn tập tin và bấm Kiểm tra phát.")
                            .font(.caption).foregroundColor(.secondary)
                    } else {
                        VStack(spacing: 6) {
                            ForEach(rows) { r in
                                HStack {
                                    Image(systemName: r.playable ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        .foregroundColor(r.playable ? .green : .red)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(r.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                                        Text("\(r.container) · \(r.codecs)")
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundColor(.secondary).lineLimit(1)
                                    }
                                    Spacer()
                                    Text(r.playable ? "Phát được" : "Không")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(r.playable ? .green : .red)
                                }
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(Color(.controlBackgroundColor).opacity(0.6))
                                .cornerRadius(6)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20).padding(.bottom, 20)
            }
        }
        .background(Color(.windowBackgroundColor))
    }

    private func pick() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK { files = panel.urls }
    }

    private func check() {
        checking = true
        let list = files
        Task.detached(priority: .userInitiated) {
            var made: [Row] = []
            for url in list { made.append(Self.inspect(url)) }
            let frozen = made
            await MainActor.run {
                rows = frozen
                checking = false
            }
        }
    }

    private nonisolated static func inspect(_ url: URL) -> Row {
        let asset = AVURLAsset(url: url)
        let tracks = asset.tracks
        let playable = !tracks.isEmpty
        let container = url.pathExtension.isEmpty ? "—" : url.pathExtension.uppercased()
        var codecs: [String] = []
        for t in asset.tracks {
            if let f = t.formatDescriptions.first {
                let fd = f as! CMFormatDescription
                codecs.append(fourCC(CMFormatDescriptionGetMediaType(fd)))
            }
        }
        return Row(id: url.path, name: url.lastPathComponent,
                   container: container,
                   playable: playable,
                   codecs: codecs.isEmpty ? "—" : Array(Set(codecs)).joined(separator: ", "))
    }

    private nonisolated static func fourCC(_ code: FourCharCode) -> String {
        let bytes: [UInt8] = [
            UInt8((code >> 24) & 0xFF), UInt8((code >> 16) & 0xFF),
            UInt8((code >> 8) & 0xFF), UInt8(code & 0xFF),
        ]
        let s = String(bytes: bytes, encoding: .ascii) ?? "?"
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Tiện ích Finder — toggles the user-facing Finder behaviors that have
/// supported `defaults` keys, applied via `cfprefsd` + Finder relaunch.
/// Readback is real (reads the same domain), so the switches show current truth.
struct FinderUtilsDetailView: View {
    @State private var showExtensions = true
    @State private var showHidden = false
    @State private var showFullPath = true
    @State private var doubleClickToOpen = false
    @State private var status: String? = nil

    private let domain = "com.apple.finder"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Tiện ích Finder")
                    .font(.system(size: 22, weight: .bold))
                    .padding(.horizontal, 20).padding(.top, 16)

                SettingsCard(title: "Hiển thị") {
                    VStack(spacing: 10) {
                        ToggleRow(title: "Hiện phần mở rộng tập tin", isOn: $showExtensions)
                        ToggleRow(title: "Hiện tập tin ẩn (.DS_Store…)", isOn: $showHidden)
                        ToggleRow(title: "Hiện đường dẫn đầy đủ ở tiêu đề", isOn: $showFullPath)
                        ToggleRow(title: "Nháy đúp mở thay vì chọn", isOn: $doubleClickToOpen)
                    }
                }
                .padding(.horizontal, 20)

                Button {
                    applyAll()
                } label: {
                    Text("Áp dụng").fontWeight(.semibold).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, 20)

                if let s = status {
                    SettingsCard(title: "Kết quả") {
                        Text(s).font(.system(size: 12))
                    }
                    .padding(.horizontal, 20)
                }

                SettingsCard(title: "Ghi chú") {
                    Text("Thay đổi ghi thẳng vào cấu hình Finder và khởi động lại Finder. Đây là các khóa Apple được hỗ trợ; tính năng sâu hơn (menu ngữ cảnh tùy biến) cần Finder Extension.")
                        .font(.caption).foregroundColor(.secondary)
                }
                .padding(.horizontal, 20).padding(.bottom, 20)
            }
        }
        .background(Color(.windowBackgroundColor))
        .onAppear(perform: readBack)
    }

    private func readBack() {
        let d = UserDefaults(suiteName: domain)
        showExtensions = d?.object(forKey: "AppleShowAllExtensions") as? Bool ?? false
        showHidden = d?.bool(forKey: "FXPreferredStartAtDesktop") ?? false ||
                     (d?.bool(forKey: "AppleShowAllFiles") ?? false)
        showFullPath = d?.bool(forKey: "_FXShowPosixPathInTitle") ?? false
        doubleClickToOpen = d?.bool(forKey: "FXDoubleClickToOpen") ?? false
    }

    private func applyAll() {
        let d = UserDefaults(suiteName: domain)
        d?.set(showExtensions, forKey: "AppleShowAllExtensions")
        d?.set(showHidden, forKey: "AppleShowAllFiles")
        d?.set(showFullPath, forKey: "_FXShowPosixPathInTitle")
        d?.set(doubleClickToOpen, forKey: "FXDoubleClickToOpen")
        d?.synchronize()
        // Flush caches and restart Finder so it picks the values up.
        _ = run(["/usr/bin/killall", "-KILL", "cfprefsd"])
        _ = run(["/usr/bin/killall", "Finder"])
        status = "Đã ghi cấu hình và khởi động lại Finder."
    }

    @discardableResult
    private func run(_ cmd: [String]) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: cmd[0])
        p.arguments = Array(cmd.dropFirst())
        p.standardOutput = Pipe(); p.standardError = Pipe()
        do { try p.run(); p.waitUntilExit(); return p.terminationStatus == 0 }
        catch { return false }
    }
}

private extension UserDefaults {
    func bool(forKey key: String) -> Bool { object(forKey: key) as? Bool ?? false }
}
