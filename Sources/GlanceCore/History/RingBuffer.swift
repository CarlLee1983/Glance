/// 固定容量的環形緩衝,超出容量時丟棄最舊元素。供歷史曲線使用。
public struct RingBuffer<Element> {
    public let capacity: Int
    private var storage: [Element] = []

    public init(capacity: Int) {
        precondition(capacity > 0, "capacity must be > 0")
        self.capacity = capacity
        storage.reserveCapacity(capacity)
    }

    public mutating func append(_ element: Element) {
        storage.append(element)
        if storage.count > capacity {
            storage.removeFirst(storage.count - capacity)
        }
    }

    /// 由舊到新排列的元素快照。
    public var elements: [Element] { storage }

    public var last: Element? { storage.last }
    public var isEmpty: Bool { storage.isEmpty }
}
