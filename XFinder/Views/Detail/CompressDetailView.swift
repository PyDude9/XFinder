import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Nén & Giải nén — real implementation backed by the system `ditto` (ZIP)
/// and `tar` (TAR.GZ) tools via Foundation Process. No third-party deps.
struct CompressDetailView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case compress, extract
        var id: String { rawValue }
        var titleVI: String {
            switch self {
            case .compress: return L10n.t("Nén")
            case .extract: return L10n.t("Giải nén")
            }
        }
    }

    enum ArchiveFormat: String, CaseIterable, Identifiable {
        case zip, tarGz
        var id: String { rawValue }
        var titleVI: String {
            switch self {
            case .zip: return "ZIP (.zip)"
            case .tarGz: return "TAR.GZ (.tar.gz)"
            }
        }
        var fileExtension: String {
            switch self {
            case .zip: return "zip"
            case .tarGz: return "tar.gz"
            }
        }
    }

    enum CompressionLevel: Int, CaseIterable, Identifiable {
        case fast = 1, normal = 6, max = 9
        var id: Int { rawValue }
        var titleVI: String {
            switch self {
            case .fast: return L10n.t("Nhanh")
            case .normal: return L10n.t("Thường")
            case .max: return L10n.t("Tối đa")
            }
        }
    }

    @State private var mode: Mode = .compress
    @State private var sources: [URL] = []
    @State private var outputFolder: URL? = nil
    @State private var extractionDestination: ExtractionDestination = .newFolderBesideArchive
    @State private var conflictPolicy: ConflictPolicy = .keepBoth
    @State private var format: ArchiveFormat = .zip
    @State private var archiveName: String = "Archive"
    @State private var password = ""
    @State private var level = 6
    @State private var resultURL: URL?
    @State private var isRunning = false
    @State private var log: [String] = []
    /// "Kiểm tra" (spec §4.4–4.5): the reviewed plan for the current selection, shown before anything
    /// is written. nil = not reviewed yet, which is why the extract button asks for it.
    @State private var reviews: [ArchiveJob.ArchiveReview] = []
    /// What `reviews` was computed for. A plan is only valid for the exact selection **and** the exact
    /// destination/policy it was measured against: showing a "fits, no conflicts" review after the
    /// user changed the destination would describe a different job than the one about to run.
    @State private var checkedPlan = ""
    @State private var runTask: Task<Void, Never>?
    @State private var cancelled = false
    @State private var deleteReport: ArchiveJob.DeletionReport?
    /// Archives this run already put in the Trash, so the button cannot offer them a second time.
    @State private var deletedSources: [URL] = []
    @State private var outcomes: [(archive: URL, outcome: ArchiveJob.Outcome)] = []

    enum ExtractionDestination: String, CaseIterable, Identifiable {
        case newFolderBesideArchive, sameFolder, downloads, custom
        var id: String { rawValue }
        var titleVI: String {
            switch self {
            case .newFolderBesideArchive: return L10n.t("Thư mục mới cạnh file nén")
            case .sameFolder: return L10n.t("Cùng thư mục với file nén")
            case .downloads: return L10n.t("Tải về")
            case .custom: return L10n.t("Thư mục tùy chọn")
            }
        }
    }

    enum ConflictPolicy: String, CaseIterable, Identifiable {
        case keepBoth, ask, merge
        var id: String { rawValue }
        var titleVI: String {
            switch self {
            case .keepBoth: return L10n.t("Giữ cả hai")
            case .ask: return L10n.t("Hỏi")
            case .merge: return L10n.t("Gộp thư mục, giữ cả hai file trùng")
            }
        }
        /// The approved label (Boss decision 1) is too long for the picker, so the picker stays short
        /// and the explanation below it carries the exact wording.
        var pickerTitleVI: String {
            switch self {
            case .keepBoth: return L10n.t("Giữ cả hai")
            case .ask: return L10n.t("Hỏi")
            case .merge: return L10n.t("Gộp thư mục")
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: XFinderTokens.Settings.sectionGap) {
                headerSection

                Picker(L10n.t("Chế độ"), selection: $mode) {
                    Text(Mode.compress.titleVI).tag(Mode.compress)
                    Text(Mode.extract.titleVI).tag(Mode.extract)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, XFinderTokens.Space.page)
                .onChange(of: mode) { sources = [] }

                SettingsSection(
                    title: mode == .compress ? L10n.t("Tập tin / thư mục cần nén") : L10n.t("Tập tin nén cần giải"),
                    footer: sources.isEmpty
                        ? L10n.t("Chưa chọn gì")
                        : "\(sources.count)\(L10n.t(" mục đã chọn"))"
                ) {
                    Button(L10n.t("Chọn…")) { pickSources() }
                        .settingsRow()
                    if !sources.isEmpty {
                        ForEach(sources.prefix(8), id: \.self) { url in
                            SettingsDivider()
                            HStack {
                                Image(systemName: mode == .compress ? "doc.fill" : "archivebox.fill")
                                    .foregroundColor(.secondary)
                                Text(url.lastPathComponent)
                                    .font(XFinderTokens.Font.rowValue)
                                    .fileNameRowSafe()
                                Spacer()
                                Button {
                                    sources.removeAll { $0 == url }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .settingsRow()
                        }
                        if sources.count > 8 {
                            SettingsDivider()
                            Text("\(L10n.t("…và "))\(sources.count - 8)\(L10n.t(" mục nữa"))")
                                .font(XFinderTokens.Font.caption)
                                .foregroundColor(.secondary)
                                .settingsRow()
                        }
                        SettingsDivider()
                        Button(L10n.t("Xóa hết")) { sources = [] }
                            .font(XFinderTokens.Font.rowValue)
                            .foregroundColor(.red)
                            .settingsRow()
                    }
                }

                if mode == .compress {
                    SettingsSection(title: L10n.t("Định dạng & tên")) {
                        Picker(L10n.t("Định dạng"), selection: $format) {
                            Text(ArchiveFormat.zip.titleVI).tag(ArchiveFormat.zip)
                            Text(ArchiveFormat.tarGz.titleVI).tag(ArchiveFormat.tarGz)
                        }
                        .pickerStyle(.segmented)
                        .settingsRow()
                        SettingsDivider()
                        HStack {
                            Text(L10n.t("Tên tập tin:")).font(XFinderTokens.Font.rowValue).foregroundColor(.secondary)
                            TextField("Archive", text: $archiveName)
                                .textFieldStyle(.roundedBorder)
                                .font(XFinderTokens.Font.rowValue)
                            Text(".\(format.fileExtension)")
                                .font(XFinderTokens.Font.rowValue)
                                .foregroundColor(.secondary)
                        }
                        .settingsRow()
                        if format == .zip {
                            SettingsDivider()
                            HStack {
                                Text(L10n.t("Mật khẩu (tuỳ chọn):")).font(XFinderTokens.Font.rowValue).foregroundColor(.secondary)
                                SecureField(L10n.t("để trống nếu không khoá"), text: $password)
                                    .textFieldStyle(.roundedBorder)
                                    .font(XFinderTokens.Font.rowValue)
                            }
                            .settingsRow()
                            if !password.isEmpty {
                                SettingsDivider()
                                InlineNote(text: L10n.t("Mật khẩu dùng mã hoá ZIP truyền thống (ZipCrypto): đủ chặn người xem tình cờ, không phải mã hoá mạnh. Mật khẩu không nằm trong dòng lệnh và XFinder không lưu nó."))
                                    .settingsRow()
                            }
                            SettingsDivider()
                            HStack {
                                Text(L10n.t("Mức nén:")).font(XFinderTokens.Font.rowValue).foregroundColor(.secondary)
                                Picker("", selection: $level) {
                                    Text(CompressionLevel.fast.titleVI).tag(CompressionLevel.fast.rawValue)
                                    Text(CompressionLevel.normal.titleVI).tag(CompressionLevel.normal.rawValue)
                                    Text(CompressionLevel.max.titleVI).tag(CompressionLevel.max.rawValue)
                                }
                                .pickerStyle(.segmented)
                                .frame(maxWidth: 240)
                            }
                            .settingsRow()
                        }
                    }
                }

                SettingsSection(title: L10n.t("Giải nén vào")) {
                    PickerRow(title: L10n.t("Giải nén vào"), selection: $extractionDestination, width: 220) {
                        ForEach(ExtractionDestination.allCases) { d in Text(d.titleVI).tag(d) }
                    }
                    .settingsRow()
                    if extractionDestination == .custom {
                        SettingsDivider()
                        HStack {
                            Button(L10n.t("Chọn thư mục đích…")) { pickOutputFolder() }
                            if let f = outputFolder {
                                Text(f.lastPathComponent)
                                    .font(XFinderTokens.Font.caption)
                                    .foregroundColor(.secondary)
                                    .fileNameRowSafe()
                            }
                            if outputFolder != nil {
                                Button(L10n.t("Mặc định")) { outputFolder = nil; extractionDestination = .newFolderBesideArchive }
                                    .font(XFinderTokens.Font.rowValue)
                            }
                        }
                        .settingsRow()
                        if let problem = destinationProblem {
                            SettingsDivider()
                            InlineNote(text: L10n.t(problem.messageKey))
                                .settingsRow()
                        }
                    }
                }

                SettingsSection(title: L10n.t("Khi tên đã tồn tại")) {
                    PickerRow(title: L10n.t("Khi tên đã tồn tại"), selection: $conflictPolicy, width: 180) {
                        ForEach(ConflictPolicy.allCases) { p in Text(p.pickerTitleVI).tag(p) }
                    }
                    .settingsRow()
                    SettingsDivider()
                    InlineNote(text: conflictPolicy == .keepBoth ? L10n.t("Giữ cả hai lưu một bản sao riêng (\"Report 2\").")
                         : conflictPolicy == .merge ? L10n.t("Gộp thư mục, giữ cả hai file trùng: thư mục được gộp vào nhau, file trùng tên được đánh số (“Report 2.pdf”) nên không file nào bị thay. Khi nén: không ghi thêm vào tệp nén cũ — tệp nén mới được đánh số.")
                         : L10n.t("Hiện hộp thoại trước khi ghi: giữ cả hai, gộp thư mục hoặc huỷ. Mặc định là Huỷ."))
                        .settingsRow()
                }

                if mode == .compress {
                    SettingsSection(title: L10n.t("Mặc định giải nén")) {
                        LabeledLine(label: L10n.t("Bộ máy nén và giải nén"), value: L10n.t("ditto, zip, tar có sẵn của macOS"))
                            .settingsRow()
                        SettingsDivider()
                        InlineNote(text: L10n.t("Dùng công cụ có sẵn của macOS: ditto cho ZIP một mục (giữ metadata của Mac), zip cho nhiều mục hoặc có mật khẩu, tar cho TAR.GZ. Không cần cài thêm gì. Chỉ ghi đè khi bạn chọn Gộp hoặc Thay thế."))
                            .settingsRow()
                    }

                    SettingsSection(title: L10n.t("Tách tác vụ nén và giải nén hoạt động")) {
                        InlineNote(text: L10n.t("Tạo ZIP hoặc TAR.GZ từ nhiều mục ở nhiều thư mục khác nhau; giải nén ZIP, TAR, TAR.GZ, TAR.BZ2. Tệp nén được đọc lại sau khi tạo để chắc không thiếu mục nào."))
                            .settingsRow()
                    }
                }

                if mode == .extract {
                    reviewSection
                }

                HStack(spacing: XFinderTokens.Space.row) {
                    if mode == .extract {
                        Button {
                            runTask = Task { await check() }
                        } label: {
                            Label(L10n.t("Kiểm tra"), systemImage: "checklist")
                        }
                        .disabled(sources.isEmpty || isRunning)
                    }
                    Button {
                        runTask = Task { await run() }
                    } label: {
                        HStack {
                            if isRunning { ProgressView().scaleEffect(0.7) }
                            Text(isRunning ? L10n.t("Đang xử lý…") : (mode == .compress ? L10n.t("Nén ngay") : L10n.t("Giải nén")))
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(sources.isEmpty || isRunning || (mode == .extract && !isReviewed))
                    if isRunning {
                        Button(L10n.t("Huỷ")) { cancelled = true; runTask?.cancel() }
                    }
                }
                .padding(.horizontal, XFinderTokens.Space.page)

                if let resultURL {
                    SettingsSection(title: L10n.t("Việc tiếp theo")) {
                        HStack {
                            Menu {
                                if mode == .compress {
                                    Button(L10n.t("Mở thư mục chứa")) { NSWorkspace.shared.open(resultURL.deletingLastPathComponent()) }
                                    Button(L10n.t("Hiện trong Finder")) { NSWorkspace.shared.activateFileViewerSelecting([resultURL]) }
                                } else {
                                    Button(L10n.t("Mở thư mục đã giải")) { NSWorkspace.shared.open(resultURL) }
                                    Button(L10n.t("Hiện trong Finder")) { NSWorkspace.shared.activateFileViewerSelecting([resultURL]) }
                                    if !deletableNow.isEmpty {
                                        Button(L10n.t("Xóa file nén gốc"), role: .destructive) { deleteSources() }
                                    }
                                }
                                Button(L10n.t("Chép đường dẫn")) {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(resultURL.path, forType: .string)
                                }
                            } label: {
                                Label(mode == .compress ? L10n.t("Đã nén xong — tuỳ chọn…") : L10n.t("Đã giải xong — tuỳ chọn…"),
                                      systemImage: "ellipsis.circle")
                            }
                            .fixedSize()
                        }
                        .settingsRow()
                    }
                }

                if !log.isEmpty {
                    SettingsSection(title: L10n.t("Kết quả")) {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(log.indices.reversed().prefix(10), id: \.self) { i in
                                Text(log[i])
                                    .font(XFinderTokens.Font.mono)
                                    .foregroundColor(log[i].hasPrefix(L10n.t("Lỗi")) || log[i].hasPrefix(L10n.t("Thất bại")) ? .red : .primary)
                                    .lineLimit(3)
                            }
                        }
                        .settingsRow()
                    }
                }

                // Per-file outcome of "Xóa file nén gốc": every name is listed with what happened, so a
                // file that stayed stays visible instead of scrolling out of the log.
                if let report = deleteReport, !(report.trashed.isEmpty && report.failed.isEmpty) {
                    SettingsSection(title: L10n.t("Đã xoá file nén gốc")) {
                        ForEach(Array(report.trashed.enumerated()), id: \.offset) { _, url in
                            Label(url.lastPathComponent, systemImage: "trash")
                                .font(XFinderTokens.Font.caption)
                                .settingsRow()
                        }
                        ForEach(Array(report.failed.enumerated()), id: \.offset) { _, failure in
                            VStack(alignment: .leading, spacing: 2) {
                                Label(failure.0.lastPathComponent, systemImage: "exclamationmark.triangle")
                                    .font(XFinderTokens.Font.caption)
                                    .foregroundColor(.red)
                                Text(failure.1)
                                    .font(XFinderTokens.Font.mono)
                                    .foregroundColor(.red)
                                    .lineLimit(2)
                            }
                            .settingsRow()
                        }
                    }
                }
            }
            .padding(.bottom, XFinderTokens.Space.section)
            .pageWidthSafe()
        }
        .background(XFinderTokens.Settings.contentBackground)
    }

    /// The reviewed plan (spec §4.5). Every number here is counted or measured; nothing is a
    /// percentage or an estimate, and a blocked archive says exactly why with no bypass.
    ///
    /// Spec §4.5 also requires that a change of input, archive or destination invalidates the plan.
    /// A stale plan is never deleted from the screen (that would look like the check did nothing), but
    /// it is labelled as belonging to the previous selection and the primary action stays disabled.
    @ViewBuilder
    private var reviewSection: some View {
        if !reviews.isEmpty {
            SettingsSection(title: L10n.t("Kiểm tra trước khi giải nén")) {
                if !isReviewed && destinationProblem == nil {
                    InlineNote(text: L10n.t("Lựa chọn hoặc thư mục đích đã thay đổi — hãy bấm Kiểm tra lại trước khi giải nén."))
                        .settingsRow()
                    SettingsDivider()
                }
                ForEach(Array(reviews.indices), id: \.self) { i in
                    reviewRow(reviews[i])
                    if i < reviews.count - 1 { SettingsDivider() }
                }
            }
        }
    }

    @ViewBuilder
    private func reviewRow(_ review: ArchiveJob.ArchiveReview) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(review.archive.lastPathComponent)
                .font(XFinderTokens.Font.rowValue)
                .fileNameRowSafe()
            Text(reviewCounts(review))
                .font(XFinderTokens.Font.caption)
                .foregroundColor(.secondary)
            Text(reviewCapacity(review))
                .font(XFinderTokens.Font.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)
            Text(review.destination.path)
                .font(XFinderTokens.Font.mono)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .fileNameRowSafe()
            if !review.conflicts.isEmpty {
                Text(conflictLine(review))
                    .font(XFinderTokens.Font.caption)
                    .foregroundColor(.orange)
                    .lineLimit(2)
            }
            if !review.keepsBothRenames.isEmpty {
                Text(renameLine(review))
                    .font(XFinderTokens.Font.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            if let warning = capacityWarning(review) {
                Text(warning)
                    .font(XFinderTokens.Font.caption)
                    .foregroundColor(.red)
            }
            if !review.refusals.isEmpty {
                Text(refusalLine(review))
                    .font(XFinderTokens.Font.mono)
                    .foregroundColor(.red)
                    .lineLimit(3)
            }
        }
        .settingsRow()
    }

    /// nil when the plan fits; otherwise the exact sentence, never a percentage.
    private func capacityWarning(_ review: ArchiveJob.ArchiveReview) -> String? {
        switch review.capacityVerdict {
        case .fits: return nil
        case .doesNotFit(let short): return L10n.t("Không đủ dung lượng, còn thiếu ") + Self.bytes(short)
        case .unknown: return L10n.t("Chưa đọc được dung lượng trống của thư mục đích.")
        }
    }

    private func conflictLine(_ review: ArchiveJob.ArchiveReview) -> String {
        "\(L10n.t("Trùng tên: "))\(review.conflicts.prefix(4).joined(separator: ", "))"
    }

    /// The names the plan would produce instead. Shown before the run so "merge" is never a surprise:
    /// the archive's copy lands as "Report 2.pdf", never on top of the user's file.
    private func renameLine(_ review: ArchiveJob.ArchiveReview) -> String {
        "\(L10n.t("Sẽ giữ cả hai với tên: "))\(review.keepsBothRenames.prefix(4).joined(separator: ", "))"
    }

    private func refusalLine(_ review: ArchiveJob.ArchiveReview) -> String {
        L10n.t("Tệp nén không an toàn nên sẽ không giải nén: ")
            + review.refusals.prefix(4).map { ArchiveRunner.Failure.describe($0) }.joined(separator: "; ")
    }

    private func reviewCounts(_ review: ArchiveJob.ArchiveReview) -> String {
        "\(review.entryCount)\(L10n.t(" mục · đã khai báo "))\(Self.bytes(review.declaredBytes))"
    }

    /// Required vs available, in the spec §4.5 wording. Unknown capacity says so; it never prints
    /// "0 / 0", which reads as a shortage the user does not have.
    private func reviewCapacity(_ review: ArchiveJob.ArchiveReview) -> String {
        let need = Self.bytes(review.requiredBytes)
        guard let available = review.availableBytes else {
            return "\(L10n.t("Cần "))\(need)\(L10n.t(" · chưa đọc được dung lượng trống"))"
        }
        return "\(L10n.t("Cần "))\(need)\(L10n.t(" · còn trống "))\(Self.bytes(available))"
    }

    /// Reviewed means: a plan exists for exactly this selection, destination and policy, and nothing in
    /// it was refused. A single string fingerprint is used instead of comparing URLs one by one so no
    /// input can be forgotten — that omission is what would let a stale plan authorise a new job.
    private var isReviewed: Bool {
        !reviews.isEmpty && checkedPlan == planFingerprint && reviews.allSatisfy { $0.isExtractable }
    }

    /// Everything the reviewed plan depends on.
    private var planFingerprint: String {
        let target: String
        switch extractionDestination {
        case .newFolderBesideArchive, .sameFolder: target = "beside"
        case .downloads: target = "downloads"
        case .custom: target = "custom:" + (outputFolder?.path ?? "-")
        }
        return ([target, conflictPolicy.rawValue] + sources.map(\.path)).joined(separator: "\u{1}")
    }

    private static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    // MARK: - Pickers

    private func pickSources() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = mode == .compress
        panel.allowsMultipleSelection = true
        if mode == .extract {
            panel.allowedContentTypes = [.zip, .gzip, UTType(filenameExtension: "bz2"), UTType(filenameExtension: "tar")].compactMap { $0 }
        }
        if panel.runModal() == .OK { sources = panel.urls }
    }

    private func pickOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        if panel.runModal() == .OK { outputFolder = panel.url }
    }

    // MARK: - Run

    private func run() async {
        isRunning = true
        cancelled = false
        defer { isRunning = false }
        if mode == .compress {
            await compress()
        } else {
            if !isReviewed { await check() }
            guard isReviewed else { return }
            await extract()
        }
    }

    /// "Kiểm tra": read each archive, validate it, count what is really inside, and remember the plan.
    /// Nothing is written here — the whole point is to see the conflicts and the capacity first.
    private func check() async {
        reviews = []
        outcomes = []
        // A new plan starts a new batch: the previous run's Trash record must not filter it.
        deletedSources = []
        // Spec §4.2: an unchosen custom folder blocks the review instead of quietly extracting beside
        // the archive. The page says which destination is missing; it never picks one.
        if let problem = destinationProblem {
            appendLog(L10n.t(problem.messageKey))
            reviews = sources.map { src in
                ArchiveJob.ArchiveReview(archive: src, destination: src.deletingLastPathComponent(),
                                         entryCount: 0, declaredBytes: 0, availableBytes: nil,
                                         requiredBytes: 0, conflicts: [], keepsBothRenames: [],
                                         refusals: [.unsupportedEntry(L10n.t(problem.messageKey))])
            }
            checkedPlan = planFingerprint
            return
        }
        for src in sources {
            guard let dest = resolvedDestDir(for: src) else { continue }
            let plan = await ArchiveRunner.inspect(archive: src, near: dest, topLevelName: newFolderName(for: src))
            switch plan {
            case .failure(let f):
                reviews.append(ArchiveJob.ArchiveReview(
                    archive: src, destination: dest, entryCount: 0, declaredBytes: 0, availableBytes: nil,
                    requiredBytes: 0, conflicts: [], keepsBothRenames: [],
                    refusals: refusalReasons(f)))
            case .success(let review):
                reviews.append(review)
            }
            if cancelled { break }
        }
        checkedPlan = planFingerprint
        if reviews.contains(where: { !$0.isExtractable }) {
            appendLog(L10n.t("Kiểm tra xong: có tệp nén không giải nén được."))
        }
    }

    private func refusalReasons(_ f: ArchiveRunner.Failure) -> [ArchiveSafetyRules.Reason] {
        if case .unsafeArchive(let reasons, _) = f, !reasons.isEmpty { return reasons }
        // A failure that is not a rule verdict still blocks the plan; it gets a reason row so the
        // review cannot say "extractable" about something that just failed to inspect.
        return [.unsupportedEntry(L10n.t(f.messageKey))]
    }

    /// The one name the review checks when everything lands in a new folder beside the archive; nil for every
    /// other destination, where the review checks the archive's own top-level entries (`ArchiveJob.previewNames`).
    /// This used to return the ARCHIVE's file name for the other three modes, so "same folder" always previewed the
    /// archive itself as a conflict and never the entries that really collide.
    private func newFolderName(for src: URL) -> String? {
        extractionDestination == .newFolderBesideArchive ? ArchiveEngine.folderName(forArchive: src) : nil
    }

    private var destinationProblem: ArchiveJob.DestinationProblem? {
        ArchiveJob.destinationProblem(isCustom: extractionDestination == .custom, folder: outputFolder)
    }

    private var headerSection: some View {
        PageHeader(title: L10n.t("Nén & Giải nén"),
                   subtitle: L10n.t("Nén và giải nén file từ Finder."))
    }

    /// The folder the archive lands in. `nil` means "the page must ask first" (spec §4.2): a custom
    /// destination with no folder chosen is not silently replaced by the archive's own folder.
    private func resolvedDestDir(for src: URL) -> URL? {
        switch extractionDestination {
        case .newFolderBesideArchive, .sameFolder:
            return src.deletingLastPathComponent()
        case .downloads:
            return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
                ?? src.deletingLastPathComponent()
        case .custom:
            return outputFolder
        }
    }

    private var enginePolicy: ArchiveEngine.ConflictPolicy {
        switch conflictPolicy {
        case .keepBoth: return .keepBoth
        case .ask: return .ask
        case .merge: return .merge
        }
    }

    private static func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    private enum ConflictChoice { case keepBoth, third, cancel }

    /// The real "Hỏi" (Ask), with **Cancel as the default button** (Boss decision 1).
    ///
    /// Extraction offers Keep Both / Merge / Cancel. Compression offers Keep Both / Replace / Cancel,
    /// and "Replace" is the transactional replacement from Boss decision 5 — never a pre-emptive Trash.
    ///
    /// Button order comes from `AskChoice.buttonOrder`, so the default is declared in the engine and
    /// the alert cannot drift from it.
    private func askConflict(names: [String], thirdIsReplace: Bool) -> ConflictChoice {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "\(names.count)\(L10n.t(" mục đã tồn tại ở nơi đích."))"
        alert.informativeText = names.prefix(6).joined(separator: "\n") + (names.count > 6 ? "\n…" : "")
        var slots: [ArchiveEngine.AskChoice] = []
        for choice in ArchiveEngine.AskChoice.buttonOrder {
            slots.append(choice)
            switch choice {
            case .cancel: alert.addButton(withTitle: L10n.t("Huỷ"))
            case .keepBoth: alert.addButton(withTitle: L10n.t("Giữ cả hai"))
            case .merge: alert.addButton(withTitle: thirdIsReplace
                                          ? L10n.t("Thay thế (bản cũ vào Thùng rác)")
                                          : L10n.t("Gộp thư mục"))
            }
        }
        // Return triggers the first button, which `buttonOrder` guarantees is Cancel.
        alert.buttons.first?.keyEquivalent = "\r"
        let index = alert.runModal().rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        guard slots.indices.contains(index) else { return .cancel }
        switch slots[index] {
        case .cancel: return .cancel
        case .keepBoth: return .keepBoth
        case .merge: return .third
        }
    }

    private func failureLine(_ f: ArchiveRunner.Failure) -> String {
        if let d = f.detail, !d.isEmpty { return "\(L10n.t(f.messageKey)) \(d)" }
        return L10n.t(f.messageKey)
    }

    private var engineFormat: ArchiveEngine.Format { format == .zip ? .zip : .tarGz }

    private func compress() async {
        guard let first = sources.first else { return }
        let base = first.deletingLastPathComponent()
            .appendingPathComponent("\(ArchiveEngine.archiveName(archiveName)).\(engineFormat.fileExtension)")
        // "Gộp" only means something for extraction; an existing archive is never appended to.
        let policy: ArchiveEngine.ConflictPolicy = enginePolicy == .merge ? .keepBoth : enginePolicy
        var output: URL
        /// Replacement is a transaction (Boss decision 5): the candidate is built and verified FIRST,
        /// and only then does the old archive leave its path. The old code trashed it before building —
        /// a failed compression left the user with neither file.
        var replaceTarget: URL?
        switch ArchiveEngine.destination(base: base, policy: policy, exists: Self.exists) {
        case .write(let url): output = url
        case .needsDecision(let existing):
            switch askConflict(names: [existing.lastPathComponent], thirdIsReplace: true) {
            case .cancel: appendLog(L10n.t("Đã hủy.")); return
            case .third:
                // "Thay thế": build a verified candidate first, then hand it to the transaction. The
                // old archive leaves its path only after the new one exists (Boss decision 5).
                replaceTarget = existing
                output = existing.deletingLastPathComponent()
                    .appendingPathComponent(".xf-candidate-\(UUID().uuidString)-\(existing.lastPathComponent)")
            case .keepBoth:
                guard case .write(let url) = ArchiveEngine.destination(base: base, policy: .keepBoth, exists: Self.exists) else { return }
                output = url
            }
        }
        let result = await ArchiveRunner.compress(sources: sources, format: engineFormat, level: level,
                                                  password: password.isEmpty ? nil : password, output: output)
        switch result {
        case .success(let built):
            var finalURL = built
            if let target = replaceTarget {
                switch ArchiveRunner.replace(existing: target, with: built) {
                case .success(let url):
                    finalURL = url
                    appendLog("\(L10n.t("Đã thay tệp nén cũ (bản cũ vào Thùng rác): "))\(url.lastPathComponent)")
                case .failure(let f):
                    // The candidate is this job's own file; the old one was restored or is in the Trash.
                    try? FileManager.default.removeItem(at: built)
                    DiagnosticsLog.record("archive", "compress." + f.diagnosticCode)
                    appendLog(failureLine(f))
                    return
                }
            }
            appendLog("\(L10n.t("Đã nén → "))\(finalURL.lastPathComponent)")
            resultURL = finalURL
            ActionHistoryStore.shared.record(
                kind: "compress",
                summary: "\(L10n.t("Nén "))\(sources.count)\(L10n.t(" mục → "))\(finalURL.lastPathComponent)",
                detail: finalURL.path,
                reversible: false)
        case .failure(let f):
            DiagnosticsLog.record("archive", "compress." + f.diagnosticCode)
            appendLog("\(L10n.t("Thất bại khi nén "))\(sources.count)\(L10n.t(" mục"))")
            appendLog(failureLine(f))
        }
    }

    private func extract() async {
        outcomes = []
        deletedSources = []
        // The review step is the only way in: without a plan for this exact selection/destination there
        // is nothing to execute, so a missing destination cannot slip past on the extract path either.
        guard destinationProblem == nil, isReviewed else {
            appendLog(L10n.t("Chưa kiểm tra xong nên chưa giải nén gì."))
            return
        }
        for src in sources {
            if cancelled {
                outcomes.append((src, .cancelledBeforePlacement))
                continue
            }
            guard var dest = resolvedDestDir(for: src) else { continue }
            var policy = enginePolicy
            if extractionDestination == .newFolderBesideArchive {
                let folder = dest.appendingPathComponent(ArchiveEngine.folderName(forArchive: src))
                switch ArchiveEngine.destination(base: folder, policy: policy == .merge ? .keepBoth : policy, exists: Self.exists) {
                case .write(let url): dest = url
                case .needsDecision(let existing):
                    switch askConflict(names: [existing.lastPathComponent], thirdIsReplace: false) {
                    case .cancel:
                        appendLog("\(L10n.t("Bỏ qua "))\(src.lastPathComponent)")
                        outcomes.append((src, .untouched)); continue
                    case .third:
                        dest = existing; policy = .merge
                    case .keepBoth:
                        guard case .write(let url) = ArchiveEngine.destination(base: folder, policy: .keepBoth, exists: Self.exists) else {
                            outcomes.append((src, .untouched)); continue
                        }
                        dest = url; policy = .keepBoth
                    }
                }
            }
            let staged = await ArchiveRunner.extractToStaging(archive: src, near: dest)
            guard case .success(let batch) = staged else {
                if case .failure(let f) = staged {
                    DiagnosticsLog.record("archive", "extract." + f.diagnosticCode)
                    appendLog("\(L10n.t("Lỗi: không giải được "))\(src.lastPathComponent)")
                    appendLog(failureLine(f))
                    outcomes.append((src, .rejected(f)))
                }
                continue
            }
            let clashes = ArchiveRunner.conflicts(batch, in: dest)
            if policy == .ask {
                if clashes.isEmpty { policy = .keepBoth }
                else {
                    switch askConflict(names: clashes, thirdIsReplace: false) {
                    case .cancel:
                        ArchiveRunner.discard(batch)
                        appendLog("\(L10n.t("Bỏ qua "))\(src.lastPathComponent)")
                        outcomes.append((src, .cancelledBeforePlacement)); continue
                    case .third: policy = .merge
                    case .keepBoth: policy = .keepBoth
                    }
                }
            }
            // The archives in this batch are protected identities: an entry named like one of them
            // must never overwrite it (measured, spec §2 — a ZIP holding `self.zip` replaced its own
            // source).
            switch await ArchiveRunner.place(batch, into: dest, policy: policy, protected: Set(sources)) {
            case .failure(let f):
                appendLog("\(L10n.t("Lỗi: không giải được "))\(src.lastPathComponent)")
                appendLog(failureLine(f))
                outcomes.append((src, .rejected(f)))
            case .success(let result):
                if result.isComplete {
                    appendLog("\(L10n.t("Đã giải → "))\(dest.lastPathComponent)")
                    if !result.renamed.isEmpty {
                        appendLog("\(L10n.t("Giữ cả hai, đã đánh số: "))\(result.renamed.prefix(4).joined(separator: ", "))")
                    }
                    outcomes.append((src, .completed(outputs: result.placed, renamed: result.renamed)))
                    resultURL = result.placed.count == 1 ? result.placed[0] : dest
                } else {
                    // Partial: name what exists and where the rest still is. Never "success".
                    appendLog("\(L10n.t("Chỉ giải được một phần "))\(src.lastPathComponent)")
                    if !result.placed.isEmpty {
                        appendLog("\(L10n.t("Đã đặt: "))" + result.placed.map(\.lastPathComponent).prefix(4).joined(separator: ", "))
                    }
                    if !result.failed.isEmpty {
                        appendLog("\(L10n.t("Chưa đặt được: "))" + result.failed.prefix(4).joined(separator: ", "))
                    }
                    if let recovery = result.recoveryRoot {
                        appendLog("\(L10n.t("Phần còn lại giữ ở: "))\(recovery.path)")
                    }
                    if let f = result.failure { appendLog(failureLine(f)) }
                    outcomes.append((src, .partial(placed: result.placed, failed: result.failed, recoveryRoot: result.recoveryRoot)))
                }
            }
        }
        let done = outcomes.filter { $0.outcome.isCompleted }.count
        appendLog("\(L10n.t("Đã giải "))\(done)/\(sources.count)\(L10n.t(" tập tin"))")
        if done > 0 {
            ActionHistoryStore.shared.record(
                kind: "extract",
                summary: "\(L10n.t("Giải "))\(done)/\(sources.count)\(L10n.t(" tập tin"))",
                reversible: false)
        }
    }

    /// Archives that completed this run and are not already in the Trash. Pure, so the menu and the
    /// action read the same list: a button that offers a file the action will refuse is a broken button.
    private var deletableNow: [URL] {
        ArchiveJob.deletableSources(outcomes: outcomes).filter { !deletedSources.contains($0) }
    }

    /// "Xóa file nén gốc" — only archives that completed in this run, a confirmation that lists them
    /// with **Cancel as default**, Trash only, and a per-file report (Boss approval point 6).
    private func deleteSources() {
        let candidates = deletableNow
        guard !candidates.isEmpty else {
            appendLog(L10n.t("Chưa có tệp nén nào giải xong trong lần này."))
            return
        }
        let confirmation = ArchiveJob.deleteConfirmation(names: candidates.map(\.lastPathComponent))
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = confirmation.title
        alert.informativeText = confirmation.detail
        alert.addButton(withTitle: L10n.t("Huỷ"))
        alert.addButton(withTitle: L10n.t("Đưa vào Thùng rác"))
        alert.buttons.first?.keyEquivalent = "\r"          // Cancel is what Return does
        guard alert.runModal() == .alertSecondButtonReturn else { return }

        let report = ArchiveJob.trashSources(candidates)
        deleteReport = report
        deletedSources.append(contentsOf: report.trashed)
        for url in report.trashed { appendLog("\(L10n.t("Đã đưa vào Thùng rác: "))\(url.lastPathComponent)") }
        for (url, reason) in report.failed {
            appendLog("\(L10n.t("Không đưa được vào Thùng rác: "))\(url.lastPathComponent)")
            appendLog(reason)
        }
    }

    private func appendLog(_ line: String) {
        log.append(line)
        if log.count > 50 { log.removeFirst(log.count - 50) }
    }
}
