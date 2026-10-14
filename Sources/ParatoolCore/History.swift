import Foundation

public struct RecentItems<Item> {
    private var entries: [(id: String, item: Item)] = []
    public let limit: Int
    public init(limit: Int = 3) { self.limit = max(1, limit) }
    public var items: [Item] { entries.map(\.item) }
    public mutating func insert(_ item: Item, id: String) {
        entries.removeAll { $0.id == id }
        entries.insert((id, item), at: 0)
        entries = Array(entries.prefix(limit))
    }
    public mutating func remove(id: String) { entries.removeAll { $0.id == id } }
}
