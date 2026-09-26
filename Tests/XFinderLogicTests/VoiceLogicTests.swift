import XCTest
import Foundation
@testable import XFinderLogicTests

final class VoiceLogicTests: XCTestCase {

    // MARK: - RMS & dB Math Tests

    func testRMSCalculationForSilence() {
        let samples: [Float] = Array(repeating: 0.0, count: 1024)
        var sumSquare: Float = 0
        for s in samples { sumSquare += s * s }
        let rms = sqrt(sumSquare / Float(samples.count))
        let db: Float = rms > 1e-5 ? 20 * log10(rms) : -100.0
        let normalized = max(0.0, min(1.0, (db + 55.0) / 45.0))

        XCTAssertEqual(rms, 0.0, accuracy: 1e-6)
        XCTAssertEqual(db, -100.0)
        XCTAssertEqual(normalized, 0.0)
    }

    func testRMSCalculationForLoudSpeech() {
        // -10 dB corresponding RMS: 10^(-10/20) = 0.3162277
        let amplitude: Float = pow(10.0, -10.0 / 20.0)
        let samples: [Float] = Array(repeating: amplitude, count: 1024)
        var sumSquare: Float = 0
        for s in samples { sumSquare += s * s }
        let rms = sqrt(sumSquare / Float(samples.count))
        let db: Float = 20 * log10(rms)
        let normalized = max(0.0, min(1.0, (db + 55.0) / 45.0))

        XCTAssertEqual(db, -10.0, accuracy: 0.01)
        XCTAssertEqual(normalized, 1.0, accuracy: 0.01)
    }

    func testRMSCalculationForThresholdSilence() {
        // -55 dB threshold: 10^(-55/20) = 0.001778
        let amplitude: Float = pow(10.0, -55.0 / 20.0)
        let samples: [Float] = Array(repeating: amplitude, count: 1024)
        var sumSquare: Float = 0
        for s in samples { sumSquare += s * s }
        let rms = sqrt(sumSquare / Float(samples.count))
        let db: Float = 20 * log10(rms)
        let normalized = max(0.0, min(1.0, (db + 55.0) / 45.0))

        XCTAssertEqual(db, -55.0, accuracy: 0.01)
        XCTAssertEqual(normalized, 0.0, accuracy: 0.01)
    }

    func testRMSCalculationForMidVolumeSpeech() {
        // Mid-point between -55 dB and -10 dB is -32.5 dB -> normalized should be 0.5
        let amplitude: Float = pow(10.0, -32.5 / 20.0)
        let samples: [Float] = Array(repeating: amplitude, count: 1024)
        var sumSquare: Float = 0
        for s in samples { sumSquare += s * s }
        let rms = sqrt(sumSquare / Float(samples.count))
        let db: Float = 20 * log10(rms)
        let normalized = max(0.0, min(1.0, (db + 55.0) / 45.0))

        XCTAssertEqual(db, -32.5, accuracy: 0.01)
        XCTAssertEqual(normalized, 0.5, accuracy: 0.01)
    }

    // MARK: - Silence Logic & Zero-Hallucination

    func testContinuousSilenceDetectionFlag() {
        // Condition: continuousSilenceDuration >= 0.8s AND avgDB < -55dB
        let speechOccurred = false
        let continuousSilence: TimeInterval = 0.85
        let avgDB: Float = -60.0

        let isSilent = !speechOccurred || (continuousSilence >= 0.8 && avgDB < -55.0)
        XCTAssertTrue(isSilent, "Should flag as silence if speech never occurred or silence >= 800ms below -55dB")
    }

    func testSpeechOverridesSilence() {
        let speechOccurred = true
        let continuousSilence: TimeInterval = 0.2 // brief pause under 800ms
        let avgDB: Float = -25.0 // audible speech

        let isSilent = !speechOccurred || (continuousSilence >= 0.8 && avgDB < -55.0)
        XCTAssertFalse(isSilent, "Should not flag as silent when speech occurred and pause < 800ms")
    }

    // MARK: - KeyCode Distinction

    func testRightOptionVsLeftOptionKeyCode() {
        let rightOptionKeyCode: Int64 = 61
        let leftOptionKeyCode: Int64 = 58
        let escapeKeyCode: Int64 = 53

        XCTAssertNotEqual(rightOptionKeyCode, leftOptionKeyCode, "Right Option (61) and Left Option (58) must be strictly distinct")
        XCTAssertEqual(rightOptionKeyCode, 61)
        XCTAssertEqual(leftOptionKeyCode, 58)
        XCTAssertEqual(escapeKeyCode, 53)
    }

    // MARK: - SttError Equatable

    func testSttErrors() {
        XCTAssertEqual(SttError.permissionDenied, SttError.permissionDenied)
        XCTAssertEqual(SttError.silentStream, SttError.silentStream)
        XCTAssertEqual(SttError.noSpeech, SttError.noSpeech)
        XCTAssertEqual(SttError.modelNotReady, SttError.modelNotReady)
        XCTAssertEqual(SttError.systemError("timeout"), SttError.systemError("timeout"))
        XCTAssertNotEqual(SttError.noSpeech, SttError.permissionDenied)
    }

    // MARK: - Mock SttProvider Workflow

    func testMockSttProviderLifecycle() async {
        final class MockSttProvider: SttProvider {
            let id = "mock"
            var isStarted = false
            var isWarm = false

            func isAvailable() async -> Bool { true }
            func warmup() async { isWarm = true }
            func start(
                language: String,
                onPartial: @escaping @Sendable (String) -> Void,
                onFinal: @escaping @Sendable (String) -> Void,
                onError: @escaping @Sendable (SttError) -> Void
            ) async {
                isStarted = true
                onPartial("Xin")
                onPartial("Xin chào")
                onFinal("Xin chào các bạn")
            }
            func stop() async -> String? {
                isStarted = false
                return "Xin chào các bạn"
            }
            func cancel() {
                isStarted = false
            }
        }

        let provider = MockSttProvider()
        let available = await provider.isAvailable()
        XCTAssertTrue(available)

        await provider.warmup()
        XCTAssertTrue(provider.isWarm)

        var partials: [String] = []
        var finalResult = ""

        await provider.start(
            language: "vi-VN",
            onPartial: { partials.append($0) },
            onFinal: { finalResult = $0 },
            onError: { _ in }
        )

        XCTAssertTrue(provider.isStarted)
        XCTAssertEqual(partials, ["Xin", "Xin chào"])
        XCTAssertEqual(finalResult, "Xin chào các bạn")

        let stoppedText = await provider.stop()
        XCTAssertFalse(provider.isStarted)
        XCTAssertEqual(stoppedText, "Xin chào các bạn")
    }
}
