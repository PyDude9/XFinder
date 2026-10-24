import SwiftUI

/// XF-T28 cluster E — the operations popover: one row per job (state, progress, speed, ETA), per-job controls, and
/// queue-wide Tạm dừng tất cả / Tiếp tục tất cả.
struct OperationsPanelView: View {
    let queue: FileOperationQueue

    var body: some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
            header
            if queue.queue.jobs.isEmpty {
                Text(L10n.t("Không có việc nào"))
                    .font(XFinderTokens.Font.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, XFinderTokens.Space.row)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(queue.queue.jobs) { job in
                            jobRow(job)
                            if job.id != queue.queue.jobs.last?.id {
                                SettingsDivider()
                            }
                        }
                    }
                }
                .frame(maxHeight: 320)
            }
            if let errorKey = queue.lastErrorKey {
                Text(L10n.t(errorKey))
                    .font(XFinderTokens.Font.caption)
                    .foregroundColor(.red)
            }
        }
        .padding(XFinderTokens.Space.row)
        .frame(width: 360)
    }

    private var header: some View {
        HStack {
            Text(L10n.t("Hàng đợi thao tác"))
                .font(XFinderTokens.Font.sectionTitle)
            Spacer()
            Button(L10n.t("Tạm dừng tất cả")) { queue.pauseAll() }
                .font(XFinderTokens.Font.caption)
            Button(L10n.t("Tiếp tục tất cả")) { queue.resumeAll() }
                .font(XFinderTokens.Font.caption)
        }
    }

    @ViewBuilder
    private func jobRow(_ job: FileJob) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title(for: job))
                    .font(XFinderTokens.Font.row)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text(stateLabel(job.state))
                    .font(XFinderTokens.Font.caption)
                    .foregroundColor(.secondary)
            }

            if job.bytesTotal > 0 {
                ProgressView(value: Double(job.bytesDone), total: Double(job.bytesTotal))
                    .progressViewStyle(.linear)
            }

            HStack {
                if let speed = queue.speed, job.state == .running {
                    Text(ByteCountFormatter.string(fromByteCount: Int64(speed), countStyle: .file) + "/s")
                        .font(XFinderTokens.Font.caption)
                        .foregroundColor(.secondary)
                }
                if let eta = queue.eta, job.state == .running {
                    Text(etaLabel(eta))
                        .font(XFinderTokens.Font.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                jobControls(job)
            }

            if job.state == .failed {
                Text(L10n.t(job.errorKey ?? "Không đọc được thư mục này"))
                    .font(XFinderTokens.Font.caption)
                    .foregroundColor(.red)
                if let detail = job.errorDetail {
                    Text(detail)
                        .font(XFinderTokens.Font.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .settingsRow()
    }

    @ViewBuilder
    private func jobControls(_ job: FileJob) -> some View {
        HStack(spacing: XFinderTokens.Space.tight) {
            switch job.state {
            case .running, .pausing:
                Button(L10n.t("Tạm dừng")) { queue.pause(job.id) }
                    .disabled(!FileOperationRules.canPause(job.state))
                Button(L10n.t("Dừng")) { queue.cancel(job.id) }
            case .paused:
                Button(L10n.t("Tiếp tục")) { queue.resume(job.id) }
                Button(L10n.t("Dừng")) { queue.cancel(job.id) }
            case .verifying, .finishing:
                Button(L10n.t("Tạm dừng")) { queue.pause(job.id) }
                    .disabled(true)
                Button(L10n.t("Dừng")) { queue.cancel(job.id) }
            case .waiting:
                Button(L10n.t("Chạy kế tiếp")) { queue.runNext(job.id) }
                Button(L10n.t("Lên")) { queue.moveUp(job.id) }
                Button(L10n.t("Xuống")) { queue.moveDown(job.id) }
                Button(L10n.t("Dừng")) { queue.cancel(job.id) }
            case .done, .failed, .cancelled:
                EmptyView()
            }
        }
        .font(XFinderTokens.Font.caption)
        .buttonStyle(.borderless)
    }

    private func title(for job: FileJob) -> String {
        let kind: String
        switch job.kind {
        case .copy: kind = L10n.t("Sao chép")
        case .move: kind = L10n.t("Di chuyển")
        case .duplicate: kind = L10n.t("Nhân bản")
        case .trash: kind = L10n.t("Chuyển vào Thùng rác")
        }
        let count = job.itemsTotal > 0 ? job.itemsTotal : job.sources.count
        return "\(kind) \(count) \(L10n.t("mục"))"
    }

    private func stateLabel(_ state: JobState) -> String {
        switch state {
        case .waiting: return L10n.t("Đang chờ")
        case .running: return L10n.t("Đang chạy")
        case .pausing: return L10n.t("Đang tạm dừng")
        case .paused: return L10n.t("Đã tạm dừng")
        case .verifying: return L10n.t("Đang kiểm")
        case .finishing: return L10n.t("Đang hoàn tất")
        case .done: return L10n.t("Xong")
        case .failed: return L10n.t("Lỗi")
        case .cancelled: return L10n.t("Đã huỷ")
        }
    }

    private func etaLabel(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        return formatter.string(from: seconds) ?? ""
    }
}
