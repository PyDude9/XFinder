import SwiftUI
import AppKit
import CoreImage.CIFilterBuiltins

/// A QR code for a string — CoreImage's `CIQRCodeGenerator` (public, offline), scaled with nearest-neighbour so the
/// modules stay crisp. Rendered once per `text` in `.task(id:)`, never inside `body`.
struct QRCodeView: View {
    let text: String
    var size: CGFloat = 180
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).interpolation(.none).resizable().scaledToFit()
            } else {
                Color.clear
            }
        }
        .frame(width: size, height: size)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: XFinderTokens.Radius.control, style: .continuous))
        .task(id: text) { image = Self.render(text, pixels: Int(size) * 2) }
        .accessibilityLabel(text)
    }

    /// `pixels` square; "M" correction so a scuffed screen or a glossy reflection still scans.
    static func render(_ text: String, pixels: Int) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage, output.extent.width > 0 else { return nil }
        let scale = CGFloat(pixels) / output.extent.width
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cg = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: pixels, height: pixels))
    }
}
