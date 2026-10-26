import Dispatch
import Foundation

/// XF-T32 W0 — dispatches memory-pressure relief to registered caches. Contract §D.
///
/// One `DispatchSource` on the main queue; each event is mapped through `PressureRules.level(fromDispatchMask:)`
/// and every reliever runs in registration order with `PressureRules.plan(for:)`. `simulate(_:)` takes the same path.
@MainActor final class MemoryPressureRelief {
    static let shared: MemoryPressureRelief = MemoryPressureRelief()

    private struct Reliever {
        let name: String
        let action: @MainActor (PressureRules.Plan) -> Void
    }

    private(set) var lastRelief: (level: PressureRules.Level, at: Date)?
    private var relievers: [Reliever] = []
    private var source: DispatchSourceMemoryPressure?

    /// Idempotent: a second call keeps the existing source.
    func start() {
        guard source == nil else { return }
        let pressure: DispatchSourceMemoryPressure = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical], queue: .main)
        // The source targets `.main`, so the handler always runs on the main run loop.
        pressure.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                self?.handleSourceEvent()
            }
        }
        source = pressure
        pressure.resume()
    }

    /// Registers a reliever; a second registration under the same name replaces the first in place
    /// (keeps its original position, so order stays stable across re-registration).
    func register(_ name: String, _ reliever: @escaping @MainActor (PressureRules.Plan) -> Void) {
        let entry: Reliever = Reliever(name: name, action: reliever)
        if let index: Int = relievers.firstIndex(where: { $0.name == name }) {
            relievers[index] = entry
        } else {
            relievers.append(entry)
        }
    }

    func simulate(_ level: PressureRules.Level) {
        relieve(level)
    }

    private func handleSourceEvent() {
        guard let source else { return }
        handle(rawMask: source.data.rawValue)
    }

    private func handle(rawMask: UInt) {
        guard let level: PressureRules.Level = PressureRules.level(fromDispatchMask: rawMask) else { return }
        relieve(level)
    }

    private func relieve(_ level: PressureRules.Level) {
        let plan: PressureRules.Plan = PressureRules.plan(for: level)
        // Snapshot so a reliever that registers another reliever does not mutate the array mid-iteration.
        let snapshot: [Reliever] = relievers
        for reliever in snapshot {
            reliever.action(plan)
        }
        lastRelief = (level, Date())
    }
}
