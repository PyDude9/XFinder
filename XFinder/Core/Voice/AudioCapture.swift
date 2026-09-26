import Foundation
import AVFoundation

/// AudioCapture handles microphone input via AVAudioEngine at 16kHz Mono Float32.
/// Computes RMS every 100ms and monitors for continuous silence (< -55dB for >= 800ms).
public final class AudioCapture: @unchecked Sendable {
    public static let shared = AudioCapture()

    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private let targetFormat: AVAudioFormat

    private let lock = NSLock()
    private var _isRunning = false
    public var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isRunning
    }

    /// Callback delivering converted 16kHz Mono Float32 audio buffers for STT.
    public var onAudioBuffer: (@Sendable (AVAudioPCMBuffer) -> Void)?

    /// Callback delivering current sound level: (rawDB: Float, normalized: Float 0.0...1.0)
    public var onRMSUpdate: (@Sendable (Float, Float) -> Void)?

    // Silence detection state
    private var silenceStartTime: Date?
    private var continuousSilenceDuration: TimeInterval = 0
    private var totalSamplesCount: Int64 = 0
    private var totalEnergySum: Double = 0
    private var hasHeardSpeech = false

    public init() {
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false) else {
            fatalError("Could not create 16kHz Mono Float32 AVAudioFormat")
        }
        self.targetFormat = format
    }

    /// Starts audio capture from the default input device.
    public func start() throws {
        lock.lock()
        defer { lock.unlock() }
        guard !_isRunning else { return }

        let inputNode = engine.inputNode
        let hwFormat = inputNode.inputFormat(forBus: 0)

        // Reset silence metrics
        silenceStartTime = nil
        continuousSilenceDuration = 0
        totalSamplesCount = 0
        totalEnergySum = 0
        hasHeardSpeech = false

        if hwFormat.sampleRate != targetFormat.sampleRate || hwFormat.channelCount != targetFormat.channelCount {
            converter = AVAudioConverter(from: hwFormat, to: targetFormat)
        } else {
            converter = nil
        }

        // Tap the microphone input
        let bufferSize: AVAudioFrameCount = 1024
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: hwFormat) { [weak self] buffer, time in
            guard let self = self else { return }
            self.processInputBuffer(buffer)
        }

        try engine.start()
        _isRunning = true
    }

    /// Stops audio capture and returns summary metrics.
    /// - Returns: `(isSilent: Bool, hasSpeech: Bool, avgDB: Float)`
    public func stop() -> (isSilent: Bool, hasSpeech: Bool, avgDB: Float) {
        lock.lock()
        defer { lock.unlock() }
        guard _isRunning else {
            return (true, false, -100.0)
        }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        _isRunning = false

        let avgRMS = totalSamplesCount > 0 ? Float(sqrt(totalEnergySum / Double(totalSamplesCount))) : 0
        let avgDB: Float = avgRMS > 1e-5 ? 20 * log10(avgRMS) : -100.0
        let isSilent = !hasHeardSpeech || (continuousSilenceDuration >= 0.8 && avgDB < -55.0)

        return (isSilent, hasHeardSpeech, avgDB)
    }

    private func processInputBuffer(_ buffer: AVAudioPCMBuffer) {
        let convertedBuffer: AVAudioPCMBuffer
        if let converter = self.converter {
            let ratio = targetFormat.sampleRate / buffer.format.sampleRate
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 100
            guard let targetBuf = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }

            var error: NSError?
            var allConsumed = false
            let status = converter.convert(to: targetBuf, error: &error) { inNumPackets, outStatus in
                if allConsumed {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                outStatus.pointee = .haveData
                allConsumed = true
                return buffer
            }

            if status == .error || error != nil {
                return
            }
            convertedBuffer = targetBuf
        } else {
            convertedBuffer = buffer
        }

        // Compute RMS power
        guard let channelData = convertedBuffer.floatChannelData else { return }
        let channelSamples = channelData[0]
        let frameCount = Int(convertedBuffer.frameLength)
        guard frameCount > 0 else { return }

        var sumSquare: Float = 0
        for i in 0..<frameCount {
            let val = channelSamples[i]
            sumSquare += val * val
        }

        let rms = sqrt(sumSquare / Float(frameCount))
        let db: Float = rms > 1e-5 ? 20 * log10(rms) : -100.0

        // Normalized 0.0 (silent) to 1.0 (loud) for wave UI
        // Range: -55 dB (floor) to -10 dB (peak speech)
        let normalized = max(0.0, min(1.0, (db + 55.0) / 45.0))

        lock.lock()
        totalSamplesCount += Int64(frameCount)
        totalEnergySum += Double(sumSquare)

        if db >= -55.0 {
            hasHeardSpeech = true
            continuousSilenceDuration = 0
            silenceStartTime = nil
        } else {
            let now = Date()
            if let start = silenceStartTime {
                continuousSilenceDuration = now.timeIntervalSince(start)
            } else {
                silenceStartTime = now
                continuousSilenceDuration = 0
            }
        }
        lock.unlock()

        onRMSUpdate?(db, normalized)
        onAudioBuffer?(convertedBuffer)
    }
}
