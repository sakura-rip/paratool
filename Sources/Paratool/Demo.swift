import AppKit
import ParatoolCore

// Deterministic, local-only fixture for UI and watcher verification.
enum Demo {
    static func image() -> CGImage {
        let image = NSImage(size: NSSize(width: 1200, height: 760), flipped: true) { rect in
            NSColor(srgbRed: 0.96, green: 0.96, blue: 0.94, alpha: 1).setFill(); rect.fill()
            NSColor(srgbRed: 0.12, green: 0.15, blue: 0.20, alpha: 1).setFill(); NSRect(x: 0, y: 0, width: 1200, height: 64).fill()
            text("STUDIO  /  PROJECTS", at: CGPoint(x: 36, y: 22), size: 16, color: .white, weight: .bold)
            text("Overview     Activity     Settings", at: CGPoint(x: 840, y: 24), size: 13, color: .lightGray)
            text("Workspace overview", at: CGPoint(x: 58, y: 110), size: 36, color: .black, weight: .bold)
            text("A little clarity goes a long way.", at: CGPoint(x: 60, y: 160), size: 17, color: .darkGray)
            for (i, label) in ["Active projects", "In review", "Completed"].enumerated() {
                let x = CGFloat(60 + i * 368)
                NSColor.white.setFill(); NSBezierPath(roundedRect: NSRect(x: x, y: 220, width: 344, height: 146), xRadius: 14, yRadius: 14).fill()
                text(label, at: CGPoint(x: x + 24, y: 242), size: 14, color: .gray)
                text(["12", "04", "28"][i], at: CGPoint(x: x + 24, y: 280), size: 45, color: .black, weight: .semibold)
            }
            text("Recent projects", at: CGPoint(x: 60, y: 410), size: 22, color: .black, weight: .semibold)
            for (i, label) in ["Brand refresh", "Product launch", "Website update"].enumerated() {
                let y = CGFloat(458 + i * 76)
                NSColor.white.setFill(); NSBezierPath(roundedRect: NSRect(x: 60, y: y, width: 1080, height: 64), xRadius: 10, yRadius: 10).fill()
                text(label, at: CGPoint(x: 84, y: y + 21), size: 16, color: .black, weight: .medium)
                text(["Design", "Marketing", "Engineering"][i], at: CGPoint(x: 570, y: y + 23), size: 14, color: .gray)
                text(["In progress", "Review", "Completed"][i], at: CGPoint(x: 920, y: y + 23), size: 14, color: .systemIndigo)
            }
            return true
        }
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
    }
    static func text(_ string: String, at point: CGPoint, size: CGFloat, color: NSColor, weight: NSFont.Weight = .regular) {
        (string as NSString).draw(at: point, withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color])
    }
    static func annotate(_ capture: Capture) {
        let marks: [Annotation] = [
            Annotation(tool: .rectangle, points: [CGPoint(x: 426, y: 216), CGPoint(x: 776, y: 370)], color: InkColor.palette[3], width: 4),
            Annotation(tool: .arrow, points: [CGPoint(x: 850, y: 168), CGPoint(x: 732, y: 240)], color: InkColor.palette[0], width: 5),
            Annotation(tool: .text, points: [CGPoint(x: 824, y: 116)], color: InkColor.palette[0], width: 4, text: "ここを確認！")
        ]
        let scale = CGFloat(capture.image.width) / 1200
        capture.document.commit(marks.map { mark in
            var result = mark
            result.points = mark.points.map { CGPoint(x: $0.x * scale, y: $0.y * scale) }
            result.width *= scale
            return result
        })
    }
    static func populate(app: AppDelegate) {
        let image = image()
        for index in 1...3 { app.addCapture(url: URL(fileURLWithPath: "/tmp/Demo-\(index).png"), image: image) }
        if let capture = app.shelf.model.captures.first { annotate(capture); app.openEditor(capture) }
    }
}

enum SmokeTest {
    private static var watcher: CaptureWatcher?
    static func run(app: AppDelegate) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("paratool-smoke-\(UUID().uuidString)", isDirectory: true)
        do { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        catch { fail("temporary folder: \(error)") }
        let data = NSBitmapImageRep(cgImage: Demo.image()).representation(using: .png, properties: [:])!
        let metadata = try! PropertyListSerialization.data(fromPropertyList: true, format: .binary, options: 0)
        func write(_ name: String, screenshot: Bool) {
            let url = folder.appendingPathComponent(name)
            do { try data.write(to: url) } catch { fail("fixture write: \(error)") }
            if screenshot {
                let result = metadata.withUnsafeBytes { setxattr(url.path, "com.apple.metadata:kMDItemIsScreenCapture", $0.baseAddress, metadata.count, 0, 0) }
                if result != 0 { fail("fixture xattr") }
                if !CaptureWatcher.isScreenshot(url) { fail("metadata recognition") }
            }
        }
        write("baseline.png", screenshot: true)
        let watcher = CaptureWatcher(); self.watcher = watcher
        var received: [String] = []
        watcher.onCapture = { url, image in received.append(url.lastPathComponent); app.addCapture(url: url, image: image) }
        watcher.start(folder: folder)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            write("ordinary.png", screenshot: false)
            for i in 1...4 { write("capture-\(i).png", screenshot: true) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
            guard received.count == 4, Set(received).count == 4, !received.contains("baseline.png"), !received.contains("ordinary.png"), app.shelf.model.captures.count == 3 else {
                fail("watcher/history: received=\(received), shelf=\(app.shelf.model.captures.count)")
            }
            guard let capture = app.shelf.model.captures.first else { fail("missing capture") }
            Demo.annotate(capture); app.openEditor(capture)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("dist/verification", isDirectory: true)
                do {
                    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
                    try ImageRenderer.png(base: capture.image, annotations: capture.document.annotations)!.write(to: output.appendingPathComponent("annotated.png"))
                    for (name, view) in [("shelf", app.shelf.panel.contentView), ("editor", NSApp.windows.first(where: { $0.title.hasPrefix("Paratool —") })?.contentView)] {
                        guard let view else { fail("missing \(name) view") }
                        view.layoutSubtreeIfNeeded(); view.displayIfNeeded()
                        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { fail("snapshot \(name)") }
                        view.effectiveAppearance.performAsCurrentDrawingAppearance { view.cacheDisplay(in: view.bounds, to: rep) }
                        try rep.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("\(name).png"))
                    }
                    try FileManager.default.removeItem(at: folder)
                } catch { fail("export: \(error)") }
                print("SMOKE PASS: metadata detection, baseline exclusion, ordinary image exclusion, 4 captures → 3 thumbnails, editor and PNG export")
                fflush(stdout)
                NSApp.terminate(nil)
            }
        }
    }
    private static func fail(_ message: String) -> Never { fputs("SMOKE FAIL: \(message)\n", stderr); exit(1) }
}
