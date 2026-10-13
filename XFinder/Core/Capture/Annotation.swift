import Foundation
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers

/// F4 — Chụp & chú thích: the annotation document and renderer. Pure Foundation/CoreGraphics/CoreText/ImageIO —
/// no AppKit/SwiftUI, so the editor's model and the pixel renderer are both unit-testable without a running app.
///
/// All coordinates in `Mark`/`AnnotationDocument` are IMAGE PIXELS with the origin at the TOP-LEFT, matching the
/// screenshot's own pixel grid. `scale` is pixels-per-point (2 on a Retina capture) and is used only to convert
/// `StrokeWidth.points` and hit-test tolerance into pixels.

// MARK: - Tools

enum AnnotationTool: String, CaseIterable {
    case select, arrow, rectangle, text, counter, blur, highlighter, crop

    var titleKey: String {
        switch self {
        case .select: return "Chọn"
        case .arrow: return "Mũi tên"
        case .rectangle: return "Khung"
        case .text: return "Chữ"
        case .counter: return "Số thứ tự"
        case .blur: return "Làm mờ"
        case .highlighter: return "Tô sáng"
        case .crop: return "Cắt"
        }
    }

    var symbol: String {
        switch self {
        case .select: return "cursorarrow"
        case .arrow: return "arrow.up.right"
        case .rectangle: return "rectangle"
        case .text: return "textformat"
        case .counter: return "number.circle"
        case .blur: return "eye.slash"
        case .highlighter: return "highlighter"
        case .crop: return "crop"
        }
    }

    var keyEquivalent: String {
        switch self {
        case .select: return "V"
        case .arrow: return "A"
        case .rectangle: return "R"
        case .text: return "T"
        case .counter: return "N"
        case .blur: return "B"
        case .highlighter: return "H"
        case .crop: return "C"
        }
    }
}

// MARK: - Colour / stroke width

enum MarkColor: String, CaseIterable {
    case red, yellow, green, blue, black, white

    /// 0...1 components, matching the named macOS system colours used across the app.
    var rgb: (r: CGFloat, g: CGFloat, b: CGFloat) {
        switch self {
        case .red: return (0xFF / 255.0, 0x3B / 255.0, 0x30 / 255.0)
        case .yellow: return (0xFF / 255.0, 0xCC / 255.0, 0x00 / 255.0)
        case .green: return (0x34 / 255.0, 0xC7 / 255.0, 0x59 / 255.0)
        case .blue: return (0x0A / 255.0, 0x84 / 255.0, 0xFF / 255.0)
        case .black: return (0x1D / 255.0, 0x1D / 255.0, 0x1F / 255.0)
        case .white: return (1, 1, 1)
        }
    }
}

enum StrokeWidth: String, CaseIterable {
    case thin, medium, thick

    var titleKey: String {
        switch self {
        case .thin: return "Mảnh"
        case .medium: return "Vừa"
        case .thick: return "Dày"
        }
    }

    /// Stroke width in IMAGE POINTS. Multiply by the document's `scale` to get pixels.
    var points: CGFloat {
        switch self {
        case .thin: return 3
        case .medium: return 6
        case .thick: return 10
        }
    }
}

// MARK: - Mark

struct Mark: Identifiable, Equatable {
    enum Kind: Equatable {
        case arrow(from: CGPoint, to: CGPoint)
        case rectangle(CGRect)
        case text(origin: CGPoint, string: String, fontSize: CGFloat)
        case counter(center: CGPoint, number: Int)
        case blur(CGRect)
        case highlight(CGRect)
    }

    var id: UUID
    var kind: Kind
    var color: MarkColor
    var width: StrokeWidth

    init(id: UUID = UUID(), kind: Kind, color: MarkColor, width: StrokeWidth) {
        self.id = id
        self.kind = kind
        self.color = color
        self.width = width
    }

    /// Bounds in image pixels. Text bounds are an estimate (no CoreText layout dependency needed for hit-testing
    /// or canvas placement — the renderer does its own precise CoreText layout when drawing).
    var bounds: CGRect {
        switch kind {
        case let .arrow(from, to):
            let minX = min(from.x, to.x)
            let minY = min(from.y, to.y)
            let maxX = max(from.x, to.x)
            let maxY = max(from.y, to.y)
            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        case let .rectangle(r), let .blur(r), let .highlight(r):
            return r.standardized
        case let .text(origin, string, fontSize):
            let estimatedWidth = CGFloat(max(string.count, 1)) * fontSize * 0.6
            let estimatedHeight = fontSize * 1.3
            return CGRect(x: origin.x, y: origin.y, width: estimatedWidth, height: estimatedHeight)
        case let .counter(center, _):
            // Counter badges are drawn as a fixed-radius circle; see AnnotationRenderer.counterRadius.
            let r = AnnotationRenderer.counterRadius
            return CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
        }
    }

    func moved(by delta: CGVector) -> Mark {
        var copy = self
        switch kind {
        case let .arrow(from, to):
            copy.kind = .arrow(from: from.offset(by: delta), to: to.offset(by: delta))
        case let .rectangle(r):
            copy.kind = .rectangle(r.offsetBy(dx: delta.dx, dy: delta.dy))
        case let .blur(r):
            copy.kind = .blur(r.offsetBy(dx: delta.dx, dy: delta.dy))
        case let .highlight(r):
            copy.kind = .highlight(r.offsetBy(dx: delta.dx, dy: delta.dy))
        case let .text(origin, string, fontSize):
            copy.kind = .text(origin: origin.offset(by: delta), string: string, fontSize: fontSize)
        case let .counter(center, number):
            copy.kind = .counter(center: center.offset(by: delta), number: number)
        }
        return copy
    }

    /// Arrow: distance from `p` to the segment must be ≤ tolerance. Rectangle outline tools (rectangle) hit near
    /// the border; filled/region tools (blur, highlight) and text/counter hit anywhere inside their bounds.
    func hitTest(_ p: CGPoint, tolerance: CGFloat) -> Bool {
        switch kind {
        case let .arrow(from, to):
            return Self.distance(from: p, toSegment: from, to) <= tolerance
        case let .rectangle(r):
            let standardized = r.standardized
            let outer = standardized.insetBy(dx: -tolerance, dy: -tolerance)
            guard outer.contains(p) else { return false }
            let inner = standardized.insetBy(dx: tolerance, dy: tolerance)
            return !inner.contains(p)
        case let .blur(r), let .highlight(r):
            return r.standardized.insetBy(dx: -tolerance, dy: -tolerance).contains(p)
        case .text, .counter:
            return bounds.insetBy(dx: -tolerance, dy: -tolerance).contains(p)
        }
    }

    private static func distance(from p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        if lengthSquared == 0 {
            return hypot(p.x - a.x, p.y - a.y)
        }
        var t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared
        t = max(0, min(1, t))
        let projX = a.x + t * dx
        let projY = a.y + t * dy
        return hypot(p.x - projX, p.y - projY)
    }
}

private extension CGPoint {
    func offset(by delta: CGVector) -> CGPoint {
        CGPoint(x: x + delta.dx, y: y + delta.dy)
    }
}

// MARK: - Document

/// All coordinates are IMAGE PIXELS, origin TOP-LEFT. `scale` is pixels per point (2 on Retina).
struct AnnotationDocument: Equatable {
    var pixelSize: CGSize
    var scale: CGFloat
    var marks: [Mark]
    var crop: CGRect?

    init(pixelSize: CGSize, scale: CGFloat) {
        self.pixelSize = pixelSize
        self.scale = scale
        self.marks = []
        self.crop = nil
    }

    /// Max existing counter number + 1; starts at 1 when there is no counter yet.
    var nextCounterNumber: Int {
        let numbers: [Int] = marks.compactMap {
            if case let .counter(_, number) = $0.kind { return number }
            return nil
        }
        return (numbers.max() ?? 0) + 1
    }

    mutating func add(_ m: Mark) {
        marks.append(m)
    }

    mutating func remove(id: UUID) {
        marks.removeAll { $0.id == id }
    }

    mutating func replace(_ m: Mark) {
        guard let index = marks.firstIndex(where: { $0.id == m.id }) else { return }
        marks[index] = m
    }

    /// Topmost hit (last-added mark wins ties), tolerance `8 * scale` pixels.
    func mark(at p: CGPoint) -> Mark? {
        let tolerance = 8 * scale
        for m in marks.reversed() where m.hitTest(p, tolerance: tolerance) {
            return m
        }
        return nil
    }

    var outputPixelSize: CGSize {
        if let crop {
            return crop.standardized.size
        }
        return pixelSize
    }
}

// MARK: - Undo stack

/// Undo/redo by snapshots, capped at 100 entries.
struct UndoStack<T: Equatable> {
    private static var cap: Int { 100 }
    private var past: [T] = []
    private var present: T
    private var future: [T] = []

    init(_ initial: T) {
        present = initial
    }

    var current: T { present }
    var canUndo: Bool { !past.isEmpty }
    var canRedo: Bool { !future.isEmpty }

    /// No-op if `next` equals the current value; otherwise pushes `present` onto the undo history and clears
    /// the redo history (a new branch invalidates any redo path).
    mutating func push(_ next: T) {
        guard next != present else { return }
        past.append(present)
        if past.count > Self.cap {
            past.removeFirst(past.count - Self.cap)
        }
        present = next
        future.removeAll()
    }

    mutating func undo() {
        guard let previous = past.popLast() else { return }
        future.append(present)
        present = previous
    }

    mutating func redo() {
        guard let next = future.popLast() else { return }
        past.append(present)
        present = next
    }
}

// MARK: - Renderer

enum AnnotationRenderer {
    /// Radius (image pixels at scale 1; the renderer scales it with the document) of a counter badge circle.
    static let counterRadius: CGFloat = 14

    /// Draws every mark onto `base`, then applies the document's crop (if any). Marks are drawn in array order
    /// (later marks on top). Returns nil if a CGContext could not be created.
    static func render(base: CGImage, document: AnnotationDocument) -> CGImage? {
        let width = base.width
        let height = base.height
        guard width > 0, height > 0 else { return nil }

        let colorSpace = base.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // `CGContext.draw(_:in:)` already places an image's row 0 at the top of the given rect in the
        // context's OWN (unflipped, bottom-left) space, so the base image must be drawn BEFORE flipping, or
        // it lands upside down relative to the buffer (measured: flipping first inverts every row). Every mark
        // below, by contrast, is a path/text draw, which flipping maps correctly onto image-pixel (top-left)
        // coordinates — so the flip happens once, after the base image, and stays in effect for every mark.
        context.interpolationQuality = .none
        context.draw(base, in: CGRect(x: 0, y: 0, width: width, height: height))

        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)

        for mark in document.marks {
            draw(mark, in: context, scale: document.scale, base: base)
        }

        guard let rendered = context.makeImage() else { return nil }

        guard let crop = document.crop else { return rendered }
        let pixelCrop = crop.standardized.intersection(CGRect(x: 0, y: 0, width: width, height: height))
        guard !pixelCrop.isEmpty else { return rendered }
        return rendered.cropping(to: pixelCrop) ?? rendered
    }

    private static func draw(_ mark: Mark, in context: CGContext, scale: CGFloat, base: CGImage) {
        let lineWidth = mark.width.points * scale
        let rgb = mark.color.rgb

        switch mark.kind {
        case let .arrow(from, to):
            context.setStrokeColor(red: rgb.r, green: rgb.g, blue: rgb.b, alpha: 1)
            context.setFillColor(red: rgb.r, green: rgb.g, blue: rgb.b, alpha: 1)
            context.setLineWidth(lineWidth)
            context.setLineCap(.round)
            context.move(to: from)
            context.addLine(to: to)
            context.strokePath()
            drawArrowHead(from: from, to: to, lineWidth: lineWidth, in: context)

        case let .rectangle(r):
            context.setStrokeColor(red: rgb.r, green: rgb.g, blue: rgb.b, alpha: 1)
            context.setLineWidth(lineWidth)
            context.stroke(r.standardized)

        case let .blur(r):
            pixelate(region: r.standardized, in: context, base: base)

        case let .highlight(r):
            // Yellow-ish, 40% alpha, multiply blend — darkens what is under it like a highlighter pen rather
            // than painting flat colour over it.
            context.saveGState()
            context.setBlendMode(.multiply)
            context.setFillColor(red: rgb.r, green: rgb.g, blue: rgb.b, alpha: 0.4)
            context.fill(r.standardized)
            context.restoreGState()

        case let .counter(center, number):
            let radius = counterRadius * scale
            context.setFillColor(red: rgb.r, green: rgb.g, blue: rgb.b, alpha: 1)
            let circle = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
            context.fillEllipse(in: circle)
            drawCenteredText(
                "\(number)",
                in: circle,
                color: (1, 1, 1),
                fontSize: radius,
                bold: true,
                context: context
            )

        case let .text(origin, string, fontSize):
            drawText(string, at: origin, fontSize: fontSize * scale, color: rgb, context: context)
        }
    }

    private static func drawArrowHead(from: CGPoint, to: CGPoint, lineWidth: CGFloat, in context: CGContext) {
        let angle = atan2(to.y - from.y, to.x - from.x)
        let headLength = max(lineWidth * 2.5, 10)
        let headAngle: CGFloat = .pi / 7
        let p1 = CGPoint(
            x: to.x - headLength * cos(angle - headAngle),
            y: to.y - headLength * sin(angle - headAngle)
        )
        let p2 = CGPoint(
            x: to.x - headLength * cos(angle + headAngle),
            y: to.y - headLength * sin(angle + headAngle)
        )
        context.beginPath()
        context.move(to: to)
        context.addLine(to: p1)
        context.addLine(to: p2)
        context.closePath()
        context.fillPath()
    }

    /// Pixelate the region: downscale to roughly 1/12 then scale back up with nearest-neighbour interpolation,
    /// so neighbouring pixels in the output become identical blocks (verified by the test suite).
    private static func pixelate(region: CGRect, in context: CGContext, base: CGImage) {
        let pixelRegion = region.integral.intersection(CGRect(x: 0, y: 0, width: base.width, height: base.height))
        guard !pixelRegion.isEmpty, pixelRegion.width >= 1, pixelRegion.height >= 1 else { return }
        guard let cropped = base.cropping(to: pixelRegion) else { return }

        let factor: CGFloat = 12
        let smallWidth = max(1, Int(pixelRegion.width / factor))
        let smallHeight = max(1, Int(pixelRegion.height / factor))

        let colorSpace = cropped.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        guard let smallContext = CGContext(
            data: nil,
            width: smallWidth,
            height: smallHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return }
        smallContext.interpolationQuality = .none
        smallContext.draw(cropped, in: CGRect(x: 0, y: 0, width: smallWidth, height: smallHeight))
        guard let smallImage = smallContext.makeImage() else { return }

        context.saveGState()
        context.interpolationQuality = .none
        // `context.draw(_:in:)` places an image's row 0 at the top of the rect in the CONTEXT'S OWN space —
        // since the outer context is already flipped to image-pixel (top-left) coordinates, drawing the patch
        // directly here would land it upside down (the same effect measured for the base image). Flip locally
        // around the region so the patch is un-inverted before landing back at its own top-left-origin rect.
        context.translateBy(x: 0, y: pixelRegion.minY * 2 + pixelRegion.height)
        context.scaleBy(x: 1, y: -1)
        context.draw(smallImage, in: pixelRegion)
        context.restoreGState()
    }

    private static func drawText(_ string: String, at origin: CGPoint, fontSize: CGFloat, color: (r: CGFloat, g: CGFloat, b: CGFloat), context: CGContext) {
        guard !string.isEmpty else { return }
        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, fontSize, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: CGColor(red: color.r, green: color.g, blue: color.b, alpha: 1),
        ]
        let attributed = NSAttributedString(string: string, attributes: attributes)
        let line = CTLineCreateWithAttributedString(attributed)
        let bounds = CTLineGetBoundsWithOptions(line, [])

        context.saveGState()
        // CoreText draws in a bottom-left-origin space even inside our flipped (top-left) context, so flip
        // locally around the text's own origin.
        context.textMatrix = .identity
        context.translateBy(x: origin.x, y: origin.y + bounds.height)
        context.scaleBy(x: 1, y: -1)
        context.textPosition = .zero
        CTLineDraw(line, context)
        context.restoreGState()
    }

    private static func drawCenteredText(_ string: String, in rect: CGRect, color: (r: CGFloat, g: CGFloat, b: CGFloat), fontSize: CGFloat, bold: Bool, context: CGContext) {
        guard !string.isEmpty else { return }
        let fontName = bold ? "Helvetica-Bold" : "Helvetica"
        let font = CTFontCreateWithName(fontName as CFString, fontSize, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: CGColor(red: color.r, green: color.g, blue: color.b, alpha: 1),
        ]
        let attributed = NSAttributedString(string: string, attributes: attributes)
        let line = CTLineCreateWithAttributedString(attributed)
        let bounds = CTLineGetBoundsWithOptions(line, [])

        let originX = rect.midX - bounds.width / 2
        let originY = rect.midY - bounds.height / 2

        context.saveGState()
        context.textMatrix = .identity
        context.translateBy(x: originX, y: originY + bounds.height)
        context.scaleBy(x: 1, y: -1)
        context.textPosition = .zero
        CTLineDraw(line, context)
        context.restoreGState()
    }

    /// Encodes `image` with the given UTType identifier, writing a DPI of `72 * scale` (so a Retina capture's
    /// physical size on screen stays accurate). Returns nil on failure.
    static func encode(_ image: CGImage, format: String, scale: CGFloat) -> Data? {
        guard let utType = UTType(format) else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, utType.identifier as CFString, 1, nil) else {
            return nil
        }
        let dpi = 72.0 * Double(scale)
        let properties: [CFString: Any] = [
            kCGImagePropertyDPIWidth: dpi,
            kCGImagePropertyDPIHeight: dpi,
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
