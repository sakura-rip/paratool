import AppKit
import SwiftUI
import ParatoolCore

final class Capture: Identifiable, ObservableObject {
    let id = UUID()
    let url: URL
    let image: CGImage
    let document = AnnotationDocument()
    @Published private(set) var shelfPreview: NSImage
    init(url: URL, image: CGImage) {
        self.url = url; self.image = image
        shelfPreview = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        document.onChange = { [weak self] in
            guard let self, let rendered = ImageRenderer.render(base: self.image, annotations: self.document.annotations) else { return }
            self.shelfPreview = NSImage(cgImage: rendered, size: NSSize(width: rendered.width, height: rendered.height))
        }
    }
    lazy var preview = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
}

final class ShelfModel: ObservableObject {
    @Published var captures: [Capture] = []
    var open: ((Capture) -> Void)?
    var dismiss: ((Capture) -> Void)?
}

private struct ShelfView: View {
    @ObservedObject var model: ShelfModel
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(model.captures) { capture in
                ZStack(alignment: .topTrailing) {
                    DraggableCapture(capture: capture, open: { model.open?(capture) })
                        .frame(width: 240, height: 164)
                    Button { model.dismiss?(capture) } label: {
                        Image(systemName: "xmark").font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.black)
                            .frame(width: 32, height: 32)
                            .background(Color.white, in: Circle())
                            .overlay(Circle().strokeBorder(Color.black.opacity(0.25), lineWidth: 1))
                            .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
                    }.buttonStyle(.plain).padding(8).accessibilityLabel("このスクショを一覧から閉じる").help("一覧から外す（ファイルは残ります）")
                }
            }
        }.frame(width: 240)
            .environment(\.colorScheme, .dark)
    }
}

private struct DraggableCapture: NSViewRepresentable {
    @ObservedObject var capture: Capture
    var open: () -> Void
    func makeNSView(context: Context) -> CaptureDragView { CaptureDragView(frame: .zero) }
    func updateNSView(_ view: CaptureDragView, context: Context) {
        view.capture = capture
        view.open = open
        view.needsDisplay = true
    }
}

final class CaptureDragView: NSView, NSDraggingSource {
    var capture: Capture?
    var open: (() -> Void)?
    private var downEvent: NSEvent?
    override var isFlipped: Bool { true }
    override init(frame: NSRect) {
        super.init(frame: frame)
        toolTip = "クリックで編集・ドラッグで画像やファイルパスを渡す"
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("スクリーンショットを編集、またはドラッグして書き出す")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func accessibilityPerformPress() -> Bool { open?(); return true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        guard let capture else { return }
        NSGraphicsContext.saveGraphicsState()
        let outline = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 9, yRadius: 9)
        outline.addClip()
        NSColor(srgbRed: 0.10, green: 0.11, blue: 0.14, alpha: 1).setFill(); bounds.fill()
        let imageArea = NSRect(x: 0, y: 0, width: bounds.width, height: 132)
        let size = capture.shelfPreview.size
        let scale = min(imageArea.width / size.width, imageArea.height / size.height)
        let rect = NSRect(x: (imageArea.width - size.width * scale) / 2, y: (imageArea.height - size.height * scale) / 2, width: size.width * scale, height: size.height * scale)
        capture.shelfPreview.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        NSColor.white.withAlphaComponent(0.06).setFill()
        NSRect(x: 0, y: 132, width: bounds.width, height: 32).fill()
        ("\(capture.image.width) × \(capture.image.height)" as NSString).draw(at: NSPoint(x: 10, y: 140), withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular), .foregroundColor: NSColor.lightGray])
        ("編集 / ドラッグ" as NSString).draw(at: NSPoint(x: 146, y: 140), withAttributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.white])
        NSColor.white.withAlphaComponent(0.12).setStroke(); outline.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }
    override func mouseDown(with event: NSEvent) { downEvent = event }
    override func mouseUp(with event: NSEvent) {
        guard downEvent != nil else { return }
        downEvent = nil
        if bounds.contains(convert(event.locationInWindow, from: nil)) { open?() }
    }
    override func mouseDragged(with event: NSEvent) {
        guard let start = downEvent, let capture,
              hypot(event.locationInWindow.x - start.locationInWindow.x, event.locationInWindow.y - start.locationInWindow.y) >= 5 else { return }
        downEvent = nil
        do {
            let export = try DragExport.prepare(base: capture.image, annotations: capture.document.annotations, name: capture.url.lastPathComponent)
            let item = NSDraggingItem(pasteboardWriter: export.pasteboardItem())
            item.setDraggingFrame(NSRect(x: 0, y: 0, width: bounds.width, height: 132), contents: capture.shelfPreview)
            beginDraggingSession(with: [item], event: start, source: self)
        } catch {
            let alert = NSAlert()
            alert.messageText = "ドラッグ用の画像を作成できませんでした"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
}

final class ShelfController {
    let model = ShelfModel()
    let panel: NSPanel
    init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.contentView = NSHostingView(rootView: ShelfView(model: model))
        NotificationCenter.default.addObserver(self, selector: #selector(reposition), name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }
    func update(_ captures: [Capture]) {
        model.captures = captures
        guard !captures.isEmpty else { panel.orderOut(nil); return }
        reposition()
        panel.orderFrontRegardless()
    }
    @objc func reposition() {
        // screens.first is the display containing the menu bar, independent of editor focus.
        guard let screen = NSScreen.screens.first else { return }
        let frame = screen.visibleFrame
        let height = CGFloat(model.captures.count * 164 + max(0, model.captures.count - 1) * 10)
        panel.setFrame(NSRect(x: frame.minX + 16, y: frame.minY + 16, width: 240, height: height), display: true)
    }
}
