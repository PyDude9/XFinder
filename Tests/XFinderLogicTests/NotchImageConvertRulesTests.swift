import XCTest
import Foundation
import ImageIO
import CoreGraphics
import Darwin
import os

final class NotchImageConvertRulesTests: XCTestCase {
    typealias R = NotchImageConvertRules

    var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("xf-notch-img-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path)
        try? FileManager.default.removeItem(at: dir)
    }

    private func makeImage(_ name: String,
                           type: String,
                           width: Int = 400,
                           height: Int = 300,
                           orientation: Int = 1) -> URL {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.15, green: 0.45, blue: 0.85, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let url = dir.appendingPathComponent(name)
        let dest = CGImageDestinationCreateWithURL(url as CFURL, type as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, [kCGImagePropertyOrientation: orientation] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return url
    }

    private func props(_ u: URL) -> [CFString: Any] {
        CGImageSourceCreateWithURL(u as CFURL, nil)
            .flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [CFString: Any] } ?? [:]
    }

    // MARK: - Queue intake: 50-file cap, duplicates, unsupported formats

    func testEnqueueEnforcesMax50Cap() {
        var state = R.BatchState()
        let urls = (1...60).map { URL(fileURLWithPath: "/tmp/img_\($0).png") }
        let res = state.enqueue(urls)
        XCTAssertEqual(res.acceptedCount, 50)
        XCTAssertEqual(res.droppedOverLimit, 10)
        XCTAssertEqual(res.skippedDuplicates, 0)
        XCTAssertEqual(res.skippedUnsupported, 0)
        XCTAssertEqual(state.totalCount, 50)
        XCTAssertEqual(state.remainingCapacity, 0)

        let extra = state.enqueue([URL(fileURLWithPath: "/tmp/img_61.png")])
        XCTAssertEqual(extra.acceptedCount, 0)
        XCTAssertEqual(extra.droppedOverLimit, 1)
    }

    func testEnqueueDeduplicatesWithinBatchAcrossBatchesAndStandardizedPaths() {
        var state = R.BatchState()
        let a = URL(fileURLWithPath: "/tmp/folder/a.jpg")
        let aUnstandardized = URL(fileURLWithPath: "/tmp/folder/../folder/a.jpg")
        let b = URL(fileURLWithPath: "/tmp/folder/b.heic")

        let r1 = state.enqueue([a, aUnstandardized, b])
        XCTAssertEqual(r1.acceptedCount, 2)
        XCTAssertEqual(r1.skippedDuplicates, 1)

        let r2 = state.enqueue([a, b])
        XCTAssertEqual(r2.acceptedCount, 0)
        XCTAssertEqual(r2.skippedDuplicates, 2)
        XCTAssertEqual(state.totalCount, 2)
    }

    func testEnqueueRejectsUnsupportedFormatsAndDirectories() {
        var state = R.BatchState()
        let folder = URL(fileURLWithPath: "/tmp/photos.png") // masquerading directory
        let inputs = [
            URL(fileURLWithPath: "/tmp/doc.pdf"),
            URL(fileURLWithPath: "/tmp/raw.cr2"),
            URL(fileURLWithPath: "/tmp/note.txt"),
            folder,
            URL(fileURLWithPath: "/tmp/valid.HEIC"),
        ]
        let res = state.enqueue(inputs, isDirectory: { $0.path == folder.path })
        XCTAssertEqual(res.acceptedCount, 1)
        XCTAssertEqual(res.skippedUnsupported, 4)
        XCTAssertEqual(state.items.map(\.fileName), ["valid.HEIC"])
    }

    // MARK: - Encoder filtering, quality, and longest-edge rules

    func testOnlyEncoderConfirmedFormatsAreOffered() {
        let formats = R.availableFormats(encodable: ["public.png", "public.heic", "org.webmproject.webp"])
        XCTAssertEqual(formats, [.png, .heic])
        XCTAssertEqual(R.resolvedFormat(.jpeg, encodable: ["public.png", "public.heic"]), .png)
        XCTAssertEqual(R.resolvedFormat(.heic, encodable: ["public.png", "public.heic"]), .heic)
        XCTAssertNil(R.resolvedFormat(.jpeg, encodable: []))
    }

    func testQualityControlShownOnlyForLossyFormatsAndClamped() {
        XCTAssertTrue(R.Settings(format: .jpeg).showsQualityControl)
        XCTAssertTrue(R.Settings(format: .heic).showsQualityControl)
        XCTAssertTrue(R.Settings(format: .avif).showsQualityControl)
        XCTAssertFalse(R.Settings(format: .png).showsQualityControl)
        XCTAssertFalse(R.Settings(format: .gif).showsQualityControl)
        XCTAssertFalse(R.Settings(format: .tiff).showsQualityControl)

        XCTAssertEqual(R.clampedQuality(-0.5), R.minQuality)
        XCTAssertEqual(R.clampedQuality(2.5), R.maxQuality)
        XCTAssertEqual(R.clampedQuality(.nan), R.defaultQuality)
        XCTAssertEqual(R.clampedQuality(.infinity), R.defaultQuality)
    }

    func testEffectiveTransformTargetUsesImageTransformRulesAndAvoidsUpscale() throws {
        // Larger than cap -> shrinks
        let shrink = try R.effectiveTransformTarget(sourceWidth: 4000, sourceHeight: 3000, orientation: 1, maxLongestEdge: 1600)
        XCTAssertEqual(shrink, .longestEdge(1600))

        // Smaller than cap -> nil target (still converts format without upscaling)
        let noUpscale = try R.effectiveTransformTarget(sourceWidth: 800, sourceHeight: 600, orientation: 6, maxLongestEdge: 2048)
        XCTAssertNil(noUpscale)

        // Over 100 MP -> throws sourceTooLarge before decode
        XCTAssertThrowsError(try R.effectiveTransformTarget(sourceWidth: 12_000, sourceHeight: 10_000, orientation: 1, maxLongestEdge: 1600)) { error in
            XCTAssertEqual(error as? ImageTransformRules.Failure, .sourceTooLarge)
        }

        // Invalid edge limits rejected
        XCTAssertNil(R.validatedMaxLongestEdge(0))
        XCTAssertNil(R.validatedMaxLongestEdge(-100))
        XCTAssertNil(R.validatedMaxLongestEdge(ImageTransformRules.maximumOutputDimension + 1))
        XCTAssertEqual(R.validatedMaxLongestEdge(1600), 1600)
    }

    // MARK: - Preflight & Failure Mapping (disk full, permissions, collisions)

    func testPreflightCatchesOutOfSpaceAndPermissionDenied() {
        let file = URL(fileURLWithPath: "/tmp/photo.jpg")
        let noSpace = R.DestinationAccess(sourceExists: true, sourceReadable: true, directoryWritable: true,
                                          availableCapacityBytes: 512_000, sourceFileSizeBytes: 200_000)
        XCTAssertEqual(R.preflight(source: file, access: noSpace), .outOfSpace("photo.jpg"))

        let noRead = R.DestinationAccess(sourceExists: true, sourceReadable: false, directoryWritable: true,
                                         availableCapacityBytes: 100_000_000, sourceFileSizeBytes: 200_000)
        XCTAssertEqual(R.preflight(source: file, access: noRead), .permissionDenied("photo.jpg"))

        let noWrite = R.DestinationAccess(sourceExists: true, sourceReadable: true, directoryWritable: false,
                                          availableCapacityBytes: 100_000_000, sourceFileSizeBytes: 200_000)
        XCTAssertEqual(R.preflight(source: file, access: noWrite), .permissionDenied("photo.jpg"))

        let ok = R.DestinationAccess(sourceExists: true, sourceReadable: true, directoryWritable: true,
                                     availableCapacityBytes: 50_000_000, sourceFileSizeBytes: 200_000)
        XCTAssertNil(R.preflight(source: file, access: ok))
    }

    func testFailureMappingCoversPosixAndCollision() {
        XCTAssertEqual(R.mapFailure(.writeFailed("x"), sourceName: "a.jpg", posixError: ENOSPC), .outOfSpace("a.jpg"))
        XCTAssertEqual(R.mapFailure(.writeFailed("x"), sourceName: "a.jpg", posixError: EACCES), .permissionDenied("a.jpg"))
        XCTAssertEqual(R.mapFailure(.writeFailed("x"), sourceName: "a.jpg", posixError: EROFS), .permissionDenied("a.jpg"))
        XCTAssertEqual(R.mapFailure(.writeFailed("Có quá nhiều tệp trùng tên trong thư mục."), sourceName: "a.jpg"),
                       .nameCollision("a.jpg"))
    }

    // MARK: - Real ImageIO Integration Tests

    func testConvertWithOptionalMaxEdgeBakesOrientationAndKeepsSource() throws {
        let src = makeImage("portrait.heic", type: "public.heic", width: 800, height: 600, orientation: 6)
        let originalBytes = try Data(contentsOf: src)
        let settings = R.Settings(format: .jpeg, quality: 0.80, maxLongestEdge: 400)
        guard case .success(let out) = R.convertSingle(src, settings: settings) else {
            return XCTFail("Expected conversion to succeed")
        }
        XCTAssertEqual(out.lastPathComponent, "portrait.jpg")
        let p = props(out)
        XCTAssertEqual(p[kCGImagePropertyPixelWidth] as? Int, 300)
        XCTAssertEqual(p[kCGImagePropertyPixelHeight] as? Int, 400)
        XCTAssertEqual(p[kCGImagePropertyOrientation] as? Int ?? 1, 1)
        XCTAssertEqual(try Data(contentsOf: src), originalBytes)
    }

    func testConvertSmallerThanMaxEdgeStillConvertsWithoutUpscaling() throws {
        let src = makeImage("small.png", type: "public.png", width: 320, height: 240, orientation: 1)
        let settings = R.Settings(format: .jpeg, quality: 0.85, maxLongestEdge: 1600)
        guard case .success(let out) = R.convertSingle(src, settings: settings) else {
            return XCTFail("Expected conversion without upscale to succeed")
        }
        let p = props(out)
        XCTAssertEqual(p[kCGImagePropertyPixelWidth] as? Int, 320)
        XCTAssertEqual(p[kCGImagePropertyPixelHeight] as? Int, 240)
    }

    func testNameCollisionUsesKeepBothAndNeverOverwritesExistingOrSource() throws {
        let src = makeImage("clash.jpg", type: "public.jpeg")
        let existingPng = makeImage("clash.png", type: "public.png")
        let srcBytes = try Data(contentsOf: src)
        let existingBytes = try Data(contentsOf: existingPng)

        guard case .success(let outPng) = R.convertSingle(src, settings: R.Settings(format: .png)) else {
            return XCTFail("Expected keep-both PNG output")
        }
        XCTAssertEqual(outPng.lastPathComponent, "clash (2).png")
        XCTAssertEqual(try Data(contentsOf: existingPng), existingBytes)
        XCTAssertEqual(try Data(contentsOf: src), srcBytes)

        // Same-format conversion must never overwrite source
        guard case .success(let outJpg) = R.convertSingle(src, settings: R.Settings(format: .jpeg, quality: 0.7)) else {
            return XCTFail("Expected keep-both JPEG output")
        }
        XCTAssertEqual(outJpg.lastPathComponent, "clash (2).jpg")
        XCTAssertEqual(try Data(contentsOf: src), srcBytes)
    }

    func testCorruptAnimatedUnsupportedNoEncoderOutOfSpaceAndPermissionDeniedWriteNothing() throws {
        // Corrupt file
        let junk = dir.appendingPathComponent("corrupt.jpg")
        try Data("not-an-image".utf8).write(to: junk)
        XCTAssertEqual(R.convertSingle(junk, settings: R.Settings(format: .png)), .failure(.unreadable("corrupt.jpg")))

        // Unsupported extension
        let pdf = dir.appendingPathComponent("doc.pdf")
        try Data("%PDF-1.4".utf8).write(to: pdf)
        XCTAssertEqual(R.convertSingle(pdf, settings: R.Settings(format: .png)), .failure(.unsupportedFormat("doc.pdf")))

        // Valid image with unavailable encoder
        let valid = makeImage("ok.png", type: "public.png")
        XCTAssertEqual(R.convertSingle(valid, settings: R.Settings(format: .avif), encodable: ["public.jpeg"]),
                       .failure(.noEncoder("AVIF")))

        // Out of space via preflight
        let fullDisk = R.DestinationAccess(sourceExists: true, sourceReadable: true, directoryWritable: true,
                                           availableCapacityBytes: 100, sourceFileSizeBytes: 4096)
        XCTAssertEqual(R.convertSingle(valid, settings: R.Settings(format: .jpeg), probeAccess: { _ in fullDisk }),
                       .failure(.outOfSpace("ok.png")))

        // Multi-frame animated GIF
        let f1 = makeImage("f1.png", type: "public.png")
        let f2 = makeImage("f2.png", type: "public.png")
        let gif = dir.appendingPathComponent("anim.gif")
        let d = CGImageDestinationCreateWithURL(gif as CFURL, "com.compuserve.gif" as CFString, 2, nil)!
        let img1 = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(f1 as CFURL, nil)!, 0, nil)!
        let img2 = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(f2 as CFURL, nil)!, 0, nil)!
        CGImageDestinationAddImage(d, img1, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.1]] as CFDictionary)
        CGImageDestinationAddImage(d, img2, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.1]] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(d))
        XCTAssertEqual(R.convertSingle(gif, settings: R.Settings(format: .png)), .failure(.animatedUnsupported("anim.gif")))

        // Real read-only directory permission denied (only effective when not running as root)
        if geteuid() != 0 {
            let lockedDir = dir.appendingPathComponent("readonly")
            try FileManager.default.createDirectory(at: lockedDir, withIntermediateDirectories: true)
            let inside = lockedDir.appendingPathComponent("locked.png")
            try FileManager.default.copyItem(at: valid, to: inside)
            try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: lockedDir.path)
            defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: lockedDir.path) }

            XCTAssertEqual(R.convertSingle(inside, settings: R.Settings(format: .jpeg)),
                           .failure(.permissionDenied("locked.png")))
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: lockedDir.path), ["locked.png"])
        }
    }

    // MARK: - Sequential Off-MainActor Execution, Cancel & Close Mid-Batch

    func testCancelMidBatchPreventsStartingNextFileAndKeepsWrittenOutputs() async throws {
        let img1 = makeImage("one.png", type: "public.png")
        let img2 = makeImage("two.png", type: "public.png")
        let img3 = makeImage("three.png", type: "public.png")
        let orig1 = try Data(contentsOf: img1)
        let orig2 = try Data(contentsOf: img2)
        let orig3 = try Data(contentsOf: img3)

        var state = R.BatchState()
        _ = state.enqueue([img1, img2, img3])
        let snapshot = state.beginRun()

        actor Recorder {
            var started: [Int] = []
            var offMainChecks: [Bool] = []
            var cancelled = false
            func markStarted(_ idx: Int, offMain: Bool) {
                started.append(idx)
                offMainChecks.append(offMain)
            }
            func setCancelled() { cancelled = true }
            func isCancelled() -> Bool { cancelled }
        }
        let recorder = Recorder()
        let flag = AtomicCancel()

        await Task.detached(priority: .userInitiated) {
            await R.runBatch(
                items: snapshot,
                settings: R.Settings(format: .jpeg),
                shouldContinue: { !flag.isCancelled },
                onItemStarted: { idx in
                    await recorder.markStarted(idx, offMain: !Thread.isMainThread)
                },
                onItemFinished: { idx, result in
                    if idx == 0 {
                        // Simulate user clicking Cancel or closing the notch right after file 0 finishes
                        flag.cancel()
                        await recorder.setCancelled()
                    }
                    // Record into local assertion via state after batch
                    _ = result
                },
                converter: { url, settings in
                    R.convertSingle(url, settings: settings)
                }
            )
        }.value

        let started = await recorder.started
        let offMain = await recorder.offMainChecks
        XCTAssertEqual(started, [0], "Cancelling after item 0 must prevent item 1 and item 2 from starting")
        XCTAssertEqual(offMain, [true], "Batch loop must run off MainActor")

        // Verify item 0 output exists on disk, item 1 & 2 outputs were never created, and all sources are untouched
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("one.jpg").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("two.jpg").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("three.jpg").path))
        XCTAssertEqual(try Data(contentsOf: img1), orig1)
        XCTAssertEqual(try Data(contentsOf: img2), orig2)
        XCTAssertEqual(try Data(contentsOf: img3), orig3)
    }

    func testBatchStateCancelAndClosePreservesCompletedResults() {
        var state = R.BatchState()
        let u1 = URL(fileURLWithPath: "/tmp/a.png")
        let u2 = URL(fileURLWithPath: "/tmp/b.png")
        let u3 = URL(fileURLWithPath: "/tmp/c.png")
        let out1 = URL(fileURLWithPath: "/tmp/a.jpg")
        _ = state.enqueue([u1, u2, u3])
        _ = state.beginRun()

        state.markItemRunning(at: 0)
        state.markItemFinished(at: 0, result: .success(out1))
        state.markItemRunning(at: 1)

        // Close/cancel while item 1 is in-flight and item 2 is pending
        state.cancel()
        XCTAssertEqual(state.phase, .cancelled)
        XCTAssertEqual(state.items[0].status, .succeeded(output: out1))
        XCTAssertEqual(state.items[2].status, .cancelled)
        XCTAssertEqual(state.outputs, [out1])

        // If in-flight item 1 finishes writing its output, that written file is still preserved in state
        let out2 = URL(fileURLWithPath: "/tmp/b.jpg")
        state.markItemFinished(at: 1, result: .success(out2))
        XCTAssertEqual(state.items[1].status, .succeeded(output: out2))
        XCTAssertEqual(state.outputs, [out1, out2])
        XCTAssertEqual(state.cancelledCount, 1)
    }
}

private final class AtomicCancel: Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: false)
    var isCancelled: Bool { lock.withLock { $0 } }
    func cancel() { lock.withLock { $0 = true } }
}
