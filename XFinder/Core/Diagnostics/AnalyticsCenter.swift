import AppKit
import CryptoKit

/// Sends the anonymous daily report (`AnalyticsRules`) when the rules allow it. No timer: the decision runs at launch
/// and whenever XFinder becomes active, so a Mac left alone sends nothing until it is used again.
///
/// The receiver is TelemetryDeck, configured by two PUBLIC Info.plist strings (`XFAnalyticsTelemetryDeckAppID`,
/// `XFAnalyticsTelemetryDeckNamespace`). With either missing — the state of every build until the owner creates the
/// TelemetryDeck app — nothing is announced and nothing is sent, and the page says so.
@MainActor
final class AnalyticsCenter {
    static let shared = AnalyticsCenter()
    private init() {}

    /// The ONE reader of `analytics.optOut` (default false — the owner chose opt-out: sending is on until refused).
    nonisolated static var isOptedOut: Bool {
        UserDefaults.standard.object(forKey: "analytics.optOut") as? Bool ?? false
    }

    private enum Key {
        static let noticeShownAt = "analytics.noticeShownAt"
        static let noticeSchema = "analytics.noticeSchema"
        static let lastSentAt = "analytics.lastSentAt"
        static let lastAttemptAt = "analytics.lastAttemptAt"
    }

    private var sending = false
    private var noticeOpen = false

    var receiver: AnalyticsRules.Receiver? {
        AnalyticsRules.receiver(
            appID: Bundle.main.object(forInfoDictionaryKey: "XFAnalyticsTelemetryDeckAppID") as? String,
            namespace: Bundle.main.object(forInfoDictionaryKey: "XFAnalyticsTelemetryDeckNamespace") as? String)
    }

    var lastSentAt: Date? { UserDefaults.standard.object(forKey: Key.lastSentAt) as? Date }

    func state() -> AnalyticsRules.State {
        let d = UserDefaults.standard
        return AnalyticsRules.State(
            optedOut: Self.isOptedOut,
            configured: receiver != nil,
            noticeShownAt: d.object(forKey: Key.noticeShownAt) as? Date,
            noticeSchema: d.object(forKey: Key.noticeSchema) as? Int,
            lastSentAt: d.object(forKey: Key.lastSentAt) as? Date,
            lastAttemptAt: d.object(forKey: Key.lastAttemptAt) as? Date,
            onboardingShowing: Onboarding.shouldShow(completedVersion: d.object(forKey: Onboarding.completedKey) as? Int))
    }

    func currentAction() -> AnalyticsRules.Action { AnalyticsRules.nextAction(state(), now: Date()) }

    /// Launch (a few seconds after windows settle) and every `didBecomeActive`.
    func evaluate() {
        switch currentAction() {
        case .showNotice: presentNotice()
        case .send: send()
        case .wait: break
        }
    }

    // MARK: The report

    func buildReport() -> AnalyticsRules.Report {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let diagnostics = DiagnosticsCenter.shared
        let granted = FeatureHub.shared.granted()
        let home = NSHomeDirectory()
        return AnalyticsRules.report(AnalyticsRules.Inputs(
            appVersion: diagnostics.appVersion, build: diagnostics.appBuild,
            osVersion: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
            model: diagnostics.systemInfo().model, arch: diagnostics.systemInfo().arch,
            language: L10n.isEnglish ? "en" : "vi",
            featuresOn: FeatureHub.shared.enabledSet.map(\.rawValue),
            permissionsGranted: AppPermission.allCases.filter { granted[$0] == true }.map(\.rawValue),
            // "Ghi lỗi kỹ thuật… trên máy này" off ⇒ XFinder collects no diagnostics at all: no error counts AND no crash
            // summaries (crash reports would otherwise still be read from ~/Library/Logs) — the switch's caption says so.
            events: DiagnosticsLog.isEnabled ? DiagnosticsLog.events() : [],
            crashes: DiagnosticsLog.isEnabled
                ? DiagnosticsCenter.storedMetricKitSummaries() + DiagnosticsCenter.recentCrashReports(home: home) : [],
            since: lastSentAt))
    }

    /// Exactly what the next send would carry, for "Xem dữ liệu sẽ gửi".
    func previewText() -> String { AnalyticsRules.previewJSON(buildReport()) }

    // MARK: Notice — once, before anything is ever sent

    private func presentNotice() {
        guard !noticeOpen else { return }
        noticeOpen = true
        defer { noticeOpen = false }
        let alert = NSAlert()
        alert.messageText = L10n.t("XFinder gửi thống kê ẩn danh")
        alert.informativeText = L10n.t("Để sửa lỗi và nâng cấp app cho đúng nhu cầu, mỗi ngày XFinder gửi tối đa một bản thống kê ẩn danh: phiên bản app và macOS, loại máy, ngôn ngữ, tính năng đang bật, quyền đã cấp, số lần gặp từng mã lỗi và tóm tắt crash của chính XFinder. Không có mã định danh, tên tệp, nội dung clipboard, ghi chú, tên cửa sổ hay tài khoản; mỗi lần gửi là một bản rời. Lần gửi đầu sau 24 giờ. Bạn từ chối được bất cứ lúc nào ở Giới thiệu ▸ Hỗ trợ & báo lỗi.")
        alert.addButton(withTitle: L10n.t("Đã hiểu"))
        alert.addButton(withTitle: L10n.t("Từ chối gửi"))
        alert.addButton(withTitle: L10n.t("Xem dữ liệu…"))
        NSApp.activate()
        let answer = alert.runModal()
        // The notice counts as shown whatever was pressed: the grace day starts now.
        let d = UserDefaults.standard
        d.set(Date(), forKey: Key.noticeShownAt)
        d.set(AnalyticsRules.schemaVersion, forKey: Key.noticeSchema)
        switch answer {
        case .alertSecondButtonReturn:
            d.set(true, forKey: "analytics.optOut")
        case .alertThirdButtonReturn:
            AppState.shared.aboutShowsAnalytics = true
            AppState.shared.navigate(to: .about)
        default:
            break
        }
    }

    // MARK: Send

    private func send() {
        guard !sending, let receiver, let url = AnalyticsRules.endpoint(receiver) else { return }
        let report = buildReport()
        // A fresh value per send: nothing links this report to the previous one.
        let clientUser = SHA256.hash(data: Data(UUID().uuidString.utf8)).map { String(format: "%02x", $0) }.joined()
        #if DEBUG
        let testMode = true      // development builds land in TelemetryDeck's test mode, outside production charts
        #else
        let testMode = false
        #endif
        guard let body = AnalyticsRules.telemetryDeckBody(report, receiver: receiver, clientUser: clientUser,
                                                          testMode: testMode) else { return }
        sending = true
        UserDefaults.standard.set(Date(), forKey: Key.lastAttemptAt)
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        Task {
            let status = await Self.post(request)
            self.sending = false
            // A refusal that arrived while the request was in flight still wins for every later send.
            if let status, (200..<300).contains(status) {
                UserDefaults.standard.set(Date(), forKey: Key.lastSentAt)
            } else {
                DiagnosticsLog.record("analytics", "sendFailed", detail: status.map { "HTTP \($0)" } ?? "no response")
            }
        }
    }

    /// An ephemeral session: no cookies, no cache, nothing kept between sends.
    nonisolated private static func post(_ request: URLRequest) async -> Int? {
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        do {
            let (_, response) = try await session.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode
        } catch {
            return nil
        }
    }
}
