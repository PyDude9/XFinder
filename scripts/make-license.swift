// XF-T29 — the owner's licence tool. Runs on the owner's Mac only; the private key never enters the repo.
//
//   swift scripts/make-license.swift init  ~/Private/xfinder-license.key
//       → writes a new Ed25519 private key (mode 0600) and prints the PUBLIC key as a Swift Data literal to paste into
//         XFinder/Core/Pro/LicenseKey.swift (`publicKeyRaw`).
//   swift scripts/make-license.swift sign  ~/Private/xfinder-license.key  "buyer@example.com"  [edition]  [id]
//       → prints an XF1-… licence key for that buyer (edition defaults to "pro").
//   swift scripts/make-license.swift check <public key base64> <XF1-… key>
//       → verifies a key the way the app does.
//
// Format (must match LicenseKey.swift): "XF1-" + base64url(JSON {edition,id,issued,licensee}, sorted keys, ISO-8601 date)
// + "." + base64url(64-byte Ed25519 signature over those JSON bytes).
import CryptoKit
import Foundation

struct Payload: Codable { let id: String; let licensee: String; let edition: String; let issued: Date }

func b64url(_ d: Data) -> String {
    d.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
}
func unb64url(_ s: String) -> Data? {
    var t = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
    while t.count % 4 != 0 { t += "=" }
    return Data(base64Encoded: t)
}
func fail(_ m: String) -> Never { FileHandle.standardError.write(Data((m + "\n").utf8)); exit(1) }

let args = CommandLine.arguments
guard args.count >= 2 else { fail("usage: init <key file> | sign <key file> <licensee> [edition] [id] | check <pub b64> <key>") }

switch args[1] {
case "init":
    guard args.count == 3 else { fail("usage: init <key file>") }
    let url = URL(fileURLWithPath: (args[2] as NSString).expandingTildeInPath)
    guard !FileManager.default.fileExists(atPath: url.path) else { fail("refusing to overwrite \(url.path)") }
    let key = Curve25519.Signing.PrivateKey()
    FileManager.default.createFile(atPath: url.path, contents: key.rawRepresentation.base64EncodedData(),
                                   attributes: [.posixPermissions: 0o600])
    let pub = key.publicKey.rawRepresentation
    print("private key written to \(url.path) (keep it secret, back it up)")
    print("public key (base64): \(pub.base64EncodedString())")
    print("paste into LicenseKey.swift:")
    print("    static let publicKeyRaw: Data? = Data(base64Encoded: \"\(pub.base64EncodedString())\")")
case "sign":
    guard args.count >= 4 else { fail("usage: sign <key file> <licensee> [edition] [id]") }
    let url = URL(fileURLWithPath: (args[2] as NSString).expandingTildeInPath)
    guard let b64 = try? String(contentsOf: url, encoding: .utf8), let raw = Data(base64Encoded: b64.trimmingCharacters(in: .whitespacesAndNewlines)),
          let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw) else { fail("cannot read the private key") }
    let payload = Payload(id: args.count >= 6 ? args[5] : UUID().uuidString, licensee: args[3],
                          edition: args.count >= 5 ? args[4] : "pro", issued: Date())
    let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]; enc.dateEncodingStrategy = .iso8601
    guard let json = try? enc.encode(payload), let sig = try? key.signature(for: json) else { fail("signing failed") }
    print("XF1-" + b64url(json) + "." + b64url(sig))
case "check":
    guard args.count == 4, let pubRaw = Data(base64Encoded: args[2]),
          let pub = try? Curve25519.Signing.PublicKey(rawRepresentation: pubRaw) else { fail("usage: check <pub b64> <key>") }
    let compact = args[3].filter { !$0.isWhitespace }
    guard compact.hasPrefix("XF1-") else { fail("not an XF1 key") }
    let parts = compact.dropFirst(4).split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count == 2, let json = unb64url(String(parts[0])), let sig = unb64url(String(parts[1])),
          pub.isValidSignature(sig, for: json) else { fail("INVALID") }
    print("VALID: " + String(decoding: json, as: UTF8.self))
default:
    fail("unknown command \(args[1])")
}
