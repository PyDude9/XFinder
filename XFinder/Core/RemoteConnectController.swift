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
        state = .running("Đang kiểm tra kết nối…")
        var args = ["-o", "BatchMode=yes", "-o", "ConnectTimeout=8",
                    "-p", "\(destination.port)"]
        if !destination.keyPath.isEmpty { args += ["-i", destination.keyPath] }
        args += ["\(destination.user)@\(destination.host)", "echo ok"]

        let result = await Self.run("/usr/bin/ssh", args)
        state = result.ok
            ? .done("Kết nối thành công tới \(destination.host).")
            : .failed(Self.explain(result.output))
    }

    func upload(files: [URL], to destination: Destination) async {
        guard !files.isEmpty else { return }
        state = .running("Đang tải lên \(files.count) mục…")

        var args = ["-o", "BatchMode=yes", "-o", "ConnectTimeout=10",
                    "-P", "\(destination.port)", "-r"]
        if !destination.keyPath.isEmpty { args += ["-i", destination.keyPath] }
        args += files.map(\.path)
        args += ["\(destination.user)@\(destination.host):\(destination.remotePath)"]

        let result = await Self.run("/usr/bin/scp", args)
        if result.ok {
            state = .done("Đã tải lên \(files.count) mục tới \(destination.host).")
            ActionHistoryStore.shared.record(
                kind: "remote",
                summary: "Tải lên \(files.count) mục → \(destination.name)")
        } else {
            state = .failed(Self.explain(result.output))
        }
    }

    /// Turn ssh/scp stderr into something a user can act on.
    private nonisolated static func explain(_ output: String) -> String {
        let lower = output.lowercased()
        if lower.contains("permission denied") {
            return "Bị từ chối — khóa SSH chưa được chấp nhận trên máy chủ. Thêm khóa công khai vào ~/.ssh/authorized_keys ở máy đích."
        }
        if lower.contains("could not resolve hostname") {
            return "Không tìm thấy máy chủ — kiểm tra lại tên host."
        }
        if lower.contains("connection refused") {
            return "Máy chủ từ chối kết nối — kiểm tra cổng và dịch vụ SSH."
        }
        if lower.contains("timed out") || lower.contains("operation timed out") {
            return "Hết thời gian chờ — máy chủ không phản hồi."
        }
        if lower.contains("host key verification failed") {
            return "Xác minh host key thất bại. Chạy `ssh <user>@<host>` trong Terminal một lần để tin tưởng máy chủ."
        }
        let tail = output.split(separator: "\n").last.map(String.init) ?? "không rõ"
        return "Lỗi: \(tail)"
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
            guard (try? p.run()) != nil else { return (false, "không chạy được \(tool)") }
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
