# XF-T32 W2/W3 — jobs for Agent 2 (Sol) until the next Claude session

Base: `main` at the commit that adds this file. Contract (binding): `docs/specs/XF-T32-w23-contract.md`. Design ref:
`docs/specs/XF-T32-tilde-direction.md` §3b. Rules: `CLAUDE.md` §3 + `docs/AGENT_QUICKSTART.md`.

## Ground rules (every job)
- One job = one branch `agent/sol-T32-<job>` from `main` (`git -C /Users/wolong/github/XFinder ...`; the shell's `cd` can die).
  Commit only on that branch, English message, no attribution. **No push, no merge into main.**
- Edit ONLY the files listed for the job. pbxproj, symlinks, the L10n store and FeatureCatalog belong to Claude.
- New strings: `L10n.t("Vietnamese literal")` + an add-only script `scripts/add-xft32-<job>-l10n-entries.py` (copy the shape
  of an existing `scripts/add-*-l10n-entries.py`) — do NOT run it.
- Tokens only (`XFinderTokens`); `python3 scripts/audit-ui-tokens.py` must print `TOTAL 0`.
- Before committing: `XF_ROOT=<your checkout> XF_OUT=<your scratch>/build sh scripts/build-and-check.sh` → BUILD SUCCEEDED,
  `swift test --package-path Tests` → 0 failures. Paste both last lines into the commit body.
- Never install, never launch XFinder, never send events/keys to other apps, never delete outside your own scratch folder,
  no `@unchecked Sendable`, no `print`, no `NSApp.activate`.
- Swift 6: an actor's `deinit` must not read a non-Sendable stored property (it compiles in `Tests/` and fails in the app).

## State when Claude stopped (2026-10-26 16:2x)
| Unit | Branch | State |
|:--|:--|:--|
| spaces | `xf-t32-w23-spaces` (713847a) | built + verified PASS; one medium defect → job S1 |
| sidebarparts | `xf-t32-w23-sidebarparts` (cd3699a) | built, build green, **not verified** → job V1 |
| sidebar | `xf-t32-w23-sidebar` (22ef1e1) | built, **not verified** → job V2 |
| metadata | — | not built → job B1 |
| tree | — | not built → job B2 |
| menus | — | not built → job B3 |
| chrome | — | not built → job B4 |

## Jobs (do in this order; B1 first — the views read its data)

**B1 · metadata** — `XFinder/Core/Browser/BrowserMetadata.swift`, `Tests/XFinderLogicTests/BrowserMetadataTests.swift`.
Contract §A. Caches per folder, synchronous reads, mutations update the cache then write through `MetadataStore` (actor,
real). `load(folder:)` drops a duplicate in-flight load of the same folder and bumps `revision` only when data changed;
`liveGroups` cached by (revision, refs). Tests: temp-URL store, wait for `revision` with bounded `Task.sleep` polling; cover
NFD vs NFC paths (`MetadataStore.normalized` returns NFC; Swift `String ==` is canonical). Filter `BrowserMetadataTests`.

**B2 · tree** — `XFinder/Views/Browser/FileListView.swift` only. Contract §E. Look at
`scratchpad/claude/tilde/sheet-live-groups.png` and `sheet-pinned-folders.png` if present; else `/Applications/Tilde.app`
(look only). Tree mode = only the Name column visible: no header, 31 pt rows. Pinned card = custom `NSTableRowView`
(rounded 10, first/last row corners) fed by `PinRules.split`. Name cell: emoji/icon · name · "aka …" · chips
(`BrowserMetadata.shared.visibleProperties` + `option(for:property:)`, `XFinderTokens.PropertyTint`) · hover `⋯` (opens
`RowActionsMenu.menu(for:pane:model:)`) · `›` for folders. Reload only visible rows on `revision` change.
**Must keep**: `ListingDiff` in-place patch + `editedRow` guard, rename, drag/drop, spring-load, cut fade,
`PaneActivating` click activation, group rows. No hit-testing overlay above the outline.

**B3 · menus** — `XFinder/Views/Browser/RowActionsMenu.swift`, `PropertyEditorPopover.swift`,
`XFinder/Core/Browser/BrowserWindowModel+Views.swift`. Contract §F. Menu order as Tilde: Pin in “folder” / Unpin ·
one item per property with value + submenu (Clear, coloured pills ✓) · Add property › · nickname · emoji. `folderMenu`:
Filter · Sort › · Properties (n visible) › · Group › (None, every `GroupBy`, every property). `rebuildSections`: property
branch when `propertyGroupID` is set; add `func metadataDidChange()` on `PaneState` there.

**B4 · chrome** — `XFinder/Views/Browser/PaneView.swift`, `PathBarView.swift`, `RelatedItemsStrip.swift`,
`BrowserSettingsWindow.swift`, and in `XFinder/Core/Browser/BrowserSettings.swift` ONLY the `showPathBar` default
false→true. Contract §G. Breadcrumb at the bottom (12 pt), related strip under the location bar, pane focus `dim` =
opacity only (no overlay; keep the no-tap-gesture comment and `onGeometryChange` in `PaneView`), picker in General tab.

**S1 · spaces fix** — branch from `xf-t32-w23-spaces`, file `XFinder/Core/Browser/SpaceController.swift` + its tests.
Defect: at launch the mirror (`BrowserSettings.sidebarLayout`) replaces the active Space's sidebar when they differ, but a
missing key decodes to `SidebarLayout()` with fresh UUIDs every read ⇒ save on every relaunch and custom favorites reset.
Fix: `writeLayout(store.active.sidebar)` on first launch/migration; adopt the mirror only when the key exists. Test: a
`legacyLayout` closure returning a fresh `SidebarLayout()` each call ⇒ second launch saves nothing.

**V1 · verify sidebarparts** — read-only review of `xf-t32-w23-sidebarparts` vs contract §C + Tilde ref; rebuild it in your
own `XF_OUT`; write findings (file:line, evidence, fix) to `docs/reviews/XF-T32-w23-sidebarparts-sol.md` on branch
`agent/sol-T32-V1`. Do not edit the code under review.

**V2 · verify sidebar** — same for `xf-t32-w23-sidebar` vs §D (order Header · Favorites · Live Groups · Recents ·
Locations · Tags · Saved searches · Sync · Pager outside the ScrollView; every existing behaviour kept: eject, rename,
groups, drag, Pro banners). Also list every place that still writes `BrowserSettings.sidebarLayout` without
`SpaceController.shared.sidebarDidChange` (known: `BrowserSidebarView`, `BrowserWindowModel+Views.swift`,
`BrowserSettingsWindow.swift`). Output `docs/reviews/XF-T32-w23-sidebar-sol.md` on `agent/sol-T32-V2`.

## Report back (one file)
Append one line per finished job to `docs/AGENT_TASKS.md` under "XF-T32 W2/W3 (Sol)": job · branch · sha · build line ·
test line · anything not done and why. Claude reviews, merges, adds L10n/pbxproj, runs mutation, installs and measures.
