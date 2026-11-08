import XCTest

final class ImageTransformRulesTests: XCTestCase {
    typealias Rules = ImageTransformRules

    func testEXIFOrientationsProduceDisplayedDimensions() throws {
        XCTAssertEqual(try Rules.uprightDimensions(width: 4032, height: 3024, orientation: 1).width, 4032)
        XCTAssertEqual(try Rules.uprightDimensions(width: 4032, height: 3024, orientation: 6).width, 3024)
        XCTAssertEqual(try Rules.uprightDimensions(width: 4032, height: 3024, orientation: 6).height, 4032)
        XCTAssertEqual(try Rules.uprightDimensions(width: 4032, height: 3024, orientation: 8).width, 3024)
    }

    func testCropUsesUprightTopLeftCoordinatesBeforeResize() throws {
        let crop = Rules.NormalizedCrop(x: 0.25, y: 0.125, width: 0.5, height: 0.5)
        let plan = try Rules.calculate(sourceWidth: 800, sourceHeight: 600, orientation: 6,
                                       crop: crop, target: .width(300))
        XCTAssertEqual(plan.uprightWidth, 600)
        XCTAssertEqual(plan.uprightHeight, 800)
        XCTAssertEqual(plan.cropPixels, .init(x: 150, y: 100, width: 300, height: 400))
        XCTAssertEqual(plan.outputWidth, 300)
        XCTAssertEqual(plan.outputHeight, 400)
    }

    func testWidthHeightAndFitPreserveAspectRatio() throws {
        let width = try Rules.calculate(sourceWidth: 1600, sourceHeight: 900, orientation: 1, target: .width(800))
        XCTAssertEqual(width.outputWidth, 800)
        XCTAssertEqual(width.outputHeight, 450)
        let height = try Rules.calculate(sourceWidth: 1600, sourceHeight: 900, orientation: 1, target: .height(450))
        XCTAssertEqual(height.outputWidth, 800)
        XCTAssertEqual(height.outputHeight, 450)
        let fit = try Rules.calculate(sourceWidth: 1600, sourceHeight: 900, orientation: 1, target: .fitInside(width: 1000, height: 400))
        XCTAssertEqual(fit.outputWidth, 711)
        XCTAssertEqual(fit.outputHeight, 400)
    }

    func testNoUpscaleSkipsAndExplicitUpscaleIsAvailable() throws {
        let small = try Rules.calculate(sourceWidth: 320, sourceHeight: 200, orientation: 1, target: .longestEdge(1024))
        XCTAssertEqual(small.skipReason, .wouldUpscale)
        XCTAssertEqual(small.outputWidth, 320)
        XCTAssertEqual(small.outputHeight, 200)
        let enlarged = try Rules.calculate(sourceWidth: 320, sourceHeight: 200, orientation: 1,
                                           target: .longestEdge(1024), allowUpscale: true)
        XCTAssertNil(enlarged.skipReason)
        XCTAssertEqual(enlarged.outputWidth, 1024)
        XCTAssertEqual(enlarged.outputHeight, 640)
    }

    func testInvalidOrEmptyCropsFailClosed() {
        for crop in [Rules.NormalizedCrop(x: -0.1, y: 0, width: 0.5, height: 0.5),
                     Rules.NormalizedCrop(x: 0.75, y: 0.5, width: 0.5, height: 0.5),
                     Rules.NormalizedCrop(x: 0.2, y: 0.2, width: 0, height: 0.2)] {
            XCTAssertThrowsError(try Rules.calculate(sourceWidth: 100, sourceHeight: 100, orientation: 1, crop: crop))
        }
    }

    func testInvalidTargetsAndUnsafeSourcesFailClosed() {
        XCTAssertThrowsError(try Rules.calculate(sourceWidth: 100, sourceHeight: 100, orientation: 1, target: .width(0)))
        XCTAssertThrowsError(try Rules.calculate(sourceWidth: 100, sourceHeight: 100, orientation: 1, target: .fitInside(width: 20, height: 9000)))
        XCTAssertThrowsError(try Rules.calculate(sourceWidth: 0, sourceHeight: 100, orientation: 1))
        XCTAssertThrowsError(try Rules.calculate(sourceWidth: 20_000, sourceHeight: 20_000, orientation: 1))
        XCTAssertThrowsError(try Rules.uprightDimensions(width: 100, height: 100, orientation: 9))
    }
}
