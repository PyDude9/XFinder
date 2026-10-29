# Live Group validation and refresh completion — owner continuation 2026-10-29

Base c6ce9c4 already implements the Space/footer/editor/model work. Do not duplicate it. Complete reliability and live acceptance.

Observed code risks: editor validates source using synchronous fileExists from body and permits a regular file/denied folder as a source; listing errors are rendered as empty groups; projection generation changes only on resubscribe so cached/disk deliveries can arrive out of order; old projection can publish after source removal/close. Name changes do not refresh invalid-name preview. Source input currently reads on every keystroke.

Use DirectoryLoadCoordinator as the source validity authority; show its actual error and disable Save until final successful directory read for current path. Debounce path editing with cancellable task (no polling), invalidate listing/projection generations on source change/failure/disappearance, and supersede projections per listing delivery. Empty matches remain valid. Show errors separately from empty. Keep model/schema/defaults/Space semantics unchanged. File chooser asynchronous, no new source files.

Verify source file/missing/denied states, empty match, scratch source watcher updates, source edit while projection runs, close/reopen editor, create/edit/remove membership, Space isolation and duplicate manual name feedback where GUI permits. Targeted existing pure model/controller tests; app build/full gate; installed hash; report live results separately. No push.
