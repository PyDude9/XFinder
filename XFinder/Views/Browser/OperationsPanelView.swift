import SwiftUI

/// XF-T28 cluster E / XF-T30 W6 — the operations popover: one row per job (state, progress, speed, ETA, stage
/// label), per-job controls, drag reorder + Run Next/Up/Down for waiting jobs, queue-wide Tạm dừng tất cả / Tiếp tục
/// tất cả, and a Sự cố (Problems) section for jobs that finished with an error.
///
/// Deviation (contract §2): the full per-item `ProblemsList`/`ProblemEntry` model (F6, pure) and its recording into
/// the queue's run loop (Q6, `FileOperationQueue.run`/`performItem`) are not wired yet — a `FileJob` today carries
/// one `errorKey`/`errorDetail` for the whole job, not one reason per failed item. The Sự cố section below is built
/// job-granular against what the queue has today; once Q6 records per-item failures into a real `problems:
/// ProblemsList` property, this section should bind to that instead. "Dismiss" (remove one Sự cố row without
/// touching the others) needs a new `FileJobQueue.removeJob(_:)` — not added here, since `FileOperationQueue.swift`/
/// `FileOperationRules.swift` are not this file's to edit; "Xoá hết" uses the existing `clearFinished()` instead
/// (clears every finished job, not only failed ones — the closest equivalent available today). `canRetry`/
/// "nearest surviving ancestor" are likewise not on `FileOperationRules` yet (not this file's to add), so both are
/// small local helpers here against the fields `FileJob` already has.
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
                jobList
            }
            if !failedJobs.isEmpty {
                SettingsDivider()
                problemsSection
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
            if queue.queue.jobs.count >= 2 {
                Button(L10n.t("Tạm dừng tất cả")) { queue.pauseAll() }
                    .font(XFinderTokens.Font.caption)
                Button(L10n.t("Tiếp tục tất cả")) { queue.resumeAll() }
                    .font(XFinderTokens.Font.caption)
            }
        }
    }

    // MARK: - Job list (drag reorder applies to waiting jobs only — the active job is pinned)

    private var jobList: some View {
        List {
            ForEach(queue.queue.jobs) { job in
                jobRow(job)
                    .settingsRow()
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets())
            }
            .onMove(perform: moveWaitingJobs)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .frame(height: min(320, CGFloat(queue.queue.jobs.count) * 72 + 8))
    }

    /// SwiftUI's `onMove` reports offsets into the WHOLE list; `FileOperationQueue` only reorders `.waiting` rows
    /// (the active row is pinned per contract §2 "kéo sắp xếp" applying to waiting jobs). A drag that touches the
    /// active/finished rows at all is a no-op rather than silently reordering the wrong thing.
    private func moveWaitingJobs(from source: IndexSet, to destination: Int) {
        let jobs = queue.queue.jobs
        guard let sourceIndex = source.first, source.count == 1 else { return }
        guard jobs.indices.contains(sourceIndex), jobs[sourceIndex].state == .waiting else { return }
        let movingDown = destination > sourceIndex
        let targetIndex = movingDown ? destination - 1 : destination
        guard jobs.indices.contains(targetIndex) else { return }
        let id = jobs[sourceIndex].id
        // `moveUp`/`moveDown` are single-step swaps (contract: drag reorder is "waiting rows only"); repeat the swap
        // once per position so a multi-row drag still lands where SwiftUI asked, same as a user clicking the button
        // that many times.
        let steps = abs(targetIndex - sourceIndex)
        for _ in 0..<steps {
            if movingDown { queue.moveDown(id) } else { queue.moveUp(id) }
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
                Text(stageLabel(job))
                    .font(XFinderTokens.Font.caption)
                    .foregroundColor(stageColor(job.state))
            }

            if job.bytesTotal > 0 {
                ProgressView(value: Double(job.bytesDone), total: Double(job.bytesTotal))
                    .progressViewStyle(.linear)
            }

            HStack {
                if showsSpeedAndETA(job), let speed = queue.speed {
                    Text(ByteCountFormatter.string(fromByteCount: Int64(speed), countStyle: .file) + "/s")
                        .font(XFinderTokens.Font.caption)
                        .foregroundColor(.secondary)
                }
                if showsSpeedAndETA(job), let eta = queue.eta {
                    Text(etaLabel(eta))
                        .font(XFinderTokens.Font.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                jobControls(job)
            }
        }
        .contextMenu {
            if job.state == .waiting {
                Button(L10n.t("Chạy kế tiếp")) { queue.runNext(job.id) }
                Button(L10n.t("Lên")) { queue.moveUp(job.id) }
                Button(L10n.t("Xuống")) { queue.moveDown(job.id) }
            }
        }
    }

    /// Contract §2: speed/ETA hide while Đang tạm dừng / Đang kiểm / Đang hoàn tất, when stalled (no sample yet —
    /// `queue.speed`/`queue.eta` are nil until a sample lands), and for zero-byte jobs (rename-only moves, same-disk
    /// trash) that never report a `bytesTotal`.
    private func showsSpeedAndETA(_ job: FileJob) -> Bool {
        job.state == .running && job.bytesTotal > 0
    }

    @ViewBuilder
    private func jobControls(_ job: FileJob) -> some View {
        HStack(spacing: XFinderTokens.Space.tight) {
            switch job.state {
            case .running, .pausing:
                Button(L10n.t("Tạm dừng")) { queue.pause(job.id) }
                    .disabled(!FileOperationRules.canPause(job.state))
                    .help(FileOperationRules.canPause(job.state) ? "" : L10n.t("Không tạm dừng được ở bước cuối"))
                Button(L10n.t("Dừng")) { queue.cancel(job.id) }
            case .paused:
                Button(L10n.t("Tiếp tục")) { queue.resume(job.id) }
                Button(L10n.t("Dừng")) { queue.cancel(job.id) }
            case .verifying, .finishing:
                Button(L10n.t("Tạm dừng")) { queue.pause(job.id) }
                    .disabled(true)
                    .help(L10n.t("Không tạm dừng được ở bước cuối"))
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
        case .merge: kind = L10n.t("Gộp thư mục")
        case .trash: kind = L10n.t("Chuyển vào Thùng rác")
        }
        let count = job.itemsTotal > 0 ? job.itemsTotal : job.sources.count
        return "\(kind) \(count) \(L10n.t("mục"))"
    }

    /// Contract §2's seven stage labels. `JobState` has no separate "preparing" phase yet (the queue goes straight
    /// to `.running` once copying starts) — a job that is `.running` with nothing moved yet reads as "Đang chuẩn
    /// bị", matching FileOctopus's own "checking items + destination, conflict dialogs surface here" meaning for
    /// that stage; once bytes/items start moving it reads as "Đang chép".
    private func stageLabel(_ job: FileJob) -> String {
        switch job.state {
        case .waiting: return L10n.t("Đang chờ")
        case .running:
            return (job.bytesDone == 0 && job.itemsDone == 0) ? L10n.t("Đang chuẩn bị") : L10n.t("Đang chép")
        case .pausing: return L10n.t("Đang tạm dừng")
        case .paused: return L10n.t("Đã tạm dừng")
        case .verifying: return L10n.t("Đang kiểm")
        case .finishing: return L10n.t("Đang hoàn tất")
        case .done: return L10n.t("Xong")
        case .failed: return L10n.t("Lỗi")
        case .cancelled: return L10n.t("Đã dừng")
        }
    }

    private func stageColor(_ state: JobState) -> Color {
        switch state {
        case .pausing, .paused: return .orange
        case .failed, .cancelled: return .red
        default: return .secondary
        }
    }

    private func etaLabel(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        return formatter.string(from: seconds) ?? ""
    }

    // MARK: - Sự cố (Problems)

    private var failedJobs: [FileJob] {
        queue.queue.jobs.filter { $0.state == .failed }
    }

    private var problemsSection: some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.tight) {
            HStack {
                Text(L10n.t("Sự cố"))
                    .font(XFinderTokens.Font.sectionTitle)
                Spacer()
                Button(L10n.t("Xoá hết")) { queue.clearFinished() }
                    .font(XFinderTokens.Font.caption)
            }
            ForEach(failedJobs) { job in
                problemRow(job)
            }
        }
    }

    @ViewBuilder
    private func problemRow(_ job: FileJob) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title(for: job))
                .font(XFinderTokens.Font.row)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(L10n.t(job.errorKey ?? "Không đọc được thư mục này"))
                .font(XFinderTokens.Font.caption)
                .foregroundColor(.red)
            if let detail = job.errorDetail {
                Text(detail)
                    .font(XFinderTokens.Font.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if canRetry(job) {
                Button(L10n.t("Thử lại")) { retry(job) }
                    .font(XFinderTokens.Font.caption)
            }
        }
        .settingsRow()
        .contextMenu {
            Button(L10n.t("Hiện trong XFinder")) { showInXFinder(job) }
            Button(L10n.t("Hiện trong Finder")) { showInFinder(job) }
            if canRetry(job) {
                Button(L10n.t("Thử lại")) { retry(job) }
            }
            Button(L10n.t("Bỏ qua")) { queue.clearFinished() }
        }
    }

    /// contract §1 "canRetry chỉ lỗi trước khi ghi và có thể tạm thời": the queue (`FileOperationQueue.run`) stops a
    /// job at its FIRST failed item, so `itemsDone == 0` means nothing in this job was written yet. A handful of
    /// error keys are rejections the queue raises before any copy starts at all (CLAUDE.md §3.2: user data is never
    /// silently retried into a state that could duplicate work) — those are excluded even though `itemsDone == 0`.
    private func canRetry(_ job: FileJob) -> Bool {
        guard job.state == .failed, job.itemsDone == 0 else { return false }
        let permanent: Set<String> = ["Không có gì để thao tác", "Nguồn và đích không được trùng nhau."]
        if let key = job.errorKey, permanent.contains(key) { return false }
        return true
    }

    private func retry(_ job: FileJob) {
        _ = queue.enqueue(job.kind, sources: job.sources, destination: job.destination)
    }

    /// "Hiện trong XFinder": open a new window at the item's enclosing folder with it selected (or the nearest
    /// surviving ancestor — contract §2). `OperationsPanelView` only ever has a `queue` reference (its call site in
    /// `BrowserToolbar.swift` is not this file's to change), so this opens a fresh window rather than reusing the
    /// window the popover is anchored to.
    private func showInXFinder(_ job: FileJob) {
        guard let path = job.sources.first else { return }
        let (folder, selected) = nearestSurvivingAncestor(of: path)
        let model = BrowserWindowController.shared.openWindow(path: folder)
        if let selected {
            model.active.selection = [selected]
        }
    }

    private func showInFinder(_ job: FileJob) {
        guard let path = job.sources.first else { return }
        let (folder, selected) = nearestSurvivingAncestor(of: path)
        let url = URL(fileURLWithPath: selected ?? folder)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Walks `path` upward until something on disk still exists. Returns the enclosing folder to open plus which
    /// path to select inside it — `selected == nil` when even the immediate parent is gone, so the caller opens the
    /// nearest surviving ancestor itself with nothing to select.
    private func nearestSurvivingAncestor(of path: String) -> (folder: String, selected: String?) {
        let fm = FileManager.default
        let parent = (path as NSString).deletingLastPathComponent
        if fm.fileExists(atPath: parent) {
            return (parent, fm.fileExists(atPath: path) ? path : nil)
        }
        var ancestor = parent
        while !ancestor.isEmpty, ancestor != "/" {
            let next = (ancestor as NSString).deletingLastPathComponent
            if next == ancestor { break }
            ancestor = next
            if fm.fileExists(atPath: ancestor) {
                return (ancestor, nil)
            }
        }
        return (NSHomeDirectory(), nil)
    }
}
