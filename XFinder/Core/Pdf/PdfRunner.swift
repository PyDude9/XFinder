import Foundation
import PDFKit
import Darwin
import CryptoKit

/// PDF transformations are copy-only: inspect the input, mutate an in-memory document, write a
/// same-folder staging file, reopen and compare inspected invariants, then publish with an
/// exclusive rename. No operation writes to an input URL.
enum PdfRunner {

    enum Failure: Error, Equatable {
        case cancelled
        case unreadable(String)
        case invalidRange(pageCount: Int)
        case writeFailed(String)
        case tooLarge(String)
        case encrypted(String)
        case permission(String)
        case signed(String)
        case unsupportedStructure(String)
        case recoveryUnverified(String)
        case validationFailed(String)
        case sourceChanged(String)

        var messageKey: String {
            switch self {
            case .cancelled: return "Đã hủy thao tác PDF; tệp nguồn vẫn được giữ nguyên."
            case .unreadable: return "Không đọc được tập tin PDF: "
            case .invalidRange: return "Khoảng trang không hợp lệ. Số trang của tài liệu: "
            case .writeFailed: return "Không ghi được tập tin đích: "
            case .tooLarge: return "Tệp PDF vượt giới hạn kiểm tra an toàn: "
            case .encrypted: return "PDF được mã hóa hoặc khóa; chưa tạo bản mới: "
            case .permission: return "Quyền của PDF không cho phép thay đổi trang: "
            case .signed: return "PDF có chữ ký hoặc chính sách chứng nhận; không thể viết lại an toàn: "
            case .unsupportedStructure: return "PDF có cấu trúc chưa được kiểm tra; chưa tạo bản mới: "
            case .recoveryUnverified: return "Không thể xác minh cấu trúc PDF bị lỗi để phục hồi an toàn: "
            case .validationFailed: return "Bản PDF mới không vượt qua kiểm tra cấu trúc; tệp gốc được giữ nguyên: "
            case .sourceChanged: return "PDF nguồn đã thay đổi trong lúc xử lý; chưa công bố bản mới: "
            }
        }
        var detail: String {
            switch self {
            case .cancelled: return ""
            case .unreadable(let n), .writeFailed(let n), .tooLarge(let n), .encrypted(let n), .permission(let n),
                 .signed(let n), .unsupportedStructure(let n), .recoveryUnverified(let n),
                 .validationFailed(let n), .sourceChanged(let n): return n
            case .invalidRange(let c): return "\(c)"
            }
        }
        static let examples: [Failure] = [
            .cancelled, .unreadable("a"), .invalidRange(pageCount: 3), .writeFailed("a"), .tooLarge("a"), .encrypted("a"),
            .permission("a"), .signed("a"), .unsupportedStructure("a"), .recoveryUnverified("a"),
            .validationFailed("a"), .sourceChanged("a")
        ]
    }

    struct Output: Equatable {
        let url: URL
        let pages: Int
        let rewrittenAfterRecoveryWarning: Bool
    }

    static func merge(_ sources: [URL], into folder: URL) -> Result<Output, Failure> {
        guard sources.count >= 2 else { return .failure(.unreadable(sources.first?.lastPathComponent ?? "PDF")) }
        var docs: [PDFDocument] = []
        var evidence: [PdfStructureInspector.DocumentEvidence] = []
        var hashes: [String] = []
        for url in sources {
            if isCancelled { return .failure(.cancelled) }
            guard let doc = PDFDocument(url: url) else { return .failure(.unreadable(url.lastPathComponent)) }
            do {
                docs.append(doc)
                evidence.append(try PdfStructureInspector.inspect(url))
                hashes.append(try hash(url))
            } catch { return .failure(failure(error, url: url)) }
        }
        let output = PDFDocument()
        for (sourceIndex, doc) in docs.enumerated() {
            for index in 0..<doc.pageCount {
                if isCancelled { return .failure(.cancelled) }
                guard let page = doc.page(at: index) else { return .failure(.unreadable(sources[sourceIndex].lastPathComponent)) }
                output.insert(page, at: output.pageCount)
            }
        }
        return write(output, tool: .merge, sources: sources, folder: folder,
                     expected: PdfStructureInspector.concatenate(evidence), sourceHashes: hashes)
    }

    static func extract(_ source: URL, range: String, into folder: URL) -> Result<Output, Failure> {
        guard let doc = PDFDocument(url: source) else { return .failure(.unreadable(source.lastPathComponent)) }
        let evidence: PdfStructureInspector.DocumentEvidence
        let sourceHash: String
        do { evidence = try PdfStructureInspector.inspect(source); sourceHash = try hash(source) }
        catch { return .failure(failure(error, url: source)) }
        guard let pages = PdfEngine.pageIndices(range, pageCount: doc.pageCount, emptyMeansAll: false) else {
            return .failure(.invalidRange(pageCount: doc.pageCount))
        }
        let output = PDFDocument()
        for index in pages {
            if isCancelled { return .failure(.cancelled) }
            guard let page = doc.page(at: index) else { return .failure(.unreadable(source.lastPathComponent)) }
            output.insert(page, at: output.pageCount)
        }
        return write(output, tool: .extract, sources: [source], folder: folder,
                     expected: PdfStructureInspector.selectPages(evidence, indices: pages), sourceHashes: [sourceHash])
    }

    static func reorder(_ source: URL, order: String, into folder: URL) -> Result<Output, Failure> {
        guard let doc = PDFDocument(url: source) else { return .failure(.unreadable(source.lastPathComponent)) }
        guard let order = PdfEngine.orderedPageIndices(order, pageCount: doc.pageCount) else {
            return .failure(.invalidRange(pageCount: doc.pageCount))
        }
        let evidence: PdfStructureInspector.DocumentEvidence
        let sourceHash: String
        do { evidence = try PdfStructureInspector.inspect(source); sourceHash = try hash(source) }
        catch { return .failure(failure(error, url: source)) }
        let output = PDFDocument()
        for index in order {
            if isCancelled { return .failure(.cancelled) }
            guard let page = doc.page(at: index) else { return .failure(.unreadable(source.lastPathComponent)) }
            output.insert(page, at: output.pageCount)
        }
        return write(output, tool: .reorder, sources: [source], folder: folder,
                     expected: PdfStructureInspector.selectPages(evidence, indices: order), sourceHashes: [sourceHash])
    }

    static func rotate(_ source: URL, range: String, degrees: Int, into folder: URL) -> Result<Output, Failure> {
        guard let doc = PDFDocument(url: source) else { return .failure(.unreadable(source.lastPathComponent)) }
        let evidence: PdfStructureInspector.DocumentEvidence
        let sourceHash: String
        do { evidence = try PdfStructureInspector.inspect(source); sourceHash = try hash(source) }
        catch { return .failure(failure(error, url: source)) }
        guard let pages = PdfEngine.pageIndices(range, pageCount: doc.pageCount, emptyMeansAll: true),
              [90, 180, 270].contains(degrees) else { return .failure(.invalidRange(pageCount: doc.pageCount)) }
        for index in pages {
            if isCancelled { return .failure(.cancelled) }
            guard let page = doc.page(at: index) else { return .failure(.unreadable(source.lastPathComponent)) }
            page.rotation = ((page.rotation + degrees) % 360 + 360) % 360
        }
        return write(doc, tool: .rotate, sources: [source], folder: folder,
                     expected: PdfStructureInspector.expectedAfterRotation(evidence, pageIndices: pages, degrees: degrees),
                     sourceHashes: [sourceHash])
    }

    private static func write(_ doc: PDFDocument, tool: PdfEngine.Tool, sources: [URL], folder: URL,
                              expected: PdfStructureInspector.DocumentEvidence, sourceHashes: [String]) -> Result<Output, Failure> {
        guard sourceHashes.count == sources.count else { return .failure(.validationFailed("source count")) }
        if isCancelled { return .failure(.cancelled) }
        let stage = folder.appendingPathComponent(".xf-pdf-\(UUID().uuidString).tmp.pdf")
        let fd = open(stage.path, O_WRONLY | O_CREAT | O_EXCL, mode_t(S_IRUSR | S_IWUSR))
        guard fd >= 0 else { return .failure(.writeFailed(stage.lastPathComponent)) }
        _ = close(fd)
        defer { try? FileManager.default.removeItem(at: stage) }
        guard doc.write(to: stage) else { return .failure(.writeFailed(stage.lastPathComponent)) }
        if isCancelled { return .failure(.cancelled) }
        let actual: PdfStructureInspector.DocumentEvidence
        do { actual = try PdfStructureInspector.inspect(stage) }
        catch { return .failure(failure(error, url: stage)) }
        guard actual.pages == expected.pages else { return .failure(.validationFailed(stage.lastPathComponent)) }
        if isCancelled { return .failure(.cancelled) }
        for (url, before) in zip(sources, sourceHashes) {
            if isCancelled { return .failure(.cancelled) }
            do {
                guard try hash(url) == before else { return .failure(.sourceChanged(url.lastPathComponent)) }
            } catch { return .failure(.sourceChanged(url.lastPathComponent)) }
        }

        var attempted: Set<String> = []
        for _ in 0..<1_000 {
            let target = PdfEngine.outputURL(tool: tool, sources: sources, folder: folder) { candidate in
                attempted.contains(candidate.standardizedFileURL.path) || FileManager.default.fileExists(atPath: candidate.path)
            }
            guard !sources.contains(where: { $0.standardizedFileURL == target.standardizedFileURL }) else {
                attempted.insert(target.standardizedFileURL.path)
                continue
            }
            if publishExclusive(staged: stage, target: target) {
                return .success(Output(url: target, pages: actual.pages.count,
                                       rewrittenAfterRecoveryWarning: expected.recoveredStructure))
            }
            if errno == EEXIST { attempted.insert(target.standardizedFileURL.path); continue }
            return .failure(.writeFailed(target.lastPathComponent))
        }
        return .failure(.writeFailed(sources.first?.lastPathComponent ?? "PDF"))
    }

    /// The final name can become occupied after the keep-both lookup. This atomic exclusive publish
    /// closes that race without replacing a file another process created in the meantime.
    static func publishExclusive(staged: URL, target: URL) -> Bool {
        renamex_np(staged.path, target.path, UInt32(RENAME_EXCL)) == 0
    }

    private static var isCancelled: Bool {
        withUnsafeCurrentTask { $0?.isCancelled ?? false }
    }

    private static func hash(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty { hasher.update(data: data) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func failure(_ error: Error, url: URL) -> Failure {
        switch error as? PdfStructureInspector.Problem {
        case .cancelled: return .cancelled
        case .unreadable: return .unreadable(url.lastPathComponent)
        case .tooLarge: return .tooLarge(url.lastPathComponent)
        case .encrypted: return .encrypted(url.lastPathComponent)
        case .permission: return .permission(url.lastPathComponent)
        case .signature: return .signed(url.lastPathComponent)
        case .unsupportedStructure: return .unsupportedStructure(url.lastPathComponent)
        case .recoveryUnverified: return .recoveryUnverified(url.lastPathComponent)
        case .validationFailed: return .validationFailed(url.lastPathComponent)
        case .sourceChanged: return .sourceChanged(url.lastPathComponent)
        case nil: return .unreadable(url.lastPathComponent)
        }
    }
}
