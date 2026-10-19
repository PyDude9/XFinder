import XCTest
import Foundation
import CoreGraphics

final class CaptureRulesTests: XCTestCase {

    // MARK: - CaptureShortcut.label ordering ⌃⌥⇧⌘ + key names

    func testLabelOrdersModifiersControlOptionShiftCommand() {
        // All four modifiers together must render in the fixed order ⌃⌥⇧⌘, never the order they were set.
        let s = CaptureShortcut(
            keyCode: 21,
            modifiers: CaptureShortcut.commandBit | CaptureShortcut.controlBit | CaptureShortcut.optionBit | CaptureShortcut.shiftBit
        )
        XCTAssertEqual(s.label, "⌃⌥⇧⌘4")
    }

    func testLabelShiftCommandOnly() {
        let s = CaptureShortcut(keyCode: 21, modifiers: CaptureShortcut.shiftBit | CaptureShortcut.commandBit)
        XCTAssertEqual(s.label, "⇧⌘4")
    }

    func testLabelDigitNames() {
        // kVK_ANSI_0...9
        let expectations: [Int: String] = [
            29: "0", 18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9",
        ]
        for (code, name) in expectations {
            let s = CaptureShortcut(keyCode: code, modifiers: CaptureShortcut.commandBit)
            XCTAssertEqual(s.label, "⌘\(name)", "keyCode \(code)")
        }
    }

    func testLabelLetterNames() {
        let s = CaptureShortcut(keyCode: 0, modifiers: CaptureShortcut.commandBit) // kVK_ANSI_A
        XCTAssertEqual(s.label, "⌘A")
        let z = CaptureShortcut(keyCode: 6, modifiers: CaptureShortcut.commandBit) // kVK_ANSI_Z
        XCTAssertEqual(z.label, "⌘Z")
    }

    func testLabelFKeyNames() {
        let f1 = CaptureShortcut(keyCode: 122, modifiers: CaptureShortcut.commandBit)
        XCTAssertEqual(f1.label, "⌘F1")
        let f12 = CaptureShortcut(keyCode: 111, modifiers: CaptureShortcut.commandBit)
        XCTAssertEqual(f12.label, "⌘F12")
    }

    func testLabelArrowNames() {
        let left = CaptureShortcut(keyCode: 123, modifiers: CaptureShortcut.commandBit)
        XCTAssertEqual(left.label, "⌘←")
        let up = CaptureShortcut(keyCode: 126, modifiers: CaptureShortcut.commandBit)
        XCTAssertEqual(up.label, "⌘↑")
    }

    func testLabelWithNoModifiers() {
        let s = CaptureShortcut(keyCode: 49, modifiers: 0) // Space
        XCTAssertEqual(s.label, "Space")
    }

    // MARK: - Carbon modifier mapping

    func testCarbonModifiersMapping() {
        let cmd = CaptureShortcut(keyCode: 0, modifiers: CaptureShortcut.commandBit)
        XCTAssertEqual(cmd.carbonModifiers, 256)
        let shift = CaptureShortcut(keyCode: 0, modifiers: CaptureShortcut.shiftBit)
        XCTAssertEqual(shift.carbonModifiers, 512)
        let option = CaptureShortcut(keyCode: 0, modifiers: CaptureShortcut.optionBit)
        XCTAssertEqual(option.carbonModifiers, 2048)
        let control = CaptureShortcut(keyCode: 0, modifiers: CaptureShortcut.controlBit)
        XCTAssertEqual(control.carbonModifiers, 4096)
        let all = CaptureShortcut(
            keyCode: 0,
            modifiers: CaptureShortcut.commandBit | CaptureShortcut.shiftBit | CaptureShortcut.optionBit | CaptureShortcut.controlBit
        )
        XCTAssertEqual(all.carbonModifiers, 256 | 512 | 2048 | 4096)
    }

    func testCarbonModifiersWithNoModifiersIsZero() {
        let s = CaptureShortcut(keyCode: 49, modifiers: 0)
        XCTAssertEqual(s.carbonModifiers, 0)
    }

    // MARK: - encode / decode round trip

    func testEncodeDecodeRoundTrip() {
        let original = CaptureShortcut(keyCode: 21, modifiers: CaptureShortcut.shiftBit | CaptureShortcut.commandBit)
        let encoded = original.encoded
        XCTAssertFalse(encoded.isEmpty)
        let decoded = CaptureShortcut.decode(encoded)
        XCTAssertEqual(decoded, original)
    }

    func testDecodeNilInput() {
        XCTAssertNil(CaptureShortcut.decode(nil))
    }

    func testDecodeGarbageInput() {
        XCTAssertNil(CaptureShortcut.decode("not json"))
        XCTAssertNil(CaptureShortcut.decode(""))
        XCTAssertNil(CaptureShortcut.decode("{}"))
    }

    func testDecodeMissingFieldFails() {
        XCTAssertNil(CaptureShortcut.decode(#"{"keyCode": 21}"#))
    }

    // MARK: - hasRequiredModifier

    func testHasRequiredModifierTrueForCommandOptionControl() {
        XCTAssertTrue(CaptureShortcut(keyCode: 0, modifiers: CaptureShortcut.commandBit).hasRequiredModifier)
        XCTAssertTrue(CaptureShortcut(keyCode: 0, modifiers: CaptureShortcut.optionBit).hasRequiredModifier)
        XCTAssertTrue(CaptureShortcut(keyCode: 0, modifiers: CaptureShortcut.controlBit).hasRequiredModifier)
    }

    func testHasRequiredModifierFalseForShiftAloneOrNone() {
        XCTAssertFalse(CaptureShortcut(keyCode: 0, modifiers: CaptureShortcut.shiftBit).hasRequiredModifier)
        XCTAssertFalse(CaptureShortcut(keyCode: 0, modifiers: 0).hasRequiredModifier)
    }

    // MARK: - conflict()

    func testConflictAnotherModeBeatsSystem() {
        // Both the system AND another mode use this shortcut; the mode conflict must win.
        let shortcut = CaptureRules.systemReserved[0].shortcut
        let assigned: [CaptureMode: CaptureShortcut] = [.window: shortcut]
        let result = CaptureRules.conflict(for: shortcut, mode: .area, assigned: assigned)
        XCTAssertEqual(result, .mode(.window))
    }

    func testConflictSystemReservedDetected() {
        let shortcut = CaptureRules.systemReserved[0].shortcut
        let result = CaptureRules.conflict(for: shortcut, mode: .area, assigned: [:])
        guard case let .system(nameKey)? = result else {
            return XCTFail("expected .system conflict")
        }
        XCTAssertEqual(nameKey, CaptureRules.systemReserved[0].nameKey)
    }

    func testConflictOwnModeIsNotAConflict() {
        // A mode's own already-assigned shortcut (not reserved by the system, not used by another mode) must
        // not be reported as a conflict against itself.
        let shortcut = CaptureShortcut(keyCode: 3, modifiers: CaptureShortcut.controlBit | CaptureShortcut.optionBit)
        let assigned: [CaptureMode: CaptureShortcut] = [.area: shortcut]
        let result = CaptureRules.conflict(for: shortcut, mode: .area, assigned: assigned)
        XCTAssertNil(result)
    }

    func testConflictOwnModeStillReportsASystemClash() {
        // The own-mode exemption only suppresses a `.mode` conflict against itself; if that same shortcut is
        // ALSO one macOS already reserves, that system clash is still a real, independent fact to surface.
        let shortcut = CaptureRules.systemReserved[0].shortcut
        let assigned: [CaptureMode: CaptureShortcut] = [.area: shortcut]
        let result = CaptureRules.conflict(for: shortcut, mode: .area, assigned: assigned)
        XCTAssertEqual(result, .system(nameKey: CaptureRules.systemReserved[0].nameKey))
    }

    func testConflictNoneWhenUnused() {
        let unusedShortcut = CaptureShortcut(keyCode: 3, modifiers: CaptureShortcut.controlBit | CaptureShortcut.optionBit)
        let result = CaptureRules.conflict(for: unusedShortcut, mode: .area, assigned: [:])
        XCTAssertNil(result)
    }

    // MARK: - screencaptureArguments

    func testScreencaptureArgumentsArea() {
        let args = CaptureRules.screencaptureArguments(mode: .area, output: "/tmp/out.png", sound: true, windowID: nil, display: 1)
        XCTAssertEqual(args, ["-i", "-t", "png", "/tmp/out.png"])
    }

    func testScreencaptureArgumentsAreaAnnotate() {
        let args = CaptureRules.screencaptureArguments(mode: .areaAnnotate, output: "/tmp/out.png", sound: true, windowID: nil, display: 1)
        XCTAssertEqual(args, ["-i", "-t", "png", "/tmp/out.png"])
    }

    func testScreencaptureArgumentsText() {
        let args = CaptureRules.screencaptureArguments(mode: .text, output: "/tmp/out.png", sound: true, windowID: nil, display: 1)
        XCTAssertEqual(args, ["-i", "-t", "png", "/tmp/out.png"])
    }

    func testScreencaptureArgumentsColor() {
        let args = CaptureRules.screencaptureArguments(mode: .color, output: "/tmp/out.png", sound: true, windowID: nil, display: 1)
        XCTAssertEqual(args, ["-i", "-t", "png", "/tmp/out.png"])
    }

    func testScreencaptureArgumentsWindowWithID() {
        let args = CaptureRules.screencaptureArguments(mode: .window, output: "/tmp/out.png", sound: true, windowID: 42, display: 1)
        XCTAssertEqual(args, ["-l", "42", "-t", "png", "/tmp/out.png"])
    }

    func testScreencaptureArgumentsWindowWithoutID() {
        let args = CaptureRules.screencaptureArguments(mode: .window, output: "/tmp/out.png", sound: true, windowID: nil, display: 1)
        XCTAssertEqual(args, ["-i", "-W", "-t", "png", "/tmp/out.png"])
    }

    func testScreencaptureArgumentsFullscreen() {
        let args = CaptureRules.screencaptureArguments(mode: .fullscreen, output: "/tmp/out.png", sound: true, windowID: nil, display: 2)
        XCTAssertEqual(args, ["-D", "2", "-t", "png", "/tmp/out.png"])
    }

    func testScreencaptureArgumentsSoundOffAddsDashX() {
        let args = CaptureRules.screencaptureArguments(mode: .area, output: "/tmp/out.png", sound: false, windowID: nil, display: 1)
        XCTAssertEqual(args, ["-i", "-t", "png", "-x", "/tmp/out.png"])
    }

    func testScreencaptureArgumentsOutputAlwaysLast() {
        let args = CaptureRules.screencaptureArguments(mode: .fullscreen, output: "/tmp/anywhere.png", sound: false, windowID: nil, display: 0)
        XCTAssertEqual(args.last, "/tmp/anywhere.png")
    }

    func testScreencaptureArgumentsNeverContainsDashOByDefault() {
        for mode in CaptureMode.allCases {
            let args = CaptureRules.screencaptureArguments(mode: mode, output: "/tmp/x.png", sound: true, windowID: 1, display: 0)
            XCTAssertFalse(args.contains("-o"), "mode \(mode) should never pass -o by default (keep window shadow)")
            XCTAssertFalse(args.contains("-T"), "mode \(mode) should never pass -T by default (no countdown)")
        }
    }

    func testWindowShadowOffAddsDashOForWindowShotsOnly() {
        for mode in CaptureMode.allCases {
            let args = CaptureRules.screencaptureArguments(mode: mode, output: "/tmp/x.png", sound: true, windowID: 1, display: 0, windowShadow: false)
            XCTAssertEqual(args.contains("-o"), mode == .window, "mode \(mode)")
        }
        let byID = CaptureRules.screencaptureArguments(mode: .window, output: "/tmp/x.png", sound: true, windowID: 42, display: 0, windowShadow: false)
        XCTAssertEqual(byID, ["-l", "42", "-o", "-t", "png", "/tmp/x.png"])
    }

    func testCountdownAppliesOnlyWhereNobodyPicksARegion() {
        XCTAssertEqual(CaptureRules.screencaptureArguments(mode: .fullscreen, output: "/tmp/x.png", sound: true, windowID: nil, display: 2, countdown: 3),
                       ["-D", "2", "-T", "3", "-t", "png", "/tmp/x.png"])
        XCTAssertEqual(CaptureRules.screencaptureArguments(mode: .window, output: "/tmp/x.png", sound: true, windowID: 7, display: 1, countdown: 5),
                       ["-l", "7", "-T", "5", "-t", "png", "/tmp/x.png"])
        for mode in [CaptureMode.area, .areaAnnotate, .text, .color] {
            let args = CaptureRules.screencaptureArguments(mode: mode, output: "/tmp/x.png", sound: true, windowID: nil, display: 1, countdown: 10)
            XCTAssertFalse(args.contains("-T"), "\(mode) has a selection step — the person decides when")
        }
        let noID = CaptureRules.screencaptureArguments(mode: .window, output: "/tmp/x.png", sound: true, windowID: nil, display: 1, countdown: 10)
        XCTAssertFalse(noID.contains("-T"), "a window picked by hand (-i -W) is a selection step too")
        XCTAssertFalse(CaptureRules.screencaptureArguments(mode: .fullscreen, output: "/tmp/x.png", sound: true, windowID: nil, display: 1, countdown: 0).contains("-T"))
        XCTAssertEqual(CaptureRules.countdownKey, "capture.countdown"); XCTAssertEqual(CaptureRules.windowShadowKey, "capture.windowShadow")
    }

    // MARK: - fileName

    func testFileNameFormat() {
        var components = DateComponents()
        components.year = 2026
        components.month = 10
        components.day = 13
        components.hour = 14
        components.minute = 32
        components.second = 10
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
        let date = calendar.date(from: components)!

        let name = CaptureRules.fileName(
            prefix: "Ảnh chụp",
            at: " lúc ",
            date: date,
            ext: "png",
            timeZone: TimeZone(identifier: "Asia/Ho_Chi_Minh")!
        )
        XCTAssertEqual(name, "Ảnh chụp 2026-10-13 lúc 14.32.10.png")
    }

    func testFileNameUses24HourClock() {
        // 14:32 must render as "14", never "02 PM" / "2".
        var components = DateComponents()
        components.year = 2026; components.month = 1; components.day = 1
        components.hour = 23; components.minute = 5; components.second = 9
        var calendar = Calendar(identifier: .gregorian)
        let tz = TimeZone(identifier: "UTC")!
        calendar.timeZone = tz
        let date = calendar.date(from: components)!
        let name = CaptureRules.fileName(prefix: "P", at: " at ", date: date, ext: "png", timeZone: tz)
        XCTAssertEqual(name, "P 2026-01-01 at 23.05.09.png")
    }

    func testFileNameZeroPadsEverySegment() {
        // A date with single-digit month/day/hour/minute/second must still pad to two digits everywhere.
        var components = DateComponents()
        components.year = 2026; components.month = 1; components.day = 2
        components.hour = 3; components.minute = 4; components.second = 5
        var calendar = Calendar(identifier: .gregorian)
        let tz = TimeZone(identifier: "UTC")!
        calendar.timeZone = tz
        let date = calendar.date(from: components)!
        let name = CaptureRules.fileName(prefix: "P", at: " at ", date: date, ext: "jpg", timeZone: tz)
        XCTAssertEqual(name, "P 2026-01-02 at 03.04.05.jpg")
    }

    // MARK: - uniqueName (keep-both)

    func testUniqueNameNoCollision() {
        XCTAssertEqual(CaptureRules.uniqueName("x.png", existing: []), "x.png")
    }

    func testUniqueNameSingleCollision() {
        XCTAssertEqual(CaptureRules.uniqueName("x.png", existing: ["x.png"]), "x 2.png")
    }

    func testUniqueNameMultipleCollisions() {
        let existing: Set<String> = ["x.png", "x 2.png", "x 3.png"]
        XCTAssertEqual(CaptureRules.uniqueName("x.png", existing: existing), "x 4.png")
    }

    func testUniqueNameCaseInsensitive() {
        // "X.PNG" already exists; "x.png" must still be treated as a collision.
        XCTAssertEqual(CaptureRules.uniqueName("x.png", existing: ["X.PNG"]), "x 2.png")
    }

    func testUniqueNameNoExtension() {
        XCTAssertEqual(CaptureRules.uniqueName("noext", existing: ["noext"]), "noext 2")
    }

    // MARK: - toPrune

    func testTopruneOldestFirstOut() {
        let old = CaptureItem(url: URL(fileURLWithPath: "/tmp/old.png"), date: Date(timeIntervalSince1970: 0), pixelWidth: 1, pixelHeight: 1)
        let mid = CaptureItem(url: URL(fileURLWithPath: "/tmp/mid.png"), date: Date(timeIntervalSince1970: 100), pixelWidth: 1, pixelHeight: 1)
        let new = CaptureItem(url: URL(fileURLWithPath: "/tmp/new.png"), date: Date(timeIntervalSince1970: 200), pixelWidth: 1, pixelHeight: 1)
        let pruned = CaptureRules.toPrune([new, mid, old], limit: 2)
        XCTAssertEqual(pruned, [old])
    }

    func testTopruneNoneWhenUnderLimit() {
        let a = CaptureItem(url: URL(fileURLWithPath: "/tmp/a.png"), date: Date(), pixelWidth: 1, pixelHeight: 1)
        XCTAssertEqual(CaptureRules.toPrune([a], limit: 50), [])
    }

    func testTopruneTiesBrokenByPath() {
        let sameDate = Date(timeIntervalSince1970: 0)
        let a = CaptureItem(url: URL(fileURLWithPath: "/tmp/b.png"), date: sameDate, pixelWidth: 1, pixelHeight: 1)
        let b = CaptureItem(url: URL(fileURLWithPath: "/tmp/a.png"), date: sameDate, pixelWidth: 1, pixelHeight: 1)
        // "a.png" sorts before "b.png" path-wise, so it is the one considered "oldest" when dates tie.
        let pruned = CaptureRules.toPrune([a, b], limit: 1)
        XCTAssertEqual(pruned, [b])
    }

    // MARK: - cardFrame

    func testCardFrameLeftEdge() {
        let visible = CGRect(x: 0, y: 0, width: 1728, height: 1080)
        let size = CGSize(width: 220, height: 150)
        let frame = CaptureRules.cardFrame(visible: visible, edge: .left, size: size, index: 0)
        XCTAssertEqual(frame.origin.x, 16)
        XCTAssertEqual(frame.origin.y, 16)
        XCTAssertEqual(frame.size, size)
    }

    func testCardFrameRightEdge() {
        let visible = CGRect(x: 0, y: 0, width: 1728, height: 1080)
        let size = CGSize(width: 220, height: 150)
        let frame = CaptureRules.cardFrame(visible: visible, edge: .right, size: size, index: 0)
        XCTAssertEqual(frame.origin.x, 1728 - 16 - 220)
        XCTAssertEqual(frame.origin.y, 16)
    }

    func testCardFrameStacksUpwardByIndex() {
        let visible = CGRect(x: 0, y: 0, width: 1728, height: 1080)
        let size = CGSize(width: 220, height: 150)
        let first = CaptureRules.cardFrame(visible: visible, edge: .left, size: size, index: 0)
        let second = CaptureRules.cardFrame(visible: visible, edge: .left, size: size, index: 1)
        XCTAssertEqual(second.origin.y, first.origin.y + size.height + 10)
        XCTAssertEqual(second.origin.x, first.origin.x)
    }

    func testCardFrameInsideVisible() {
        let visible = CGRect(x: 100, y: 50, width: 1000, height: 700)
        let size = CGSize(width: 220, height: 150)
        let frame = CaptureRules.cardFrame(visible: visible, edge: .left, size: size, index: 0)
        XCTAssertTrue(visible.contains(CGPoint(x: frame.minX, y: frame.minY)))
        XCTAssertEqual(frame.origin.x, visible.minX + 16)
        XCTAssertEqual(frame.origin.y, visible.minY + 16)
    }

    // MARK: - cardSize

    func testCardSizeSquareImage() {
        let size = CaptureRules.cardSize(pixelWidth: 1000, pixelHeight: 1000)
        XCTAssertEqual(size.width, 220)
        XCTAssertEqual(size.height, 220)
    }

    func testCardSizeClampsToMinimum() {
        // A very wide, short image should clamp the height to 90, not go below it.
        let size = CaptureRules.cardSize(pixelWidth: 2000, pixelHeight: 10)
        XCTAssertEqual(size.width, 220)
        XCTAssertEqual(size.height, 90)
    }

    func testCardSizeClampsToMaximum() {
        // A very tall, narrow image should clamp the height to 260, not exceed it.
        let size = CaptureRules.cardSize(pixelWidth: 10, pixelHeight: 2000)
        XCTAssertEqual(size.width, 220)
        XCTAssertEqual(size.height, 260)
    }

    func testCardSizeZeroWidthFallback() {
        let size = CaptureRules.cardSize(pixelWidth: 0, pixelHeight: 100)
        XCTAssertEqual(size.width, 220)
        XCTAssertEqual(size.height, 90)
    }

    // MARK: - CardCountdown

    func testCardCountdownBasicTicking() {
        let start = Date(timeIntervalSince1970: 0)
        let countdown = CardCountdown(total: 10, start: start)
        XCTAssertEqual(countdown.remaining(at: start), 10, accuracy: 0.001)
        XCTAssertEqual(countdown.remaining(at: start.addingTimeInterval(4)), 6, accuracy: 0.001)
        XCTAssertFalse(countdown.isExpired(at: start.addingTimeInterval(4)))
        XCTAssertTrue(countdown.isExpired(at: start.addingTimeInterval(10)))
    }

    func testCardCountdownNeverNegative() {
        let start = Date(timeIntervalSince1970: 0)
        let countdown = CardCountdown(total: 10, start: start)
        XCTAssertEqual(countdown.remaining(at: start.addingTimeInterval(1000)), 0)
    }

    func testCardCountdownPauseResume() {
        let start = Date(timeIntervalSince1970: 0)
        var countdown = CardCountdown(total: 10, start: start)
        // 2s elapse, then pause for 100s, then resume: only 2s should have counted against the total.
        countdown.pause(at: start.addingTimeInterval(2))
        XCTAssertTrue(countdown.isPaused)
        XCTAssertEqual(countdown.remaining(at: start.addingTimeInterval(102)), 8, accuracy: 0.001)
        countdown.resume(at: start.addingTimeInterval(102))
        XCTAssertFalse(countdown.isPaused)
        XCTAssertEqual(countdown.remaining(at: start.addingTimeInterval(104)), 6, accuracy: 0.001)
    }

    func testCardCountdownPauseIsIdempotent() {
        let start = Date(timeIntervalSince1970: 0)
        var countdown = CardCountdown(total: 10, start: start)
        countdown.pause(at: start.addingTimeInterval(1))
        countdown.pause(at: start.addingTimeInterval(50)) // should be ignored, already paused
        countdown.resume(at: start.addingTimeInterval(51))
        // Only (1s before pause) + (time after resume) counts; the pause window from 1s to 51s must not count.
        XCTAssertEqual(countdown.remaining(at: start.addingTimeInterval(52)), 10 - 1 - 1, accuracy: 0.001)
    }

    func testCardCountdownResumeWithoutPauseIsNoOp() {
        let start = Date(timeIntervalSince1970: 0)
        var countdown = CardCountdown(total: 10, start: start)
        countdown.resume(at: start.addingTimeInterval(5)) // never paused; must be a no-op
        XCTAssertEqual(countdown.remaining(at: start.addingTimeInterval(5)), 5, accuracy: 0.001)
    }

    func testCardCountdownNeverExpiresWhenTotalIsZero() {
        let start = Date(timeIntervalSince1970: 0)
        let countdown = CardCountdown(total: 0, start: start)
        XCTAssertFalse(countdown.isExpired(at: start.addingTimeInterval(1_000_000)))
        XCTAssertEqual(countdown.remaining(at: start.addingTimeInterval(5)), .infinity)
    }

    // MARK: - titleParts

    func testTitlePartsFormat() {
        var components = DateComponents()
        components.day = 13; components.month = 10
        components.hour = 14; components.minute = 32
        var calendar = Calendar(identifier: .gregorian)
        let tz = TimeZone(identifier: "UTC")!
        calendar.timeZone = tz
        let date = calendar.date(from: components)!
        let parts = CaptureRules.titleParts(date: date, timeZone: tz)
        XCTAssertEqual(parts.day, "13/10")
        XCTAssertEqual(parts.time, "14.32")
    }

    func testTitlePartsZeroPadsTime() {
        var components = DateComponents()
        components.day = 1; components.month = 1
        components.hour = 3; components.minute = 4
        var calendar = Calendar(identifier: .gregorian)
        let tz = TimeZone(identifier: "UTC")!
        calendar.timeZone = tz
        let date = calendar.date(from: components)!
        let parts = CaptureRules.titleParts(date: date, timeZone: tz)
        XCTAssertEqual(parts.time, "03.04")
    }

    // MARK: - oneNotchPreset / systemReserved sanity

    func testOneNotchPresetCoversFiveModesNotAreaAnnotate() {
        let preset = CaptureRules.oneNotchPreset
        XCTAssertEqual(preset[.area]?.label, "⇧⌘4")
        XCTAssertEqual(preset[.fullscreen]?.label, "⇧⌘3")
        XCTAssertEqual(preset[.window]?.label, "⇧⌘9")
        XCTAssertEqual(preset[.text]?.label, "⇧⌘2")
        XCTAssertEqual(preset[.color]?.label, "⇧⌘1")
        XCTAssertNil(preset[.areaAnnotate])
    }

    func testSystemReservedIsNonEmpty() {
        XCTAssertFalse(CaptureRules.systemReserved.isEmpty)
    }

    func testHistoryLimitAndChoicesAreStable() {
        XCTAssertEqual(CaptureRules.historyLimit, 50)
        XCTAssertEqual(CaptureRules.cardSecondsChoices, [5, 10, 30, 0])
    }
}
