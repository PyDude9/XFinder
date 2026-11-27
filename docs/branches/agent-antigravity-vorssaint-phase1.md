# Branch note: `agent/antigravity-vorssaint-phase1`

## Purpose

Integration branch for the active Notch, Full Settings, Stocks, Revenue,
Website Analytics, AI Usage, timers, system monitor, and adjacent feature work.
Keep the branch as the review boundary; do not push it.

Integration commit: `4c35b15` (`XF-CLOSURE: Integrate active Notch and Settings work`).

## Integration work

- Reconcile Notch destinations with editable Settings destinations.
- Add inline Settings sections for Stocks, Revenue, and Website Analytics.
- Keep provider configuration reachable from Notch before and after setup.
- Route Audio settings to System settings.
- Align inline settings typography and avoid nested analytics scrolling.
- Preserve feature-level specs, tests, and localization gate changes with sources.

## Verification

- Run `sh scripts/gate-all.sh` from this checkout before each integration commit.
- Record build, test, localization, and UI-token results in `docs/AGENT_WORKLOG.md`.
- Build outputs belong under a unique `/tmp/` directory.

## Still requires live verification

- OAuth and provider credentials against real accounts.
- Menu-bar icon presence and placement in the installed app.
- Physical lid-close wake behavior and live stock quote access.
- Settings and Notch interaction in a running signed build.

## Guardrails

- Stage reviewed paths explicitly; never stage owner assets wholesale.
- Keep `XFinder/Info.plist` changes outside this integration commit.
- Do not push, merge, or amend commits on this branch.
