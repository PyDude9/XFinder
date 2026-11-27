# Dynamic Island fixes from the integrated review

Use the verified source findings in the Gemini Island review. Confirm each against the current checkout before changing it. Preserve user data and existing tab routes.

- Scratchpad must not write over unreadable content when opening, editing or closing. Give the user a localized retry action. Preserve bytes until a successful reload. Test a failed read, edit, clear, flush and recovery.
- Capture must hand off the requested operation exactly once after the panel hides. Own the in-flight token outside the transient view. Reject duplicate taps and invalid results after cancellation. Preserve permission behavior. Test unmount, repeated clicks, cancellation and retry without recording the user's desktop.
- The coordinator owns the shared Island controller, Teleprompter and Mirror lifecycle, Settings and integration. A hidden or sleeping Island must release the camera. Disabling Island must close the floating reader. Escape must respect the focused window. Re-clamp a pointer panel after display changes.
