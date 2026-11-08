import Foundation
import Darwin

/// Small on-disk child protocol. Image bytes never cross into the UI process.
enum InspectorImageRules {
    static let byteLimit = 100 * 1024 * 1024
    static let pixelLimit = 100_000_000
    enum Operation: String, Codable, CaseIterable, Sendable { case png, jpeg, webp, resize, flipHorizontal, flipVertical }
    struct Request: Codable, Sendable {
        let id: UUID
        let source: String
        let expectedIdentity: String
        let operation: Operation
        let maxPixels: Int?
        let target: ImageTransformRules.Target?
        let format: ImageEngine.Target?
        let crop: ImageTransformRules.NormalizedCrop
        let quality: Double
        let allowUpscale: Bool
        init(source: String, expectedIdentity: String, operation: Operation, maxPixels: Int?,
             crop: ImageTransformRules.NormalizedCrop = .full, quality: Double = 0.85,
             allowUpscale: Bool = false, target: ImageTransformRules.Target? = nil,
             format: ImageEngine.Target? = nil, id: UUID = UUID()) {
            self.id = id
            self.source = source
            self.expectedIdentity = expectedIdentity
            self.operation = operation
            self.maxPixels = maxPixels
            self.target = target
            self.format = format
            self.crop = crop
            self.quality = quality
            self.allowUpscale = allowUpscale
        }
        var stagingURL: URL {
            URL(fileURLWithPath: source).deletingLastPathComponent().appendingPathComponent(".xfinder-image-" + id.uuidString + ".tmp")
        }
        var isValid: Bool {
            source.hasPrefix("/") && !expectedIdentity.isEmpty && crop.isValid && quality.isFinite && (0...1).contains(quality)
                && (operation != .resize || (maxPixels.map { (1...8192).contains($0) } ?? false))
                && (target.map { target in
                    switch target {
                    case .longestEdge(let n), .width(let n), .height(let n): return (1...8192).contains(n)
                    case .fitInside(let w, let h): return (1...8192).contains(w) && (1...8192).contains(h)
                    }
                } ?? true)
        }
    }
    struct Reply: Codable, Sendable {
        let output: String?
        let errorKey: String?
    }
    static func identity(path: String, info: stat) -> String {
        "\(path)@\(info.st_dev):\(info.st_ino):\(info.st_size):\(info.st_mtimespec.tv_sec):\(info.st_mtimespec.tv_nsec):\(info.st_ctimespec.tv_sec):\(info.st_ctimespec.tv_nsec)"
    }
    static func outputName(source: URL, operation: Operation, maxPixels: Int?, attempt: Int) -> String {
        outputName(source: source, operation: operation, maxPixels: maxPixels, format: nil, attempt: attempt)
    }
    static func outputName(source: URL, operation: Operation, maxPixels: Int?, format: ImageEngine.Target?, attempt: Int) -> String {
        let suffix: String
        switch operation {
        case .png, .jpeg, .webp: suffix = ""
        case .resize: suffix = "-\(maxPixels ?? 0)px"
        case .flipHorizontal: suffix = "-flip-h"
        case .flipVertical: suffix = "-flip-v"
        }
        let ext = format?.fileExtension ?? (operation == .jpeg ? "jpg" : (operation == .webp ? "webp" : "png"))
        let number = attempt == 0 ? "" : " (\(attempt + 1))"
        return source.deletingPathExtension().lastPathComponent + suffix + number + "." + ext
    }
}
