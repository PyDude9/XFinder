import SwiftUI

/// Stops a detail page from pushing the window wider than it is.
///
/// This app has hit the same bug four times (batch-rename preview rows, the
/// batch-rename segmented picker, long file-name rows, the sidebar jumping when
/// a long row is selected). The mechanism is always identical:
///
/// * SwiftUI asks each subview for its **ideal** width.
/// * Some controls report a large one — a `.segmented` picker sums every
///   label, a `Text` of a long path asks for the whole string.
/// * `NavigationView`'s split view honours that ideal, so the detail pane grows
///   and squeezes (or overlaps) the sidebar.
///
/// `minWidth: 0` alone never fixed it: that permits *shrinking* but leaves the
/// ideal width untouched. The load-bearing part is `maxWidth: .infinity`, which
/// makes the view claim a share of the offered width instead of demanding its
/// own.
///
/// Apply `.pageWidthSafe()` to the root container of every detail page.
struct PageWidthSafe: ViewModifier {
    func body(content: Content) -> some View {
        content
            // Order matters: clamp the ideal first, then let it fill.
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            // A page that still contains an over-wide control can scroll it
            // horizontally rather than resizing the whole window.
            .fixedSize(horizontal: false, vertical: true)
    }
}

extension View {
    /// See `PageWidthSafe`. Use on a detail page's outermost `VStack`.
    func pageWidthSafe() -> some View {
        modifier(PageWidthSafe())
    }

    /// For a single row that renders a file name or path.
    ///
    /// The standing rule recorded in CLAUDE.md: such a row always needs
    /// `minWidth: 0` **and** `maxWidth: .infinity`, plus truncation — otherwise
    /// one long name resizes the window.
    func fileNameRowSafe(alignment: Alignment = .leading) -> some View {
        self
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(minWidth: 0, maxWidth: .infinity, alignment: alignment)
    }
}
