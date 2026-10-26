import SwiftUI

/// XF-T32 W2 (contract XF-T32-w23 §C) — one sidebar section per Live Group of the active Space. STUB — `sidebarparts`.
struct SidebarLiveGroupsSection: View {
    let spaces: SpaceController
    let metadata: BrowserMetadata
    let onOpen: (String) -> Void
    let isSelected: (String) -> Bool

    var body: some View { EmptyView() }
}
