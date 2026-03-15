import Foundation

/// Generic trie for fast prefix-based lookups with weighted entries.
///
/// Thread-safety: Uses NSLock for all mutations and reads.
/// Not converted to `actor` because callers require synchronous access.
final class PrefixTrie<Value: Sendable>: @unchecked Sendable {

    struct TrieEntry: Sendable {
        let key: String
        let value: Value
        var weight: Double
    }

    // MARK: - Node

    private final class Node {
        var children: [Character: Node] = [:]
        var entry: TrieEntry?
    }

    // MARK: - State

    private let lock = NSLock()
    private let root = Node()
    private var _count = 0

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return _count
    }

    init() {}

    // MARK: - Insert

    func insert(key: String, value: Value, weight: Double = 0) {
        let lowered = key.lowercased()
        lock.lock()
        defer { lock.unlock() }

        var current = root
        for ch in lowered {
            if let child = current.children[ch] {
                current = child
            } else {
                let child = Node()
                current.children[ch] = child
                current = child
            }
        }

        if current.entry == nil {
            _count += 1
        }
        current.entry = TrieEntry(key: key, value: value, weight: weight)
    }

    // MARK: - Update Weight

    @discardableResult
    func updateWeight(for key: String, weight: Double) -> Bool {
        let lowered = key.lowercased()
        lock.lock()
        defer { lock.unlock() }

        guard let node = findNode(for: lowered), node.entry != nil else {
            return false
        }
        node.entry?.weight = weight
        return true
    }

    // MARK: - Search

    func search(prefix: String, limit: Int = 50) -> [TrieEntry] {
        let lowered = prefix.lowercased()
        lock.lock()
        defer { lock.unlock() }

        // Walk to the prefix node.
        var current = root
        for ch in lowered {
            guard let child = current.children[ch] else {
                return []
            }
            current = child
        }

        // Collect all terminal descendants.
        var results: [TrieEntry] = []
        collectEntries(from: current, into: &results)

        // Sort by weight descending, then alphabetically for stability.
        results.sort { lhs, rhs in
            if lhs.weight != rhs.weight {
                return lhs.weight > rhs.weight
            }
            return lhs.key.lowercased() < rhs.key.lowercased()
        }

        if results.count > limit {
            results.removeLast(results.count - limit)
        }

        return results
    }

    // MARK: - Contains

    func contains(_ key: String) -> Bool {
        let lowered = key.lowercased()
        lock.lock()
        defer { lock.unlock() }

        guard let node = findNode(for: lowered) else { return false }
        return node.entry != nil
    }

    // MARK: - Remove All

    func removeAll() {
        lock.lock()
        defer { lock.unlock() }

        root.children.removeAll()
        _count = 0
    }

    // MARK: - Private Helpers

    private func findNode(for loweredKey: String) -> Node? {
        var current = root
        for ch in loweredKey {
            guard let child = current.children[ch] else {
                return nil
            }
            current = child
        }
        return current
    }

    private func collectEntries(from node: Node, into results: inout [TrieEntry]) {
        if let entry = node.entry {
            results.append(entry)
        }
        for (_, child) in node.children {
            collectEntries(from: child, into: &results)
        }
    }
}
