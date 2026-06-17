import Foundation

/// 純 value type:持有整棵樹 + 目前路徑(節點 id 序列),提供下鑽/回上層/跳層,
/// 以及移除節點後沿祖先重算大小。無副作用,可完整單元測試。
public struct DiskTreeNavigator: Equatable, Sendable {
    public private(set) var root: DiskNode
    /// 從 root 到目前節點的子節點 id 序列(不含 root)。
    public private(set) var path: [String]

    public init(root: DiskNode) {
        self.root = root
        self.path = []
    }

    public var breadcrumb: [DiskNode] {
        var nodes = [root]
        var node = root
        for id in path {
            guard let next = node.children.first(where: { $0.id == id && !$0.isAggregate }) else { break }
            nodes.append(next)
            node = next
        }
        return nodes
    }

    public var currentNode: DiskNode { breadcrumb.last ?? root }

    public var canGoUp: Bool { !path.isEmpty }

    public mutating func drill(into child: DiskNode) {
        guard child.kind == .folder, !child.isAggregate,
              currentNode.children.contains(where: { $0.id == child.id }) else { return }
        path.append(child.id)
    }

    public mutating func goUp() {
        if !path.isEmpty { path.removeLast() }
    }

    /// depth 0 = root;depth n = path 前 n 段。
    public mutating func jump(toDepth depth: Int) {
        guard depth >= 0, depth <= path.count else { return }
        path = Array(path.prefix(depth))
    }

    public mutating func remove(ids: Set<String>) {
        root = Self.removing(ids: ids, from: root)
        clampPath()
    }

    /// 移除指定 id 的節點,並由下往上重算各層 folder 大小(file 與 aggregate 保持原值)。
    private static func removing(ids: Set<String>, from node: DiskNode) -> DiskNode {
        guard !node.children.isEmpty else { return node }
        let kept = node.children
            .filter { !ids.contains($0.id) }
            .map { removing(ids: ids, from: $0) }
        guard node.kind == .folder, !node.isAggregate else { return node }
        let total = kept.reduce(UInt64(0)) { $0 + $1.sizeBytes }
        return DiskNode(
            url: node.url, name: node.name, kind: node.kind, sizeBytes: total,
            modifiedAt: node.modifiedAt, children: kept,
            isAggregate: node.isAggregate, aggregateCount: node.aggregateCount
        )
    }

    /// 樹變動後,把 path 裁到仍存在的最深有效層。
    private mutating func clampPath() {
        var valid: [String] = []
        var node = root
        for id in path {
            guard let next = node.children.first(where: { $0.id == id && !$0.isAggregate }) else { break }
            valid.append(id)
            node = next
        }
        path = valid
    }
}
