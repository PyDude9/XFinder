import XCTest
import Foundation

final class NotchTaskTests: XCTestCase {
    let enc = ["public.jpeg", "public.png", "public.heic"]
    func u(_ n: String) -> URL { URL(fileURLWithPath: "/h/\(n)") }

    func testActionsFollowWhatIsHeld() {
        XCTAssertEqual(NotchActions.available(for: [], encodable: enc), [], "nothing held, nothing offered")
        XCTAssertEqual(NotchActions.available(for: [u("a.txt")], encodable: enc), [.zip, .airDrop])
        XCTAssertEqual(NotchActions.available(for: [u("a.pdf")], encodable: enc), [.zip, .toPDF, .airDrop], "one PDF cannot be merged; N6 still offers a (copied) PDF of it")
        XCTAssertEqual(NotchActions.available(for: [u("a.pdf"), u("b.PDF")], encodable: enc), [.zip, .mergePDFs, .toPDF, .airDrop])
        XCTAssertEqual(NotchActions.available(for: [u("p.heic")], encodable: enc),
                       [.zip, .toPDF, .convert(.jpeg), .convert(.png), .resize(maxPixels: 1600), .removeBackground, .ocr, .airDrop])
    }

    func testAConversionIsOfferedOnlyIfSomethingWouldChange() {
        XCTAssertEqual(NotchActions.available(for: [u("a.jpg")], encodable: enc),
                       [.zip, .toPDF, .convert(.png), .resize(maxPixels: 1600), .removeBackground, .ocr, .airDrop], "no JPEG→JPEG")
        XCTAssertEqual(NotchActions.inputs(for: .convert(.jpeg), from: [u("a.jpg"), u("b.png"), u("c.txt")]), [u("b.png")])
    }

    func testAMissingEncoderIsNeverOffered() {
        XCTAssertEqual(NotchActions.available(for: [u("p.heic")], encodable: ["public.jpeg"]),
                       [.zip, .toPDF, .convert(.jpeg), .resize(maxPixels: 1600), .removeBackground, .ocr, .airDrop])
    }

    func testStepsAreFilesForPerFileJobsAndOneForCombiningJobs() {
        XCTAssertEqual(NotchActions.stepCount(for: .zip, inputs: 40), 1)
        XCTAssertEqual(NotchActions.stepCount(for: .convert(.png), inputs: 40), 40)
        XCTAssertEqual(NotchActions.stepCount(for: .mergePDFs, inputs: 0), 0)
    }

    func testProgressCountsFinishedFilesAndFinishes() {
        var t = NotchTask(action: .convert(.png), total: 3)
        XCTAssertEqual(t.fraction, 0)
        t.stepSucceeded(output: u("a.png"))
        t.stepFailed(key: "k", detail: "b.heic")
        XCTAssertEqual(t.fraction, 2.0 / 3, accuracy: 1e-9)
        XCTAssertTrue(t.isRunning)
        t.stepSucceeded(output: u("c.png"))
        XCTAssertEqual(t.phase, .finished)
        XCTAssertEqual(t.outputs, [u("a.png"), u("c.png")])
        XCTAssertEqual(t.firstFailure?.detail, "b.heic")
    }

    /// A step that lands after Cancel must not resurrect the task or count as done.
    func testCancelIsFinalAndLateStepsAreIgnored() {
        var t = NotchTask(action: .removeBackground, total: 2)
        t.cancel()
        t.stepSucceeded(output: u("x.png"))
        XCTAssertEqual(t.phase, .cancelled)
        XCTAssertEqual(t.outputs, [])
        XCTAssertLessThan(t.fraction, 1)
    }

    func testAnEmptyTaskIsBornFinished() {
        XCTAssertEqual(NotchTask(action: .mergePDFs, total: 0).phase, .finished)
    }

    /// Exhaustive: any sequence of ≤ 5 step/cancel events keeps the fraction in 0…1, never counts
    /// more steps than the total, and never leaves a task "running" once every step reported.
    func testNoSequenceBreaksTheCounters() {
        let total = 3
        func walk(_ t: NotchTask, _ depth: Int) {
            XCTAssertTrue((0...1).contains(t.fraction))
            if t.phase == .running { XCTAssertLessThan(t.fraction, 1, "all steps in but still running") }
            guard depth < 5 else { return }
            var a = t; a.stepSucceeded(output: nil); walk(a, depth + 1)
            var b = t; b.stepFailed(key: "k", detail: "d"); walk(b, depth + 1)
            var c = t; c.cancel(); walk(c, depth + 1)
        }
        walk(NotchTask(action: .convert(.png), total: total), 0)
    }
}
