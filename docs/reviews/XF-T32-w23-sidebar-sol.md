# V2 — composed sidebar review

Reviewed worker commit `22ef1e1` against contract §D. No edits were made on the worker branch. Screenshots/live interaction remain unverified.

- **High — same-Space edits from another window are stale.** BrowserSidebarView observes `activeID` only (`:115–118`), retaining a local SidebarLayout. Another window/settings edit in the same Space does not replace this copy, and the next local persist can overwrite it. Observe active.sidebar too and refresh hidden-volume filtering.
- **High — two mirror writers omit the Space update.** `BrowserWindowModel+Views.swift` (Add to Sidebar) and `BrowserSettingsWindow.swift` (restore hidden volume) write BrowserSettings.sidebarLayout without calling sidebarDidChange. The worker sidebar's own `persist()` does call it. The `SpaceController.shared` writeLayout closure is intentionally mirror-only to prevent a feedback loop. Resolve the two external writer paths and refresh the settings copy when the active sidebar changes.
- Order is header, Favorites/groups, Live Groups, Recents, location-related sections (AirDrop/iCloud/volumes/cloud/Bonjour), Tags, Saved searches, Sync, pager. Pager is outside ScrollView. Existing eject/busy sheets, rename, groups, drag/drop, spring-load, hidden volumes, provider actions and Pro banners remain in the diff. Row dimensions/icon sizes/selection radius meet the contract; consolidate the sidebar constants into existing tokens while integrating.
- **Related S1 defect:** absent mirror defaults create fresh item UUIDs and overwrite persisted Space sidebars at startup. Presence must be tested separately from decoding the default; regression coverage is required.

Follow-up fixes and validation are recorded in the finishing integration report. Source checks do not prove live eject/drop/VoiceOver behavior.

## Resolution / validation

All listed source findings were addressed on integration branch `agent/codex-T32-finish`, fix commit `4d6acf4`. Original worker branch is unchanged and clean. Rebuilt the exact worker checkout with build-and-check into an isolated output directory: `** BUILD SUCCEEDED **` (arm64). V1 output: `/tmp/xfinder-t32-v1-build`; V2 output: `/tmp/xfinder-t32-v2-build`. Logs: `/tmp/xfinder-t32-V1-validation.log` and `/tmp/xfinder-t32-V2-validation.log`. Final integrated app build succeeds and all 2819 tests pass; L10n/UI gates pass. These builds establish compilation/resource inclusion, not visual or interaction acceptance. No app was installed/launched and no events were sent to another app.
