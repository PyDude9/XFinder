import SwiftUI
import AppKit
import ImageIO
import Darwin

struct InspectorImageActions: View {
    let item: FilePreviewItem
    @State private var job = InspectorImageJob()
    private var encoders: Set<String> { Set(CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []) }

    var body: some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
            Text(L10n.t("Thao tác ảnh")).font(XFinderTokens.Font.sectionTitle)
            Text(L10n.t("Tạo bản mới, chỉ xử lý khung hình đầu tiên. Lật và thu nhỏ xuất PNG."))
                .font(XFinderTokens.Font.caption).foregroundStyle(.secondary)
            HStack {
                Menu(L10n.t("Chuyển đổi")) {
                    if encoders.contains("public.png") { Button("PNG") { start(.png) } }
                    if encoders.contains("public.jpeg") { Button("JPEG") { start(.jpeg) } }
                    if encoders.contains("org.webmproject.webp") { Button("WebP") { start(.webp) } }
                }
                Menu(L10n.t("Giảm kích thước ảnh")) {
                    if let size = item.pixelSize {
                        ForEach(ImageEngine.resizePresets.filter { $0 < max(size.width, size.height) }, id: \.self) { side in
                            Button("\(side) px") { start(.resize, pixels: side) }
                        }
                    }
                }
                .disabled(item.pixelSize.map { max($0.width, $0.height) <= (ImageEngine.resizePresets.min() ?? 512) } ?? true)
            }
            .disabled(job.running)
            HStack {
                Button(L10n.t("Lật ngang")) { start(.flipHorizontal) }
                Button(L10n.t("Lật dọc")) { start(.flipVertical) }
            }
            .disabled(job.running)
            if !encoders.contains("org.webmproject.webp") {
                Text(L10n.t("ImageIO trên máy này chưa có bộ ghi WebP."))
                    .font(XFinderTokens.Font.caption).foregroundStyle(.secondary)
            }
            if job.running {
                HStack { ProgressView().controlSize(.small); Button(L10n.t("Hủy")) { job.cancel() } }
            }
            if let key = job.message { Text(L10n.t(key)).font(XFinderTokens.Font.caption) }
            if let output = job.output {
                Button(L10n.t("Hiện bản ảnh mới")) {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: output)])
                }
            }
        }
        .onDisappear { job.cancel() }
        .onChange(of: item.identity) { _, _ in job.cancel() }
    }
    private func start(_ operation: InspectorImageRules.Operation, pixels: Int? = nil) {
        job.start(.init(source: item.path, expectedIdentity: item.identity, operation: operation, maxPixels: pixels))
    }
}

/// Only orchestration lives in the app process: no image decoding and no in-process fallback.
@MainActor @Observable final class InspectorImageJob {
    private static var active: InspectorImageJob?
    private(set) var running = false
    private(set) var message: String?
    private(set) var output: String?
    private var process: Process?
    private var timeout: Task<Void, Never>?
    private var cancelled = false

    func start(_ request: InspectorImageRules.Request) {
        guard !running, let executable = Bundle.main.executableURL, Bundle.main.bundleIdentifier == "com.xfinder.app" else { return }
        guard Self.active == nil else { message = "Đang xử lý ảnh khác. Hãy chờ thao tác đó kết thúc."; return }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("xfinder-image-" + UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            let input = directory.appendingPathComponent("request.json")
            let reply = directory.appendingPathComponent("reply.json")
            try JSONEncoder().encode(request).write(to: input, options: .atomic)
            let worker = Process()
            worker.executableURL = executable
            worker.arguments = [InspectorImageChild.flag, input.path, reply.path]
            worker.standardInput = FileHandle.nullDevice
            worker.standardOutput = FileHandle.nullDevice
            worker.standardError = FileHandle.nullDevice
            worker.terminationHandler = { [weak self] _ in
                Task { @MainActor in
                    let result = await Task.detached {
                        defer {
                            try? FileManager.default.removeItem(at: request.stagingURL)
                            try? FileManager.default.removeItem(at: directory)
                        }
                        return (try? Data(contentsOf: reply)).flatMap { try? JSONDecoder().decode(InspectorImageRules.Reply.self, from: $0) }
                    }.value
                    guard let self else { return }
                    self.timeout?.cancel()
                    self.process = nil
                    self.running = false
                    if Self.active === self { Self.active = nil }
                    if self.cancelled { return }
                    self.output = result?.output
                    self.message = result?.errorKey ?? (result?.output == nil ? "Không thực hiện được thao tác ảnh." : "Đã tạo bản ảnh mới.")
                }
            }
            cancelled = false
            output = nil
            message = nil
            process = worker
            running = true
            Self.active = self
            try worker.run()
            timeout = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
                guard let self, self.running else { return }
                self.cancel()
                self.message = "Thao tác ảnh quá thời gian cho phép."
            }
        } catch {
            if Self.active === self { Self.active = nil }
            running = false
            process = nil
            message = "Không khởi chạy được tiến trình xử lý ảnh."
            try? FileManager.default.removeItem(at: directory)
        }
    }

    func cancel() {
        guard running else { return }
        cancelled = true
        timeout?.cancel()
        message = "Đã hủy thao tác ảnh."
        guard let worker = process, worker.isRunning else { return }
        worker.terminate()
        Task {
            try? await Task.sleep(for: .seconds(2))
            if worker.isRunning { kill(worker.processIdentifier, SIGKILL) }
        }
    }
}
