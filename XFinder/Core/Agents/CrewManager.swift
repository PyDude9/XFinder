import Foundation
import os

/// P7b — the live half of "Crew" (rules, measurements and decisions: `CrewRules`). Starts one windowless Claude Code
/// session per role, watches the crew's inbox for `xfinder-crew send` requests, and runs the relay: every delivery is one
/// write through `WindowlessSessionManager.deliver` (the single stdin gate), every turn end may carry a reply back.
/// Nothing polls: the inbox is a folder watch, turn ends come from the manager's stream.
///
/// Lifetime: in memory only. Members die with XFinder (P7a); the crew folder is removed on Stop, and any folder left by a
/// crash is removed at the next launch (`removeStaleFolders`). The board lives in memory (≤ 200 entries); each member's own
/// conversation stays in Claude Code.
@MainActor @Observable
final class CrewManager {
    static let shared = CrewManager()
    @ObservationIgnored private let log = Logger(subsystem: "com.xfinder.app", category: "Crew")

    struct Crew: Identifiable {
        let id: String
        let template: CrewRules.Template
        let folder: String
        let goal: String
        let createdAt: Date
        var relay: CrewRules.Relay
        /// role → session id (lower-case UUID)
        var members: [String: String]
        var stopped: Bool { relay.stopped }
    }

    enum StartError: Error, Equatable {
        case badFolder, noScript, setupFailed, member(WindowlessSessionManager.StartError)
        var key: String {
            switch self {
            case .badFolder: return "Thư mục không còn."
            case .noScript, .setupFailed: return "Không tạo được crew."
            case .member(let e): return e.key
            }
        }
    }

    private(set) var crews: [Crew] = []
    var liveCrews: [Crew] { crews.filter { !$0.stopped } }

    @ObservationIgnored private var tokens: [String: [String: String]] = [:]     // crew id → token → role
    @ObservationIgnored private var watchers: [String: DispatchSourceFileSystemObject] = [:]
    @ObservationIgnored private var started = false
    /// The notch says "crew paused — waiting for you" (set by `NotchSurfaceController`; kept out of this file).
    @ObservationIgnored var onCapReached: ((String) -> Void)?
    /// Test seam for the e2e harness (no app bundle there). Never set by the app.
    @ObservationIgnored var scriptSourceOverride: URL?

    private init() {}

    // MARK: - Paths

    nonisolated static var root: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/XFinder/Agents/crew", isDirectory: true)
    }
    nonisolated static var binDir: URL { root.appendingPathComponent("bin", isDirectory: true) }
    nonisolated static func folder(for crewID: String) -> URL { root.appendingPathComponent(crewID, isDirectory: true) }

    /// Once per run: the crew relay listens to the windowless manager, and folders a crashed run left behind go.
    func startIfNeeded() {
        guard !started else { return }
        started = true
        WindowlessSessionManager.shared.crewObserver = { [weak self] signal in self?.handle(signal) }
        Self.removeStaleFolders()
    }

    nonisolated static func removeStaleFolders() {
        let fm = FileManager.default
        for url in (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        where url.lastPathComponent != "bin" && UUID(uuidString: url.lastPathComponent) != nil {
            try? fm.removeItem(at: url)
        }
    }

    // MARK: - Start

    /// A crew from `template` in `folder`. The lead gets `goal` as its first message (one model turn); the others start
    /// with no message and spend nothing until a crewmate writes to them.
    @discardableResult
    func start(template: CrewRules.Template, folder: URL, goal: String) async throws -> String {
        startIfNeeded()
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDir), isDir.boolValue else { throw StartError.badFolder }
        guard let goalText = WindowlessRules.cleanMessage(goal) else { throw StartError.setupFailed }
        let crewID = UUID().uuidString.lowercased()
        let dir = Self.folder(for: crewID)
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: dir.appendingPathComponent("inbox", isDirectory: true), withIntermediateDirectories: true,
                                   attributes: [.posixPermissions: 0o700])
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
            let roster = template.roles.map { "\($0.name) — \($0.purpose)" }.joined(separator: "\n") + "\n"
            try Data(roster.utf8).write(to: dir.appendingPathComponent("roster.txt"), options: .atomic)
            try installScript()
        } catch is StartError {
            try? fm.removeItem(at: dir); throw StartError.noScript
        } catch {
            try? fm.removeItem(at: dir); throw StartError.setupFailed
        }

        var roleTokens: [String: String] = [:]
        var members: [String: String] = [:]
        let lead = template.lead.name
        for role in template.roles {
            let token = UUID().uuidString
            roleTokens[token] = role.name
            let env = ["XFINDER_CREW_DIR": dir.path, "XFINDER_CREW_TOKEN": token, "XFINDER_CREW_ROLE": role.name]
            do {
                let sid = try await WindowlessSessionManager.shared.startClaude(
                    folder: folder, firstMessage: nil,
                    extraArguments: CrewRules.launchArguments(for: role, in: template),
                    extraEnvironment: env, pathPrepend: Self.binDir.path)
                members[role.name] = sid
            } catch let e as WindowlessSessionManager.StartError {
                for sid in members.values { WindowlessSessionManager.shared.stop(sid) }
                try? fm.removeItem(at: dir)
                throw StartError.member(e)
            }
        }
        tokens[crewID] = roleTokens
        let crew = Crew(id: crewID, template: template, folder: folder.path, goal: goalText, createdAt: Date(),
                        relay: CrewRules.Relay(roles: template.roles.map(\.name), busy: [lead]), members: members)
        crews.insert(crew, at: 0)
        watchInbox(crewID)
        // P7b review: the goal goes to the lead only once the crew is registered and its inbox watched — a lead turn
        // that ended before that would have reached no relay and left the lead marked busy forever.
        guard let leadSID = members[lead],
              WindowlessSessionManager.shared.deliver(goalText, to: leadSID) == .sent else {
            stop(crewID)
            forget(crewID)
            throw StartError.setupFailed
        }
        log.info("crew started template=\(template.rawValue) members=\(members.count)")
        return crewID
    }

    /// The bundled CLI, copied next to the crews (0700) — a member's PATH starts with that folder.
    private func installScript() throws {
        guard let src = scriptSourceOverride ?? Bundle.main.url(forResource: "xfinder-crew", withExtension: "zsh") else { throw StartError.noScript }
        let fm = FileManager.default
        try fm.createDirectory(at: Self.binDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let dest = Self.binDir.appendingPathComponent("xfinder-crew")
        let data = try Data(contentsOf: src)
        if (try? Data(contentsOf: dest)) != data { try data.write(to: dest, options: .atomic) }
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dest.path)
    }

    // MARK: - Inbox

    private func watchInbox(_ crewID: String) {
        let inbox = Self.folder(for: crewID).appendingPathComponent("inbox", isDirectory: true)
        let fd = open(inbox.path, O_EVTONLY)
        guard fd >= 0 else { log.error("inbox watch failed"); return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .extend, .rename], queue: .main)
        src.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.readInbox(crewID) } }
        src.setCancelHandler { close(fd) }
        src.resume()
        watchers[crewID] = src
        readInbox(crewID)
    }

    private func readInbox(_ crewID: String) {
        guard let i = crews.firstIndex(where: { $0.id == crewID }), let roleTokens = tokens[crewID] else { return }
        let inbox = Self.folder(for: crewID).appendingPathComponent("inbox", isDirectory: true)
        let fm = FileManager.default
        let files = ((try? fm.contentsOfDirectory(at: inbox, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "json" && !$0.lastPathComponent.hasPrefix(".") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !files.isEmpty else { return }
        var effects: [CrewRules.Effect] = []
        for f in files {
            let data = (try? Data(contentsOf: f)) ?? Data()
            try? fm.removeItem(at: f)
            guard data.count <= 64 * 1024,
                  let req = CrewRules.parseRequest(data, name: f.lastPathComponent, tokens: roleTokens,
                                                    roles: crews[i].relay.roles) else {
                log.info("crew inbox: a request was refused")
                continue
            }
            effects += crews[i].relay.receive(req, at: Date())
        }
        run(effects, crewID: crewID)
    }

    // MARK: - Signals from the windowless manager

    private func handle(_ signal: WindowlessSessionManager.Signal) {
        for i in crews.indices where !crews[i].stopped {
            let id: String
            switch signal {
            case .turnEnded(let sid, _), .processEnded(let sid): id = sid
            }
            guard let role = crews[i].members.first(where: { $0.value == id })?.key else { continue }
            let effects: [CrewRules.Effect]
            switch signal {
            case .turnEnded(_, let result): effects = crews[i].relay.turnEnded(role, result: result, at: Date())
            case .processEnded: effects = crews[i].relay.memberEnded(role, at: Date())
            }
            run(effects, crewID: crews[i].id)
        }
    }

    private func run(_ effects: [CrewRules.Effect], crewID: String) {
        var pending = effects
        while !pending.isEmpty {
            let e = pending.removeFirst()
            guard let i = crews.firstIndex(where: { $0.id == crewID }) else { return }
            switch e {
            case .deliver(let role, let text):
                guard let sid = crews[i].members[role] else { continue }
                switch WindowlessSessionManager.shared.deliver(text, to: sid) {
                case .sent: break
                case .busy: pending += crews[i].relay.deliveryFailed(role, gone: false, at: Date())
                case .gone: pending += crews[i].relay.deliveryFailed(role, gone: true, at: Date())
                }
            case .stopMember(let role):
                if let sid = crews[i].members[role] { WindowlessSessionManager.shared.stop(sid) }
            case .noticeCapReached:
                syncPausedMarker(crewID)
                onCapReached?(crewID)
            }
        }
        syncPausedMarker(crewID)
    }

    /// `paused` exists while the relay is paused, so `xfinder-crew send` can say so.
    private func syncPausedMarker(_ crewID: String) {
        guard let crew = crews.first(where: { $0.id == crewID }) else { return }
        let marker = Self.folder(for: crewID).appendingPathComponent("paused")
        if crew.relay.pause != nil && !crew.stopped {
            FileManager.default.createFile(atPath: marker.path, contents: Data())
        } else {
            try? FileManager.default.removeItem(at: marker)
        }
    }

    // MARK: - The person's controls

    func pause(_ crewID: String) {
        guard let i = crews.firstIndex(where: { $0.id == crewID }) else { return }
        crews[i].relay.pauseByPerson(at: Date())
        syncPausedMarker(crewID)
    }

    func resume(_ crewID: String) {
        guard let i = crews.firstIndex(where: { $0.id == crewID }) else { return }
        run(crews[i].relay.resume(at: Date()), crewID: crewID)
    }

    /// Stop the crew: every member's process, the relay, the inbox watch, the crew folder.
    func stop(_ crewID: String) {
        guard let i = crews.firstIndex(where: { $0.id == crewID }) else { return }
        run(crews[i].relay.stop(at: Date()), crewID: crewID)
        watchers.removeValue(forKey: crewID)?.cancel()
        tokens[crewID] = nil
        try? FileManager.default.removeItem(at: Self.folder(for: crewID))
    }

    func forget(_ crewID: String) {
        guard let crew = crews.first(where: { $0.id == crewID }), crew.stopped else { return }
        crews.removeAll { $0.id == crewID }
    }

    /// XFinder is quitting: members stop through `WindowlessSessionManager.stopAll`; the folders go here.
    func stopAllForQuit() {
        for c in crews where !c.stopped {
            watchers.removeValue(forKey: c.id)?.cancel()
            try? FileManager.default.removeItem(at: Self.folder(for: c.id))
        }
    }

    // MARK: - Reading

    /// Which crew (and role) a hosted session belongs to.
    func membership(of sessionID: String) -> (crew: Crew, role: String)? {
        let sid = sessionID.lowercased()
        for c in crews { if let role = c.members.first(where: { $0.value == sid })?.key { return (c, role) } }
        return nil
    }

    /// Claude Code's own estimate summed over the members (not a bill).
    func costUSD(_ crew: Crew) -> Double? {
        let costs = crew.members.values.compactMap { WindowlessSessionManager.shared.records[$0]?.costUSD }
        return costs.isEmpty ? nil : costs.reduce(0, +)
    }
}
