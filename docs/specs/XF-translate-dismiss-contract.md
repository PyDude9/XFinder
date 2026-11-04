# Selection translation dismissal — owner screenshot 2026-10-29

Trigger: close Apple's translation popover after translating; the transparent XFinder host remains on the source web page until another outside click. Source: TranslateSelectionView owns presented state with no dismissal callback; controller only hides the host on its own close/outside actions. Host root has no background.

Close the host when native popover ends without returning a replacement. Preserve the existing returned-translation Copy workflow after Replace. Controller close/Esc/outside/feature OFF must reset native presentation as well as hide the host. A late close from an older request must not close a newer selection. First show/reopen should present native translation after hosting. Give the host an opaque themed panel background so web content never bleeds through text. No translation/network provider change, no new permission or shortcuts.

Failure cases: first open; native close without result; replacement callback then native close; outside click while native popover is present; Escape/host close; feature OFF; repeated request while old popover closes; message-only unsupported/empty states; panel reused after dismissal. No polling or new app files.

Files: existing TranslateSelectionView, TranslateSelectionController, TranslateSelectionRules and tests. Pure dismissal decision tests + intentional mutation RED/restore GREEN; app build/tests/audits; install/hash; GUI native dismissal/host absence and reopen where actual selected text can be captured. State exact live limitations. No push.
