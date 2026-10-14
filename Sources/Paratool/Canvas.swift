import AppKit
import ParatoolCore

final class AnnotationCanvas: NSView, NSTextViewDelegate {
    let capture: Capture
    var tool: AnnotationTool = .rectangle {
        willSet { finishText() }
        didSet { selectedID = nil; needsDisplay = true }
    }
    var ink = InkColor.palette[3]
    var lineWidth: CGFloat = 4
    var scale: CGFloat = 1 { didSet { needsDisplay = true } }
    var onChange: (() -> Void)?
    var selectedID: UUID?
    private var draft: Annotation?
    private var dragStart: CGPoint?
    private var original: Annotation?
    private var textMark: Annotation?
    private(set) var textView: NSTextView?
    var isEditingText: Bool { textView != nil }
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
        let affine = NSAffineTransform(); affine.translateX(by: t.imageRect.minX, yBy: t.imageRect.minY); affine.scale(by: scale); affine.concat()
        var annotations = capture.document.annotations.filter { $0.id != textMark?.id }
        if let draft {
            if let i = annotations.firstIndex(where: { $0.id == draft.id }) { annotations[i] = draft }
            else { annotations.append(draft) }
        }
        ImageRenderer.draw(annotations, base: capture.image)
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
        finishText()
        window?.makeFirstResponder(self)
        guard transform.imageRect.contains(convert(event.locationInWindow, from: nil)) else { return }
        let p = point(event)
        let found = capture.document.annotations.reversed().first { $0.hitTest(p, tolerance: max(6 / scale, $0.width / 2)) }
        dragStart = p
        if tool == .select {
            if event.clickCount == 2, let found, found.tool == .text { beginText(at: found.points[0], existing: found); dragStart = nil; return }
            selectedID = found?.id; original = found
        } else if tool == .text {
            if let found, found.tool == .text { beginText(at: found.points[0], existing: found) }
            else { beginText(at: p) }
            dragStart = nil
        } else if tool == .tag {
            let number = (capture.document.annotations.filter { $0.tool == .tag }.compactMap { Int($0.text) }.max() ?? 0) + 1
            let tag = Annotation(tool: .tag, points: [p], color: ink, width: max(lineWidth, 28 / (scale * 10)), text: String(number))
            capture.document.commit(capture.document.annotations + [tag]); dragStart = nil; changed()
        } else { draft = Annotation(tool: tool, points: [p, p], color: ink, width: lineWidth) }
        needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart else { return }
        let p = point(event)
        if tool == .select, let original { draft = original.translated(dx: p.x - start.x, dy: p.y - start.y) }
        else if tool == .pen { draft?.points.append(p) }
        else if draft != nil { draft?.points[1] = p }
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        defer { draft = nil; original = nil; dragStart = nil; needsDisplay = true }
        guard let draft else { return }
        var annotations = capture.document.annotations
        if let i = annotations.firstIndex(where: { $0.id == draft.id }) { annotations[i] = draft }
        else if draft.bounds.width > 1 || draft.bounds.height > 1 { annotations.append(draft) }
        capture.document.commit(annotations); onChange?()
    }

    func beginText(at point: CGPoint, existing: Annotation? = nil) {
        finishText()
        let mark = existing ?? Annotation(tool: .text, points: [point], color: ink, width: max(lineWidth, 16 / (scale * 6)))
        textMark = mark; selectedID = nil
        let input = NSTextView(frame: .zero)
        input.delegate = self; input.isRichText = false; input.allowsUndo = true
        input.isAutomaticQuoteSubstitutionEnabled = false; input.isAutomaticDashSubstitutionEnabled = false
        input.drawsBackground = false; input.textColor = mark.color.nsColor; input.insertionPointColor = mark.color.nsColor
        input.font = NSFont.systemFont(ofSize: mark.font.pointSize * scale, weight: .semibold)
        input.textContainerInset = NSSize(width: 3, height: 1)
        input.textContainer?.lineFragmentPadding = 0
        input.textContainer?.widthTracksTextView = false
        input.textContainer?.containerSize = NSSize(width: 100_000, height: 100_000)
        input.isHorizontallyResizable = false; input.isVerticallyResizable = false
        input.wantsLayer = true; input.layer?.borderColor = NSColor.systemBlue.cgColor; input.layer?.borderWidth = 1
        input.layer?.cornerRadius = 3
        input.string = mark.text; input.toolTip = "Enterで確定 · Shift+Enterで改行 · Escでキャンセル"
        textView = input; addSubview(input); updateTextFrame()
        window?.makeFirstResponder(input)
        input.setSelectedRange(NSRange(location: (input.string as NSString).length, length: 0))
        needsDisplay = true
    }
    private func updateTextFrame() {
        guard let input = textView, let mark = textMark, let point = mark.points.first else { return }
        let size = ((input.string.isEmpty ? "文字を入力" : input.string) as NSString).size(withAttributes: [.font: input.font!])
        input.frame = NSRect(x: transform.imageRect.minX + point.x * scale - 3, y: transform.imageRect.minY + point.y * scale - 1,
            width: max(180, size.width + 14), height: max(34, size.height + 8))
    }
    func textDidChange(_ notification: Notification) { updateTextFrame() }
    func textDidEndEditing(_ notification: Notification) { finishText() }
    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            if NSApp.currentEvent?.modifierFlags.contains(.shift) == true { return false }
            finishText(); return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) { finishText(cancel: true); return true }
        return false
    }
    func finishText(cancel: Bool = false) {
        guard let input = textView, var mark = textMark else { return }
        textView = nil; textMark = nil; input.delegate = nil
        mark.text = input.string
        input.removeFromSuperview()
        if !cancel {
            var marks = capture.document.annotations
            if let index = marks.firstIndex(where: { $0.id == mark.id }) { marks.remove(at: index) }
            if !mark.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { marks.append(mark) }
            capture.document.commit(marks)
            selectedID = marks.contains(where: { $0.id == mark.id }) ? mark.id : nil
        }
        window?.makeFirstResponder(self); changed()
    }
    func deleteSelection() {
        guard let selectedID else { return }
        capture.document.commit(capture.document.annotations.filter { $0.id != selectedID })
        self.selectedID = nil; changed()
    }
    func changed() { needsDisplay = true; onChange?() }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 51 || event.keyCode == 117 { deleteSelection() }
        else if event.keyCode == 53 { selectedID = nil; needsDisplay = true }
        else { super.keyDown(with: event) }
    }
}
