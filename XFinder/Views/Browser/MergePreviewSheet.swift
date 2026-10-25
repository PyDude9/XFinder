import SwiftUI

/// XF-T30 W6 — the Merge… preview: tallies (will copy / replace / skip / rename), the policy picker, Apply to All.
/// W6 builder (panel).
struct MergePreviewSheet: View {
    let plan: MergePlan
    let onConfirm: (MergePolicy) -> Void
    let onCancel: () -> Void

    var body: some View { EmptyView() }
}
