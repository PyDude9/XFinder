# V1 — sidebar parts review

Reviewed worker commit `cd3699a` against contract §C, without changing that worker branch. Tilde contact sheets are absent and the installed Tilde app had no visible window in the prior read-only probe; visual matching remains unverified. This is a source review, not live acceptance.

- **High — Live Groups show files as folder rows.** `SidebarLiveGroupsSection.swift:30–31,58–61` renders every PropertyRules.LiveGroup path and calls folder navigation. Metadata selections contain both files and folders; no kind filter exists. Resolve by fetching directory facts off the main actor, discarding missing/files/packages, and distinguishing loading from an empty group.
- **Medium — pager departs from one-dot-per-Space contract.** `SidebarSpacePager.swift:34–35,63–73` switches to a numeric indicator above twelve Spaces. Resolve with a horizontally scrollable dot strip, keeping the active dot in view.
- **Medium — group identity is option-only.** `SidebarLiveGroupsSection.swift:22` identifies a group by option UUID alone, although LiveGroupRef identity is (property, option). Resolve with composite identity.
- Header menu includes activation, create, rename and guarded deletion; name sheet handles deleted/renamed Spaces and blank/duplicate names. Header/pager dimensions and system property tints use shared tokens. No input or app launch was performed.

The fixes and final validation are recorded in the finishing integration report; the worker branch remains unchanged.

## Resolution / validation

All listed source findings were addressed on integration branch `agent/codex-T32-finish`, fix commit `4d6acf4`. Original worker branch is unchanged and clean. Rebuilt the exact worker checkout with build-and-check into an isolated output directory: `** BUILD SUCCEEDED **` (arm64). V1 output: `/tmp/xfinder-t32-v1-build`; V2 output: `/tmp/xfinder-t32-v2-build`. Logs: `/tmp/xfinder-t32-V1-validation.log` and `/tmp/xfinder-t32-V2-validation.log`. Final integrated app build succeeds and all 2819 tests pass; L10n/UI gates pass. These builds establish compilation/resource inclusion, not visual or interaction acceptance. No app was installed/launched and no events were sent to another app.
