# Tilde Spaces / Live Groups — evidence and implementation boundary

Target: `/Applications/Tilde.app`, bundle `com.blazegreenhalgh.FileExplorer`, version 1.0.2 build 14.

## Observed reference behavior

Seven owner-supplied Desktop screenshots dated 2026-10-28:

- 19.28.42: Space title at sidebar top, Workspaces/Favorites/Recents/Locations; overview can pin folder views.
- 19.28.46: one footer creation menu offers New Group, New Live Group, New Space.
- 19.30.16: Pin to Sidebar chooses a manual group (Favorites shown).
- 19.31.19 and 19.31.53: pane splits and workspace layout are separate from sidebar organization.
- 19.32.21: changing Space changes sidebar context (Github versus Tilde); pane content can remain.
- 19.32.29: New Live Group sheet contains name, source folder, filters, sorting, preview and save validation. This is a source-folder query, not merely an alias for a property value.

These are observations from supplied screenshots, not decompiled execution traces. Exact supported Tilde filter operators, persistence transactions and watcher implementation are not established by those images.

## REA evidence

REA CLI 6.8.0 `inspect-plist /Applications/Tilde.app --format json` successfully returned Evidence `ev_a4f7ceb9dc1fb31f450c4c0bcc0398ddae090ba4587234e312cb937213bd9c76`; repeated on 2026-10-29 with the same Evidence identity. Its native-macos provider confirms the bundle/version above. Resource-only evidence has null executable SHA256; it does not establish native control flow.

The earlier native Hopper route timed out at bridge startup after 120000 ms with `cleanup_incomplete`; no successful decompilation Evidence was returned. Hopper UI showed background analysis still running. Do not treat it as completed research or reuse that attempt as behavioral proof. The next-day continuation found no running owned Hopper process and no retained `/tmp/xfinder-tilde-*` native output. A bounded `xcrun nm -j` search on the executable found zero symbols containing LiveGroup, SidebarSpace or SpaceHome; this is ordinary shell evidence about symbol names, not proof those features are absent. No agent MCP configuration was modified, no Hopper/provider installed.

## XFinder choices

Inherited commit c6ce9c4 adds a visible three-choice menu, modal focused manual group creation, independent custom-group visibility, 28-point Space targets, additive per-Space folder queries and live directory subscription. Legacy property-backed groups remain separate and compatible.

Continuation fixes source-read validation, error/empty distinction, cancellation and stale delivery. DirectoryLoadCoordinator is the authoritative reader and shared watcher. Preview/sidebars filter and sort off-main; each new delivery supersedes the prior projection. Space removal and group removal only alter saved sidebar metadata, not source files.

## Installed acceptance, 2026-10-29

Verified through XFinder GUI: three-choice menu; focused Space creation; focused manual-group creation and immediate empty-group guidance; invalid file source disables Save and displays the actual not-directory error; valid folder preview contains only the matching item; Save renders group; creating a matching scratch subfolder updates sidebar automatically; clicking a member opens its real folder; switching to existing Git Space hides the test group's section.

Current build SHA256 matches installed dylib: b60bb172099341a167c948cd3632f4640961a306a7177706ed52ddea5494455e. Scratch source `/tmp/xfinder-livegroup-20261029/source`; all filesystem mutations were confined there.

Unverified at this checkpoint: forced permission denial/timeout, deterministic cache-vs-disk race injection, external volume removal, all editor operator combinations in GUI, VoiceOver. Core filters/sorts/persistence/Space isolation have existing pure tests (66 targeted, 2864 full suite). Build and all seven gates passed separately.

Cleanup: returned to QA Space and confirmed its saved group/members reappeared, then removed only the newly-created QA Space through its named confirmation. Active Space returned to Git. Scratch source folders remain intact. GUI context menu exposed Edit Live Group / Remove from Sidebar; editing/removing a single group was not completed live.
