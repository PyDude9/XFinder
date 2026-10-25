import Foundation

/// XF-T30 W5a — the rules of the opt-in local index (FileOctopus "Search" settings): which folders, what is skipped,
/// the content limits, what an FSEvents flag means, how a root's status reads. Pure, symlinked into the test package.
/// Contract docs/specs/XF-T30-w5a-contract.md §2.
struct IndexRoot: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var path: String
    /// Index file contents (text, PDF text layer, rich text).
    var contents: Bool
    /// OCR images and scanned PDFs (Text in Images).
    var textInImages: Bool
    var paused: Bool
    /// Identity when approved (device + inode) so a folder moved or replaced reads "Moved or replaced — add it again".
    var device: Int32?
    var inode: UInt64?
}

enum IndexRootStatus: Equatable, Sendable {
    case indexing(done: Int)
    case updating(changes: Int)
    case ready
    case paused
    case offline
    case noAccess
    case movedOrReplaced
    case failed
}

enum IndexContentKind: Equatable, Sendable { case plainText, pdf, richText, image, none }

enum SearchIndexRules {
    static let textReadCap = 2 * 1024 * 1024
    static let storedCharacterCap = 200_000
    static let pdfPageCap = 50
    static let pdfSizeCap = 64 * 1024 * 1024
    static let scannedPDFPageCap = 10
    static let ocrFileCap = 50 * 1024 * 1024

    static let excludedDirectoryNames: Set<String> = ["node_modules", ".git", "DerivedData", ".build", "build", "Pods", ".Trash"]

    /// `~/Library` and any component in `excludedDirectoryNames`. W5a builder (pure): implement.
    static func isExcluded(_ path: String, home: String) -> Bool { false }

    /// By lowercase extension. W5a builder (pure): implement (txt md csv json swift … ⇒ plainText; pdf; rtf rtfd doc docx
    /// odt html htm pages? (pages is a package — none); png jpg jpeg heic tiff gif bmp webp ⇒ image).
    static func contentKind(forExtension ext: String) -> IndexContentKind { .none }

    enum EventAction: Equatable, Sendable {
        case rescanSubtree(String), updatePath(String), removePath(String), rootChanged
    }

    /// One FSEvents event (`kFSEventStreamEventFlag*` raw values) → what the index does. W5a builder (pure): implement.
    static func action(path: String, flags: UInt32) -> EventAction { .updatePath(path) }

    enum RootValidation: Equatable, Sendable {
        case ok, notADirectory, excluded, alreadyCovered(by: String), coversExisting([String])
    }

    /// Adding `path` as a root. A root inside an existing one is `alreadyCovered`; one that contains existing roots is
    /// `coversExisting` (the caller merges them). W5a builder (pure): implement.
    static func validateNewRoot(_ path: String, isDirectory: Bool, existing: [IndexRoot], home: String) -> RootValidation { .ok }

    /// L10n key for a status. W5a builder (pure): implement.
    static func statusKey(_ status: IndexRootStatus) -> String { "" }
}
