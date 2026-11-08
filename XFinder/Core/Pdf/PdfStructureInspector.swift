import Foundation
import PDFKit
import CoreGraphics
import CryptoKit

/// A deliberately bounded PDF inspection pass. It records only properties that the current
/// PDFKit editor can compare after a rewrite; uncertain catalog/security structures fail closed.
enum PdfStructureInspector {
    struct PageEvidence: Equatable {
        let mediaBox: [Double]
        let cropBox: [Double]
        let rotation: Int
        let text: String?
        let annotations: [String]
        let contentStreams: [String]
        let xObjects: [String]
    }

    struct DocumentEvidence: Equatable {
        let pages: [PageEvidence]
        let recoveredStructure: Bool
    }

    enum Problem: Error, Equatable {
        case cancelled
        case unreadable
        case tooLarge
        case encrypted
        case permission
        case signature
        case unsupportedStructure
        case recoveryUnverified
        case validationFailed
        case sourceChanged
    }

    // Proposed safety ceilings. They bound work on untrusted catalogs and large inputs.
    static let maximumInputBytes: Int64 = 512 * 1_024 * 1_024
    static let maximumPages = 20_000
    static let maximumCatalogObjects = 100_000
    static let maximumCatalogDepth = 32

    private static let rootKeys: Set<String> = ["Type", "Pages"]
    private static let annotationTypes: Set<String> = [
        "Link", "Text", "FreeText", "Highlight", "Underline", "StrikeOut", "Square", "Circle", "Line", "Ink", "Stamp"
    ]

    static func inspect(_ url: URL) throws -> DocumentEvidence {
        try checkCancellation()
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let bytes = attrs[.size] as? NSNumber, bytes.int64Value > 0 else { throw Problem.unreadable }
        guard bytes.int64Value <= maximumInputBytes else { throw Problem.tooLarge }
        guard let pdf = PDFDocument(url: url), let cg = CGPDFDocument(url as CFURL) else { throw Problem.unreadable }
        guard !pdf.isEncrypted, !pdf.isLocked, !cg.isEncrypted, cg.isUnlocked else {
            throw Problem.encrypted
        }
        guard pdf.pageCount > 0, pdf.pageCount <= maximumPages,
              cg.numberOfPages == pdf.pageCount else { throw Problem.unreadable }
        guard pdf.allowsDocumentAssembly else { throw Problem.permission }

        guard let catalog = cg.catalog else { throw Problem.unreadable }
        var state = CatalogScan()
        walkDictionary(catalog, depth: 0, state: &state)
        if state.cancelled { throw Problem.cancelled }
        guard state.inspectable else { throw Problem.unsupportedStructure }
        if state.hasSignature { throw Problem.signature }
        guard state.rootKeys.isSubset(of: rootKeys) else {
            throw Problem.unsupportedStructure
        }

        let recovery = try recoveryWarning(url: url, size: bytes.int64Value, pdf: pdf, cg: cg)
        var pages: [PageEvidence] = []
        pages.reserveCapacity(pdf.pageCount)
        for index in 0..<pdf.pageCount {
            try checkCancellation()
            guard let page = pdf.page(at: index), let cgPage = cg.page(at: index + 1) else {
                throw Problem.unreadable
            }
            let annotations = try annotationEvidence(page, document: pdf)
            let streams = try decodedStreams(cgPage)
            let xObjects = try xObjectEvidence(cgPage)
            pages.append(PageEvidence(
                mediaBox: rect(page.bounds(for: .mediaBox)),
                cropBox: rect(page.bounds(for: .cropBox)),
                rotation: page.rotation,
                text: page.string,
                annotations: annotations,
                contentStreams: streams,
                xObjects: xObjects
            ))
        }
        return DocumentEvidence(pages: pages, recoveredStructure: recovery)
    }

    static func expectedAfterRotation(_ evidence: DocumentEvidence, pageIndices: [Int], degrees: Int) -> DocumentEvidence {
        var pages = evidence.pages
        for index in pageIndices where pages.indices.contains(index) {
            let page = pages[index]
            pages[index] = PageEvidence(mediaBox: page.mediaBox, cropBox: page.cropBox,
                rotation: ((page.rotation + degrees) % 360 + 360) % 360, text: page.text,
                annotations: page.annotations, contentStreams: page.contentStreams, xObjects: page.xObjects)
        }
        return DocumentEvidence(pages: pages, recoveredStructure: evidence.recoveredStructure)
    }

    static func selectPages(_ evidence: DocumentEvidence, indices: [Int]) -> DocumentEvidence {
        DocumentEvidence(pages: indices.compactMap { evidence.pages.indices.contains($0) ? evidence.pages[$0] : nil },
                         recoveredStructure: evidence.recoveredStructure)
    }

    static func concatenate(_ evidence: [DocumentEvidence]) -> DocumentEvidence {
        DocumentEvidence(pages: evidence.flatMap(\.pages), recoveredStructure: evidence.contains(where: \.recoveredStructure))
    }

    private static func rect(_ rect: CGRect) -> [Double] {
        [Double(rect.minX), Double(rect.minY), Double(rect.width), Double(rect.height)].map { ($0 * 1_000).rounded() / 1_000 }
    }

    private static func annotationEvidence(_ page: PDFPage, document: PDFDocument) throws -> [String] {
        try page.annotations.map { annotation in
            guard let type = annotation.type, annotationTypes.contains(type), !annotation.hasAppearanceStream else {
                throw Problem.unsupportedStructure
            }
            var values: [String] = [type, String(describing: rect(annotation.bounds)), annotation.contents ?? "",
                                    annotation.userName ?? "", annotation.shouldDisplay.description,
                                    annotation.shouldPrint.description]
            if type == "Widget" { throw Problem.unsupportedStructure }
            if let action = annotation.action {
                guard type == "Link" else { throw Problem.unsupportedStructure }
                if let goTo = action as? PDFActionGoTo {
                    guard let page = goTo.destination.page else { throw Problem.unsupportedStructure }
                    values.append("GoTo:\(document.index(for: page))")
                } else if let url = action as? PDFActionURL {
                    guard ["URL", "URI"].contains(action.type) else { throw Problem.unsupportedStructure }
                    guard let target = url.url else { throw Problem.unsupportedStructure }
                    values.append("URL:\(target.absoluteString)")
                } else { throw Problem.unsupportedStructure }
            } else if type == "Link" {
                if let destination = annotation.destination, let target = destination.page {
                    values.append("Destination:\(document.index(for: target))")
                } else { throw Problem.unsupportedStructure }
            }
            return values.joined(separator: "\u{1f}")
        }.sorted()
    }

    private static func decodedStreams(_ page: CGPDFPage) throws -> [String] {
        guard let dictionary = page.dictionary else { throw Problem.unreadable }
        var object: CGPDFObjectRef?
        guard CGPDFDictionaryGetObject(dictionary, "Contents", &object) else { return [] }
        guard let object else { throw Problem.unsupportedStructure }
        return try streams(from: object)
    }

    private static func streams(from object: CGPDFObjectRef) throws -> [String] {
        switch CGPDFObjectGetType(object) {
        case .stream:
            var stream: CGPDFStreamRef?
            guard CGPDFObjectGetValue(object, .stream, &stream), let stream,
                  let data = streamData(stream) else { throw Problem.unsupportedStructure }
            return [SHA256.hash(data: data as Data).map { String(format: "%02x", $0) }.joined()]
        case .array:
            var array: CGPDFArrayRef?
            guard CGPDFObjectGetValue(object, .array, &array), let array else { throw Problem.unsupportedStructure }
            let count = CGPDFArrayGetCount(array)
            guard count <= 100_000 else { throw Problem.unsupportedStructure }
            var result: [String] = []
            for index in 0..<count {
                var child: CGPDFObjectRef?
                guard CGPDFArrayGetObject(array, index, &child), let child else { throw Problem.unsupportedStructure }
                result += try streams(from: child)
            }
            return result
        default: throw Problem.unsupportedStructure
        }
    }

    private static func xObjectEvidence(_ page: CGPDFPage) throws -> [String] {
        guard let pageDict = page.dictionary else { throw Problem.unreadable }
        var resources: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(pageDict, "Resources", &resources), let resources else { return [] }
        var result: [String] = []
        var budget = 0
        try collectXObjects(resources, prefix: "", depth: 0, budget: &budget, result: &result)
        return result.sorted()
    }

    private static func collectXObjects(_ resources: CGPDFDictionaryRef, prefix: String, depth: Int,
                                        budget: inout Int, result: inout [String]) throws {
        guard depth <= maximumCatalogDepth, budget < maximumCatalogObjects else { throw Problem.unsupportedStructure }
        var xObjects: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(resources, "XObject", &xObjects), let xObjects else { return }
        var failure: Problem?
        CGPDFDictionaryApplyBlock(xObjects, { key, object, _ in
            budget += 1
            guard budget <= maximumCatalogObjects, CGPDFObjectGetType(object) == .stream else {
                failure = .unsupportedStructure
                return false
            }
            var stream: CGPDFStreamRef?
            guard CGPDFObjectGetValue(object, .stream, &stream), let stream,
                  let data = streamData(stream), let dictionary = CGPDFStreamGetDictionary(stream) else {
                failure = .unsupportedStructure
                return false
            }
            var subtype: UnsafePointer<CChar>?
            guard CGPDFDictionaryGetName(dictionary, "Subtype", &subtype), let subtype else {
                failure = .unsupportedStructure
                return false
            }
            let kind = String(cString: subtype)
            guard kind == "Image" || kind == "Form" else { failure = .unsupportedStructure; return false }
            let name = prefix.isEmpty ? String(cString: key) : "\(prefix)/\(String(cString: key))"
            let hash = SHA256.hash(data: data as Data).map { String(format: "%02x", $0) }.joined()
            if kind == "Image" {
                var width: CGPDFInteger = 0
                var height: CGPDFInteger = 0
                guard CGPDFDictionaryGetInteger(dictionary, "Width", &width),
                      CGPDFDictionaryGetInteger(dictionary, "Height", &height), width > 0, height > 0 else {
                    failure = .unsupportedStructure
                    return false
                }
                result.append("\(name):Image:\(width)x\(height):\(hash)")
            } else {
                result.append("\(name):Form:\(hash)")
                var nested: CGPDFDictionaryRef?
                if CGPDFDictionaryGetDictionary(dictionary, "Resources", &nested), let nested {
                    do { try collectXObjects(nested, prefix: name, depth: depth + 1, budget: &budget, result: &result) }
                    catch { failure = .unsupportedStructure; return false }
                }
            }
            return true
        }, nil)
        if let failure { throw failure }
    }

    private struct CatalogScan {
        var rootKeys = Set<String>()
        var objectCount = 0
        var inspectable = true
        var hasSignature = false
        var cancelled = false
    }

    private static func walkDictionary(_ dictionary: CGPDFDictionaryRef, depth: Int, state: inout CatalogScan) {
        if isCancelled { state.inspectable = false; state.cancelled = true; return }
        guard depth <= maximumCatalogDepth, state.objectCount < maximumCatalogObjects else {
            state.inspectable = false
            return
        }
        CGPDFDictionaryApplyBlock(dictionary, { key, object, _ in
            state.objectCount += 1
            guard state.objectCount <= maximumCatalogObjects else { state.inspectable = false; return false }
            let keyName = String(cString: key)
            if depth == 0 { state.rootKeys.insert(keyName) }
            if ["Perms", "DocMDP"].contains(keyName) { state.hasSignature = true }
            if keyName == "FT", pdfName(object) == "Sig" { state.hasSignature = true }
            if keyName == "Type", pdfName(object) == "Sig" { state.hasSignature = true }
            // PDF page/annotation nodes point back to their owner. Exclude these edges from the
            // security walk; all forward catalog/page structure remains bounded and traversed.
            if keyName == "Parent" || keyName == "P" { return true }
            if !walk(object, depth: depth + 1, state: &state) { return false }
            return true
        }, nil)
    }

    private static func walk(_ object: CGPDFObjectRef, depth: Int, state: inout CatalogScan) -> Bool {
        if isCancelled { state.inspectable = false; state.cancelled = true; return false }
        guard depth <= maximumCatalogDepth, state.objectCount < maximumCatalogObjects else {
            state.inspectable = false
            return false
        }
        switch CGPDFObjectGetType(object) {
        case .array:
            var array: CGPDFArrayRef?
            guard CGPDFObjectGetValue(object, .array, &array), let array else { state.inspectable = false; return false }
            let count = CGPDFArrayGetCount(array)
            guard count <= maximumCatalogObjects else { state.inspectable = false; return false }
            for index in 0..<count {
                var child: CGPDFObjectRef?
                guard CGPDFArrayGetObject(array, index, &child), let child,
                      walk(child, depth: depth + 1, state: &state) else { state.inspectable = false; return false }
            }
        case .dictionary:
            var child: CGPDFDictionaryRef?
            guard CGPDFObjectGetValue(object, .dictionary, &child), let child else { state.inspectable = false; return false }
            walkDictionary(child, depth: depth, state: &state)
        case .stream:
            var stream: CGPDFStreamRef?
            guard CGPDFObjectGetValue(object, .stream, &stream), let stream,
                  let data = streamData(stream), Int64(CFDataGetLength(data)) <= maximumInputBytes else { state.inspectable = false; return false }
            guard let dictionary = CGPDFStreamGetDictionary(stream) else { state.inspectable = false; return false }
            walkDictionary(dictionary, depth: depth, state: &state)
        default: break
        }
        return state.inspectable
    }

    private static func pdfName(_ object: CGPDFObjectRef) -> String? {
        guard CGPDFObjectGetType(object) == .name else { return nil }
        var value: UnsafePointer<CChar>?
        guard CGPDFObjectGetValue(object, .name, &value), let value else { return nil }
        return String(cString: value)
    }

    private static func recoveryWarning(url: URL, size: Int64, pdf: PDFDocument, cg: CGPDFDocument) throws -> Bool {
        try checkCancellation()
        guard let handle = try? FileHandle(forReadingFrom: url) else { throw Problem.unreadable }
        defer { try? handle.close() }
        let head = try handle.read(upToCount: 1_024) ?? Data()
        guard String(data: head, encoding: .isoLatin1)?.contains("%PDF-") == true else { throw Problem.unreadable }
        try handle.seek(toOffset: UInt64(max(0, size - 8_192)))
        let tail = try handle.readToEnd() ?? Data()
        let text = String(data: tail, encoding: .isoLatin1) ?? ""
        let eofPresent = text.range(of: "%%EOF", options: .backwards) != nil
        guard let marker = text.range(of: "startxref", options: .backwards),
              let offset = Int64(text[marker.upperBound...].split(whereSeparator: { $0.isWhitespace }).first ?? "") else {
            throw Problem.recoveryUnverified
        }
        let bothExposeTree = pdf.pageCount > 0 && cg.numberOfPages == pdf.pageCount
        if offset < 0 || offset >= size {
            guard bothExposeTree else { throw Problem.recoveryUnverified }
            return true
        }
        try handle.seek(toOffset: UInt64(offset))
        let xrefHead = String(data: try handle.read(upToCount: 64) ?? Data(), encoding: .isoLatin1) ?? ""
        let normalized = xrefHead.trimmingCharacters(in: .whitespacesAndNewlines)
        var validTarget = normalized.hasPrefix("xref")
        if !validTarget, normalized.range(of: #"^\d+\s+\d+\s+obj"#, options: .regularExpression) != nil {
            try handle.seek(toOffset: UInt64(offset))
            let objectHead = String(data: try handle.read(upToCount: 8_192) ?? Data(), encoding: .isoLatin1) ?? ""
            validTarget = objectHead.range(of: #"/Type\s*/XRef\b"#, options: .regularExpression) != nil
        }
        guard validTarget else { throw Problem.recoveryUnverified }
        if !eofPresent {
            guard bothExposeTree else { throw Problem.recoveryUnverified }
            return true
        }
        return false
    }

    private static func streamData(_ stream: CGPDFStreamRef) -> CFData? {
        var format = CGPDFDataFormat.raw
        return CGPDFStreamCopyData(stream, &format)
    }

    private static var isCancelled: Bool {
        withUnsafeCurrentTask { $0?.isCancelled ?? false }
    }

    private static func checkCancellation() throws {
        if isCancelled { throw Problem.cancelled }
    }
}
