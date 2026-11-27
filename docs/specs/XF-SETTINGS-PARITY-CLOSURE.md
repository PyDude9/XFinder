# XF Settings parity closure

## Goal

Make every provider-backed Dynamic Island page configurable from both the inline Notch Settings surface and Full Settings. Fix dead Settings navigation and align the affected Settings typography with `XFinderTokens`.

## Failure cases to cover

- A provider-backed tab is enabled but has no key: its Settings action must open the matching form.
- A provider-backed tab is disabled in Features: its Settings action must open Features.
- Stocks, Revenue, and Website Analytics are configured: opening their Settings must retain the saved account and never expose stored secrets.
- The inline Settings panel is narrow: each provider form remains reachable and scrollable.
- The Settings panel closes or switches sections: temporary API key input is cleared by the owning form.
- A Settings navigation target is absent: the control must not silently navigate to an unrelated page.
- Audio Settings is opened: it must not route to Live Activities.
- Provider setup is unavailable: no fabricated quote, revenue, or analytics data is shown.

## Scope

- Add inline configuration sections for Stocks, Revenue, and Website Analytics.
- Route each unconfigured provider tab to its matching settings section or Full Settings page.
- Route Gallery's unavailable provider tiles to matching Settings destinations.
- Correct the Audio Settings destination.
- Replace ad hoc small typography in the affected Settings forms and rows with shared tokens.
- Add regression coverage for provider destinations and navigation contracts.

## Out of scope

- Adding permissions that no current feature requests.
- Adding duplicate FeatureCatalog switches for features with their own explicit opt-in controls.
- Deleting legacy File Browser sources or worktrees.
- Claiming live provider access without real credentials and user grants.

## Acceptance

- Stocks, Revenue, and Website Analytics each expose the correct configuration form from inline Settings and Full Settings.
- Gallery and tab Settings actions resolve to a real destination for every provider state.
- Audio Settings no longer navigates to Live Activities.
- Affected Settings text uses the shared typography scale and stays readable at the supported panel width.
- `sh scripts/gate-all.sh` ends with `GATE: green`.
- Clean checkout build succeeds after the required source closure is committed.
