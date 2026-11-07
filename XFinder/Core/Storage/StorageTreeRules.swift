import Foundation

struct StorageTreeNode: Sendable, Equatable, Identifiable {
    let id: Int
    let name: String
    let path: String
    let parent: Int?
    let isDirectory: Bool
    let isAggregate: Bool
    var bytes: Int64 = 0
    var fileCount = 0
    var skipped = false
    var children: [Int] = []
}

struct StorageTree: Sendable, Equatable {
    var nodes: [StorageTreeNode]
    var simplified: Bool
}

/// Flat indices avoid recursive ownership/destruction, including on very deep trees.
struct StorageTreeBuilder {
    static let nodeLimit = 100_000
    static let fileLimit = 20
    private(set) var nodes: [StorageTreeNode]
    private var directories: [String: Int] = ["": 0]
    private var aggregates: [Int: Int] = [:]
    private var filesByDirectory: [Int: [Int]] = [:]
    private var simplified = false
    private let limit: Int

    init(name: String, limit: Int = nodeLimit) {
        self.limit = max(2, limit)
        nodes = [.init(id: 0, name: name, path: "", parent: nil, isDirectory: true, isAggregate: false),
                 .init(id: 1, name: "", path: "", parent: 0, isDirectory: false, isAggregate: true)]
        nodes[0].children = [1]
        aggregates[0] = 1
    }

    private func owner(_ path: String) -> Int {
        var current = (path as NSString).deletingLastPathComponent
        while !current.isEmpty {
            if let id = directories[current] { return id }
            current = (current as NSString).deletingLastPathComponent
        }
        return 0
    }

    mutating func recordSkippedEntry() { nodes[0].skipped = true }

    mutating func directory(_ path: String, skipped: Bool = false) {
        let parent = owner(path)
        guard nodes.count + 2 <= limit else {
            simplified = true
            nodes[parent].skipped = nodes[parent].skipped || skipped
            return
        }
        let id = nodes.count
        nodes.append(.init(id: id, name: (path as NSString).lastPathComponent, path: path,
                           parent: parent, isDirectory: true, isAggregate: false, skipped: skipped))
        let aggregate = nodes.count
        nodes.append(.init(id: aggregate, name: "", path: path, parent: id, isDirectory: false, isAggregate: true))
        nodes[id].children = [aggregate]
        nodes[parent].children.append(id)
        directories[path] = id
        aggregates[id] = aggregate
    }

    static func sum(_ a: Int64, _ b: Int64) -> Int64 {
        let (value, overflow) = a.addingReportingOverflow(b)
        return overflow ? Int64.max : value
    }

    mutating func file(_ file: StorageScanFile) {
        guard file.logicalSize >= 0 else { return }
        let parent = owner(file.relativePath)
        let aggregate = aggregates[parent]!
        let directParent = (file.relativePath as NSString).deletingLastPathComponent
        let leaves = filesByDirectory[parent] ?? []
        let candidate = StorageTreeNode(id: nodes.count, name: file.name, path: file.relativePath,
            parent: parent, isDirectory: false, isAggregate: false, bytes: file.logicalSize, fileCount: 1)
        if directories[directParent] != parent {
            simplified = true
            fold(candidate, into: aggregate)
        } else if leaves.count < Self.fileLimit && nodes.count < limit {
            filesByDirectory[parent, default: []].append(nodes.count)
            nodes[parent].children.append(nodes.count)
            nodes.append(candidate)
        } else if let smallest = leaves.min(by: { precedes(nodes[$1], nodes[$0]) }), precedes(candidate, nodes[smallest]) {
            let old = nodes[smallest]
            fold(old, into: aggregate)
            nodes[smallest] = .init(id: smallest, name: candidate.name, path: candidate.path,
                parent: parent, isDirectory: false, isAggregate: false, bytes: candidate.bytes, fileCount: 1)
        } else {
            if leaves.count < Self.fileLimit { simplified = true }
            fold(candidate, into: aggregate)
        }
    }

    private func precedes(_ a: StorageTreeNode, _ b: StorageTreeNode) -> Bool {
        a.bytes == b.bytes ? a.path.utf8.lexicographicallyPrecedes(b.path.utf8) : a.bytes > b.bytes
    }

    private mutating func fold(_ node: StorageTreeNode, into id: Int) {
        nodes[id].bytes = Self.sum(nodes[id].bytes, node.bytes)
        nodes[id].fileCount += node.fileCount
    }

    mutating func finish() -> StorageTree {
        for id in nodes.indices.reversed() where nodes[id].isDirectory {
            var bytes: Int64 = 0
            var count = 0
            var skipped = nodes[id].skipped
            for child in nodes[id].children {
                bytes = Self.sum(bytes, nodes[child].bytes)
                count += nodes[child].fileCount
                skipped = skipped || nodes[child].skipped
            }
            nodes[id].bytes = bytes
            nodes[id].fileCount = count
            nodes[id].skipped = skipped
            nodes[id].children = nodes[id].children.filter { !nodes[$0].isAggregate || nodes[$0].fileCount > 0 }
                .sorted { precedes(nodes[$0], nodes[$1]) }
        }
        return .init(nodes: nodes, simplified: simplified)
    }
}

enum StorageChartPreferences {
    static let defaultStyle = "treemap"
    static let defaultFraction = 0.6
    static func style(_ value: String) -> String { value == "sunburst" ? value : defaultStyle }
    static func fraction(_ value: Double) -> Double {
        value.isFinite ? min(0.7, max(0.3, value)) : defaultFraction
    }
}
