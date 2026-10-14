import SwiftUI

/// P9 — the handoff preview. The message is built from the old session (`AgentHandoff`) and shown here in full: the
/// person reads it, can edit it, and only "Gửi" spends a model turn on the target (Notch Crew shows what it writes before
/// it writes it). Dark like the notch; same panel kind as "Sửa văn bản…".
@MainActor @Observable
final class AgentHandoffModel {
    var source: AgentKind = .claude
    var target: AgentKind = .claude
    var sourceName = ""
    var text = ""
    var loading = false
    var sending = false
    var turnCount = 0
    var noticeKey: String?
    var onSend: () -> Void = {}
    var onClose: () -> Void = {}
    var onRetarget: (AgentKind) -> Void = { _ in }
}

struct AgentHandoffView: View {
    @Bindable var model: AgentHandoffModel

    var body: some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
            header
            Group {
                if model.loading {
                    VStack(spacing: XFinderTokens.Space.tight) {
                        ProgressView().controlSize(.small)
                        Text(L10n.t("Đang đọc phiên gốc…")).font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    TextEditor(text: $model.text)
                        .font(XFinderTokens.Font.mono)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: XFinderTokens.Radius.control).strokeBorder(XFinderTokens.Fill.hairline))
            footer
        }
        .padding(XFinderTokens.Space.page)
        .frame(width: 600, height: 440)
        .onExitCommand { model.onClose() }
    }

    private var header: some View {
        HStack(spacing: XFinderTokens.Space.tight) {
            Image(systemName: "arrow.triangle.branch").foregroundColor(.secondary)
            Text(L10n.t("Chuyển phiên")).font(XFinderTokens.Font.sectionTitle)
            AgentBrandTile(kind: model.source, size: 16)
            Text(model.sourceName).font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                .lineLimit(1).truncationMode(.middle).frame(minWidth: 0, alignment: .leading).layoutPriority(-1)
            Image(systemName: "arrow.right").font(XFinderTokens.Font.caption).foregroundColor(.secondary)
            ForEach(AgentKind.allCases, id: \.self) { kind in
                Button { model.onRetarget(kind) } label: {
                    HStack(spacing: 4) {
                        AgentBrandTile(kind: kind, size: 14)
                        Text(kind.displayName).font(XFinderTokens.Font.caption)
                    }
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Capsule().fill(Color.primary.opacity(model.target == kind ? 0.14 : 0.04)))
                    .foregroundColor(model.target == kind ? .primary : .secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(kind.displayName)
            }
            Spacer(minLength: 0)
        }
    }

    private var footer: some View {
        HStack(spacing: XFinderTokens.Space.tight) {
            VStack(alignment: .leading, spacing: 2) {
                if let key = model.noticeKey {
                    Text(L10n.t(key)).font(XFinderTokens.Font.caption).foregroundColor(.orange)
                } else if model.target == .codex {
                    Text(L10n.t("Codex chưa có phiên không cửa sổ: XFinder chép lệnh mở Codex kèm tin này, bạn dán vào terminal."))
                        .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                } else {
                    Text("\(L10n.t("Gửi sẽ dùng một lượt của "))\(model.target.displayName)\(L10n.t(". Chỉ có lời bạn gõ và câu trả lời của agent — không có output của công cụ."))")
                        .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                }
                if !model.loading {
                    Text("\(L10n.t("Lượt đọc được: "))\(model.turnCount)")
                        .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(L10n.t("Hủy")) { model.onClose() }
                .keyboardShortcut(.cancelAction)
            Button(model.target == .codex ? L10n.t("Chép lệnh") : L10n.t("Gửi")) { model.onSend() }
                .keyboardShortcut(.defaultAction)
                .disabled(model.loading || model.sending || model.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
}
