import AppKit
import ParatoolCore

final class AnnotationCanvas: NSView {
    let capture: Capture
    var tool: AnnotationTool = .rectangle { didSet { selectedID = nil; needsDisplay = true } }
    var ink = InkColor.palette[3]
    var lineWidth: CGFloat = 4
    var scale: CGFloat = 1 { didSet { needsDisplay = true } }
    var onChange: (() -> Void)?
    var onText: ((CGPoint) -> Void)?
    var selectedID: UUID?
    private var draft: Annotation?
    private var dragStart: CGPoint?
    private var original: Annotation?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    var imageSize: CGSize { CGSize(width: capture.image.width, height: capture.image.height) }
    var transform: CanvasTransform { CanvasTransform(imageSize: imageSize, bounds: bounds, scale: scale) }
    init(capture: Capture) { self.capture = capture; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 0.085, alpha: 1).setFill(); bounds.fill()
        let t = transform
        NSColor.black.withAlphaComponent(0.45).setFill()
        t.imageRect.offsetBy(dx: 0, dy: 4).insetBy(dx: -1, dy: -1).fill()
        capture.preview.draw(in: t.imageRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: t.imageRect).addClip()
        let affine = AffineTransform(translationByX: t.imageRect.minX, byY: t.imageRect.minY)
        (affine as NSAffineTransform).concat()
        let zoom = NSAffineTransform(); zoom.scale(by: scale); zoom.concat()
        var annotations = capture.document.annotations
        if let draft {
            if let i = annotations.firstIndex(where: { $0.id == draft.id }) { annotations[i] = draft }
            else { annotations.append(draft) }
        }
        ImageRenderer.draw(annotations)
        if let selected = annotations.first(where: { $0.id == selectedID }) {
            NSColor.systemBlue.setStroke()
            let outline = NSBezierPath(rect: selected.bounds.insetBy(dx: -5 / scale, dy: -5 / scale))
            outline.lineWidth = 1 / scale
            outline.setLineDash([4 / scale, 3 / scale], count: 2, phase: 0)
            outline.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()
    }
    private func point(_ event: NSEvent) -> CGPoint {
        let p = transform.imagePoint(from: convert(event.locationInWindow, from: nil))
        return CGPoint(x: max(0, min(imageSize.width, p.x)), y: max(0, min(imageSize.height, p.y)))
    }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        guard transform.imageRect.contains(convert(event.locationInWindow, from: nil)) else { return }
        let p = point(event)
        dragStart = p
        if tool == .select {
            let found = capture.document.annotations.reversed().first { $0.hitTest(p, tolerance: max(6 / scale, $0.width / 2)) }
            selectedID = found?.id; original = found
        } else if tool == .text { onText?(p); dragStart = nil }
        else { draft = Annotation(tool: tool, points: [p, p], color: ink, width: lineWidth) }
        needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart else { return }
        let p = point(event)
        if tool == .select, let original {
            draft = original.translated(dx: p.x - start.x, dy: p.y - start.y)
        } else if tool == .pen { draft?.points.append(p) }
        else if draft != nil { draft?.points[1] = p }
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        defer { draft = nil; original = nil; dragStart = nil; needsDisplay = true }
        guard let draft else { return }
        var annotations = capture.document.annotations
        if let i = annotations.firstIndex(where: { $0.id == draft.id }) { annotations[i] = draft }
        else if draft.bounds.width > 1 || draft.bounds.height > 1 { annotations.append(draft) }
        capture.document.commit(annotations)
        onChange?()
    }
    func deleteSelection() {
        guard let selectedID else { return }
        capture.document.commit(capture.document.annotations.filter { $0.id != selectedID })
        self.selectedID = nil
        changed()
    }
    func changed() { needsDisplay = true; onChange?() }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 51 || event.keyCode == 117 { deleteSelection() }
        else if event.keyCode == 53 { selectedID = nil; needsDisplay = true }
        else { super.keyDown(with: event) }
    }
}
