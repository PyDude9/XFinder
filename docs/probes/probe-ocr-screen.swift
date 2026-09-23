// probe-ocr-screen.swift — read the screen as text.
//
// Why this exists: `screencapture` works on this host but the agent cannot view images,
// and the Accessibility tree only exposes what an app chose to publish. Vision's text
// recogniser reads what is actually *rendered*, which is the only way to answer "does
// this page look right / did Mission Control open?" without a human looking.
//
// Usage:
//   swift docs/probes/probe-ocr-screen.swift                 # capture + OCR the whole screen
//   swift docs/probes/probe-ocr-screen.swift <path.png>      # OCR an existing image
//
// Capture happens through `screencapture -x` so this needs Screen Recording permission
// for the calling process.

import AppKit
import Foundation
import Vision

func ocr(path: String) {
    guard let img = NSImage(contentsOfFile: path),
          let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        print("could not load image at \(path)")
        return
    }
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = false
    let handler = VNImageRequestHandler(cgImage: cg, options: [:])
    do { try handler.perform([request]) } catch {
        print("vision failed: \(error)")
        return
    }
    let results = request.results ?? []
    // Group by vertical position so the output reads roughly top-to-bottom.
    let lines = results.compactMap { obs -> (y: CGFloat, x: CGFloat, text: String)? in
        guard let c = obs.topCandidates(1).first else { return nil }
        let b = obs.boundingBox
        return (y: 1 - b.midY, x: b.minX, text: c.string)
    }.sorted { a, b in abs(a.y - b.y) < 0.012 ? a.x < b.x : a.y < b.y }

    print("--- OCR \(path) — \(lines.count) text lines ---")
    for l in lines { print(l.text) }
}

let args = CommandLine.arguments
var path = "/tmp/xfinder-ocr.png"
if args.count >= 2 {
    path = args[1]
} else {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    task.arguments = ["-x", path]
    try? task.run()
    task.waitUntilExit()
}
ocr(path: path)
