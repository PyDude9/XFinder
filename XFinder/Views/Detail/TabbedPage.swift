import SwiftUI

/// One sidebar row that shows several pages as tabs (`SidebarDestination.tabGroups`). Each tab is the existing page,
/// unchanged, with its own header hidden (`pageHeaderHidden`); a page's samplers still start on appear and stop on
/// disappear, so only the open tab costs anything. The open tab lives in `AppState.openTab`, so a deep link to a tab
/// (`.network`) opens its row on that tab.
///
/// First used for "Theo dõi hệ thống" (Hệ thống / Mạng / Ổ đĩa / Pin, the owner pointed at MFinder's System Monitor),
/// then for every pair of pages that served one job.
struct TabbedPage<Content: View>: View {
    let row: SidebarDestination
    let content: (SidebarDestination) -> Content
    @State private var appState = AppState.shared

    init(row: SidebarDestination, @ViewBuilder content: @escaping (SidebarDestination) -> Content) {
        self.row = row
        self.content = content
    }

    var body: some View {
        let tabs = row.tabGroup ?? [row]
        let shown = appState.tab(of: row)
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: L10n.t(row.titleKey), subtitle: row.tabbedSubtitleKey.map { L10n.t($0) })
            Picker("", selection: Binding(get: { appState.tab(of: row) }, set: { appState.openTab[row] = $0 })) {
                ForEach(tabs, id: \.self) { tab in
                    Text(L10n.t(tab.tabTitleKey)).tag(tab)
                }
            }
            .pickerStyle(.segmented)                 // segmented-ok: a tab group has at most four members (SidebarDestinationTests)
            .labelsHidden()
            .frame(maxWidth: 420)
            .padding(.horizontal, XFinderTokens.Space.page)
            .padding(.top, 14)
            .padding(.bottom, 4)

            content(shown)
                .environment(\.pageHeaderHidden, true)
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, idealHeight: 0, maxHeight: .infinity, alignment: .top)
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, idealHeight: 0, maxHeight: .infinity, alignment: .topLeading)
    }
}
