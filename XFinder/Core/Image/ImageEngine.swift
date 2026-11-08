import Foundation

/// Pure rules for the image tools (Thao tác Finder now, the Notch hub in B2d): which output formats
/// exist on THIS Mac, which inputs are images, and output naming.
///
/// Measured on macOS 27 (`CGImageDestinationCopyTypeIdentifiers`): JPEG, PNG, HEIC, AVIF, TIFF and GIF
/// encode; **WebP does not** (`CGImageDestinationCreateWithURL` returns nil for org.webmproject.webp).
/// The plan said "WebP nếu encoder có" — there is none, so the UI derives its list from the encoder
/// list and never offers a format the machine cannot write.
enum ImageEngine {

    enum Target: String, CaseIterable, Sendable, Codable {
        case jpeg, png, heic, avif, gif, tiff
        var uti: String {
            switch self {
            case .jpeg: return "public.jpeg"
            case .png: return "public.png"
            case .heic: return "public.heic"
            case .avif: return "public.avif"
            case .gif: return "com.compuserve.gif"
            case .tiff: return "public.tiff"
            }
        }
        var fileExtension: String { self == .jpeg ? "jpg" : rawValue }
        var label: String { self == .jpeg ? "JPEG" : rawValue.uppercased() }
        /// Lossy formats take a quality setting; PNG ignores it.
        var isLossy: Bool { self == .jpeg || self == .heic || self == .avif }
    }

    /// Targets this machine can actually encode, in display order.
    static func availableTargets(encodable: [String]) -> [Target] {
        let set = Set(encodable)
        return Target.allCases.filter { set.contains($0.uti) }
    }

    /// Extensions ImageIO reads that the tools accept. Deliberately excludes PDF (it has its own tools)
    /// and RAW (decoding RAW through ImageIO bakes in default development — not what a photographer wants).
    static let inputExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "avif", "tif", "tiff", "gif", "bmp", "webp"]

    static func isImage(_ url: URL) -> Bool { inputExtensions.contains(url.pathExtension.lowercased()) }

    /// Converting a file into its own format is a no-op copy; the UI should not offer it.
    static func isSameFormat(_ url: URL, _ target: Target) -> Bool {
        let ext = url.pathExtension.lowercased()
        switch target {
        case .jpeg: return ext == "jpg" || ext == "jpeg"
        case .heic: return ext == "heic" || ext == "heif"
        case .tiff: return ext == "tif" || ext == "tiff"
        default: return ext == target.fileExtension
        }
    }

    enum Operation: Equatable, Sendable {
        case convert(Target)
        case resize(maxPixels: Int)
        case removeBackground
    }

    /// "IMG_1.HEIC" → convert JPEG "IMG_1.jpg", resize "IMG_1-1600px.HEIC", cutout "IMG_1-cutout.png";
    /// never onto an existing file or the source (keep-both numbering).
    static func outputURL(for source: URL, operation: Operation, exists: (URL) -> Bool) -> URL {
        let dir = source.deletingLastPathComponent()
        let stem = source.deletingPathExtension().lastPathComponent
        let name: String
        switch operation {
        case .convert(let t): name = "\(stem).\(t.fileExtension)"
        case .resize(let px): name = "\(stem)-\(px)px.\(source.pathExtension)"
        case .removeBackground: name = "\(stem)-cutout.png"
        }
        let src = source.standardizedFileURL.path
        let taken: (URL) -> Bool = { exists($0) || $0.standardizedFileURL.path == src }
        guard case .write(let url) = ArchiveEngine.destination(base: dir.appendingPathComponent(name), policy: .keepBoth, exists: taken)
        else { return dir.appendingPathComponent(name) }
        return url
    }

    /// Resize presets the UI offers (longest edge, pixels).
    static let resizePresets = [3840, 2048, 1600, 1024, 512]

    /// A resize only makes sense when it actually shrinks the image.
    static func resizeShrinks(width: Int, height: Int, maxPixels: Int) -> Bool { max(width, height) > maxPixels }
}
