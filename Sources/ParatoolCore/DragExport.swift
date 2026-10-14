import AppKit
import CryptoKit

/// A stable snapshot: subsequent edits must not change an already dropped file.
public struct DragExport {
    public let url: URL
    public let png: Data

    public static func prepare(base: CGImage, annotations: [Annotation], name: String, directory: URL? = nil) throws -> DragExport {
        guard let png = ImageRenderer.png(base: base, annotations: annotations) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let root: URL
        if let directory { root = directory }
        else {
            root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("Paratool/DragExports", isDirectory: true)
        }
        let digest = SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined()
        let folder = root.appendingPathComponent(digest, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let stem = String(URL(fileURLWithPath: name).deletingPathExtension().lastPathComponent.prefix(100))
            .replacingOccurrences(of: ":", with: "-")
        let url = folder.appendingPathComponent((stem.isEmpty ? "Screenshot" : stem) + ".png")
        if (try? Data(contentsOf: url)) != png { try png.write(to: url, options: .atomic) }
        return DragExport(url: url, png: png)
    }

    public func pasteboardItem() -> NSPasteboardItem {
        let item = NSPasteboardItem()
        item.setString(url.absoluteString, forType: .fileURL)
        item.setData(png, forType: .png)
        if let tiff = NSImage(data: png)?.tiffRepresentation { item.setData(tiff, forType: .tiff) }
        item.setString(url.path, forType: .string)
        return item
    }
}
