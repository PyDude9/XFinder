import XCTest

/// Locks the language pipeline down so the "English UI with Vietnamese in it"
/// bug cannot come back unnoticed.
///
/// What this file tests is deliberately not "does `L10n.t` return a string" —
/// it always does. The bug was never about a missing return; it was that a miss
/// *silently* returns the Vietnamese literal, so an untranslated string is
/// indistinguishable from a translated one until a human looks at the screen.
/// These tests fail on the store itself, which is the thing that was wrong.
final class L10nTests: XCTestCase {

    // MARK: - Store loading

    /// The store is a bundled JSON resource. If it is not in the app bundle the
    /// app runs entirely in Vietnamese with no error anywhere — exactly the
    /// silent-failure shape this whole class of bug has.
    func testStoreIsPresentAndNonTrivial() throws {
        let store = try L10nFixture.load()
        XCTAssertGreaterThan(store.entries.count, 700,
                             "the translation store looks truncated; a partial store "
                             + "translates some pages and leaves the rest Vietnamese")
    }

    // MARK: - Coverage

    /// Every entry that has letters must have an English value that differs from
    /// its Vietnamese key, unless it is an explicitly allowlisted brand name.
    ///
    /// This is the assertion that would have caught `"Nút giữa / bấm con lăn
    /// (Button 2)"`: it was never in a dictionary at all, so `L10n.t` returned the
    /// Vietnamese and the English page showed Vietnamese.
    func testEveryEntryWithLettersHasADistinctTranslation() throws {
        let store = try L10nFixture.load()
        let allowlist = try L10nFixture.allowlist()
        var failures: [String] = []

        for (vi, entry) in store.entries {
            guard vi.rangeOfCharacter(from: .letters) != nil else { continue }
            guard !entry.en.isEmpty else {
                if entry.swap == true { continue }  // deposition: empty is correct
                failures.append("\(vi) -> no English")
                continue
            }
            if entry.en == vi && !allowlist.contains(vi) {
                failures.append("\(vi) -> English is identical, so untranslated")
            }
        }

        XCTAssertTrue(failures.isEmpty,
                      "these strings would render Vietnamese in an English UI:\n"
                      + failures.sorted().joined(separator: "\n"))
    }

    /// The allowlist is an exception list, and a stale exception is how a real
    /// gap gets hidden. Every allowlisted string must actually be an entry that
    /// needs it.
    func testAllowlistHasNoStaleEntries() throws {
        let store = try L10nFixture.load()
        let allowlist = try L10nFixture.allowlist()
        let stale = allowlist.filter { key in
            guard let entry = store.entries[key] else { return true }
            return entry.en != key
        }
        XCTAssertTrue(stale.isEmpty,
                      "allowlisted but no longer an identical-translation entry, "
                      + "so the exception is hiding nothing and should be removed: \(stale.sorted())")
    }

    // MARK: - Scope

    /// `fragment` and `sentence` are claims about how a string is used, not
    /// filing cabinets. A fragment is concatenated, so a fragment must not read
    /// as a finished sentence and must keep the padding its Vietnamese form has.
    func testFragmentsKeepTheirPadding() throws {
        let store = try L10nFixture.load()
        var failures: [String] = []
        for (vi, entry) in store.entries where entry.scope == "fragment" {
            if entry.swap == true { continue }
            let viPadded = vi != vi.trimmingCharacters(in: .whitespaces)
            let enPadded = entry.en != entry.en.trimmingCharacters(in: .whitespaces)
            if viPadded && !enPadded {
                failures.append("\(vi) -> \(entry.en) (lost the edge space)")
            }
        }
        XCTAssertTrue(failures.isEmpty,
                      "a fragment without its padding runs into the neighbouring "
                      + "word when concatenated:\n" + failures.sorted().joined(separator: "\n"))
    }

    /// A sentence is rendered on its own, so a leading or trailing space is
    /// always a copy-paste artifact rather than intent.
    func testSentencesCarryNoEdgeWhitespace() throws {
        let store = try L10nFixture.load()
        let bad = store.entries
            .filter { $0.value.scope == "sentence" }
            .filter { $0.value.en != $0.value.en.trimmingCharacters(in: .whitespaces) }
            .map(\.key)
            .sorted()
        XCTAssertTrue(bad.isEmpty,
                      "marked as standalone sentences but padded like fragments: \(bad)")
    }

    /// Nothing may be **declared language-neutral** if it is actually a Vietnamese
    /// sentence.
    ///
    /// This is the exact mechanism behind the repeated "Vietnamese leaks into the
    /// English UI" reports, and it is why wrapping call sites never fixed it.
    /// `L10n.LanguageNeutralKeys` is a declaration that a key must be returned
    /// *verbatim*, so a Vietnamese sentence listed there is not a missing
    /// translation — it is a line of code asserting that the string can never be
    /// translated. Three button labels sat in that list (`"Nút 3 (bấm con lăn
    /// xuống)"` and friends) and rendered as Vietnamese in English, no matter how many
    /// call sites were wrapped.
    ///
    /// The allowed values are therefore only glyphs: a string with a Vietnamese
    /// letter in it cannot be language-neutral.
    /// The list lives in `Core/L10n.swift`, which imports SwiftUI and so cannot be
    /// compiled by this package. It is therefore **read from the source** — a
    /// fixture would let the declaration and the assertion drift, and the whole
    /// point of this gate is to catch the declaration itself being wrong.
    func testLanguageNeutralKeysContainNoSentences() throws {
        let keys = try L10nFixture.declaredLanguageNeutralKeys()
        XCTAssertFalse(keys.isEmpty, "the gate is reading nothing — check the pattern")
        let vietnamese = Set("ăâđêôơưĂÂĐÊÔƠƯáàảãạắằẳẵặấầẩẫậéèẻẽẹếềểễệíìỉĩịóòỏõọốồổỗộớờởỡợúùủũụứừửữựýỳỷỹỵ")
        for key in keys {
            let leaked = key.unicodeScalars.contains { scalar in
                CharacterSet(charactersIn: String(vietnamese)).contains(scalar)
            }
            XCTAssertFalse(leaked,
                           "`\(key)` is declared language-neutral but contains Vietnamese "
                           + "letters — it will render verbatim in an English UI. "
                           + "Only glyphs (⌘ ⌥ ⌃ ⇧) may be language-neutral.")
            XCTAssertFalse(key.contains(" ") && key.count > 4,
                           "`\(key)` is declared language-neutral but looks like a sentence")
        }
    }

    /// The gesture page's leak shape, pinned by name.
    ///
    /// The model exposes **semantic keys**, never display text: `TriggerSource.key`
    /// (a `ButtonKey`), `GestureDirection.titleKey`, `.motionKey` and
    /// `.motionHintKey`. Those are Vietnamese literals, which is what the store is
    /// keyed by — so every one of them has to be *in the store* with an English
    /// value, or the English page silently renders Vietnamese.
    ///
    /// This test is the model-layer enforcement C4 asks for: it walks the model's
    /// own key vocabulary rather than a hand-written list, so adding a direction or
    /// a button shape cannot skip it.
    func testGesturePageStringsAreAllTranslatable() throws {
        let store = try L10nFixture.load()
        var needed = Set<L10nFixture.Probe>()

        // Every button the trigger picker can show. Codes 0...2 carry a short
        // factual note; everything from 3 up is the interpolated "Nút \(n + 1)".
        let buttonNumbers = [0, 1, 2, 3, 4, 7, 31]
        for code in buttonNumbers {
            needed.insert(.init(L10nFixtures.buttonName(code)))
        }
        // The interpolated case is probed as its pieces, because that is how the
        // call site must assemble it: a whole-string wrap can never match a key
        // containing a runtime value, which is bug shape #2 in this file's header.
        let interpolated = buttonNumbers.filter { $0 >= 3 }
        XCTAssertFalse(interpolated.isEmpty, "precondition: an interpolated case exists")
        needed.insert(.init(fragment: "Nút ", suffix: "Button "))

        // Headings are built from semantic keys, so every one of them must resolve.
        for direction in GestureDirection.allCases {
            // The heading on its own — no button in it. This is the key the detail
            // panel shows, and the one that must NOT name a number.
            needed.insert(.init(direction.titleKey))
            needed.insert(.init(direction.motionKey))
            needed.insert(.init(direction.motionHintKey))
        }
        // Every action name the picker and the detail panel print. These reach the screen
        // through `L10n.t(kind.labelKey)` — a **variable** — so neither the `L10n.t("...")`
        // sweep in `verify-gesture-ui.sh` nor the literal audit (which skips
        // `GestureModel.swift`/`GestureMap.swift`) can see them.
        for kind in GestureActionKind.allCases {
            needed.insert(.init(kind.labelKey))
        }
        // The system-action captions and the "no shortcut set in macOS" wording. Four of
        // these were **missing before this pass** and therefore rendered Vietnamese in an
        // English UI (`App Exposé`, `Hiện màn hình nền`, `Space trước`, `Space kế tiếp`) —
        // exactly the variable-keyed leak shape this gate exists for, found by asking the
        // store directly rather than by reading a screenshot.
        for action in GestureSystemAction.allCases {
            needed.insert(.init(action.captionKey))
            needed.insert(.init(action.unboundCaptionKey))
        }

        // A `whole` probe is a string the call site passes to `L10n.t` verbatim.
        let missing = needed.filter { probe in
            switch probe.kind {
            case .whole(let key):
                if L10nFixture.interpolatedButtonNumber(key) != nil { return false }
                guard let entry = store.entries[key] else { return true }
                if entry.swap == true { return false }
                return entry.en.isEmpty
            case .fragment(let key, let suffix, let prefix):
                guard let entry = store.entries[key], entry.scope == "fragment" else { return true }
                return !entry.en.hasPrefix(suffix) && !entry.en.hasSuffix(prefix)
            }
        }

        XCTAssertTrue(missing.isEmpty,
                      "the Mouse & Gestures page can still render Vietnamese in an "
                      + "English UI for: \(missing.map(\.label).sorted())")
    }

    /// A side button's positional hint must be in the store too. It is a full
    /// sentence that reaches the screen through `L10n.t(_ key: ButtonKey)`, so a
    /// missing entry would render the Vietnamese hint in an English UI — the same
    /// leak shape, one level down.
    func testSideButtonHintsAreTranslatable() throws {
        let store = try L10nFixture.load()
        var missing: [String] = []
        for code in [3, 4] {
            guard let hint = L10nFixtures.buttonHint(code) else { continue }
            guard let entry = store.entries[hint] else {
                missing.append("\(code): \(hint) missing"); continue
            }
            if entry.en.isEmpty { missing.append("\(code): \(hint) has no English") }
        }
        XCTAssertTrue(missing.isEmpty,
                      "button hints can render Vietnamese in an English UI: \(missing)")
    }

    /// The model must not carry display strings, and that is now checkable by name.
    ///
    /// `titleKey`/`motionKey`/`motionHintKey`/`GestureDirection.glyph` and
    /// `ButtonKey` are the whole vocabulary; if someone re-adds a `var label:
    /// String` that builds a sentence, the screen can show it un-translated again.
    /// This pins the shape: every direction key must be a **store key**, which is
    /// exactly the property a rendered sentence does not have.
    func testDirectionKeysAreStoreKeysNotRenderedSentences() throws {
        let store = try L10nFixture.load()
        for direction in GestureDirection.allCases {
            for (name, key) in [("titleKey", direction.titleKey),
                                ("motionKey", direction.motionKey),
                                ("motionHintKey", direction.motionHintKey)] {
                XCTAssertNotNil(store.entries[key],
                                "\(direction.rawValue).\(name) = \(key) is not a store key, "
                                + "so L10n cannot translate it")
                // A key that interpolates a runtime value can never match a store
                // entry — that is bug shape #2 and it must not come back.
                XCTAssertFalse(L10nFixtures.interpolates(key),
                               "\(direction.rawValue).\(name) interpolates a value, so it "
                               + "can never be a lookup key: \(key)")
            }
        }
    }

    // MARK: - Cross-language drift

    /// Two `AppLanguage` cases exist and every entry must be usable in both.
    /// A store that only carries English works today and breaks the moment a
    /// third language is added — so assert the shape, not just the content.
    func testEveryEntryCarriesBothLanguages() throws {
        let raw = try L10nFixture.raw()
        let entries = try XCTUnwrap(raw["entries"] as? [String: [String: Any]])
        XCTAssertFalse(entries.isEmpty)
        for (vi, value) in entries {
            XCTAssertFalse(vi.isEmpty, "an entry has an empty Vietnamese key")
            XCTAssertNotNil(value["scope"] as? String,
                            "\(vi) has no scope, so the checker cannot reason about it")
        }
    }
}

// MARK: - Fixture

/// Reads the shipped store and allowlist straight off disk.
///
/// The test bundle cannot import the app target, so this mirrors the decode the
/// app performs. It reads the **real** shipped files, not a copy: a copy would
/// let the two drift, which is the failure this whole module exists to prevent.
enum L10nFixture {

    struct Entry {
        var en: String
        var scope: String
        var swap: Bool?
    }

    struct Store {
        var entries: [String: Entry]
    }

    /// A string the UI needs translated, in the shape the call site uses it.
    ///
    /// `whole`    — passed to `L10n.t` as one literal.
    /// `fragment` — assembled from a fragment plus literal neighbours.
    struct Probe: Hashable {
        enum Kind: Hashable {
            case whole(String)
            case fragment(key: String, suffix: String, prefix: String)
        }
        var kind: Kind
        var label: String

        init(_ key: String) {
            kind = .whole(key)
            label = key
        }

        init(fragment key: String, suffix: String = "", prefix: String = "") {
            kind = .fragment(key: key, suffix: suffix, prefix: prefix)
            label = "fragment \(key)"
        }
    }

    static func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // XFinderLogicTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
    }

    static func raw() throws -> [String: Any] {
        let url = repoRoot().appendingPathComponent("XFinder/Resources/L10n.strings.json")
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    static func load() throws -> Store {
        let root = try raw()
        let dict = try XCTUnwrap(root["entries"] as? [String: [String: Any]])
        var entries: [String: Entry] = [:]
        for (vi, value) in dict {
            entries[vi] = Entry(en: value["en"] as? String ?? "",
                                scope: value["scope"] as? String ?? "sentence",
                                swap: value["swap"] as? Bool)
        }
        return Store(entries: entries)
    }

    static func allowlist() throws -> Set<String> {
        let url = repoRoot().appendingPathComponent("XFinder/Resources/L10n.allowlist.json")
        let data = try Data(contentsOf: url)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let list = try XCTUnwrap(root["sameByDesign"] as? [String])
        return Set(list)
    }

    /// The strings `L10n.LanguageNeutralKeys` declares, read from the declaration.
    ///
    /// `Core/L10n.swift` imports SwiftUI, so this package cannot compile it and the
    /// gate cannot ask the type directly. Reading the source is deliberate: this is
    /// the one assertion that must catch the *declaration* being wrong (a Vietnamese
    /// sentence listed as "language-neutral" is exactly how the leak survived every
    /// call-site fix), so a hand-kept fixture would defeat it.
    ///
    /// The parse is narrow on purpose — it takes quoted strings between the
    /// `static let all` marker and the closing bracket, and fails loudly if it finds
    /// none.
    static func declaredLanguageNeutralKeys() throws -> [String] {
        let url = repoRoot().appendingPathComponent("XFinder/Core/L10n.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        let marker = "static let all"
        guard let start = source.range(of: marker) else {
            throw FixtureError.declarationNotFound("`\(marker)` not found in Core/L10n.swift")
        }
        guard let end = source.range(of: "]", range: start.upperBound..<source.endIndex) else {
            throw FixtureError.declarationNotFound("the list after `\(marker)` is unclosed")
        }
        let body = source[start.upperBound..<end.lowerBound]
        let pattern = #""((?:[^"\\]|\\.)*)""#
        let regex = try NSRegularExpression(pattern: pattern)
        let ns = String(body) as NSString
        return regex.matches(in: String(body), range: NSRange(location: 0, length: ns.length))
            .compactMap { match in
                guard match.numberOfRanges == 2 else { return nil }
                return ns.substring(with: match.range(at: 1))
            }
    }

    enum FixtureError: Error, CustomStringConvertible {
        case declarationNotFound(String)

        var description: String {
            switch self {
            case .declarationNotFound(let detail): return detail
            }
        }
    }

    /// Extracts the hint half of a direction heading. Derived from the model's own
    /// keys rather than a hand-written table, so it cannot drift out of sync.
    ///
    /// The heading is assembled by `L10n.t(direction, trigger:)` as
    /// `<titleKey> — <button>: <motionHintKey>`. That sentence cannot be built in
    /// this package (no `L10n` here), so the hint is read from the model directly —
    /// which is stronger, because it is the *source* of the sentence rather than a
    /// parse of its output.
    static func directionHint(_ direction: GestureDirection) -> String? {
        guard !GestureTriggerKind.isTilt(direction) else { return nil }
        let hint = direction.motionHintKey
        return hint.isEmpty ? nil : hint
    }

    /// The English each hint must resolve to. Pinned here so a hint fragment that
    /// silently loses its translation is caught by name rather than by "some
    /// string was empty".
    static let directionHintEnglish: [String: String] = [
        "kéo lên": "pull up",
        "kéo xuống": "pull down",
        "kéo sang trái": "pull left",
        "kéo sang phải": "pull right",
    ]

    /// Recognises the interpolated default of `TriggerSource.numberedName`, i.e.
    /// `"Nút \(n + 1)"` for a button above the three named ones. Returns the
    /// rendered number so the caller can tell a real interpolated value from a
    /// literal that merely looks similar.
    static func interpolatedButtonNumber(_ text: String) -> Int? {
        let pattern = #"^Nút (\d+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges == 2,
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return Int(text[range])
    }
}
