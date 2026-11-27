# Dynamic Island Teleprompter

Use references 12, 18 and 25 for the reading workflow and XFinder's own visual style. Add an editor and a reader with play, pause, restart, speed and font controls. A separate reader window opens below the top edge of the active display. Preserve the reading position when switching surfaces. Escape closes the reader. Keep the script local. The tool needs no permissions or network.

The worker owns new Teleprompter files under `XFinder/Core/Notch/`, `XFinder/Views/NotchTeleprompterPage.swift` and Teleprompter tests. Return new localization entries separately. The coordinator owns the catalog toggle, router, project and shared localization file.

Cover empty text, large scripts, invalid saved settings, edits during playback, reaching the end, closing the Island, disabling the tab, closing the reader, sleep, display changes and Reduce Motion. Advance only while a reader is visible and playing. Report build, tests and Atlas results separately.
