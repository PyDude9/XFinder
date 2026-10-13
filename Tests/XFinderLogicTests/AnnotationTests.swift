import XCTest
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

final class AnnotationTests: XCTestCase {

    // MARK: - nextCounterNumber

    func testNextCounterNumberStartsAtOne() {
        let doc = AnnotationDocument(pixelSize: CGSize(width: 100, height: 100), scale: 1)
        XCTAssertEqual(doc.nextCounterNumber, 1)
    }

    func testNextCounterNumberIncrementsFromMax() {
        var doc = AnnotationDocument(pixelSize: CGSize(width: 100, height: 100), scale: 1)
        doc.add(Mark(kind: .counter(center: CGPoint(x: 10, y: 10), number: 1), color: .red, width: .medium))
        doc.add(Mark(kind: .counter(center: CGPoint(x: 20, y: 20), number: 3), color: .red, width: .medium))
        XCTAssertEqual(doc.nextCounterNumber, 4)
    }

    func testNextCounterNumberIgnoresOtherMarkKinds() {
        var doc = AnnotationDocument(pixelSize: CGSize(width: 100, height: 100), scale: 1)
        doc.add(Mark(kind: .arrow(from: .zero, to: CGPoint(x: 5, y: 5)), color: .red, width: .medium))
        XCTAssertEqual(doc.nextCounterNumber, 1)
    }

    // MARK: - hitTest: arrow distance

    func testArrowHitTestOnSegment() {
        let mark = Mark(kind: .arrow(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 0)), color: .red, width: .medium)
        XCTAssertTrue(mark.hitTest(CGPoint(x: 50, y: 0), tolerance: 5))
    }

    func testArrowHitTestWithinTolerance() {
        let mark = Mark(kind: .arrow(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 0)), color: .red, width: .medium)
        XCTAssertTrue(mark.hitTest(CGPoint(x: 50, y: 4), tolerance: 5))
    }

    func testArrowHitTestBeyondTolerance() {
        let mark = Mark(kind: .arrow(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 0)), color: .red, width: .medium)
        XCTAssertFalse(mark.hitTest(CGPoint(x: 50, y: 20), tolerance: 5))
    }

    func testArrowHitTestBeyondSegmentEndpoint() {
        // A point past the endpoint, even if "close" diagonally, must measure distance to the nearest endpoint.
        let mark = Mark(kind: .arrow(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 0)), color: .red, width: .medium)
        XCTAssertFalse(mark.hitTest(CGPoint(x: 120, y: 0), tolerance: 5))
        XCTAssertTrue(mark.hitTest(CGPoint(x: 104, y: 0), tolerance: 5))
    }

    func testArrowHitTestDegenerateZeroLength() {
        // A zero-length "arrow" (from == to) must not crash (division by zero in the projection math).
        let mark = Mark(kind: .arrow(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 10, y: 10)), color: .red, width: .medium)
        XCTAssertTrue(mark.hitTest(CGPoint(x: 10, y: 10), tolerance: 5))
        XCTAssertFalse(mark.hitTest(CGPoint(x: 100, y: 100), tolerance: 5))
    }

    // MARK: - hitTest: rectangle border vs. filled regions

    func testRectangleHitTestNearBorderOnly() {
        let r = CGRect(x: 0, y: 0, width: 100, height: 100)
        let mark = Mark(kind: .rectangle(r), color: .red, width: .medium)
        XCTAssertTrue(mark.hitTest(CGPoint(x: 0, y: 50), tolerance: 5))   // on the border
        XCTAssertFalse(mark.hitTest(CGPoint(x: 50, y: 50), tolerance: 5)) // deep inside — outline only
    }

    func testBlurAndHighlightHitTestAnywhereInside() {
        let r = CGRect(x: 0, y: 0, width: 100, height: 100)
        let blur = Mark(kind: .blur(r), color: .red, width: .medium)
        let highlight = Mark(kind: .highlight(r), color: .yellow, width: .medium)
        XCTAssertTrue(blur.hitTest(CGPoint(x: 50, y: 50), tolerance: 5))
        XCTAssertTrue(highlight.hitTest(CGPoint(x: 50, y: 50), tolerance: 5))
    }

    func testTextAndCounterHitTestAnywhereInBounds() {
        let text = Mark(kind: .text(origin: CGPoint(x: 0, y: 0), string: "Hello", fontSize: 20), color: .black, width: .medium)
        XCTAssertTrue(text.hitTest(CGPoint(x: 5, y: 5), tolerance: 2))

        let counter = Mark(kind: .counter(center: CGPoint(x: 50, y: 50), number: 1), color: .red, width: .medium)
        XCTAssertTrue(counter.hitTest(CGPoint(x: 50, y: 50), tolerance: 2))
    }

    // MARK: - mark(at:) topmost

    func testMarkAtReturnsTopmostOnOverlap() {
        var doc = AnnotationDocument(pixelSize: CGSize(width: 200, height: 200), scale: 1)
        let bottom = Mark(kind: .rectangle(CGRect(x: 0, y: 0, width: 100, height: 100)), color: .red, width: .medium)
        let top = Mark(kind: .blur(CGRect(x: 0, y: 0, width: 100, height: 100)), color: .blue, width: .medium)
        doc.add(bottom)
        doc.add(top)
        let hit = doc.mark(at: CGPoint(x: 50, y: 50))
        XCTAssertEqual(hit?.id, top.id)
    }

    func testMarkAtReturnsNilWhenNoHit() {
        var doc = AnnotationDocument(pixelSize: CGSize(width: 200, height: 200), scale: 1)
        doc.add(Mark(kind: .rectangle(CGRect(x: 0, y: 0, width: 10, height: 10)), color: .red, width: .medium))
        XCTAssertNil(doc.mark(at: CGPoint(x: 190, y: 190)))
    }

    func testMarkAtUsesScaleForTolerance() {
        // At scale 2, tolerance is 16 (8 * 2), so a point 10px from a thin rectangle border should hit.
        var doc = AnnotationDocument(pixelSize: CGSize(width: 200, height: 200), scale: 2)
        let r = CGRect(x: 50, y: 50, width: 50, height: 50)
        doc.add(Mark(kind: .rectangle(r), color: .red, width: .thin))
        XCTAssertNotNil(doc.mark(at: CGPoint(x: 50, y: 60))) // on border
        XCTAssertNotNil(doc.mark(at: CGPoint(x: 40, y: 60))) // 10px outside, within scaled tolerance of 16
    }

    // MARK: - moved(by:)

    func testMovedByTranslatesArrow() {
        let mark = Mark(kind: .arrow(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 10, y: 10)), color: .red, width: .medium)
        let moved = mark.moved(by: CGVector(dx: 5, dy: -5))
        guard case let .arrow(from, to) = moved.kind else { return XCTFail() }
        XCTAssertEqual(from, CGPoint(x: 5, y: -5))
        XCTAssertEqual(to, CGPoint(x: 15, y: 5))
    }

    func testMovedByTranslatesRectangle() {
        let mark = Mark(kind: .rectangle(CGRect(x: 0, y: 0, width: 10, height: 10)), color: .red, width: .medium)
        let moved = mark.moved(by: CGVector(dx: 3, dy: 4))
        guard case let .rectangle(r) = moved.kind else { return XCTFail() }
        XCTAssertEqual(r.origin, CGPoint(x: 3, y: 4))
    }

    func testMovedByPreservesIdentity() {
        let mark = Mark(kind: .counter(center: CGPoint(x: 10, y: 10), number: 2), color: .red, width: .medium)
        let moved = mark.moved(by: CGVector(dx: 1, dy: 1))
        XCTAssertEqual(mark.id, moved.id)
    }

    // MARK: - AnnotationDocument CRUD

    func testAddRemoveReplace() {
        var doc = AnnotationDocument(pixelSize: CGSize(width: 100, height: 100), scale: 1)
        let mark = Mark(kind: .rectangle(CGRect(x: 0, y: 0, width: 10, height: 10)), color: .red, width: .medium)
        doc.add(mark)
        XCTAssertEqual(doc.marks.count, 1)

        var replaced = mark
        replaced.color = .blue
        doc.replace(replaced)
        XCTAssertEqual(doc.marks.first?.color, .blue)

        doc.remove(id: mark.id)
        XCTAssertTrue(doc.marks.isEmpty)
    }

    func testReplaceNonExistentMarkIsNoOp() {
        var doc = AnnotationDocument(pixelSize: CGSize(width: 100, height: 100), scale: 1)
        let mark = Mark(kind: .rectangle(.zero), color: .red, width: .medium)
        doc.replace(mark) // never added; should not crash or insert
        XCTAssertTrue(doc.marks.isEmpty)
    }

    // MARK: - outputPixelSize with crop

    func testOutputPixelSizeFullWhenNoCrop() {
        let doc = AnnotationDocument(pixelSize: CGSize(width: 300, height: 200), scale: 1)
        XCTAssertEqual(doc.outputPixelSize, CGSize(width: 300, height: 200))
    }

    func testOutputPixelSizeUsesCropWhenSet() {
        var doc = AnnotationDocument(pixelSize: CGSize(width: 300, height: 200), scale: 1)
        doc.crop = CGRect(x: 10, y: 10, width: 100, height: 50)
        XCTAssertEqual(doc.outputPixelSize, CGSize(width: 100, height: 50))
    }

    // MARK: - UndoStack

    func testUndoStackPushNoOpOnEqualValue() {
        var stack = UndoStack(5)
        stack.push(5) // equal to current; should not create an undo step
        XCTAssertFalse(stack.canUndo)
        XCTAssertEqual(stack.current, 5)
    }

    func testUndoStackBasicUndoRedo() {
        var stack = UndoStack(0)
        stack.push(1)
        stack.push(2)
        XCTAssertEqual(stack.current, 2)
        XCTAssertTrue(stack.canUndo)
        stack.undo()
        XCTAssertEqual(stack.current, 1)
        stack.undo()
        XCTAssertEqual(stack.current, 0)
        XCTAssertFalse(stack.canUndo)
        stack.redo()
        XCTAssertEqual(stack.current, 1)
    }

    func testUndoStackRedoClearedAfterNewPush() {
        var stack = UndoStack(0)
        stack.push(1)
        stack.undo()
        XCTAssertTrue(stack.canRedo)
        stack.push(2) // a new branch must clear redo history
        XCTAssertFalse(stack.canRedo)
        XCTAssertEqual(stack.current, 2)
    }

    func testUndoStackCapAt100() {
        var stack = UndoStack(0)
        for i in 1...150 {
            stack.push(i)
        }
        XCTAssertEqual(stack.current, 150)
        var undoCount = 0
        while stack.canUndo {
            stack.undo()
            undoCount += 1
        }
        // 150 pushes (1 initial push creates no undo step since initial state is distinct from pushes 1...150,
        // but cap limits history to 100 entries): undoCount must not exceed the cap.
        XCTAssertLessThanOrEqual(undoCount, 100)
        XCTAssertGreaterThan(undoCount, 0)
    }

    func testUndoWithEmptyHistoryIsNoOp() {
        var stack = UndoStack(42)
        stack.undo() // nothing to undo
        XCTAssertEqual(stack.current, 42)
    }

    func testRedoWithEmptyFutureIsNoOp() {
        var stack = UndoStack(42)
        stack.redo() // nothing to redo
        XCTAssertEqual(stack.current, 42)
    }

    // MARK: - AnnotationRenderer: pixel-level checks on a generated image

    /// A simple synthetic gradient image (no two adjacent pixels identical horizontally) so blur's "adjacent
    /// pixels become equal" effect is unambiguous, and so cropping/highlight can be measured precisely.
    private func makeGradientImage(width: Int, height: Int) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var data = [UInt8](repeating: 0, count: bytesPerRow * height)
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * bytesPerPixel
                data[offset] = UInt8((x * 255) / max(width - 1, 1))      // R varies with x
                data[offset + 1] = UInt8((y * 255) / max(height - 1, 1)) // G varies with y
                data[offset + 2] = 128
                data[offset + 3] = 255
            }
        }
        let context = CGContext(
            data: &data,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return context.makeImage()!
    }

    private struct RGBA: Equatable {
        var r: UInt8, g: UInt8, b: UInt8, a: UInt8
    }

    private func pixel(_ image: CGImage, x: Int, y: Int) -> RGBA {
        let data = image.dataProvider!.data
        let ptr = CFDataGetBytePtr(data)!
        let bytesPerRow = image.bytesPerRow
        let bytesPerPixel = image.bitsPerPixel / 8
        let offset = y * bytesPerRow + x * bytesPerPixel
        return RGBA(r: ptr[offset], g: ptr[offset + 1], b: ptr[offset + 2], a: ptr[offset + 3])
    }

    func testBlurRegionBecomesBlocky() {
        let base = makeGradientImage(width: 120, height: 120)
        var doc = AnnotationDocument(pixelSize: CGSize(width: 120, height: 120), scale: 1)
        doc.add(Mark(kind: .blur(CGRect(x: 0, y: 0, width: 120, height: 120)), color: .red, width: .medium))
        guard let rendered = AnnotationRenderer.render(base: base, document: doc) else {
            return XCTFail("render failed")
        }

        // Before blur: gradient means adjacent pixels along x differ (since width 120 > 1, step is non-zero).
        let beforeLeft = pixel(base, x: 10, y: 60)
        let beforeRight = pixel(base, x: 11, y: 60)
        XCTAssertNotEqual(beforeLeft.r, beforeRight.r, "sanity: gradient must vary pixel-to-pixel before blur")

        // After blur: pixels within the same 12px-ish block should become identical (pixelation), unlike the
        // smooth gradient before.
        let afterA = pixel(rendered, x: 10, y: 60)
        let afterB = pixel(rendered, x: 11, y: 60)
        XCTAssertEqual(afterA.r, afterB.r, "adjacent pixels inside a pixelated block must be equal")
        XCTAssertEqual(afterA.g, afterB.g)
    }

    func testBlurLeavesOutsideRegionUnchanged() {
        let base = makeGradientImage(width: 120, height: 120)
        var doc = AnnotationDocument(pixelSize: CGSize(width: 120, height: 120), scale: 1)
        // Blur only the left half; the right half must remain exactly as the base image.
        doc.add(Mark(kind: .blur(CGRect(x: 0, y: 0, width: 60, height: 120)), color: .red, width: .medium))
        guard let rendered = AnnotationRenderer.render(base: base, document: doc) else {
            return XCTFail("render failed")
        }
        let untouchedBefore = pixel(base, x: 100, y: 60)
        let untouchedAfter = pixel(rendered, x: 100, y: 60)
        XCTAssertEqual(untouchedBefore, untouchedAfter, "pixels outside the blur region must be unchanged")
    }

    func testHighlightChangesPixels() {
        let base = makeGradientImage(width: 60, height: 60)
        var doc = AnnotationDocument(pixelSize: CGSize(width: 60, height: 60), scale: 1)
        doc.add(Mark(kind: .highlight(CGRect(x: 10, y: 10, width: 30, height: 30)), color: .yellow, width: .medium))
        guard let rendered = AnnotationRenderer.render(base: base, document: doc) else {
            return XCTFail("render failed")
        }
        let before = pixel(base, x: 25, y: 25)
        let after = pixel(rendered, x: 25, y: 25)
        XCTAssertNotEqual(before, after, "highlight must change pixels under it")
    }

    func testCropOutputSize() {
        let base = makeGradientImage(width: 200, height: 150)
        var doc = AnnotationDocument(pixelSize: CGSize(width: 200, height: 150), scale: 1)
        doc.crop = CGRect(x: 20, y: 10, width: 80, height: 60)
        guard let rendered = AnnotationRenderer.render(base: base, document: doc) else {
            return XCTFail("render failed")
        }
        XCTAssertEqual(rendered.width, 80)
        XCTAssertEqual(rendered.height, 60)
    }

    func testCounterDrawsNonBackgroundPixelsAtCenter() {
        // Use a flat black background so any non-black pixel at the counter's center proves something was drawn.
        let width = 80, height = 80
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let base = context.makeImage()!

        var doc = AnnotationDocument(pixelSize: CGSize(width: CGFloat(width), height: CGFloat(height)), scale: 1)
        doc.add(Mark(kind: .counter(center: CGPoint(x: 40, y: 40), number: 5), color: .red, width: .medium))
        guard let rendered = AnnotationRenderer.render(base: base, document: doc) else {
            return XCTFail("render failed")
        }
        let center = pixel(rendered, x: 40, y: 40)
        let isBackgroundBlack = center.r == 0 && center.g == 0 && center.b == 0
        XCTAssertFalse(isBackgroundBlack, "the counter badge must draw something at its own center")
    }

    func testRenderWithNoMarksReturnsImageUnchanged() {
        let base = makeGradientImage(width: 40, height: 40)
        let doc = AnnotationDocument(pixelSize: CGSize(width: 40, height: 40), scale: 1)
        guard let rendered = AnnotationRenderer.render(base: base, document: doc) else {
            return XCTFail("render failed")
        }
        XCTAssertEqual(rendered.width, base.width)
        XCTAssertEqual(rendered.height, base.height)
        XCTAssertEqual(pixel(rendered, x: 20, y: 20), pixel(base, x: 20, y: 20))
    }

    // MARK: - AnnotationRenderer.encode

    func testEncodeProducesDecodablePNG() {
        let base = makeGradientImage(width: 50, height: 40)
        guard let data = AnnotationRenderer.encode(base, format: "public.png", scale: 2) else {
            return XCTFail("encode failed")
        }
        XCTAssertFalse(data.isEmpty)

        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let decoded = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return XCTFail("could not decode the encoded PNG back")
        }
        XCTAssertEqual(decoded.width, 50)
        XCTAssertEqual(decoded.height, 40)
    }

    func testEncodeWritesCorrectDPI() {
        let base = makeGradientImage(width: 10, height: 10)
        guard let data = AnnotationRenderer.encode(base, format: "public.png", scale: 2) else {
            return XCTFail("encode failed")
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return XCTFail("could not read back image properties")
        }
        let dpiWidth = properties[kCGImagePropertyDPIWidth] as? Double
        XCTAssertNotNil(dpiWidth)
        XCTAssertEqual(dpiWidth ?? 0, 144, accuracy: 0.5) // 72 * scale(2)
    }

    func testEncodeInvalidFormatReturnsNil() {
        let base = makeGradientImage(width: 10, height: 10)
        XCTAssertNil(AnnotationRenderer.encode(base, format: "not.a.real.uttype", scale: 1))
    }
}
