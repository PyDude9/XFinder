# Feature master-key ground truth (input for FeatureRegistry) — 2026-10-09

Source: a read-only sweep by a background agent, then **spot-checked by hand**. Rows/claims marked
✔ were re-verified with grep in the working tree; everything else is agent-reported and must be
re-checked at the moment a registry entry is written. Working tree is uncommitted and moving —
line numbers will drift.

## Table (toggleable features only)

`idle`: N = nothing at rest · E = event-driven monitor · T-vis = timer only while visible · T-always = timer while enabled

| Feature | Master key | Reader (file) | Default (reader = view) | Permission | idle |
|:--|:--|:--|:--|:--|:--|
| Dock hover preview | `windowPreview.hoverEnabled` | DockPreviewController | true = true | AX | E |
| ⌘-Tab switcher | `windowPreview.commandTabEnabled` | CommandTabController | false = false | AX + Screen Rec | N |
| Custom Dock preview panel | `windowPreview.customDockEnabled` | DockLayerController | false = false | — | N |
| Snap zones | `snapzones.enabled` + `dragEnabled` + `hotkeysEnabled` | SnapZoneController | true ×3 | AX | E (drag watch, documented global-only) |
| Mouse gestures | `enabled` **inside** blob `mouseGestures.configuration.v1` | GestureController | model default | AX | E (own queue) |
| Menu bar hider | `menubar.hiderEnabled` (+ autoHide*) | MenuBarHiderController | true = true | AX (position) | **T-always when autoHide** |
| Finder keyboard | **none** — OR of 3 sub-keys | FinderKeyboardController | false ×3 | AX | N |
| Clipboard shelf hotkey | `clipboard.globalHotkey` | ClipboardShelfController | true = true | AX | N |
| Clipboard capture | `clipboard.capture*`, `enableOCR`, … | ClipboardManager | true = true | — | **T-always (0.25→1→5 s backoff)** |
| iCloud clipboard sync | `sync.icloudClipboard` | CloudSyncController | false = false | (entitlement missing per its own comment) | E |
| ⌘K palette | `quickSearch.enabled` | QuickSearchPanelController | true = true | **none** (Carbon hotkey) | N |
| Screen-edge notes | `notes.edgeEnabled` | EdgeNotesController | false = false | — | E |
| Khay thả (notch) | `dropTray.notchEnabled` (+ shake/…) | NotchDropController | true = true | — | E + T-vis (1 s while shown) |
| Folder sync | `sync.autoEnabled` | FolderSyncController | false = false | — | E + **T-always (60 s)** |
| Voice typing | `voice.enabled` | VoiceManager / VoiceSettingsKeys | true = true | AX + Mic + Speech | N |
| Flyout rows | `menubar.showBattery/showNetwork` | MenubarController | true = true | — | — |
| Metrics cadence | `menubar.updateInterval` | SystemMonitorManager | 2 = 2 | — | T-vis (retain/release) |
| Launch at login | `general.launchAtLogin` | pass-through to SMAppService | — | — | — |
| Dock icon | `ShowDockIcon` | XFinderApp | true = true | — | — |

### No on/off at all (imperative actions) — must NOT appear as toggles in the hub

Caffeine (`IOPMAssertion`, timer only while counting down) · Folder lock · Remote connect · Quick Share
(server starts lazily on first share; **T-always 60 s sweep while any share exists**) · Finder utils
(one-shot `defaults write`) · Finder actions (10 per-row visibility flags, no master).

→ Registry needs `kind: .toggle | .action`. The hub's "n/N đang bật" counts toggles only.

## Findings (what the table implies)

### A. Honesty / dead controls — FIXED 2026-10-09 (Phase 1, step 1)
- `windowPreview.showHiddenWindows` → **wired.** Single reader `WindowPreviewStore.showsHiddenWindows`
  (+ pure `listsWindow(ofHiddenApp:showHidden:)`); both window listers (`WindowPreviewStore.windowLister`,
  `WindowManager.listWindows`) call it instead of `if isHidden { continue }`. Default `false` = old behaviour.
  **Thumbnails of hidden-app windows are unverified** — SCK may return blank for them; the toggle's own copy
  already warns the app must re-open the window.
- `clipboard.intelligentSuggestions` → **wired** to the shelf's "Gợi ý" tab (`ClipboardIntelligenceEngine.isEnabled`,
  single reader; tab hidden + `suggestionsActive` false when off). **Label corrected:** the engine is a rule-based
  ranker (recency · usage · pinned · app role by bundle ID). It never touched FoundationModels; the card no longer
  says "Apple Intelligence". Strings renamed in the store, dead entries removed.
- `clipboard.linkPreviews` → **removed** (toggle + key + 2 store entries). No reader ever existed, and fetching
  every copied URL would break the local-only promise. `testRemovedLinkPreviewsKeyIsBoundNowhere` pins it.
- New gate `Tests/XFinderLogicTests/FeatureKeyDefaultsTests.swift`: parses the **source** of each view
  (`@AppStorage("k") … = x`) and its ONE Core reader (`object(forKey: "k") as? Bool ?? y`), fails on `x != y`,
  on zero readers (dead key / rotted anchor) and on more than one reader (two copies that can drift). Covers 6 keys.
  Proven red four ways: engine default flipped · hidden rule ignores switch · view default flipped · reader deleted.
- CLAUDE.md Part 3b's *"zero stored-but-unread keys remain"* was false when written; after this fix it is true
  again **and now has a gate** instead of a sentence.

### B. "One key, one control" is violated again (it was "killed" once)
- ✔ `windowPreview.hoverEnabled` is bound in **Dashboard**, **QuickControls**, **WindowDetail** (`@AppStorage`) and the **flyout**
  (raw `UserDefaults` get/set, `MenubarController.swift:332-334`). Same for `commandTabEnabled` (QuickControls, WindowDetail, flyout).
  QuickControls even carries a comment that its default "MUST match" the controller's — a hand-maintained invariant.
- `notes.edgeEnabled` (3 files), `clipboard.touchIDLock` (3 readers), `clipboard.autoPasteAfterSelection` (2 readers): lower severity, same drift risk.
- Defaults currently agree everywhere (no Part 0 #5 violation found) — but only by luck; the registry should own the default.

### C. The re-arm list is incomplete
- ✔ The `didBecomeActive` block re-arms: Permission, DockPreview, CommandTab, SnapZone, FinderKeyboard, ClipboardShelf,
  QuickSearch (needs no permission — harmless), Voice, Gestures.
- ✔ `MenuBarHiderController.applySettings()` is called **once, at launch** (`XFinderApp.swift:68`). The agent reports its engine reads
  AX (`AccessibilityMenuBarInventory`); if so, a mid-session grant is not picked up. Confirm AX dependence, then add — or, better, make the registry do it.

### D. Features with no single master key
Finder keyboard (OR of three) · Snap zones (master + two sub-gates) · Mouse gestures (flag lives inside a Codable blob —
the registry needs a per-feature `isEnabled` accessor, not just a key name) · Finder actions · Quick Share (enabled ≡ "has shares").

### E. Idle-cost badges must be honest, and four features are not "nothing at rest"
Clipboard (5 s floor timer), Menu bar hider (auto-hide timer), Folder sync (60 s), Quick Share (60 s while sharing),
Khay thả (1 s while shown). These are small and already measured as ~0 % in aggregate — but a badge that said
"Nothing at rest" for them would be a lie. Show what it is.

### F. Documentation contradiction
CLAUDE.md says in one place the hider is *off* (`applySettings = remove`), and in a later section describes the active
native engine. The code (`if hiderEnabled { install() } else { remove() }`) matches the later section. Reconcile the
earlier text when the next CLAUDE.md edit happens.

### G. SMART in the flyout — FIXED 2026-10-09, and it uncovered language leak #6
- Flyout said `SMART → Không khả dụng`; the Ổ đĩa page already read it via `diskutil`. Now both use `SMARTStatus`
  (pure parse + raw→**store key** mapping) and the flyout fetches once per popover appearance (`.task`), mount `/`.
- `DiskManager.smartLabel` returned Vietnamese **display strings from Core**, rendered by a bare `Text(...)`, keys absent
  from the store → English UI showed Vietnamese on the SMART card. Fixed + gated (`SMARTStatusTests`, 3 mutations red).
- Rendered, installed, English: `Boot drive SMART → Healthy` (AX probe). 306 tests, 0 failures.
- Review workflow (3 lenses + cross-lens refuters) confirmed ONE defect, mine: `.task` did not clear `smartRaw` before refetch,
  so reopening the popover showed the previous answer while diskutil ran (popover's hosting controller is app-lifetime, @State
  persists). Fixed in both the flyout and the pre-existing identical ordering in `StorageDetailView.task(id:)`.
- Same-shape hunt done: 143 Vietnamese literals returned from `Core/` → **142 are store keys** (gesture vocabulary, gated);
  the only non-store one is `L10n.swift` `"Tiếng Việt"` (endonym, identical in both languages by design). SMART was the sole leak.

