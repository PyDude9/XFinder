# XF-T32 W2 + W3 — contract (sidebar Spaces/Live Groups · list tree, Pinned, chips, menus, pane chrome)

Spec: `XF-T32-tilde-direction.md` §3b (design ref, binding) · §4 W2/W3. W1 data layer: `XF-T32-w1-contract.md`.
Design evidence (look before building): `scratchpad/claude/tilde/sheet-live-groups.png`, `sheet-pinned-folders.png`,
`sheet-properties.png`, `sheet-spaces.png`, `sheet-split-view.png` (6 videos at 1 fps; Tilde installed at
`/Applications/Tilde.app` — look, never copy code). Copy mechanism + position + style; add no block Tilde lacks.

Fan-out by FILE. Each builder edits ONLY its files. pbxproj, symlinks, L10n store, FeatureCatalog are the integrator's.
New strings: wrap in `L10n.t("literal")` and write an add-only script `scripts/add-xft32-<unit>-l10n-entries.py`
(copy the shape of an existing `scripts/add-*-l10n-entries.py`; `{en, scope}`), DO NOT run it.
Rules that bite here: CLAUDE.md §3.2 (one key one control, view default == reader default), §3.3 #14 (no AppKit lookup in
`body` without a cache; filename rows truncate middle), tokens only (`XFinderTokens`, `audit-ui-tokens.py` = 0 literals —
add a token to `XFinderTokens.swift` only if your unit owns it, see table), Swift 6 strict, no `@unchecked Sendable`.

## Units and owned files

| Unit | Owns (edit only these) | Does |
|:--|:--|:--|
| `metadata` | `Core/Browser/BrowserMetadata.swift`, `Tests/XFinderLogicTests/BrowserMetadataTests.swift` | §A façade over `MetadataStore` |
| `spaces` | `Core/Browser/SpaceController.swift`, `Tests/XFinderLogicTests/SpaceControllerTests.swift` | §B persistence + active Space |
| `sidebarparts` | `Views/Browser/SidebarSpaceHeader.swift`, `SidebarSpacePager.swift`, `SidebarLiveGroupsSection.swift` | §C new sidebar pieces |
| `sidebar` | `Views/Browser/BrowserSidebarView.swift` | §D compose + restyle the sidebar |
| `tree` | `Views/Browser/FileListView.swift` | §E List = tree: Pinned, chips, aka, emoji, hover ⋯, 31 pt |
| `menus` | `Views/Browser/RowActionsMenu.swift`, `PropertyEditorPopover.swift`, `Core/Browser/BrowserWindowModel+Views.swift` | §F row ⋯ menu, property editor, group by property |
| `chrome` | `Views/Browser/PaneView.swift`, `PathBarView.swift`, `RelatedItemsStrip.swift`, `BrowserSettingsWindow.swift` | §G breadcrumb bottom, related strip, pane focus |

Already on main (integrator, do not change signatures): `PaneState.propertyGroupID: UUID?` (nil = use `groupBy`),
`PaneState` calls `BrowserMetadata.shared.load(folder:)` after every successful listing, `BrowserSettings.paneFocusStyle`
(`fileBrowser.paneFocusStyle`, String `"dim"` | `"outline"`, default `"dim"`).

## §A `BrowserMetadata` (@MainActor @Observable, Foundation + Observation only — symlinked into Tests)

```swift
@MainActor @Observable final class BrowserMetadata {
    static let shared: BrowserMetadata            // MetadataStore.shared
    init(store: MetadataStore)
    private(set) var revision: Int                // bumped after every load that changed data and every mutation
    private(set) var catalog: PropertyCatalog     // loaded once at init (Task), refreshed after updateCatalog
    func load(folder: String)                     // async fetch: pins(in:), nicknames(in:), emoji of folder AND its
                                                  // child folders seen in nicknames/emoji tables, selections(in:),
                                                  // folderProperties(folder). Coalesce: a second load of the same
                                                  // folder while one runs is dropped. Bumps revision only if data differs.
    func pins(in folder: String) -> [String]
    func nickname(for path: String) -> String?
    func emoji(for folder: String) -> String?
    func option(for path: String, property: UUID) -> PropertyOption?
    func shownProperties(in folder: String) -> [(definition: PropertyDefinition, showInView: Bool)]  // folder_properties order
    func visibleProperties(in folder: String) -> [PropertyDefinition]   // showInView == true only
    func togglePin(_ path: String, in folder: String)                  // PinRules.toggled, then store.setPins
    func setNickname(_ nickname: String?, for path: String)
    func setEmoji(_ emoji: String?, for folder: String)
    func select(path: String, property: UUID, option: UUID?)          // nil = clear
    func updateCatalog(_ change: (inout PropertyCatalog) -> Void)       // mutate a copy, store.saveCatalog, publish
    func setFolderProperties(_ folder: String, _ list: [(property: UUID, showInView: Bool)])
    func related(to folder: String) -> [String]                         // RelationRules.related
    func addRelation(_ a: String, _ b: String)
    func removeRelation(_ a: String, _ b: String)
    func liveGroups(_ refs: [LiveGroupRef]) -> [PropertyRules.LiveGroup]  // from store.allSelections()/allNicknames(),
                                                  // cached; recomputed on revision change, never per body call
    func itemMoved(from: String, to: String)      // store.itemMoved + rewrite in-memory caches
    func itemRemoved(_ path: String)
    func relieve(_ plan: PressureRules.Plan)      // drop caches of folders no pane shows (keep the last 8 loaded)
}
```
Reads are synchronous from in-memory caches filled by `load`/mutations (never block main on SQLite). Mutations update
the cache first (UI instant), then write through the actor. Path keys: compare with Swift `String` (canonical) —
`MetadataStore.normalized` is NFC. Tests: load → reads; mutation → revision bump + cache; coalesced loads; move rewrite.

## §B `SpaceController` (@MainActor @Observable — symlinked into Tests)

```swift
@MainActor @Observable final class SpaceController {
    static let shared: SpaceController   // UserDefaults "fileBrowser.spaces" (Data) + BrowserSettings.sidebarLayout
    init(load: @escaping () -> Data?, save: @escaping (Data) -> Void,
         legacyLayout: @escaping () -> SidebarLayout, writeLayout: @escaping (SidebarLayout) -> Void)
    private(set) var store: SpaceStore
    var active: Space { get }
    func activate(_ id: UUID)
    func activateNext(); func activatePrevious()
    @discardableResult func add(name: String) -> Space   // clones the active sidebar, activates the new Space
    func rename(_ id: UUID, to name: String) -> Bool
    func delete(_ id: UUID) -> Bool                       // last Space cannot be deleted (SpaceStore rule)
    func toggleLiveGroup(_ ref: LiveGroupRef)
    func sidebarDidChange(_ layout: SidebarLayout)        // the sidebar saved a layout ⇒ store it in the active Space
}
```
Invariant: `writeLayout(active.sidebar)` after every activation, so the existing `BrowserSettings.sidebarLayout` reader
(and every open window's sidebar) always shows the active Space's sidebar. First launch: `SpaceStore.decode(nil,
fallbackLayout: legacyLayout())` (one Space wrapping today's sidebar, name key `SpaceStore.migratedSpaceNameKey`).
Every mutation saves. Tests with in-memory closures: migration, activate writes layout, add clones + activates, delete
last refused, sidebarDidChange persists into the active Space only, corrupt data ⇒ migration.

## §C sidebar parts (SwiftUI)

```swift
struct SidebarSpaceHeader: View { let spaces: SpaceController; let onToggleSidebar: () -> Void }
struct SidebarSpacePager: View { let spaces: SpaceController; let onNewGroup: () -> Void }
struct SidebarLiveGroupsSection: View {
    let spaces: SpaceController; let metadata: BrowserMetadata
    let onOpen: (String) -> Void                 // navigate the active pane
    let isSelected: (String) -> Bool
}
```
- Header: Space name 17 pt bold, left; click ⇒ menu: every Space (✓ active), separator, "Space mới…", "Đổi tên Space…",
  "Xoá Space" (disabled when only one). Rename/new via a small sheet with one text field. Sidebar-collapse button right
  (SF `sidebar.left`), calls `onToggleSidebar`.
- Pager (bottom, 28 pt): ⊕ left (`onNewGroup`), page dots centre (one per Space, active filled, click activates),
  + right (new Space). Trackpad two-finger horizontal swipe on the sidebar is NOT required.
- Live Groups: one sidebar section PER ref in `spaces.active.liveGroups` whose group still exists; section title =
  option title + colour dot (8 pt circle, `PropertyColor` tint); rows = folders in that group (folder icon 16 pt +
  nickname or last path component, 28 pt row, selected = gray rounded 8). Empty group ⇒ section still shows with a
  secondary "Trống" row. No refs ⇒ the view renders nothing.
- Colours: add `XFinderTokens.PropertyTint` (7 tints, chip background = tint at 18 % opacity, text = tint) in
  `XFinderTokens.swift` — owned by `sidebarparts`; `tree`/`menus` use it (build against the stub token on main).

## §D `BrowserSidebarView` (compose + restyle)
Order top→bottom (Tilde): `SidebarSpaceHeader` · Favorites (current favorites + groups) · Live Groups ·
Recents · Locations (volumes, iCloud, network) · Tags · Saved searches · Sync · `SidebarSpacePager` pinned at the bottom
(outside the ScrollView). Row height 28, icon 16, section title = small secondary semibold, selected row = gray fill
rounded 8 (`XFinderTokens.Radius`), background `NSVisualEffectView` `.sidebar` material. Reload `layout` when
`spaces.store.activeID` changes; every place that writes `BrowserSettings.sidebarLayout` also calls
`SpaceController.shared.sidebarDidChange(layout)`. Keep every existing behaviour (eject, rename, groups, drag, Pro
banners). Toggle-sidebar = existing `model.perform(.toggleSidebar)` (or the equivalent command already used by ⌥⌘S).

## §E `FileListView` → tree
- Tree mode = the List view when only the Name column is visible (column chooser unchanged): no header view, row 31 pt,
  no alternating rows, disclosure triangles kept. With more columns visible: today's table (22 pt, header) unchanged.
- Pinned block (tree mode and table mode): `PinRules.split(entries, folder: pane.path, pins: metadata.pins(in:))`;
  a group row "Đã ghim" then the pinned rows, drawn as one gray card rounded 10 (custom `NSTableRowView`: first row top
  corners, last row bottom corners); "This folder" pin shows the folder itself with a secondary "Thư mục này" label.
  Pinned rows are also NOT repeated below. Stale pins are left to `metadata` (call `togglePin` never; ignore them).
- Name cell (tree mode): icon (folder emoji from `metadata.emoji(for:)` drawn instead of the folder icon when set) ·
  name · "aka <nickname>" secondary 11 pt when a nickname exists · spacer · property chips (one per
  `metadata.visibleProperties(in: pane.path)` with a value: pill, `PropertyTint`, 11 pt semibold) · on hover a `⋯`
  button (opens `RowActionsMenu.menu(for:pane:model:)` under it) · `›` chevron for folders (secondary).
- Group rows from `pane.sections` keep working (property grouping arrives through the same `sections`).
- Re-render on `metadata.revision` change through the existing reload path (no full reload when only chips changed:
  `reloadData(forRowIndexes:columnIndexes:)` of visible rows).
- Keep: ListingDiff patching, rename, drag/drop, spring-load, cut fade, click activation (`PaneActivating`).

## §F row menu, property editor, group by property
```swift
enum RowActionsMenu { @MainActor static func menu(for entries: [DirectoryEntry], pane: PaneState, model: BrowserWindowModel) -> NSMenu }
struct PropertyEditorPopover: View { let propertyID: UUID; let folder: String; let metadata: BrowserMetadata }
```
- Menu (Tilde order): "Ghim vào “<folder>”" / "Bỏ ghim khỏi “<folder>”" · one item per catalog property: "<Name>" with
  the current value right-aligned, submenu "Xoá giá trị" + each option (coloured pill image) with ✓ on the current ·
  "Thêm thuộc tính ›" (submenu: properties not yet shown in this folder + "Thuộc tính mới…") · separator ·
  "Đặt biệt danh…" · "Đặt emoji…" (folders only; the system Character Viewer via `NSApp.orderFrontCharacterPalette`
  over a one-field sheet). Multi-selection applies to all. Wire it into the existing context menu too (append a section).
- Popover (opened from the folder `⋯` menu ▸ Thuộc tính ▸ <name>): back ‹ + title + ⋯ (Xoá thuộc tính), name field,
  "Hiện trong danh sách" toggle (→ `setFolderProperties`), Options list with drag handles (`moveOption`), each option
  row: colour dot + title (click ⇒ inline colour list: text field + 7 colour rows Gray…Purple), "+ Thêm lựa chọn".
- Folder-level `⋯` menu (button in `RelatedItemsStrip` right side, owned by `chrome`, calls
  `RowActionsMenu.folderMenu(pane:model:) -> NSMenu`): Lọc · Sắp xếp › · Thuộc tính (n hiện) › · Nhóm › (Không nhóm,
  each existing `GroupBy`, each property). Put `folderMenu` in `RowActionsMenu.swift` too.
- `BrowserWindowModel+Views.swift` `rebuildSections`: when `propertyGroupID` names a property in
  `BrowserMetadata.shared.catalog`, sections = `PropertyRules.sections(...)` mapped to `EntrySection(titleKey: "",
  titleArg: option.title)` and the unset section `EntrySection(titleKey: PropertyRules.unsetTitleKey, titleArg: nil)`;
  else today's code. Rebuild when `metadata.revision` changes for that pane's folder (observe in the view layer you own
  or expose `func metadataDidChange()` on the extension that the integrator calls).

## §G pane chrome
- Breadcrumb at the BOTTOM of every pane (Q-T32-13, default on): `PathBarView` restyled 12 pt, folder icon 12 pt per
  component, `›` separators, height 24, shown by `fileBrowser.showPathBar` whose default becomes `true` in BOTH the
  `@AppStorage` here and `BrowserSettings.showPathBar` (edit that one reader line too — allowed for this unit).
- `RelatedItemsStrip` (between the tab strip/location bar and the content, 28 pt): left "+ Thêm mục liên quan" (opens
  NSOpenPanel for folders ⇒ `metadata.addRelation(pane.path, picked)`), then one pill per `metadata.related(to:)` (click
  navigates, context menu "Bỏ liên kết"); right: 🔍 (focus filter: `model.filterFocusRequest = pane.id`), ⋯
  (`RowActionsMenu.folderMenu`), + (new folder: existing new-folder command).
- Pane focus: with ≥ 2 panes, `paneFocusStyle == "dim"` ⇒ inactive pane content at 0.55 opacity (`XFinderTokens`
  value) and no accent line; `"outline"` ⇒ today's accent line. Picker "Làm nổi ngăn đang dùng: Làm mờ ngăn khác /
  Viền ngăn đang dùng" in the General tab of `BrowserSettingsWindow` (`@AppStorage("fileBrowser.paneFocusStyle") = "dim"`).
  Dimming must not block clicks (opacity only, no overlay).

## Acceptance per unit (builder runs; verifier re-runs)
Build (`XF_ROOT=<your worktree> XF_OUT=<own scratch> sh scripts/build-and-check.sh` = BUILD SUCCEEDED), full
`swift test --package-path Tests` 0 failures, `python3 scripts/audit-ui-tokens.py` 0, no edits outside owned files
(`git diff --stat main`), report new L10n keys. Views: describe in the report how each §3b point was matched.
