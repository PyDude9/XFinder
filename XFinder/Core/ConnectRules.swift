import Foundation

/// XF-T21 (2026-10-18) — the pure rules behind Chia sẻ nhanh and Kết nối từ xa (symlinked into the test package), so the two
/// KẾT NỐI features have a FeatureContract row instead of two exemptions.
///
/// Found while extracting them: the share server wrote `Content-Disposition: attachment; filename="<name>"` with the file name
/// as is. A macOS file name may contain `"`, CR and LF, so a file called `a"\r\nX-Evil: 1.txt` injected a header into the
/// response. `contentDisposition` now emits an ASCII-only quoted fallback plus RFC 6266 / 5987 `filename*=UTF-8''…`.
enum QuickShareRules {
    static let enabledKey = "quickShare.enabled"

    /// The token of "GET /<token> HTTP/1.1": the request target's path without slashes; empty for anything else.
    static func token(fromRequest request: String) -> String {
        guard let line = request.split(separator: "\r\n", omittingEmptySubsequences: false).first else { return "" }
        let parts = line.split(separator: " ")
        guard parts.count >= 2, parts[0] == "GET" else { return "" }
        let target = parts[1].split(separator: "?").first.map(String.init) ?? ""
        let token = target.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return token.allSatisfy({ $0.isHexDigit }) ? token : ""
    }

    static func link(address: String?, port: UInt16, token: String) -> String? {
        guard let address, port != 0, !token.isEmpty else { return nil }
        return "http://\(address):\(port)/\(token)"
    }

    /// `attachment; filename="<ascii fallback>"; filename*=UTF-8''<percent-encoded>` — no byte of the name can end the header.
    static func contentDisposition(filename: String) -> String {
        let fallback = String(filename.unicodeScalars.map { s -> Character in
            (s.isASCII && s.value >= 0x20 && s != "\"" && s != "\\" && s.value != 0x7F) ? Character(s) : "_"
        })
        var allowed = CharacterSet.alphanumerics.intersection(CharacterSet(charactersIn: Unicode.Scalar(0)...Unicode.Scalar(0x7F)))
        allowed.insert(charactersIn: "!#$&+-.^_`|~")
        let encoded = filename.addingPercentEncoding(withAllowedCharacters: allowed) ?? fallback
        return "attachment; filename=\"\(fallback)\"; filename*=UTF-8''\(encoded)"
    }
}

enum RemoteConnectRules {
    static let enabledKey = "remoteConnect.enabled"

    /// `ssh -o BatchMode=yes` fails fast instead of hanging on a password prompt no terminal can answer.
    static func testArguments(host: String, port: Int, user: String, keyPath: String) -> [String] {
        var args = ["-o", "BatchMode=yes", "-o", "ConnectTimeout=8", "-p", "\(port)"]
        if !keyPath.isEmpty { args += ["-i", keyPath] }
        // `--` so a host or user beginning with "-" (e.g. "-oProxyCommand=…") can never be read as an option.
        return args + ["--", "\(user)@\(host)", "echo ok"]
    }

    static func uploadArguments(files: [String], host: String, port: Int, user: String, remotePath: String, keyPath: String) -> [String] {
        var args = ["-o", "BatchMode=yes", "-o", "ConnectTimeout=10", "-P", "\(port)", "-r"]
        if !keyPath.isEmpty { args += ["-i", keyPath] }
        // `--` so a local file whose name starts with "-" is a file, not an option.
        return args + ["--"] + files + ["\(user)@\(host):\(remotePath)"]
    }

    /// The store key for what ssh/scp said, or nil when none matches (the caller then shows the tool's last line).
    static func explanationKey(_ output: String) -> String? {
        let lower = output.lowercased()
        if lower.contains("permission denied") {
            return "Bị từ chối — khóa SSH chưa được chấp nhận trên máy chủ. Thêm khóa công khai vào ~/.ssh/authorized_keys ở máy đích."
        }
        if lower.contains("could not resolve hostname") { return "Không tìm thấy máy chủ — kiểm tra lại tên host." }
        if lower.contains("connection refused") { return "Máy chủ từ chối kết nối — kiểm tra cổng và dịch vụ SSH." }
        if lower.contains("timed out") { return "Hết thời gian chờ — máy chủ không phản hồi." }
        if lower.contains("host key verification failed") {
            return "Xác minh host key thất bại. Chạy `ssh <user>@<host>` trong Terminal một lần để tin tưởng máy chủ."
        }
        return nil
    }

    static let explanationKeys = [
        "Bị từ chối — khóa SSH chưa được chấp nhận trên máy chủ. Thêm khóa công khai vào ~/.ssh/authorized_keys ở máy đích.",
        "Không tìm thấy máy chủ — kiểm tra lại tên host.", "Máy chủ từ chối kết nối — kiểm tra cổng và dịch vụ SSH.",
        "Hết thời gian chờ — máy chủ không phản hồi.",
        "Xác minh host key thất bại. Chạy `ssh <user>@<host>` trong Terminal một lần để tin tưởng máy chủ.",
    ]
}
