import Foundation
import ImageIO
import CoreGraphics

/// `XFinder --vision <job>`: the app binary as its own short-lived Vision worker. The image's bytes arrive on stdin, the
/// answer goes to stdout, the exit status says what happened (`Status`). Decided in `XFinderApp.init` before any scene or
/// AppKit object exists, like `--mcp`; `main` never returns.
///
/// Why a child (2026-10-21): the first Vision request in a process takes its footprint from ~10 MB to 106–150 MB and keeps
/// +21 MB (`.fast` text), +29 MB (foreground mask) or +54 MB (`.accurate` text) for good — `malloc_zone_pressure_relief`
/// frees nothing, 60 s of idling changes nothing (probes `scratchpad/ocrmem`). The clipboard reads the text of every copied
/// image, so a few screenshots took the installed app from 43 MB to 125 MB (peak 170 MB). A whole child run costs 0.1 s
/// (`.fast`) / 0.2 s (`.accurate`, cutout) and its memory is the system's again when it exits.
enum VisionChild {
    static let flag = "--vision"

    enum Job: String, CaseIterable {
        case ocrFast = "ocr-fast", ocrAccurate = "ocr-accurate", cutout
    }

    /// The child's exit statuses. Anything else (a kill, a crash) is "no answer": the parent does the work itself.
    enum Status {
        static let ok: Int32 = 0
        static let notAnImage: Int32 = 2
        static let noSubject: Int32 = 3
        static let visionFailed: Int32 = 4
        static let usage: Int32 = 64
    }

    /// Only the app can be its own child: under `swift test` the executable is the test runner, which must never be
    /// started with `--vision`.
    static var isAvailable: Bool { Bundle.main.bundleIdentifier == "com.xfinder.app" && Bundle.main.executableURL != nil }

    /// One child at a time: three screenshots copied in a row would otherwise be three ~100 MB processes at once.
    private static let oneAtATime = NSLock()

    /// The word after `--vision`; nil for anything else, so a typo is a usage error, not a silent default.
    static func job(fromArguments args: [String]) -> Job? {
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return Job(rawValue: args[i + 1])
    }

    /// An uncompressed TIFF: encoding a full-screen PNG costs more than the recognition saves.
    static func encode(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data as CFMutableData, "public.tiff" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest) ? data as Data : nil
    }

    static func decode(_ data: Data) -> CGImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    /// The child. Never returns.
    static func main() -> Never {
        guard let job = job(fromArguments: CommandLine.arguments) else { exit(Status.usage) }
        let input = FileHandle.standardInput.readDataToEndOfFile()
        guard let image = decode(input) else { exit(Status.notAnImage) }
        switch job {
        case .ocrFast, .ocrAccurate:
            let lines = ScreenTextRecognizer.recognizeHere(image, level: job == .ocrFast ? .fast : .accurate)
            FileHandle.standardOutput.write(OCRWire.encode(lines))
            exit(Status.ok)
        case .cutout:
            switch ImageRunner.cutoutHere(image, name: "stdin") {
            case .success(let png):
                FileHandle.standardOutput.write(png)
                exit(Status.ok)
            case .failure(.noSubject):
                exit(Status.noSubject)
            case .failure:
                exit(Status.visionFailed)
            }
        }
    }

    /// The parent: the child's exit status and stdout, or nil when it could not start, was killed, or crashed.
    static func run(_ job: Job, imageData: Data) -> (status: Int32, output: Data)? {
        guard let exe = Bundle.main.executableURL else { return nil }
        oneAtATime.lock()
        defer { oneAtATime.unlock() }
        let p = Process()
        p.executableURL = exe
        p.arguments = [flag, job.rawValue]
        let inPipe = Pipe(), out = Pipe()
        p.standardInput = inPipe
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        // A stuck child must not hold the next one forever: measured ≤ 0.2 s warm; the very first run after a build waited
        // on the Neural Engine daemon once for > 15 s.
        let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 30, execute: killer)
        // F_SETNOSIGPIPE: a child that dies before reading its stdin must not take XFinder down with SIGPIPE. The child reads
        // all of stdin before it writes a byte, so writing first and reading after cannot deadlock.
        _ = fcntl(inPipe.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        try? inPipe.fileHandleForWriting.write(contentsOf: imageData)
        try? inPipe.fileHandleForWriting.close()
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        killer.cancel()
        guard p.terminationReason == .exit else { return nil }
        return (p.terminationStatus, outData)
    }
}
