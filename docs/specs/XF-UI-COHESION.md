# XF-UI-COHESION

Remove the standalone Anti-sleep page. Notch System owns session duration, stop, and lid wake. Keep the unique display-awake preference under Features & Permissions. Redirect legacy Settings links to Features & Permissions and preserve the right-click emergency access when Notch System is hidden or disabled.

Use shared SwiftUI tokens for the menu bar popover and Settings shell. Use compact sidebar rows, clearer title contrast, and an aligned segmented picker. Keep native selection, accessibility, appearance and minimum window sizing.

Scope: sidebar destination and search, app routing, system controls, Settings chrome, and the menu bar view/controller. Avoid the legacy tab source files under review by Antigravity.

Check the old link, missing battery, Notch disabled or hidden, active Caffeine after the preference changes, narrow layouts, English and Vietnamese labels, and light and dark appearance. Preserve stored preferences. Build and run the existing gate. Record the commit and how to revert it.

## Changes and rollback

| Commit | Change |
|---|---|
| `55970cb` | Removed the standalone Anti-sleep page and search entry. Old routes now resolve to Features & Permissions, where the display-awake preference lives. The Notch runs Caffeine sessions. The native menu keeps its fallback when Notch System is unavailable by configuration. |
| `8ec611e` | Matched the dropdown rows to Settings cards, reduced sidebar row density, aligned segmented controls to the content, and improved page title contrast. |
| `f8cdf5e` | Removed the repeated Overview Caffeine status, matched the defaults test to the direct Notch binding, and corrected the English uptime suffix. |

Revert the visual changes alone with `git revert 8ec611e`. To restore the previous Caffeine UI, revert `f8cdf5e` then `55970cb`. Rebuild after reverting. No preference keys or defaults were changed.

Full Settings continues to own setup pages such as Stocks, Analytics and Revenue. The matching Notch tabs show data and give users a quick way to reach those settings. The Antigravity worktree owns the separate dead-code and performance audit.

## Live checks

Signed arm64 Debug build and full gate passed with 3,582 tests, one skipped and zero failures. Localization and UI checks passed.

Atlas exercised the signed build in the helper account at 900 pt window width, in Vietnamese and light appearance. The compact popover showed three rows, its Settings row opened Overview, the accessibility tree returned no Anti-sleep item on that screen, and System Monitor showed its tabs aligned to the metrics below. Dark appearance, physical lid behavior and the installed owner profile were not exercised in this pass.
