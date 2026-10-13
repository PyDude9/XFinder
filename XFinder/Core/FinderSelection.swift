import Foundation

/// The current Finder selection, read through Apple Events (Automation-gated: -1743 means XFinder is not allowed to
/// control Finder). One implementation for every page that acts on "what is selected in Finder" — it used to live
/// privately inside Thao tác Finder.
enum FinderSelection {
    enum Result {
        case success([URL])
        case failure(String)
    }

    static func read() async -> Result {
        await Task.detached {
            let script = """
            tell application "Finder"
                set sel to selection as alias list
                set out to ""
                repeat with anItem in sel
                    set out to out & POSIX path of anItem & linefeed
                end repeat
                return out
            end tell
            """
            guard let apple = NSAppleScript(source: script) else {
                return .failure(L10n.t("Không tạo được AppleScript."))
            }
            var err: NSDictionary?
            let output = apple.executeAndReturnError(&err)
            if let err {
                let code = (err[NSAppleScript.errorNumber] as? Int) ?? 0
                if code == -1743 {
                    return .failure(L10n.t("Cần quyền Tự động hóa cho Finder — Cài đặt hệ thống → Quyền riêng tư & Bảo mật → Tự động hóa → XFinder → bật Finder."))
                }
                let msg = (err[NSAppleScript.errorMessage] as? String) ?? "\(L10n.t("Lỗi")) \(code)"
                return .failure("\(L10n.t("Không đọc được lựa chọn")): \(msg)")
            }
            let paths = (output.stringValue ?? "")
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            return .success(paths.map { URL(fileURLWithPath: $0) })
        }.value
    }
}
