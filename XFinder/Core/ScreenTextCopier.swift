import AppKit
import SwiftUI
import ImageIO

/// "Copy text from anywhere on screen": drag a region, the text lands on the clipboard.
///
/// The region picker is the system's own `screencapture -i` (crosshair, Space to switch to a
/// window, Esc to cancel) — a public tool with the UX every Mac user already knows, instead of a
/// second overlay to maintain. The capture goes to a temp file that is deleted whether or not
/// anything was recognised; nothing is kept and nothing leaves the machine (Vision runs on-device).
///
/// Needs Screen Recording: without it `screencapture` returns only the wallpaper, which would read
/// as "no text found" — a misleading answer — so the permission is checked FIRST and named.
@MainActor
@Observable
final class ScreenTextCopier {
    static let shared = ScreenTextCopier()

    enum Outcome: Equatable {
        case cancelled
        case noText
        case text(String)
    }

    private(set) var isBusy = false
    private let toast = TextToast()
    init() {}

    func start() {
        guard !isBusy else { return }
        guard CGPreflightScreenCaptureAccess() else {
            _ = CGRequestScreenCaptureAccess()
            toast.show(icon: "exclamationmark.triangle.fill", title: L10n.t("Cần quyền Ghi màn hình"),
                       detail: L10n.t("Cấp quyền trong Tính năng & Quyền rồi thử lại."))
            return
        }
        isBusy = true
        Task {
            let outcome = await Self.captureAndRecognize()
            await MainActor.run { self.finish(outcome) }
        }
    }

    private func finish(_ outcome: Outcome) {
        isBusy = false
        switch outcome {
        case .cancelled: break
        case .noText:
            toast.show(icon: "text.viewfinder", title: L10n.t("Không tìm thấy chữ"),
                       detail: L10n.t("Thử chọn vùng lớn hơn hoặc chữ rõ hơn."))
        case .text(let text):
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(text, forType: .string)
            let preview = text.replacingOccurrences(of: "\n", with: " ").prefix(60)
            toast.show(icon: "doc.on.clipboard", title: "\(L10n.t("Đã sao chép "))\(OCRText.lineCount(text))\(L10n.t(" dòng"))",
                       detail: String(preview))
        }
    }

    /// Off the main actor: the selection UI blocks until the user finishes, and Vision is heavy.
    nonisolated static func captureAndRecognize() async -> Outcome {
        await Task.detached(priority: .userInitiated) { () -> Outcome in
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("xfinder-ocr-\(UUID().uuidString).png")
            defer { try? FileManager.default.removeItem(at: url) }
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            // -i interactive selection, -x no shutter sound, -t png.
            p.arguments = ["-i", "-x", "-t", "png", url.path]
            guard (try? p.run()) != nil else { return .cancelled }
            p.waitUntilExit()
            // Esc leaves no file (exit status is 0 either way), so existence IS the cancel signal.
            guard let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size > 0,
                  let src = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return .cancelled }
            guard let text = OCRText.assemble(ScreenTextRecognizer.recognize(image)) else { return .noText }
            return .text(text)
        }.value
    }
}

/// A short confirmation panel, same behaviour as the colour picker's: non-activating,
/// mouse-transparent, one one-shot hide.
@MainActor
final class TextToast {
    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?

    func show(icon: String, title: String, detail: String) {
        hideWork?.cancel()
        panel?.orderOut(nil)
        let size = NSSize(width: 340, height: 62)
        let host = NSHostingController(rootView: TextToastView(icon: icon, title: title, detail: detail))
        host.view.frame = NSRect(origin: .zero, size: size)
        let p = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.contentViewController = host
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .statusBar
        p.hidesOnDeactivate = false
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main ?? NSScreen.screens.first
        if let frame = screen?.visibleFrame {
            p.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.maxY - size.height - 72))
        }
        p.orderFrontRegardless()
        panel = p
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.panel?.orderOut(nil); self?.panel = nil }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4, execute: work)
    }
}

struct TextToastView: View {
    let icon: String, title: String, detail: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 20)).foregroundColor(.accentColor).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .frame(width: 340, height: 62)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
