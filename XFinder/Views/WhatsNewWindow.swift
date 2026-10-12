import SwiftUI
import AppKit

/// N7 — the "Có gì mới" window: one line per note with a button to its page. Its own window, not a sheet (an open
/// SwiftUI sheet blocks `NSApp.terminate` — measured for the setup window, same reason here).
@MainActor
final class WhatsNewWindowController {
    static let shared = WhatsNewWindowController()
    private var window: NSWindow?

    var currentVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0" }

    private var isExistingUser: Bool {
        if UserDefaults.standard.object(forKey: Onboarding.completedKey) != nil { return true }
        let fm = FileManager.default
        let dir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fm.temporaryDirectory
        return fm.fileExists(atPath: dir.appendingPathComponent("XFinder/xfinder.db").path)
    }

    /// Called once from `applicationDidFinishLaunching`, after the first-run setup decision: a fresh install is on
    /// setup and simply gets this version recorded as seen; an existing user sees the notes once per version.
    func presentIfNeeded(setupShowing: Bool) {
        let d = UserDefaults.standard
        if setupShowing || !isExistingUser {
            d.set(currentVersion, forKey: WhatsNewRules.key)
            return
        }
        if WhatsNewRules.shouldShow(lastSeen: d.string(forKey: WhatsNewRules.key), current: currentVersion, isExistingUser: true) {
            present(currentVersion)
        }
    }

    func present(_ version: String) {
        if let window { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let host = NSHostingController(rootView: WhatsNewView(version: version) { [weak self] in self?.close() })
        let w = NSWindow(contentViewController: host)
        w.title = "\(L10n.t("Có gì mới trong "))\(version)"
        w.styleMask = [.titled, .closable]
        w.isReleasedWhenClosed = false
        w.center()
        window = w
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { [weak self] _ in
            Task { @MainActor in
                UserDefaults.standard.set(version, forKey: WhatsNewRules.key)
                self?.window = nil
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    func close() {
        UserDefaults.standard.set(currentVersion, forKey: WhatsNewRules.key)
        window?.close()
        window = nil
    }
}

struct WhatsNewView: View {
    let version: String
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
            ScrollView {
                VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
                    ForEach(WhatsNewRules.notes(for: version)) { n in
                        HStack(alignment: .top, spacing: XFinderTokens.Space.inline) {
                            Image(systemName: n.symbol).font(.system(size: 18)).foregroundColor(.accentColor).frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L10n.t(n.titleKey)).font(XFinderTokens.Font.row).bold()
                                Text(L10n.t(n.bodyKey)).font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                            if let dest = n.destinationRaw.flatMap(SidebarDestination.init(rawValue:)) {
                                Button(L10n.t("Mở")) {
                                    AppState.shared.navigate(to: dest)
                                    AppState.shared.bringMainWindowFront()
                                }
                                .controlSize(.small)
                            }
                        }
                    }
                }
                .padding(.trailing, XFinderTokens.Space.inline)
            }
            HStack {
                Spacer()
                Button(L10n.t("Xong")) { onDone() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }
        }
        .padding(XFinderTokens.Space.section)
        .frame(width: 560, height: 440)
    }
}
