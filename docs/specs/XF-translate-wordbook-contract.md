# Native Translate / Wordbook / Blueprint workspace — owner update 2026-10-29

Source: owner pasted Trancy Air Architecture & Prompt Blueprint Studio requirements while improving XFinder Translate. Interpret this as native XFinder feature expansion; reuse existing Voice refiners/Keychain, Apple Translation and Dictionary Services. Do not create an unrelated web app or claim unseen video parity. Four cited videos are not attached. Installed Trancy.app REA plist is version7.9.4 build68, bundle org.trancy.extension.trancy-ios-extension, not established as Trancy Air desktop; do not conflate artifacts.

Deliver staged commits on this branch. No push. Keep existing Translate native-dismiss fix 3944f0a and tested Space fixes 6e6ed90.

## Step 1 — durable pure core

New VocabularyLibrary.swift (Foundation only) and VocabularyStore.swift (Foundation+Observation), tests/symlinks, four project entries per new compiled file. Model wordbooks, vocabulary lexical fields (term, language, syllables, US/UK IPA, definitions, examples, synonyms, etymology, CEFR optional), context, dates and review state. Local Application Support/XFinder/Wordbook JSON with atomic primary+backup writes, visible error on failure, recovery from valid backup, refuse silent overwrite when both corrupted. No existing SQLite schema/migration touched. JSON merge import and complete export; UTF8 Anki note TSV with safe field escaping and explicit distinction from transferring scheduler state. Prompt blueprint customizations included in full JSON backup.

Pure SM2: EF initial2.5/floor1.3, grades Again0/Hard3/Good4/Easy5. Success intervals first1day/second6days/later ceil(previous*EF), EF formula from original SM2; Again is explicit 10-minute learning retry extension with repetitions reset. Never present this as exact Anki scheduling. Bounded numbers/dates/strings, deterministic clock injection, due/mastered counts from actual state, no inferred CEFR/frequency/IPA. Language EN/VI default, ZH/JA/KO recognized; retain unknown when unsupported.

## Step 2 — native workspace and quick entry

Add native Wordbook workspace accessed from Smart Selection settings and Translate panel; input selected text without automatically saving it. Words/decks, definition detail, pronunciation (native speech fallback), save/edit, due review (answer flip then four grades), JSON import/export and Anki TSV. Five editable prompt blueprint modules (definition, contextual translation, dictation cleanup, grammar, Anki generator), reset and export MD/JSON; live test uses configured Voice refiner via direct RefineRequest messages, not microphone/dictation side effects. Validate structured definitions before saving; model output cannot execute tools or act as instructions. No fake successful AI analysis or fabricated linguistic fields. Explicit Analyze action sends only the provided text/context to configured provider. Missing/refused provider has an explanation and route to existing Voice settings. Cancel stale requests/results when selection/module changes. No new credential storage/provider configuration duplicate.

## Cloud boundary

Owner asked Firestore+local persistence; Firebase project/auth/backend configuration is not provided. Optional user question pending. Native local persistence/export is independently useful and proceeds first. Do not add a fake cloud sync switch/status or embed credentials. Record exact remaining configuration needed for actual Cloud step and continue once provided. No spontaneous Firebase project provisioning or public deployment.

## Failures / acceptance

Empty/long mixed-language input; unavailable dictionary/provider/voice/network; invalid/truncated AI JSON; malformed/oversized import; duplicate term/book; disk full/denied; corrupt primary/backup; app restart; repeated click; source changes while request runs; no due cards; invalid EF/date/count from import; overdue timezone/calendar changes. User strings localized add-only; no polling, secrets or selected-text logging. Pure core/parser/export tests with RED mutations; build, full tests/audits, pbx lint/compiled evidence, installed hash, live save/reopen/review/export and async cancel where possible, each reported separately. No claim of cloud or native translation popover acceptance until actually verified.

Primary references: https://super-memory.org/archive/english/ol/sm2.htm ; https://docs.ankiweb.net/importing/text-files.html ; https://ai.google.dev/gemini-api/docs/models ; https://ai.google.dev/gemini-api/docs/speech-generation . Model IDs follow configured provider and verified API availability, not hardcoded assumptions from the supplied draft.

## Write ordering and quit safety

Store mutations are serialized on the main actor and persisted before publication. Prompt edits enqueue durable saves without debounce; save failure remains visible. Application termination waits for queued writes after the existing Browser quit confirmation. Window close cancels AI/speech but does not cancel pending writes. Verify rapid concurrent edits do not drop previous mutations.
