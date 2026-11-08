#!/bin/sh
# Generate the compressed fixture in a separate process, then sample the isolated XCTest process
# while one real ImageRunner.transform call resizes it from 48 MP to 12 MP.
set -eu
cd "$(dirname "$0")/.."
WORK="${TMPDIR:-/tmp}/xf-t33-footprint-$$"
mkdir -p "$WORK"
trap 'rm -rf "$WORK"' EXIT INT TERM
cat > "$WORK/generate.swift" <<'SWIFT'
import Foundation
import ImageIO
import CoreGraphics

let url = URL(fileURLWithPath: CommandLine.arguments[1])
let width = 8_000
let height = 6_000
let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                              bytesPerRow: 0, space: colorSpace,
                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
      let image = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil) else {
    fatalError("Could not create the 48 MP JPEG probe fixture")
}
CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
guard CGImageDestinationFinalize(destination) else { fatalError("Could not write the 48 MP JPEG probe fixture") }
let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? NSNumber
print("FIXTURE=\(url.path) DIMENSIONS=8000x6000 BYTES=\(bytes?.intValue ?? 0)")
SWIFT
swift "$WORK/generate.swift" "$WORK/source.jpg"
XF_IMAGE_MEMORY_PROBE_PATH="$WORK/source.jpg" swift test --package-path Tests --filter ImageTransformMemoryProbeTests.testProbePeakFootprintForOne48MPJPEGResize
