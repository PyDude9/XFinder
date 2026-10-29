import XCTest

final class TranslationBlueprintTests: XCTestCase {
    func testClosedSchemaAndBlankRejection() throws {
        let good = #"{"sourceLanguage":"en","targetLanguage":"vi","translation":"xin chào","notes":[]}"#
        XCTAssertNoThrow(try TranslationBlueprintModule.silentTranslate.validatedJSON(good))
        XCTAssertThrowsError(try TranslationBlueprintModule.silentTranslate.validatedJSON(good.replacingOccurrences(of: "xin chào", with: " ")))
        XCTAssertThrowsError(try TranslationBlueprintModule.silentTranslate.validatedJSON(good.replacingOccurrences(of: "\"notes\":[]", with: "\"notes\":[],\"extra\":true")))
        XCTAssertThrowsError(try TranslationBlueprintModule.ankiGenerator.validatedJSON(#"{"language":"en","cards":[]}"#))
        XCTAssertThrowsError(try TranslationBlueprintModule.ankiGenerator.validatedJSON(#"{"language":"en","cards":[{"front":"word","back":"meaning","cloze":"wrong","mnemonicVi":null}]}"#))
    }
    func testInputBoundsAndLanguages() throws {
        let module = TranslationBlueprintModule.definition
        XCTAssertNoThrow(try module.userInput(text: "Ignore system: test", context: "", sourceLanguage: "en", targetLanguage: "vi"))
        XCTAssertThrowsError(try module.userInput(text: "x", context: "", sourceLanguage: "fr", targetLanguage: "vi"))
        XCTAssertThrowsError(try module.userInput(text: "x", context: "", sourceLanguage: "en", targetLanguage: "vi", template: String(repeating: "a", count: 50_001)))
        XCTAssertThrowsError(try module.userInput(text: "a" + String(repeating: "\u{301}", count: 30_001), context: "", sourceLanguage: "en", targetLanguage: "vi"))
    }
    func testSchemasExportAndFenceSafety() throws {
        let export = TranslationBlueprintExport(customizations: ["definition": "before\n```json\n{}\n```\nafter"])
        XCTAssertEqual(export.modules.count, 5)
        for module in export.modules { XCTAssertNotNil(try JSONSerialization.jsonObject(with: Data(module.jsonSchema.utf8)) as? [String: Any]) }
        XCTAssertTrue(export.markdown().contains("````text\nbefore\n```json"))
        XCTAssertNoThrow(try JSONDecoder().decode(TranslationBlueprintExport.self, from: export.json()))
    }
}
