import AppKit
import SwiftUI
import NetFS

/// XF-T30 W3 — Connect to Server (⌘K): smb / afp / nfs / ftp / webdav URLs, recent + favorite servers, mounting through
/// NetFS (the system asks for credentials — XFinder never reads or stores them). W3 builder (AppKit).
///
/// `NetFSMountURLAsync(url, mountpath: nil, user: nil, passwd: nil, …)` — passing nil for user/passwd routes
/// authentication through the system's own NetAuth agent, which puts up its own password sheet; this class never
/// sees, reads, or stores a credential (CLAUDE.md rule: never read credential/token material), matching the
/// contract's own wording verbatim.
@MainActor
final class ConnectToServer {
    static let shared = ConnectToServer()

    private static let defaultsKey = "fileBrowser.connectToServer.servers"
    private static let supportedSchemes: Set<String> = ["smb", "afp", "nfs", "ftp", "webdav", "https"]

    private var panel: NSPanel?
    private var model: ConnectToServerModel?

    private init() {}

    /// A recent or favourite server entry. `favorite` entries never age out of the list the way plain recents do.
    struct ServerEntry: Codable, Equatable, Identifiable, Sendable {
        var id: String { urlString }
        var urlString: String
        var favorite: Bool
        var lastConnected: Date
    }

    struct Store: Codable, Equatable, Sendable {
        var entries: [ServerEntry] = []

        static let recentLimit = 10

        static func decode(_ data: Data?) -> Store {
            guard let data, let store = try? JSONDecoder().decode(Store.self, from: data) else { return Store() }
            return store
        }

        func encoded() -> Data {
            (try? JSONEncoder().encode(self)) ?? Data()
        }

        /// Recents newest-first, favourites always kept (never dropped by the recent-count limit); a server that is
        /// both recent and favourite keeps its favourite flag.
        mutating func noteConnected(_ urlString: String) {
            let now = Date()
            if let index = entries.firstIndex(where: { $0.urlString == urlString }) {
                entries[index].lastConnected = now
            } else {
                entries.append(ServerEntry(urlString: urlString, favorite: false, lastConnected: now))
            }
            trimRecents()
        }

        mutating func setFavorite(_ urlString: String, _ isFavorite: Bool) {
            if let index = entries.firstIndex(where: { $0.urlString == urlString }) {
                entries[index].favorite = isFavorite
            } else if isFavorite {
                entries.append(ServerEntry(urlString: urlString, favorite: true, lastConnected: Date()))
            }
            trimRecents()
        }

        mutating func remove(_ urlString: String) {
            entries.removeAll { $0.urlString == urlString }
        }

        private mutating func trimRecents() {
            let favorites = entries.filter(\.favorite)
            let recents = entries.filter { !$0.favorite }
                .sorted { $0.lastConnected > $1.lastConnected }
                .prefix(Store.recentLimit)
            entries = favorites + Array(recents)
        }
    }

    /// The ONE reader+writer of `fileBrowser.connectToServer.servers` (JSON `Store`) — kept in this file rather than
    /// `BrowserSettings` since Connect to Server is this builder's own self-contained feature (noted in the build
    /// report for the integrator, who may fold it into `BrowserSettings` alongside the other `fileBrowser.*` keys).
    static var store: Store {
        get { Store.decode(UserDefaults.standard.data(forKey: defaultsKey)) }
        set { UserDefaults.standard.set(newValue.encoded(), forKey: defaultsKey) }
    }

    /// Validates a server address string into a URL this class will attempt to mount — accepts the five schemes the
    /// sheet advertises, with or without a trailing path. Pure enough to unit test without any AppKit/NetFS call,
    /// exposed `static` so a view or test can check an address before `present` ever runs.
    static func parseAddress(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
              supportedSchemes.contains(scheme), url.host != nil
        else { return nil }
        return url
    }

    /// Shows the sheet on `window`; a successful mount calls `opened(mountPath)`.
    func present(on window: NSWindow?, opened: @escaping @MainActor (String) -> Void) {
        guard let window else { return }
        let model = ConnectToServerModel(
            onConnect: { [weak self] url in
                self?.connect(url: url, window: window, opened: opened)
            },
            onCancel: { [weak self] in
                self?.dismiss(window: window)
            }
        )
        self.model = model
        let hosting = NSHostingView(rootView: ConnectToServerSheetView(model: model))
        hosting.sizingOptions = []
        let contentSize = NSSize(width: 420, height: 280)
        let sheet = NSPanel(contentRect: NSRect(origin: .zero, size: contentSize),
                           styleMask: [.titled, .closable], backing: .buffered, defer: false)
        sheet.isReleasedWhenClosed = false
        sheet.contentView = hosting
        sheet.contentMinSize = contentSize
        self.panel = sheet
        window.beginSheet(sheet)
    }

    private func dismiss(window: NSWindow) {
        guard let panel else { return }
        window.endSheet(panel)
        self.panel = nil
        self.model = nil
    }

    /// `NetFSMountURLAsync` with `user`/`passwd` both nil: the system's NetAuth agent puts up its own credential
    /// sheet and this process never sees what was typed into it — matching the contract line verbatim ("hỏi mật
    /// khẩu do hệ thống — XFinder không đọc/không lưu mật khẩu").
    private func connect(url: URL, window: NSWindow, opened: @escaping @MainActor (String) -> Void) {
        model?.isConnecting = true
        model?.errorMessage = nil
        var requestID: AsyncRequestID?
        let status = NetFSMountURLAsync(
            url as CFURL, nil, nil, nil, nil, nil, &requestID, DispatchQueue.main
        ) { [weak self] status, _, mountPoints in
            Task { @MainActor in
                guard let self else { return }
                self.model?.isConnecting = false
                if status == 0, let first = (mountPoints as? [String])?.first {
                    var store = Self.store
                    store.noteConnected(url.absoluteString)
                    Self.store = store
                    self.dismiss(window: window)
                    opened(first)
                } else if status != -128 {   // userCanceledErr: the NetAuth sheet's own Cancel — not an XFinder error.
                    self.model?.errorMessage = L10n.t("Không kết nối được máy chủ")
                }
            }
        }
        if status != 0 {
            model?.isConnecting = false
            if status != -128 {
                model?.errorMessage = L10n.t("Không kết nối được máy chủ")
            }
        }
    }
}

/// Backing state for the sheet — a plain `@Observable` so the SwiftUI view can bind to it without `ConnectToServer`
/// itself needing to be a View-shaped type.
@MainActor @Observable
final class ConnectToServerModel {
    var addressText: String = ""
    var isConnecting: Bool = false
    var errorMessage: String?
    let onConnect: (URL) -> Void
    let onCancel: () -> Void

    init(onConnect: @escaping (URL) -> Void, onCancel: @escaping () -> Void) {
        self.onConnect = onConnect
        self.onCancel = onCancel
    }

    var canConnect: Bool {
        !isConnecting && ConnectToServer.parseAddress(addressText) != nil
    }

    func submit() {
        guard let url = ConnectToServer.parseAddress(addressText) else {
            errorMessage = L10n.t("Địa chỉ không hợp lệ (smb:// afp:// nfs:// ftp:// webdav)")
            return
        }
        onConnect(url)
    }
}

/// The Connect to Server sheet: address field, recent + favourite servers, Connect/Cancel.
struct ConnectToServerSheetView: View {
    @Bindable var model: ConnectToServerModel
    @State private var store = ConnectToServer.store

    var body: some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.section) {
            Text(L10n.t("Kết nối máy chủ"))
                .font(XFinderTokens.Font.row.weight(.semibold))
            TextField(L10n.t("smb://may-chu/chia-se"), text: $model.addressText)
                .textFieldStyle(.roundedBorder)
                .onSubmit { model.submit() }
            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(XFinderTokens.Font.caption)
                    .foregroundColor(.red)
            }
            if !store.entries.isEmpty {
                Text(L10n.t("Gần đây và ưa thích"))
                    .font(XFinderTokens.Font.caption)
                    .foregroundColor(.secondary)
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(sortedEntries) { entry in
                            serverRow(entry)
                        }
                    }
                }
                .frame(maxHeight: 120)
            }
            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button(L10n.t("Huỷ")) { model.onCancel() }
                Button(L10n.t("Kết nối")) { model.submit() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.canConnect)
            }
        }
        .padding(XFinderTokens.Space.section)
    }

    /// Favourites first (alphabetical), then recents newest-first — same grouping Connect to Server's own store
    /// already keeps, re-sorted here only for display stability independent of store write order.
    private var sortedEntries: [ConnectToServer.ServerEntry] {
        let favorites = store.entries.filter(\.favorite).sorted { $0.urlString < $1.urlString }
        let recents = store.entries.filter { !$0.favorite }.sorted { $0.lastConnected > $1.lastConnected }
        return favorites + recents
    }

    private func serverRow(_ entry: ConnectToServer.ServerEntry) -> some View {
        HStack(spacing: XFinderTokens.Space.tight) {
            Image(systemName: entry.favorite ? "star.fill" : "clock")
                .font(XFinderTokens.Font.caption)
                .foregroundColor(.secondary)
            Text(entry.urlString)
                .font(XFinderTokens.Settings.sidebarRow)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            Button {
                var updated = store
                updated.setFavorite(entry.urlString, !entry.favorite)
                ConnectToServer.store = updated
                store = updated
            } label: {
                Image(systemName: entry.favorite ? "star.fill" : "star")
                    .font(XFinderTokens.Font.caption)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture { model.addressText = entry.urlString }
    }
}
