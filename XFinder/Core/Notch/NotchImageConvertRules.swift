import Foundation
import ImageIO
import Darwin

/// Pure rules and sequential off-MainActor batch runner for the Dynamic Island image converter.
///
/// Reuses `ImageEngine` (supported inputs, encoder-confirmed output formats, resize presets),
/// `ImageTransformRules` (EXIF-upright geometry, 100 MP source cap, 8192 px output cap, no-upscale
/// detection), and `ImageRunner` (atomic staging + `RENAME_EXCL` keep-both publication).
///
/// Never modifies or deletes source files, never deletes already-written outputs on cancel/close,
/// and never starts the next file once cancelled.
enum NotchImageConvertRules {

    static let maxBatchSize = 50
    static let defaultQuality: Double = 0.85
    static let minQuality: Double = 0.10
    static let maxQuality: Double = 1.00
    static let qualityPresets: [Double] = [0.60, 0.75, 0.85, 0.95, 1.00]
    static let maxEdgePresets: [Int] = ImageEngine.resizePresets
    /// Conservative headroom required above the source file size before starting an encode.
    static let minimumFreeSpaceHeadroomBytes: Int64 = 1_048_576

    // MARK: - Options & Encoder Filtering

    struct Settings: Equatable, Sendable {
        var format: ImageEngine.Target
        var quality: Double
        var maxLongestEdge: Int?

        init(format: ImageEngine.Target = .jpeg,
             quality: Double = NotchImageConvertRules.defaultQuality,
             maxLongestEdge: Int? = nil) {
            self.format = format
            self.quality = NotchImageConvertRules.clampedQuality(quality)
            self.maxLongestEdge = NotchImageConvertRules.validatedMaxLongestEdge(maxLongestEdge)
        }

        /// Quality is only meaningful for lossy encoders (JPEG, HEIC, AVIF); PNG/GIF/TIFF ignore it.
        var showsQualityControl: Bool { format.isLossy }
    }

    /// Formats confirmed encodable by `ImageEngine` on this Mac.
    static func availableFormats(encodable: [String]) -> [ImageEngine.Target] {
        ImageEngine.availableTargets(encodable: encodable)
    }

    /// Keeps `preferred` when encodable; otherwise falls back to the first encodable format (or nil).
    static func resolvedFormat(_ preferred: ImageEngine.Target, encodable: [String]) -> ImageEngine.Target? {
        let formats = availableFormats(encodable: encodable)
        if formats.contains(preferred) { return preferred }
        return formats.first
    }

    static func clampedQuality(_ value: Double) -> Double {
        guard value.isFinite else { return defaultQuality }
        return min(maxQuality, max(minQuality, value))
    }

    static func validatedMaxLongestEdge(_ value: Int?) -> Int? {
        guard let value else { return nil }
        guard (1...ImageTransformRules.maximumOutputDimension).contains(value) else { return nil }
        return value
    }

    /// Validates source geometry through `ImageTransformRules` and resolves the resize target.
    ///
    /// When the user sets an optional longest-edge cap and the image is already at or below that cap,
    /// `ImageTransformRules` marks `skipReason == .wouldUpscale`; we return `nil` so the format
    /// conversion still runs at original dimensions without upscaling.
    static func effectiveTransformTarget(sourceWidth: Int,
                                         sourceHeight: Int,
                                         orientation: Int,
                                         maxLongestEdge: Int?) throws -> ImageTransformRules.Target? {
        let requested = maxLongestEdge.map { ImageTransformRules.Target.longestEdge($0) }
        let plan = try ImageTransformRules.calculate(sourceWidth: sourceWidth,
                                                     sourceHeight: sourceHeight,
                                                     orientation: orientation,
                                                     crop: .full,
                                                     target: requested,
                                                     allowUpscale: false)
        if plan.skipReason == .wouldUpscale {
            return nil
        }
        return requested
    }

    // MARK: - Failures & Preflight

    enum ItemFailure: Error, Equatable, Sendable {
        case unsupportedFormat(String)
        case noEncoder(String)
        case unreadable(String)
        case tooLarge(String)
        case animatedUnsupported(String)
        case outOfSpace(String)
        case permissionDenied(String)
        case nameCollision(String)
        case staleSource(String)
        case writeFailed(String)
        case invalidTransform(String)

        var messageKey: String {
            switch self {
            case .unsupportedFormat: return "Định dạng ảnh không được hỗ trợ: "
            case .noEncoder: return "Máy này không ghi được định dạng: "
            case .unreadable: return "Không đọc được ảnh: "
            case .tooLarge: return "Ảnh vượt giới hạn kích thước xử lý: "
            case .animatedUnsupported: return "Ảnh động nhiều khung hình chưa được hỗ trợ; tệp gốc được giữ nguyên: "
            case .outOfSpace: return "Không đủ dung lượng trống để lưu: "
            case .permissionDenied: return "Không có quyền đọc hoặc ghi tệp: "
            case .nameCollision: return "Có quá nhiều tệp trùng tên trong thư mục: "
            case .staleSource: return "Ảnh đã thay đổi trước khi chuyển đổi: "
            case .writeFailed: return "Không ghi được ảnh: "
            case .invalidTransform: return "Không thể áp dụng thông số ảnh: "
            }
        }

        var detail: String {
            switch self {
            case .unsupportedFormat(let s),
                 .noEncoder(let s),
                 .unreadable(let s),
                 .tooLarge(let s),
                 .animatedUnsupported(let s),
                 .outOfSpace(let s),
                 .permissionDenied(let s),
                 .nameCollision(let s),
                 .staleSource(let s),
                 .writeFailed(let s),
                 .invalidTransform(let s):
                return s
            }
        }

        static let examples: [ItemFailure] = [
            .unsupportedFormat("a"),
            .noEncoder("a"),
            .unreadable("a"),
            .tooLarge("a"),
            .animatedUnsupported("a"),
            .outOfSpace("a"),
            .permissionDenied("a"),
            .nameCollision("a"),
            .staleSource("a"),
            .writeFailed("a"),
            .invalidTransform("a"),
        ]
    }

    struct DestinationAccess: Equatable, Sendable {
        let sourceExists: Bool
        let sourceReadable: Bool
        let directoryWritable: Bool
        let availableCapacityBytes: Int64?
        let sourceFileSizeBytes: Int64
    }

    static func preflight(source: URL, access: DestinationAccess) -> ItemFailure? {
        let name = source.lastPathComponent
        guard access.sourceExists else { return .unreadable(name) }
        guard access.sourceReadable, access.directoryWritable else { return .permissionDenied(name) }
        if let free = access.availableCapacityBytes {
            let required = max(minimumFreeSpaceHeadroomBytes, access.sourceFileSizeBytes)
            if free < required {
                return .outOfSpace(name)
            }
        }
        return nil
    }

    static func probeFileSystemAccess(_ source: URL) -> DestinationAccess {
        let fm = FileManager.default
        let path = source.path
        let dir = source.deletingLastPathComponent()
        let exists = fm.fileExists(atPath: path)
        let readable = exists && fm.isReadableFile(atPath: path)
        let writable = fm.isWritableFile(atPath: dir.path)
        let size = (try? fm.attributesOfItem(atPath: path)[.size] as? NSNumber)?.int64Value ?? 0
        let values = try? dir.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey,
                                                       .volumeAvailableCapacityKey])
        let capacity: Int64?
        if let important = values?.volumeAvailableCapacityForImportantUsage {
            capacity = important
        } else if let plain = values?.volumeAvailableCapacity {
            capacity = Int64(plain)
        } else {
            capacity = nil
        }
        return DestinationAccess(sourceExists: exists,
                                 sourceReadable: readable,
                                 directoryWritable: writable,
                                 availableCapacityBytes: capacity,
                                 sourceFileSizeBytes: size)
    }

    static func mapFailure(_ failure: ImageRunner.Failure,
                           sourceName: String,
                           posixError: Int32? = nil) -> ItemFailure {
        if let code = posixError {
            if code == ENOSPC { return .outOfSpace(sourceName) }
            if code == EACCES || code == EPERM || code == EROFS { return .permissionDenied(sourceName) }
        }
        switch failure {
        case .unreadable(let d): return .unreadable(d)
        case .noEncoder(let d): return .noEncoder(d)
        case .animatedUnsupported(let d): return .animatedUnsupported(d)
        case .staleSource(let d): return .staleSource(d)
        case .invalidTransform(let d): return .invalidTransform(d)
        case .writeFailed(let d):
            if d.contains("trùng tên") { return .nameCollision(sourceName) }
            return .writeFailed(d)
        case .noSubject(let d), .visionFailed(let d):
            return .invalidTransform(d)
        }
    }

    // MARK: - Queue & Batch State Machine

    enum ItemStatus: Equatable, Sendable {
        case pending
        case running
        case succeeded(output: URL)
        case failed(ItemFailure)
        case cancelled

        var outputURL: URL? {
            if case .succeeded(let url) = self { return url }
            return nil
        }
    }

    struct BatchItem: Identifiable, Equatable, Sendable {
        let source: URL
        let normalizedPath: String
        var status: ItemStatus = .pending

        var id: String { normalizedPath }
        var fileName: String { source.lastPathComponent }
    }

    struct IntakeResult: Equatable, Sendable {
        let acceptedCount: Int
        let skippedDuplicates: Int
        let skippedUnsupported: Int
        let droppedOverLimit: Int

        var hasWarnings: Bool { skippedDuplicates > 0 || skippedUnsupported > 0 || droppedOverLimit > 0 }
    }

    enum BatchPhase: Equatable, Sendable {
        case idle
        case running
        case finished
        case cancelled
    }

    struct BatchState: Equatable, Sendable {
        var items: [BatchItem] = []
        var phase: BatchPhase = .idle
        var currentIndex: Int? = nil

        var isRunning: Bool { phase == .running }
        var totalCount: Int { items.count }
        var succeededCount: Int {
            items.reduce(0) { count, item in
                if case .succeeded = item.status { return count + 1 }
                return count
            }
        }
        var failedCount: Int {
            items.reduce(0) { count, item in
                if case .failed = item.status { return count + 1 }
                return count
            }
        }
        var cancelledCount: Int {
            items.reduce(0) { count, item in
                if case .cancelled = item.status { return count + 1 }
                return count
            }
        }
        var finishedCount: Int { succeededCount + failedCount }
        var outputs: [URL] { items.compactMap(\.status.outputURL) }
        var remainingCapacity: Int { max(0, NotchImageConvertRules.maxBatchSize - items.count) }
        var canStart: Bool { !isRunning && !items.isEmpty }
        var fraction: Double {
            guard totalCount > 0 else { return 0 }
            return Double(finishedCount) / Double(totalCount)
        }

        /// Deduplicates by standardized path, filters unsupported formats/directories, and enforces the 50-file cap.
        mutating func enqueue(_ urls: [URL], isDirectory: (URL) -> Bool = { _ in false }) -> IntakeResult {
            guard !isRunning else {
                return IntakeResult(acceptedCount: 0, skippedDuplicates: 0, skippedUnsupported: 0, droppedOverLimit: 0)
            }
            var seen = Set(items.map(\.normalizedPath))
            var accepted = 0
            var duplicates = 0
            var unsupported = 0
            var overLimit = 0

            for raw in urls {
                let standardized = raw.standardizedFileURL
                if !standardized.isFileURL || isDirectory(standardized) || !ImageEngine.isImage(standardized) {
                    unsupported += 1
                    continue
                }
                let key = standardized.path
                if seen.contains(key) {
                    duplicates += 1
                    continue
                }
                if items.count >= NotchImageConvertRules.maxBatchSize {
                    overLimit += 1
                    continue
                }
                seen.insert(key)
                items.append(BatchItem(source: standardized, normalizedPath: key, status: .pending))
                accepted += 1
            }

            if accepted > 0 && phase != .idle {
                phase = .idle
                currentIndex = nil
            }
            return IntakeResult(acceptedCount: accepted,
                                skippedDuplicates: duplicates,
                                skippedUnsupported: unsupported,
                                droppedOverLimit: overLimit)
        }

        mutating func remove(id: String) {
            guard !isRunning else { return }
            items.removeAll { $0.id == id }
            if items.isEmpty {
                phase = .idle
                currentIndex = nil
            }
        }

        mutating func clear() {
            guard !isRunning else { return }
            items.removeAll()
            phase = .idle
            currentIndex = nil
        }

        /// Prepares a fresh sequential run. Existing output files on disk are never deleted.
        mutating func beginRun() -> [BatchItem] {
            guard !isRunning, !items.isEmpty else { return [] }
            for i in items.indices {
                items[i].status = .pending
            }
            phase = .running
            currentIndex = nil
            return items
        }

        mutating func markItemRunning(at index: Int) {
            guard phase == .running, items.indices.contains(index) else { return }
            currentIndex = index
            items[index].status = .running
        }

        /// Records the outcome of an item that already ran — even if cancel arrived mid-file, a written
        /// output is preserved in the item's status so the user can locate it in Finder.
        mutating func markItemFinished(at index: Int, result: Result<URL, ItemFailure>) {
            guard items.indices.contains(index) else { return }
            switch result {
            case .success(let output):
                items[index].status = .succeeded(output: output)
            case .failure(let failure):
                items[index].status = .failed(failure)
            }
            if currentIndex == index {
                currentIndex = nil
            }
        }

        /// Cancels the batch: prevents any unstarted item from running while keeping all completed results.
        mutating func cancel() {
            guard phase == .running else { return }
            phase = .cancelled
            currentIndex = nil
            for i in items.indices where items[i].status == .pending {
                items[i].status = .cancelled
            }
        }

        mutating func finishIfRunning() {
            guard phase == .running else { return }
            phase = .finished
            currentIndex = nil
        }
    }

    // MARK: - Single-File Conversion & Sequential Off-MainActor Runner

    /// Converts one image using `ImageEngine`, `ImageTransformRules`, and `ImageRunner`.
    /// Safe to invoke off the MainActor.
    nonisolated static func convertSingle(_ source: URL,
                                          settings: Settings,
                                          encodable: [String] = ImageRunner.encodableTypes,
                                          probeAccess: ((URL) -> DestinationAccess)? = nil) -> Result<URL, ItemFailure> {
        let name = source.lastPathComponent
        guard ImageEngine.isImage(source) else {
            return .failure(.unsupportedFormat(name))
        }
        guard availableFormats(encodable: encodable).contains(settings.format) else {
            return .failure(.noEncoder(settings.format.label))
        }
        let access = (probeAccess ?? probeFileSystemAccess)(source)
        if let preflightFailure = preflight(source: source, access: access) {
            return .failure(preflightFailure)
        }
        guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil) else {
            return .failure(.unreadable(name))
        }
        let frameCount = CGImageSourceGetCount(imageSource)
        guard frameCount > 0 else {
            return .failure(.unreadable(name))
        }
        guard frameCount == 1 else {
            return .failure(.animatedUnsupported(name))
        }
        guard let props = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int else {
            return .failure(.unreadable(name))
        }
        let orientation = props[kCGImagePropertyOrientation] as? Int ?? 1

        let target: ImageTransformRules.Target?
        do {
            target = try effectiveTransformTarget(sourceWidth: width,
                                                  sourceHeight: height,
                                                  orientation: orientation,
                                                  maxLongestEdge: settings.maxLongestEdge)
        } catch let err as ImageTransformRules.Failure {
            switch err {
            case .sourceTooLarge:
                return .failure(.tooLarge(name))
            case .invalidSourceDimensions, .invalidOrientation:
                return .failure(.unreadable(name))
            case .invalidCrop, .invalidTarget:
                return .failure(.invalidTransform(name))
            }
        } catch {
            return .failure(.invalidTransform(name))
        }

        let options = ImageRunner.TransformOptions(
            crop: .full,
            target: target,
            allowUpscale: false,
            format: settings.format,
            quality: clampedQuality(settings.quality),
            outputOperation: .convert(settings.format)
        )
        errno = 0
        let runnerResult = ImageRunner.transform(source, options: options)
        let capturedErrno = errno
        switch runnerResult {
        case .success(let output):
            return .success(output)
        case .failure(let failure):
            return .failure(mapFailure(failure, sourceName: name, posixError: capturedErrno == 0 ? nil : capturedErrno))
        }
    }

    /// Runs a batch sequentially off the MainActor. Checks `Task.isCancelled` and `shouldContinue()`
    /// before starting every file so cancelling immediately prevents the next file from starting.
    nonisolated static func runBatch(
        items: [BatchItem],
        settings: Settings,
        shouldContinue: @escaping @Sendable () -> Bool,
        onItemStarted: @escaping @Sendable (Int) async -> Void,
        onItemFinished: @escaping @Sendable (Int, Result<URL, ItemFailure>) async -> Void,
        converter: @escaping @Sendable (URL, Settings) -> Result<URL, ItemFailure> = { convertSingle($0, settings: $1) }
    ) async {
        for (index, item) in items.enumerated() {
            if Task.isCancelled || !shouldContinue() { break }
            await onItemStarted(index)
            if Task.isCancelled || !shouldContinue() { break }
            let result = converter(item.source, settings)
            await onItemFinished(index, result)
        }
    }
}
