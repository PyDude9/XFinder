import AppKit
import SwiftUI

/// Paste 7-style clipboard card: dynamic vibrant accent header matching the source app's
/// brand icon color, rich per-type body, metadata footer, elevated selection.
struct ClipboardCardView: View {
    let record: ClipboardRecord
    let selected: Bool
    var onSelect: (() -> Void)? = nil
    var onPreview: (() -> Void)? = nil
    /// D4 — shown under "Đã khoá" when this card is locked. The Library passes
    /// `L10n.t("Bấm để mở khoá (Touch ID)")`; the shelf passes nil, which falls back to
    /// `L10n.t("Mở trong Thư viện")` (a shelf card never unlocks in place — it only navigates there).
    var lockedHint: String? = nil

    @Environment(ClipboardManager.self) private var clipboardManager
    @AppStorage("clipboard.textSize") private var textSize: Double = 13.5
    @Environment(\.colorScheme) private var colorScheme
    @State private var hovering = false
    @State private var appIcon: NSImage?

    var body: some View {
        VStack(spacing: 0) {
            // Thanh màu trên đỉnh khi item được ghim vào một bảng tùy chỉnh
            if let boardColor = clipboardManager.pinnedColor(for: record.id) {
                Rectangle().fill(boardColor).frame(height: 3)
            }

            // Header: Vibrant app brand color background (Paste 7 style)
            headerView

            // Body: per content type
            bodyView
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Color(.windowBackgroundColor))

            // Footer metadata
            footerView
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(selected ? Color.accentColor : Color.primary.opacity(0.08),
                        lineWidth: selected ? 2.5 : 1)
        )
        .shadow(color: Color.black.opacity(selected ? 0.22 : (hovering ? 0.14 : 0.07)),
                radius: selected ? 10 : (hovering ? 6 : 3),
                y: selected ? 4 : (hovering ? 3 : 1))
        .offset(y: selected ? -4 : (hovering ? -2 : 0))
        .scaleEffect(selected ? 1.02 : 1.0)
        .animation(.spring(response: 0.26, dampingFraction: 0.8), value: hovering)
        .animation(.spring(response: 0.26, dampingFraction: 0.8), value: selected)
        .onHover { hovering = $0 }
        .onTapGesture {
            if clipboardManager.isMultiSelectActive {
                clipboardManager.toggleMultiSelect(record.id)
            } else if let onSelect {
                onSelect()
            }
        }
        .onAppear {
            appIcon = ClipboardAppIcon.icon(forBundleID: record.sourceBundleID)
        }
    }

    // MARK: - Header (Paste 7 Vibrant Header)

    private var headerView: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(record.type.titleVI)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(record.timeString)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(1)
            }

            Spacer()

            if record.isPinned {
                Image(systemName: "pin.fill")
                    .font(.caption2)
                    .foregroundColor(.white)
                    .padding(4)
                    .background(Circle().fill(Color.orange))
                    .help(L10n.t("Đã ghim"))
            }

            if record.isSavedSnippet {
                Image(systemName: "bookmark.fill")
                    .font(.caption2)
                    .foregroundColor(.white)
                    .padding(4)
                    .background(Circle().fill(Color.accentColor))
                    .help(L10n.t("Đã lưu"))
            }

            // Quick actions on hover
            if hovering && !clipboardManager.isMultiSelectActive {
                Button {
                    clipboardManager.togglePin(record.id)
                } label: {
                    Image(systemName: record.isPinned ? "pin.fill" : "pin")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(5)
                        .background(Circle().fill(Color.black.opacity(0.25)))
                }
                .buttonStyle(.plain)
                .help(record.isPinned ? L10n.t("Bỏ ghim") : L10n.t("Ghim"))

                Button {
                    ClipboardPasteEngine.writeToPasteboard(record: record)
                    ClipboardSounds.playCopy()
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(5)
                        .background(Circle().fill(Color.black.opacity(0.25)))
                }
                .buttonStyle(.plain)
                .help(L10n.t("Sao chép lại vào clipboard"))
            }

            // Source App Icon badge
            Group {
                if let icon = appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: iconFor(record.type))
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                }
            }
            .frame(width: 26, height: 26)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.18), radius: 2, y: 1)
            .help(record.displayTitle)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(height: 48)
        .background(accent)
    }

    // MARK: - Body View

    @ViewBuilder
    private var bodyView: some View {
        VStack(alignment: .leading, spacing: 6) {
            if record.isLocked {
                lockedBody
            } else {
                switch record.type {
                case .text, .markdown:
                    formattedTextBody
                case .code:
                    codeBody
                case .image:
                    imageBody
                case .link:
                    linkBody
                case .color:
                    colorBody
                case .file:
                    fileBody
                case .merged:
                    mergedBody
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
    }

    /// D4 — a locked clip never renders a preview, whatever its type. The footer's type label is left
    /// alone (the type itself is not secret; the content is).
    private var lockedBody: some View {
        VStack(spacing: 6) {
            Image(systemName: "lock.fill")
                .font(.system(size: 22))
                .foregroundColor(.secondary)
            Text(L10n.t("Đã khoá"))
                .font(.system(size: 12, weight: .semibold))
            Text(lockedHint ?? L10n.t("Mở trong Thư viện"))
                .font(.system(size: 10.5))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 8)
    }

    private var formattedTextBody: some View {
        let text = fullText ?? record.displayPreview

        if let img = ClipboardClassifier.resolveCandidateImage(for: record) {
            return AnyView(
                VStack(alignment: .center, spacing: 6) {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: 110)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    Text(text)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            )
        }

        let lines = text.split(separator: "\n", maxSplits: 2, omittingEmptySubsequences: true)
        let firstLine = lines.first.map(String.init) ?? ""

        return AnyView(
            VStack(alignment: .leading, spacing: 4) {
                if lines.count > 1 && firstLine.count < 50 {
                    Text(firstLine)
                        .font(.system(size: CGFloat(textSize), weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(2)
                    let remaining = text.dropFirst(firstLine.count).trimmingCharacters(in: .whitespacesAndNewlines)
                    Text(remaining)
                        .font(.system(size: CGFloat(textSize - 1)))
                        .foregroundColor(.secondary)
                        .lineLimit(5)
                } else {
                    Text(text)
                        .font(.system(size: CGFloat(textSize)))
                        .foregroundColor(.primary)
                        .lineLimit(7)
                }
            }
        )
    }

    private var codeBody: some View {
        let text = fullText ?? record.displayPreview
        return VStack(alignment: .leading, spacing: 4) {
            // D: on-device syntax colouring (`CodeHighlighter`); palette follows the shelf's appearance.
            HighlightedCodeText(text: text, font: .system(size: CGFloat(textSize - 2), design: .monospaced),
                                dark: colorScheme == .dark, lineLimit: 7)
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                )
        }
    }

    private var imageBody: some View {
        VStack(alignment: .center, spacing: 6) {
            ZStack(alignment: .bottomTrailing) {
                // D3 review: decode through the shared ImageIO thumbnail cache (≤ 480 px) instead of
                // `NSImage(contentsOfFile:)` in a computed property — the Library shows 60 of these at once.
                if let path = record.thumbnailPath ?? record.payloadPath ?? record.metadata["path"],
                   let img = NotchThumbnailCache.image(atPath: path) {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: 110)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                } else if let img = ClipboardClassifier.resolveCandidateImage(for: record) {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: 110)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                        .frame(maxWidth: .infinity, minHeight: 90, maxHeight: 110)
                        .overlay(
                            Image(systemName: "photo")
                                .font(.system(size: 32))
                                .foregroundColor(.secondary)
                        )
                }

                if let dims = record.metadata["dimensions"] {
                    Text(dims)
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.black.opacity(0.65)))
                        .padding(4)
                }
            }

            if let snippet = record.textSnippet, snippet != "Image" && !snippet.isEmpty {
                Text(L10n.t(snippet))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            if let ocr = record.ocrText, !ocr.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "text.viewfinder")
                        .font(.system(size: 10))
                        .foregroundColor(.accentColor)
                    Text(ocr)
                        .font(.system(size: 10))
                        .italic()
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    Spacer()
                }
            }
        }
    }

    private var linkBody: some View {
        let urlStr = record.metadata["url"]?.isEmpty == false ? record.metadata["url"]! : record.displayPreview
        let host = URL(string: urlStr)?.host ?? ""

        // D4b: an opt-in preview (title + image fetched from the page) when the record carries one.
        let title = record.metadata[LinkPreviewRules.titleKey]
        let image = record.metadata[LinkPreviewRules.imageKey].flatMap { NotchThumbnailCache.image(atPath: $0, maxPixel: 160) }
        return HStack(alignment: .top, spacing: 8) {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                    .frame(width: 56, height: 56).clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "link")
                        .font(.system(size: 12))
                        .foregroundColor(accent)
                    Text(host.isEmpty ? urlStr : host)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(accent)
                        .lineLimit(1)
                }
                if let title {
                    Text(title).font(.system(size: 12, weight: .medium)).lineLimit(2)
                }
                Text(urlStr)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(title == nil ? 4 : 2)
            }
        }
    }

    private var colorBody: some View {
        HStack(spacing: 12) {
            if let ns = ClipboardClassifier.color(from: record.displayPreview) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(ns))
                    .frame(width: 52, height: 52)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.1), radius: 3, y: 1)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(record.displayPreview.uppercased())
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                Text(L10n.t("Màu sắc"))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 8)
    }

    private var fileBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            let path = record.metadata["path"] ?? record.payloadPath
            if let path, let img = NotchThumbnailCache.image(atPath: path) {
                ZStack(alignment: .bottomTrailing) {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: 110)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    if let dims = record.metadata["dimensions"] {
                        Text(dims)
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.black.opacity(0.65)))
                            .padding(4)
                    }
                }
                Text(record.displayPreview)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else if let img = ClipboardClassifier.resolveCandidateImage(for: record) {
                ZStack(alignment: .bottomTrailing) {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: 110)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    if let dims = record.metadata["dimensions"] {
                        Text(dims)
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.black.opacity(0.65)))
                            .padding(4)
                    }
                }
                Text(record.displayPreview)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "doc.fill")
                        .font(.system(size: 24))
                        .foregroundColor(accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(record.displayPreview)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(2)
                        if let path {
                            Text(path)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
            }
        }
    }

    private var mergedBody: some View {
        let parts = record.mergedComponents
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("\(parts.count) \(L10n.t("mục"))", systemImage: "arrow.triangle.merge")
                    .font(.caption2).fontWeight(.semibold)
                    .foregroundColor(.accentColor)
                Spacer()
            }
            ForEach(Array(parts.prefix(2).enumerated()), id: \.offset) { idx, part in
                HStack(alignment: .top, spacing: 4) {
                    Text("\(idx + 1).")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                    Text(part)
                        .font(.system(size: CGFloat(textSize - 2)))
                        .lineLimit(2)
                }
            }
            if parts.count > 2 {
                Text("\(L10n.t("…và "))\(parts.count - 2)\(L10n.t(" mục nữa"))")
                    .font(.caption2).foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack(spacing: 6) {
            if let len = record.metadata["length"] {
                Text("\(len)\(L10n.t(" ký tự"))")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
            } else if record.type == .image, let dims = record.metadata["dimensions"] {
                Text(dims)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
            } else if record.type == .link, let host = URL(string: record.metadata["url"] ?? "")?.host {
                Text(host)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
            }
            Spacer()
            if clipboardManager.isMultiSelectActive {
                let isChecked = clipboardManager.multiSelectedIDs.contains(record.id)
                Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13))
                    .foregroundColor(isChecked ? .accentColor : .secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.02))
        .overlay(Divider().opacity(0.3), alignment: .top)
    }

    // MARK: - Helpers

    private var accent: Color {
        if let boardColor = clipboardManager.pinnedColor(for: record.id) { return boardColor }
        return ClipboardAppColor.color(forBundleID: record.sourceBundleID, contentType: record.type)
    }

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
        case .merged: return "arrow.triangle.merge"
        }
    }
}
