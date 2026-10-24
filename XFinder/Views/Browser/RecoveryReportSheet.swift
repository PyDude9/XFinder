import SwiftUI
import AppKit

/// XF-T28 cluster E — shown once per launch when `queue.recovery` is non-empty: a list of operations the journal
/// says did not finish cleanly, each with "Xem trong Finder" and a per-item "Đã xem xong" that clears it.
struct RecoveryReportSheet: View {
    let queue: FileOperationQueue

    @State private var cleared: Set<String> = []
    @Environment(\.dismiss) private var dismiss

    private var remaining: [RecoveryItem] {
        queue.recovery.filter { !cleared.contains(recoveryKey($0)) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.section) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.t("Báo cáo khôi phục"))
                    .font(XFinderTokens.Font.sectionTitle)
                Text(L10n.t("Thao tác sau đây có thể đã bị cắt ngang. Xem lại trước khi coi là xong."))
                    .font(XFinderTokens.Font.caption)
                    .foregroundColor(.secondary)
            }

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(remaining, id: \.source) { item in
                        recoveryRow(item)
                        SettingsDivider()
                    }
                }
            }
            .frame(maxHeight: 360)

            HStack {
                Spacer()
                Button(L10n.t("Đóng")) {
                    queue.clearRecovery()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(XFinderTokens.Space.section)
        .frame(width: 520, height: 420)
    }

    private func recoveryRow(_ item: RecoveryItem) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.t(item.messageKey))
                    .font(XFinderTokens.Font.row)
                Text(item.source)
                    .font(XFinderTokens.Font.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let destination = item.destination {
                    Text(destination)
                        .font(XFinderTokens.Font.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Button(L10n.t("Hiện trong Finder")) {
                    NSWorkspace.shared.selectFile(item.destination ?? item.source, inFileViewerRootedAtPath: "")
                }
                Button(L10n.t("Đã xem xong")) {
                    cleared.insert(recoveryKey(item))
                }
            }
            .font(XFinderTokens.Font.caption)
            .buttonStyle(.borderless)
        }
        .padding(.vertical, XFinderTokens.Space.tight)
    }

    private func recoveryKey(_ item: RecoveryItem) -> String {
        "\(item.source)|\(item.destination ?? "")|\(item.messageKey)"
    }
}
