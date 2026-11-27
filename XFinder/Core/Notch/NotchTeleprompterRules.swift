import Foundation
import CoreGraphics

/// Pure state, persistence sanitization, playback advancement, and reader-window geometry
/// for the Dynamic Island Teleprompter. Kept free of AppKit/SwiftUI so `Tests/XFinderLogicTests`
/// verifies every failure case deterministically.
enum NotchTeleprompterMode: String, Equatable, CaseIterable, Codable, Sendable {
    case editor
    case reader
}

enum NotchTeleprompterStorageKeys {
    static let script = "notch.teleprompter.script"
    static let speed = "notch.teleprompter.speed"
    static let fontSize = "notch.teleprompter.fontSize"
    static let progress = "notch.teleprompter.progress"
    static let mode = "notch.teleprompter.mode"
}

enum NotchTeleprompterLimits {
    static let maxScriptCharacters = 100_000

    static let minSpeed: Double = 16
    static let maxSpeed: Double = 180
    static let defaultSpeed: Double = 44
    static let speedStep: Double = 8

    static let minFontSize: Double = 14
    static let maxFontSize: Double = 40
    static let defaultFontSize: Double = 22
    static let fontSizeStep: Double = 2

    /// Upper bound for a single playback tick so runloop stalls or sleep/wake never jump to the end.
    static let maxTickDelta: Double = 0.25

    /// Discrete step cadence (seconds) used when macOS Reduce Motion is active.
    static let reduceMotionStepInterval: Double = 0.85

    static let defaultReaderSize = CGSize(width: 560, height: 184)
    static let minReaderSize = CGSize(width: 320, height: 120)
    static let screenHorizontalMargin: CGFloat = 12
    static let screenBottomMargin: CGFloat = 12
    static let gapBelowTopEdge: CGFloat = 10
}

struct NotchTeleprompterSettings: Equatable, Sendable {
    var speedPointsPerSecond: Double
    var fontSize: Double
    var progress: Double
    var mode: NotchTeleprompterMode

    static let `default` = NotchTeleprompterSettings(
        speedPointsPerSecond: NotchTeleprompterLimits.defaultSpeed,
        fontSize: NotchTeleprompterLimits.defaultFontSize,
        progress: 0,
        mode: .editor
    )

    static func sanitized(
        speed: Double?,
        fontSize: Double?,
        progress: Double?,
        modeRaw: String?
    ) -> NotchTeleprompterSettings {
        NotchTeleprompterSettings(
            speedPointsPerSecond: clampFinite(
                speed,
                min: NotchTeleprompterLimits.minSpeed,
                max: NotchTeleprompterLimits.maxSpeed,
                fallback: NotchTeleprompterLimits.defaultSpeed
            ),
            fontSize: clampFinite(
                fontSize,
                min: NotchTeleprompterLimits.minFontSize,
                max: NotchTeleprompterLimits.maxFontSize,
                fallback: NotchTeleprompterLimits.defaultFontSize
            ),
            progress: clampFinite(
                progress,
                min: 0,
                max: 1,
                fallback: 0
            ),
            mode: modeRaw.flatMap(NotchTeleprompterMode.init(rawValue:)) ?? .editor
        )
    }

    static func clampFinite(_ value: Double?, min lower: Double, max upper: Double, fallback: Double) -> Double {
        guard let value, value.isFinite else { return fallback }
        return Swift.min(Swift.max(value, lower), upper)
    }
}

enum NotchTeleprompterScriptNormalization {
    struct Result: Equatable, Sendable {
        let text: String
        let wasTruncated: Bool
    }

    /// Normalizes line endings and bounds huge scripts so local persistence and layout remain responsive.
    static func sanitize(
        _ raw: String,
        maxCharacters: Int = NotchTeleprompterLimits.maxScriptCharacters
    ) -> Result {
        let normalized = raw.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let limit = max(0, maxCharacters)
        if normalized.count <= limit {
            return Result(text: normalized, wasTruncated: false)
        }
        let endIndex = normalized.index(normalized.startIndex, offsetBy: limit)
        return Result(text: String(normalized[..<endIndex]), wasTruncated: true)
    }

    static func hasReadableContent(_ text: String) -> Bool {
        text.unicodeScalars.contains { !CharacterSet.whitespacesAndNewlines.contains($0) }
    }

    /// Single-pass O(n) word counter safe for 100k+ character scripts without intermediate array allocations.
    static func wordCount(_ text: String) -> Int {
        var count = 0
        var inWord = false
        for scalar in text.unicodeScalars {
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                inWord = false
            } else if !inWord {
                inWord = true
                count += 1
            }
        }
        return count
    }
}

struct NotchTeleprompterState: Equatable, Sendable {
    var script: String
    var wasTruncated: Bool
    var mode: NotchTeleprompterMode
    var isPlaying: Bool
    var reachedEnd: Bool
    /// Normalized scroll position in `0...1`, preserved across surface switches (Island ↔ Reader Window).
    var progress: Double
    var speedPointsPerSecond: Double
    var fontSize: Double

    var isTabEnabled: Bool
    var isIslandVisible: Bool
    var isReaderWindowVisible: Bool
    var isSleeping: Bool
    var reduceMotion: Bool
    var reduceMotionAccumulator: Double

    init(
        script: String = "",
        settings: NotchTeleprompterSettings = .default,
        isTabEnabled: Bool = true,
        isIslandVisible: Bool = false,
        isReaderWindowVisible: Bool = false,
        isSleeping: Bool = false,
        reduceMotion: Bool = false
    ) {
        let normalized = NotchTeleprompterScriptNormalization.sanitize(script)
        self.script = normalized.text
        self.wasTruncated = normalized.wasTruncated
        let hasContent = NotchTeleprompterScriptNormalization.hasReadableContent(normalized.text)
        let clampedProgress = hasContent
            ? NotchTeleprompterSettings.clampFinite(settings.progress, min: 0, max: 1, fallback: 0)
            : 0
        self.mode = settings.mode
        self.isPlaying = false
        self.reachedEnd = hasContent && clampedProgress >= 1.0
        self.progress = clampedProgress
        self.speedPointsPerSecond = NotchTeleprompterSettings.clampFinite(
            settings.speedPointsPerSecond,
            min: NotchTeleprompterLimits.minSpeed,
            max: NotchTeleprompterLimits.maxSpeed,
            fallback: NotchTeleprompterLimits.defaultSpeed
        )
        self.fontSize = NotchTeleprompterSettings.clampFinite(
            settings.fontSize,
            min: NotchTeleprompterLimits.minFontSize,
            max: NotchTeleprompterLimits.maxFontSize,
            fallback: NotchTeleprompterLimits.defaultFontSize
        )
        self.isTabEnabled = isTabEnabled
        self.isIslandVisible = isIslandVisible
        self.isReaderWindowVisible = isReaderWindowVisible
        self.isSleeping = isSleeping
        self.reduceMotion = reduceMotion
        self.reduceMotionAccumulator = 0
    }

    var hasReadableScript: Bool {
        NotchTeleprompterScriptNormalization.hasReadableContent(script)
    }

    var isInlineReaderVisible: Bool {
        isTabEnabled && isIslandVisible && mode == .reader
    }

    var isAnyReaderVisible: Bool {
        isTabEnabled && (isInlineReaderVisible || isReaderWindowVisible)
    }

    /// Playback advances ONLY while a reader surface is visible, tab is enabled, script is non-empty,
    /// system is awake, and playback is active.
    var canAdvance: Bool {
        isPlaying && hasReadableScript && isAnyReaderVisible && !isSleeping
    }

    var needsTicker: Bool {
        canAdvance
    }

    var speedMultiplier: Double {
        speedPointsPerSecond / NotchTeleprompterLimits.defaultSpeed
    }

    var settingsSnapshot: NotchTeleprompterSettings {
        NotchTeleprompterSettings(
            speedPointsPerSecond: speedPointsPerSecond,
            fontSize: fontSize,
            progress: progress,
            mode: mode
        )
    }
}

enum NotchTeleprompterEngine {
    struct TickResult: Equatable, Sendable {
        let state: NotchTeleprompterState
        let didAdvance: Bool
    }

    static func play(_ state: NotchTeleprompterState) -> NotchTeleprompterState {
        var next = state
        guard next.isTabEnabled, !next.isSleeping, next.hasReadableScript else {
            next.isPlaying = false
            next.reduceMotionAccumulator = 0
            return next
        }
        // If user hits Play from the Island editor while no reader window is open, switch to inline reader.
        if !next.isAnyReaderVisible {
            if next.isIslandVisible {
                next.mode = .reader
            } else {
                next.isPlaying = false
                next.reduceMotionAccumulator = 0
                return next
            }
        }
        if next.reachedEnd || next.progress >= 1.0 {
            next.progress = 0
            next.reachedEnd = false
        }
        next.isPlaying = true
        next.reduceMotionAccumulator = 0
        return next
    }

    static func pause(_ state: NotchTeleprompterState) -> NotchTeleprompterState {
        var next = state
        next.isPlaying = false
        next.reduceMotionAccumulator = 0
        return next
    }

    static func togglePlayPause(_ state: NotchTeleprompterState) -> NotchTeleprompterState {
        state.isPlaying ? pause(state) : play(state)
    }

    static func restart(_ state: NotchTeleprompterState) -> NotchTeleprompterState {
        var next = state
        next.progress = 0
        next.reachedEnd = false
        next.reduceMotionAccumulator = 0
        if !next.canAdvance {
            next.isPlaying = false
        }
        return next
    }

    static func setMode(_ state: NotchTeleprompterState, mode: NotchTeleprompterMode) -> NotchTeleprompterState {
        var next = state
        next.mode = mode
        if !next.isAnyReaderVisible {
            next.isPlaying = false
            next.reduceMotionAccumulator = 0
        }
        return next
    }

    /// Updates script text while preserving reading position safely.
    /// Edits during active playback pause playback so text never scrolls away under the cursor.
    static func updateScript(_ state: NotchTeleprompterState, rawText: String) -> NotchTeleprompterState {
        var next = state
        let sanitized = NotchTeleprompterScriptNormalization.sanitize(rawText)
        let changed = sanitized.text != next.script
        next.script = sanitized.text
        next.wasTruncated = sanitized.wasTruncated

        guard next.hasReadableScript else {
            next.progress = 0
            next.isPlaying = false
            next.reachedEnd = false
            next.reduceMotionAccumulator = 0
            return next
        }

        if changed && next.isPlaying {
            next.isPlaying = false
            next.reduceMotionAccumulator = 0
        }
        next.progress = NotchTeleprompterSettings.clampFinite(next.progress, min: 0, max: 1, fallback: 0)
        next.reachedEnd = next.progress >= 1.0
        return next
    }

    static func setProgress(_ state: NotchTeleprompterState, progress: Double) -> NotchTeleprompterState {
        var next = state
        guard next.hasReadableScript else {
            next.progress = 0
            next.reachedEnd = false
            next.isPlaying = false
            return next
        }
        let clamped = NotchTeleprompterSettings.clampFinite(progress, min: 0, max: 1, fallback: next.progress)
        next.progress = clamped
        next.reachedEnd = clamped >= 1.0
        if next.reachedEnd {
            next.isPlaying = false
            next.reduceMotionAccumulator = 0
        }
        return next
    }

    static func adjustSpeed(_ state: NotchTeleprompterState, delta: Double) -> NotchTeleprompterState {
        setSpeed(state, value: state.speedPointsPerSecond + delta)
    }

    static func setSpeed(_ state: NotchTeleprompterState, value: Double) -> NotchTeleprompterState {
        var next = state
        next.speedPointsPerSecond = NotchTeleprompterSettings.clampFinite(
            value,
            min: NotchTeleprompterLimits.minSpeed,
            max: NotchTeleprompterLimits.maxSpeed,
            fallback: next.speedPointsPerSecond
        )
        return next
    }

    static func adjustFontSize(_ state: NotchTeleprompterState, delta: Double) -> NotchTeleprompterState {
        setFontSize(state, value: state.fontSize + delta)
    }

    static func setFontSize(_ state: NotchTeleprompterState, value: Double) -> NotchTeleprompterState {
        var next = state
        next.fontSize = NotchTeleprompterSettings.clampFinite(
            value,
            min: NotchTeleprompterLimits.minFontSize,
            max: NotchTeleprompterLimits.maxFontSize,
            fallback: next.fontSize
        )
        return next
    }

    static func setIslandVisible(_ state: NotchTeleprompterState, visible: Bool) -> NotchTeleprompterState {
        var next = state
        next.isIslandVisible = visible
        if !next.isAnyReaderVisible {
            next.isPlaying = false
            next.reduceMotionAccumulator = 0
        }
        return next
    }

    static func setReaderWindowVisible(_ state: NotchTeleprompterState, visible: Bool) -> NotchTeleprompterState {
        var next = state
        next.isReaderWindowVisible = visible && next.isTabEnabled
        if !next.isAnyReaderVisible {
            next.isPlaying = false
            next.reduceMotionAccumulator = 0
        }
        return next
    }

    static func setTabEnabled(_ state: NotchTeleprompterState, enabled: Bool) -> NotchTeleprompterState {
        var next = state
        next.isTabEnabled = enabled
        if !enabled {
            next.isPlaying = false
            next.isReaderWindowVisible = false
            next.reduceMotionAccumulator = 0
        }
        return next
    }

    static func handleSystemSleep(_ state: NotchTeleprompterState) -> NotchTeleprompterState {
        var next = state
        next.isSleeping = true
        next.isPlaying = false
        next.reduceMotionAccumulator = 0
        return next
    }

    static func handleSystemWake(_ state: NotchTeleprompterState) -> NotchTeleprompterState {
        var next = state
        next.isSleeping = false
        next.reduceMotionAccumulator = 0
        return next
    }

    static func setReduceMotion(_ state: NotchTeleprompterState, enabled: Bool) -> NotchTeleprompterState {
        var next = state
        if next.reduceMotion != enabled {
            next.reduceMotion = enabled
            next.reduceMotionAccumulator = 0
        }
        return next
    }

    /// Advances playback by `deltaTime` seconds over `scrollableDistance` points.
    /// Guarantees zero advancement unless a reader surface is visible and actively playing.
    static func tick(
        _ state: NotchTeleprompterState,
        deltaTime: Double,
        scrollableDistance: Double
    ) -> TickResult {
        var next = state
        guard next.canAdvance else {
            next.isPlaying = false
            next.reduceMotionAccumulator = 0
            return TickResult(state: next, didAdvance: false)
        }
        guard deltaTime.isFinite, deltaTime > 0 else {
            return TickResult(state: next, didAdvance: false)
        }
        guard scrollableDistance.isFinite, scrollableDistance > 0 else {
            let moved = next.progress < 1.0
            next.progress = 1.0
            next.reachedEnd = true
            next.isPlaying = false
            next.reduceMotionAccumulator = 0
            return TickResult(state: next, didAdvance: moved)
        }

        let clampedDelta = min(deltaTime, NotchTeleprompterLimits.maxTickDelta)
        let effectiveDelta: Double

        if next.reduceMotion {
            next.reduceMotionAccumulator += clampedDelta
            guard next.reduceMotionAccumulator >= NotchTeleprompterLimits.reduceMotionStepInterval else {
                return TickResult(state: next, didAdvance: false)
            }
            let steps = floor(next.reduceMotionAccumulator / NotchTeleprompterLimits.reduceMotionStepInterval)
            effectiveDelta = steps * NotchTeleprompterLimits.reduceMotionStepInterval
            next.reduceMotionAccumulator -= effectiveDelta
        } else {
            effectiveDelta = clampedDelta
        }

        let deltaProgress = (next.speedPointsPerSecond * effectiveDelta) / scrollableDistance
        let updatedProgress = min(1.0, next.progress + deltaProgress)
        let moved = updatedProgress > next.progress
        next.progress = updatedProgress

        if next.progress >= 1.0 {
            next.progress = 1.0
            next.reachedEnd = true
            next.isPlaying = false
            next.reduceMotionAccumulator = 0
        } else {
            next.reachedEnd = false
        }

        return TickResult(state: next, didAdvance: moved)
    }
}

/// Pure AppKit-coordinate (bottom-left origin) placement for the separate Teleprompter reader window,
/// anchored below the top edge of the active display.
enum NotchTeleprompterWindowLayout {
    static func readerWindowFrame(
        size: CGSize = NotchTeleprompterLimits.defaultReaderSize,
        screenFrame: CGRect,
        visibleFrame: CGRect,
        topInset: CGFloat = 0,
        gapBelowTopEdge: CGFloat = NotchTeleprompterLimits.gapBelowTopEdge
    ) -> CGRect {
        let safeVisible = visibleFrame.width > 0 && visibleFrame.height > 0 ? visibleFrame : screenFrame
        guard safeVisible.width > 0, safeVisible.height > 0 else {
            return CGRect(origin: .zero, size: NotchTeleprompterLimits.minReaderSize)
        }

        let hMargin = NotchTeleprompterLimits.screenHorizontalMargin
        let bMargin = NotchTeleprompterLimits.screenBottomMargin
        let maxW = max(1, safeVisible.width - hMargin * 2)
        let maxH = max(1, safeVisible.height - gapBelowTopEdge - bMargin)

        let targetW = size.width.isFinite && size.width > 0 ? size.width : NotchTeleprompterLimits.defaultReaderSize.width
        let targetH = size.height.isFinite && size.height > 0 ? size.height : NotchTeleprompterLimits.defaultReaderSize.height
        let width = min(max(targetW, min(NotchTeleprompterLimits.minReaderSize.width, maxW)), maxW)
        let height = min(max(targetH, min(NotchTeleprompterLimits.minReaderSize.height, maxH)), maxH)

        let centerX = screenFrame.width > 0 ? screenFrame.midX : safeVisible.midX
        let rawX = (centerX - width / 2).rounded()
        let minX = safeVisible.minX + hMargin
        let maxX = max(minX, safeVisible.maxX - hMargin - width)
        let x = min(max(rawX, minX), maxX)

        let safeTopInset = topInset.isFinite && topInset > 0 ? topInset : 0
        let topAnchor = screenFrame.height > 0
            ? min(safeVisible.maxY, screenFrame.maxY - safeTopInset)
            : safeVisible.maxY
        let rawY = (topAnchor - gapBelowTopEdge - height).rounded()
        let minY = safeVisible.minY + bMargin
        let maxY = max(minY, safeVisible.maxY - height)
        let y = min(max(rawY, minY), maxY)

        return CGRect(x: x, y: y, width: width, height: height)
    }
}
