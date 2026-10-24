import Foundation
import AppKit

/// Kết nối từ xa — upload files to an SFTP/SCP destination.
///
/// Uses the system `scp` binary over SSH **key** authentication only. Storing
/// or replaying SSH passwords would mean holding a reusable secret in the app;
/// a key in `~/.ssh` is what macOS and every SSH tool already expect, so the
/// connection sheet asks for a key path instead of a password.
///
/// Nothing leaves the Mac until the user explicitly presses Upload — there is
/// no background sync here.
@MainActor
@Observable
final class RemoteConnectController {
    static let shared = RemoteConnectController()

    struct Destination: Identifiable, Codable, Equatable {
        var id: UUID = UUID()
        var name: String
        var host: String
        var port: Int = 22
        var user: String
        /// Absolute path on the remote host.
        var remotePath: String
        /// Path to a private key; empty = the SSH agent / default identity.
        var keyPath: String = ""

        var displayTarget: String { "\(user)@\(host):\(remotePath)" }
    }

    enum TransferState: Equatable {
        case idle
        case running(String)
        case done(String)
        case failed(String)
    }

    private(set) var destinations: [Destination] = []
    var state: TransferState = .idle

    private let key = "XFinder.RemoteDestinations"

    private init() { load() }

    /// XF-T21: the ONE reader of the catalog switch. Off ⇒ nothing is sent: test and upload refuse before any process runs.
    var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "remoteConnect.enabled") as? Bool ?? true
    }

    // MARK: CRUD

    func add(_ destination: Destination) {
        destinations.append(destination)
        persist()
    }

    func update(_ destination: Destination) {
        guard let idx = destinations.firstIndex(where: { $0.id == destination.id }) else { return }
        destinations[idx] = destination
        persist()
    }

    func remove(_ destination: Destination) {
        destinations.removeAll { $0.id == destination.id }
        persist()
    }

    // MARK: Actions

    /// `ssh -o BatchMode=yes` fails fast instead of hanging on a password
    /// prompt that has no terminal to answer it.
    func test(_ destination: Destination) async {
        guard isEnabled else { state = .failed(L10n.t("Kết nối từ xa đang tắt — bật lại ở đầu trang.")); return }
        state = .running(L10n.t("Đang kiểm tra kết nối…"))
        let args = RemoteConnectRules.testArguments(host: destination.host, port: destination.port,
                                                    user: destination.user, keyPath: destination.keyPath)

        let result = await Self.run("/usr/bin/ssh", args)
        state = result.ok
            ? .done("\(L10n.t("Kết nối thành công tới "))\(destination.host).")
            : .failed(Self.explain(result.output))
    }

    func upload(files: [URL], to destination: Destination) async {
        guard !files.isEmpty else { return }
        guard isEnabled else { state = .failed(L10n.t("Kết nối từ xa đang tắt — bật lại ở đầu trang.")); return }
        // XF-T29: uploading is the Pro gate (`.remoteConnect`) — saved destinations are kept either way.
        guard LicenseManager.shared.allows(.remoteConnect) else {
            state = .failed(L10n.t("Cần XFinder Pro để tải lên. Danh sách kết nối vẫn được giữ nguyên."))
            return
        }
        state = .running("\(L10n.t("Đang tải lên "))\(files.count)\(L10n.t(" mục…"))")

        let args = RemoteConnectRules.uploadArguments(files: files.map(\.path), host: destination.host, port: destination.port,
                                                      user: destination.user, remotePath: destination.remotePath,
                                                      keyPath: destination.keyPath)

        let result = await Self.run("/usr/bin/scp", args)
        if result.ok {
            state = .done("\(L10n.t("Đã tải lên "))\(files.count)\(L10n.t(" mục tới "))\(destination.host).")
            ActionHistoryStore.shared.record(
                kind: "remote",
                summary: "\(L10n.t("Tải lên "))\(files.count)\(L10n.t(" mục → "))\(destination.name)")
        } else {
            state = .failed(Self.explain(result.output))
        }
    }

    /// Turn ssh/scp stderr into something a user can act on. The match is `RemoteConnectRules.explanationKey` (tested);
    /// every key it can return is translated here through a literal so the L10n audits see each one.
    private nonisolated static func explain(_ output: String) -> String {
        let k = RemoteConnectRules.explanationKey(output), keys = RemoteConnectRules.explanationKeys
        if k == keys[0] {
            return L10n.t("Bị từ chối — khóa SSH chưa được chấp nhận trên máy chủ. Thêm khóa công khai vào ~/.ssh/authorized_keys ở máy đích.")
        }
        if k == keys[1] { return L10n.t("Không tìm thấy máy chủ — kiểm tra lại tên host.") }
        if k == keys[2] { return L10n.t("Máy chủ từ chối kết nối — kiểm tra cổng và dịch vụ SSH.") }
        if k == keys[3] { return L10n.t("Hết thời gian chờ — máy chủ không phản hồi.") }
        if k == keys[4] {
            return L10n.t("Xác minh host key thất bại. Chạy `ssh <user>@<host>` trong Terminal một lần để tin tưởng máy chủ.")
        }
        let tail = output.split(separator: "\n").last.map(String.init) ?? L10n.t("không rõ")
        return "\(L10n.t("Lỗi: "))\(tail)"
    }

    private nonisolated static func run(_ tool: String, _ args: [String]) async -> (ok: Bool, output: String) {
        await Task.detached {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: tool)
            p.arguments = args
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = pipe
            // No terminal is attached, so make sure ssh never tries to prompt.
            var env = ProcessInfo.processInfo.environment
            env["SSH_ASKPASS"] = ""
            env["DISPLAY"] = ""
            p.environment = env
            guard (try? p.run()) != nil else { return (false, "\(L10n.t("không chạy được "))\(tool)") }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            return (p.terminationStatus == 0, String(data: data, encoding: .utf8) ?? "")
        }.value
    }

    // MARK: Persistence (no secrets — only host/user/path/key *location*)

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([Destination].self, from: data) else { return }
        destinations = decoded
    }

    private func persist() {
        guard let encoded = try? JSONEncoder().encode(destinations) else { return }
        UserDefaults.standard.set(encoded, forKey: key)
    }
}
