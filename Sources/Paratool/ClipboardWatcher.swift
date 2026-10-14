import AppKit
import ParatoolCore

final class ClipboardWatcher {
    static let exportMarker = NSPasteboard.PasteboardType("app.paratool.annotated-export")
    private var timer: Timer?
    private var tracker: ClipboardTracker
    private let pasteboard: NSPasteboard
    var onCapture: ((CGImage) -> Void)?
    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
        tracker = ClipboardTracker(initialChangeCount: pasteboard.changeCount)
    }
    func start() {
        timer?.invalidate()
        let timer = Timer(timeInterval: 0.4, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
    func poll() {
        let types = pasteboard.types ?? []
        guard tracker.shouldImport(changeCount: pasteboard.changeCount,
            hasImage: types.contains(.png) || types.contains(.tiff),
            isOwnExport: types.contains(Self.exportMarker)) else { return }
        // Decode the advertised representation directly; NSImage(pasteboard:) does
        // not consistently read a PNG-only pasteboard on every macOS version.
        for type in [NSPasteboard.PasteboardType.png, .tiff] {
            guard let data = pasteboard.data(forType: type), let image = NSImage(data: data),
                  let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
            onCapture?(cgImage)
            return
        }
    }
    deinit { timer?.invalidate() }
}
