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
        // Read bytes directly: getPixel's imported Int/UInt type differs by SDK.
        let bytes = try XCTUnwrap(bitmap.bitmapData)
        let offset = 20 * bitmap.bytesPerRow + 20 * bitmap.samplesPerPixel
        XCTAssertEqual(Array(UnsafeBufferPointer(start: bytes + offset, count: 4)), [255, 0, 0, 255])
        XCTAssertEqual(bytes[60 * bitmap.bytesPerRow + 20 * bitmap.samplesPerPixel + 3], 0)
    }

    func testClipboardIgnoresBaselineRepeatedAndOwnCopies() {
        var tracker = ClipboardTracker(initialChangeCount: 10)
        XCTAssertFalse(tracker.shouldImport(changeCount: 10, hasImage: true, isOwnExport: false))
        XCTAssertFalse(tracker.shouldImport(changeCount: 11, hasImage: false, isOwnExport: false))
        XCTAssertTrue(tracker.shouldImport(changeCount: 12, hasImage: true, isOwnExport: false))
        XCTAssertFalse(tracker.shouldImport(changeCount: 12, hasImage: true, isOwnExport: false))
        XCTAssertFalse(tracker.shouldImport(changeCount: 13, hasImage: true, isOwnExport: true))
        XCTAssertTrue(tracker.shouldImport(changeCount: 14, hasImage: true, isOwnExport: false))
    }

    func testHighlightCompositesWithOpacity() throws {
        let context = CGContext(data: nil, width: 60, height: 60, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 60, height: 60))
        let mark = Annotation(tool: .highlight, points: [CGPoint(x: 10, y: 10), CGPoint(x: 50, y: 50)], color: .init(red: 1, green: 0, blue: 0, alpha: 0.5))
        let output = try XCTUnwrap(ImageRenderer.render(base: context.makeImage()!, annotations: [mark]))
        let bitmap = NSBitmapImageRep(cgImage: output)
        let pixel = try XCTUnwrap(bitmap.bitmapData) + 20 * bitmap.bytesPerRow + 20 * 4
        XCTAssertEqual(pixel[0], 255)
        XCTAssertTrue((125...129).contains(Int(pixel[1])))
        XCTAssertTrue((125...129).contains(Int(pixel[2])))
        XCTAssertEqual(pixel[3], 255)
    }

    func testMosaicRemovesFineDetailAndPreservesOutside() throws {
        let context = CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        for x in 0..<64 {
            context.setFillColor(CGColor(gray: x.isMultiple(of: 2) ? 1 : 0, alpha: 1))
            context.fill(CGRect(x: x, y: 0, width: 1, height: 64))
        }
        let mark = Annotation(tool: .mosaic, points: [CGPoint(x: 16, y: 16), CGPoint(x: 48, y: 48)], width: 4)
        let output = try XCTUnwrap(ImageRenderer.render(base: context.makeImage()!, annotations: [mark]))
        let bitmap = NSBitmapImageRep(cgImage: output)
        let bytes = try XCTUnwrap(bitmap.bitmapData)
        let a = 20 * bitmap.bytesPerRow + 20 * 4
        let b = 20 * bitmap.bytesPerRow + 21 * 4
        XCTAssertEqual(bytes[a], bytes[b], "Adjacent stripes must become one mosaic block")
        XCTAssertNotEqual(bytes[4 * 4], bytes[5 * 4], "Outside the selection must remain unchanged")
    }

    func testTagHasVisibleBoundsAndCanBeSelected() {
        let tag = Annotation(tool: .tag, points: [CGPoint(x: 20, y: 30)], text: "1")
        XCTAssertGreaterThan(tag.bounds.width, 20)
        XCTAssertTrue(tag.hitTest(CGPoint(x: tag.bounds.midX, y: tag.bounds.midY), tolerance: 3))
        XCTAssertFalse(tag.hitTest(CGPoint(x: 400, y: 400), tolerance: 3))
    }
}
