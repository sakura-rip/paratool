import AppKit
import CoreServices
import ImageIO
import Darwin
import ParatoolCore

final class CaptureWatcher {
    private let queue = DispatchQueue(label: "app.paratool.capture", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var tracker = CaptureTracker()
    private var folder: URL?
    private var lastError: String?
    private var needsBaseline = false
    var onCapture: ((URL, CGImage) -> Void)?
    var onStatus: ((String?) -> Void)?

    static var systemFolder: URL {
        let domain = "com.apple.screencapture" as CFString
        CFPreferencesAppSynchronize(domain)
        if let location = CFPreferencesCopyAppValue("location" as CFString, domain) as? String {
            return URL(fileURLWithPath: (location as NSString).expandingTildeInPath, isDirectory: true)
        }
        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
    }

    func start(folder: URL) {
        queue.async { [weak self] in
            guard let self else { return }
            self.timer?.cancel()
            self.folder = folder
            do {
                let existing = try self.files(in: folder)
                self.tracker = CaptureTracker(baseline: Set(existing.map(\.path)))
                self.needsBaseline = false
                self.report(nil)
            } catch {
                self.tracker = CaptureTracker()
                self.needsBaseline = true
                self.report("保存先を開けません。メニューからフォルダを選択してください。")
            }
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now() + 0.75, repeating: 0.75)
            timer.setEventHandler { [weak self] in self?.scan() }
            self.timer = timer
            timer.resume()
        }
    }

    func ignore(_ url: URL) { queue.async { self.tracker.accept(id: url.path) } }
    private func files(in folder: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey], options: [.skipsHiddenFiles]).filter {
            ["png", "jpg", "jpeg", "heic", "tiff", "tif"].contains($0.pathExtension.lowercased())
        }
    }
    private func scan() {
        guard let folder else { return }
        do {
            let urls = try files(in: folder)
            if needsBaseline {
                tracker = CaptureTracker(baseline: Set(urls.map(\.path)))
                needsBaseline = false
                report(nil)
                return
            }
            tracker.prune(existing: Set(urls.map(\.path)))
            let sorted = urls.sorted {
                let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return a < b
            }
            for url in sorted {
                guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]), values.isRegularFile == true else { continue }
                let stamp = FileStamp(size: values.fileSize ?? 0, modified: values.contentModificationDate?.timeIntervalSince1970 ?? 0)
                guard tracker.observe(id: url.path, stamp: stamp), Self.isScreenshot(url) else { continue }
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetStatus(source) == .statusComplete,
                      let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else { continue }
                tracker.accept(id: url.path)
                DispatchQueue.main.async { [weak self] in self?.onCapture?(url, image) }
            }
            report(nil)
        } catch { report("保存先を読み取れません。メニューから保存先を選び直してください。") }
    }
    static func isScreenshot(_ url: URL) -> Bool {
        let key = "com.apple.metadata:kMDItemIsScreenCapture"
        let length = getxattr(url.path, key, nil, 0, 0, 0)
        if length > 0 && length < 4096 {
            var bytes = [UInt8](repeating: 0, count: length)
            let count = getxattr(url.path, key, &bytes, length, 0, 0)
            if count == length, let value = try? PropertyListSerialization.propertyList(from: Data(bytes), format: nil) {
                if let bool = value as? Bool { return bool }
                if let string = value as? String { return string == "1" || string.lowercased() == "true" }
            }
        }
        if let item = MDItemCreate(kCFAllocatorDefault, url.path as CFString),
           let value = MDItemCopyAttribute(item, "kMDItemIsScreenCapture" as CFString) as? NSNumber { return value.boolValue }
        return false
    }
    private func report(_ message: String?) {
        guard message != lastError else { return }
        lastError = message
        DispatchQueue.main.async { [weak self] in self?.onStatus?(message) }
    }
}
