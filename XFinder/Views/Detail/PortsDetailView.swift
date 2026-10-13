import SwiftUI

/// Cổng đang mở — *"something is holding port 3000: what is it, and can I stop it?"*
///
/// Rows come from `PortList` (pure, tested). The Stop button exists only where sending the signal
/// can work (the user's own process, not XFinder, not pid ≤ 1); other rows are SHOWN with the
/// reason instead of a button that would answer "operation not permitted".
struct PortsDetailView: View {
    @State private var manager = PortManager.shared
    @State private var query = ""
    @State private var pending: Pending?
    @State private var status: Status?
    @State private var stopping: Set<String> = []

    private struct Pending: Identifiable { let row: PortList.Row; let force: Bool; var id: String { row.id } }
    private struct Status { let text: String; let isError: Bool; let forceRow: PortList.Row? }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: XFinderTokens.Space.section) {
                PageHeader(icon: "point.3.connected.trianglepath.dotted",
                           title: L10n.t("Cổng đang mở"),
                           subtitle: L10n.t("Tiến trình nào đang giữ một cổng mạng, và có dừng được không."))

                HStack(spacing: 10) {
                    TextField(L10n.t("Lọc theo cổng hoặc tên tiến trình"), text: $query)
                        .textFieldStyle(.roundedBorder)
                    Button { Task { await manager.refresh() } } label: {
                        Label(L10n.t("Làm mới"), systemImage: "arrow.clockwise")
                    }
                    .disabled(manager.isLoading)
                }
                .padding(.horizontal, XFinderTokens.Space.page)

                if let status { statusBanner(status) }

                content
            }
            .padding(.bottom, XFinderTokens.Space.section)
            .pageWidthSafe()
        }
        .background(XFinderTokens.Settings.contentBackground)
        .task { await manager.refresh() }
        .alert(item: $pending) { p in
            Alert(title: Text(p.force ? L10n.t("Buộc dừng tiến trình?") : L10n.t("Dừng tiến trình?")),
                  message: Text(confirmMessage(p)),
                  primaryButton: .destructive(Text(p.force ? L10n.t("Buộc dừng") : L10n.t("Dừng"))) { run(p) },
                  secondaryButton: .cancel(Text(L10n.t("Hủy"))))
        }
    }

    // MARK: - Content

    @ViewBuilder private var content: some View {
        if let result = manager.result {
            if !result.scanSucceeded {
                note(L10n.t("Không đọc được danh sách tiến trình. Đây không phải là “không có cổng nào mở” — hãy bấm Làm mới."),
                     color: .orange)
            } else {
                let rows = PortList.filter(result.rows, query: query)
                if rows.isEmpty {
                    note(query.isEmpty ? L10n.t("Không có cổng nào đang lắng nghe.")
                                       : L10n.t("Không có cổng hoặc tiến trình nào khớp bộ lọc."),
                         color: .secondary)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                            rowView(row)
                            if index < rows.count - 1 { Divider().padding(.leading, XFinderTokens.Space.page) }
                        }
                    }
                    .padding(.horizontal, XFinderTokens.Space.page)
                }
                footer(count: result.rows.count)
                if result.uninspectable > 0 {
                    note("\(result.uninspectable)\(L10n.t(" tiến trình khác (của hệ thống hoặc người dùng khác) macOS không cho XFinder xem, nên cổng do chúng giữ có thể không hiện ở đây."))",
                         color: .secondary)
                }
            }
        } else {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(L10n.t("Đang đọc danh sách cổng…")).font(XFinderTokens.Font.rowValue).foregroundColor(.secondary)
            }
            .padding(.horizontal, XFinderTokens.Space.page)
        }
    }

    private func rowView(_ r: PortList.Row) -> some View {
        HStack(alignment: .center, spacing: XFinderTokens.Space.inline) {
            Text(String(r.port))
                .font(XFinderTokens.Font.mono)
                .frame(width: 64, alignment: .trailing)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(r.command).font(XFinderTokens.Font.row).lineLimit(1).truncationMode(.middle)
                    exposureBadge(r.exposure)
                }
                Text("PID \(r.pid) · \(r.owner?.user ?? "—") · \(r.addresses.joined(separator: ", "))")
                    .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

            if stopping.contains(r.id) {
                ProgressView().controlSize(.small)
            } else if r.canTerminate {
                Button(L10n.t("Dừng")) { pending = Pending(row: r, force: false) }
                    .controlSize(.small)
            } else {
                Label(L10n.t("Không dừng được"), systemImage: "lock.fill")
                    .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                    .help(L10n.t("Tiến trình này không thuộc về bạn (hoặc là hệ thống, hoặc chính XFinder) nên macOS không cho XFinder dừng nó."))
            }
        }
        .padding(.horizontal, XFinderTokens.Space.inline).padding(.vertical, 9)
    }

    private func exposureBadge(_ e: PortList.Exposure) -> some View {
        let (key, color, help): (String, Color, String) = {
            switch e {
            case .allInterfaces: return ("Mọi mạng", .orange, "Máy khác trong cùng mạng có thể kết nối tới cổng này.")
            case .localOnly:     return ("Chỉ máy này", .secondary, "Chỉ ứng dụng trên máy này kết nối được (loopback).")
            case .specific:      return ("Một địa chỉ", .secondary, "Lắng nghe trên một địa chỉ mạng cụ thể.")
            }
        }()
        return Text(L10n.t(key))
            .font(XFinderTokens.Font.caption).foregroundColor(color)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.14)))
            .help(L10n.t(help))
    }

    private func footer(count: Int) -> some View {
        HStack {
            Text("\(count)\(L10n.t(" cổng đang lắng nghe"))")
            if let t = manager.refreshedAt {
                Text("· \(L10n.t("cập nhật ")) \(t.formatted(date: .omitted, time: .standard))")
            }
        }
        .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
        .padding(.horizontal, XFinderTokens.Space.page)
    }

    private func note(_ text: String, color: Color) -> some View {
        Text(text).font(XFinderTokens.Font.rowValue).foregroundColor(color)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, XFinderTokens.Space.page)
    }

    private func statusBanner(_ s: Status) -> some View {
        HStack(spacing: 10) {
            Text(s.text).font(XFinderTokens.Font.rowValue).foregroundColor(s.isError ? .orange : .primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let row = s.forceRow {
                Button(L10n.t("Buộc dừng")) { pending = Pending(row: row, force: true) }.controlSize(.small)
            }
            Button { status = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: XFinderTokens.Radius.control).fill(XFinderTokens.Fill.inset))
        .padding(.horizontal, XFinderTokens.Space.page)
    }

    // MARK: - Actions

    private func confirmMessage(_ p: Pending) -> String {
        let head = "\(p.row.command) (PID \(p.row.pid))\(L10n.t(" đang giữ cổng "))\(p.row.port)."
        let tail = p.force
            ? L10n.t("Buộc dừng kết thúc tiến trình ngay, không cho nó lưu hay dọn dẹp.")
            : L10n.t("Mọi kết nối tới cổng này sẽ đóng và việc chưa lưu trong tiến trình có thể mất.")
        return head + "\n" + tail
    }

    private func run(_ p: Pending) {
        stopping.insert(p.row.id)
        status = nil
        Task {
            let r = await manager.stop(p.row, force: p.force)
            stopping.remove(p.row.id)
            let name = "\(p.row.command) (\(p.row.port))"
            switch r {
            case .stopped:
                status = Status(text: "\(name)\(L10n.t(" đã dừng.") )", isError: false, forceRow: nil)
            case .stillRunning:
                status = Status(text: "\(name)\(L10n.t(" chưa thoát sau 2 giây — nó có thể đang bỏ qua yêu cầu dừng."))",
                                isError: true, forceRow: p.force ? nil : p.row)
            case .refused:
                status = Status(text: "\(name)\(L10n.t(" không còn khớp với danh sách (đã thoát hoặc đổi chủ), nên XFinder không gửi gì. Danh sách đã được làm mới."))",
                                isError: true, forceRow: nil)
            case .failed(let m):
                status = Status(text: "\(L10n.t("Không dừng được: "))\(m)", isError: true, forceRow: nil)
            }
        }
    }
}
