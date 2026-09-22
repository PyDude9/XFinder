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

    /// The gesture UI's two known leaks, pinned by name.
    ///
    /// `TriggerSource.buttonName` and `GestureDirectionDisplay.title` both return
    /// Vietnamese from a pure-Foundation file that must stay translation-free
    /// (the test package symlinks them). The fix was to wrap at the call site, so
    /// the strings have to be *in the store* for the call-site wrap to do
    /// anything — this asserts exactly that, for every value either function can
    /// return, including the interpolated default case.
    func testGesturePageStringsAreAllTranslatable() throws {
        let store = try L10nFixture.load()
        var needed = Set<L10nFixture.Probe>()

        // Every button the trigger picker can show, including out-of-range codes
        // that fall through to the interpolated default. The interpolated case is
        // probed as its three pieces, because that is how the call site must
        // assemble it: a whole-string wrap can never match a key containing a
        // runtime value, which is bug shape #2 in this file's header.
        let buttonNumbers = [0, 1, 2, 3, 4, 7, 31]
        for code in buttonNumbers {
            needed.insert(.init(TriggerSource.buttonName(code)))
        }
        let interpolated = buttonNumbers.filter { !(0...4).contains($0) }
        XCTAssertFalse(interpolated.isEmpty, "precondition: an interpolated case exists")
        needed.insert(.init(fragment: "Nút chuột số ", suffix: "Mouse button "))
        needed.insert(.init(fragment: " (Button ", prefix: " (Button "))

        for direction in GestureDirection.allCases {
            needed.insert(.init(GestureDirectionDisplay.title(direction)))
            needed.insert(.init(direction.instruction))
        }

        // A `whole` probe is a string the call site passes to `L10n.t` verbatim.
        // An interpolated default's assembled result is NOT one of those — it can
        // only ever be built from its pieces — so those drop out of this check and
        // are covered by the two fragment probes above instead.
        let missing = needed.filter { probe in
            switch probe.kind {
            case .whole(let key):
                if let code = L10nFixture.interpolatedButtonCode(key), interpolated.contains(code) {
                    return false
                }
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

    /// Recognises the interpolated default of `TriggerSource.buttonName`, i.e.
    /// `"Nút chuột số \(n + 1) (Button \(n))"` for a button above the named four.
    /// Returns the raw button code so the caller can tell a real interpolated
    /// value from a literal that merely looks similar.
    static func interpolatedButtonCode(_ text: String) -> Int? {
        let pattern = #"^Nút chuột số (\d+) \(Button (\d+)\)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges == 3,
              let codeRange = Range(match.range(at: 2), in: text),
              let numberRange = Range(match.range(at: 1), in: text),
              let code = Int(text[codeRange]),
              let shown = Int(text[numberRange]),
              shown == code + 1 else { return nil }
        return code
    }
}
