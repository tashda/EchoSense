import Foundation
import Testing
@testable import EchoSense

// MARK: - Basic Operations

@Test
func insertAndContains() {
    let trie = PrefixTrie<String>()
    trie.insert(key: "users", value: "table")
    #expect(trie.contains("users"))
    #expect(!trie.contains("orders"))
}

@Test
func caseInsensitiveLookup() {
    let trie = PrefixTrie<String>()
    trie.insert(key: "Users", value: "table")
    #expect(trie.contains("users"))
    #expect(trie.contains("USERS"))
    #expect(trie.contains("Users"))
}

@Test
func countTracksInsertions() {
    let trie = PrefixTrie<String>()
    #expect(trie.count == 0)
    trie.insert(key: "a", value: "1")
    trie.insert(key: "b", value: "2")
    #expect(trie.count == 2)
}

@Test
func duplicateInsertUpdatesValue() {
    let trie = PrefixTrie<String>()
    trie.insert(key: "users", value: "old")
    trie.insert(key: "users", value: "new")
    #expect(trie.count == 1)
    let results = trie.search(prefix: "users")
    #expect(results.count == 1)
    #expect(results[0].value == "new")
}

// MARK: - Prefix Search

@Test
func searchByPrefix() {
    let trie = PrefixTrie<String>()
    trie.insert(key: "users", value: "table")
    trie.insert(key: "user_roles", value: "table")
    trie.insert(key: "orders", value: "table")

    let results = trie.search(prefix: "us")
    #expect(results.count == 2)
    let keys = results.map(\.key)
    #expect(keys.contains("users"))
    #expect(keys.contains("user_roles"))
}

@Test
func searchEmptyPrefixReturnsAll() {
    let trie = PrefixTrie<String>()
    trie.insert(key: "a", value: "1")
    trie.insert(key: "b", value: "2")
    trie.insert(key: "c", value: "3")

    let results = trie.search(prefix: "")
    #expect(results.count == 3)
}

@Test
func searchRespectsLimit() {
    let trie = PrefixTrie<String>()
    for i in 0..<100 {
        trie.insert(key: "item\(i)", value: "\(i)")
    }

    let results = trie.search(prefix: "item", limit: 5)
    #expect(results.count == 5)
}

@Test
func searchNoMatchReturnsEmpty() {
    let trie = PrefixTrie<String>()
    trie.insert(key: "users", value: "table")

    let results = trie.search(prefix: "xyz")
    #expect(results.isEmpty)
}

// MARK: - Weight-Based Ordering

@Test
func searchOrdersByWeightDescending() {
    let trie = PrefixTrie<String>()
    trie.insert(key: "users", value: "table", weight: 10)
    trie.insert(key: "user_roles", value: "table", weight: 50)
    trie.insert(key: "user_settings", value: "table", weight: 30)

    let results = trie.search(prefix: "user")
    #expect(results.count == 3)
    #expect(results[0].key == "user_roles")
    #expect(results[1].key == "user_settings")
    #expect(results[2].key == "users")
}

@Test
func updateWeightChangesOrdering() {
    let trie = PrefixTrie<String>()
    trie.insert(key: "a", value: "1", weight: 10)
    trie.insert(key: "ab", value: "2", weight: 5)

    #expect(trie.updateWeight(for: "ab", weight: 20))

    let results = trie.search(prefix: "a")
    #expect(results[0].key == "ab")
}

@Test
func updateWeightReturnsFalseForMissing() {
    let trie = PrefixTrie<String>()
    #expect(!trie.updateWeight(for: "missing", weight: 10))
}

// MARK: - Remove All

@Test
func removeAllClearsTrie() {
    let trie = PrefixTrie<String>()
    trie.insert(key: "a", value: "1")
    trie.insert(key: "b", value: "2")
    trie.removeAll()

    #expect(trie.count == 0)
    #expect(!trie.contains("a"))
    #expect(trie.search(prefix: "").isEmpty)
}

// MARK: - Preserves Original Casing

@Test
func preservesOriginalKeyCase() {
    let trie = PrefixTrie<String>()
    trie.insert(key: "UserRoles", value: "table")

    let results = trie.search(prefix: "user")
    #expect(results.count == 1)
    #expect(results[0].key == "UserRoles")
}
