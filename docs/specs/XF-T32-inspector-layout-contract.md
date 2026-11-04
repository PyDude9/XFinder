# XF-T32 — responsive Inspector layout, owner continuation 2026-10-28

Problem previously observed in the installed W5 app: a 720-point window with sidebar and two panes leaves each pane narrower than Inspector's fixed 280 points; the file listing disappears while Inspector fills the pane. Source still has the same unconditional fixed width. Current CUA screen capture failed, so that is not new live evidence.

Keep both listing and Inspector reachable without changing the global preview preference. At widths supporting 280-point listing + divider + 280-point Inspector, retain the existing side-by-side layout. Below that, stack Inspector below the listing. The bottom Inspector uses at most 40% of the available content height, capped at 280 points; the listing keeps the remainder. Adapt per pane as window/split geometry changes. Inspector content is flexible-width only in the bottom layout. Keep existing preview loading/cancellation and file actions. No new settings, strings, watchers, or filesystem actions.

Failure cases: single-pane wide view unchanged; two/four narrow panes; empty or selected-file Inspector; very short pane; resizing back and forth; Preview OFF gives all content area to listing; Learn virtual page remains unchanged; no negative/nonfinite frame sizes. Rapid layout changes must not retain obsolete preview tasks beyond the existing onDisappear cancellation.

Files: PaneView.swift; PreviewPaneView.swift; InspectorPreviewRules.swift (pure layout rules in existing compiled source); InspectorPreviewRulesTests.swift. No new app files/project entries.

Acceptance: layout boundary/geometry invariants and mutation RED then restored GREEN; targeted preview tests; full detached gate in private XF_OUT; install using existing script and compare hashes; live narrow/wide, Preview OFF/ON and file selection where GUI access permits. Report build/tests/mutation/live separately. No push.
