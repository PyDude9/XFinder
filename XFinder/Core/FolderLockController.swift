import Foundation
import AppKit

/// Khóa thư mục — real encryption, not a hidden-file trick.
///
/// **Why an encrypted disk image.** macOS has no API to password-protect a
/// folder in place. Chmod/`chflags hidden` only *hides* — anyone with the Mac
/// can reveal it in seconds, so shipping that as "locked" would be dishonest.
/// Instead this uses `hdiutil` to build an **AES-256 encrypted sparse bundle**:
/// the same mechanism as FileVault-encrypted images, with the password held in
/// the macOS Keychain (or typed each time, user's choice).
///
/// Locked  = image detached; contents are ciphertext on disk.
/// Unlocked = image attached at a mount point and open in Finder.
///
/// The original folder is only removed after a verified copy exists inside the
/// image — a failed encrypt must never lose data.
@MainActor
@Observable
final class FolderLockController {
    static let shared = FolderLockController()

    struct Vault: Identifiable, Codable, Equatable {
        var id: UUID = UUID()
        /// `.sparsebundle` holding the encrypted contents.
        var imagePath: String
        var name: String
        /// Where it mounts when unlocked.
        var mountPath: String?
        var createdAt: Date = Date()

        var isMounted: Bool {
            guard let mountPath else { return false }
            return FileManager.default.fileExists(atPath: mountPath)
        }
    }

    private(set) var vaults: [Vault] = []
    var lastError: String?
    var busy = false

    private let key = "XFinder.FolderVaults"

    private init() { load() }

    // MARK: Create

    /// Encrypts `folder` into a new vault. `deleteOriginal` is honoured only
    /// after the copy is verified.
    func createVault(from folder: URL, password: String, deleteOriginal: Bool) async -> Bool {
        busy = true
        lastError = nil
        defer { busy = false }

        let name = folder.lastPathComponent
        let imagePath = folder.deletingLastPathComponent()
            .appendingPathComponent("\(name).sparsebundle").path

        guard !FileManager.default.fileExists(atPath: imagePath) else {
            lastError = "\(L10n.t("Đã tồn tại “"))\(name).sparsebundle\(L10n.t("” ở thư mục này."))"
            return false
        }

        // hdiutil reads the password from stdin with -stdinpass.
        let created = await Self.run(
            ["/usr/bin/hdiutil", "create",
             "-type", "SPARSEBUNDLE",
             "-encryption", "AES-256",
             "-stdinpass",
             "-volname", name,
             "-fs", "APFS",
             "-srcfolder", folder.path,
             imagePath],
            stdin: password)

        guard created.ok else {
            lastError = "\(L10n.t("Không tạo được vault: "))\(created.output)"
            return false
        }

        // Verify by attaching and comparing the top-level entry count before
        // anything is deleted.
        guard let mount = await attach(imagePath: imagePath, password: password) else {
            lastError = L10n.t("Tạo xong nhưng không mở được để kiểm tra — giữ nguyên thư mục gốc.")
            return false
        }
        let fm = FileManager.default
        let src = (try? fm.contentsOfDirectory(atPath: folder.path).count) ?? -1
        let dst = (try? fm.contentsOfDirectory(atPath: mount).count) ?? -2
        _ = await Self.run(["/usr/bin/hdiutil", "detach", mount, "-quiet"])

        guard src >= 0, dst >= src else {
            lastError = L10n.t("Kiểm tra nội dung thất bại — giữ nguyên thư mục gốc để an toàn.")
            return false
        }

        if deleteOriginal {
            // Trash, never rm: recoverable if the user changes their mind.
            do { try fm.trashItem(at: folder, resultingItemURL: nil) }
            catch { lastError = "\(L10n.t("Đã mã hóa nhưng không xóa được thư mục gốc: "))\(error.localizedDescription)" }
        }

        vaults.append(Vault(imagePath: imagePath, name: name))
        persist()
        return true
    }

    // MARK: Lock / unlock

    func unlock(_ vault: Vault, password: String) async -> Bool {
        busy = true
        lastError = nil
        defer { busy = false }
        guard let mount = await attach(imagePath: vault.imagePath, password: password) else {
            lastError = L10n.t("Sai mật khẩu hoặc không mở được vault.")
            return false
        }
        if let idx = vaults.firstIndex(where: { $0.id == vault.id }) {
            vaults[idx].mountPath = mount
            persist()
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: mount))
        return true
    }

    func lock(_ vault: Vault) async -> Bool {
        busy = true
        lastError = nil
        defer { busy = false }
        guard let mount = vault.mountPath else { return true }
        let result = await Self.run(["/usr/bin/hdiutil", "detach", mount, "-quiet"])
        guard result.ok else {
            lastError = L10n.t("Không khóa được — có thể còn file đang mở trong vault.")
            return false
        }
        if let idx = vaults.firstIndex(where: { $0.id == vault.id }) {
            vaults[idx].mountPath = nil
            persist()
        }
        return true
    }

    /// Removes the vault from XFinder's list. The encrypted image stays on
    /// disk — deleting user data silently would be unacceptable.
    func forget(_ vault: Vault) {
        vaults.removeAll { $0.id == vault.id }
        persist()
    }

    private func attach(imagePath: String, password: String) async -> String? {
        let result = await Self.run(
            ["/usr/bin/hdiutil", "attach", imagePath,
             "-stdinpass", "-nobrowse", "-plist"],
            stdin: password)
        guard result.ok else { return nil }
        // The plist lists mount points under "mount-point" keys.
        guard let range = result.output.range(of: "<key>mount-point</key>") else { return nil }
        let tail = result.output[range.upperBound...]
        guard let open = tail.range(of: "<string>"),
              let close = tail.range(of: "</string>") else { return nil }
        return String(tail[open.upperBound..<close.lowerBound])
    }

    // MARK: Process helper

    private nonisolated static func run(_ cmd: [String], stdin: String? = nil) async -> (ok: Bool, output: String) {
        await Task.detached {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: cmd[0])
            p.arguments = Array(cmd.dropFirst())
            let out = Pipe()
            p.standardOutput = out
            p.standardError = out
            let input = Pipe()
            if stdin != nil { p.standardInput = input }
            guard (try? p.run()) != nil else { return (false, L10n.t("không chạy được hdiutil")) }
            if let stdin {
                // A child that exits before reading (bad arguments) would raise SIGPIPE and kill XFinder (measured: exit
                // 141). With F_SETNOSIGPIPE the write fails instead, and the exit status says what happened.
                _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
                try? input.fileHandleForWriting.write(contentsOf: Data(stdin.utf8))
                try? input.fileHandleForWriting.close()
            }
            let data = out.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            return (p.terminationStatus == 0, String(data: data, encoding: .utf8) ?? "")
        }.value
    }

    // MARK: Persistence (metadata only — never the password)

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([Vault].self, from: data) else { return }
        vaults = decoded
    }

    private func persist() {
        guard let encoded = try? JSONEncoder().encode(vaults) else { return }
        UserDefaults.standard.set(encoded, forKey: key)
    }
}
