import XCTest
import AppKit
@testable import ParatoolCore

final class CoreTests: XCTestCase {
    func testShelfKeepsNewestThreeAndDoesNotDuplicate() {
        var history = RecentItems<String>(limit: 3)
        for item in ["a", "b", "c", "d", "c"] { history.insert(item, id: item) }
        XCTAssertEqual(history.items, ["c", "d", "b"])
        history.remove(id: "d")
        XCTAssertEqual(history.items, ["c", "b"])
    }

    func testCaptureWaitsForStableWriteAndIgnoresBaseline() {
        var tracker = CaptureTracker(baseline: ["old"])
        let one = FileStamp(size: 10, modified: 1)
        let two = FileStamp(size: 20, modified: 2)
        XCTAssertFalse(tracker.observe(id: "old", stamp: one))
        XCTAssertFalse(tracker.observe(id: "new", stamp: one))
        XCTAssertFalse(tracker.observe(id: "new", stamp: two))
        XCTAssertTrue(tracker.observe(id: "new", stamp: two))
        // Metadata can arrive after the file: keep retrying until accepted.
        XCTAssertTrue(tracker.observe(id: "new", stamp: two))
        tracker.accept(id: "new")
        XCTAssertFalse(tracker.observe(id: "new", stamp: two))
    }

    func testUndoRedoAndNewEditClearsRedo() {
        let document = AnnotationDocument()
        let mark = Annotation(tool: .rectangle, points: [.zero, CGPoint(x: 20, y: 20)])
        document.commit([mark])
        document.undo()
        XCTAssertTrue(document.annotations.isEmpty)
        document.redo()
        XCTAssertEqual(document.annotations.count, 1)
        document.undo()
        document.commit([Annotation(tool: .ellipse, points: [.zero, CGPoint(x: 5, y: 5)])])
        XCTAssertFalse(document.canRedo)
    }

    func testCanvasCoordinatesIgnoreZoomAndMargins() {
        let transform = CanvasTransform(imageSize: CGSize(width: 100, height: 80), bounds: CGRect(x: 0, y: 0, width: 300, height: 240), scale: 2)
        XCTAssertEqual(transform.imagePoint(from: CGPoint(x: 70, y: 80)), CGPoint(x: 10, y: 20))
        XCTAssertEqual(transform.imageRect, CGRect(x: 50, y: 40, width: 200, height: 160))
    }

    func testExportKeepsPixelSizeAndRedactionIsOpaque() throws {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 100, pixelsHigh: 80, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let base = try XCTUnwrap(rep.cgImage)
        let mark = Annotation(tool: .redact, points: [CGPoint(x: 10, y: 10), CGPoint(x: 40, y: 40)], color: .init(red: 1, green: 0, blue: 0, alpha: 0.1))
        let output = try XCTUnwrap(ImageRenderer.render(base: base, annotations: [mark]))
        XCTAssertEqual(output.width, 100)
        XCTAssertEqual(output.height, 80)
        let bitmap = NSBitmapImageRep(cgImage: output)
        // Assert encoded RGBA bytes; NSColor conversion can apply display/HDR transforms.
        var pixel = [UInt](repeating: 0, count: 4)
        bitmap.getPixel(&pixel, atX: 20, y: 20)
        XCTAssertEqual(pixel, [255, 0, 0, 255])
        bitmap.getPixel(&pixel, atX: 20, y: 60)
        XCTAssertEqual(pixel[3], 0, "Redaction must use top-left image coordinates")
    }
}
