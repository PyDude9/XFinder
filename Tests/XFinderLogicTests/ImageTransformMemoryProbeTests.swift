import XCTest
import Foundation
import Dispatch
import MachO
import Darwin

final class ImageTransformMemoryProbeTests: XCTestCase {
    private final class Sampler {
        private let lock = NSLock()
        private let queue = DispatchQueue(label: "xf.image.memory-probe")
        private var timer: DispatchSourceTimer?
        private var peak: UInt64 = 0

        func start() {
            sample()
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now(), repeating: .milliseconds(2), leeway: .microseconds(500))
            timer.setEventHandler { [weak self] in self?.sample() }
            self.timer = timer
            timer.resume()
        }

        func stop() -> UInt64 {
            timer?.cancel()
            timer = nil
            queue.sync { sample() }
            lock.lock(); defer { lock.unlock() }
            return peak
        }

        private func sample() {
            guard let current = Self.currentFootprint() else { return }
            lock.lock(); peak = max(peak, current); lock.unlock()
        }

        private static func currentFootprint() -> UInt64? {
            var info = task_vm_info_data_t()
            var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
            let result = withUnsafeMutablePointer(to: &info) { pointer in
                pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                    task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
                }
            }
            guard result == KERN_SUCCESS else { return nil }
            return UInt64(info.phys_footprint)
        }
    }

    func testProbePeakFootprintForOne48MPJPEGResize() throws {
        guard let sourcePath = ProcessInfo.processInfo.environment["XF_IMAGE_MEMORY_PROBE_PATH"] else {
            throw XCTSkip("Set XF_IMAGE_MEMORY_PROBE_PATH to a pre-generated 48 MP JPEG to run the footprint probe.")
        }
        let source = URL(fileURLWithPath: sourcePath)
        let options = ImageRunner.TransformOptions(target: .longestEdge(4_000), format: .jpeg, quality: 0.82)
        let sampler = Sampler()
        sampler.start()
        let result = ImageRunner.transform(source, options: options)
        let peak = sampler.stop()
        guard case .success(let output) = result else { return XCTFail("ImageRunner.transform refused the probe fixture: \(result)") }
        defer { try? FileManager.default.removeItem(at: output) }
        let bytes = try FileManager.default.attributesOfItem(atPath: output.path)[.size] as? NSNumber
        XCTAssertNotNil(bytes)
        print("XF_IMAGE_TRANSFORM_PEAK_PHYS_FOOTPRINT_BYTES=\(peak)")
        print("XF_IMAGE_TRANSFORM_PEAK_PHYS_FOOTPRINT_MIB=\(Double(peak) / 1_048_576)")
    }
}
