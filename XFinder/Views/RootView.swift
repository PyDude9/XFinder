import SwiftUI

struct RootView: View {
    @State private var appState = AppState.shared
    @State private var clipboardManager = ClipboardManager.shared
    @State private var systemMonitorManager = SystemMonitorManager.shared

    var body: some View {
        NavigationView {
            SidebarView(selection: $appState.selection)
                .environment(clipboardManager)
                // Fixed, not a range: with min/ideal/max the column re-negotiates
                // its width per page and the window visibly jumps when a long
                // row like "Đổi tên hàng loạt" is selected.
                .frame(width: 240)

            // No notes column here: notes live in the screen-edge panel, and a
            // permanent sidebar repeated it on every settings page.
            DetailHostView(selection: appState.selection)
                .environment(clipboardManager)
                .environment(systemMonitorManager)
                // `minWidth: 0` is the load-bearing part: without it a page
                // whose content has a large ideal width (the batch-rename
                // preview rows) pushes the whole window wider when selected.
                .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationViewStyle(.columns)
        .frame(minWidth: 900, minHeight: 600)
        .environment(appState)
    }
}

struct DetailHostView: View {
    let selection: SidebarDestination
    @Environment(ClipboardManager.self) var clipboardManager
    @Environment(SystemMonitorManager.self) var systemMonitorManager

    var body: some View {
        Group {
            switch selection {
            case .clipboard:
                ClipboardTabView()
                    .environment(clipboardManager)
            case .notes:
                NotesDetailView()
            case .windowPreview:
                WindowPreviewDetailView()
            case .snapZones:
                SnapZonesDetailView()
            case .menuIcons:
                MenuIconsDetailView()
            case .finderActions:
                FinderActionsDetailView()
            case .finderKeyboard:
                FinderKeyboardDetailView()
            case .folderLock:
                FolderLockDetailView()
            case .sync:
                FolderSyncDetailView()
            case .remoteConnect:
                RemoteConnectDetailView()
            case .quickShare:
                QuickShareDetailView()
            case .finderSearch:
                FinderSearchDetailView()
            case .aiSearch:
                AiSearchDetailView()
            case .batchRename:
                BatchRenameDetailView()
            case .actionHistory:
                ActionHistoryDetailView()
            case .dropTray:
                DropTrayDetailView()
            case .quickLookPage:
                QuickLookDetailView()
            case .mediaCompat:
                MediaCompatDetailView()
            case .finderUtils:
                FinderUtilsDetailView()
            case .dashboard:
                DashboardDetailView()
                    .environment(systemMonitorManager)
                    .environment(clipboardManager)
            case .quickControls:
                QuickControlsDetailView()
            case .antiSleep:
                AntiSleepDetailView()
            case .system:
                SystemDetailView()
                    .environment(systemMonitorManager)
            case .network:
                NetworkDetailView()
                    .environment(systemMonitorManager)
            case .storage:
                StorageDetailView()
            case .pin:
                PinDetailView()
                    .environment(systemMonitorManager)
            case .settingsClipboard, .settingsMenubar:
                SettingsDetailView(destination: selection)
            case .compress:
                CompressDetailView()
            case .pdfTools:
                PdfToolsDetailView()
            case .about:
                AboutView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            default:
                PlaceholderDetailView(destination: selection)
            }
        }
    }
}
