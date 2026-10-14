import SwiftUI

/// "Theo dõi hệ thống" (2026-10-14) — one sidebar row for the four pages that answer "how is this Mac doing":
/// Hệ thống, Mạng, Ổ đĩa, Pin, as tabs (the owner pointed at MFinder's System Monitor, which has the same four). Each tab
/// is the existing page, unchanged, with its own header hidden (`pageHeaderHidden`); its samplers still start on appear
/// and stop on disappear, so only the open tab costs anything. The tab lives in `AppState.monitorTab`, so a deep link to
/// `.network` opens this page on Mạng.
struct SystemMonitorPage: View {
    @State private var appState = AppState.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: L10n.t("Theo dõi hệ thống"),
                       subtitle: L10n.t("Máy Mac đang chạy thế nào: bộ xử lý, bộ nhớ, mạng, ổ đĩa và pin."))
            Picker("", selection: Bindable(appState).monitorTab) {
                ForEach(SidebarDestination.monitorTabs, id: \.self) { tab in
                    Text(L10n.t(tab.tabTitleKey)).tag(tab)
                }
            }
            .pickerStyle(.segmented)                 // segmented-ok: four short labels (monitorTabs has 4 cases)
            .labelsHidden()
            .frame(maxWidth: 420)
            .padding(.horizontal, XFinderTokens.Space.page)
            .padding(.top, 14)
            .padding(.bottom, 4)

            Group {
                switch appState.monitorTab {
                case .network: NetworkDetailView()
                case .storage: StorageDetailView()
                case .pin: PinDetailView()
                default: SystemDetailView()
                }
            }
            .environment(\.pageHeaderHidden, true)
            .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
