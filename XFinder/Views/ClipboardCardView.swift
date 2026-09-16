import AppKit
import SwiftUI

/// PasteApp-style clipboard card (guide §2): dynamic accent header from the
/// source app's icon tint, rich per-type body, metadata footer. macOS 12-safe
/// (no Grid/symbolEffect/scrollContentBackground).
struct ClipboardCardView: View {
    let record: ClipboardRecord
    let selected: Bool
    let onPreview: () -> Void

    @Environment(ClipboardManager.self) private var clipboardManager
    @State private var hovering = false
    @State private var appIcon: NSImage?

    var body: some View {
        VStack(spacing: 0) {
            // Thanh màu trên đỉnh khi item được ghim vào một bảng (vd "Error"
            // màu đỏ → thanh đỏ) — phản ánh đúng danh mục người dùng kéo-vào.
            if clipboardManager.pinnedColor(for: record.id) != nil {
                Rectangle().fill(accent).frame(height: 3)
            }
            // Header: app icon + name + time, accent-tinted
            HStack(spacing: 8) {
                Group {
                    if let icon = appIcon {
                        Image(nsImage: icon).resizable()
                    } else {
                        Image(systemName: iconFor(record.type)).foregroundColor(.secondary)
                    }
                }
                .frame(width: 22, height: 22).cornerRadius(5)
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.displayTitle).font(.caption).fontWeight(.semibold).lineLimit(1)
                    Text(record.timeString).font(.caption2).foregroundColor(.secondary)
                }
                Spacer()
                Button {
                    ClipboardPasteEngine.writeToPasteboard(record: record)
                } label: {
                    Image(systemName: "doc.on.doc").font(.caption).foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Sao chép lại vào clipboard")
            }
            .padding(12)
            .background(accent.opacity(0.14))
            Divider()

            // Body per content type
            VStack(alignment: .leading, spacing: 8) {
                switch record.type {
                case .text:
                    Text(fullText ?? record.displayPreview)
                        .font(.system(size: 13))
                        .lineLimit(6)
                case .markdown:
                    Text(fullText ?? record.displayPreview)
                        .font(.system(size: 12))
                        .lineLimit(7)
                case .code:
                    Text(fullText ?? record.displayPreview)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.green)
                        .lineLimit(8)
                case .image:
                    if let path = record.thumbnailPath ?? record.payloadPath,
                       let img = NSImage(contentsOfFile: path) {
                        Image(nsImage: img)
                            .resizable().aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 130).cornerRadius(4)
                    } else {
                        Image(systemName: "photo").font(.system(size: 40)).foregroundColor(.secondary)
                    }
                    HStack {
                        if let dims = record.metadata["dimensions"] {
                            Text(dims).font(.caption).foregroundColor(.secondary)
                        }
                        if record.ocrText != nil {
                            Label("OCR", systemImage: "text.viewfinder")
                                .font(.caption2).foregroundColor(.accentColor)
                        }
                    }
                case .link:
                    Label(record.metadata["url"]?.isEmpty == false ? record.metadata["url"]! : record.displayPreview,
                          systemImage: "link")
                        .font(.system(size: 12))
                        .lineLimit(4)
                        .foregroundColor(.accentColor)
                case .color:
                    HStack(spacing: 10) {
                        if let ns = ClipboardClassifier.color(from: record.displayPreview) {
                            Circle().fill(Color(ns)).frame(width: 44, height: 44)
                        } else {
                            Circle().fill(Color.blue).frame(width: 44, height: 44)
                        }
                        Text(record.displayPreview)
                            .font(.system(size: 12, design: .monospaced))
                    }
                case .file:
                    Label(record.displayPreview, systemImage: "doc.fill")
                        .font(.system(size: 12)).lineLimit(2)
                    if let p = record.metadata["path"] {
                        Text(p).font(.caption2).foregroundColor(.secondary).lineLimit(2)
                    }
                }
                Spacer()
            }
            .padding(12)
            Divider()

            // Footer: type + length / OCR-hit hint
            HStack(spacing: 8) {
                Text(record.type.rawValue.uppercased())
                    .font(.caption2).fontWeight(.semibold).foregroundColor(.secondary)
                Spacer()
                if let len = record.metadata["length"] {
                    Text("\(len) ký tự").font(.caption2).foregroundColor(.secondary)
                }
            }
            .padding(12)
            .background(Color(.controlBackgroundColor).opacity(0.5))
        }
        .background(Color(.controlBackgroundColor))
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(selected ? Color.accentColor : Color.secondary.opacity(0.25),
                        lineWidth: selected ? 2 : 1)
        )
        .shadow(radius: hovering ? 6 : 2)
        .scaleEffect(hovering ? 1.03 : 1.0)
        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: hovering)
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { onPreview() }
        .onAppear {
            appIcon = ClipboardAppIcon.icon(forBundleID: record.sourceBundleID)
        }
    }

    private var accent: Color {
        if let boardColor = clipboardManager.pinnedColor(for: record.id) { return boardColor }
        if let hex = record.metadata["accent"], !hex.isEmpty {
            return Color(hex: hex) ?? .accentColor
        }
        return .accentColor
    }

    /// Short payloads inline; long ones load from disk on appear.
    private var fullText: String? {
        if let p = record.payloadPath, record.type == .text,
           let s = try? String(contentsOfFile: p, encoding: .utf8) {
            return String(s.prefix(1200))
        }
        return record.textSnippet
    }

    private func iconFor(_ t: ContentType) -> String {
        switch t {
        case .text: return "doc.text"
        case .code: return "curlybraces"
        case .markdown: return "doc.richtext"
        case .image: return "photo"
        case .link: return "link"
        case .color: return "paintpalette"
        case .file: return "doc"
        }
    }
}

private extension Color {
    init?(hex: String) {
        guard let ns = ClipboardClassifier.color(from: hex) else { return nil }
        self.init(ns)
    }
}
