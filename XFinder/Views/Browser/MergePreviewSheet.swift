import SwiftUI

/// XF-T30 W6 — the Merge… preview: tallies (will copy / replace / skip / rename), the policy picker, Apply to All.
/// W6 builder (panel). `plan` is recomputed by the caller (`ConflictSheet`) whenever `policy` changes here — this
/// view only reports the policy the user picked, it does not call `FolderMerge.plan` itself (that belongs to the
/// pure F6 file this view does not own).
struct MergePreviewSheet: View {
    let plan: MergePlan
    @State private var policy: MergePolicy
    @State private var applyToAll = false
    let onPolicyChange: (MergePolicy) -> Void
    let onConfirm: (MergePolicy, Bool) -> Void
    let onCancel: () -> Void

    init(plan: MergePlan, initialPolicy: MergePolicy, onPolicyChange: @escaping (MergePolicy) -> Void,
         onConfirm: @escaping (MergePolicy, Bool) -> Void, onCancel: @escaping () -> Void) {
        self.plan = plan
        self._policy = State(initialValue: initialPolicy)
        self.onPolicyChange = onPolicyChange
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.section) {
            Text(L10n.t("Gộp thư mục"))
                .font(XFinderTokens.Font.sectionTitle)

            Picker(L10n.t("Khi trùng tên"), selection: $policy) {
                Text(L10n.t("Giữ cả hai")).tag(MergePolicy.keepBoth)
                Text(L10n.t("Bỏ qua")).tag(MergePolicy.skip)
                Text(L10n.t("Giữ bản mới hơn")).tag(MergePolicy.keepNewer)
            }
            .pickerStyle(.radioGroup)
            .onChange(of: policy) { _, newValue in onPolicyChange(newValue) }

            VStack(alignment: .leading, spacing: XFinderTokens.Space.tight) {
                tallyRow(L10n.t("Sẽ chép"), plan.willCopy)
                tallyRow(L10n.t("Sẽ thay"), plan.willReplace)
                tallyRow(L10n.t("Sẽ bỏ qua"), plan.willSkip)
                tallyRow(L10n.t("Sẽ đổi tên"), plan.willRename)
            }
            .font(XFinderTokens.Font.caption)

            if !excludedSteps.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t("Bỏ qua (không hợp lệ)"))
                        .font(XFinderTokens.Font.caption)
                        .foregroundColor(.secondary)
                    ForEach(Array(excludedSteps.enumerated()), id: \.offset) { _, step in
                        if case let .excluded(path, reason) = step {
                            Text("\((path as NSString).lastPathComponent)\(L10n.t(" — "))\(L10n.t(reason))")
                                .font(XFinderTokens.Font.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
            }

            Toggle(isOn: $applyToAll) {
                Text(L10n.t("Áp dụng cho tất cả"))
            }
            .toggleStyle(.checkbox)
            .font(XFinderTokens.Font.caption)

            HStack {
                Button(L10n.t("Dừng")) { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(L10n.t("Gộp…")) { onConfirm(policy, applyToAll) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(XFinderTokens.Space.section)
        .frame(width: 420)
    }

    private var excludedSteps: [MergePlan.Step] {
        plan.steps.filter {
            if case .excluded = $0 { return true }
            return false
        }
    }

    private func tallyRow(_ label: String, _ count: Int) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text("\(count)")
                .foregroundColor(.secondary)
        }
    }
}
