import XCTest

/// Pins the **structure** of the gesture label sentences: which store key a value
/// resolves to, and how the pieces join.
///
/// Why this file exists at all — and it is the honest reason, not a nice-to-have:
/// the numbering and the heading assembly used to live in `Core/L10n.swift`, which
/// imports SwiftUI and therefore cannot be compiled into this package. A mutation
/// injected into either one stayed **green**:
///
///     M1 invented physical button names:       *** STAYED GREEN ***
///     M2 heading omits the held button:         *** STAYED GREEN ***
///     M5 button name drops the number offset:   *** STAYED GREEN ***
///
/// That is a hole in the gate, not merely a missing test — the harness was
/// reporting protection it did not have. Moving the structure into
/// `GestureLabelStructure.swift` (Foundation-only, symlinked here) is what makes
/// these assertions possible, and all three mutations now go red.
///
/// What is asserted here is structure. What the words *are* is asserted in
/// `L10nTests`, against the shipped store.
final class GestureLabelStructureTests: XCTestCase {

    // MARK: - Button numbering

    /// macOS numbers mouse buttons from 0; people count from 1. This is the single
    /// highest-value assertion in the gesture UI, because getting it wrong mislabels
    /// every button on the page — and the user reads those numbers to know which
    /// physical control to hold.
    func testButtonDisplayNumberIsOffsetByOne() {
        XCTAssertEqual(ButtonLabelStructure.displayNumber(forButtonNumber: 0), 1,
                       "macOS button 0 is the user's button 1 (left click)")
        XCTAssertEqual(ButtonLabelStructure.displayNumber(forButtonNumber: 1), 2)
        XCTAssertEqual(ButtonLabelStructure.displayNumber(forButtonNumber: 2), 3)
        // The offset must hold for every number, not just the first three.
        for n in 0...31 {
            XCTAssertEqual(ButtonLabelStructure.displayNumber(forButtonNumber: n), n + 1, "button \(n)")
        }
    }

    /// The three buttons every mouse shares carry a short factual note naming **where
    /// the button is**, because that is the question the user asked. Everything above
    /// them is the plain numbered form.
    ///
    /// These notes used to be Vietnamese sentences listed as "language-neutral" in
    /// `L10n.LanguageNeutralKeys`, which is why an English UI rendered "Bấm con lăn".
    /// They are ordinary translatable sentences now, and the assertion below pins the
    /// **key** rather than a rendered value.
    func testOnlyTheSharedButtonsHaveNamedKeys() {
        XCTAssertNotNil(ButtonLabelStructure.namedKey(forButtonNumber: 0))
        XCTAssertNotNil(ButtonLabelStructure.namedKey(forButtonNumber: 1))
        XCTAssertNotNil(ButtonLabelStructure.namedKey(forButtonNumber: 2))
        // Code 2 is the wheel press, and the note must say that and nothing invented.
        XCTAssertEqual(ButtonLabelStructure.namedKey(forButtonNumber: 2),
                       "Bấm con lăn xuống")
        // A side button must NOT be given a nickname: no API can confirm its position.
        for n in [3, 4, 5, 7, 31] {
            XCTAssertNil(ButtonLabelStructure.namedKey(forButtonNumber: n),
                         "button \(n) must use the plain numbered form, not a nickname")
        }
    }

    /// The side-button **hint** is a separate, deliberately hedged sentence. It may
    /// say "usually", and it must never be presented as a measured position.
    func testSideButtonsCarryAHedgedHintNotAClaim() {
        XCTAssertNil(ButtonLabelStructure.hintKey(forButtonNumber: 2),
                     "the wheel is named directly, so it needs no hint")
        let up = ButtonLabelStructure.hintKey(forButtonNumber: 3)
        XCTAssertNotNil(up, "button 3 is the default hold trigger and must be locatable")
        XCTAssertTrue(up?.contains("thường là") == true,
                      "a position no API can confirm must be hedged, not asserted")
        XCTAssertNotNil(ButtonLabelStructure.hintKey(forButtonNumber: 4))
        XCTAssertNil(ButtonLabelStructure.hintKey(forButtonNumber: 12),
                     "no hint is invented for buttons we cannot even guess at")
    }

    /// The numbered form is assembled from a **fragment plus a runtime value**. The
    /// fragment keeps its trailing space; the number is appended. If the offset moves
    /// into the fragment, the key stops being a key.
    func testNumberedFormIsAFragmentPlusARuntimeValue() {
        XCTAssertEqual(ButtonLabelStructure.numberedPrefixKey, "Nút ",
                       "the prefix is a fragment and must keep its trailing space")
        // It is a fragment because it is concatenated — a leading/trailing space is
        // the whole point, not an accident.
        XCTAssertNotEqual(ButtonLabelStructure.numberedPrefixKey,
                          ButtonLabelStructure.numberedPrefixKey.trimmingCharacters(in: .whitespaces))
    }

    // MARK: - Heading assembly

    /// A hold direction's heading is **two parts**: the held button and the motion.
    /// Both must be present, and the button must be a lookup key rather than a
    /// value-bearing string.
    func testHoldDirectionHeadingHasBothHalves() {
        for direction in [GestureDirection.up, .down, .left, .right] {
            let parts = ButtonLabelStructure.HeadingStructure.parts(
                for: direction, trigger: .mouseButton(2))
            XCTAssertEqual(parts.motionKey, direction.motionHintKey, direction.rawValue)
            XCTAssertFalse(parts.motionKey.isEmpty, "\(direction) has no motion half")
            XCTAssertEqual(parts.buttonKey, "Bấm con lăn xuống",
                           "\(direction) must name the held button")
            XCTAssertNil(parts.appendNumber,
                         "the shared buttons resolve to a whole key, not a prefix + number")
        }
    }

    /// A button above the three shared ones uses the prefix fragment plus an appended
    /// number — and the number is the **user-facing** one, not the macOS code.
    func testUnnamedButtonHeadingCarriesTheDisplayNumber() {
        let parts = ButtonLabelStructure.HeadingStructure.parts(
            for: .up, trigger: .mouseButton(3))
        XCTAssertEqual(parts.buttonKey, ButtonLabelStructure.numberedPrefixKey)
        XCTAssertEqual(parts.appendNumber, 4,
                       "macOS button 3 is the user's button 4 — the heading must say 4")
    }

    /// Tilt is performed without holding a button, so its heading has no button half
    /// at all. Asserting a button there would tell the user to hold something that
    /// plays no part in the gesture.
    func testTiltHeadingHasNoButtonHalf() {
        for direction in [GestureDirection.tiltLeft, .tiltRight] {
            let parts = ButtonLabelStructure.HeadingStructure.parts(
                for: direction, trigger: .mouseButton(2))
            XCTAssertNil(parts.buttonKey,
                         "\(direction) is performed without holding a button")
            XCTAssertNil(parts.appendNumber)
            XCTAssertEqual(parts.motionKey, direction.titleKey)
        }
    }

    /// A modifier trigger is not a button, so it contributes no button half and no
    /// number — and the motion half is still present, so the heading is not empty.
    func testModifierTriggerHasNoButtonHalfButKeepsTheMotion() {
        for flags in [GestureShortcut.control, GestureShortcut.option,
                      GestureShortcut.command, GestureShortcut.shift] {
            let parts = ButtonLabelStructure.HeadingStructure.parts(
                for: .left, trigger: .modifierKey(flags))
            XCTAssertNil(parts.buttonKey, "a modifier is not a button")
            XCTAssertNil(parts.appendNumber, "a modifier has no button number")
            XCTAssertEqual(parts.motionKey, "kéo sang trái")
        }
    }

    /// Every hold direction must produce a **distinct** motion half, or two arrows in
    /// the diagram would carry the same caption and the diagram could not be read.
    func testEveryHoldDirectionHasADistinctMotionHalf() {
        var seen = Set<String>()
        for direction in [GestureDirection.up, .down, .left, .right] {
            let parts = ButtonLabelStructure.HeadingStructure.parts(
                for: direction, trigger: .mouseButton(2))
            XCTAssertTrue(seen.insert(parts.motionKey).inserted,
                          "\(direction) shares a motion half with another direction")
        }
        XCTAssertEqual(seen.count, 4)
    }

    /// The separator is language-neutral punctuation, and it must be non-empty — an
    /// empty separator would run the button name into the motion ("Button 3pull up").
    func testHeadingSeparatorIsPresentAndLanguageNeutral() {
        XCTAssertFalse(ButtonLabelStructure.HeadingStructure.separator.isEmpty)
        XCTAssertEqual(ButtonLabelStructure.HeadingStructure.separator, ": ")
        // It must contain no letters, or it would need translating.
        XCTAssertNil(ButtonLabelStructure.HeadingStructure.separator
            .rangeOfCharacter(from: .letters),
                     "the separator must need no translation")
    }

    /// **L1, pinned at the structure level.** The button number must not appear in
    /// the motion half. If it did, a heading assembled per arm would print the same
    /// number on all four arms — which is exactly what the user reported reading as
    /// "all four buttons are Button 3".
    func testMotionHalfNeverCarriesTheButtonNumber() {
        for direction in GestureDirection.allCases {
            let motion = GestureTriggerKind.isTilt(direction)
                ? direction.titleKey
                : direction.motionHintKey
            XCTAssertFalse(motion.contains("Nút"),
                           "\(direction.rawValue) motion half names a button: \(motion)")
            XCTAssertFalse(motion.contains("Button"),
                           "\(direction.rawValue) motion half names a button: \(motion)")
        }
    }

    // MARK: - The compact form drawn on the diagram (PATCH v9.1 R2)

    /// The chip form is the bare user-facing number, and it goes through
    /// `displayNumber(forButtonNumber:)` rather than doing its own `+ 1`.
    ///
    /// A second copy of the offset is the hazard: `displayNumber(forButtonNumber:)`
    /// already exists and was wrong once, so the chip path must use it. The named form is
    /// deliberately **not** used here — `Bấm con lăn xuống` is 17 characters and cannot fit
    /// a 46 pt chip, which is a measured width limit, not a preference.
    func testChipLabelIsTheBareNumberAndSharesTheOneOffset() {
        for code in 0...31 {
            XCTAssertEqual(ButtonLabelStructure.compactLabel(forButtonNumber: code),
                           ButtonLabel(key: ButtonLabelStructure.numberedPrefixKey,
                                       appendNumber: ButtonLabelStructure.displayNumber(forButtonNumber: code)),
                           "chip label for button \(code)")
        }
        // Named forms still exist for the list, the tooltips and the detail heading.
        XCTAssertEqual(ButtonLabelStructure.compactLabel(forButtonNumber: 0).appendNumber, 1)
        XCTAssertEqual(ButtonLabelStructure.compactLabel(forButtonNumber: 2).appendNumber, 3)
        XCTAssertEqual(ButtonLabelStructure.compactLabel(forButtonNumber: 5).appendNumber, 6)
        XCTAssertNotNil(ButtonLabelStructure.namedKey(forButtonNumber: 2),
                        "the descriptive name is still the one the list prints")
    }

    /// The chip form drops the positional hint and the descriptive name, and that is the
    /// whole reason it is a separate function: the hint is a sentence and the Vietnamese
    /// wheel name is 17 characters, neither of which fits a 46 pt chip. Nothing is lost,
    /// because the full form is still what the Assigned-buttons list and the tooltips print.
    func testChipLabelDropsTheHintTheFullLabelKeeps() {
        for code in [3, 4] {
            let hint = ButtonLabelStructure.hintKey(forButtonNumber: code)
            XCTAssertNotNil(hint, "precondition: \(code) has a hint to drop")
            let chip = ButtonLabelStructure.compactLabel(forButtonNumber: code)
            XCTAssertEqual(chip.key, ButtonLabelStructure.numberedPrefixKey)
            XCTAssertNotEqual(chip.key, hint,
                              "the chip form must use the fragment, never the hint")
        }
        for code in [0, 1, 2] {
            let named = ButtonLabelStructure.namedKey(forButtonNumber: code)
            XCTAssertNotNil(named, "precondition: \(code) has a descriptive name")
            XCTAssertNotEqual(ButtonLabelStructure.compactLabel(forButtonNumber: code).key,
                              named,
                              "the chip is a number; the name belongs to the full-width rows")
        }
    }

    /// A key that renders a number must never be the prefix used for the interpolated
    /// case — if it were, the chip would print “Nút 4” and then append another 4.
    func testChipNumberedFormUsesTheFragmentSoTheNumberIsAppendedOnce() {
        let chip = ButtonLabelStructure.compactLabel(forButtonNumber: 3)
        XCTAssertEqual(chip.key, ButtonLabelStructure.numberedPrefixKey)
        // The fragment carries its trailing space on purpose: without it the join would
        // read "Nút4".
        XCTAssertTrue(chip.key.hasSuffix(" "), "the fragment must keep its trailing space")
        XCTAssertFalse(chip.key.contains("4"),
                       "a key containing a runtime value can never be looked up")
    }
}
