public struct ClipboardTracker {
    private var lastChangeCount: Int
    public init(initialChangeCount: Int) { lastChangeCount = initialChangeCount }
    public mutating func shouldImport(changeCount: Int, hasImage: Bool, isOwnExport: Bool) -> Bool {
        guard changeCount != lastChangeCount else { return false }
        lastChangeCount = changeCount
        return hasImage && !isOwnExport
    }
}
