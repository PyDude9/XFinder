import SwiftUI
import CoreGraphics

/// The editor's drawing surface: the base image fitted (aspect) inside a checkerboard area, marks
/// drawn with `Canvas`, and every gesture that creates/edits a `Mark`. All hit-testing and mark
/// geometry happen in IMAGE PIXELS (`AnnotationDocument`'s space); this view only converts between
/// that space and its own view points (`imageToView` / `viewToImage`), so `AnnotationRenderer` and
/// the canvas preview never disagree about where something is.
struct AnnotateCanvasView: View {
    @Bindable var model: AnnotateDocumentModel
    var color: Binding<MarkColor>
    var width: Binding<StrokeWidth>

    /// In-flight gesture state: the mark being drawn, before it is committed to the undo stack.
    @State private var liveMark: Mark?
    @State private var dragStartImagePoint: CGPoint?
    @State private var movingOriginal: Mark?
    /// Blur preview cache, keyed by the exact rect so repeated geometry reads do not re-render it.
    @State private var blurPreviewCache: [String: CGImage] = [:]
    @State private var textDraft: String = ""
    @FocusState private var textFieldFocused: Bool

    var body: some View {
        GeometryReader { geo in
            let fit = fittedRect(imageSize: model.document.pixelSize, in: geo.size)
            ZStack {
                Checkerboard()
                    .frame(width: geo.size.width, height: geo.size.height)

                Image(decorative: model.baseImage, scale: model.document.scale)
                    .resizable()
                    .frame(width: fit.width, height: fit.height)
                    .position(x: fit.midX, y: fit.midY)

                Canvas { context, _ in
                    for mark in model.document.marks {
                        draw(mark, selected: mark.id == model.selection, into: &context, fit: fit)
                    }
                    if let live = liveMark {
                        draw(live, selected: false, into: &context, fit: fit)
                    }
                    if let crop = model.document.crop {
                        drawCropOverlay(crop, into: &context, fit: fit, fullSize: model.document.pixelSize)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .allowsHitTesting(false)

                textEditingOverlay(fit: fit)
            }
            .contentShape(Rectangle())
            .gesture(drag(fit: fit))
            .onTapGesture { location in handleTap(at: location, fit: fit) }
            .clipped()
        }
    }

    // MARK: - Coordinate mapping

    /// Where the full image (aspect-fit) sits inside the available view size, centred.
    private func fittedRect(imageSize: CGSize, in available: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return CGRect(origin: .zero, size: available) }
        let scale = min(available.width / imageSize.width, available.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let origin = CGPoint(x: (available.width - size.width) / 2, y: (available.height - size.height) / 2)
        return CGRect(origin: origin, size: size)
    }

    /// View point → image pixel (origin top-left in both spaces).
    private func viewToImage(_ p: CGPoint, fit: CGRect) -> CGPoint {
        guard fit.width > 0, fit.height > 0 else { return .zero }
        let sx = model.document.pixelSize.width / fit.width
        let sy = model.document.pixelSize.height / fit.height
        return CGPoint(x: (p.x - fit.minX) * sx, y: (p.y - fit.minY) * sy)
    }

    /// Image pixel → view point.
    private func imageToView(_ p: CGPoint, fit: CGRect) -> CGPoint {
        guard model.document.pixelSize.width > 0, model.document.pixelSize.height > 0 else { return .zero }
        let sx = fit.width / model.document.pixelSize.width
        let sy = fit.height / model.document.pixelSize.height
        return CGPoint(x: fit.minX + p.x * sx, y: fit.minY + p.y * sy)
    }

    private func imageScale(fit: CGRect) -> CGFloat {
        guard model.document.pixelSize.width > 0 else { return 1 }
        return fit.width / model.document.pixelSize.width
    }

    // MARK: - Gestures

    private func drag(fit: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in handleDragChanged(value, fit: fit) }
            .onEnded { value in handleDragEnded(value, fit: fit) }
    }

    private func handleDragChanged(_ value: DragGesture.Value, fit: CGRect) {
        let start = viewToImage(value.startLocation, fit: fit)
        let current = viewToImage(value.location, fit: fit)

        switch model.activeTool {
        case .select:
            if dragStartImagePoint == nil {
                // Begin a move only if the drag started on the selected mark.
                guard let id = model.selection, let mark = model.document.marks.first(where: { $0.id == id }),
                      mark.hitTest(start, tolerance: 8 * model.document.scale) else { return }
                dragStartImagePoint = start
                movingOriginal = mark
            }
            guard let original = movingOriginal, let origin = dragStartImagePoint else { return }
            let delta = CGVector(dx: current.x - origin.x, dy: current.y - origin.y)
            liveMark = original.moved(by: delta)

        case .arrow:
            dragStartImagePoint = start
            liveMark = Mark(kind: .arrow(from: start, to: current), color: color.wrappedValue, width: width.wrappedValue)

        case .rectangle:
            dragStartImagePoint = start
            liveMark = Mark(kind: .rectangle(rect(from: start, to: current)), color: color.wrappedValue, width: width.wrappedValue)

        case .blur:
            dragStartImagePoint = start
            liveMark = Mark(kind: .blur(rect(from: start, to: current)), color: color.wrappedValue, width: width.wrappedValue)

        case .highlighter:
            dragStartImagePoint = start
            liveMark = Mark(kind: .highlight(rect(from: start, to: current)), color: color.wrappedValue, width: width.wrappedValue)

        case .crop:
            dragStartImagePoint = start
            // Represented as a transient rectangle mark purely for live preview; committed to
            // `document.crop` on drag end, never added to `marks`.
            liveMark = Mark(kind: .rectangle(rect(from: start, to: current)), color: .white, width: .thin)

        case .text, .counter:
            break // created on tap, not drag
        }
    }

    private func handleDragEnded(_ value: DragGesture.Value, fit: CGRect) {
        defer { liveMark = nil; dragStartImagePoint = nil; movingOriginal = nil }

        switch model.activeTool {
        case .select:
            guard let moved = liveMark else { return }
            var doc = model.document
            doc.replace(moved)
            model.commit(doc)

        case .arrow, .rectangle, .blur, .highlighter:
            guard let mark = liveMark, mark.bounds.width > 1 || mark.bounds.height > 1 else { return }
            var doc = model.document
            doc.add(mark)
            model.commit(doc)
            model.selection = mark.id
            if case .blur = mark.kind { invalidateBlurPreview() }

        case .crop:
            guard let mark = liveMark, case .rectangle(let r) = mark.kind, r.width > 2, r.height > 2 else { return }
            model.setCrop(r)

        case .text, .counter:
            break
        }
    }

    private func handleTap(at location: CGPoint, fit: CGRect) {
        let p = viewToImage(location, fit: fit)
        switch model.activeTool {
        case .select:
            model.selection = model.document.mark(at: p)?.id

        case .text:
            let mark = Mark(kind: .text(origin: p, string: "", fontSize: 18 * model.document.scale),
                             color: color.wrappedValue, width: width.wrappedValue)
            var doc = model.document
            doc.add(mark)
            model.commit(doc)
            model.selection = mark.id
            textDraft = ""
            model.editingText = mark.id

        case .counter:
            let mark = Mark(kind: .counter(center: p, number: model.document.nextCounterNumber),
                             color: color.wrappedValue, width: width.wrappedValue)
            var doc = model.document
            doc.add(mark)
            model.commit(doc)
            model.selection = mark.id

        case .arrow, .rectangle, .blur, .highlighter, .crop:
            break
        }
    }

    // MARK: - Inline text editing

    @ViewBuilder
    private func textEditingOverlay(fit: CGRect) -> some View {
        if let editingID = model.editingText,
           let mark = model.document.marks.first(where: { $0.id == editingID }),
           case .text(let origin, _, let fontSize) = mark.kind {
            let viewOrigin = imageToView(origin, fit: fit)
            let viewFontSize = fontSize * imageScale(fit: fit)
            TextField("", text: $textDraft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: max(viewFontSize, 8)))
                .foregroundColor(swatch(mark.color))
                .focused($textFieldFocused)
                .frame(minWidth: 40, alignment: .leading)
                .position(x: viewOrigin.x + 60, y: viewOrigin.y + 10)
                .onAppear { textDraft = ""; textFieldFocused = true }
                .onSubmit { commitTextEdit(editingID) }
                .onExitCommand { commitTextEdit(editingID) }
                .onChange(of: textFieldFocused) { _, focused in
                    if !focused { commitTextEdit(editingID) }
                }
        }
    }

    private func commitTextEdit(_ id: UUID) {
        defer { model.editingText = nil }
        var doc = model.document
        let trimmed = textDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            doc.remove(id: id)
            model.selection = nil
        } else if let existing = doc.marks.first(where: { $0.id == id }), case .text(let origin, _, let fontSize) = existing.kind {
            doc.replace(Mark(id: id, kind: .text(origin: origin, string: trimmed, fontSize: fontSize),
                              color: existing.color, width: existing.width))
        }
        model.commit(doc)
    }

    // MARK: - Drawing

    private func draw(_ mark: Mark, selected: Bool, into context: inout GraphicsContext, fit: CGRect) {
        let c = swatch(mark.color)
        let lineWidth = max(1, mark.width.points * imageScale(fit: fit))

        switch mark.kind {
        case .arrow(let from, let to):
            let a = imageToView(from, fit: fit), b = imageToView(to, fit: fit)
            var path = Path()
            path.move(to: a); path.addLine(to: b)
            context.stroke(path, with: .color(c), lineWidth: lineWidth)
            drawArrowHead(from: a, to: b, width: lineWidth, color: c, into: &context)

        case .rectangle(let r):
            let viewRect = CGRect(origin: imageToView(r.origin, fit: fit),
                                   size: CGSize(width: r.width * imageScale(fit: fit), height: r.height * imageScale(fit: fit)))
            context.stroke(Path(viewRect), with: .color(c), lineWidth: lineWidth)

        case .text(let origin, let string, let fontSize):
            guard !string.isEmpty else { break }
            let p = imageToView(origin, fit: fit)
            let resolved = context.resolve(Text(string).font(.system(size: max(fontSize * imageScale(fit: fit), 8))).foregroundColor(c))
            context.draw(resolved, at: p, anchor: .topLeading)

        case .counter(let center, let number):
            let p = imageToView(center, fit: fit)
            let radius = max(10, 10 * imageScale(fit: fit))
            let circle = Path(ellipseIn: CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2))
            context.fill(circle, with: .color(c))
            let resolved = context.resolve(Text("\(number)").font(.system(size: radius, weight: .bold)).foregroundColor(.white))
            context.draw(resolved, at: p, anchor: .center)

        case .blur(let r):
            let viewRect = CGRect(origin: imageToView(r.origin, fit: fit),
                                   size: CGSize(width: r.width * imageScale(fit: fit), height: r.height * imageScale(fit: fit)))
            if let img = blurPreview(for: r) {
                context.draw(Image(decorative: img, scale: 1), in: viewRect)
            } else {
                context.fill(Path(viewRect), with: .color(.gray.opacity(0.6)))
            }
            if selected { context.stroke(Path(viewRect), with: .color(.white.opacity(0.8)), style: StrokeStyle(lineWidth: 1, dash: [4, 3])) }

        case .highlight(let r):
            let viewRect = CGRect(origin: imageToView(r.origin, fit: fit),
                                   size: CGSize(width: r.width * imageScale(fit: fit), height: r.height * imageScale(fit: fit)))
            context.blendMode = .multiply
            context.fill(Path(viewRect), with: .color(.yellow.opacity(0.4)))
            context.blendMode = .normal
        }

        if selected, !mark.bounds.isEmpty {
            let b = mark.bounds
            let viewRect = CGRect(origin: imageToView(CGPoint(x: b.minX, y: b.minY), fit: fit),
                                   size: CGSize(width: b.width * imageScale(fit: fit), height: b.height * imageScale(fit: fit)))
            context.stroke(Path(viewRect), with: .color(.accentColor), style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
        }
    }

    private func drawArrowHead(from: CGPoint, to: CGPoint, width: CGFloat, color: Color, into context: inout GraphicsContext) {
        let angle = atan2(to.y - from.y, to.x - from.x)
        let headLength = max(10, width * 2.2)
        let headAngle: CGFloat = .pi / 7
        let p1 = CGPoint(x: to.x - headLength * cos(angle - headAngle), y: to.y - headLength * sin(angle - headAngle))
        let p2 = CGPoint(x: to.x - headLength * cos(angle + headAngle), y: to.y - headLength * sin(angle + headAngle))
        var head = Path()
        head.move(to: to); head.addLine(to: p1); head.addLine(to: p2); head.closeSubpath()
        context.fill(head, with: .color(color))
    }

    private func drawCropOverlay(_ crop: CGRect, into context: inout GraphicsContext, fit: CGRect, fullSize: CGSize) {
        let full = CGRect(origin: .zero, size: fullSize)
        let viewFull = CGRect(origin: imageToView(full.origin, fit: fit),
                               size: CGSize(width: full.width * imageScale(fit: fit), height: full.height * imageScale(fit: fit)))
        let viewCrop = CGRect(origin: imageToView(crop.origin, fit: fit),
                               size: CGSize(width: crop.width * imageScale(fit: fit), height: crop.height * imageScale(fit: fit)))
        var dim = Path(viewFull)
        dim.addPath(Path(viewCrop))
        context.fill(dim, with: .color(.black.opacity(0.45)), style: FillStyle(eoFill: true))
        context.stroke(Path(viewCrop), with: .color(.white), lineWidth: 1.5)
    }

    private func rect(from a: CGPoint, to b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    private func swatch(_ c: MarkColor) -> Color {
        let rgb = c.rgb
        return Color(red: rgb.r, green: rgb.g, blue: rgb.b)
    }

    // MARK: - Blur preview (real pixelation via AnnotationRenderer, cached by rect)

    private func blurPreview(for rect: CGRect) -> CGImage? {
        let key = "\(Int(rect.minX)),\(Int(rect.minY)),\(Int(rect.width)),\(Int(rect.height))"
        if let cached = blurPreviewCache[key] { return cached }
        // Render just this one mark against the base image so the cost stays proportional to the
        // blurred region, not the whole canvas.
        var doc = AnnotationDocument(pixelSize: model.document.pixelSize, scale: model.document.scale)
        doc.add(Mark(kind: .blur(rect), color: .red, width: .medium))
        guard let rendered = AnnotationRenderer.render(base: model.baseImage, document: doc),
              let cropped = rendered.cropping(to: rect) else { return nil }
        blurPreviewCache[key] = cropped
        return cropped
    }

    private func invalidateBlurPreview() { blurPreviewCache.removeAll() }
}

/// A tiled grey/white checkerboard, drawn once per geometry change — the standard "this has
/// transparency" background behind the fitted image.
private struct Checkerboard: View {
    var tile: CGFloat = 10

    var body: some View {
        Canvas { context, size in
            let cols = Int(ceil(size.width / tile))
            let rows = Int(ceil(size.height / tile))
            for row in 0..<max(rows, 0) {
                for col in 0..<max(cols, 0) {
                    let isDark = (row + col) % 2 == 0
                    let r = CGRect(x: CGFloat(col) * tile, y: CGFloat(row) * tile, width: tile, height: tile)
                    context.fill(Path(r), with: .color(isDark ? Color.gray.opacity(0.18) : Color.gray.opacity(0.08)))
                }
            }
        }
    }
}
