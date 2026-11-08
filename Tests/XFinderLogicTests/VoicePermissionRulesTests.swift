import XCTest

/// XF-VOICE-PERMISSIONS — what one dictation press does about Microphone and Speech Recognition, and how the Voice page
/// labels them. Every expectation below is written out by hand, not derived from the rule under test.
final class VoicePermissionRulesTests: XCTestCase {
    typealias R = VoicePermissionRules

    /// All sixteen (microphone, speech) pairs. a = authorized, n = notDetermined, d = denied, r = restricted.
    private let table: [(VoicePermissionStatus, VoicePermissionStatus, VoiceActivationDecision)] = [
        (.authorized, .authorized, .start),
        (.authorized, .notDetermined, .ask([.speechRecognition])),
        (.authorized, .denied, .blocked(.speechRecognition, restricted: false)),
        (.authorized, .restricted, .blocked(.speechRecognition, restricted: true)),

        (.notDetermined, .authorized, .ask([.microphone])),
        (.notDetermined, .notDetermined, .ask([.microphone, .speechRecognition])),
        // A refused Speech Recognition means dictation cannot work: the microphone is not prompted for nothing.
        (.notDetermined, .denied, .blocked(.speechRecognition, restricted: false)),
        (.notDetermined, .restricted, .blocked(.speechRecognition, restricted: true)),

        (.denied, .authorized, .blocked(.microphone, restricted: false)),
        (.denied, .notDetermined, .blocked(.microphone, restricted: false)),
        (.denied, .denied, .blocked(.microphone, restricted: false)),
        (.denied, .restricted, .blocked(.microphone, restricted: false)),

        (.restricted, .authorized, .blocked(.microphone, restricted: true)),
        (.restricted, .notDetermined, .blocked(.microphone, restricted: true)),
        (.restricted, .denied, .blocked(.microphone, restricted: true)),
        (.restricted, .restricted, .blocked(.microphone, restricted: true)),
    ]

    func testEveryStatusPairDecidesAsSpecified() {
        for (mic, speech, expected) in table {
            XCTAssertEqual(R.decide(microphone: mic, speech: speech), expected, "mic \(mic), speech \(speech)")
        }
    }

    func testTheTableCoversEveryPair() {
        let pairs = Set(table.map { "\($0.0)|\($0.1)" })
        XCTAssertEqual(pairs.count, VoicePermissionStatus.allCases.count * VoicePermissionStatus.allCases.count)
    }

    func testARefusedPermissionIsNeverAskedAgain() {
        for (mic, speech, decision) in table where mic.isRefused || speech.isRefused {
            if case .ask = decision { XCTFail("asks while refused: mic \(mic), speech \(speech)") }
            if case .start = decision { XCTFail("starts while refused: mic \(mic), speech \(speech)") }
        }
    }

    func testOnlyAuthorizedAndUndecidedCountAsNotRefused() {
        XCTAssertFalse(VoicePermissionStatus.authorized.isRefused)
        XCTAssertFalse(VoicePermissionStatus.notDetermined.isRefused)
        XCTAssertTrue(VoicePermissionStatus.denied.isRefused)
        XCTAssertTrue(VoicePermissionStatus.restricted.isRefused)
    }

    // MARK: Words

    func testEachBlockedLineNamesExactlyItsPermissionAndCase() throws {
        let store = try L10nFixture.load()
        let lines = [
            (VoicePermissionKind.microphone, false, "Micro", "từ chối", "Microphone", "denied"),
            (.microphone, true, "Micro", "giới hạn", "Microphone", "restricted"),
            (.speechRecognition, false, "Nhận dạng giọng nói", "từ chối", "Speech Recognition", "denied"),
            (.speechRecognition, true, "Nhận dạng giọng nói", "giới hạn", "Speech Recognition", "restricted"),
        ]
        var seen = Set<String>()
        for (kind, restricted, viName, viCase, enName, enCase) in lines {
            let key = R.blockedMessageKey(kind, restricted: restricted)
            XCTAssertTrue(seen.insert(key).inserted, "two cases share one line: \(key)")
            XCTAssertTrue(key.contains(viName) && key.contains(viCase), key)
            let en = try XCTUnwrap(store.entries[key]?.en, "\(key) is not in L10n.strings.json")
            XCTAssertTrue(en.contains(enName) && en.contains(enCase), en)
        }
        XCTAssertFalse(R.blockedMessageKey(.microphone, restricted: false).contains("Nhận dạng"),
                       "the microphone line must not mention Speech Recognition")
    }

    func testRowButtonsMatchWhatMacOSStillAllows() {
        XCTAssertNil(R.rowActionKey(.authorized))
        XCTAssertEqual(R.rowActionKey(.notDetermined), "Yêu cầu")
        XCTAssertEqual(R.rowActionKey(.denied), "Mở Cài đặt hệ thống", "a refused permission is changed only in the pane")
        XCTAssertNil(R.rowActionKey(.restricted), "restricted: nothing the user can change from XFinder")
    }

    func testRowStatusesAreDistinct() {
        XCTAssertEqual(R.rowStatusKey(.authorized), "Đã cấp")
        XCTAssertEqual(R.rowStatusKey(.denied), "Đã từ chối")
        XCTAssertEqual(Set(VoicePermissionStatus.allCases.map(R.rowStatusKey)).count, VoicePermissionStatus.allCases.count)
    }

    func testEveryKeyIsInTheStoreWithAnEnglishLine() throws {
        let store = try L10nFixture.load()
        XCTAssertGreaterThanOrEqual(R.allKeys.count, 10)
        for key in R.allKeys {
            let entry = store.entries[key]
            XCTAssertNotNil(entry, "\(key.debugDescription) is not in L10n.strings.json")
            if let entry {
                XCTAssertFalse(entry.en.isEmpty, key)
                XCTAssertNotEqual(entry.en, key, key)
            }
        }
    }

    /// The HUD shows these on ONE line, 13 pt medium, 350 pt wide. Measured with AppKit (2026-11-08, positive control
    /// overflowing at 575 pt): the longest line here is 301.5 pt at 47 characters. The character cap is the guard a test
    /// without AppKit can hold; a longer line must be re-measured, not just let through.
    func testHUDLinesStayShortEnoughForOneLine() throws {
        let store = try L10nFixture.load()
        var hud = [R.grantedNoticeKey]
        for kind in VoicePermissionKind.allCases {
            hud.append(R.blockedMessageKey(kind, restricted: false))
            hud.append(R.blockedMessageKey(kind, restricted: true))
        }
        for key in hud {
            XCTAssertLessThanOrEqual(key.count, 50, key)
            XCTAssertLessThanOrEqual(try XCTUnwrap(store.entries[key]?.en).count, 50, key)
        }
    }
}
