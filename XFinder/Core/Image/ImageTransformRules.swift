import Foundation
import CoreGraphics

/// Pure geometry for every XFinder image output path. Coordinates are normalized from the
/// displayed (EXIF-upright) image with a top-left origin; callers must crop before resizing.
enum ImageTransformRules {
    static let maximumSourcePixels = 100_000_000
    static let maximumOutputDimension = 8_192

    enum Target: Equatable, Sendable, Codable {
        case longestEdge(Int)
        case width(Int)
        case height(Int)
        case fitInside(width: Int, height: Int)
    }

    struct NormalizedCrop: Equatable, Sendable, Codable {
        let x: Double
        let y: Double
        let width: Double
        let height: Double

        var isValid: Bool {
            x.isFinite && y.isFinite && width.isFinite && height.isFinite
                && x >= 0 && y >= 0 && width > 0 && height > 0
                && x + width <= 1 && y + height <= 1
        }

        static let full = NormalizedCrop(x: 0, y: 0, width: 1, height: 1)
    }

    /// Pixel rectangle in the upright image, still expressed from the top-left.
    struct PixelRect: Equatable, Sendable {
        let x: Int
        let y: Int
        let width: Int
        let height: Int
    }

    enum SkipReason: Equatable, Sendable {
        case wouldUpscale
    }

    enum Failure: Error, Equatable, Sendable {
        case invalidSourceDimensions
        case sourceTooLarge
        case invalidOrientation
        case invalidCrop
        case invalidTarget
    }

    struct Plan: Equatable, Sendable {
        let sourceWidth: Int
        let sourceHeight: Int
        let orientation: Int
        let uprightWidth: Int
        let uprightHeight: Int
        let crop: NormalizedCrop
        let cropPixels: PixelRect
        let outputWidth: Int
        let outputHeight: Int
        let scale: Double
        let skipReason: SkipReason?
    }

    static func uprightDimensions(width: Int, height: Int, orientation: Int) throws -> (width: Int, height: Int) {
        guard width > 0, height > 0 else { throw Failure.invalidSourceDimensions }
        guard (1...8).contains(orientation) else { throw Failure.invalidOrientation }
        guard width <= maximumSourcePixels / height else { throw Failure.sourceTooLarge }
        return (orientation >= 5 ? height : width, orientation >= 5 ? width : height)
    }

    static func calculate(sourceWidth: Int, sourceHeight: Int, orientation: Int,
                          crop requestedCrop: NormalizedCrop? = nil,
                          target: Target? = nil, allowUpscale: Bool = false) throws -> Plan {
        let upright = try uprightDimensions(width: sourceWidth, height: sourceHeight, orientation: orientation)
        let crop = requestedCrop ?? .full
        guard crop.isValid else { throw Failure.invalidCrop }

        let x0 = min(upright.width - 1, Int(floor(crop.x * Double(upright.width))))
        let y0 = min(upright.height - 1, Int(floor(crop.y * Double(upright.height))))
        let x1 = min(upright.width, Int(ceil((crop.x + crop.width) * Double(upright.width))))
        let y1 = min(upright.height, Int(ceil((crop.y + crop.height) * Double(upright.height))))
        let cropPixels = PixelRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
        guard cropPixels.width > 0, cropPixels.height > 0 else { throw Failure.invalidCrop }

        let desiredScale: Double
        switch target {
        case nil:
            desiredScale = 1
        case .longestEdge(let edge):
            guard validLimit(edge) else { throw Failure.invalidTarget }
            desiredScale = Double(edge) / Double(max(cropPixels.width, cropPixels.height))
        case .width(let width):
            guard validLimit(width) else { throw Failure.invalidTarget }
            desiredScale = Double(width) / Double(cropPixels.width)
        case .height(let height):
            guard validLimit(height) else { throw Failure.invalidTarget }
            desiredScale = Double(height) / Double(cropPixels.height)
        case .fitInside(let width, let height):
            guard validLimit(width), validLimit(height) else { throw Failure.invalidTarget }
            desiredScale = min(Double(width) / Double(cropPixels.width), Double(height) / Double(cropPixels.height))
        }
        guard desiredScale.isFinite, desiredScale > 0 else { throw Failure.invalidTarget }
        let skipped = !allowUpscale && desiredScale > 1 ? SkipReason.wouldUpscale : nil
        let scale = skipped == nil ? desiredScale : 1
        let outputWidth = max(1, Int((Double(cropPixels.width) * scale).rounded()))
        let outputHeight = max(1, Int((Double(cropPixels.height) * scale).rounded()))
        guard outputWidth <= maximumOutputDimension, outputHeight <= maximumOutputDimension,
              outputWidth <= maximumSourcePixels / outputHeight else { throw Failure.invalidTarget }

        return Plan(sourceWidth: sourceWidth, sourceHeight: sourceHeight, orientation: orientation,
                    uprightWidth: upright.width, uprightHeight: upright.height, crop: crop,
                    cropPixels: cropPixels, outputWidth: outputWidth, outputHeight: outputHeight,
                    scale: scale, skipReason: skipped)
    }

    private static func validLimit(_ value: Int) -> Bool { (1...maximumOutputDimension).contains(value) }
}
