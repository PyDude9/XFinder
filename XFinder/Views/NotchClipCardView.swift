import SwiftUI
import AppKit
import ImageIO

/// Decoded, downsampled thumbnails for the deck. Measured 2026-10-12: the cards decoded their picture with
/// `NSImage(contentsOfFile:)` on every render — a 2722×1562 PNG for a 174×100 tile, again on each key press.
/// ImageIO's thumbnail path decodes at most `maxPixel` on the long side (and applies EXIF rotation); the
/// result is kept per path. Payload files are written once, so a path never changes meaning.
@MainActor
enum NotchThumbnailCache {
    private static let cache: NSCache<NSString, NSImage> = { let c = NSCache<NSString, NSImage>(); c.countLimit = 120; return c }()
    private static let missing = NSImage()

    static func image(atPath path: String, maxPixel: Int = 480) -> NSImage? {
        let key = "\(path)#\(maxPixel)" as NSString
        if let hit = cache.object(forKey: key) { return hit === missing ? nil : hit }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                     kCGImageSourceCreateThumbnailWithTransform: true,
                                     kCGImageSourceThumbnailMaxPixelSize: maxPixel,
                                     kCGImageSourceShouldCache: false]
        guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else {
            cache.setObject(missing, forKey: key)
            return nil
        }
        let img = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        cache.setObject(img, forKey: key)
        return img
    }
}

/// The full text of a clip for the footer's word/line count, read from its payload file ONCE per path.
/// Before this the deck re-read every visible payload file on each render.
@MainActor
enum NotchTextCache {
    private static let cache: NSCache<NSString, NSString> = { let c = NSCache<NSString, NSString>(); c.countLimit = 200; return c }()

    static func fullText(snippet: String?, payloadPath: String?) -> String? {
        guard let p = payloadPath, !p.isEmpty else { return snippet }
        if let hit = cache.object(forKey: p as NSString) { return hit as String }
        let full = ClipboardText.fullText(snippet: snippet, payloadPath: p) ?? snippet
        if let full { cache.setObject(full as NSString, forKey: p as NSString) }
        return full
    }
}

/// One clip as a card on the BLACK notch surface (D0, wireframe B): a 130×92 tile with the content on
/// top and a 22 pt footer — source-app icon · age · pin · one fact (`NotchClipboardRules.meta`).
/// `ClipboardCardView` keeps its light look for the in-window page; a light card with a solid blue
/// header was the only bright block on the notch (review row 3), so this card uses the surface's own
/// fills: white 10 % body, black 28 % footer, accent only for the selection ring.
struct NotchClipCardView: View {
    let record: ClipboardRecord
    let selected: Bool
    /// Position in the Paste Stack (1-based) while the stack holds this clip.
    let stackIndex: Int?
    let now: Date
    /// 92 in a 3×2 grid; 122 in the horizontal deck (D0, OneNotch reference). Text lines follow it.
    var height: CGFloat = 92
    @Environment(\.notchAccent) private var accent

    private static let radius = XFinderTokens.Radius.tile
    private var textLines: Int { height >= 120 ? 6 : 4 }

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
            footer
        }
        .frame(height: height)
        .background(RoundedRectangle(cornerRadius: Self.radius, style: .continuous).fill(Color.white.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
            .strokeBorder(selected ? accent : Color.clear, lineWidth: 2))
        .clipShape(RoundedRectangle(cornerRadius: Self.radius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: Self.radius, style: .continuous))
    }

    // MARK: Content

    @ViewBuilder private var content: some View {
        switch record.type {
        case .image: imageBody
        case .color: colorBody
        case .file: fileBody
        case .link:
            Text(record.metadata["url"]?.isEmpty == false ? record.metadata["url"]! : record.displayPreview)
                .font(.system(size: 11)).foregroundColor(accent)
                .lineLimit(textLines).multilineTextAlignment(.leading)
                .padding(.horizontal, 9).padding(.top, 7)
        case .code:
            // D: on-device syntax colouring; the preview is the first 200 characters, so this is cheap.
            HighlightedCodeText(text: record.displayPreview, dark: true, lineLimit: textLines)
                .padding(.horizontal, 9).padding(.top, 7)
        case .markdown:
            Text(record.displayPreview)
                .font(.system(size: 10.5, design: .monospaced)).foregroundColor(.white)
                .lineLimit(textLines).multilineTextAlignment(.leading)
                .padding(.horizontal, 9).padding(.top, 7)
        case .text, .merged:
            Text(record.displayPreview)
                .font(.system(size: 11)).foregroundColor(.white)
                .lineLimit(textLines).multilineTextAlignment(.leading)
                .padding(.horizontal, 9).padding(.top, 7)
        }
    }

    private var imageBody: some View {
        ZStack(alignment: .topTrailing) {
            if let path = record.thumbnailPath ?? record.payloadPath ?? record.metadata["path"],
               let img = NotchThumbnailCache.image(atPath: path) {
                // Picture area = card minus the 22-pt footer. Fill when the shapes are close, fit (whole picture
                // on a backdrop) when they are not — a 2.8:1 screenshot filled here was a zoomed centre crop.
                let tileAspect = Double(174) / Double(max(1, height - 22))
                let fits = NotchClipboardRules.imageScaling(imageAspect: Double(img.size.width) / Double(max(1, img.size.height)),
                                                            tileAspect: tileAspect) == .fit
                ZStack {
                    if fits { Color.black.opacity(0.28) }
                    Image(nsImage: img).resizable().aspectRatio(contentMode: fits ? .fit : .fill)
                        .frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
                }
            } else {
                Image(systemName: "photo").font(XFinderTokens.Font.pageIcon).opacity(0.5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if case .dimensions(let d)? = meta {
                Text(d).font(.system(size: 10, weight: .semibold)).monospacedDigit()
                    .padding(.horizontal, 5).padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: XFinderTokens.Radius.badge).fill(Color.black.opacity(0.65)))
                    .padding(6)
            }
        }
    }

    private var colorBody: some View {
        ZStack(alignment: .topLeading) {
            if let ns = ClipboardClassifier.color(from: record.displayPreview) { Color(ns) } else { Color.white.opacity(0.06) }
            Text(record.displayPreview)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.6), radius: 1, y: 1)   // legible on any swatch colour
                .padding(.horizontal, 9).padding(.top, 7)
        }
    }

    private var fileBody: some View {
        HStack(alignment: .center, spacing: 8) {
            if let path = record.payloadPath ?? record.metadata["path"], FileManager.default.fileExists(atPath: path) {
                Image(nsImage: ClipboardAppIcon.fileIcon(forPath: path)).resizable().frame(width: 28, height: 28)
            } else {
                Image(systemName: "doc").font(.system(size: 22)).opacity(0.65).frame(width: 28, height: 28)
            }
            Text(record.displayPreview).font(.system(size: 11)).foregroundColor(.white).lineLimit(3)
        }
        .padding(.horizontal, 9).padding(.vertical, 7)
    }

    // MARK: Footer

    private var meta: NotchClipboardRules.Meta? {
        NotchClipboardRules.meta(type: record.type, dimensions: record.metadata["dimensions"],
                                 path: record.payloadPath ?? record.metadata["path"],
                                 text: NotchTextCache.fullText(snippet: record.textSnippet, payloadPath: record.type == .file ? nil : record.payloadPath))
    }

    private var footer: some View {
        HStack(spacing: 5) {
            if let n = stackIndex {
                Text("\(n)").font(.system(size: 9, weight: .bold)).foregroundColor(.black)
                    .frame(width: 14, height: 14).background(Circle().fill(accent))
                    .help(L10n.t("Thêm vào Paste Stack"))
            }
            if let icon = ClipboardAppIcon.icon(forBundleID: record.sourceBundleID) {
                Image(nsImage: icon).resizable().frame(width: 13, height: 13)
                    .help(record.sourceAppName ?? record.sourceBundleID ?? "")
            } else {
                RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.25)).frame(width: 13, height: 13)
            }
            Text(Self.ageLabel(record.timestamp, now: now))
                .font(XFinderTokens.Font.caption).foregroundColor(.white.opacity(0.65))
                .lineLimit(1).monospacedDigit()
            Spacer(minLength: 2)
            if record.isPinned {
                Image(systemName: "pin.fill").font(.system(size: 9)).foregroundColor(.orange).help(L10n.t("Đã ghim"))
            }
            if let m = meta, record.type != .image {        // the image shows its size on the picture itself
                Text(Self.metaLabel(m)).font(XFinderTokens.Font.caption).foregroundColor(.white.opacity(0.5))
                    .lineLimit(1).monospacedDigit()
            }
        }
        .padding(.horizontal, 7)
        .frame(height: 22)
        .background(Color.black.opacity(0.28))
    }

    /// "Vừa xong" · "5 phút" · "1 giờ" · "3 ngày" · a short date. The unit words are their own store
    /// keys (`phút`, `giờ`, `ngày`) — the existing " phút" fragment means " min LEFT" (the timer).
    static func ageLabel(_ date: Date, now: Date) -> String {
        switch NotchClipboardRules.age(of: date, now: now) {
        case .justNow: return L10n.t("Vừa xong")
        case .minutes(let n): return "\(n) \(L10n.t("phút"))"
        case .hours(let n): return "\(n) \(L10n.t("giờ"))"
        case .days(let n): return "\(n) \(L10n.t("ngày"))"
        case .older(let d):
            let f = DateFormatter(); f.dateStyle = .short; f.timeStyle = .none
            return f.string(from: d)
        }
    }

    static func metaLabel(_ m: NotchClipboardRules.Meta) -> String {
        switch m {
        case .dimensions(let d): return d
        case .fileExtension(let e): return e
        case .words(let n): return "\(n)\(L10n.t(" từ"))"
        case .lines(let n): return "\(n)\(L10n.t(" dòng"))"
        }
    }
}
