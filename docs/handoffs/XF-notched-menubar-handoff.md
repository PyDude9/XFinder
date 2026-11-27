# XFinder IDE handoff

## Start here

Open `/Users/wolong/github/XFinder` in the new IDE. Continue from local branch `agent/codex-XF-UI-COHESION`, which includes the installed build and the handoff. The verified source baseline through the previous notes is `dd62bac`; latest app code is `03c9b88`. Confirm the worktree is clean before branching for the next task.

At handoff, `main` and `origin/main` point to `614cd4f`. The newer integration is local. Starting from `main` would omit Quit, the Settings cleanup, and Antigravity's performance work. The published `v1.4.0` tag points to `0071eb3`.

## Completed work

| Commits on the continuation branch | Result |
|---|---|
| `55970cb`, `8ec611e`, `f8cdf5e` | Removed the standalone Anti-sleep page and duplicate Overview row. Notch System owns duration, stop and lid wake. The display-awake preference remains in Features & Permissions, and old links resolve there. Shared typography and row styling between dropdown and Settings, tightened the sidebar, aligned System Monitor tabs, and corrected the English Uptime suffix. |
| `ecda9f4`, `725c462`, `f8f7eed` | Integrated Antigravity's work. Skipped Notch hover layout away from the top band, removed repeat calculations, reused the popover and cached the icon. Deleted three unreachable legacy dropdown views and their Xcode registrations. |
| `03c9b88`, `dd62bac` | Added Quit. Left-click menu now contains File Browser when enabled, Uninstall Apps, Settings and Quit. The native right-click menu is a separate entry point. |

The base already includes Notch and Full Settings parity for Stocks, Website Analytics and Revenue, plus Massive key save feedback. Full Settings owns provider setup; Notch displays data and provides quick access.

## Evidence and rollback

- **Installed on `wolong`** at `/Applications/XFinder.app`. The running executable path was verified and the installed debug dylib matched the signed build at `/tmp/xfinder-ui-perf-integrated/out/XFinder.app` byte for byte. SHA-256 `20f785e5b5e037edf95cadb4babaac7438e9efa9eae0b4bd6502de69f5d58621`.
- **Integrated gate** passed on arm64 Debug with 3,582 tests, zero failures, one skipped, and all localization and UI audits green. Atlas verified the four dropdown rows, outside-click dismissal, reopen and Quit on the helper. An earlier build of the same Settings UI was checked in light appearance.
- **Rollback** is documented per commit in the [UI and rollback notes](../specs/XF-UI-COHESION.md). The previous installed bundle is at `/tmp/xfinder-ui-perf-rollback.UzMWSP/XFinder.app` while that temporary directory exists.

## Next work

- **Performance**. Antigravity profiled the old installed app. There is no controlled before/after result. If performance is the next ticket, measure idle CPU/wakeups, dropdown open time and Notch tab switching under matched conditions before claiming an improvement. The worker's spec and baseline are in [performance notes](../specs/XF-PERF-MENUBAR.md) and the first section of [AGENT_WORKLOG.md](../AGENT_WORKLOG.md). Finder frontmost-app lookups and synchronous LocalAppUsageTracker persistence were observed candidates, not completed fixes.
- **Live checks**. Dark Settings appearance, Notch hover on different displays, and physical lid-close behavior remain unverified. Real provider accounts and live stock entitlement were not exercised. Open these only if the next ticket needs them.
- **Source delivery**. The installed build is ahead of GitHub. Review the local branch against `origin/main` before publishing it, and verify the remote head after any authorized publication. Old worktrees are separate. Do not merge their contents based on their names or age.

For dropdown changes, start at [MenubarPanelView.swift](../../XFinder/Views/MenubarPanelView.swift) and [MenubarController.swift](../../XFinder/App/MenubarController.swift). For Full Settings, start at [SidebarDestination.swift](../../XFinder/Models/SidebarDestination.swift) and the relevant view. Read [AGENT_QUICKSTART.md](../AGENT_QUICKSTART.md) and the next ticket's spec. Use a unique `XF_OUT` and one reviewed bundle path per install.
