import XCTest
import ImageIO

/// XF-T26 — scrolling capture: comparing captures and assembling the long image, on synthetic pages whose truth is known.
final class ScrollStitchTests: XCTestCase {
    typealias S = ScrollStitch
    let width = 160

    /// One page row: "text lines" 14 rows tall with a 6-row gap, every line different (seeded by the row), so a shift is
    /// recognisable. Returns gray levels per pixel.
    func pageRow(_ y: Int) -> [UInt8] {
        let inLine = y % 20 < 14
        return (0..<width).map { x in
            guard inLine else { return 250 }
            let v = (x * 7 + y * 13 + (x * y) % 29) % 97
            return v < 40 ? 30 : 230     // dark "glyph" pixels on white
        }
    }
    func headerRow(_ y: Int) -> [UInt8] { (0..<width).map { x in UInt8((x / 8 + y) % 2 == 0 ? 90 : 160) } }
    func footerRow(_ y: Int) -> [UInt8] { (0..<width).map { x in UInt8((x / 5 + y) % 3 == 0 ? 60 : 200) } }

    /// RGBA bitmap from gray rows.
    func bitmap(_ rows: [[UInt8]], noise: Bool = false) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(rows.count * width * 4)
        for (y, row) in rows.enumerated() {
            for (x, g) in row.enumerated() {
                var v = g
                if noise, (x * 31 + y * 17) % 11 == 0 { v = v > 128 ? v - 3 : v + 3 }   // anti-aliasing-sized noise
                out += [v, v, v, 255]
            }
        }
        return out
    }
    func frame(_ rows: [[UInt8]], noise: Bool = false) -> S.Frame {
        S.frame(pixels: bitmap(rows, noise: noise), width: width, height: rows.count, bytesPerRow: width * 4)
    }

    /// The visible area at a page offset: optional pinned header/footer around `body` rows of the page.
    func viewport(offset: Int, body: Int, header: Int = 0, footer: Int = 0) -> [[UInt8]] {
        (0..<header).map(headerRow) + (offset..<(offset + body)).map(pageRow) + (0..<footer).map(footerRow)
    }

    /// Assemble frames with the real rules and return the long image's row signatures, plus what the truth should be.
    func stitch(offsets: [Int], body: Int, header: Int = 0, footer: Int = 0, noise: Bool = false) -> (got: [ArraySlice<UInt8>], want: [ArraySlice<UInt8>]) {
        let frames = offsets.map { frame(viewport(offset: $0, body: body, header: header, footer: footer), noise: noise) }
        var assembly = S.Assembly(first: frames[0])
        var rows: [ArraySlice<UInt8>] = (0..<frames[0].height).map { frames[0].row($0) }
        for i in 1..<frames.count {
            guard case .moved(let m) = S.compare(frames[i - 1], frames[i]) else {
                XCTFail("frame \(i) (offset \(offsets[i])) not matched: \(S.compare(frames[i - 1], frames[i]))"); break
            }
            XCTAssertEqual(m.shift, offsets[i] - offsets[i - 1], "frame \(i)")
            let step = assembly.add(m, frameHeight: frames[i].height)
            rows.removeLast(step.dropFooter)
            rows += step.append.map { frames[i].row($0) }
            rows += step.footer.map { frames[i].row($0) }
        }
        XCTAssertEqual(assembly.height, rows.count, "the assembly's height tracks the rows it describes")
        let truth = frame(viewport(offset: 0, body: offsets.last! + body, header: header, footer: footer), noise: false)
        return (rows, (0..<truth.height).map { truth.row($0) })
    }

    func assertRowsEqual(_ got: [ArraySlice<UInt8>], _ want: [ArraySlice<UInt8>], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(got.count, want.count, "height", file: file, line: line)
        let bad = zip(got, want).enumerated().filter { !zip($0.element.0, $0.element.1).allSatisfy { abs(Int($0) - Int($1)) <= 1 } }.map(\.offset)
        XCTAssertTrue(bad.isEmpty, "rows differ from the page at \(bad.prefix(5))…", file: file, line: line)
    }

    // MARK: Assembly

    func testEvenScrollsRebuildThePageRowForRow() {
        let r = stitch(offsets: [0, 30, 60, 90, 120], body: 120)
        assertRowsEqual(r.got, r.want)
    }

    func testUnevenScrollsAndALargeStepStillLineUp() {
        let r = stitch(offsets: [0, 17, 72, 75, 190, 200], body: 140)
        assertRowsEqual(r.got, r.want)
    }

    /// A sticky header and footer appear once, at the top and the bottom — not repeated in every slice.
    func testPinnedHeaderAndFooterAppearOnce() {
        let r = stitch(offsets: [0, 40, 85, 130], body: 120, header: 24, footer: 16)
        assertRowsEqual(r.got, r.want)
        // 30 rows: the rows just above the footer then differ (a shift by a whole "line" would leave blank gap rows at
        // the same place, which are honestly pinned too — the assembly copes, but the count would not be 16).
        let frames = [0, 30].map { frame(viewport(offset: $0, body: 120, header: 24, footer: 16)) }
        guard case .moved(let m) = S.compare(frames[0], frames[1]) else { return XCTFail() }
        XCTAssertEqual(m.top, 24); XCTAssertEqual(m.bottom, 16)
    }

    /// Shifts of 31 and 34 rows: NOT multiples of the noise pattern's period (11), so the matched rows carry different
    /// noise — a shift of 33 lined the noise up exactly and tested nothing (mutant X3 survived it).
    func testAntiAliasingSizedNoiseDoesNotBreakTheMatch() {
        let r = stitch(offsets: [0, 31, 65], body: 120, noise: true)
        XCTAssertEqual(r.got.count, r.want.count)
    }

    // MARK: Outcomes

    func testAnUnchangedAreaIsNothingNew() {
        let f = frame(viewport(offset: 50, body: 100))
        XCTAssertEqual(S.compare(f, f), .same)
        let blank = frame(Array(repeating: Array(repeating: 250, count: width), count: 80))
        XCTAssertEqual(S.compare(blank, blank), .same, "a flat area has nothing to match — and nothing new")
    }

    func testScrollingTooFarOrBackwardsLosesThePlace() {
        let a = frame(viewport(offset: 0, body: 100))
        XCTAssertEqual(S.compare(a, frame(viewport(offset: 140, body: 100))), .lost, "no overlap left")
        XCTAssertEqual(S.compare(frame(viewport(offset: 80, body: 100)), frame(viewport(offset: 40, body: 100))), .lost,
                       "scrolling up is not stitched in this version")
        XCTAssertEqual(S.compare(a, frame(viewport(offset: 0, body: 90))), .lost, "a different-sized capture")
    }

    func testFlatRowsAreNoEvidence() {
        // Only blank rows overlap: any shift would "match"; the rule refuses to count them as evidence.
        XCTAssertNil(S.agreement(frame(Array(repeating: Array(repeating: 250, count: width), count: 40)),
                                 frame(Array(repeating: Array(repeating: 250, count: width), count: 40)), shift: 3, top: 0, bottom: 0))
    }

    /// The overlay scroll bar at the right edge changes while scrolling; those columns are not sampled.
    func testTheScrollBarEdgeIsIgnored() {
        var a = viewport(offset: 0, body: 100), b = viewport(offset: 20, body: 100)
        // The last 7 % of the width: inside the skipped 8 %, but wide enough that sampling it would break every row.
        for y in 0..<b.count { for x in (width - 11)..<width { b[y][x] = 0; a[y][x] = 255 } }
        guard case .moved(let m) = S.compare(frame(a), frame(b)) else { return XCTFail("the scroll bar broke the match") }
        XCTAssertEqual(m.shift, 20)
    }

    // MARK: Session decisions

    func testSessionLimits() {
        XCTAssertFalse(S.isLargeEnough(width: 47, height: 300))
        XCTAssertTrue(S.isLargeEnough(width: 48, height: 48))
        XCTAssertEqual(S.autoScrollStep(areaHeightPoints: 500, pinnedPoints: 100), 240)
        XCTAssertEqual(S.autoScrollStep(areaHeightPoints: 60, pinnedPoints: 20), 40, "never less than 40 pt")
        XCTAssertGreaterThan(S.heightLimit, 10_000)
        XCTAssertGreaterThanOrEqual(S.unchangedScrollsToStop, 2)
    }

    // MARK: Building the long image

    /// Strips stack top to bottom at their own height, the screen's DPI is kept, and a missing strip fails instead of
    /// writing a shorter image.
    func testComposeStacksStripsInOrderAndKeepsTheDPI() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("xf-stitch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        func strip(_ gray: UInt8, height: Int, name: String) -> URL {
            let ctx = CGContext(data: nil, width: 20, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            let v = CGFloat(gray) / 255
            ctx.setFillColor(CGColor(red: v, green: v, blue: v, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 20, height: height))
            let url = dir.appendingPathComponent(name)
            XCTAssertTrue(S.writePNG(ctx.makeImage(), to: url, scale: 2))
            return url
        }
        let top = strip(20, height: 10, name: "a.png"), bottom = strip(230, height: 6, name: "b.png")
        let out = dir.appendingPathComponent("out.png")
        XCTAssertTrue(S.compose(S.Manifest(strips: [top.path, bottom.path], output: out.path, scale: 2)))
        let src = try XCTUnwrap(CGImageSourceCreateWithURL(out as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(src, 0, nil))
        XCTAssertEqual(image.width, 20); XCTAssertEqual(image.height, 16)
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        XCTAssertEqual((props?[kCGImagePropertyDPIWidth] as? NSNumber)?.intValue, 144, "Retina DPI, read by the editor and the pin window")
        // Top row dark, bottom row light: the first strip is at the top.
        let ctx = CGContext(data: nil, width: 20, height: 16, bitsPerComponent: 8, bytesPerRow: 80,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: 20, height: 16))
        let px = ctx.data!.assumingMemoryBound(to: UInt8.self)
        XCTAssertLessThan(px[0], 60, "row 0 (top in memory) comes from the first strip")
        XCTAssertGreaterThan(px[15 * 80], 200, "the last row comes from the second strip")
        XCTAssertFalse(S.compose(S.Manifest(strips: [top.path, dir.appendingPathComponent("missing.png").path], output: out.path, scale: 2)))
    }

    /// ScreenCaptureKit's padded BGRA rows become packed RGBA: channels swapped, alpha kept, the padding dropped.
    func testBGRARowsBecomePackedRGBA() {
        // 2 × 2 pixels, rows padded to 12 bytes (2 px = 8 bytes + 4 bytes of padding filled with 0xEE).
        let bgra: [UInt8] = [
            1, 2, 3, 4,     5, 6, 7, 8,       0xEE, 0xEE, 0xEE, 0xEE,
            9, 10, 11, 12,  13, 14, 15, 16,   0xEE, 0xEE, 0xEE, 0xEE,
        ]
        let rgba = bgra.withUnsafeBytes { S.rgba(fromBGRA: $0, width: 2, height: 2, bytesPerRow: 12) }
        XCTAssertEqual(rgba, [3, 2, 1, 4,  7, 6, 5, 8,  11, 10, 9, 12,  15, 14, 13, 16])
        // The last row may end without its padding.
        let short = Array(bgra.prefix(12 + 8))
        XCTAssertEqual(short.withUnsafeBytes { S.rgba(fromBGRA: $0, width: 2, height: 2, bytesPerRow: 12) }, rgba)
        // Too few bytes, or rows narrower than the width, is no image — never a read past the buffer.
        XCTAssertNil(Array(bgra.prefix(19)).withUnsafeBytes { S.rgba(fromBGRA: $0, width: 2, height: 2, bytesPerRow: 12) })
        XCTAssertNil(bgra.withUnsafeBytes { S.rgba(fromBGRA: $0, width: 2, height: 2, bytesPerRow: 7) })
        XCTAssertNil(bgra.withUnsafeBytes { S.rgba(fromBGRA: $0, width: 0, height: 2, bytesPerRow: 12) })
    }

    func testTheManifestRoundTrips() throws {
        let m = S.Manifest(strips: ["/a/1.png", "/a/2.png"], output: "/a/out.png", scale: 2)
        XCTAssertEqual(try JSONDecoder().decode(S.Manifest.self, from: JSONEncoder().encode(m)), m)
    }
}
