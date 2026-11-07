# XFinder — kiểm kê Settings hiện có để đối chiếu MFinder (2026-11-07)

Phạm vi: source trên `main` commit `9788415`. Đây là kiểm kê các trang có cài đặt và toàn bộ khai báo `@AppStorage` trong `XFinder/Views`, kèm hai truy cập `UserDefaults` literal trong view. Không thay đổi hay chuẩn hoá khoá/defaults. `Control trong trang cài đặt` nghĩa là khai báo nằm trong trang UI; `View runtime` chỉ là reader/writer của cùng key, không nhất thiết là một control thứ hai. Các dòng có cùng key được giữ riêng để lộ đúng chỗ cần kiểm tra ownership.

## Nơi cài đặt đang hiển thị

| Vị trí/route | Nội dung | Bằng chứng |
|---|---|---|
| Sidebar `CHUNG` | Tổng quan, Tính năng & Quyền, Phím tắt, Hệ thống, Cảnh báo | `XFinder/Models/SidebarDestination.swift:264–270`; route tại `XFinder/Views/RootView.swift:78–170` |
| Sidebar `NOTCH` | Giao diện notch, Khay thả, Media, Agent AI, Lịch, hoạt động | cùng `SidebarDestination.swift:264–270`; từng pane tại `Views/Detail/*DetailView.swift` |
| Sidebar `CỬA SỔ` | Xem trước cửa sổ, Vùng bắt dính, thoát app, cử chỉ chuột, menu bar | `SidebarDestination.swift:268`; `WindowDetailViews.swift`, `MouseGesturesDetailView.swift`, `MenuIconsDetailView.swift`, `AppQuitDetailView.swift` |
| Sidebar `FINDER & TÌM KIẾM` | File Browser, Finder actions/keyboard/search, batch rename, cleanup, history | `SidebarDestination.swift:269–270`; `RootView.swift:89–127` |
| Sidebar `CÔNG CỤ` | Voice, Smart Select, Capture, Clipboard Library, Clipboard Settings, Notes, archive/PDF/vault | `SidebarDestination.swift:270–271`; `RootView.swift:78–170` |
| Sidebar `KẾT NỐI` / `TIỆN ÍCH` | Sync, remote, share, ports; Finder utilities, Quick Look, uninstall | `SidebarDestination.swift:272–273` |
| File Browser embedded settings | 9 menu categories: Chung, Giao diện, Sidebar, Đám mây, Nâng cao, Bàn phím, Ngăn thông tin, Tìm kiếm, Quyền riêng tư; rendered inside the File Browser page, not a separate settings window | `XFinder/Views/Browser/BrowserSettingsWindow.swift:12–42,56–84`; `FileBrowserDetailView.swift:58` |
| App-level settings window | Diagnostics local log + analytics opt-out | `XFinder/Views/SettingsWindow.swift:9–15` |
| System settings panel | Volume/brightness/theme, Keep Awake and Cleaning Mode; shown as system controls, not the Settings sidebar | `XFinder/Views/Detail/SystemControlsPanel.swift:71–276,310–333` |

Không có một trang Settings tổng duy nhất trong `SidebarDestination.groups`: page cài đặt Clipboard là route riêng (`settingsClipboard`); phần lớn tuỳ chọn sống cạnh tính năng sở hữu chúng. Vì vậy bảng đối chiếu MFinder phải ánh xạ từng setting vào trang owner, không giả định một Settings page chung.

## Tất cả khai báo `@AppStorage` trong Views (234 khai báo, 199 biểu thức khoá riêng biệt)

| Khoá/biểu thức | Giá trị mặc định tại view | Property | Vị trí / dòng | Vai trò |
|---|---|---|---|---|
| `BrowserLearnProgress.key` | `Data()` | `progress` | `XFinder/Views/Browser/BrowserLearnView.swift:5` | View runtime đọc/ghi cùng khoá |
| `fileBrowser.showLearnButton` · khai báo lặp ×2 | `true` | `showLearnButton` | `XFinder/Views/Browser/BrowserRootView.swift:19` | View runtime đọc/ghi cùng khoá |
| `fileBrowser.showSidebar` | `true` | `showSidebar` | `XFinder/Views/Browser/BrowserRootView.swift:20` | View runtime đọc/ghi cùng khoá |
| `fileBrowser.newWindowTarget` | `"home"` | `newWindowTarget` | `XFinder/Views/Browser/BrowserSettingsWindow.swift:90` | Control trong trang cài đặt |
| `fileBrowser.newWindowCustomPath` | `""` | `newWindowCustomPath` | `XFinder/Views/Browser/BrowserSettingsWindow.swift:91` | Control trong trang cài đặt |
| `fileBrowser.reopenWindows` | `true` | `reopenWindows` | `XFinder/Views/Browser/BrowserSettingsWindow.swift:92` | Control trong trang cài đặt |
| `fileBrowser.returnOpens` | `false` | `returnOpens` | `XFinder/Views/Browser/BrowserSettingsWindow.swift:93` | Control trong trang cài đặt |
| `fileBrowser.downloadsHotkey` · khai báo lặp ×2 | `false` | `downloadsHotkey` | `XFinder/Views/Browser/BrowserSettingsWindow.swift:94` | Control trong trang cài đặt |
| `fileBrowser.cutWithCmdX` | `false` | `cutWithCmdX` | `XFinder/Views/Browser/BrowserSettingsWindow.swift:95` | Control trong trang cài đặt |
| `fileBrowser.showLocationBar` · khai báo lặp ×2 | `true` | `showLocationBar` | `XFinder/Views/Browser/BrowserSettingsWindow.swift:185` | Control trong trang cài đặt |
| `fileBrowser.showPathBar` · khai báo lặp ×2 | `true` | `showPathBar` | `XFinder/Views/Browser/BrowserSettingsWindow.swift:186` | Control trong trang cài đặt |
| `fileBrowser.showStatusBar` · khai báo lặp ×2 | `true` | `showStatusBar` | `XFinder/Views/Browser/BrowserSettingsWindow.swift:187` | Control trong trang cài đặt |
| `fileBrowser.paneFocusStyle` · khai báo lặp ×2 | `"dim"` | `paneFocusStyle` | `XFinder/Views/Browser/BrowserSettingsWindow.swift:189` | Control trong trang cài đặt |
| `fileBrowser.showLearnButton` · khai báo lặp ×2 | `true` | `showLearnButton` | `XFinder/Views/Browser/BrowserSettingsWindow.swift:190` | Control trong trang cài đặt |
| `fileBrowser.showPreview` · khai báo lặp ×2 | `false` | `inspectorVisible` | `XFinder/Views/Browser/BrowserSettingsWindow.swift:215` | Control trong trang cài đặt |
| `fileBrowser.previewShowMore` · khai báo lặp ×2 | `false` | `inspectorShowMore` | `XFinder/Views/Browser/BrowserSettingsWindow.swift:216` | Control trong trang cài đặt |
| `fileBrowser.sidebar.favorites` | `true` | `favorites` | `XFinder/Views/Browser/BrowserSettingsWindow.swift:235` | Control trong trang cài đặt |
| `fileBrowser.sidebar.iCloud` | `true` | `iCloud` | `XFinder/Views/Browser/BrowserSettingsWindow.swift:236` | Control trong trang cài đặt |
| `fileBrowser.sidebar.recents` | `true` | `recents` | `XFinder/Views/Browser/BrowserSettingsWindow.swift:237` | Control trong trang cài đặt |
| `fileBrowser.sidebar.airDrop` | `true` | `airDrop` | `XFinder/Views/Browser/BrowserSettingsWindow.swift:238` | Control trong trang cài đặt |
| `fileBrowser.sidebar.hardDisks` | `true` | `hardDisks` | `XFinder/Views/Browser/BrowserSettingsWindow.swift:239` | Control trong trang cài đặt |
| `fileBrowser.sidebar.externalDisks` | `true` | `externalDisks` | `XFinder/Views/Browser/BrowserSettingsWindow.swift:240` | Control trong trang cài đặt |
| `fileBrowser.sidebar.cloudStorage` · khai báo lặp ×2 | `true` | `cloudStorage` | `XFinder/Views/Browser/BrowserSettingsWindow.swift:241` | Control trong trang cài đặt |
| `fileBrowser.sidebar.connectedServers` | `true` | `connectedServers` | `XFinder/Views/Browser/BrowserSettingsWindow.swift:242` | Control trong trang cài đặt |
| `fileBrowser.sidebar.bonjour` | `false` | `bonjour` | `XFinder/Views/Browser/BrowserSettingsWindow.swift:243` | Control trong trang cài đặt |
| `fileBrowser.sidebar.recentTags` | `true` | `recentTags` | `XFinder/Views/Browser/BrowserSettingsWindow.swift:244` | Control trong trang cài đặt |
| `fileBrowser.sidebar.groupLocationsByType` | `false` | `groupByType` | `XFinder/Views/Browser/BrowserSettingsWindow.swift:245` | Control trong trang cài đặt |
| `fileBrowser.sidebar.highlightCurrent` | `false` | `highlightCurrent` | `XFinder/Views/Browser/BrowserSettingsWindow.swift:246` | Control trong trang cài đặt |
| `fileBrowser.sidebar.cloudStorage` · khai báo lặp ×2 | `true` | `showInSidebar` | `XFinder/Views/Browser/BrowserSettingsWindow.swift:336` | Control trong trang cài đặt |
| `fileBrowser.showAllExtensions` | `false` | `showAllExtensions` | `XFinder/Views/Browser/BrowserSettingsWindow.swift:502` | Control trong trang cài đặt |
| `fileBrowser.showHidden` | `false` | `showHidden` | `XFinder/Views/Browser/BrowserSettingsWindow.swift:503` | Control trong trang cài đặt |
| `fileBrowser.foldersFirst` | `false` | `foldersFirst` | `XFinder/Views/Browser/BrowserSettingsWindow.swift:504` | Control trong trang cài đặt |
| `fileBrowser.search.defaultScope` | `"mac"` | `searchScope` | `XFinder/Views/Browser/BrowserSettingsWindow.swift:505` | Control trong trang cài đặt |
| `fileBrowser.defaultView` | `"list"` | `defaultView` | `XFinder/Views/Browser/BrowserSettingsWindow.swift:506` | Control trong trang cài đặt |
| `fileBrowser.tabSwitchesPanes` | `false` | `tabSwitchesPanes` | `XFinder/Views/Browser/BrowserSettingsWindow.swift:562` | Control trong trang cài đặt |
| `fileBrowser.mouseBackForward` | `"on"` | `mouseBackForward` | `XFinder/Views/Browser/BrowserSettingsWindow.swift:563` | Control trong trang cài đặt |
| `BrowserPaletteRules.usageKey` | `Data()` | `usage` | `XFinder/Views/Browser/CommandPaletteView.swift:16` | View runtime đọc/ghi cùng khoá |
| `fileBrowser.showLocationBar` · khai báo lặp ×2 | `true` | `showLocationBar` | `XFinder/Views/Browser/PaneView.swift:19` | View runtime đọc/ghi cùng khoá |
| `fileBrowser.showPathBar` · khai báo lặp ×2 | `true` | `showPathBar` | `XFinder/Views/Browser/PaneView.swift:20` | View runtime đọc/ghi cùng khoá |
| `fileBrowser.showStatusBar` · khai báo lặp ×2 | `true` | `showStatusBar` | `XFinder/Views/Browser/PaneView.swift:21` | View runtime đọc/ghi cùng khoá |
| `fileBrowser.showPreview` · khai báo lặp ×2 | `false` | `showPreview` | `XFinder/Views/Browser/PaneView.swift:23` | View runtime đọc/ghi cùng khoá |
| `fileBrowser.paneFocusStyle` · khai báo lặp ×2 | `"dim"` | `paneFocusStyle` | `XFinder/Views/Browser/PaneView.swift:25` | View runtime đọc/ghi cùng khoá |
| `fileBrowser.previewShowMore` · khai báo lặp ×2 | `false` | `showMore` | `XFinder/Views/Browser/PreviewPaneView.swift:26` | View runtime đọc/ghi cùng khoá |
| `capture.annotate.color` · khai báo lặp ×2 | `"red"` | `colorRaw` | `XFinder/Views/Capture/AnnotateWindow.swift:227` | View runtime đọc/ghi cùng khoá |
| `capture.annotate.width` · khai báo lặp ×2 | `"medium"` | `widthRaw` | `XFinder/Views/Capture/AnnotateWindow.swift:228` | View runtime đọc/ghi cùng khoá |
| `dropTray.notchEnabled` · khai báo lặp ×6 | `true` | `notchEnabled` | `XFinder/Views/Detail/AIAgentsDetailView.swift:9` | Control trong trang cài đặt |
| `agents.enabled` | `false` | `agentsEnabled` | `XFinder/Views/Detail/AIAgentsDetailView.swift:10` | Control trong trang cài đặt |
| `agents.opencode` | `false` | `openCodeEnabled` | `XFinder/Views/Detail/AIAgentsDetailView.swift:19` | Control trong trang cài đặt |
| `agents.notify.permission` | `true` | `notifyPermission` | `XFinder/Views/Detail/AIAgentsDetailView.swift:23` | Control trong trang cài đặt |
| `agents.notify.finished` | `true` | `notifyFinished` | `XFinder/Views/Detail/AIAgentsDetailView.swift:24` | Control trong trang cài đặt |
| `agents.notify.sound` | `false` | `notifySound` | `XFinder/Views/Detail/AIAgentsDetailView.swift:25` | Control trong trang cài đặt |
| `agents.notify.quotaBlocked` | `true` | `notifyLimit` | `XFinder/Views/Detail/AIAgentsDetailView.swift:26` | Control trong trang cài đặt |
| `agents.notify.quietWhenFront` | `true` | `notifyQuietWhenFront` | `XFinder/Views/Detail/AIAgentsDetailView.swift:27` | Control trong trang cài đặt |
| `agents.sortMode` | `"priority"` | `sortMode` | `XFinder/Views/Detail/AIAgentsDetailView.swift:28` | Control trong trang cài đặt |
| `agents.keepFinished` | `true` | `keepFinished` | `XFinder/Views/Detail/AIAgentsDetailView.swift:29` | Control trong trang cài đặt |
| `notch.agentEdgeHover` | `true` | `agentEdgeHover` | `XFinder/Views/Detail/AIAgentsDetailView.swift:30` | Control trong trang cài đặt |
| `alerts.enabled` | `false` | `enabled` | `XFinder/Views/Detail/AlertsDetailView.swift:9` | Control trong trang cài đặt |
| `quitProtection.enabled` · khai báo lặp ×2 | `false` | `holdEnabled` | `XFinder/Views/Detail/AppQuitDetailView.swift:7` | Control trong trang cài đặt |
| `quitOnClose.enabled` | `false` | `closeEnabled` | `XFinder/Views/Detail/AppQuitDetailView.swift:8` | Control trong trang cài đặt |
| `quitOnClose.apps` | `""` | `appsRaw` | `XFinder/Views/Detail/AppQuitDetailView.swift:9` | Control trong trang cài đặt |
| `dropTray.notchEnabled` · khai báo lặp ×6 | `true` | `notchEnabled` | `XFinder/Views/Detail/CalendarSettingsDetailView.swift:9` | Control trong trang cài đặt |
| `notch.calendar` | `false` | `calendarEnabled` | `XFinder/Views/Detail/CalendarSettingsDetailView.swift:10` | Control trong trang cài đặt |
| `notch.calendar.hideAllDay` | `false` | `calendarHideAllDay` | `XFinder/Views/Detail/CalendarSettingsDetailView.swift:11` | Control trong trang cài đặt |
| `notch.calendar.alerts` | `true` | `calendarAlerts` | `XFinder/Views/Detail/CalendarSettingsDetailView.swift:13` | Control trong trang cài đặt |
| `notch.calendar.alertLead` | `5` | `calendarAlertLead` | `XFinder/Views/Detail/CalendarSettingsDetailView.swift:14` | Control trong trang cài đặt |
| `notch.calendar.alertSound` | `true` | `calendarAlertSound` | `XFinder/Views/Detail/CalendarSettingsDetailView.swift:15` | Control trong trang cài đặt |
| `capture.enabled` · khai báo lặp ×2 | `true` | `enabled` | `XFinder/Views/Detail/CaptureDetailView.swift:12` | Control trong trang cài đặt |
| `capture.after` | `"copyAndCard"` | `afterRaw` | `XFinder/Views/Detail/CaptureDetailView.swift:13` | Control trong trang cài đặt |
| `capture.cardSeconds` | `10` | `cardSeconds` | `XFinder/Views/Detail/CaptureDetailView.swift:14` | Control trong trang cài đặt |
| `capture.cardEdge` | `"left"` | `cardEdgeRaw` | `XFinder/Views/Detail/CaptureDetailView.swift:15` | Control trong trang cài đặt |
| `capture.pauseOnHover` | `true` | `pauseOnHover` | `XFinder/Views/Detail/CaptureDetailView.swift:16` | Control trong trang cài đặt |
| `capture.swipeDismiss` | `true` | `swipeDismiss` | `XFinder/Views/Detail/CaptureDetailView.swift:17` | Control trong trang cài đặt |
| `capture.sound` | `true` | `sound` | `XFinder/Views/Detail/CaptureDetailView.swift:18` | Control trong trang cài đặt |
| `capture.countdown` | `0` | `countdown` | `XFinder/Views/Detail/CaptureDetailView.swift:19` | Control trong trang cài đặt |
| `capture.windowShadow` | `true` | `windowShadow` | `XFinder/Views/Detail/CaptureDetailView.swift:20` | Control trong trang cài đặt |
| `capture.format` | `"png"` | `formatRaw` | `XFinder/Views/Detail/CaptureDetailView.swift:21` | Control trong trang cài đặt |
| `capture.keepHistory` | `true` | `keepHistory` | `XFinder/Views/Detail/CaptureDetailView.swift:22` | Control trong trang cài đặt |
| `capture.deleteAfterDays` | `0` | `deleteAfterDays` | `XFinder/Views/Detail/CaptureDetailView.swift:23` | Control trong trang cài đặt |
| `capture.annotate.color` · khai báo lặp ×2 | `"red"` | `annotateColorRaw` | `XFinder/Views/Detail/CaptureDetailView.swift:24` | Control trong trang cài đặt |
| `capture.annotate.width` · khai báo lặp ×2 | `"medium"` | `annotateWidthRaw` | `XFinder/Views/Detail/CaptureDetailView.swift:25` | Control trong trang cài đặt |
| `general.launchAtLogin` | `false` | `launchAtLogin` | `XFinder/Views/Detail/DashboardDetailView.swift:14` | Control trong trang cài đặt |
| `ShowDockIcon` | `true` | `showDockIcon` | `XFinder/Views/Detail/DashboardDetailView.swift:15` | Control trong trang cài đặt |
| `notes.edgeEnabled` · khai báo lặp ×2 | `false` | `edgeNotesEnabled` | `XFinder/Views/Detail/DashboardDetailView.swift:16` | Control trong trang cài đặt |
| `windowPreview.hoverEnabled` · khai báo lặp ×2 | `true` | `hoverEnabled` | `XFinder/Views/Detail/DashboardDetailView.swift:17` | Control trong trang cài đặt |
| `menubar.icon` | `"magnifier"` | `menubarIcon` | `XFinder/Views/Detail/DashboardDetailView.swift:19` | Control trong trang cài đặt |
| `dropTray.notchEnabled` · khai báo lặp ×6 | `true` | `notchEnabled` | `XFinder/Views/Detail/DropTrayDetailView.swift:18` | Control trong trang cài đặt |
| `dropTray.notchDropEnabled` | `true` | `notchDropEnabled` | `XFinder/Views/Detail/DropTrayDetailView.swift:21` | Control trong trang cài đặt |
| `dropTray.shakeEnabled` | `true` | `shakeEnabled` | `XFinder/Views/Detail/DropTrayDetailView.swift:22` | Control trong trang cài đặt |
| `dropTray.shakeSensitivity` | `"medium"` | `shakeSensitivity` | `XFinder/Views/Detail/DropTrayDetailView.swift:23` | Control trong trang cài đặt |
| `fileBrowser.enabled` · khai báo lặp ×2 | `true` | `enabled` | `XFinder/Views/Detail/FileBrowserDetailView.swift:6` | Control trong trang cài đặt |
| `fileBrowser.globalHotkey` · khai báo lặp ×2 | `false` | `globalHotkey` | `XFinder/Views/Detail/FileBrowserDetailView.swift:7` | Control trong trang cài đặt |
| `fileBrowser.launcherShortcut` · khai báo lặp ×2 | `"controlOptionCommandF"` | `launcherShortcut` | `XFinder/Views/Detail/FileBrowserDetailView.swift:8` | Control trong trang cài đặt |
| `finderKeyboard.cutPaste` · khai báo lặp ×2 | `false` | `cutPaste` | `XFinder/Views/Detail/FinderKeyboardDetailView.swift:5` | Control trong trang cài đặt |
| `finderKeyboard.deleteToTrash` · khai báo lặp ×2 | `false` | `deleteToTrash` | `XFinder/Views/Detail/FinderKeyboardDetailView.swift:6` | Control trong trang cài đặt |
| `finderKeyboard.returnOpens` · khai báo lặp ×2 | `false` | `returnOpens` | `XFinder/Views/Detail/FinderKeyboardDetailView.swift:7` | Control trong trang cài đặt |
| `finder.showExtensions` | `false` | `showExtensions` | `XFinder/Views/Detail/FinderUtilsDetailView.swift:13` | Control trong trang cài đặt |
| `finder.showHidden` | `false` | `showHidden` | `XFinder/Views/Detail/FinderUtilsDetailView.swift:14` | Control trong trang cài đặt |
| `finder.showFullPath` | `false` | `showFullPath` | `XFinder/Views/Detail/FinderUtilsDetailView.swift:15` | Control trong trang cài đặt |
| `sync.autoEnabled` | `false` | `autoEnabled` | `XFinder/Views/Detail/FolderSyncDetailView.swift:8` | Control trong trang cài đặt |
| `dropTray.notchEnabled` · khai báo lặp ×6 | `true` | `notchEnabled` | `XFinder/Views/Detail/LiveActivitiesDetailView.swift:8` | Control trong trang cài đặt |
| `notch.activities` | `true` | `activities` | `XFinder/Views/Detail/LiveActivitiesDetailView.swift:9` | Control trong trang cài đặt |
| `notch.activity.power` | `true` | `actPower` | `XFinder/Views/Detail/LiveActivitiesDetailView.swift:10` | Control trong trang cài đặt |
| `notch.activity.network` | `true` | `actNetwork` | `XFinder/Views/Detail/LiveActivitiesDetailView.swift:11` | Control trong trang cài đặt |
| `notch.activity.capsLock` | `true` | `actCapsLock` | `XFinder/Views/Detail/LiveActivitiesDetailView.swift:12` | Control trong trang cài đặt |
| `notch.activity.bluetooth` | `true` | `actBluetooth` | `XFinder/Views/Detail/LiveActivitiesDetailView.swift:13` | Control trong trang cài đặt |
| `notch.activity.alerts` | `true` | `actAlerts` | `XFinder/Views/Detail/LiveActivitiesDetailView.swift:14` | Control trong trang cài đặt |
| `notch.activity.volume` | `true` | `actVolume` | `XFinder/Views/Detail/LiveActivitiesDetailView.swift:15` | Control trong trang cài đặt |
| `notch.activity.brightness` | `true` | `actBrightness` | `XFinder/Views/Detail/LiveActivitiesDetailView.swift:16` | Control trong trang cài đặt |
| `notch.activity.hideSystemHUD` | `true` | `hideSystemHUD` | `XFinder/Views/Detail/LiveActivitiesDetailView.swift:17` | Control trong trang cài đặt |
| `dropTray.notchEnabled` · khai báo lặp ×6 | `true` | `notchEnabled` | `XFinder/Views/Detail/MediaDetailView.swift:9` | Control trong trang cài đặt |
| `notch.nowPlaying` | `false` | `nowPlaying` | `XFinder/Views/Detail/MediaDetailView.swift:10` | Control trong trang cài đặt |
| `notch.nowPlaying.waveform` | `false` | `waveform` | `XFinder/Views/Detail/MediaDetailView.swift:11` | Control trong trang cài đặt |
| `menubar.hiderEnabled` | `true` | `enabled` | `XFinder/Views/Detail/MenuIconsDetailView.swift:7` | Control trong trang cài đặt |
| `menubar.defaultCollapsed` | `true` | `defaultCollapsed` | `XFinder/Views/Detail/MenuIconsDetailView.swift:8` | Control trong trang cài đặt |
| `menubar.autoHideEnabled` | `false` | `autoHideEnabled` | `XFinder/Views/Detail/MenuIconsDetailView.swift:9` | Control trong trang cài đặt |
| `menubar.autoHideSeconds` | `5.0` | `autoHideSeconds` | `XFinder/Views/Detail/MenuIconsDetailView.swift:10` | Control trong trang cài đặt |
| `dropTray.notchEnabled` · khai báo lặp ×6 | `true` | `notchEnabled` | `XFinder/Views/Detail/NotchInterfaceDetailView.swift:9` | Control trong trang cài đặt |
| `dropTray.hoverEnabled` | `true` | `hoverEnabled` | `XFinder/Views/Detail/NotchInterfaceDetailView.swift:13` | Control trong trang cài đặt |
| `notch.hoverOpens` | `"peek"` | `hoverOpens` | `XFinder/Views/Detail/NotchInterfaceDetailView.swift:14` | Control trong trang cài đặt |
| `notch.hoverSpeed` | `"medium"` | `hoverSpeed` | `XFinder/Views/Detail/NotchInterfaceDetailView.swift:15` | Control trong trang cài đặt |
| `notch.clickOpens` | `"files"` | `clickOpens` | `XFinder/Views/Detail/NotchInterfaceDetailView.swift:16` | Control trong trang cài đặt |
| `notch.pillOnPlainScreens` | `true` | `pillOnPlainScreens` | `XFinder/Views/Detail/NotchInterfaceDetailView.swift:19` | Control trong trang cài đặt |
| `notch.hideFromCapture` | `false` | `hideFromCapture` | `XFinder/Views/Detail/NotchInterfaceDetailView.swift:20` | Control trong trang cài đặt |
| `notch.fullscreenVisibility` | `"show"` | `fullscreenVisibility` | `XFinder/Views/Detail/NotchInterfaceDetailView.swift:21` | Control trong trang cài đặt |
| `notch.pages` | `"files,clipboard,nowPlaying,agents,calendar,timer,aiUsage"` | `pagesRaw` | `XFinder/Views/Detail/NotchInterfaceDetailView.swift:24` | Control trong trang cài đặt |
| `notch.accent` | `"system"` | `accent` | `XFinder/Views/Detail/NotchInterfaceDetailView.swift:26` | Control trong trang cài đặt |
| `notes.edgeEnabled` · khai báo lặp ×2 | `false` | `edgeEnabled` | `XFinder/Views/Detail/NotesDetailView.swift:11` | Control trong trang cài đặt |
| `notes.edgeSide` | `"Right"` | `edgeSide` | `XFinder/Views/Detail/NotesDetailView.swift:200` | Control trong trang cài đặt |
| `notes.edgeHotspot` | `12.0` | `edgeHotspot` | `XFinder/Views/Detail/NotesDetailView.swift:201` | Control trong trang cài đặt |
| `notes.fullscreen` | `false` | `showFullscreen` | `XFinder/Views/Detail/NotesDetailView.swift:202` | Control trong trang cài đặt |
| `notes.hideOnLeave` | `true` | `hideOnLeave` | `XFinder/Views/Detail/NotesDetailView.swift:203` | Control trong trang cài đặt |
| `notes.globalHotkey` | `false` | `globalHotkey` | `XFinder/Views/Detail/NotesDetailView.swift:205` | Control trong trang cài đặt |
| `notes.font` | `"system"` | `noteFont` | `XFinder/Views/Detail/NotesDetailView.swift:264` | Control trong trang cài đặt |
| `notes.autoBackup` | `true` | `autoBackup` | `XFinder/Views/Detail/NotesDetailView.swift:328` | Control trong trang cài đặt |
| `battery.showDisconnected` | `false` | `showDisconnected` | `XFinder/Views/Detail/PinDetailView.swift:7` | Control trong trang cài đặt |
| `pro.simulateTier` | `""` | `simulateTier` | `XFinder/Views/Detail/ProDetailView.swift:10` | Control trong trang cài đặt |
| `quickShare.expiryHours` | `24.0` | `expiryHours` | `XFinder/Views/Detail/QuickShareDetailView.swift:7` | Control trong trang cài đặt |
| `quickShare.enabled` | `true` | `enabled` | `XFinder/Views/Detail/QuickShareDetailView.swift:9` | Control trong trang cài đặt |
| `remoteConnect.enabled` · khai báo lặp ×2 | `true` | `enabled` | `XFinder/Views/Detail/RemoteConnectDetailView.swift:10` | Control trong trang cài đặt |
| `remoteConnect.enabled` · khai báo lặp ×2 | `true` | `enabled` | `XFinder/Views/Detail/RemoteConnectDetailView.swift:158` | Control trong trang cài đặt |
| `quickSearch.enabled` · khai báo lặp ×2 | `true` | `quickSearchEnabled` | `XFinder/Views/Detail/SearchDetailViews.swift:49` | Control trong trang cài đặt |
| `clipboard.captureImages` | `true` | `captureImages` | `XFinder/Views/Detail/SettingsDetailView.swift:40` | Control trong trang cài đặt |
| `clipboard.captureLinks` | `true` | `captureLinks` | `XFinder/Views/Detail/SettingsDetailView.swift:41` | Control trong trang cài đặt |
| `clipboard.cleanURLs` | `false` | `cleanURLs` | `XFinder/Views/Detail/SettingsDetailView.swift:42` | Control trong trang cài đặt |
| `clipboard.linkPreviews` | `false` | `linkPreviews` | `XFinder/Views/Detail/SettingsDetailView.swift:43` | Control trong trang cài đặt |
| `clipboard.autoClearSeconds` | `0` | `autoClearSeconds` | `XFinder/Views/Detail/SettingsDetailView.swift:44` | Control trong trang cài đặt |
| `clipboard.enableOCR` | `true` | `enableOCR` | `XFinder/Views/Detail/SettingsDetailView.swift:45` | Control trong trang cài đặt |
| `clipboard.maxHistory` | `1000` | `maxHistory` | `XFinder/Views/Detail/SettingsDetailView.swift:46` | Control trong trang cài đặt |
| `clipboard.autoDeleteDays` | `30` | `autoDeleteDays` | `XFinder/Views/Detail/SettingsDetailView.swift:47` | Control trong trang cài đặt |
| `clipboard.sounds` | `true` | `sounds` | `XFinder/Views/Detail/SettingsDetailView.swift:48` | Control trong trang cài đặt |
| `clipboard.copySound` | `"Pop"` | `copySound` | `XFinder/Views/Detail/SettingsDetailView.swift:50` | Control trong trang cài đặt |
| `clipboard.cardHaptic` | `true` | `cardHaptic` | `XFinder/Views/Detail/SettingsDetailView.swift:52` | Control trong trang cài đặt |
| `clipboard.paused` | `false` | `paused` | `XFinder/Views/Detail/SettingsDetailView.swift:54` | Control trong trang cài đặt |
| `clipboard.shelfHotkey` · khai báo lặp ×2 | `false` | `shelfHotkey` | `XFinder/Views/Detail/SettingsDetailView.swift:56` | Control trong trang cài đặt |
| `clipboard.mcpEnabled` | `false` | `mcpEnabled` | `XFinder/Views/Detail/SettingsDetailView.swift:58` | Control trong trang cài đặt |
| `privacy.excludePasswordManagers` | `true` | `excludePW` | `XFinder/Views/Detail/SettingsDetailView.swift:65` | Control trong trang cài đặt |
| `sync.icloudClipboard` | `false` | `icloudSync` | `XFinder/Views/Detail/SettingsDetailView.swift:66` | Control trong trang cài đặt |
| `clipboard.globalHotkey` · khai báo lặp ×2 | `true` | `globalHotkey` | `XFinder/Views/Detail/SettingsDetailView.swift:68` | Control trong trang cài đặt |
| `clipboard.hotkeySurface` | `"notch"` | `hotkeySurface` | `XFinder/Views/Detail/SettingsDetailView.swift:71` | Control trong trang cài đặt |
| `clipboard.autoPasteAfterSelection` | `true` | `autoPaste` | `XFinder/Views/Detail/SettingsDetailView.swift:72` | Control trong trang cài đặt |
| `clipboard.excludeCreditCards` | `true` | `excludeCreditCards` | `XFinder/Views/Detail/SettingsDetailView.swift:73` | Control trong trang cài đặt |
| `clipboard.customExcludedApps` | `""` | `customExcludedApps` | `XFinder/Views/Detail/SettingsDetailView.swift:74` | Control trong trang cài đặt |
| `clipboard.touchIDLock` | `false` | `touchIDLock` | `XFinder/Views/Detail/SettingsDetailView.swift:76` | Control trong trang cài đặt |
| `clipboard.intelligentSuggestions` | `true` | `intelligentSuggestions` | `XFinder/Views/Detail/SettingsDetailView.swift:77` | Control trong trang cài đặt |
| `windowPreview.switcherHotkey` · khai báo lặp ×2 | `"commandTab"` | `switcherHotkey` | `XFinder/Views/Detail/ShortcutsDetailView.swift:12` | Control trong trang cài đặt |
| `capture.enabled` · khai báo lặp ×2 | `true` | `captureEnabled` | `XFinder/Views/Detail/ShortcutsDetailView.swift:13` | Control trong trang cài đặt |
| `quickSearch.enabled` · khai báo lặp ×2 | `true` | `quickSearchEnabled` | `XFinder/Views/Detail/ShortcutsDetailView.swift:14` | Control trong trang cài đặt |
| `fileBrowser.enabled` · khai báo lặp ×2 | `true` | `browserEnabled` | `XFinder/Views/Detail/ShortcutsDetailView.swift:18` | Control trong trang cài đặt |
| `fileBrowser.launcherShortcut` · khai báo lặp ×2 | `"controlOptionCommandF"` | `browserLauncherShortcut` | `XFinder/Views/Detail/ShortcutsDetailView.swift:19` | Control trong trang cài đặt |
| `fileBrowser.globalHotkey` · khai báo lặp ×2 | `false` | `browserHotkey` | `XFinder/Views/Detail/ShortcutsDetailView.swift:20` | Control trong trang cài đặt |
| `fileBrowser.downloadsHotkey` · khai báo lặp ×2 | `false` | `downloadsHotkey` | `XFinder/Views/Detail/ShortcutsDetailView.swift:21` | Control trong trang cài đặt |
| `clipboard.globalHotkey` · khai báo lặp ×2 | `true` | `clipboardGlobalHotkey` | `XFinder/Views/Detail/ShortcutsDetailView.swift:22` | Control trong trang cài đặt |
| `clipboard.shelfHotkey` · khai báo lặp ×2 | `false` | `clipboardShelfHotkey` | `XFinder/Views/Detail/ShortcutsDetailView.swift:23` | Control trong trang cài đặt |
| `translate.hotkeyEnabled` · khai báo lặp ×2 | `false` | `translateEnabled` | `XFinder/Views/Detail/ShortcutsDetailView.swift:24` | Control trong trang cài đặt |
| `snapzones.enabled` · khai báo lặp ×2 | `true` | `snapEnabled` | `XFinder/Views/Detail/ShortcutsDetailView.swift:25` | Control trong trang cài đặt |
| `snapzones.hotkeysEnabled` · khai báo lặp ×2 | `true` | `snapHotkeysEnabled` | `XFinder/Views/Detail/ShortcutsDetailView.swift:26` | Control trong trang cài đặt |
| `quitProtection.enabled` · khai báo lặp ×2 | `false` | `quitHoldEnabled` | `XFinder/Views/Detail/ShortcutsDetailView.swift:27` | Control trong trang cài đặt |
| `windowPreview.commandTabEnabled` · khai báo lặp ×2 | `false` | `commandTabEnabled` | `XFinder/Views/Detail/ShortcutsDetailView.swift:28` | Control trong trang cài đặt |
| `finderKeyboard.cutPaste` · khai báo lặp ×2 | `false` | `finderCutPaste` | `XFinder/Views/Detail/ShortcutsDetailView.swift:29` | Control trong trang cài đặt |
| `finderKeyboard.deleteToTrash` · khai báo lặp ×2 | `false` | `finderDeleteToTrash` | `XFinder/Views/Detail/ShortcutsDetailView.swift:30` | Control trong trang cài đặt |
| `finderKeyboard.returnOpens` · khai báo lặp ×2 | `false` | `finderReturnOpens` | `XFinder/Views/Detail/ShortcutsDetailView.swift:31` | Control trong trang cài đặt |
| `smartSelect.enabled` | `false` | `enabled` | `XFinder/Views/Detail/SmartSelectDetailView.swift:7` | Control trong trang cài đặt |
| `smartSelect.minLength` | `2` | `minLength` | `XFinder/Views/Detail/SmartSelectDetailView.swift:8` | Control trong trang cài đặt |
| `smartSelect.excludedApps` | `""` | `excludedRaw` | `XFinder/Views/Detail/SmartSelectDetailView.swift:9` | Control trong trang cài đặt |
| `translate.hotkeyEnabled` · khai báo lặp ×2 | `false` | `translateEnabled` | `XFinder/Views/Detail/SmartSelectDetailView.swift:11` | Control trong trang cài đặt |
| `smartSelect.currency` | `false` | `currencyEnabled` | `XFinder/Views/Detail/SmartSelectDetailView.swift:14` | Control trong trang cài đặt |
| `smoothScroll.enabled` | `false` | `enabled` | `XFinder/Views/Detail/SmoothScrollSection.swift:7` | Control trong trang cài đặt |
| `smoothScroll.speed` | `100` | `speed` | `XFinder/Views/Detail/SmoothScrollSection.swift:8` | Control trong trang cài đặt |
| `smoothScroll.smoothness` | `220` | `smoothness` | `XFinder/Views/Detail/SmoothScrollSection.swift:9` | Control trong trang cài đặt |
| `smoothScroll.reverse` | `false` | `reverse` | `XFinder/Views/Detail/SmoothScrollSection.swift:10` | Control trong trang cài đặt |
| `caffeine.keepDisplayOn` | `true` | `keepDisplayOn` | `XFinder/Views/Detail/SystemControlsPanel.swift:36` | Control trong trang cài đặt |
| `cleaning.minutes` | `2` | `cleaningMinutes` | `XFinder/Views/Detail/SystemControlsPanel.swift:37` | Control trong trang cài đặt |
| `menubar.updateInterval` | `2` | `updateInterval` | `XFinder/Views/Detail/SystemDetailView.swift:12` | Control trong trang cài đặt |
| `VoiceSettingsKey.enabled` | `false` | `voiceEnabled` | `XFinder/Views/Detail/VoiceDetailView.swift:23` | Control trong trang cài đặt |
| `VoiceSettingsKey.language` | `"vi-VN"` | `voiceLanguage` | `XFinder/Views/Detail/VoiceDetailView.swift:24` | Control trong trang cài đặt |
| `VoiceSettingsKey.triggerKey` | `VoiceTriggerKey.rightOption.rawValue` | `triggerKeyRaw` | `XFinder/Views/Detail/VoiceDetailView.swift:25` | Control trong trang cài đặt |
| `VoiceSettingsKey.activationMode` | `VoiceActivationMode.hold.rawValue` | `activationModeRaw` | `XFinder/Views/Detail/VoiceDetailView.swift:26` | Control trong trang cài đặt |
| `VoiceSettingsKey.dictationMode` | `DictationMode.cleanUp.rawValue` | `modeRaw` | `XFinder/Views/Detail/VoiceDetailView.swift:29` | Control trong trang cài đặt |
| `VoiceSettingsKey.customInstruction` | `""` | `customInstruction` | `XFinder/Views/Detail/VoiceDetailView.swift:30` | Control trong trang cài đặt |
| `VoiceSettingsKey.stripFillers` | `true` | `stripFillers` | `XFinder/Views/Detail/VoiceDetailView.swift:31` | Control trong trang cài đặt |
| `VoiceSettingsKey.autoPunctuation` | `true` | `autoPunctuation` | `XFinder/Views/Detail/VoiceDetailView.swift:32` | Control trong trang cài đặt |
| `VoiceSettingsKey.refinerTier` | `VoiceRefinerTier.appleOnDevice.rawValue` | `tierRaw` | `XFinder/Views/Detail/VoiceDetailView.swift:35` | Control trong trang cài đặt |
| `VoiceSettingsKey.apiProvider` | `APIProviderKind.openai.rawValue` | `providerRaw` | `XFinder/Views/Detail/VoiceDetailView.swift:36` | Control trong trang cài đặt |
| `VoiceSettingsKey.apiBaseURL` | `""` | `apiBaseURL` | `XFinder/Views/Detail/VoiceDetailView.swift:37` | Control trong trang cài đặt |
| `VoiceSettingsKey.ollamaBaseURL` | `"http:` | `ollamaBaseURL` | `XFinder/Views/Detail/VoiceDetailView.swift:38` | Control trong trang cài đặt |
| `VoiceSettingsKey.ollamaModel` | `""` | `ollamaModel` | `XFinder/Views/Detail/VoiceDetailView.swift:39` | Control trong trang cài đặt |
| `VoiceSettingsKey.screenContext` | `false` | `screenContext` | `XFinder/Views/Detail/VoiceDetailView.swift:42` | Control trong trang cài đặt |
| `VoiceSettingsKey.selectionContext` | `false` | `selectionContext` | `XFinder/Views/Detail/VoiceDetailView.swift:43` | Control trong trang cài đặt |
| `VoiceSettingsKey.diffReview` | `false` | `diffReview` | `XFinder/Views/Detail/VoiceDetailView.swift:46` | Control trong trang cài đặt |
| `VoiceSettingsKey.restoreClipboard` | `true` | `restoreClipboard` | `XFinder/Views/Detail/VoiceDetailView.swift:47` | Control trong trang cài đặt |
| `VoiceSettingsKey.hudAnchor` | `VoiceHUDAnchor.caret.rawValue` | `hudAnchorRaw` | `XFinder/Views/Detail/VoiceDetailView.swift:50` | Control trong trang cài đặt |
| `VoiceSettingsKey.showWaveform` | `true` | `showWaveform` | `XFinder/Views/Detail/VoiceDetailView.swift:51` | Control trong trang cài đặt |
| `VoiceSettingsKey.audioCues` | `false` | `audioCues` | `XFinder/Views/Detail/VoiceDetailView.swift:52` | Control trong trang cài đặt |
| `windowPreview.hoverEnabled` · khai báo lặp ×2 | `true` | `hoverEnabled` | `XFinder/Views/Detail/WindowDetailViews.swift:9` | Control trong trang cài đặt |
| `windowPreview.hoverDelayMs` | `80` | `hoverDelayMs` | `XFinder/Views/Detail/WindowDetailViews.swift:10` | Control trong trang cài đặt |
| `windowPreview.commandTabEnabled` · khai báo lặp ×2 | `false` | `commandTabEnabled` | `XFinder/Views/Detail/WindowDetailViews.swift:11` | Control trong trang cài đặt |
| `windowPreview.showHiddenWindows` | `false` | `showHiddenWindows` | `XFinder/Views/Detail/WindowDetailViews.swift:12` | Control trong trang cài đặt |
| `windowPreview.switcherHotkey` · khai báo lặp ×2 | `"commandTab"` | `switcherHotkey` | `XFinder/Views/Detail/WindowDetailViews.swift:13` | Control trong trang cài đặt |
| `windowPreview.animationEnabled` | `true` | `animationEnabled` | `XFinder/Views/Detail/WindowDetailViews.swift:14` | Control trong trang cài đặt |
| `windowPreview.currentScreenOnly` | `false` | `currentScreenOnly` | `XFinder/Views/Detail/WindowDetailViews.swift:16` | Control trong trang cài đặt |
| `snapzones.enabled` · khai báo lặp ×2 | `true` | `snapEnabled` | `XFinder/Views/Detail/WindowDetailViews.swift:224` | Control trong trang cài đặt |
| `snapzones.restoreOnUnsnap` | `true` | `restoreOnUnsnap` | `XFinder/Views/Detail/WindowDetailViews.swift:225` | Control trong trang cài đặt |
| `snapzones.showPreview` | `true` | `showPreview` | `XFinder/Views/Detail/WindowDetailViews.swift:226` | Control trong trang cài đặt |
| `snapzones.haptic` | `false` | `hapticEnabled` | `XFinder/Views/Detail/WindowDetailViews.swift:227` | Control trong trang cài đặt |
| `snapzones.dragEnabled` | `true` | `dragEnabled` | `XFinder/Views/Detail/WindowDetailViews.swift:228` | Control trong trang cài đặt |
| `snapzones.hotkeysEnabled` · khai báo lặp ×2 | `true` | `hotkeysEnabled` | `XFinder/Views/Detail/WindowDetailViews.swift:229` | Control trong trang cài đặt |
| `snapzones.edgeMargin` | `20.0` | `edgeMargin` | `XFinder/Views/Detail/WindowDetailViews.swift:230` | Control trong trang cài đặt |
| `snapzones.stageInset` | `68.0` | `stageInset` | `XFinder/Views/Detail/WindowDetailViews.swift:231` | Control trong trang cài đặt |
| `snapzones.reserveStage` | `true` | `reserveStage` | `XFinder/Views/Detail/WindowDetailViews.swift:232` | Control trong trang cài đặt |
| `snapzones.notchRow` | `true` | `notchRow` | `XFinder/Views/Detail/WindowDetailViews.swift:234` | Control trong trang cài đặt |
| `snapzones.remember` | `false` | `rememberLayouts` | `XFinder/Views/Detail/WindowDetailViews.swift:236` | Control trong trang cài đặt |
| `snapzones.rememberFrames` | `false` | `rememberFrames` | `XFinder/Views/Detail/WindowDetailViews.swift:237` | Control trong trang cài đặt |
| `diagnostics.localLog` | `true` | `localLog` | `XFinder/Views/SettingsWindow.swift:9` | Control trong trang cài đặt |
| `analytics.optOut` | `false` | `analyticsOptOut` | `XFinder/Views/SettingsWindow.swift:14` | Control trong trang cài đặt |

## `UserDefaults` literal trực tiếp trong View

| Khoá | View | Dòng / hành vi |
|---|---|---|
| `fileBrowser.onboardingDone` | `XFinder/Views/Browser/OnboardingWindow.swift` | 88: `UserDefaults.standard.set(value, forKey: "fileBrowser.onboardingDone")` |
| `general.automationVerified` | `XFinder/Views/Detail/DashboardDetailView.swift` | 344: `automationOK = UserDefaults.standard.bool(forKey: "general.automationVerified")` |
| `snapzones.orientation` | `XFinder/Views/Detail/WindowDetailViews.swift` | 585: `get: { UserDefaults.standard.string(forKey: "snapzones.orientation") ?? "horizontal" },` |
| `snapzones.orientation` | `XFinder/Views/Detail/WindowDetailViews.swift` | 586: `set: { UserDefaults.standard.set($0, forKey: "snapzones.orientation") }` |

## Cài đặt mang trạng thái theo phiên, không phải khoá bền vững

Các form dưới đây dùng `@State`/model/store trong phiên hoặc ghi vào store riêng thay vì `@AppStorage`; không được báo chúng là tuỳ chọn bền vững nếu chưa mở reader/store: Archive destination/conflict/compression options (`CompressDetailView.swift:48–84`); rename mode/sequence/text (`BatchRenameDetailView.swift:9–10,61–104`); sync pair schedule/delete policy (`FolderSyncDetailView.swift:204–244`, persisted per pair by `FolderSyncController`); window-selected exclusion list and snap custom-memory records (`WindowDetailViews.swift:118–158,401–487`); PDF page-range/output destination (`PdfToolsDetailView.swift:42–131`); local filters and criteria in search (`SearchDetailViews.swift:49–109,350–425`).

## Các key cùng xuất hiện ở nhiều view cần phân biệt owner với mirror

| Khoá | Các view khai báo | Ghi chú kiểm kê |
|---|---|---|
| `capture.annotate.color` | `XFinder/Views/Capture/AnnotateWindow.swift:227`, `XFinder/Views/Detail/CaptureDetailView.swift:24` | Giữ đúng trạng thái hiện tại; một số là control lặp (đặc biệt `ShortcutsDetailView`), một số là reader/runtime mirror. Cần phân loại trước khi chuyển trang hoặc bỏ control. |
| `capture.annotate.width` | `XFinder/Views/Capture/AnnotateWindow.swift:228`, `XFinder/Views/Detail/CaptureDetailView.swift:25` | Giữ đúng trạng thái hiện tại; một số là control lặp (đặc biệt `ShortcutsDetailView`), một số là reader/runtime mirror. Cần phân loại trước khi chuyển trang hoặc bỏ control. |
| `capture.enabled` | `XFinder/Views/Detail/CaptureDetailView.swift:12`, `XFinder/Views/Detail/ShortcutsDetailView.swift:13` | Giữ đúng trạng thái hiện tại; một số là control lặp (đặc biệt `ShortcutsDetailView`), một số là reader/runtime mirror. Cần phân loại trước khi chuyển trang hoặc bỏ control. |
| `clipboard.globalHotkey` | `XFinder/Views/Detail/SettingsDetailView.swift:68`, `XFinder/Views/Detail/ShortcutsDetailView.swift:22` | Giữ đúng trạng thái hiện tại; một số là control lặp (đặc biệt `ShortcutsDetailView`), một số là reader/runtime mirror. Cần phân loại trước khi chuyển trang hoặc bỏ control. |
| `clipboard.shelfHotkey` | `XFinder/Views/Detail/SettingsDetailView.swift:56`, `XFinder/Views/Detail/ShortcutsDetailView.swift:23` | Giữ đúng trạng thái hiện tại; một số là control lặp (đặc biệt `ShortcutsDetailView`), một số là reader/runtime mirror. Cần phân loại trước khi chuyển trang hoặc bỏ control. |
| `dropTray.notchEnabled` | `XFinder/Views/Detail/AIAgentsDetailView.swift:9`, `XFinder/Views/Detail/CalendarSettingsDetailView.swift:9`, `XFinder/Views/Detail/DropTrayDetailView.swift:18`, `XFinder/Views/Detail/LiveActivitiesDetailView.swift:8`, `XFinder/Views/Detail/MediaDetailView.swift:9`, `XFinder/Views/Detail/NotchInterfaceDetailView.swift:9` | Giữ đúng trạng thái hiện tại; một số là control lặp (đặc biệt `ShortcutsDetailView`), một số là reader/runtime mirror. Cần phân loại trước khi chuyển trang hoặc bỏ control. |
| `fileBrowser.downloadsHotkey` | `XFinder/Views/Browser/BrowserSettingsWindow.swift:94`, `XFinder/Views/Detail/ShortcutsDetailView.swift:21` | Giữ đúng trạng thái hiện tại; một số là control lặp (đặc biệt `ShortcutsDetailView`), một số là reader/runtime mirror. Cần phân loại trước khi chuyển trang hoặc bỏ control. |
| `fileBrowser.enabled` | `XFinder/Views/Detail/FileBrowserDetailView.swift:6`, `XFinder/Views/Detail/ShortcutsDetailView.swift:18` | Giữ đúng trạng thái hiện tại; một số là control lặp (đặc biệt `ShortcutsDetailView`), một số là reader/runtime mirror. Cần phân loại trước khi chuyển trang hoặc bỏ control. |
| `fileBrowser.globalHotkey` | `XFinder/Views/Detail/FileBrowserDetailView.swift:7`, `XFinder/Views/Detail/ShortcutsDetailView.swift:20` | Giữ đúng trạng thái hiện tại; một số là control lặp (đặc biệt `ShortcutsDetailView`), một số là reader/runtime mirror. Cần phân loại trước khi chuyển trang hoặc bỏ control. |
| `fileBrowser.launcherShortcut` | `XFinder/Views/Detail/FileBrowserDetailView.swift:8`, `XFinder/Views/Detail/ShortcutsDetailView.swift:19` | Giữ đúng trạng thái hiện tại; một số là control lặp (đặc biệt `ShortcutsDetailView`), một số là reader/runtime mirror. Cần phân loại trước khi chuyển trang hoặc bỏ control. |
| `fileBrowser.paneFocusStyle` | `XFinder/Views/Browser/BrowserSettingsWindow.swift:189`, `XFinder/Views/Browser/PaneView.swift:25` | Giữ đúng trạng thái hiện tại; một số là control lặp (đặc biệt `ShortcutsDetailView`), một số là reader/runtime mirror. Cần phân loại trước khi chuyển trang hoặc bỏ control. |
| `fileBrowser.previewShowMore` | `XFinder/Views/Browser/BrowserSettingsWindow.swift:216`, `XFinder/Views/Browser/PreviewPaneView.swift:26` | Giữ đúng trạng thái hiện tại; một số là control lặp (đặc biệt `ShortcutsDetailView`), một số là reader/runtime mirror. Cần phân loại trước khi chuyển trang hoặc bỏ control. |
| `fileBrowser.showLearnButton` | `XFinder/Views/Browser/BrowserRootView.swift:19`, `XFinder/Views/Browser/BrowserSettingsWindow.swift:190` | Giữ đúng trạng thái hiện tại; một số là control lặp (đặc biệt `ShortcutsDetailView`), một số là reader/runtime mirror. Cần phân loại trước khi chuyển trang hoặc bỏ control. |
| `fileBrowser.showLocationBar` | `XFinder/Views/Browser/BrowserSettingsWindow.swift:185`, `XFinder/Views/Browser/PaneView.swift:19` | Giữ đúng trạng thái hiện tại; một số là control lặp (đặc biệt `ShortcutsDetailView`), một số là reader/runtime mirror. Cần phân loại trước khi chuyển trang hoặc bỏ control. |
| `fileBrowser.showPathBar` | `XFinder/Views/Browser/BrowserSettingsWindow.swift:186`, `XFinder/Views/Browser/PaneView.swift:20` | Giữ đúng trạng thái hiện tại; một số là control lặp (đặc biệt `ShortcutsDetailView`), một số là reader/runtime mirror. Cần phân loại trước khi chuyển trang hoặc bỏ control. |
| `fileBrowser.showPreview` | `XFinder/Views/Browser/BrowserSettingsWindow.swift:215`, `XFinder/Views/Browser/PaneView.swift:23` | Giữ đúng trạng thái hiện tại; một số là control lặp (đặc biệt `ShortcutsDetailView`), một số là reader/runtime mirror. Cần phân loại trước khi chuyển trang hoặc bỏ control. |
| `fileBrowser.showStatusBar` | `XFinder/Views/Browser/BrowserSettingsWindow.swift:187`, `XFinder/Views/Browser/PaneView.swift:21` | Giữ đúng trạng thái hiện tại; một số là control lặp (đặc biệt `ShortcutsDetailView`), một số là reader/runtime mirror. Cần phân loại trước khi chuyển trang hoặc bỏ control. |
| `fileBrowser.sidebar.cloudStorage` | `XFinder/Views/Browser/BrowserSettingsWindow.swift:241`, `XFinder/Views/Browser/BrowserSettingsWindow.swift:336` | Giữ đúng trạng thái hiện tại; một số là control lặp (đặc biệt `ShortcutsDetailView`), một số là reader/runtime mirror. Cần phân loại trước khi chuyển trang hoặc bỏ control. |
| `finderKeyboard.cutPaste` | `XFinder/Views/Detail/FinderKeyboardDetailView.swift:5`, `XFinder/Views/Detail/ShortcutsDetailView.swift:29` | Giữ đúng trạng thái hiện tại; một số là control lặp (đặc biệt `ShortcutsDetailView`), một số là reader/runtime mirror. Cần phân loại trước khi chuyển trang hoặc bỏ control. |
| `finderKeyboard.deleteToTrash` | `XFinder/Views/Detail/FinderKeyboardDetailView.swift:6`, `XFinder/Views/Detail/ShortcutsDetailView.swift:30` | Giữ đúng trạng thái hiện tại; một số là control lặp (đặc biệt `ShortcutsDetailView`), một số là reader/runtime mirror. Cần phân loại trước khi chuyển trang hoặc bỏ control. |
| `finderKeyboard.returnOpens` | `XFinder/Views/Detail/FinderKeyboardDetailView.swift:7`, `XFinder/Views/Detail/ShortcutsDetailView.swift:31` | Giữ đúng trạng thái hiện tại; một số là control lặp (đặc biệt `ShortcutsDetailView`), một số là reader/runtime mirror. Cần phân loại trước khi chuyển trang hoặc bỏ control. |
| `notes.edgeEnabled` | `XFinder/Views/Detail/DashboardDetailView.swift:16`, `XFinder/Views/Detail/NotesDetailView.swift:11` | Giữ đúng trạng thái hiện tại; một số là control lặp (đặc biệt `ShortcutsDetailView`), một số là reader/runtime mirror. Cần phân loại trước khi chuyển trang hoặc bỏ control. |
| `quickSearch.enabled` | `XFinder/Views/Detail/SearchDetailViews.swift:49`, `XFinder/Views/Detail/ShortcutsDetailView.swift:14` | Giữ đúng trạng thái hiện tại; một số là control lặp (đặc biệt `ShortcutsDetailView`), một số là reader/runtime mirror. Cần phân loại trước khi chuyển trang hoặc bỏ control. |
| `quitProtection.enabled` | `XFinder/Views/Detail/AppQuitDetailView.swift:7`, `XFinder/Views/Detail/ShortcutsDetailView.swift:27` | Giữ đúng trạng thái hiện tại; một số là control lặp (đặc biệt `ShortcutsDetailView`), một số là reader/runtime mirror. Cần phân loại trước khi chuyển trang hoặc bỏ control. |
| `remoteConnect.enabled` | `XFinder/Views/Detail/RemoteConnectDetailView.swift:10`, `XFinder/Views/Detail/RemoteConnectDetailView.swift:158` | Giữ đúng trạng thái hiện tại; một số là control lặp (đặc biệt `ShortcutsDetailView`), một số là reader/runtime mirror. Cần phân loại trước khi chuyển trang hoặc bỏ control. |
| `snapzones.enabled` | `XFinder/Views/Detail/ShortcutsDetailView.swift:25`, `XFinder/Views/Detail/WindowDetailViews.swift:224` | Giữ đúng trạng thái hiện tại; một số là control lặp (đặc biệt `ShortcutsDetailView`), một số là reader/runtime mirror. Cần phân loại trước khi chuyển trang hoặc bỏ control. |
| `snapzones.hotkeysEnabled` | `XFinder/Views/Detail/ShortcutsDetailView.swift:26`, `XFinder/Views/Detail/WindowDetailViews.swift:229` | Giữ đúng trạng thái hiện tại; một số là control lặp (đặc biệt `ShortcutsDetailView`), một số là reader/runtime mirror. Cần phân loại trước khi chuyển trang hoặc bỏ control. |
| `translate.hotkeyEnabled` | `XFinder/Views/Detail/ShortcutsDetailView.swift:24`, `XFinder/Views/Detail/SmartSelectDetailView.swift:11` | Giữ đúng trạng thái hiện tại; một số là control lặp (đặc biệt `ShortcutsDetailView`), một số là reader/runtime mirror. Cần phân loại trước khi chuyển trang hoặc bỏ control. |
| `windowPreview.commandTabEnabled` | `XFinder/Views/Detail/ShortcutsDetailView.swift:28`, `XFinder/Views/Detail/WindowDetailViews.swift:11` | Giữ đúng trạng thái hiện tại; một số là control lặp (đặc biệt `ShortcutsDetailView`), một số là reader/runtime mirror. Cần phân loại trước khi chuyển trang hoặc bỏ control. |
| `windowPreview.hoverEnabled` | `XFinder/Views/Detail/DashboardDetailView.swift:17`, `XFinder/Views/Detail/WindowDetailViews.swift:9` | Giữ đúng trạng thái hiện tại; một số là control lặp (đặc biệt `ShortcutsDetailView`), một số là reader/runtime mirror. Cần phân loại trước khi chuyển trang hoặc bỏ control. |
| `windowPreview.switcherHotkey` | `XFinder/Views/Detail/ShortcutsDetailView.swift:12`, `XFinder/Views/Detail/WindowDetailViews.swift:13` | Giữ đúng trạng thái hiện tại; một số là control lặp (đặc biệt `ShortcutsDetailView`), một số là reader/runtime mirror. Cần phân loại trước khi chuyển trang hoặc bỏ control. |

## Giới hạn của kiểm kê

Đây là source inventory, không khẳng định mỗi pane đã được mở/launched hay mọi control hoạt động đúng khi chạy. Khoá do controller tự định nghĩa, model `Codable`/SQLite, Keychain, security-scoped bookmark, bundle settings và control tạm thời cần đối chiếu cùng feature; bảng MFinder bên dưới sẽ ghi riêng các trường hợp đó, không suy ra từ việc không thấy `@AppStorage`.
