import SwiftUI

struct RootView: View {
    @State private var appState = AppState.shared
    @State private var clipboardManager = ClipboardManager.shared
    @State private var systemMonitorManager = SystemMonitorManager.shared
    @State private var l10n = L10n.shared
    @ObservedObject private var permissionManager = PermissionManager.shared

    var body: some View {
        NavigationView {
            SidebarView(selection: $appState.selection)
                .environment(clipboardManager)
                // Fixed, not a range: with min/ideal/max the column re-negotiates
                // its width per page and the window visibly jumps when a long
                // row like "Đổi tên hàng loạt" is selected. P3: OneNotch's measured 220.
                .frame(width: XFinderTokens.Settings.sidebarWidth)

            // No notes column here: notes live in the screen-edge panel, and a
            // permanent sidebar repeated it on every settings page.
            VStack(spacing: 0) {
                if !permissionManager.isAccessibilityGranted {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.system(size: 13))
                        Text(L10n.t("XFinder cần quyền Trợ năng để nhận cử chỉ"))
                            .font(.system(size: 12))
                        Spacer()
                        Button(L10n.t("Mở Cài đặt")) {
                            PermissionManager.shared.openAccessibilitySettings()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.orange.opacity(0.12))
                    Divider()
                }

                DetailHostView(selection: appState.selection)
                    .environment(clipboardManager)
                    .environment(systemMonitorManager)
                    // `minWidth: 0` is the load-bearing part: without it a page
                    // whose content has a large ideal width (the batch-rename
                    // preview rows) pushes the whole window wider when selected.
                    .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
                    // P3: the page behind the grouped cards (white in light mode, as measured).
                    .background(XFinderTokens.Settings.contentBackground)
            }
        }
        .navigationViewStyle(.columns)
        .frame(minWidth: 900, minHeight: 600)
        .environment(appState)
        // Đổi ngôn ngữ → đổi id → SwiftUI dựng lại toàn bộ cây (sidebar +
        // detail) để mọi chuỗi `L10n.t(...)` được đánh giá lại.
        .id(l10n.language.rawValue)
    }
}

struct DetailHostView: View {
    let selection: SidebarDestination
    @Environment(ClipboardManager.self) var clipboardManager
    @Environment(SystemMonitorManager.self) var systemMonitorManager

    var body: some View {
        Group {
            switch selection {
            case .settingsClipboard:
                SettingsDetailView(destination: .settingsClipboard)
            case .clipboard:
                ClipboardLibraryView()
            case .features:
                FeaturesHubView()
            case .notes:
                NotesDetailView()
            case .windowPreview:
                WindowPreviewDetailView()
            case .snapZones:
                SnapZonesDetailView()
            case .mouseGestures:
                MouseGesturesDetailView()
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
            case .junkCleanup:
                JunkCleanupDetailView()
            case .uninstaller:
                UninstallDetailView()
            case .appQuit:
                AppQuitDetailView()
            case .actionHistory:
                ActionHistoryDetailView()
            case .dropTray:
                DropTrayDetailView()
            case .notchInterface:
                NotchInterfaceDetailView()
            case .media:
                MediaDetailView()
            case .aiAgents:
                AIAgentsDetailView()
            case .calendar:
                CalendarSettingsDetailView()
            case .liveActivities:
                LiveActivitiesDetailView()
            case .shortcuts:
                ShortcutsDetailView()
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
            case .antiSleep:
                AntiSleepDetailView()
            case .system, .network, .storage, .pin:
                SystemMonitorPage()
                    .environment(systemMonitorManager)
            case .voiceTyping:
                VoiceDetailView()
            case .smartSelect:
                SmartSelectDetailView()
            case .capture:
                CaptureDetailView()
            case .ports:
                PortsDetailView()
            case .alerts:
                AlertsDetailView()
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
