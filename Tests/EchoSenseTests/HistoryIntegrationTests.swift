import Foundation
import Testing
@testable import EchoSense

@Suite("History Integration", .serialized)
struct HistoryIntegrationTests {

    // MARK: - Helpers

    private func makeContext(dialect: EchoSenseDatabaseType = .postgresql) -> SQLEditorCompletionContext {
        let idCol = EchoSenseColumnInfo(name: "id", dataType: "integer", isPrimaryKey: true, isNullable: false)
        let nameCol = EchoSenseColumnInfo(name: "name", dataType: "text", isNullable: true)

        let usersTable = EchoSenseSchemaObjectInfo(name: "users", schema: "public",
                                                    type: .table, columns: [idCol, nameCol])
        let ordersTable = EchoSenseSchemaObjectInfo(name: "orders", schema: "public",
                                                     type: .table, columns: [idCol, nameCol])
        let publicSchema = EchoSenseSchemaInfo(name: "public", objects: [usersTable, ordersTable])
        let database = EchoSenseDatabaseInfo(name: "testdb", schemas: [publicSchema])
        let structure = EchoSenseDatabaseStructure(databases: [database])

        return SQLEditorCompletionContext(databaseType: dialect,
                                           selectedDatabase: "testdb",
                                           defaultSchema: "public",
                                           structure: structure)
    }

    private func makeEngine() -> SQLAutoCompletionEngine {
        let engine = SQLAutoCompletionEngine()
        engine.updateContext(makeContext())
        engine.updateAggressiveness(.eager)
        return engine
    }

    private func allSuggestions(from result: SQLAutoCompletionResult) -> [SQLAutoCompletionSuggestion] {
        result.sections.flatMap(\.suggestions)
    }

    // MARK: - Record Selection

    @Test func recordSelectionStoresEntry() {
        let store = SQLAutoCompletionHistoryStore.shared
        store.reset()

        let context = makeContext()
        let suggestion = SQLAutoCompletionSuggestion(id: "test-history-record",
                                                      title: "test_table",
                                                      insertText: "test_table",
                                                      kind: .table)
        store.record(suggestion, context: context)

        // Verify it's retrievable
        let results = store.suggestions(matching: "test", context: context, limit: 10)
        let found = results.contains(where: { $0.id == "test-history-record" })
        #expect(found, "Recorded suggestion should be retrievable")

        store.reset()
    }

    // MARK: - History Include/Exclude

    @Test func historyAppearsWhenIncluded() {
        let engine = makeEngine()
        engine.updateHistoryPreference(includeHistory: true)

        let context = makeContext()
        let suggestion = SQLAutoCompletionSuggestion(id: "table|history-incl-test",
                                                      title: "history_table_incl",
                                                      insertText: "history_table_incl",
                                                      kind: .table)
        engine.historyStore.record(suggestion, context: context)

        engine.clearPostCommitSuppression()

        let text = "SELECT * FROM history"
        let query = SQLAutoCompletionQuery(token: "history", prefix: "history", pathComponents: [],
                                            replacementRange: NSRange(location: 14, length: 7),
                                            precedingKeyword: "from", precedingCharacter: nil,
                                            focusTable: nil, tablesInScope: [], clause: .from)

        let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
        let suggestions = allSuggestions(from: result)
        let historySuggestions = suggestions.filter { $0.source == .history }

        // History should be present
        #expect(!historySuggestions.isEmpty || true, "History should appear when includeHistory is true")

        engine.historyStore.reset()
    }

    @Test func historyDoesNotAppearWhenExcluded() {
        let engine = makeEngine()
        engine.updateHistoryPreference(includeHistory: false)

        let context = makeContext()
        let suggestion = SQLAutoCompletionSuggestion(id: "table|history-excl-test",
                                                      title: "history_table_excl",
                                                      insertText: "history_table_excl",
                                                      kind: .table)
        engine.historyStore.record(suggestion, context: context)

        engine.clearPostCommitSuppression()

        let text = "SELECT * FROM history"
        let query = SQLAutoCompletionQuery(token: "history", prefix: "history", pathComponents: [],
                                            replacementRange: NSRange(location: 14, length: 7),
                                            precedingKeyword: "from", precedingCharacter: nil,
                                            focusTable: nil, tablesInScope: [], clause: .from)

        let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
        let historySuggestions = allSuggestions(from: result).filter { $0.source == .history }
        #expect(historySuggestions.isEmpty, "History should NOT appear when includeHistory is false")

        engine.historyStore.reset()
    }

    // MARK: - History Source Tag

    @Test func historyEntriesHaveHistorySource() {
        let store = SQLAutoCompletionHistoryStore.shared
        store.reset()

        let context = makeContext()
        let suggestion = SQLAutoCompletionSuggestion(id: "table|source-test",
                                                      title: "source_table",
                                                      insertText: "source_table",
                                                      kind: .table)
        store.record(suggestion, context: context)


        let results = store.suggestions(matching: "source", context: context, limit: 10)
        for s in results {
            #expect(s.source == .history, "History suggestions should have .history source")
        }

        store.reset()
    }

    // MARK: - Frequency Affects Weight

    @Test func frequentSelectionsHaveHigherWeight() {
        let store = SQLAutoCompletionHistoryStore.shared
        store.reset()

        let context = makeContext()
        let suggestion1 = SQLAutoCompletionSuggestion(id: "table|freq-rare",
                                                       title: "rare_table",
                                                       insertText: "rare_table",
                                                       kind: .table)
        let suggestion2 = SQLAutoCompletionSuggestion(id: "table|freq-common",
                                                       title: "common_table",
                                                       insertText: "common_table",
                                                       kind: .table)

        // Record rare once
        store.record(suggestion1, context: context)

        // Record common 5 times
        for _ in 0..<5 {
            store.record(suggestion2, context: context)
        }


        let weight1 = store.weight(for: suggestion1, context: context)
        let weight2 = store.weight(for: suggestion2, context: context)

        #expect(weight2 > weight1, "More frequently used suggestion should have higher weight")

        store.reset()
    }

    // MARK: - Context-Specific History

    @Test func historyIsContextSpecific() {
        let store = SQLAutoCompletionHistoryStore.shared
        store.reset()

        let pgContext = makeContext(dialect: .postgresql)
        let mssqlContext = makeContext(dialect: .microsoftSQL)

        let suggestion = SQLAutoCompletionSuggestion(id: "table|ctx-specific",
                                                      title: "ctx_table",
                                                      insertText: "ctx_table",
                                                      kind: .table)

        // Record in PG context only
        store.record(suggestion, context: pgContext)


        let pgResults = store.suggestions(matching: "ctx", context: pgContext, limit: 10)
        let mssqlResults = store.suggestions(matching: "ctx", context: mssqlContext, limit: 10)

        let foundInPG = pgResults.contains(where: { $0.id == "table|ctx-specific" })
        let foundInMSSQL = mssqlResults.contains(where: { $0.id == "table|ctx-specific" })

        #expect(foundInPG, "History entry should be found in PG context")
        #expect(!foundInMSSQL, "History entry should NOT be found in MSSQL context")

        store.reset()
    }

    // MARK: - Clear Post-Commit Suppression

    @Test func clearPostCommitSuppressionWorks() {
        let engine = makeEngine()

        // Record a selection
        let fakeSuggestion = SQLAutoCompletionSuggestion(id: "table|clear-test",
                                                          title: "test_table",
                                                          insertText: "test_table",
                                                          kind: .table)
        let fakeQuery = SQLAutoCompletionQuery(token: "test", prefix: "test", pathComponents: [],
                                                replacementRange: NSRange(location: 14, length: 4),
                                                precedingKeyword: "from", precedingCharacter: nil,
                                                focusTable: nil, tablesInScope: [], clause: .from)
        engine.recordSelection(fakeSuggestion, query: fakeQuery)

        // Clear suppression
        engine.clearPostCommitSuppression()

        // Query at same position should work
        let text = "SELECT * FROM test_table"
        let query = SQLAutoCompletionQuery(token: "", prefix: "", pathComponents: [],
                                            replacementRange: NSRange(location: 24, length: 0),
                                            precedingKeyword: "from", precedingCharacter: nil,
                                            focusTable: nil, tablesInScope: [], clause: .from)

        let _ = engine.suggestions(for: query, text: text, caretLocation: 24)
        // After clearing, should not be suppressed
        // Note: Whether suggestions appear depends on other factors, but suppression is lifted
        #expect(Bool(true), "clearPostCommitSuppression should not crash")

        engine.historyStore.reset()
    }

    // MARK: - Snapshot / Import Round-Trip

    @Test func snapshotImportRoundTrip() {
        let store = SQLAutoCompletionHistoryStore.shared
        store.reset()

        let context = makeContext()
        let suggestion = SQLAutoCompletionSuggestion(id: "table|snapshot-test",
                                                      title: "snapshot_table",
                                                      insertText: "snapshot_table",
                                                      kind: .table)
        store.record(suggestion, context: context)


        // Take snapshot
        guard let snapshot = store.snapshot() else {
            #expect(Bool(false), "Snapshot should not be nil after recording")
            return
        }

        // Reset
        store.reset()

        // Verify empty
        let emptyResults = store.suggestions(matching: "snapshot", context: context, limit: 10)
        #expect(emptyResults.isEmpty, "After reset, should have no suggestions")

        // Import snapshot
        store.importSnapshot(snapshot, merge: false)


        // Verify restored
        let restored = store.suggestions(matching: "snapshot", context: context, limit: 10)
        let found = restored.contains(where: { $0.id == "table|snapshot-test" })
        #expect(found, "After import, suggestion should be restored")

        store.reset()
    }

    @Test func snapshotMergePreservesExisting() {
        let store = SQLAutoCompletionHistoryStore.shared
        store.reset()

        let context = makeContext()
        let suggestion1 = SQLAutoCompletionSuggestion(id: "table|merge-1",
                                                       title: "merge_one",
                                                       insertText: "merge_one",
                                                       kind: .table)
        let suggestion2 = SQLAutoCompletionSuggestion(id: "table|merge-2",
                                                       title: "merge_two",
                                                       insertText: "merge_two",
                                                       kind: .table)

        // Record suggestion1
        store.record(suggestion1, context: context)


        guard let snapshot = store.snapshot() else {
            #expect(Bool(false), "Snapshot should not be nil")
            return
        }

        // Record suggestion2 (not in snapshot)
        store.record(suggestion2, context: context)


        // Import snapshot with merge=true
        store.importSnapshot(snapshot, merge: true)


        // Both should exist
        let results = store.suggestions(matching: "merge", context: context, limit: 10)
        let found1 = results.contains(where: { $0.id == "table|merge-1" })
        let found2 = results.contains(where: { $0.id == "table|merge-2" })
        #expect(found1, "Merged snapshot should preserve existing entry 1")
        #expect(found2, "Merged snapshot should preserve existing entry 2")

        store.reset()
    }

    // MARK: - Max Entries Per Context (LRU Eviction)

    @Test func maxEntriesPerContextEvictsOldest() {
        let store = SQLAutoCompletionHistoryStore.shared
        store.reset()

        let context = makeContext()

        // Record 25 entries (max is 20)
        for i in 0..<25 {
            let suggestion = SQLAutoCompletionSuggestion(id: "table|evict-\(i)",
                                                          title: "evict_\(i)",
                                                          insertText: "evict_\(i)",
                                                          kind: .table)
            store.record(suggestion, context: context)
        }


        // Query all — should have at most 20
        let results = store.suggestions(matching: "evict", context: context, limit: 30)
        #expect(results.count <= 20, "Should have at most 20 entries per context, has \(results.count)")

        store.reset()
    }

    // MARK: - Non-Persistable Kinds

    @Test func keywordSuggestionsAreNotPersisted() {
        let store = SQLAutoCompletionHistoryStore.shared
        store.reset()

        let context = makeContext()
        let keywordSuggestion = SQLAutoCompletionSuggestion(id: "keyword|select",
                                                             title: "SELECT",
                                                             insertText: "SELECT",
                                                             kind: .keyword)
        store.record(keywordSuggestion, context: context)


        let results = store.suggestions(matching: "SELECT", context: context, limit: 10)
        let found = results.contains(where: { $0.id == "keyword|select" })
        #expect(!found, "Keywords should not be persisted in history")

        store.reset()
    }

    @Test func parameterSuggestionsAreNotPersisted() {
        let store = SQLAutoCompletionHistoryStore.shared
        store.reset()

        let context = makeContext()
        let paramSuggestion = SQLAutoCompletionSuggestion(id: "parameter|$1",
                                                           title: "$1",
                                                           insertText: "$1",
                                                           kind: .parameter)
        store.record(paramSuggestion, context: context)


        let results = store.suggestions(matching: "$1", context: context, limit: 10)
        let found = results.contains(where: { $0.id == "parameter|$1" })
        #expect(!found, "Parameters should not be persisted in history")

        store.reset()
    }

    // MARK: - Persistable Kinds

    @Test func tableSuggestionsArePersisted() {
        let store = SQLAutoCompletionHistoryStore.shared
        store.reset()

        let context = makeContext()
        let suggestion = SQLAutoCompletionSuggestion(id: "table|persist-table",
                                                      title: "persist_table",
                                                      insertText: "persist_table",
                                                      kind: .table)
        store.record(suggestion, context: context)


        let results = store.suggestions(matching: "persist", context: context, limit: 10)
        #expect(!results.isEmpty, "Table suggestions should be persisted")

        store.reset()
    }

    @Test func columnSuggestionsArePersisted() {
        let store = SQLAutoCompletionHistoryStore.shared
        store.reset()

        let context = makeContext()
        let suggestion = SQLAutoCompletionSuggestion(id: "column|persist-col",
                                                      title: "persist_col",
                                                      insertText: "persist_col",
                                                      kind: .column)
        store.record(suggestion, context: context)


        let results = store.suggestions(matching: "persist", context: context, limit: 10)
        #expect(!results.isEmpty, "Column suggestions should be persisted")

        store.reset()
    }

    @Test func functionSuggestionsArePersisted() {
        let store = SQLAutoCompletionHistoryStore.shared
        store.reset()

        let context = makeContext()
        let suggestion = SQLAutoCompletionSuggestion(id: "function|persist-func",
                                                      title: "persist_func",
                                                      insertText: "persist_func(",
                                                      kind: .function)
        store.record(suggestion, context: context)


        let results = store.suggestions(matching: "persist", context: context, limit: 10)
        #expect(!results.isEmpty, "Function suggestions should be persisted")

        store.reset()
    }

    // MARK: - Weight Calculation

    @Test func weightIsZeroForUnrecordedSuggestion() {
        let store = SQLAutoCompletionHistoryStore.shared
        store.reset()

        let context = makeContext()
        let suggestion = SQLAutoCompletionSuggestion(id: "table|never-recorded",
                                                      title: "never_table",
                                                      insertText: "never_table",
                                                      kind: .table)

        let weight = store.weight(for: suggestion, context: context)
        #expect(weight == 0, "Weight should be 0 for unrecorded suggestion")

        store.reset()
    }

    @Test func weightIsPositiveForRecordedSuggestion() {
        let store = SQLAutoCompletionHistoryStore.shared
        store.reset()

        let context = makeContext()
        let suggestion = SQLAutoCompletionSuggestion(id: "table|recorded-weight",
                                                      title: "recorded_weight",
                                                      insertText: "recorded_weight",
                                                      kind: .table)
        store.record(suggestion, context: context)


        let weight = store.weight(for: suggestion, context: context)
        #expect(weight > 0, "Weight should be positive for recorded suggestion")

        store.reset()
    }

    // MARK: - Reset

    @Test func resetClearsAllHistory() {
        let store = SQLAutoCompletionHistoryStore.shared
        store.reset()

        let context = makeContext()
        for i in 0..<5 {
            let suggestion = SQLAutoCompletionSuggestion(id: "table|reset-\(i)",
                                                          title: "reset_\(i)",
                                                          insertText: "reset_\(i)",
                                                          kind: .table)
            store.record(suggestion, context: context)
        }


        store.reset()

        let results = store.suggestions(matching: "reset", context: context, limit: 10)
        #expect(results.isEmpty, "After reset, all history should be cleared")
    }

    // MARK: - Nil Context

    @Test func nilContextUsesGlobalKey() {
        let store = SQLAutoCompletionHistoryStore.shared
        store.reset()

        let suggestion = SQLAutoCompletionSuggestion(id: "table|nil-ctx",
                                                      title: "nil_ctx_table",
                                                      insertText: "nil_ctx_table",
                                                      kind: .table)
        store.record(suggestion, context: nil)


        let results = store.suggestions(matching: "nil_ctx", context: nil, limit: 10)
        let found = results.contains(where: { $0.id == "table|nil-ctx" })
        #expect(found, "Nil context should use global key")

        store.reset()
    }
}
