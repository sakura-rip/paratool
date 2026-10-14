import Foundation

public struct FileStamp: Equatable {
    public let size: Int
    public let modified: TimeInterval
    public init(size: Int, modified: TimeInterval) { self.size = size; self.modified = modified }
}

public struct CaptureTracker {
    private var accepted: Set<String>
    private var pending: [String: (stamp: FileStamp, attempts: Int)] = [:]
    public init(baseline: Set<String> = []) { accepted = baseline }
    public mutating func observe(id: String, stamp: FileStamp) -> Bool {
        guard !accepted.contains(id), stamp.size > 0 else { return false }
        let previous = pending[id]
        let attempts = (previous?.attempts ?? 0) + 1
        // Allow delayed metadata indexing, but don't recheck non-screenshots forever.
        if attempts > 120 { accept(id: id); return false }
        pending[id] = (stamp, attempts)
        return previous?.stamp == stamp
    }
    public mutating func accept(id: String) { accepted.insert(id); pending.removeValue(forKey: id) }
    public mutating func prune(existing: Set<String>) {
        accepted.formIntersection(existing)
        pending = pending.filter { existing.contains($0.key) }
    }
}
