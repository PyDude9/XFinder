# XF-MFGAP-01 — Storage charts and chart options

## Goal

Extend the existing read-only, user-picked-folder Storage Analyzer with a retained hierarchy and two selectable visualizations: treemap and sunburst. Persist the selected chart style and chart/inspector fraction on the existing Storage page. A chart option must always control a real chart; do not add placeholder settings. Keep logical-byte wording and current read-only safety contract.

## Baseline

- Branch task baseline: `main` `9788415`; current implementation is on `agent/codex-XF-SETTINGS`.
- Existing contract: `docs/specs/XF-T35-storage-analyzer-v01.md`.
- Current owners: `XFinder/Views/Detail/StorageDetailView.swift`, `XFinder/Core/Storage/StorageScanEngine.swift`, `XFinder/Core/Storage/StorageScanRules.swift`.
- Existing storage settings in the MFinder prompt are `storage.chartStyle` (`treemap` or `sunburst`) and `storage.chartFraction`; there are no matching XFinder keys yet.

## User flow

1. User selects a folder and scans using the existing flow.
2. Once there is a complete/partial tree result, a chart-style selector chooses Treemap or Sunburst. Changing style re-renders the cached tree without rescanning.
3. A splitter or equivalent accessible control adjusts the chart/inspector fraction; keyboard users can change the same value in increments.
4. Selecting a chart node highlights it and updates the largest-items inspector; activating a folder node scopes the chart to that subtree with a visible “Back to scan root” action.
5. Empty, cancelled, and failed results do not show a selectable chart. Existing scan results and volume metrics retain their current behavior.

## Requirements

- Preserve a bounded hierarchy using logical file sizes; do not claim physical allocation, reclaimable space, or unique APFS blocks.
- Keep traversal off the main actor and cancellable under the existing scan contract. Switching chart style or adjusting the splitter never starts a scan.
- Ignore symlinks; do not trigger cloud downloads. Use deterministic child ordering for stable chart layout.
- Handle zero-size files, empty directories, a single child, deep trees, inaccessible children, saturated/overflow totals, and tiny chart rectangles without invalid geometry or NaN values.
- Use Canvas/CoreGraphics/SwiftUI drawing. Respect label legibility: suppress labels when the available geometry is too small rather than clipping or overlapping them.
- Expose a selection/inspector relationship for keyboard and VoiceOver users; charts cannot be the only route to inspect a file.
- Persist exactly one style key and one fraction key. Add defaults and reader values together; add the key/default test. Keep the existing defaults unchanged elsewhere.
- Every new user-facing string goes through the add-only localization workflow.
- No Trash action, permanent delete, full-disk scan, background indexing, new dependency, bookmark persistence, or APFS physical-space estimate in this task.

## Failure cases

| Case | Required behavior |
|---|---|
| Scan cancelled or fails | Keep the terminal state truthful; do not show a completed chart or allow stale chart selection. |
| Empty folder / all files skipped | Show the existing empty/partial result; chart controls are disabled with an explanation. |
| Folder changes during scan | Preserve the current skip/partial semantics; never turn a partial result into a complete tree. |
| Zero total bytes | Render a stable empty/zero state; never divide by zero. |
| Integer overflow | Use checked/saturating totals and show the existing partial/error semantics; never wrap into a smaller size. |
| Deep or broad hierarchy | Keep UI responsive and bound rendering work/labels; do not recurse without a depth/stack safety strategy. |
| Tiny window or narrow inspector | Clamp the fraction to a safe minimum for both panes; allow keyboard adjustment and restore usable layout. |
| Stored style/fraction is invalid | Fall back to documented defaults and repair the stored value without crashing. |
| View closes during scan | Existing cancellation behavior applies; no chart task may outlive its owner and publish stale state. |
| Selected folder disappears | Keep the prior result marked stale/partial or show failure; do not silently rescan. |

## Files allowed

- `XFinder/Views/Detail/StorageDetailView.swift`
- `XFinder/Core/Storage/StorageScanEngine.swift`, `StorageScanRules.swift`, new `StorageTreeRules.swift` (pure) and one chart layout rules file under `XFinder/Core/Storage/`
- `scripts/mutation-check-storage.sh` (add mutants for the new pure rules)
- Focused storage rules tests and their `Tests/XFinderLogicTests/` symlink if pure rules are added
- `XFinder/Resources/L10n.strings.json` via the add-only localization script
- `XFinder.xcodeproj/project.pbxproj` only for required source registration
- `Tests/XFinderLogicTests/FeatureKeyDefaultsTests.swift` only for new key/default parity

**Boss decision 2026-11-07 (resolves Q-MFGAP-11 — hierarchy retention IS in scope):** the scan engine keeps a bounded tree, built
during the same single walk (no second pass, no rescan on style change):

- **Directory nodes** for every visited directory: name, relative path, parent, logical bytes of the subtree (saturating), file count,
  skipped flag. Children sorted by size desc, then path asc.
- **File leaves**: per directory only its **20 largest files**; the rest become one aggregate leaf "N tệp khác" (count + bytes).
- **Global cap 100 000 nodes.** When reached, deeper directories are folded into their nearest kept ancestor as an aggregate leaf
  and the result says the chart is simplified (not "partial" — totals stay exact). Measure resident memory on a 100 000-entry tree
  and report it.
- Top-50 list, totals and status semantics from XF-T35 stay unchanged and keep coming from `StorageScanAccumulator`.
- Tree building/aggregation/folding rules live in a pure `StorageTreeRules.swift` (symlinked tests) with a mutation harness entry
  in `scripts/mutation-check-storage.sh`.

Still stop and report if anything outside "Files allowed" must change.

## Acceptance

1. Treemap and sunburst both show the same scan tree and sizes; changing style performs no filesystem I/O.
2. Folder drill-in, return-to-root, chart selection, and inspector selection stay synchronized.
3. `storage.chartStyle` and `storage.chartFraction` survive view/app recreation, reject invalid values safely, and each has one visible control.
4. Empty, partial, cancelled, failed, zero-byte, overflow, deep-tree and tiny-pane cases remain truthful and stable.
5. Existing read-only behavior, logical-byte labels, top-50 list, scan cancellation, and volume capacity/I/O/SMART sections remain intact.
6. Run focused storage tests, `plutil -lint XFinder.xcodeproj/project.pbxproj` if changed, and `sh scripts/gate-all.sh`; report build/tests/gate/live separately. Do not install or launch the app from this Builder worktree.

## Teaching checkpoint

Explain in the task Run how proportional chart geometry maps a child's byte size to an angle or rectangle area, why a cached hierarchy lets style changes avoid disk reads, and why logical bytes are not APFS physical usage.
