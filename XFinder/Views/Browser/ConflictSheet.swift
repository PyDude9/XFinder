import SwiftUI

/// XF-T28 cluster E / XF-T30 W6 — the copy/move name-collision dialog: the two sides (source vs. destination), a
/// "Mới hơn" badge on whichever is newer, and the four resolutions (contract: Giữ cả hai default/Return, Bỏ qua,
/// Thay thế destructive/disabled when !replaceAllowed, Dừng/Esc), plus "Áp dụng cho tất cả" — and, folder vs folder
/// only, a "Gộp…" button that opens `MergePreviewSheet` through `FolderMergeController` (contract §2).
struct ConflictSheet: View {
    let prompt: ConflictPrompt
    let queue: FileOperationQueue

    @State private var applyToAll = false
    @FocusState private var defaultFocus: Bool
    @State private var mergePlan: MergePlan?
    @State private var mergePolicy: MergePolicy = .keepBoth
    @State private var isPlanningMerge = false
    @State private var showMergePreview = false

    private var bothFolders: Bool { prompt.source.isFolder && prompt.destination.isFolder }

    var body: some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.section) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.t("Đã có tệp trùng tên"))
                    .font(XFinderTokens.Font.sectionTitle)
                Text(L10n.t("Chọn cách xử lý cho mục này."))
                    .font(XFinderTokens.Font.caption)
                    .foregroundColor(.secondary)
            }

            HStack(alignment: .top, spacing: XFinderTokens.Space.section) {
                sideView(title: L10n.t("Mục đang chép"), side: prompt.source)
                sideView(title: L10n.t("Mục đã có"), side: prompt.destination)
            }

            if prompt.remaining > 0 {
                Toggle(isOn: $applyToAll) {
                    Text("\(L10n.t("Áp dụng cho tất cả"))\(L10n.t(" ("))\(prompt.remaining)\(L10n.t(" còn lại)"))")
                }
                .toggleStyle(.checkbox)
                .font(XFinderTokens.Font.caption)
            }

            HStack {
                Button(L10n.t("Dừng")) {
                    queue.resolveConflict(.stop, applyToAll: applyToAll)
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                if bothFolders {
                    Button(L10n.t("Gộp…")) { startMerge() }
                        .disabled(isPlanningMerge)
                }

                Button(L10n.t("Bỏ qua")) {
                    queue.resolveConflict(.skip, applyToAll: applyToAll)
                }

                Button(L10n.t("Thay thế")) {
                    queue.resolveConflict(.replace, applyToAll: applyToAll)
                }
                .foregroundColor(.red)
                .disabled(!prompt.replaceAllowed)

                Button(L10n.t("Giữ cả hai")) {
                    queue.resolveConflict(.keepBoth, applyToAll: applyToAll)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .focused($defaultFocus)
            }
        }
        .padding(XFinderTokens.Space.section)
        .frame(width: 440)
        .onAppear { defaultFocus = true }
        .sheet(isPresented: $showMergePreview) {
            if let plan = mergePlan {
                MergePreviewSheet(
                    plan: plan,
                    initialPolicy: mergePolicy,
                    onPolicyChange: { newPolicy in
                        mergePolicy = newPolicy
                        planMerge()
                    },
                    onConfirm: { policy, applyMergeToAll in
                        mergePolicy = policy
                        showMergePreview = false
                        // Folder-vs-folder is handled entirely by the merge run, not the ordinary copy/replace
                        // path below it — "Bỏ qua" here just steps the queue past this one conflict so it can
                        // move on to the next pending item (contract §2 "Gộp thư mục chạy qua cùng hàng đợi").
                        queue.resolveConflict(.skip, applyToAll: applyMergeToAll || applyToAll)
                        runMerge()
                    },
                    onCancel: { showMergePreview = false }
                )
            }
        }
    }

    /// "Gộp…": plans the merge off-main through `FolderMergeController.preview` (refused for nested folders or the same
    /// folder), re-plans when the policy changes, and runs the approved plan.
    private func startMerge() {
        isPlanningMerge = true
        FolderMergeController.shared.preview(source: prompt.source.path, destination: prompt.destination.path,
                                             policy: mergePolicy) { plan, _ in
            isPlanningMerge = false
            guard let plan else { return }
            mergePlan = plan
            showMergePreview = true
        }
    }

    private func planMerge() {
        isPlanningMerge = true
        FolderMergeController.shared.replan(source: prompt.source.path, destination: prompt.destination.path,
                                            policy: mergePolicy) { plan in
            isPlanningMerge = false
            mergePlan = plan
        }
    }

    /// Queues the merge with the confirmed policy; the queue re-plans at run time (the preview may be stale).
    private func runMerge() {
        FolderMergeController.shared.enqueue(source: prompt.source.path, destination: prompt.destination.path, policy: mergePolicy)
    }

    private func sideView(title: String, side: ConflictPrompt.Side) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(title)
                    .font(XFinderTokens.Font.caption)
                    .foregroundColor(.secondary)
                if side.isNewer {
                    Text(L10n.t("Mới hơn"))
                        .font(XFinderTokens.Font.caption)
                        .padding(.horizontal, 4)
                        .background(Capsule().fill(XFinderTokens.Fill.focus))
                }
            }
            Text((side.path as NSString).lastPathComponent)
                .font(XFinderTokens.Font.row)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(side.isFolder ? L10n.t("Thư mục") : ByteCountFormatter.string(fromByteCount: side.size, countStyle: .file))
                .font(XFinderTokens.Font.caption)
                .foregroundColor(.secondary)
            Text(side.modified, style: .date)
                .font(XFinderTokens.Font.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
