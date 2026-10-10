import Foundation

/// The Notch hub's action row (B2d): which actions make sense for the files held, and the progress
/// of the one running. Pure, so both rules are tested.
///
/// Progress is counted in FILES DONE, the only thing that is actually measured: `zip`, `tar` and
/// PDFKit report no byte progress, and a smooth percentage would be invented (Honesty Rule). A
/// single-file job therefore shows 0 → done, not a fake ramp.
enum NotchActions {

    enum Action: Hashable {
        case zip                                   // all held items → one archive
        case mergePDFs                             // ≥ 2 PDFs → one PDF
        case convert(ImageEngine.Target)           // each image
        case removeBackground                      // each image
        case airDrop                               // all held items
    }

    /// Actions offered for `items`, in display order. Image targets come from the encoders this Mac
    /// has (`encodable`), and a target is offered only if at least one held image is not already in it.
    static func available(for items: [URL], encodable: [String]) -> [Action] {
        guard !items.isEmpty else { return [] }
        var out: [Action] = [.zip]
        if items.filter({ $0.pathExtension.lowercased() == "pdf" }).count >= 2 { out.append(.mergePDFs) }
        let images = items.filter(ImageEngine.isImage)
        if !images.isEmpty {
            for t in ImageEngine.availableTargets(encodable: encodable) where [.jpeg, .png].contains(t) {
                if images.contains(where: { !ImageEngine.isSameFormat($0, t) }) { out.append(.convert(t)) }
            }
            out.append(.removeBackground)
        }
        out.append(.airDrop)
        return out
    }

    /// The files an action actually works on (a convert skips images already in the target format).
    static func inputs(for action: Action, from items: [URL]) -> [URL] {
        switch action {
        case .zip, .airDrop: return items
        case .mergePDFs: return items.filter { $0.pathExtension.lowercased() == "pdf" }
        case .convert(let t): return items.filter { ImageEngine.isImage($0) && !ImageEngine.isSameFormat($0, t) }
        case .removeBackground: return items.filter(ImageEngine.isImage)
        }
    }

    /// Jobs that produce one output from all inputs count as ONE step; per-file jobs count each file.
    static func stepCount(for action: Action, inputs: Int) -> Int {
        switch action {
        case .zip, .mergePDFs, .airDrop: return inputs > 0 ? 1 : 0
        case .convert, .removeBackground: return inputs
        }
    }
}

/// One running (or finished) hub job.
struct NotchTask: Equatable {
    enum Phase: Equatable { case running, finished, cancelled }

    let action: NotchActions.Action
    let total: Int
    private(set) var done = 0
    private(set) var failed = 0
    private(set) var outputs: [URL] = []
    /// First failure's store key + detail — enough for one honest line.
    private(set) var firstFailure: (key: String, detail: String)?
    private(set) var phase: Phase = .running

    init(action: NotchActions.Action, total: Int) {
        self.action = action
        self.total = max(total, 0)
        if self.total == 0 { phase = .finished }
    }

    var fraction: Double { total == 0 ? 1 : Double(done + failed) / Double(total) }
    var isRunning: Bool { phase == .running }

    /// A finished step. Ignored once the task is no longer running (a late callback after cancel).
    mutating func stepSucceeded(output: URL?) {
        guard isRunning else { return }
        done += 1
        if let output { outputs.append(output) }
        if done + failed >= total { phase = .finished }
    }

    mutating func stepFailed(key: String, detail: String) {
        guard isRunning else { return }
        failed += 1
        if firstFailure == nil { firstFailure = (key, detail) }
        if done + failed >= total { phase = .finished }
    }

    mutating func cancel() { if isRunning { phase = .cancelled } }

    static func == (a: NotchTask, b: NotchTask) -> Bool {
        a.action == b.action && a.total == b.total && a.done == b.done && a.failed == b.failed
            && a.outputs == b.outputs && a.phase == b.phase
            && a.firstFailure?.key == b.firstFailure?.key && a.firstFailure?.detail == b.firstFailure?.detail
    }
}
