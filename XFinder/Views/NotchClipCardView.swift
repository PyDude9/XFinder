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

    /// Page 1 of a PDF at ≤ `maxPixel` (ImageIO cannot read PDF), kept per path like images. Misses are cached too.
    static func pdfFirstPage(atPath path: String, maxPixel: Int = 480) -> NSImage? {
        let key = "\(path)#pdf\(maxPixel)" as NSString
        if let hit = cache.object(forKey: key) { return hit === missing ? nil : hit }
        guard let cg = ClipPreviewRules.pdfFirstPage(atPath: path, maxPixel: maxPixel) else {
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

    /// A miss (unreadable payload AND no snippet) is cached too, or a card whose payload file is gone would retry
    /// the read on every render (review 2026-10-13).
    private static let miss: NSString = "\u{0}xfinder-miss"

    static func fullText(snippet: String?, payloadPath: String?) -> String? {
        guard let p = payloadPath, !p.isEmpty else { return snippet }
        if let hit = cache.object(forKey: p as NSString) { return hit === miss ? snippet : hit as String }
        let full = ClipboardText.fullText(snippet: snippet, payloadPath: p) ?? snippet
        cache.setObject((full as NSString?) ?? miss, forKey: p as NSString)
        return full
    }
}

/// One clip as a card on the BLACK notch surface. P1 (OneNotch grammar): a 162 × 112 tile — a type badge
/// (and the pin / Paste Stack position) over the content, the content, and a 22-pt footer: source-app icon ·
/// age · one fact (`NotchClipboardRules.meta`). The background is the surface's own dark fill tinted by the
/// source app's colour (`ClipboardAppColor`, cached per app), so a column of cards reads by where they came from;
/// accent only for the selection ring. `ClipboardCardView` keeps its own look for the in-window pages.
struct NotchClipCardView: View {
    let record: ClipboardRecord
    let selected: Bool
    /// Position in the Paste Stack (1-based) while the stack holds this clip.
    let stackIndex: Int?
    let now: Date
    var width: CGFloat = 162
    var height: CGFloat = 112
    @Environment(\.notchAccent) private var accent

    private static let radius = XFinderTokens.Radius.tile
    private static let footerHeight: CGFloat = 22
    /// Text starts under the badge row (6 + 16 + 4).
    private static let textTop: CGFloat = 26
    private var textLines: Int { height >= 110 ? 4 : 3 }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .clipped()
                header
            }
            footer
        }
        .frame(height: height)
        .background(background)
        .overlay(RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
            .strokeBorder(selected ? accent : XFinderTokens.Notch.cardStroke, lineWidth: selected ? 2 : 1))
        .clipShape(RoundedRectangle(cornerRadius: Self.radius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: Self.radius, style: .continuous))
    }

    private var background: some View {
        let tint = ClipboardAppColor.color(forBundleID: record.sourceBundleID, contentType: record.type)
        return ZStack {
            Color.white.opacity(0.07)
            LinearGradient(colors: [tint.opacity(0.30), tint.opacity(0.06)], startPoint: .top, endPoint: .bottom)
        }
    }

    // MARK: Header — type badge · pin · Paste Stack position

    private var header: some View {
        HStack(spacing: 4) {
            typeBadge
            Spacer(minLength: 0)
            if record.isPinned {
                Image(systemName: "pin.fill").font(.system(size: 9)).foregroundColor(.orange)
                    .frame(width: 16, height: 16)
                    .background(Circle().fill(Color.black.opacity(0.45)))
                    .help(L10n.t("Đã ghim"))
            }
            if let n = stackIndex {
                Text("\(n)").font(.system(size: 9, weight: .bold)).foregroundColor(.black)
                    .frame(width: 16, height: 16).background(Circle().fill(accent))
                    .help(L10n.t("Thêm vào Paste Stack"))
            }
        }
        .padding(.horizontal, 7)
        .padding(.top, 6)
    }

    /// The type, or for a picture its real dimensions (the one fact an image has); a lock for a sealed clip.
    private var typeBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: record.isLocked ? "lock.fill" : record.type.icon).font(.system(size: 8.5, weight: .bold))
            Text(badgeLabel).font(.system(size: 9.5, weight: .semibold)).monospacedDigit().lineLimit(1)
        }
        .foregroundColor(.white.opacity(0.85))
        .padding(.horizontal, 6)
        .frame(height: 16)
        .background(Capsule().fill(Color.black.opacity(0.45)))
    }

    private var badgeLabel: String {
        if record.type == .image, !record.isLocked, case .dimensions(let d)? = meta { return d }
        return record.type.titleVI
    }

    // MARK: Content

    @ViewBuilder private var content: some View {
        if record.isLocked {
            lockedBody
        } else {
            switch record.type {
            case .image: imageBody
            case .color: colorBody
            case .file: fileBody
            case .link:
                VStack(alignment: .leading, spacing: 2) {
                    if let title = record.metadata[LinkPreviewRules.titleKey] {        // D4b: the fetched title, when the opt-in is on
                        Text(title).font(.system(size: 11, weight: .semibold)).foregroundColor(.white).lineLimit(2)
                    }
                    Text(record.metadata["url"]?.isEmpty == false ? record.metadata["url"]! : record.displayPreview)
                        .font(.system(size: 11)).foregroundColor(accent)
                        .lineLimit(record.metadata[LinkPreviewRules.titleKey] == nil ? textLines : max(1, textLines - 2)).multilineTextAlignment(.leading)
                }
                .padding(.horizontal, 9).padding(.top, Self.textTop)
            case .code:
                // D: on-device syntax colouring; the preview is the first 200 characters, so this is cheap.
                HighlightedCodeText(text: record.displayPreview, dark: true, lineLimit: textLines)
                    .padding(.horizontal, 9).padding(.top, Self.textTop)
            case .markdown:
                Text(record.displayPreview)
                    .font(.system(size: 10.5, design: .monospaced)).foregroundColor(.white)
                    .lineLimit(textLines).multilineTextAlignment(.leading)
                    .padding(.horizontal, 9).padding(.top, Self.textTop)
            case .text, .merged:
                Text(record.displayPreview)
                    .font(.system(size: 11)).foregroundColor(.white)
                    .lineLimit(textLines).multilineTextAlignment(.leading)
                    .padding(.horizontal, 9).padding(.top, Self.textTop)
            }
        }
    }

    /// D4 — never a preview for a locked clip; the notch/shelf never unlock in place (they navigate to
    /// the Library, see `NotchClipboardView.select`/`ClipboardShelfController.pasteAt`).
    private var lockedBody: some View {
        VStack(spacing: 4) {
            Image(systemName: "lock.fill").font(.system(size: 18)).foregroundColor(.white.opacity(0.7))
            Text(L10n.t("Đã khoá")).font(.system(size: 11, weight: .semibold)).foregroundColor(.white)
            Text(L10n.t("Mở trong Thư viện")).font(.system(size: 9.5)).foregroundColor(.white.opacity(0.65))
                .multilineTextAlignment(.center)
        }
        .padding(.top, Self.textTop - 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The picture fills the area above the footer (the badge sits over it). Fill when the shapes are close, fit
    /// (whole picture on a backdrop) when they are not — a 2.8:1 screenshot filled here was a zoomed centre crop.
    private var imageBody: some View {
        Group {
            if let path = record.thumbnailPath ?? record.payloadPath ?? record.metadata["path"],
               let img = NotchThumbnailCache.image(atPath: path) {
                let tileAspect = Double(width) / Double(max(1, height - Self.footerHeight))
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
        }
    }

    private var colorBody: some View {
        ZStack(alignment: .topLeading) {
            if let ns = ClipboardClassifier.color(from: record.displayPreview) { Color(ns) } else { Color.white.opacity(0.06) }
            Text(record.displayPreview)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.6), radius: 1, y: 1)   // legible on any swatch colour
                .padding(.horizontal, 9).padding(.top, Self.textTop)
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
        .padding(.horizontal, 9).padding(.top, Self.textTop)
    }

    // MARK: Footer — app icon · age · one fact

    private var meta: NotchClipboardRules.Meta? {
        NotchClipboardRules.meta(type: record.type, dimensions: record.metadata["dimensions"],
                                 path: record.payloadPath ?? record.metadata["path"],
                                 text: NotchTextCache.fullText(snippet: record.textSnippet, payloadPath: record.type == .file ? nil : record.payloadPath))
    }

    private var footer: some View {
        HStack(spacing: 5) {
            if let icon = ClipboardAppIcon.icon(forBundleID: record.sourceBundleID) {
                Image(nsImage: icon).resizable().frame(width: 14, height: 14)
                    .help(record.sourceAppName ?? record.sourceBundleID ?? "")
            } else {
                RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.25)).frame(width: 14, height: 14)
            }
            Text(Self.ageLabel(record.timestamp, now: now))
                .font(XFinderTokens.Font.caption).foregroundColor(.white.opacity(0.65))
                .lineLimit(1).monospacedDigit()
            Spacer(minLength: 2)
            if let m = meta, record.type != .image {        // a picture's size is in its badge
                Text(Self.metaLabel(m)).font(XFinderTokens.Font.caption).foregroundColor(.white.opacity(0.5))
                    .lineLimit(1).monospacedDigit()
            }
        }
        .padding(.horizontal, 7)
        .frame(height: Self.footerHeight)
        .background(Color.black.opacity(0.25))
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
