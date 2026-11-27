# XFinder IDE handoff

## Starting point

Use the default branch of `PyDude9/XFinder`. Confirm it contains `283ba1f` and create one topic branch for the next task. The signed app running on `wolong` is `/Applications/XFinder.app`, built from `283ba1f`. Subsequent documentation changes do not require reinstalling. The published `v1.4.0` tag points to the earlier commit `0071eb3`.

## Work already integrated

| Commit | What shipped in source |
|---|---|
| `4c35b15`, `872559a` | Reconciled Notch and Full Settings routes, including Stocks, Website Analytics and Revenue. Added camera and reminders permission descriptions. |
| `0071eb3` | Made Massive the selectable stock feed, added API key save feedback, and gave Caffeine a dedicated Full Settings page alongside its Notch controls. |
| `283ba1f` | Replaced the tabbed left-click menu bar dropdown with File Browser (when enabled), Uninstall Apps and Settings. Added outside-click dismissal. The separate native right-click menu still exists. |

[Changelog](../../CHANGELOG.md) · [Dropdown specification](../specs/XF-MB-GENERAL-01.md)

## Where to look for the next dropdown change

- [MenubarPanelView.swift](../../XFinder/Views/MenubarPanelView.swift) owns the three actions.
- [MenubarController.swift](../../XFinder/App/MenubarController.swift) owns the status item, popover lifecycle, click monitors, and separate right-click menu.
- [MenubarPanelRules.swift](../../XFinder/Core/MenubarPanelRules.swift) owns dimensions and shared formatting and presets. Check references before removing legacy code.

## Verification and open checks

- The signed arm64 Debug build succeeded. Gate results on the implementation commit were 3,581 tests, zero failures, one skipped. Atlas showed all three actions and confirmed dismissal after a click outside the popover. The installed binary matched the tested build.
- If the next task revisits the dropdown, exercise the three action destinations, a click in another XFinder window, repeated clicks on the status icon, and File Browser disabled. These cases were not covered by the latest live check.
- If the next task revisits provider or power behavior, live stock entitlement, real provider connections, and physical lid-close behavior still need verification. Prior Weather work at `9b1f997` is outside the integrated history. Inspect it only if the next task needs it.

Read [the quickstart](../AGENT_QUICKSTART.md) and the spec for the next task. Use a unique `XF_OUT` for each build and install the reviewed bundle by exact path. Check the running executable path before drawing UI conclusions. Keep old worktrees separate until their commits have been reviewed against the current base.
