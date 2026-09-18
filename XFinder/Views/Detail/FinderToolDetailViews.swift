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
                Text(L10n.t("Tương thích media"))
                    .font(.system(size: 22, weight: .bold))
                    .padding(.horizontal, 20).padding(.top, 16)

                SettingsCard(title: L10n.t("Tập tin cần kiểm tra"),
                             subtitle: files.isEmpty ? L10n.t("Chưa chọn") : "\(files.count)\(L10n.t(" tập tin"))") {
                    HStack {
                        Button(L10n.t("Chọn tập tin…")) { pick() }
                        if !files.isEmpty {
                            Button(L10n.t("Xóa")) { files = []; rows = [] }.font(.system(size: 12))
                        }
                    }
                }
                .padding(.horizontal, 20)

                Button {
                    check()
                } label: {
                    HStack {
                        if checking { ProgressView().scaleEffect(0.7) }
                        Text(L10n.t("Kiểm tra phát")).fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(files.isEmpty || checking)
                .padding(.horizontal, 20)

                SettingsCard(title: L10n.t("Kết quả"),
                             subtitle: L10n.t("Nguồn: AVFoundation — thiết bị này có/mở được không")) {
                    if rows.isEmpty {
                        Text(L10n.t("Chọn tập tin và bấm Kiểm tra phát."))
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
                                    Text(r.playable ? L10n.t("Phát được") : L10n.t("Không"))
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

// `FinderUtilsDetailView` now lives in its own file
// (Views/Detail/FinderUtilsDetailView.swift), rebuilt in the flat
// System-Settings layout. The old copy here was removed along with its
// private UserDefaults.bool helper, which nothing else used.
