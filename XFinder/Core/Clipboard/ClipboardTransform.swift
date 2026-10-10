import Foundation
import CryptoKit

/// Text transforms for a clipboard item (B5 "Biến đổi"). Pure and tested; the view calls
/// `L10n.t(labelKey)`. Every transform that would change nothing returns `.failure(.noChange)`
/// instead of a disguised no-op, and anything that cannot parse its input says so.
///
/// Measured while designing (Foundation on macOS 27):
/// * `JSONSerialization` does NOT preserve key order → `jsonPretty` sorts keys and the label says so.
/// * `.urlQueryAllowed` leaves `&`, `=` and `?` unescaped → `urlEncode` uses the RFC 3986 unreserved set.
/// * `Data(base64Encoded:)` rejects unpadded input → `base64Decode` pads to a multiple of 4 first.
/// * Case mapping uses the locale-free `uppercased()`/`lowercased()`/`capitalized` (no Turkish-İ surprises).
enum ClipboardTransform: String, CaseIterable, Identifiable {
    case trim, normalizeWhitespace, removeLineBreaks
    case uppercase, lowercase, titleCase
    case sortLines, dedupeLines, reverseLines
    case jsonPretty, jsonMinify
    case base64Encode, base64Decode
    case urlEncode, urlDecode, cleanURL
    case md5

    var id: String { rawValue }

    /// Store key of the menu label.
    var labelKey: String {
        switch self {
        case .trim: return "Cắt khoảng trắng hai đầu"
        case .normalizeWhitespace: return "Gom khoảng trắng"
        case .removeLineBreaks: return "Bỏ xuống dòng"
        case .uppercase: return "VIẾT HOA"
        case .lowercase: return "viết thường"
        case .titleCase: return "Viết Hoa Chữ Đầu"
        case .sortLines: return "Sắp xếp dòng"
        case .dedupeLines: return "Bỏ dòng trùng"
        case .reverseLines: return "Đảo thứ tự dòng"
        case .jsonPretty: return "JSON dễ đọc (sắp xếp khoá)"
        case .jsonMinify: return "JSON một dòng"
        case .base64Encode: return "Mã hoá Base64"
        case .base64Decode: return "Giải mã Base64"
        case .urlEncode: return "Mã hoá URL"
        case .urlDecode: return "Giải mã URL"
        case .cleanURL: return "Bỏ tham số theo dõi trong link"
        case .md5: return "MD5 (mã kiểm, không bảo mật)"
        }
    }

    /// Menu grouping, in display order.
    static let groups: [[ClipboardTransform]] = [
        [.trim, .normalizeWhitespace, .removeLineBreaks],
        [.uppercase, .lowercase, .titleCase],
        [.sortLines, .dedupeLines, .reverseLines],
        [.jsonPretty, .jsonMinify],
        [.base64Encode, .base64Decode, .urlEncode, .urlDecode, .cleanURL, .md5],
    ]

    enum Failure: Error, Equatable {
        case noChange
        case notJSON
        case notBase64
        case notURLEncoded
        case notALink

        var messageKey: String {
            switch self {
            case .noChange: return "Không có gì để đổi."
            case .notJSON: return "Nội dung không phải JSON."
            case .notBase64: return "Nội dung không phải Base64."
            case .notURLEncoded: return "Nội dung không có phần mã hoá URL hợp lệ."
            case .notALink: return "Nội dung không phải một link."
            }
        }
        static let all: [Failure] = [.noChange, .notJSON, .notBase64, .notURLEncoded, .notALink]
    }

    func apply(to text: String) -> Result<String, Failure> {
        let out: String
        switch self {
        case .trim:
            out = text.trimmingCharacters(in: .whitespacesAndNewlines)
        case .normalizeWhitespace:
            out = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
        case .removeLineBreaks:
            out = text.components(separatedBy: .newlines).filter { !$0.isEmpty }.joined(separator: " ")
        case .uppercase: out = text.uppercased()
        case .lowercase: out = text.lowercased()
        case .titleCase: out = text.capitalized
        case .sortLines:
            out = Self.lines(text).sorted { $0.localizedStandardCompare($1) == .orderedAscending }.joined(separator: "\n")
        case .dedupeLines:
            var seen = Set<String>()
            out = Self.lines(text).filter { seen.insert($0).inserted }.joined(separator: "\n")
        case .reverseLines:
            out = Self.lines(text).reversed().joined(separator: "\n")
        case .jsonPretty, .jsonMinify:
            guard let data = text.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
                return .failure(.notJSON)
            }
            var options: JSONSerialization.WritingOptions = [.fragmentsAllowed, .withoutEscapingSlashes]
            if self == .jsonPretty { options.formUnion([.prettyPrinted, .sortedKeys]) } else { options.insert(.sortedKeys) }
            guard let d = try? JSONSerialization.data(withJSONObject: object, options: options),
                  let s = String(data: d, encoding: .utf8) else { return .failure(.notJSON) }
            out = s
        case .base64Encode:
            out = Data(text.utf8).base64EncodedString()
        case .base64Decode:
            var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")   // URL-safe alphabet too
            let pad = (4 - s.count % 4) % 4
            s += String(repeating: "=", count: pad)
            guard let d = Data(base64Encoded: s, options: [.ignoreUnknownCharacters]), !d.isEmpty,
                  let decoded = String(data: d, encoding: .utf8) else { return .failure(.notBase64) }
            out = decoded
        case .urlEncode:
            out = text.addingPercentEncoding(withAllowedCharacters: Self.rfc3986Unreserved) ?? text
        case .urlDecode:
            guard text.contains("%"), let d = text.removingPercentEncoding else { return .failure(.notURLEncoded) }
            out = d
        case .cleanURL:
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard URLCleaner.host(ofAbsoluteURL: t) != nil else { return .failure(.notALink) }
            guard let r = URLCleaner.clean(t) else { return .failure(.noChange) }
            out = r.cleaned
        case .md5:
            out = Insecure.MD5.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
        }
        return out == text ? .failure(.noChange) : .success(out)
    }

    /// Split on every newline convention (CRLF included) and drop a trailing empty line.
    static func lines(_ text: String) -> [String] {
        // `.newlines` treats "\r\n" as TWO separators (measured: "a\r\nb\n" split into 3 lines), so
        // CRLF is folded first.
        var l = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: .newlines)
        if l.last == "" { l.removeLast() }
        return l
    }

    /// RFC 3986 §2.3 unreserved characters — everything else is percent-encoded.
    static let rfc3986Unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    /// Counts for a "123 từ · 456 ký tự · 7 dòng" line; the view formats them.
    static func stats(_ text: String) -> (words: Int, characters: Int, lines: Int) {
        let words = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
        return (words, text.count, text.isEmpty ? 0 : lines(text).count)
    }
}
