# Mouse Gestures — verification record

Measured **2026-09-21**, **2026-09-22** and **2026-09-23**, macOS **27.0 (26A428)**. This is a
development verification record, not a claim that a release or every mouse/app combination was
tested.

---

## Round 8 (2026-09-23) — "Global recognises the gesture but does nothing"

### The report

> "App nhận chuột tốt, nhưng các thao tác tôi gán như Hold Scroll Button và kéo lên là
> Mission Control hoặc Hold Scroll Button + kéo sang phải là next space screen... Đều ko
> hoạt động, chỉ là xuất hiện và nhận dạng cho có chứ không làm việc ở Profile Global Default."

### Root cause — two wrong mechanisms in sequence, not one

Round 7 proved the Global preset's `⌃↑`/`⌃↓` were bound to nothing. Its *replacement* was also
wrong, and this round retired it:

1. **`NX_KEYTYPE_MISSION_CONTROL` does not exist.** `SystemKeySender` posted `NSEvent`
   `.systemDefined` keytype **32**. `ev_keymap.h` defines keytypes only up to
   `NX_KEYTYPE_MENU = 25`; 32 is invented, so the event was undefined and no part of the system
   listened. The code comment "id 32 → NX_KEYTYPE_MISSION_CONTROL" was folklore.
2. **Mission Control / App Exposé / Space are software *symbolic hotkeys*.** The correct
   mechanism is not a keytype at all: read the chord the user assigned in
   `com.apple.symbolichotkeys` and post that exact chord.

Measured live on this Mac:

| id | action | vk | mods |
|--:|:--|--:|--:|
| 32 | Mission Control | 126 ↑ | 8650752 (`0x840000` = control \| fn) |
| 33 | App Exposé | 125 ↓ | 8650752 |
| 34 | Show Desktop | 126 ↑ | 8781824 (shift \| control \| fn) |
| 79/80 | prev Space / alt | 123 ← | 8650752 / 8781824 |
| 81/82 | next Space / alt | 124 → | 8650752 / 8781824 |

3. **The `fn` bit is load-bearing.** `0x840000` is `control | maskSecondaryFn`; masking it off
   posts a chord the system does not match. `GestureShortcut.label` drops the bit for *display*
   (so rows read `⌃↑`, as System Settings shows) but posts the full mask.

### The fix

1. **`SystemKeySender` retired** — file, test symlink, its test file and all four pbxproj entries.
2. **`SpaceBinding`** gained `appExpose = 33`, the `79→80` / `81→82` alternates, and a new pure
   **`GestureSystemBindings`** (`[GestureSystemAction: GestureShortcut]`, plus `.empty`) passed
   explicitly into *both* the resolver and the engine — so a test can hand it `.empty` and see the
   honest "no key on this Mac" row instead of an invented key.
3. **`GestureSystemAction`** gained `.previousSpace` / `.nextSpace` + `unboundCaptionKey`.
   The Global preset is now up/down/left/right → four `.systemAction` cases, no constants.
4. **One resolver**: `GestureMap.row(..., systemBindings:)` returns `systemShortcut` +
   `isUnboundSystemAction`; the engine posts exactly that. Unresolvable ⇒ posts **nothing** and
   logs `.systemActionUnbound`.
5. **`systemAction(of:)`** — an override that picked a system action used to render as
   "unassigned" because the resolver built the entry with both `shortcut` and `systemAction` nil.
6. **Trigger migration 2 → 3**, once, only when `overrides.isEmpty`.
7. **Page**: a "system shortcuts on this Mac" row that reads the live bindings and links to
   Keyboard → Shortcuts; an unbound arm renders orange with a tooltip and a fix button; the
   "shortcut sent" row no longer appears for an `.unassigned` row (measured on Zed up/down, the
   log used to say "Shortcut sent — Raw horizontal scroll" for a row that sends nothing).

### Verified, and not — stated separately

| Claim | Status |
|:--|:--|
| Debug build, `lipo -archs` = arm64, files named in the compile log | ✅ incl. `SpaceBinding.swift` |
| `cd Tests && swift test` | ✅ **162 tests, 0 failures** |
| `scripts/verify-gesture-ui.sh` §1–§7 | ✅ 0 / 0 / 0 / 162 / names / arm64 / `active=1 trusted=1` |
| `verify-l10n-runtime.py` against the **installed** bundle store | ✅ TOTAL 0 leaks |
| Runtime harness, the new system-action path | ✅ *the machine's own chord posted, fn+control mask intact, unbound posts nothing* |
| Event tap opened on the installed app | ✅ `lastTapState {active: 1, trusted: 1}` |
| Rendered page: four arms read `⌃↑ ⌃↓ ⌃← ⌃→`; system row matches the plist | ✅ read via AX tree (`probe-ax-dump.swift`) |
| Engine log: a real gesture → `Next Space`, recorded as **sent** | ✅ user-performed |
| **Mission Control opens / the Space actually changes** | ❌ **no human has watched the screen** |

The last line must not be reported as working. The evidence is that the engine posted the chord
*this machine itself declares*, the tap is live, and the AX tree shows that key on the UI. The
final step — does macOS actually switch — needs eyes. `probe-screen-diff.swift` can measure it
but **changes Spaces for real**, so it only runs with the user's consent.

### A language leak found by reading the rendered page, not by grepping

`probe-ax-dump.swift` found:

* **Six sidebar headings** `CHUNG · CỬA SỔ · FINDER & TÌM KIẾM · CÔNG CỤ · KẾT NỐI · TIỆN ÍCH`
  rendering Vietnamese on the English UI. The call site was correct (`L10n.t(group.header)`) but
  the key was **absent from the store**, so `t()` fell back to the Vietnamese literal.
* **Five model strings passed through a variable**: `App Exposé`, `Hiện màn hình nền`,
  `Space trước`, `Space kế tiếp`, `Chụp màn hình`.

Three pre-existing gates were blind to all of these, because all three only look at
`L10n.t("…")` literals. Closed by: registering the six headings +
`scripts/check-sidebar-groups-l10n.py` (which parses the `groups` declaration and **fails if it
finds fewer than 4 headers** — proven by deleting `CỬA SỔ` → exit 1), and walking
`GestureActionKind.allCases` + `GestureSystemAction.allCases` inside `L10nTests` (which caught
`Chụp màn hình` on its first run).

**New rule: a string that reaches the screen through `L10n.t(variable)` is protected by no
pre-existing gate.** To be sure, either enumerate the model's vocabulary in a test or parse the
declaration itself.

### New traps

* **The runtime harness read production defaults.** `MouseGesturesProbe.swift` did not set
  `trigger`, so when the production default moved 2 → 3 it failed at its first precondition in a
  way that looked like an engine bug. It now pins the trigger explicitly.
* **The harness had rotted against the preset.** It asserted the browser tilt was keycode 17
  while the preset table had become `⌃⇥` (48). Changed to a **resolver-equivalence** assertion
  (`posts(resolved(...))`) so it cannot rot again.
* **`plistlib` and `defaults` differ on flush timing.** Reading the `.plist` with `plistlib`
  immediately after the app writes returns the **stale** value (cfprefsd has not flushed) — which
  nearly produced a false "the migration did not run" conclusion. `defaults export
  com.xfinder.app -` reads through cfprefsd and sees the current value. Cross-check the two
  before concluding.
* **The mutation script hung instead of failing, and left the mutated source on disk.**
  `mutation-check-gesture-labels.sh` was killed by the tool's timeout in the middle of mutation
  M3, so `up: .convention(.missionControl, GestureShortcut(key: GestureKeyCode.upArrow, …))` —
  *exactly the bug the mutation injects* — stayed in `GestureModel.swift` and went into the
  build. **Root cause of the hang:** `MouseGestureTests.swift:1161` used
  `liveBindings.shortcut(for: row.entry.systemAction!)`. M3 is *designed* to make the Global arm
  stop being a system action, so `systemAction` becomes nil → the test **traps** instead of
  failing → xctest never returns (crash reporting spins, `MallocStackLoggingDT` is loaded).
  Diagnosed with `ps -eo pid,stat,command` (xctest in state **`R`** — spinning, not deadlocked)
  and `sample <pid> 3`, which named the exact test and line. Fixed to
  `guard let system = … else { XCTFail(…); continue }`. **Rule: in a test a mutation is
  *designed* to redden, never force-unwrap the very value the mutation removes.** Note the
  second symptom: `mutation-check-gesture-ui.sh` counts `error: -[XFinderLogicTests` lines, and
  a trap emits none — so a trap also reads as **green** there.
* **Do not let the tool's timeout kill a mutation script.** Run
  `nohup sh scripts/mutation-check-*.sh > /tmp/log 2>&1 &` and poll the log. Killing one
  mid-run strands both the mutation *and* orphaned `xctest` processes
  (`pkill -9 -f XFinderLogicTests.xctest`). A silently killed gate reads exactly like a green one.
  After the fix, run in the background: labels **5/5 RED**, ui **7/7 RED**, l10n **6/6 RED**,
  every file restored byte-identical, post-restore suite **162 tests, 0 failures**.

---

## Round 7 (2026-09-22) — "gestures are recognised but do nothing"

### The report

> "App nhận chuột tốt, nhưng các thao tác tôi gán như Hold Scroll Button và kéo lên là
> Mission Control hoặc Hold Scroll Button + kéo sang phải là next space screen... Đều ko
> hoạt động, chỉ là xuất hiện và nhận dạng cho có chứ không làm việc ở Profile Global
> Default."

### Root cause — measured, and it was the **preset**, not the engine

The Global profile sent `⌃↑` / `⌃↓` for Mission Control / App Exposé and `⌃←` / `⌃→` for
previous/next Space. **Those keys are bound to nothing on this machine.** Four probes:

| Probe | Result |
|:--|:--|
| `defaults export com.apple.symbolichotkeys -` | ids 79–82 ("Move left/right a space") are present with `enabled = 1` and **no `value` block** — the switch is on with no key assigned |
| same, id 32 (Mission Control) | `vk = 232`, `mods = 0` — keycode 232 is an NX **system-defined** key; there is no `CGKeyCode` 232, so no `CGEvent(keyboardEventSource:)` can express it |
| `/System/Library/User Template/English.lproj/…/com.apple.symbolichotkeys.plist` (factory) | contains **no** ids 32/34/79–82 at all — macOS 27 ships no arrow-key default for any of them |
| `docs/probes/probe-post-shortcut.swift` + `probe-observe-shortcut.swift` | the engine's own synthetic `⌃→` was observed arriving intact: `vk=124`, `flags=537133056`, `mods=[⌃]`, down **and** up, 4 events from 2 posts — well formed, and with no listener |

So the dispatch path was never broken. `GestureMap.systemKeystroke` named four actions it
could not deliver — the failure the Honesty Rule exists to prevent.

### The fix

1. **`GestureAction.systemAction`** (new case) + `SystemKeySender`, posting Mission
   Control / App Exposé / Show Desktop through `NSEvent.otherEvent(with: .systemDefined …)`
   — the same mechanism `SystemControls.adjustBrightness` already ships. `SystemKeySender`
   is split with `#if canImport(AppKit)` so the `data1` arithmetic is unit-testable in the
   Foundation-only test package.
2. **`systemKeystroke` returns `nil`** for those three intents rather than a fake key, and
   `GestureMapEntry.systemAction` is mutually exclusive with `shortcut` by construction.
3. **Global re-derived**: up → Mission Control, down → App Exposé (both system events),
   left/right → `⌘[` / `⌘]` (history — a real convention with **no system prerequisite**).
   Spaces is deliberately **absent** from the default: it has no event-level API, so
   shipping it would repeat the bug. It stays in the picker.
4. **`SpaceBinding`** reads the user's own symbolic hotkeys so the page can say whether
   `⌃←`/`⌃→` are bound instead of assuming. It parses `enabled` from an **integer** — the
   OS writes `1`/`0`, which does **not** bridge to `Bool`, so `as? Bool` reported every
   switched-off shortcut as enabled.
5. **UI captions**: `ResolvedGestureRow.caption` names the mechanism for system actions.
   Before, `shortcut?.label ?? ""` rendered them as an **empty** caption, which reads as
   "unassigned".

### What is verified, and what is not — stated separately

| Claim | Status |
|:--|:--|
| Build succeeds, arm64, new files in the compile log **by name** | ✅ `SystemKeySender.swift`, `SpaceBinding.swift` |
| 164 unit tests pass (was 143) | ✅ |
| `⌘[` / `⌘]` dispatch reaches the app and **changes the page** | ✅ measured in Safari: window title went `Binance Spot` → `Crypto Exchange` → `Trade ETHFI/USDT` |
| The engine's synthetic shortcut is well-formed and reaches HID | ✅ observed via a second `.listenOnly` tap |
| `⌃←`/`⌃→` do nothing here | ✅ and the reason is in the table above |
| Two new tests can fail (mutation-proven) | ✅ `data1` shift layout (3 failures); Global→Space keys (8 failures) |
| **Mission Control opens when the system key is posted** | ❌ **NOT VERIFIED** — see below |

### Why Mission Control is unverified, and why that is recorded as a failure

`docs/probes/probe-mission-control-detect.swift` tried to detect it from the window list.
That detector was **wrong**, and getting it wrong twice is the instructive part:

1. First it compared a `kCGWindowBounds` width (**points**, 1728) against
   `CGDisplayPixelsWide` (**pixels**, 3456), so it reported "not open" for a Mission
   Control that was visible. A broken probe reading as a negative result.
2. After correcting that, it matched *any* full-width Dock window at a layer above 10 —
   and **macOS 27 keeps exactly one such window permanently** (measured: `owner=Dock
   layer=20 1728x1117 alpha=1`, its id survives `killall -9 Dock`). So every "MC OPEN"
   reading in this round, including one that briefly looked like a success, was measuring
   the Dock's normal surface.

Final state: no posting variant (`.cgSessionEventTap`, `.cghidEventTap`,
`.cgAnnotatedSessionEventTap`) and no sampling rate (down to 25 ms) changed the Dock's
window set. Relevant context: `com.apple.dock` has `showMissionControlGestureEnabled = 0`,
`showAppExposeGestureEnabled = 0` and `expose-animation-duration = 0` — the gesture
triggers are off and the animation is instant, so a surface may never be observable from
the window list at all.

**Honest conclusion: `⌃↑`/`⌃↓` are provably unbound, which is why the preset changed. The
system-event replacement is NOT proven to open Mission Control on this host.** It needs a
human watching the screen. Do not report it as working until someone does.

---

## Round 1–6 — blank settings page, root cause and fix

Two independent faults were needed for a blank page. The first was fixed in the
previous pass; the second was found and fixed in this one, and it is the one that
kept the page empty **even after the files were wired into the build**:

1. **The four sources had no `project.pbxproj` references at all** (grep count 0).
   This project uses classic PBX groups, not filesystem synchronization, so an
   unwired file is silently excluded — the build still succeeded, so "BUILD
   SUCCEEDED" proved nothing. Confirmed by measurement: the compiled
   `XFinder.swiftmodule` contained **0** occurrences of `GestureProfiles` /
   `GestureController` / `GestureWorker` / `MouseGesturesDetailView`, while
   known-present types resolved normally. After wiring all four entries per file,
   the same module contains them.
2. **`RootView.DetailHostView` had no `case .mouseGestures`**, so the sidebar row
   fell to `default:` → the "under construction" placeholder.
3. **The app crashed on launch, before any view rendered.** Adding new keys to
   `L10n.moreDict` introduced two duplicate keys (`"Mặc định"`, `"Hoàn tác"`).
   A Swift dictionary literal with duplicate keys is a **fatal error** —
   `Swift/Dictionary.swift:880: Fatal error: Dictionary literal contains duplicate
   keys` — so the process died during startup and every page, not just this one,
   was blank. Measured: the launch produced 84 bytes of stderr with that exact
   message, and `mouseGestures.lastTapState` was never written. After removing the
   duplicates, stderr is **0 bytes** and the tap state key appears.

   `.agent-tmp/dupkeys.py` now checks both dictionaries; the full pass prints the
   duplicate count and it must be **0**. Note that this failure is invisible to the
   Swift compiler *and* to the VI-literal lint — only reading stderr catches it.

## Passed

- Debug Xcode build, Swift 6, arm64. The compile log names all four sources:
  `GestureModel.swift`, `GestureEngine.swift`, `GestureController.swift`,
  `MouseGesturesDetailView.swift`.
- `lipo -archs` reports **arm64**, not a Universal build.
- Swift package: **78 tests, zero failures**, including the mouse-gesture suite.
  The model compiled by tests is a **symlink** to the actual production model, so the
  presets under test cannot drift from the presets that ship.
- The app's real settings page rendered and its controller initialised: the page wrote
  `mouseGestures.configuration.v1`, which only happens after
  `MouseGesturesDetailView.onAppear` runs.
- **Preset-first measured on disk:** a fresh install persisted
  `{"enabled": true, "trigger": {"mouseButton": {"_0": 2}}, "deadzone": 12,
  "tiltEnabled": false, "debug": false, "overrides": {}}`.
  `overrides` is **empty** — nothing is pre-filled, so future preset updates remain
  deliverable.
- **The Event Tap genuinely opens.** With an enabled configuration the app persisted
  `mouseGestures.lastTapState = {active: True, failure: '', trusted: True}`.
  This is a measured port state, not an inference from status text.
- **Legacy-payload migration verified end to end.** Seeded a payload generated by the
  real `Codable` model: 18 bundles carrying the complete factory dictionary, one genuine
  edit (Safari `up` → `⌘A`), one explicit Unassigned over a slot that had a factory value
  (Safari `down`), one explicit Unassigned over a slot that had none (Word `left`), and
  one unknown bundle (`my.custom.app`). After a real launch the surviving overrides were
  exactly `com.apple.Safari` (`up` = key 0 + ⌘, `down` = unassigned) and
  `my.custom.app`; Word and every other untouched family were pruned, and
  `mouseGestures.migrated.v1 = True`.

  **Measurement trap worth keeping:** the first seed of this probe hand-wrote the JSON as
  an object-of-objects (`{"com.apple.Safari": {"up": …}}`). Swift encodes
  `[GestureDirection: GestureAction]` as a **flat alternating array**
  (`["up", {…}, "down", {…}]`), so the app failed to decode it, quietly fell back to
  default settings, and the probe looked like "the migration never runs". Generate any
  legacy fixture with `JSONEncoder` on the real model; a hand-written fixture tests the
  fixture, not the code.
- **A decode failure no longer discards user data.** `init` used `try?` + a non-optional
  `enabled`. Measured: removing that one key from an otherwise valid payload makes
  `JSONDecoder` throw `keyNotFound`, `try?` swallows it, and the whole configuration
  (every custom mapping included) is lost. `GestureController.recover(from:)` now re-reads
  the envelope field by field, so a missing or renamed key recovers the readable fields
  instead of erasing them. (A *nullable* `enabled` was also probed and decodes fine when
  absent — the failure needs the non-optional form.)
- **The preset keys render as readable keystrokes.** `GestureShortcut.label` covers
  every key the built-in presets use, pinned by
  `testEveryPresetKeyHasAReadableLabel`; the page composes those with an action name
  ("New tab — ⌘T").
- Regression harness compiles the actual event worker, runs on a background queue
  and diverts output into memory, so it never sends test clicks into user apps:
  - sub-threshold click down/up; synthetic marker / recursion bypass;
  - browser up produces ⌘T; exactly one down/up pair;
  - out-and-back stroke does not become an accidental click;
  - cancel/app switch/disable drains suppressed release without replay;
  - modifier gesture, ordinary keyboard-shortcut cancellation;
  - left/unrelated buttons pass through;
  - trigger/shortcut recording, Escape, key-up/repeat suppression;
  - continuous horizontal scroll passes, discrete tilt is opt-in and throttled.
- Mutation testing on a scratch copy of the **real** model, restored byte-identical
after each run. Each injected bug was caught:

  | Injected bug | Tests failed |
  |---|---|
  | Dev family `up` falls through to the Global preset | 12 |
  | Browser previous-tab uses ⌘⇧Tab instead of ⌃⇧Tab | 6 |
  | Word given an invented worksheet shortcut | 5 |
  | Row badge claims `preset` while resolving `Unassigned` | 55 |
  | Explicit `Unassigned` falls through to the preset | 1 |
  | Key `27` (`-`) dropped from the readable-name table | 1 (`testEveryPresetKeyHasAReadableLabel`) |
  | Readiness helper returns "ready" regardless of tap state | 1 (`testReadinessBadgeNeverClaimsReadyWithoutAnArmedTap`) |

  Separately, the earlier click-decision mutation (use final displacement only) failed
the harness with exit **133**, `Out-and-back must not replay a click`.
- Live probe: the terminal-hosted binary **has Accessibility access**; actual
  background Event Tap creation and teardown succeeded. A real port was manually
  disabled, then the timeout handler was invoked: `CGEvent.tapIsEnabled` became
  true. This tests the recovery branch, **not an OS-induced timeout under load**.
- Model microbenchmark: 1,000,000 delta samples about **0.084 s** in this run.
  Actual callback harness: 80,000 invocations about **0.040 s** in another run.
  These are synthetic CPU microbenchmarks, **not hardware input latency/polling-rate
  measurements**, not proof of sustained 8 kHz behaviour.
- VI-literal lint on all Views: **TOTAL 0**.

## Preset resolution verified, per family

The preset table was audited by compiling the production model and printing every
built-in bundle's resolved action per direction. All seven families matched the
specified keys exactly, including the deliberately empty cells:

- Global: ⌃↑ ⌃↓ ⌃← ⌃→ · tilt ⌘[ ⌘]
- Browsers: ⌘T ⌘W ⌃⇧⇥ ⌃⇥ · tilt ⌘⇧T
- Dev/AI: ⌃- ⌃⇧- only; up/down unassigned
- Media: ⌘0 ⌘Z `[` `]` · tilt unassigned
- Messaging: ⌥↑ ⌥↓ only; up/down unassigned
- Office: **every direction empty** — nothing invented for Word
- Notes: ⌘P ⌘⌥← ⌘⌥→ · down unassigned

The runtime and the UI both call `GestureProfiles.resolve` / `configuration.action`;
there is only one mapping table, and a test asserts the two paths agree.

## App smoke test and permission limitation

- Launched the development app with `-startPage mouseGestures` and confirmed via
  `CGWindowListCopyWindowInfo` that a **1079×1007 on-screen main window** existed.
- Screen Recording is **not** granted to this test host, so **no screenshot-based
  visual QA is claimed** (`screencapture` fails with *could not create image from
  display*). Readiness is therefore reported from the measured
  `mouseGestures.lastTapState` key rather than from pixels.
- AX inspection of the page is unavailable here: the shell has no Accessibility grant,
  and `osascript` fails with `-1728`. The persisted-key and window-list evidence above
  is what this record rests on.

## Still needs physical/manual verification

1. Record the actual Razer/Logitech button; verify click, double click, each swipe,
   diagonal, below-threshold and out-and-back movement.
2. Repeat at available polling rates (125/1000/8000 Hz), including UI load. Measure
   timeouts and latency; do not infer them from the synthetic loop above.
3. Switch apps while holding, unplug/replug, sleep/wake and change mouse model;
   verify no stuck buttons, accidental replay or unexpected native drag.
4. Verify each listed shortcut in installed app versions and keyboard layouts.
   Bundle IDs from the prompt are configurable presets, not confirmed installed IDs.
5. Enable tilt deliberately; verify direction and driver encoding. Test continuous
   Magic Mouse/trackpad scrolling still behaves normally.
6. Test modifier-trigger coexistence with the user's actual shortcuts and other
   mouse utilities. Event tap ordering across separate products is not guaranteed.
7. With the feature disabled and settled, measure idle CPU over at least 60 seconds.
8. Confirm the Accessibility grant survives a rebuild. On an ad-hoc signed dev build
   the grant is bound to the cdhash, which changes every build; sign with a stable
   certificate (`scripts/dev-install.sh`) or re-grant after each rebuild.
   → **Resolved this round.** A self-signed "XFinder Dev" cert was created without the
   GUI (OpenSSL + `security import -legacy` + `security add-trusted-cert`), the app is
   signed with it and installed to a fixed path, and the Designated Requirement is now
   `identifier "com.xfinder.app" and certificate leaf = H"989e240c…"` — **not a cdhash**.
   The grant now survives rebuilds. Commands are in MOUSE_GESTURES.md.

---

## Round 2 — usability fix for "không hiểu dùng nút nào" (2026-09-21)

User-reported confusion, quoted: *"phần trình các gestures hơi khó hiểu, tôi ko hiểu dùng
nút nào của chuột với mũi tên"*. Two separate defects, both fixed and both measured:

| Defect | Fix | Test |
|---|---|---|
| Trigger was labelled `"Button 2"` — a CoreGraphics number, not a part of the mouse | `TriggerSource.buttonName(_:)` names the physical control and keeps the raw code in parentheses: `Nút giữa / bấm con lăn (Button 2)` | `testTriggerLabelsNameAPhysicalControl` — **proven to fail** by reverting the label (2 assertion failures) |
| Rows showed a bare arrow with no motion explained | `GestureDirection.instruction` states the motion (`Giữ nút rồi kéo LÊN`; `Nghiêng con lăn sang TRÁI (không giữ nút)`), rendered as a second line under each shortcut | `testEveryDirectionExplainsTheMotion` — **proven to fail** by collapsing the `up` instruction to `"↑"` (2 assertion failures) |

Also on the page now: a three-step **“Dùng như thế nào”** walkthrough (hold → drag → release,
with the click-threshold rule and a concrete Safari example), and the tilt switch reworded
from *“Ánh xạ tilt ngang rời rạc”* to *“Bật nghiêng con lăn (Tilt) — không cần giữ nút”*,
now stating that ordinary mice and the Magic Mouse have no tilt motion at all.

### Measured this round

| Result | Status | Evidence |
|---|---|---|
| Build | ✅ | `BUILD SUCCEEDED`; **0 errors and 0 warnings** in all five touched sources |
| Automated tests | ✅ | **81 tests, 0 failures** (was 78) |
| Both new tests can fail | ✅ | Bugs injected into a scratch copy, watched go red, restored byte-identical (`diff` empty) |
| Duplicate-key gate | ✅ | New `scripts/check-l10n-duplicates.py` → `TOTAL 0 duplicates across 843 unique keys`; **proven to fail** by injecting a duplicate (`exit=1`, names the exact line) |
| VI-literal lint | ✅ | `TOTAL 0` |
| New strings shipped | ✅ | All 13 new strings found in `XFinder.debug.dylib` (Debug splits the binary — the 58 KB `XFinder` is only a launcher stub, so `strings` on it finds nothing even for strings that *are* shipped) |
| Event Tap activation | ❌ **not granted** | `mouseGestures.lastTapState = {active: False, trusted: False, failure: "chưa có quyền Trợ năng"}` |
| Physical mouse behaviour | ❌ **not tested** | Needs the user's hardware |

**Why the tap is still closed despite the user granting permission:** the grant was made to
the previous ad-hoc build, whose cdhash no longer matches. `tccutil reset Accessibility
com.xfinder.app` was run so the cert-signed build starts from a clean identity; one fresh
grant now sticks permanently.

**Note on `strings` as a verification tool: it is unreliable twice over here.** First, macOS
stores Swift string literals as UTF-8, and `strings` only prints ASCII runs, so Vietnamese
diacritics break the run. Second, a Debug build puts the code in `XFinder.debug.dylib`, not
in `XFinder`. A control string known to be shipped reported MISS under both mistakes, which
is what exposed them — always include a control that must be present before trusting a MISS.

---

## Round 3 — UI/UX rebuilt as a mouse diagram (2026-09-21)

User's report, quoted: *"Global settings hiện tại sau khi build thì rỗng"*, *"Global Settings
với tôi hơi vô dụng"*, *"UI/UX của chức năng này khá tệ nhìn quá AI cứng nhắc, tôi cần giao
diện gần gũi hơn như Mac Mouse Fix hoặc MOS"*. Standing instruction for that round:
*"From now you can do everything bypass, no need ask me"*.

### The premise was wrong, and that mattered

**Global was never empty.** A probe compiled against the real `GestureModel.swift` printed
all six of its mappings resolving correctly:

```
== all[0].id = *  name = Global  defaults.count = 6
  ↑      -> ⌃↑  [preset]       ↓ -> ⌃↓ [preset]
  ←      -> ⌃←  [preset]       → -> ⌃→ [preset]
  Tilt ← -> ⌘[  [preset]       Tilt → -> ⌘] [preset]
```

The on-disk config confirmed `"overrides": {}` — correct and deliberately un-prefilled.
**The real cause was layout, not data.** The old `row(_:)` was one flat `HStack` of six
elements, all `.lineLimit(1)`: app icon, a 46 pt `↑`, the action name, the motion sentence,
a text badge, and **two** buttons (`Ghi phím` + a `Menu`). For Global, `⌃↑` is three
characters competing with a full Vietnamese sentence for a ~240 pt pane, so every element
truncated to invisibility. Six correctly-resolved rows rendered as six blank lines.

**Lesson kept:** "the page looks empty" was read as a data bug for three passes. It was
proved to be a layout bug only by resolving the *model* directly and finding it full.

### What replaced it

| New file | Role | pbxproj |
|---|---|---|
| `Views/Components/MouseDiagramView.swift` | The mouse drawing whose arrows **are** the selector. Each arm is a real `Button`; tilt is shown as a rotation hint on the wheel, not a fifth arm, because it is a different physical motion. Help text on every arm states the motion *and* what it sends | 4 entries |
| `Views/Components/GestureDetailPanel.swift` | Right-hand panel: Động tác → XFinder gửi (key in its own field) → provenance pill + explanation → secondary actions | 4 entries |
| `Core/MouseGestures/GestureUIDisplay.swift` | Pure UI logic extracted **out of the view** so the interaction is assertable: `MouseDiagramSelection` toggle/prof-forget, `GestureDirectionDisplay` headings + tilt rules | 4 entries |

All three needed the four hand-authored `project.pbxproj` entries each. This is exactly the
trap recorded above: an unwired file is **silently excluded while the build still says
SUCCEEDED**, which is one of the three settled causes of the original blank page.

### Measured this round

| Result | Status | Evidence |
|---|---|---|
| Build | ✅ | `BUILD SUCCEEDED`, 0 `error:` lines |
| New files actually compiled | ✅ | All 3 appear by name in `XFinder.SwiftFileList` (lines 95–97) — **not** inferred from the build result |
| Architecture | ✅ | `lipo -archs` → `arm64` |
| Automated tests | ✅ | **86 tests, 0 failures** (was 81) |
| New tests can fail | ✅ | `scripts/mutation-check-gesture-ui.sh` injects **5** bugs; all 5 went RED, file restored byte-identical (`diff` empty) |
| Duplicate-key gate | ✅ | `TOTAL 0 duplicates across 881 unique keys` |
| VI-literal lint | ✅ | `TOTAL 0` |
| L10n coverage | ✅ | Every static `L10n.t("…")` key used by the gesture UI exists in a dictionary — 0 missing (previously 41 were missing, i.e. the new UI would have leaked Vietnamese into the English UI) |
| New strings shipped | ✅ | All 20 probed new strings found in `XFinder.debug.dylib`, with 3 control strings confirming the probe |
| No fatal duplicate-key crash | ✅ | App launched with stderr captured to a file: **0 lines**, and no `Dictionary literal contains duplicate keys` in the unified log |
| Stable signature | ✅ | DR is `identifier "com.xfinder.app" and certificate leaf = H"989e240c…"` — **not** a cdhash, so the Accessibility grant survives rebuilds |
| Event Tap activation | ✅ **this round** | `mouseGestures.lastTapState = {active: True, trusted: True, failure: ""}` — the tap is armed. One fresh grant was made to the cert-signed build and it stuck |
| Physical mouse behaviour | ❌ **still not tested** | Needs the user's hardware and hand. Nothing here substitutes for it |

**The five injected bugs**, each watched going red before restore:

1. `afterClick` becomes a one-way radio instead of a toggle → 1 assertion failed
2. `afterProfileChange` keeps the stale arm (already-selected direction shown for the *previous* app) → 1 failed
3. Horizontal-scroll option removed from the tilt arms → 4 failed
4. Horizontal-scroll offered on the drag arms instead → 10 failed
5. One direction loses its heading (empty title above its keys) → 1 failed

Mutation 3 is worth keeping: on the **first** run it stayed GREEN, which proved the new test
set did not yet cover `supportsHorizontalScroll`. A test was added, and only then did it go
red. A mutation that does not fail is a finding, not a nuisance.

### Two honest defects recorded (both now resolved — see Round 4)

1. **`GestureDetailPanel`'s “Về mặc định” resets the whole app, not the one direction.**
   The button label reads as per-direction but it called `controller.resetProfile(profile)`,
   which removes every override for that bundle. This is precisely the "control cannot do
   what its label says" failure the Honesty Rule forbids, so it was recorded here rather than
   quietly left. **Fixed**: `GestureController.resetDirection(bundle:direction:)` now backs
   that button, and `resetProfile` remains only behind the page-footer button whose label
   says "ứng dụng này".
2. **The new UI is Gemini-authored and has never been looked at.** `screencapture` fails on
   this host (`could not create image from display`), AppleScript cannot inspect the app, and
   no accessibility inspector is available — so the layout was verified structurally
   (compiled, strings present, released crash-free, tests green) **not visually**. Any claim
   about how it *looks* is still unverified. **Still true.**

## Round 4 — numbered buttons, an honest tilt default, and a working Global (2026-09-22)

Requested changes and what each one turned out to require, measured.

### 1. Buttons are named by number

The user reversed the earlier decision: *"Hãy đặt tên nút theo số đi"*. Both attempts are
recorded because the reversal is the interesting part.

* Round 2 named the physical control (`Nút hông sau — nút 4 (Button 3)`) because a bare
  number was unreadable to the user. That fix asserted an anatomy **nothing had measured**.
* The number is the only identifier true for every mouse. Measured constraint: `CGEventField`
  has only five mouse fields and the highest index is `3` (`mouseEventButtonNumber`) — there is
  **no vendor/product/device field**, so no code path can know which physical control a number
  maps to. `IOHIDDeviceCopyMatchingElements` over-matches (a probe printed "873 input-button
  elements"), so it is not a substitute either.
* What ships: `TriggerSource.buttonName(n)` → `Nút \(n+1)`, with a short factual note only on
  0/1/2 (`Nút 1 (chuột trái)`, `Nút 2 (chuột phải)`, `Nút 3 (bấm con lăn xuống)`). From 3 up it
  is the bare number, and never "hông sau", "bắn tỉa" or "DPI".
* The synthesis with the round-2 complaint: the **number is primary and is printed on every
  arrow** (`Nút 3 ↑`), and every detail heading names it (`Nút 3: kéo lên`). The round-2 problem
  ("which button do I hold?") is answered by the number being *present*, not by inventing a name.

### 2. Indexing discovered by a mutation, not by reading

`testTriggerLabelsNameButtonsByNumber` asserts `mouseButton(n)` renders `Nút (n+1)` for
1...31. This is a **slash-numbering offset**, and it is the one thing about button naming that
is easy to get silently wrong.

### 3. Global was genuinely useless — root cause checked, not assumed

The user: *"hiện tại Global Settings với tôi hơi vô dụng"*. The reason is specific and was
confirmed against Logitech's own documentation: the **MX Master 3 already binds Mission
Control to its thumb button** in Logi Options, so a Global `⌃↑` repeated a binding the user
already had. The new Global is page/item navigation — `⌘[` / `⌘]` (history) and `⌘⇧[` /
`⌘⇧]` (items), with tilt as zoom — which is what a gesture is actually wanted for.

The old mapping was **replaced, not shadowed**, and a test asserts each old `⌃arrow` binding is
now unequal to what Global sends.

### 4. Tilt: a hard-coded `true` that could never fire

`MouseGesturesDetailView.hasTiltHardware` was `private var hasTiltHardware: Bool { true }`.
Combined with `tiltEnabled`, that drew two tilt arms on hardware where they can never run:
`DeviceCapabilityProbe` measured that **every** scroll event from the Razer Basilisk *and*
the Magic Mouse reports `scrollWheelEventIsContinuous = 1, axis2 = 0`, and `GestureEngine`
deliberately requires `IsContinuous == 0 && DeltaAxis2 != 0` so it never steals trackpad
scrolling. Two of the user's three mice therefore could not fire it at all.

Replaced with `tiltAvailable` (default **false**), which reveals the arms, plus a `tiltRow` on
the page that states what was measured and that XFinder cannot probe the hardware. `tiltEnabled`
still controls whether the engine reads them, so revealing and enabling stay independent.

### 5. Kitty/Terminal had no profile — added, minimally

A real gap in the brief's daily-driver list. Only `⌥←` / `⌥→` (word backward/forward) ship:
Kitty, Terminal and iTerm2 all set `macos_option_as_alt` **off** by default precisely so those
arrive as Option-Left/Option-Right, and AppKit's `moveWordBackward:` / `moveWordForward:` are
standard bindings. Everything else stays Unassigned on purpose — `⌘T` is a new *window* in
Terminal, `⌘W` can kill a running command, and there is no shared "next pane" key. A wrong
keystroke in a terminal destroys work, so Unassigned is the honest answer here.

### 6. A resource that was never in the bundle

`L10n.allowlist.json` had **zero** `project.pbxproj` references (grep count 0) — the same class
of silent exclusion as the four unwired sources in the first round. It happened to work because
only the test package reads it, and the installed app carried a stale build. `build-and-check.sh`
now checks the **built bundle** for both resources, because a resource never appears in
`XFinder.SwiftFileList` and so cannot be caught by the by-name compile check.

### Measured this round

| Check | Result |
|---|---|
| Debug build to `/tmp/xfinder-clean-build` | `BUILD SUCCEEDED`, **0** `error:` lines |
| Present in the compile log **by name** | `GestureModel`, `GestureEngine`, `GestureController`, `GestureUIDisplay`, `MouseGesturesDetailView`, `MouseDiagramView`, `GestureDetailPanel`, `L10n`, `L10nStore` — all 9 OK |
| Bundled resources | `L10n.strings.json` 122048 B, `L10n.allowlist.json` 377 B — both in `Contents/Resources` |
| `lipo -archs` | **arm64** |
| Logic tests | **97 tests, 0 failures** |
| L10n coverage gate | `TOTAL 0 problems across 919 entries` |
| Wrapped literals resolve | 954/954 — `every wrapped literal resolves to a translation` |
| English store contains no Vietnamese | **0** values |
| `verify-l10n-runtime.py` against the **installed bundle** | **TOTAL 0 leaks** — every button label, numbered heading, interpolated number and sidebar row resolves to English |
| Signature | DR = `identifier "com.xfinder.app" and certificate leaf = H"989e240c…"` — stable, so the AX grant survives rebuilds |
| Installed config | `enabled: True`, `trigger: Button 2`, `overrides: {}` — nothing pre-filled, as designed |
| Event Tap activation | ✅ `mouseGestures.lastTapState = {active: True, trusted: True, failure: ""}` |
| Physical mouse behaviour | ❌ **still not verified.** Four separate results; this is the one that needs a hand on the hardware |

**Five injected bugs against the changed model**, each watched going red
(`scripts/mutation-check-gesture-labels.sh`), then the source verified restored
byte-identically:

1. Invented physical button names return → 2 test cases failed
2. A direction heading omits the held button → 1 failed
3. Global reverts to Mission Control → 2 failed
4. Tilt arms revealed by default → 1 failed
5. Button number loses its `+1` offset → 2 failed

**A mutation that stayed green, and what it caught.** Mutation 5 of
`scripts/mutation-check-l10n.sh` (delete the `"kéo sang trái"` heading fragment) stayed GREEN
on the first run. The reason was a real hole: the heading is assembled at runtime from
`TriggerSource.numberedName` **plus** a hint fragment, and the test only probed the *whole*
assembled sentence — which was still in the store. Deleting the hint left the English page
rendering `Button 3: kéo sang trái` with a fully green suite. `L10nFixture.directionHint(_:)`
now derives the hint from the real functions and asserts its fragment resolves; all six
mutations then went red.

### Still not verified

1. **Physical mouse behaviour** — hold, drag, release, and whether the sent keystroke does
   what the label says in each app. This needs the user's hand and their three mice.
2. **The tilt switch's real effect on tilt-capable hardware** — the probe says the Basilisk and
   the Magic Mouse cannot fire tilt; a Logitech with Logi Options was never available to test.
3. **How the page looks.** `screencapture` still fails on this host, so the diagram's numbered
   arms, the tilt row and the picker were verified structurally and by resolution, not visually.

---

## Round 5 — one map for the whole module, and a measured activity panel (2026-09-22)

Triggered by the same report returning a third time: *"UI/UX ok rồi. Còn lại chức năng của
gestures không phù hợp"*. The UI had been rebuilt twice; the **mappings** were the part that
never matched the user's habits. Two structural causes, both fixed:

* **A preset could not say what an action *was*.** A mapping was a bare `GestureShortcut`,
  and the page guessed a name from the key code —
  `case 17: return L10n.t("Tab mới")` — in a SwiftUI file no test could reach. Keying on the
  intent instead is what lets `⌘0` read "Fit to window" in Photoshop *and* CapCut while the
  same key in a browser means something else, and it is why an unrecognised recorded key now
  shows **no name** rather than a borrowed one.
* **The screen could show fewer options than the engine could perform**, which is the same
  shape as the earlier "page looks empty" reports. `GestureActionCatalog.choices()` is
  generated from `GestureActionKind.allCases`, so the picker cannot be shorter than the
  vocabulary — asserted by `testActionCatalogCoversEveryIntentAndEveryChoiceIsSendable`,
  which is what caught `.horizontalScroll` being present in the vocabulary and missing from
  the list.

### What changed in behaviour

| Area | Before | After |
|---|---|---|
| Global | `⌘⇧]` / `⌘⇧[` (browser "next item") + `⌘[` / `⌘]` | history on the horizontal arms, `⌃←` / `⌃→` on the vertical — the two conventions with the widest reach |
| Browsers | left/right = `⌃⇧⇥` / `⌃⇥` | history on left/right, next-tab moved to the tilt arms |
| Dev & AI | `⌃-` / `⌃⇧-` (one editor's pane keys) | `⌘[` / `⌘]`, which every editor honours |
| Excel / Word | **one empty table shared by both** | two tables: Excel has the documented sheet pair, Word has none because Word has no worksheets |
| Terminals | unchanged, deliberately minimal | unchanged |
| Tilt (presets) | `⌘=` / `⌘-` | unassigned — the tilt branch already passes the wheel's own scroll through, so a preset keystroke here was a key that could never do anything useful |
| Scroll | — | **Engine C**: hold a side button and drag to scroll, off by default, repaired so it can never share a button with the trigger |
| Action picker | intent guessed from key code | 20 intents × their keystrokes, grouped by what the user is doing |
| Page feedback | instructions only | **measured activity**: the engine reports button-press, direction-lock, sent action, preserved click and cancellation |

### Measured this round

| Check | Result |
|---|---|
| Debug build | `BUILD SUCCEEDED`, 0 `error:` lines |
| New sources in `XFinder.SwiftFileList` by name | `GestureMap.swift`, `GestureArmView.swift`, `GestureActionPicker.swift`, `GestureActivityPanel.swift` — all present |
| `lipo -archs` | **arm64** |
| Logic tests | **137 tests, 0 failures** (was 97 at Round 4) |
| L10n coverage gate | `TOTAL 0 problems across 1018 entries` |
| L10n duplicates gate | `TOTAL 0 duplicates across 1018 unique keys` |
| VI-literal lint over `Views/` | `TOTAL 0` |
| `LanguageNeutralKeys` contains no sentence | the gate now **reads `Core/L10n.swift` from source**, because that file imports SwiftUI and the test package cannot compile it — and because the thing it must catch is the *declaration* being wrong |
| Event Tap activation | ✅ `{active: True, trusted: True, failure: ""}` |
| Physical mouse behaviour | ❌ **still not verified** — see below |

**Two injected bugs, each watched going red, source restored and re-run green:**

1. `GestureMap.row` ignoring `overrides` → **4 failures** (the row/runtime agreement test for
every bundle and direction, plus the override assertions).
2. `displayName` returning the intent name for any shortcut → **1 failure**
(`testRecordedShortcutIsNotGivenAnInventedActionName`).

### Still not verified after this round

1. **Physical mouse behaviour.** Four results stay separate: build ✅ / tests ✅ / event tap ✅ /
   **hardware ❌**. Hold a side button, drag each direction, release — that is the only thing
   that proves the mapping table, and it needs the user's hand.
2. **Which physical button is which number on the Basilisk V3 35K.** The HID descriptor declares
   `buttons = [1,2,3,4,5]`, and declaration order does **not** prove physical position. The page
   now reports the number of any press it observes, so the user can read it off rather than
   trust an index — but that reading has not been taken.
3. **Engine C's feel.** The throttle is ~60 Hz thought through, not measured against a hand.
4. **How the page looks.** `screencapture` still fails on this host.

See [MOUSE_GESTURES.md](MOUSE_GESTURES.md) for exact mappings, configuration and commands.

---

## Round 6 — the acceptance section, and a probe that falsified its own brief (2026-09-22)

### The brief's premise was wrong, and the probe is the reason to say so

PATCH v7 R1 asserted that the HID probe **undercounts** the Basilisk: it should report “≥7
buttons, not 5”, because the filter misses Razer's Vendor Defined Page (`0xFF00+`), and
there are two profile buttons on top of the wheel to exclude.

The brief also required the probe be run before any code changed. It was
(`scripts/probe-hid-raw.swift`, dumping `UsagePage`/`Usage`/`type` for **every** element before
any filtering). The measurement contradicts the brief on both counts:

```
=== Razer Basilisk V3 Pro 35K ===
  transport: USB   vendorID: 0x1532   productID: 0x00D6
  TOTAL elements: 105
  tally by (page, type):
    page=0x0009 type=0x02  ×5        ← the five buttons
    page=0xFF00 type=0x101 ×92       ← vendor page: FEATURE elements only
    page=0x0000 type=0x05  ×2
    page=0x0001 type=0x01  ×3
    page=0x0001 type=0x201 ×2
    page=0x000C type=0x01  ×1
  CURRENT filter (type 0x02 && page 0x09) buttons: [1, 2, 3, 4, 5]
  v7 PROPOSED filter (page 0x09 only)     buttons: [1, 2, 3, 4, 5]   count=5
  ALL button-typed elements (any page): [1,2,3,4,5 on 0x09] — nothing else
```

Three facts this settles:

1. **5 is correct.** The count is not an undercount. The shipped filter and v7's proposed
   filter return the **same** five usages, so `0xFF00` is not hiding buttons on this device.
   Adding the proposed branch would have changed nothing on the Basilisk while admitting
   garbage everywhere else — which is exactly what it does on **the Apple trackpad**, where the
   same tree declares `page=0xFF00 type=0x02` with `usage=0xFFFFFFFF` on **1753 elements**. A
   filter that scanned `0xFF00` for buttons would report **1756 buttons** on the trackpad, and
   a `usage` of `-1` cannot be rendered as a number at all.
2. **The profile-button exclusion is unnecessary.** No element on any page reports a sixth or
   seventh button, so there is nothing to exclude. (The two buttons above the wheel are handled
   by Razer's own firmware/driver and never reach the HID button page.)
3. **The declared identity differs from the value recorded in `Claude.md`.** Measured now:
   `USB`, `vendorID 0x1532` (Razer), `productID 0x00D6`. The stored note says
   `Bluetooth Low Energy`, `0x068E / 0x00D8` (the BSKV3P 35K). Both are real; they are the
   **same mouse over two transports**, and the mouse is currently on USB. So the note is not
   wrong, it is incomplete — a device that changes transport changes its identity tuple, which
   `deduplicated(_:)` keys on.

**What was done instead:** no probe change. R1 reduced to the profile-button exclusion, which
needed nothing. `DeviceCapabilityTypes.swift` and `DeviceCapability.swift` are untouched, and
the `0xFF00` branch the brief asked for was **not** added — it would have re-introduced the
class of bug (`[1,2,3,4,5,9]` from an over-broad filter) that a fixture test already pins.

### Implemented this round

1. **An acceptance section at the head of the page.** When a gesture does not fire there are
   exactly two causes, and both were invisible in the mapping table: the hold button is the
   wrong one, or XFinder is the app in front. Both are now stated as measurements — *this*
   button number, *this* bundle ID — not as advice.
2. **The wheel-hold warning.** The user's stored configuration carries
   `trigger = mouseButton(2)`, the wheel click, and `validate()` will never repair it because 2
   is a *valid* trigger. The page now singles that value out with an orange warning and a
   re-record button. This is the concrete cause of “cử chỉ không chạy”.
3. **An inline "set this as the hold button" offer**, gated on `observedPress` being a button
   **different from** the current trigger. The rejected alternative (v6 R1) was gated on
   `trigger == 2 && overrides == {}`, which matched **every fresh install**; gating on an
   observed press is what makes the offer honest.
4. **The frontmost-target row.** Explains a log full of `com.xfinder.app`: the resolver keys on
   the frontmost bundle, and while the user tests from this page XFinder is frontmost. Stating
   it is the honest fix — silently substituting the Global table would make the page disagree
   with the engine, which is the one thing `testMapRowAgreesWithRuntimeActionForEveryBundleAndDirection`
   exists to prevent.
5. **`DEBUG_SHOW_ENGINE_LOG` (v7 R5).** A compile-time gate, not a runtime `if`: the strings,
   the row view and the diagnostic plumbing leave the binary entirely. Verified both ways — the
   build succeeds with it `false`, and the source was restored byte-identical afterwards.

### Measured this round

| Check | Result |
|---|---|
| HID raw probe | run and reported above — **the brief's premise is falsified** |
| Debug build | `BUILD SUCCEEDED`, 0 `error:` lines |
| Gesture sources in `XFinder.SwiftFileList` by name | all 17 present, incl. `MouseGesturesDetailView.swift` |
| Bundled resources | `L10n.strings.json` (138 835 B), `L10n.allowlist.json` |
| `lipo -archs` | **arm64** |
| Logic tests | **143 tests, 0 failures** (was 139) |
| L10n coverage / duplicates | `TOTAL 0` across **1031** entries |
| VI-literal lint over `Views/` | `TOTAL 0` |
| Runtime L10n against the **installed** app | `TOTAL 0 leaks in the resolved English UI` |
| Event Tap activation | ✅ `{active: True, trusted: True, failure: ""}` |
| Installed signature | `identifier "com.xfinder.app" and certificate leaf = H"989e240c…"` — stable across rebuilds |
| Finder Sync appex | `+ com.xfinder.app.XFinderSync(1.0) … /Applications/XFinder.app/Contents/PlugIns/XFinderSync.appex` |
| Physical mouse behaviour | ❌ **still not verified** |

**Two injected bugs, each watched going red, source restored byte-identical and re-run green:**

1. The wheel-hold predicate degenerated to a generic `isMouseButton` → **4 failures**
   (`testWheelHoldIsSingledOutAsUnusable`). This is the mutation that matters: it restores
   exactly the blindness that hid the user's reported bug.
2. The "set as hold" offer made to fire on **any** press (including the current trigger) →
   **1 failure** (`testSetAsHoldOfferRequiresADifferentObservedButton`).

The `DEBUG_SHOW_ENGINE_LOG` gate was also exercised both ways: compiled with `false`
(`BUILD SUCCEEDED`, section removed from the source unit) and restored byte-identical.

### What the user must still do — one action

The configuration on disk still holds `trigger = mouseButton(2)`. **Nothing in the code changes
it**, by design: it is a valid value, so a silent migration would overwrite a deliberate choice
for anyone who genuinely likes it. Open **Chuột & cử chỉ**, read the orange row, click
**Ghi lại nút giữ**, and press the side button you want to hold. The row updates on the press.

---

## Round 7 — PATCH v9.1: the diagram draws the device, and the buttons get names (2026-09-23)

Scope was **UI only** by instruction (`Gestures logic FREEZE. Chỉ sửa UI`). No gesture semantics,
no trigger default and no engine path changed in this round.

### The requirement that could not be met as written, and the measurement that says so

R1 asked for the HID probe to be widened so a Basilisk V3 Pro 35K "over USB must return 6
buttons", and said that if it still reports 5 the UI must show a *Missing buttons* warning rather
than draw it wrong.

**The mouse is currently not connected on this machine, so the 6-button claim could not be
re-measured, and it was not asserted either way.** What the probe *did* measure, live:

```
IOHIDManagerOpen kIOReturn: 0
raw device count BEFORE dedupe: 2
  Apple Internal Keyboard / Trackpad   FIFO   vendorID: nil   productID: nil
    TOTAL elements: 1771
    page=0x0009 type=0x02  ×3        ← the declared buttons: usages [1,2,3]
    page=0xFF00 type=0x02  ×1753     ← usage 0xFFFFFFFF, element type Input_Button
```

`system_profiler SPBluetoothDataType` lists `BSKV3P 35K` (`0x068E/0x00D8`) under **Not Connected**.

**The `0xFF00` row is the reason R1's widening is not just unhelpful but actively harmful.** On
this very machine the Apple trackpad declares **1753** vendor-page elements of element type
`Input_Button`, every one with usage `0xFFFFFFFF` (= `-1`). A filter that scanned `0xFF00` for
buttons would report **1756 buttons**, one of them numbered `-1`. That is the same failure as the
original "873 input-button elements": a filter widened until it produced a number, then the number
believed. No widening was made; the button filter is unchanged and still pinned by
`testButtonFilterRequiresTheButtonPageNotJustTheElementType`.

### What was implemented instead — the honest form of R1's own fallback

R1's escape hatch was "if the probe still says 5, show a *Missing buttons* warning instead of
drawing it wrong". That is what shipped, in a form driven by **evidence rather than a guess**:

* the drawing renders every archetype position, but a control the descriptor does not declare is
drawn **dashed and dim**, and a control on a descriptor that could not be read says *"not read
yet"*. The two are different states and are never collapsed;
* pressing a button the descriptor never declared raises the warning **with the measured number
  in it** and a one-click *Đặt làm nút giữ* on that row. It cannot fire on a mouse that merely has
  fewer buttons, because it requires a real press to contradict the real declaration.

### Implemented

| Area | Change |
|---|---|
| Diagram | `MouseDiagramView` rewritten to draw the mouse's actual controls at archetype positions (left/right/middle on top, side buttons on the left edge, Sniper at the thumb rest), each labelled with the **compact** button name |
| Buttons list | new `GestureButtonList` — every control with its live role (`Nút giữ` / `Nút cuộn` / `Chỉ bấm` / `Chưa gán` / `Chuột không khai báo` / `Chưa đọc được`) and a one-click *Đặt làm nút giữ* |
| Role model | `MouseControlSlot`, `MouseButtonRole`, `MouseRoleContext`, `DeviceCapabilityModel.role(forEventButton:context:)`, `.undeclaredPress(observed:context:)`, `.eventButtons(from:)`, `.drawnButtons(...)` — all in the **Foundation-only** half, so all testable |
| Tilt | the two tilt arms moved to their own row under the drawing; inside the figure they collided with the newly-drawn control chips |
| Compact label | `ButtonLabelStructure.compactLabel(forButtonNumber:)` + `L10n.t(compactButton:)` so a 46 pt chip drops the positional hint without dropping the numbering |
| Language gate | new `scripts/audit-gesture-vocabulary-l10n.py` — enumerates the module's vocabulary from its declarations and resolves every key against the shipped store |

### Measured this round

| Check | Result |
|---|---|
| Debug build | `BUILD SUCCEEDED`, 0 `error:` lines |
| Sources in `XFinder.SwiftFileList` by name | 19/19 OK, incl. the new `GestureButtonList.swift` (proving the four hand-written pbxproj entries are right) |
| Bundled store | `L10n.strings.json` 148 817 B, **1 074** entries (was 1 055) |
| `lipo -archs` | **arm64** |
| Logic tests | **176 tests, 0 failures** (was 162) |
| New vocabulary gate | 63 keys + 20 profile names, `TOTAL 0 unresolved` |
| L10n coverage / duplicates | `TOTAL 0` across 1 074 entries |
| Runtime L10n against the **installed** app | `TOTAL 0 leaks in the resolved English UI` |
| **Rendered page, English** (`probe-ax-dump.swift`) | **116 text nodes, 89 static-text, 38 buttons — the page is not blank**; **0 Vietnamese lines** (the single regex hit was `App Exposé`, an allowlisted brand name) |
| **Rendered page, Vietnamese** | same 116 nodes; the only strings identical to English were `Quick Look`, `Mission Control`, `App Exposé` (all allowlisted), the four key glyphs `⌃↑ ⌃↓ ⌃← ⌃→`, and the IOHID product name `Apple Internal Keyboard / Trackpad` |
| Mutation harness (`mutation-check-gesture-buttons.sh`) | **5/5 RED**, source restored byte-identical, post-restore suite **176/0** |
| Physical mouse behaviour | ❌ **still not verified — and this round the mouse was not even connected** |

### The five injected bugs

| | Bug injected | Tests that caught it |
|---|---|---|
| M1 | usage→event conversion lost its `- 1` | 3 (`testEventButtonsConvertUsagesToZeroBasedNumbers` and neighbours) |
| M2 | `reserved` checked before the stored assignment | 1 (`testAssignmentOutranksReservedAndEverythingElse`) |
| M3 | the missing-button prompt fired on every press | 1 (`testUndeclaredPressFiresOnlyOnAMeasuredMismatch`) |
| M4 | the compact label re-derived the number itself | 1 (`testCompactLabelKeepsTheNumberingAndTheSharedNames`) |
| M5 | `MouseButtonRole.labelKey` returned a rendered sentence instead of a store key | 1 (`testGesturePageStringsAreAllTranslatable`) |

### Two false premises this round corrected

1. **"The feature page shows nothing."** Measured against the installed build: the page renders
   116 text nodes and 38 buttons, in both languages. The premise is false for this build; the
   cause of what the user saw was not reproducible here. What *was* reproducible is what they said
   next — the figure showed one control and no way to tell which physical button pairs with which
   arrow — and that is what this round fixed.
2. **"`Button 3` everywhere."** As of the L1 fix the held number is printed **once**, on the mouse
   body, and no arm prints a number. The *button table* is still numbered from 1 (`mouseButton(2)`
   is `Middle click`, i.e. the third control), which is macOS's 0-based numbering plus one, and
   that is intentional and documented. Every control now carries its own label, so four identical
   numbers are no longer possible.

### Still needs a human

* **Connect the mouse and read the buttons list.** Whether the Basilisk declares five controls or
  six is measurable in one second once it is paired: open the page, and the line reads
  *"The mouse's HID descriptor declares: …"*. If the Sniper is missing from that list, press it —
  the warning and the measured number appear, and *Đặt làm nút giữ* on that row settles it.
* **Whether a gesture actually fires** in a real app, and whether Mission Control opens. No probe
  in this repo has ever confirmed the last one; it needs eyes on the screen.
* The hold trigger on this machine is still `mouseButton(2)` (the wheel click), which the page
  warns about in orange. Changing it is one click in the new buttons list.
## Round 8 — PATCH v10: the vendor page is read as evidence, the figure follows the device (2026-09-23)

Scope by instruction: **`Gestures logic FREEZE — chỉ sửa Probe + UI`.** Verified rather than
asserted: `git status` for this round lists `DeviceCapability.swift`, `DeviceCapabilityTypes.swift`,
`DeviceCapabilityModel.swift`, `MouseDiagramView.swift`, `GestureButtonList.swift`,
`MouseGesturesDetailView.swift`, the L10n store and the docs. **`GestureEngine.swift`,
`GestureController.swift`, `GestureModel.swift`, `GestureMap.swift` and `SpaceBinding.swift` are
not in that list** — the engine, the trigger default, the deadzone and the release-to-fire rule
were not touched.

### The acceptance that could not be measured today, and the two measurements that say why

R1 asks for the probe to scan both the Button page (`0x09`) and the vendor page (`0xFF00`) and to
return **exactly six** buttons for a Basilisk V3 35K over USB and BLE. Both halves of the
acceptance were attempted; both are blocked by facts on this machine, and neither is claimed.

**1. The mouse is not connected.**

```
$ system_profiler SPBluetoothDataType | sed -n '/Not Connected/,$p'
      Not Connected:
          BSKV3P 35K:
              Address: CA:20:84:51:19:5B
              Vendor ID: 0x068E
              Product ID: 0x00D8
              Minor Type: Mouse
```

**2. The shell cannot read HID elements at all, so even the trackpad cannot be measured today.**

```
$ swiftc -O docs/probes/probe-hid-raw.swift -o /tmp/probe-hid-raw && /tmp/probe-hid-raw
IOHIDManagerOpen kIOReturn: -536870174          ← 0xE00002E2 = kIOReturnNotPrivileged
raw device count BEFORE dedupe: 2
  Apple Internal Keyboard / Trackpad   FIFO   vendorID: nil   productID: nil
  (no elements)                                  ← the manager never opened
```

`-536870174` is `kIOReturnNotPrivileged`: the terminal hosting the probe has no **Input
Monitoring** grant, and without an open manager `IOHIDDeviceCopyMatchingElements` returns nothing.
The same shell also fails the other read path — `AXIsProcessTrusted (this process): false`, so
`probe-ax-dump.swift` reports `NO WINDOWS attribute` and the rendered page cannot be read either.
**Both verification instruments available to this session are unprivileged today.** That is

### What was implemented, and the measurement each piece rests on

| Area | Change | The fact it rests on |
|---|---|---|
| Probe — vendor page | `DeviceCapabilityProbe.vendorButtonUsages(from:)`: element type `Input_Button`, `usagePage >= 0xFF00`, **usage in `1...0x3F`**, deduped | the 1753-element `0xFFFFFFFF` trackpad measurement (Round 7). Without the range guard the count becomes 1753 and one entry is numbered `-1` |
| Probe — raw facts | `elementDump(from:)` (pure) + `connectedElementDump()` (live) + a `DisclosureGroup` on the page | R1's own "log raw UsagePage/Usage before filtering" step, made checkable in the UI instead of in a log nobody reads |
| Descriptor | `PhysicalCapabilities.vendorButtonUsages: [Int]` — **deliberately not folded into `buttons`** | a vendor usage has no defined relationship to a `CGEvent` button number, so `usage - 1` is meaningless there; `buttons` is what every number on the page derives from |
| Figure | `MouseDiagramStyle` (`.archetype` / `.generic` / `.unknown`) + `diagramStyle(for:)`; `.generic` draws **only** the declared controls | the acceptance case "switch to a Magic Mouse → generic figure". `.unknown` still draws the archetype, dashed, because a failed read is not a measured absence |
| Figure | Basilisk positions: top row left — wheel — right; left flank upper / lower / **Sniper lowest**; a **position caption** under each chip | the reference diagram's own layout. Captions are ≤ 14 characters because the chip is 46 pt at 7 pt type — a measured content constraint, pinned by a test |
| List | per-row **Ghi** button (`recordingButton`), position name, and a statement of what a **single click** does for buttons 3/4/5 | `DeviceCapabilityModel.passthroughNoteKey` — the engine takes only the hold trigger and the optional scroll button, so a plain click on 3/4 still reaches the app |
| List | **firmware-handled controls** (scroll-mode / DPI / profile) listed with the measured half separated from the inferred half | the descriptor declares five usages; those three controls are not among them (observation), and firmware handling is the usual explanation (inference, worded as such) |
| Prompt | `underReportedControls(...)` — fires on **either** a press the descriptor never declared **or** fewer declared controls than positions *while* a vendor page declares extras | keeps the v9.1 rule that the prompt is never noise on a mouse that simply has fewer buttons |

### A third bug found while wiring R2: the tilt switch revealed arms it never enabled

R2 requires tilt to "render separately, not count into the button list". While wiring that, a grep
for the two tilt fields turned up this:

```
GestureEngine.swift:607        if type == .scrollWheel, configuration.tiltEnabled {   ← the engine
GestureController.swift:89     if let v = env.tiltEnabled { out.tiltEnabled = v }    ← decode only
MouseGesturesDetailView.swift  set: { v in controller.update { $0.tiltAvailable = v } }  ← the switch
```

**Nothing ever wrote `tiltEnabled`.** The page's single switch wrote `tiltAvailable`, which only
decides whether the two arms are *drawn*, while the engine gates on `tiltEnabled`. So the user
could turn the switch on, assign an action to *nghiêng trái*, and the action could never fire —
and turning the switch off left the engine's state untouched. This is exactly the class AGENTS.md
Part 3b keeps a register for (a stored key with no writer) and Part 0 §6 forbids (a control that
cannot do what its label says).

Fixed in the UI layer, with the engine untouched: `TiltArmsVisibility.fields(forReveal:)` is the
**pure, tested** contract for what the one switch writes, and it writes both fields. The label
changed from *"Hiện hai hướng nghiêng con lăn"* (show) to *"Bật hai hướng nghiêng con lăn"*
(turn on), because showing was all it used to do. The two fields stay **separate in the model** —
`MouseGestureTests.testTiltArmsAreHiddenByDefault` still pins that — so an older payload with only
`tiltAvailable` still decodes and still means "off".


### Measured this round

| Check | Result |
|---|---|
| Debug build | `BUILD SUCCEEDED`, **0** `error:` lines, `lipo -archs` = **arm64** |
| Changed sources present in the compile log **by name** | `MouseGesturesDetailView`, `MouseDiagramView`, `GestureButtonList`, `DeviceCapability`, `DeviceCapabilityTypes`, `DeviceCapabilityModel`, `GestureLabelStructure` — all 7 found |
| New warnings in the changed files | **none** |
| Logic tests | **183 tests, 0 failures** (was 176; +7 new) |
| L10n coverage / duplicates | `TOTAL 0` across **1 097** entries (was 1 074; +23 new, 1 re-scoped to `fragment`, 2 removed) |
| §2 sweep — unwrapped Vietnamese literals in `Views/` | `TOTAL 0` |
| §3 sweep — every `L10n.t("…")` key the gesture UI uses exists | `keys used: 169 | missing: 0` |
| Mutation harness (`mutation-check-gesture-buttons.sh`) | **11/11 RED** (M1–M5 from v9.1, M6–M11 new), source restored **byte-identical**, post-restore suite **183/0** |
| Probe script compiles and runs | yes — reaches the device list; returns `(no elements)` because of the permission state above |
| `git status` for leftover mutations | clean (the harness's post-run hash check confirms byte-identical restore) |
| **Probe returns 6 buttons over USB and BLE** | ❌ **not measured — mouse not connected, and the shell has no Input Monitoring grant** |
| **Sniper logs Button 5 / Record stores it** | ❌ **not measured — needs the mouse** |
| **Button 3/4 single click fires back/forward** | ⚠️ **code-read only.** The engine's `otherMouseDown` path returns `pass` for any button that is neither the trigger nor the enabled scroll button, so a click on 3/4 is forwarded. Not re-measured on hardware this round |
| **Rendered page in either language** | ❌ **not measured — `AXIsProcessTrusted` is false for this shell** |

recorded as a limitation of the round, not as a result.



### The five new injected bugs (M6–M10)

| | Bug injected | What caught it |
|---|---|---|
| M6 | vendor scan loses its usage-range guard, admitting the 1753 `0xFFFFFFFF` sentinels | `testVendorPageButtonElementsAreEvidenceAndTheSentinelUsageIsExcluded` |
| M7 | `diagramStyle` always returns `.archetype` | `testDiagramStyleFallsBackToGenericForADeviceWithFewButtons` |
| M8 | `MouseControlSlot.positionKey` returns a sentence instead of a store key | `testEveryArchetypePositionHasACaptionKeyThatFitsItsChip` **and** `L10nTests.testGesturePageStringsAreAllTranslatable` |
| M9 | the raw dump stops listing the vendor page | `testElementDumpReportsTheRawFactsBeforeAnyFilter` |
| M10 | the under-report prompt fires without evidence | `testUnderReportedPromptNeedsEvidence` |

M8 catching in **two** places is the useful part: the caption is rendered as
`L10n.t(slot.positionKey)`, so a rendered sentence would show in the English UI and no literal
sweep could see it. The vocabulary enumeration in `L10nTests` is what closes that hole, and M8 is
the proof that the closure works.

### Still needs a human, with the exact steps

1. **Connect the Basilisk** (USB or Bluetooth) and open *Chuột & cử chỉ*. The line under
   *Chuột đang kết nối* reads `XFinder đọc trực tiếp mô tả HID của chuột: N nút.` — that `N` is
   the measurement R1 asks about. Open **Mô tả HID thô** below it to see the raw pages.
2. **Press the Sniper button.** If the page shows *"Nút bạn vừa bấm: N"*, that is the number, and
   the warning offers *Đặt làm nút giữ*. If **nothing** appears, the button is firmware-only and
   no API will ever see it — the page already lists that case under *Nút do chuột tự xử lý*.
3. **Confirm the diagram** shows the controls at the reference positions with their captions, and
   that a one-button device falls back to the generic figure.
4. To re-run the raw probe from a terminal, grant that terminal **Input Monitoring** first;
   without it the probe exits at `kIOReturnNotPrivileged` exactly as recorded above.

---

## Round 9 — the v10 build re-verified, and the BLE question answered (2026-09-23)

Trigger: *"the feature page shows nothing, build the app again and test the feature"*. No product
source changed in this round; it is a verification pass plus one gate hardening. **Every ❌ row in
the Round 8 table above is superseded here.**

### Why the page looked empty: the installed build was old

`/Applications/XFinder.app/Contents/MacOS/` was stamped **12:54**; the v10 sources are
**14:23–14:41**. The user was reading the *previous* build. After
`sh scripts/install-mouse-rebuild.sh`, `probe-ax-dump.swift` reads the page in full:

| | English | Tiếng Việt |
|:--|--:|--:|
| text nodes / buttons | 128 / 40 | 128 / 40 |
| lines containing Vietnamese diacritics | **1** — `App Exposé` (allowlisted) | 120 |

Every v10 element is present: the `Ready — the applications below already have shortcuts` block,
`Connected mouse · Detected · BSKV3P 35K · 5 buttons`, the **Raw HID descriptor** disclosure, the
per-row **Record** button, the position captions, and the *Buttons the mouse handles itself* rows.
The eight strings identical in both languages are all legitimate: `App Exposé`, `Mission Control`,
`Quick Look`, `BSKV3P 35K`, and the four chord glyphs `⌃↑ ⌃↓ ⌃← ⌃→`.

**So "the page shows nothing" and "the English UI leaks Vietnamese" both fail to reproduce on the
v10 build.** The first had a mundane cause, and the fix is procedural: install before believing a
UI report.

### The probe, finally measured — over BLE the answer is 5, with no vendor page

The mouse is connected, over **Bluetooth Low Energy**. `docs/probes/probe-hid-raw.swift` opens
(`IOHIDManagerOpen kIOReturn: 0`) and dumps elements:

```
raw device count BEFORE dedupe: 4        (2 physical devices, listed twice — dedupe required)
BSKV3P 35K   transport: Bluetooth Low Energy   vendorID 0x68E   productID 0xD8   898 elements
  page=0x0009 type=0x02 ×5    usages [1,2,3,4,5]  → event buttons [0,1,2,3,4]
  vendor scan (page >= 0xFF00, type 0x02, usage 1...0x3F): []   ← empty
  no 0xFF00 element of any kind → nothing to widen the filter to
```

So **the Sniper button emits no HID button element over Bluetooth.** It is firmware-only on this
transport, and no filter change can reveal it — widening the scan would only re-admit the
`0xFFFFFFFF` sentinels that `DeviceCapabilityTests` exists to reject. `probe-hid-raw` prints the
honest summary itself: *"the figure has 6 positions and this descriptor declares 5. XFinder reports
that as a fact and offers Record; it does NOT invent a number."* The page renders exactly that:
`Detected · BSKV3P 35K · 5 buttons`, and `Button 6 — Not declared` with a **Record** button.

**"Probe returns 6 buttons over USB and BLE" is false for BLE.** USB remains untested (no cable).
If it is ever measured and differs, that is a *second* row, not a correction of this one.

### Measured this round

| Check | Result |
|---|---|
| Debug build | `BUILD SUCCEEDED`, **0** `error:`, `lipo -archs` = **arm64** |
| Gesture sources present in the compile log by name | **19/19** |
| Logic tests | **183 tests, 0 failures** |
| L10n coverage / duplicates | `TOTAL 0` across **1 097** entries |
| §2 sweep (unwrapped VI literals) / §3 sweep (gesture UI keys) | `TOTAL 0` / `170 keys, 0 missing` |
| `check-sidebar-groups-l10n.py` / `audit-gesture-vocabulary-l10n.py` | 0 problems / 63 keys + 20 names, 0 unresolved |
| Runtime harness | **PASS** — production callback (click replay, recursion, browser shortcut, deadzone, cancellation, modifier, passthrough) + system actions post the machine's own chord with the fn mask intact |
| Runtime harness `--live-tap` | **PASS** — real tap install/remove and simulated-timeout recovery |
| Mutation harnesses, **run sequentially** | buttons **11/11 RED** · labels **5/5 RED** · ui **7/7 RED** · l10n **6/6 RED**; all sources restored byte-identical; post-restore suite **183/0** |
| Install | signed with the stable `XFinder Dev` identity; `XFinderSync.appex` registered **and enabled** (`pluginkit` prints `+`) |
| Rendered page, both languages | **measured** — table above |
| **Physical gesture dispatch** | ❌ **not verified** — needs a human eye on Mission Control / Space change |

### New trap: the mutation harnesses must not run in parallel

They mutate the **real** tree. Four `nohup … &` in one shell produced false reds that look exactly
like real findings: `mutation-check-gesture-labels.sh` reported `FAIL: baseline is not green —
failing test cases: 6` (alone: baseline 0, 5/5 RED) and `mutation-check-l10n.sh` reported
`suite green again after restore: 2 failures` (alone: 183/0). The tree was never left dirty — each
script traps `EXIT` and restores from `/tmp` backups — but **a parallel run manufactures false
reds**, and "baseline is not green" is also the signature of a genuine stranded mutation. Run them
**one at a time**, detached, polling the log.

### Gate hardened

`mutation-check-gesture-ui.sh` ended with `echo "Executed $(total) tests"` — a count with no failure
figure, so a stranded mutation would end the script looking green. It now computes the failure count
and **exits 1** when nonzero, matching its two siblings. Proven both ways with a scratch test file
(one `XCTFail`): `184 tests, 1 failure(s)` → exit **1**; after deleting it, `183 tests, 0
failure(s)` → exit **0**. The scratch file was removed immediately.

### Housekeeping

Four LaunchServices registrations still named non-installed `/tmp` build directories
(`xf-out`, `xfinder-l10n-build`, `xfinder-v10-build`, `xf-gate-out`), all claiming the same plug-in
identifier as the installed appex. Deregistered with `lsregister -u`; the install script's own check
now reports clean. The script only deregisters its own `$SRC`/`$STAGE`, so this recurs with each new
build directory.

---

## PATCH v10.1 — Razer figure parity, chip numbers, and the debug gate (2026-09-24)

Scope, as the brief set it: **probe + UI only. Gestures logic frozen.** That freeze is verified, not
asserted — `git diff --name-only` shows `GestureEngine.swift`, `GestureController.swift`,
`GestureModel.swift`, `GestureMap.swift` and `SpaceBinding.swift` are **not** modified. Trigger,
deadzone, fire-on-release, and the preset tables are untouched.

### What the brief asked for, and which parts were already done

The brief's R1 (probe scans Button page `0x09` **and** Vendor page `0xFF00`, logs raw
UsagePage/Usage, emits `CapabilityDescriptor { buttons[], tiltSupported, source }`) and R3 (the
"Buttons XFinder can see" list with 1/2 locked to click-only, 3 marked as the hold button, 4/5/6
offering Record and Use-as-hold, plus the E/F/M "handles itself" rows) were **already satisfied by
v10** — verified by reading the source and by the rendered page, not assumed. The genuine deltas
were four:

1. the mouse body was a **pill** (`RoundedRectangle`, corner radius ≈ half its width) — the Magic
   Mouse silhouette the user reported;
2. the hold badge printed the **descriptive name** (`Middle click`) while the chips beside it
   printed numbers, so one screen used two vocabularies for the same control;
3. a chip the descriptor did not declare was drawn as a **live** control;
4. the "What XFinder received" block still rendered, because it was gated on
   `DEBUG_SHOW_ENGINE_LOG || config.debug` and the live config had `debug = true`.

### The four changes

| # | Change | Where |
|:--|:--|:--|
| 1 | `MouseSilhouette` — the outline in `MouseFigureOutline.points`, drawn as a closed Catmull-Rom curve; a **button seam**, a **wheel in that seam**, and a **thumb rest** in the lower-left carrying the three side controls | `GestureUIDisplay.swift` (pure data), `MouseDiagramView.swift` (the shape) |
| 2 | The badge, the Quick-check row and the Switches row print the **user-facing number** (`Button 3`) — the same vocabulary as the chips. The descriptive name stays in the tooltips, the list rows and the explanation sentences | `MouseDiagramView.swift`, `MouseGesturesDetailView.swift`, `GestureDetailPanel.swift` |
| 3 | `MouseButtonRole.isDeclared` — the **drawing's** question, deliberately not the same as `isAssignable`. `.notDeclared` and `.unknown` chips are disabled with a tooltip; the row below keeps its Record button | `DeviceCapabilityModel.swift`, `MouseDiagramView.swift` |
| 4 | The activity section renders on `DEBUG_SHOW_ENGINE_LOG` **alone**. The switch that enables the engine's diagnostic ring lives *inside* that section, so gating the section removes the switch with it — nothing is left promising anything | `MouseGesturesDetailView.swift` |

Change 4 corrects a reasoning error in the earlier design, and the correction is worth recording:
the old comment justified `|| config.debug` by saying a compile-time gate "would leave a control
that promises something it cannot do". The control in question is **inside the gated section**, so
that concern never applied — and what the `||` actually did was let a stored `debug = true` keep a
developer block on a user's page.

Change 1's two load-bearing properties are **numbers**, so they are testable: the widest point on
the **left** sits lower than the widest point on the **right** (that offset *is* the thumb rest),
and the thumb rest is in the lower-left. `MouseFigureTests` pins both, plus the blunt front (the two
main-button chips are 46 pt wide on a 116 pt body, so a narrow "nose" would leave them floating).

### Measured on the real hardware this round

The Basilisk reconnected over **Bluetooth Low Energy** during this pass, so the v10 figure was
re-read on live hardware:

```
BSKV3P 35K   transport: Bluetooth Low Energy   vendorID 0x68e   productID 0xd8
  page=0x0009 type=0x02 ×5    usages [1,2,3,4,5]  → event buttons [0,1,2,3,4]
  v10 vendor scan (type 0x02 && page >= 0xFF00 && usage 1...0x3F): []      ← empty
  v10 figure: archetype (6 positions) — "declares 5"
```

**Five buttons over BLE, no vendor-page button element.** The Sniper is firmware-only on this
transport, which is what the page already says under *Buttons the mouse handles itself*. **"The
probe must return 6 buttons" is false for BLE** — this is the third independent reading of the same
number, so do not re-open it. USB remains unmeasured (no cable).

The Apple Internal Keyboard / Trackpad, read in the same run, declares buttons `[1,2,3]` **and one
vendor-page button element (usage 12)** — the 1753 `0xFFFFFFFF` sentinel elements are still
correctly excluded by the range guard. That is the "1 vendor element" the page can print, and it is
real: with 3 declared controls and a vendor page, `underReportedControls` fires on evidence.

### Four results, kept separate

| Statement | Result |
|:--|:--|
| Build | `BUILD SUCCEEDED`, **0** `error:`, all gesture sources present in the compile log **by name**, `lipo -archs` = **arm64** |
| Tests | **193 tests, 0 failures** (+10: 8 `MouseFigureTests`, 1 `isDeclared`, 1 `isLive`) |
| L10n gates | coverage `TOTAL 0` / **1097** · duplicates 0 · literal sweep 0 · sidebar groups 0 · vocabulary 63 keys + 20 names, 0 unresolved · `verify-gesture-ui.sh` §1–§7 green · runtime-in-installed-bundle **TOTAL 0 leaks** |
| Mutation harnesses, sequentially | buttons **13/13 RED** (M12/M13 new) · labels **5/5 RED** · ui **8/8 RED** (BUG 8 new) · l10n **6/6 RED**; every source restored byte-identical; post-restore **193/0** |
| Rendered page, English | 122 text nodes; **1** diacritic line (`App Exposé`, allowlisted); `Button 1…Button 6` chips; `Hold, Button 3, click to change`; `Hold button: Button 3`; `Button 6 — Not declared…`; **0** tilt arms; **no** "What XFinder received" block |
| Rendered page, Tiếng Việt | 122 diacritic lines; same structure; no debug block |
| Install | signed with the stable `XFinder Dev` identity; `XFinderSync.appex` registered **and enabled** (`pluginkit` prints `+`) |
| **Physical gesture dispatch** | ❌ **not verified** — still needs a human eye on Mission Control / a Space change |

Both languages were measured with `defaults write com.xfinder.app AppLanguage …` and
`docs/probes/probe-ax-dump.swift <pid>`, then the setting was restored to `english`. The dump needs
the window **frontmost** — a background launch reports `windows: 0`, which is a measurement
artifact, not an empty page.

### New gate: the L10n entry script refuses to lie about its own counts

`add-gesture-l10n-entries.py` reported `added 5, replaced 0, removed 5` on **every** run, including
a second run on an unchanged store — so its "idempotent" claim was untestable. Cause: **five keys
were listed in both `ENTRIES` and `REMOVED`**, so they were added and then deleted in the same pass.
The store was never wrong (`REMOVED` wins), which is exactly why it went unnoticed — a report that
never reaches zero is a report nobody reads.

Fixed by deleting the five retired keys from `ENTRIES`, and by adding a **self-check** that prints
`CONFLICT: N key(s) are in BOTH ENTRIES and REMOVED` and **exits 1**. Proven in both directions:
with a deliberate conflict → `exit 1`; clean → `exit 0` and `added 0, replaced 0, removed 0`.

### Two more copy defects found by reading the rendered page

* **A sentence pointed at a block that is no longer rendered.** The frontmost row ended
  "…and try again — this is why the log below shows only com.xfinder.app", and the log block is now
  gated off. Reworded rather than left dangling: copy that names a control which is not on the page
  is the same class of problem as a control whose label lies.
* **"1 button elements".** The vendor-page count was spliced into the *middle* of the sentence, so
  English read `also declares 1 button elements on…`. The count now ends the clause
  (`also declares button-typed elements on the vendor's own page: 1.`), which is correct for every
  value in both languages. Both halves are `fragment` scope because both are concatenated with a
  runtime number — `check-l10n-coverage.py` rejects edge padding on a `sentence`.

### A third defect, found by reading the **persisted config** rather than the code

`defaults export com.xfinder.app -` then `plistlib` showed the store still holding:

```
tiltAvailable = true, tiltEnabled = false
```

That is a state the current UI cannot produce — PATCH v10 made the one tilt switch write **both**
fields (`TiltArmsVisibility.fields(forReveal:)`) — but the build before it wrote only
`tiltAvailable`, and the payload survived. Reading `tiltAvailable` alone then drew **two arms that
could never fire** *and* showed the switch as **on**: the same "control that cannot do what its
label says" the write-side contract exists to prevent, one layer down. On the rendered page that
was two live-looking controls with no possible effect.

Fixed with the **read**-side contract, in the same pure file and with no engine change:
`TiltArmsVisibility.isLive(available:enabled:)` is the conjunction, and the page reads it for the
arms, the switch and the explanation. **No migration is needed** — a payload that disagrees with
itself simply reads as off until the user turns the switch on again. `BUG 8` in
`mutation-check-gesture-ui.sh` injects the single-field read and goes red.

After the fix, the rendered page on this machine draws **0** tilt arms (measured: `Tilt the wheel`
appears 0 times) while the switch is still offered, which is the truthful state — the arms can never
fire on this hardware anyway, and the page's own copy says so.

### Docs corrected, because a stale doc teaches the next round the old bug

`docs/MOUSE_GESTURES.md` still described the **removed** L1 behaviour — "the button number is
printed on each arrow of the diagram" — which is the exact bug this feature was fixed for. Also
corrected: the old table that showed the UI as `Nút 1 (chuột trái)` (that parenthetical form is
gone), the two instructions that told the reader to enable the now-hidden log to read a button
number (they now point at the **"Nút bạn vừa bấm"** row, which is not gated), and `README.md`'s
"the page also has a *What XFinder received* section" plus its stale `162 test` figure.

### Still open

* **Instant Action for buttons 3/4/5** is still **not** shipped, and the reason is unchanged: the
  engine takes only the hold trigger and the optional scroll button, so a single click on 3/4 is
  forwarded to the application. A row offering to rebind it would be a control that cannot do what
  its label says. The row *states* what the click does instead. v10.1's acceptance list does not ask
  for it.
* **Physical dispatch** — the engine posts the machine's own chord and the tap is armed, but whether
  macOS actually opens Mission Control / changes Space needs an eye on the screen.
  `probe-screen-diff.swift` **changes Spaces for real**, so it runs only with the user's consent.
