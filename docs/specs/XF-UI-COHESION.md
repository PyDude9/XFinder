# XF-UI-COHESION

Remove the standalone Anti-sleep page. Notch System owns session duration, stop, and lid wake. Keep the unique display-awake preference under Features & Permissions. Redirect legacy Settings links to Features & Permissions and preserve the right-click emergency access when Notch System is hidden or disabled.

Use shared SwiftUI tokens for the menu bar popover and Settings shell. Use compact sidebar rows, clearer title contrast, and an aligned segmented picker. Keep native selection, accessibility, appearance and minimum window sizing.

Scope: sidebar destination and search, app routing, system controls, Settings chrome, and the menu bar view/controller. Avoid the legacy tab source files under review by Antigravity.

Check the old link, missing battery, Notch disabled or hidden, active Caffeine after the preference changes, narrow layouts, English and Vietnamese labels, and light and dark appearance. Preserve stored preferences. Build and run the existing gate. Record the commit and how to revert it.
