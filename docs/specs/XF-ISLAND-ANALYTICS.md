# XF-Island Analytics — website traffic dashboard

## Goal

Implement the website Analytics destination shown in PeakPad references #11, #24 and #27, using XFinder's own visual language. The page is separate from `Core/Diagnostics/AnalyticsCenter.swift`, which sends XFinder's anonymous product telemetry. Never reuse that type or its event data as website analytics.

The dashboard supports two independently configured, read-only sources: DataFast and Google Analytics 4 (GA4). It shows the selected source, its connection state, a 7-day or 30-day range, realtime visitors when supported, headline visitors/pageviews/bounce/average session duration, a time series, top pages and referrers. Each source retains its own property/site and credentials; never combine numbers across providers.

## Provider contracts

### DataFast

- Read-only Website API using a user-entered `df_` website API key. Do not request or store `dft_` account-management tokens.
- Send `Authorization: Bearer …` only to `https://datafa.st/api/v1/` endpoints.
- Use the documented analytics overview, timeseries, realtime, pages and referrers APIs. Check the live DataFast docs before finalizing paths, query parameters, and field decoding.
- Never expose the key in logs, errors, URLs, analytics events, previews, or persisted preferences. Store it in Keychain. Allow explicit disconnect/delete.
- Unsupported metrics must display “—”/localized unavailable, never zero. Realtime state is not inferred from pageviews.

### Google Analytics 4

- Read-only Google Analytics Data API v1beta; OAuth scope `https://www.googleapis.com/auth/analytics.readonly` only.
- Configure a GA4 property ID and OAuth 2.0 client ID. Use native-app authorization with PKCE and the supported redirect/callback mechanism. Do not embed a client secret or service-account private key. Store access and refresh tokens in Keychain. Include explicit disconnect/revoke handling where supported.
- Use `runReport` and `runRealtimeReport` for the dashboard metrics. Check metric/dimension names against current Google documentation and validate response headers before decoding positional rows.
- If OAuth cannot be completed because the app lacks a registered client ID or callback scheme, deliver a clear unconfigured state and a precise integration note; do not ship a fake connection or silently use sample data.

## UI and behavior

- Match the screenshot hierarchy: page title; provider selector (`DataFast`, `Google Analytics`); realtime indicator; 7d/30d selector; four KPI values; top pages and referrers. Fit the Dynamic Island width using the established responsive layout; narrow mode may stack sections but must retain all values and controls through scrolling.
- The currently selected provider remains selected across app launches. Selecting a provider without credentials opens its configure state. Each source has its own site/property configuration and status.
- Loading, no data, stale cached data, rate limit/quota, offline, revoked credential, malformed response and server errors have distinct states. Show last successful update time for cached data. A failed refresh never replaces good cache with zeros or partial mixed-source data.
- Refresh only on initial page entry and explicit refresh. Cancel/fence in-flight work when leaving the page or changing provider/range. No polling timers.
- Settings tab enablement is integrated by the coordinator after module delivery. The module must be independently renderable and accept an injected model/provider for fixture tests.
- No demo/sample fixtures are shown in production UI. Fixtures belong only in tests/previews with explicit names.

## Failure cases to implement

1. Missing credentials/property: actionable unconfigured state; no network request.
2. User cancels OAuth: remain disconnected; no misleading success state.
3. Invalid/expired credentials, revoked consent, HTTP 401/403: preserve cached data with stale marker and offer reconnect.
4. Rate limit/quota or server unavailable: preserve cache, report source and retry state.
5. Offline/timeout/cancellation/provider switch: no stale request may overwrite current provider/range.
6. Empty report: explicit no-data state; do not synthesize zeros or sample values.
7. Missing metric/header, changed schema, malformed JSON, non-finite numeric value: reject the affected response as an error.
8. Timezone/date boundary and 7d/30d change: request and chart buckets match the provider property's timezone/date semantics.
9. Credential deletion/disconnect: clear Keychain entries and sensitive in-memory state.
10. Large/malicious response: bound response bytes and rows; reject oversized payloads.
11. App exits during refresh/OAuth: no retained server listener or background polling.
12. Tab disabled/another page selected: cancel requests; preserve user's credentials/configuration.

## Implementation boundaries

The implementer may add dedicated files under `XFinder/Core/WebsiteAnalytics/`, one page view under `XFinder/Views/`, focused logic tests, localization entries, and the four required Xcode project entries for each source file. Do not change shared destination catalog, surface router, Settings catalog, or existing `AnalyticsCenter` files. Report the minimal integration points needed for the coordinator to add a toggleable destination. Do not alter existing defaults or existing telemetry behavior.

Inspect neighboring Stocks, Revenue, Weather and notch-page code before coding. Follow Swift 6 strict concurrency, URLSession dependency injection, existing Keychain conventions, localized Vietnamese keys, and project test conventions. Write the failure cases above into the report before implementation.

## Acceptance evidence

- Pure decoding/rules tests cover source-specific metrics, ranges, empty responses, malformed schemas, missing metrics, cancellation fencing and stale-cache retention.
- Provider tests use injected URLSession transport and local fixtures; no live account or real credential is needed.
- Credential tests use an injected Keychain abstraction; no developer's Keychain is touched.
- Focused tests pass. Build the module in the app target if shared routing can be omitted; clearly enumerate remaining router/catalog integration.
- `plutil -lint XFinder.xcodeproj/project.pbxproj`, `git diff --check`, and localization gates pass for edited entries.
- No install, launch, GUI interaction, commit, push, stage-all, or edits outside allowed paths.

## Data/API evidence captured at planning time

- DataFast docs: https://datafa.st/docs/api, https://datafa.st/docs/api/authentication, https://datafa.st/docs/api/website/analytics/overview
- Google Data API docs: https://developers.google.com/analytics/devguides/reporting/data/v1/rest, https://developers.google.com/analytics/devguides/reporting/data/v1/rest/v1beta/properties/runReport
