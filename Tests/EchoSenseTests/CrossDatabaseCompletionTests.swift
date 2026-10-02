import Foundation
import Testing
@testable import EchoSense

// MARK: - Test Fixtures

/// Two-database structure: db1 has table1 in dbo; db2 has fable2 in dbo.
private func makeCrossDatabaseStructure() -> EchoSenseDatabaseStructure {
    let idCol = EchoSenseColumnInfo(name: "id", dataType: "int", isPrimaryKey: true, isNullable: false)

    let table1 = EchoSenseSchemaObjectInfo(name: "table1", schema: "dbo", type: .table, columns: [idCol])
    let fable2 = EchoSenseSchemaObjectInfo(name: "fable2", schema: "dbo", type: .table, columns: [idCol])

    let db1Schema = EchoSenseSchemaInfo(name: "dbo", objects: [table1])
    let db2Schema = EchoSenseSchemaInfo(name: "dbo", objects: [fable2])

    let db1 = EchoSenseDatabaseInfo(name: "db1", schemas: [db1Schema])
    let db2 = EchoSenseDatabaseInfo(name: "db2", schemas: [db2Schema])

    return EchoSenseDatabaseStructure(databases: [db1, db2])
}

private func makeCrossDBEngine(selectedDatabase: String = "db1") -> SQLAutoCompletionEngine {
    let context = SQLEditorCompletionContext(
        databaseType: .microsoftSQL,
        selectedDatabase: selectedDatabase,
        defaultSchema: "dbo",
        structure: makeCrossDatabaseStructure()
    )
    let engine = SQLAutoCompletionEngine()
    engine.updateContext(context)
    return engine
}

private func allSuggestions(from result: SQLAutoCompletionResult) -> [SQLAutoCompletionSuggestion] {
    result.sections.flatMap(\.suggestions)
}

private func fromQuery(text: String, token: String = "") -> (text: String, query: SQLAutoCompletionQuery) {
    let location = text.count
    let q = SQLAutoCompletionQuery(
        token: token,
        prefix: token,
        pathComponents: [],
        replacementRange: NSRange(location: location, length: 0),
        precedingKeyword: "from",
        precedingCharacter: token.isEmpty ? nil : token.last,
        focusTable: nil,
        tablesInScope: [],
        clause: .from
    )
    return (text, q)
}

// MARK: - Issue Fix: selectedDatabase uses tab.activeDatabaseName

// These tests validate the engine side of the fix — that when a different
// selectedDatabase is provided, the right catalog is used.

@Suite("Cross-database completion")
struct CrossDatabaseCompletionTests {

    // MARK: Current DB — schema and table suggestions

    @Test func suggestsSchemaFromCurrentDatabase() {
        let engine = makeCrossDBEngine(selectedDatabase: "db1")
        let text = "SELECT * FROM "
        let query = SQLAutoCompletionQuery(
            token: "", prefix: "", pathComponents: [],
            replacementRange: NSRange(location: text.count, length: 0),
            precedingKeyword: "from", precedingCharacter: nil,
            focusTable: nil, tablesInScope: [], clause: .from
        )
        let suggestions = allSuggestions(from: engine.suggestions(for: query, text: text, caretLocation: text.count))
        let schemaNames = suggestions.filter { $0.kind == .schema }.map(\.title)
        // Should suggest "dbo" schema from db1 and "db1"/"db2" as database suggestions
        #expect(schemaNames.contains("dbo"))
    }

    @Test func suggestsTablesFromCurrentDatabase() {
        let engine = makeCrossDBEngine(selectedDatabase: "db1")
        let text = "SELECT * FROM "
        let query = SQLAutoCompletionQuery(
            token: "", prefix: "", pathComponents: [],
            replacementRange: NSRange(location: text.count, length: 0),
            precedingKeyword: "from", precedingCharacter: nil,
            focusTable: nil, tablesInScope: [], clause: .from
        )
        let suggestions = allSuggestions(from: engine.suggestions(for: query, text: text, caretLocation: text.count))
        let tableNames = suggestions.filter { $0.kind == .table }.map(\.title)
        #expect(tableNames.contains("table1"))
        #expect(!tableNames.contains("fable2"), "fable2 is in db2, not db1")
    }

    // MARK: Database name suggestions

    @Test func suggestsDatabaseNamesInFromClause() {
        let engine = makeCrossDBEngine(selectedDatabase: "db1")
        // Database suggestions require at least one typed character
        let text = "SELECT * FROM d"
        let query = SQLAutoCompletionQuery(
            token: "d", prefix: "d", pathComponents: [],
            replacementRange: NSRange(location: text.count - 1, length: 1),
            precedingKeyword: "from", precedingCharacter: nil,
            focusTable: nil, tablesInScope: [], clause: .from
        )
        let suggestions = allSuggestions(from: engine.suggestions(for: query, text: text, caretLocation: text.count))
        let titles = suggestions.map(\.title)
        #expect(titles.contains("db1"))
        #expect(titles.contains("db2"))
    }

    @Test func databaseSuggestionsInsertTrailingDot() {
        let engine = makeCrossDBEngine(selectedDatabase: "db1")
        let text = "SELECT * FROM d"
        let query = SQLAutoCompletionQuery(
            token: "d", prefix: "d", pathComponents: [],
            replacementRange: NSRange(location: text.count - 1, length: 1),
            precedingKeyword: "from", precedingCharacter: nil,
            focusTable: nil, tablesInScope: [], clause: .from
        )
        let suggestions = allSuggestions(from: engine.suggestions(for: query, text: text, caretLocation: text.count))
        let db2Suggestion = suggestions.first { $0.title == "db2" }
        #expect(db2Suggestion != nil)
        #expect(db2Suggestion?.insertText.hasSuffix(".") == true)
    }

    // MARK: Cross-database schema suggestions (db2.)

    @Test func suggesSchemasFromOtherDatabaseAfterDot() {
        let engine = makeCrossDBEngine(selectedDatabase: "db1")
        // User typed "db2." — token is "db2.", preceding = ["db2"], prefix = ""
        let text = "SELECT * FROM db2."
        let query = SQLAutoCompletionQuery(
            token: "db2.", prefix: "", pathComponents: ["db2"],
            replacementRange: NSRange(location: text.count, length: 0),
            precedingKeyword: "from", precedingCharacter: ".",
            focusTable: nil, tablesInScope: [], clause: .from
        )
        let suggestions = allSuggestions(from: engine.suggestions(for: query, text: text, caretLocation: text.count))
        let schemaNames = suggestions.filter { $0.kind == .schema }.map(\.title)
        // Should suggest "dbo" from db2's catalog
        #expect(schemaNames.contains("dbo"))
    }

    @Test func schemaInsertTextIncludesDatabasePrefix() {
        let engine = makeCrossDBEngine(selectedDatabase: "db1")
        let text = "SELECT * FROM db2."
        let query = SQLAutoCompletionQuery(
            token: "db2.", prefix: "", pathComponents: ["db2"],
            replacementRange: NSRange(location: text.count, length: 0),
            precedingKeyword: "from", precedingCharacter: ".",
            focusTable: nil, tablesInScope: [], clause: .from
        )
        let suggestions = allSuggestions(from: engine.suggestions(for: query, text: text, caretLocation: text.count))
        let dboSuggestion = suggestions.first { $0.title == "dbo" && $0.kind == .schema }
        #expect(dboSuggestion != nil)
        // insertText should be "db2.dbo."
        #expect(dboSuggestion?.insertText == "db2.dbo.")
    }

    @Test func doesNotSuggestTablesWhenOnlyDatabaseIsTyped() {
        let engine = makeCrossDBEngine(selectedDatabase: "db1")
        let text = "SELECT * FROM db2."
        let query = SQLAutoCompletionQuery(
            token: "db2.", prefix: "", pathComponents: ["db2"],
            replacementRange: NSRange(location: text.count, length: 0),
            precedingKeyword: "from", precedingCharacter: ".",
            focusTable: nil, tablesInScope: [], clause: .from
        )
        let suggestions = allSuggestions(from: engine.suggestions(for: query, text: text, caretLocation: text.count))
        let tableNames = suggestions.filter { $0.kind == .table }.map(\.title)
        // Tables should NOT appear at db. level — that's schema level
        #expect(!tableNames.contains("fable2"))
    }

    // MARK: Cross-database table suggestions (db2.dbo.)

    @Test func suggestsTablesFromOtherDatabaseAfterSchemaDot() {
        let engine = makeCrossDBEngine(selectedDatabase: "db1")
        // User typed "db2.dbo." — token is "db2.dbo.", preceding = ["db2", "dbo"], prefix = ""
        let text = "SELECT * FROM db2.dbo."
        let query = SQLAutoCompletionQuery(
            token: "db2.dbo.", prefix: "", pathComponents: ["db2", "dbo"],
            replacementRange: NSRange(location: text.count, length: 0),
            precedingKeyword: "from", precedingCharacter: ".",
            focusTable: nil, tablesInScope: [], clause: .from
        )
        let suggestions = allSuggestions(from: engine.suggestions(for: query, text: text, caretLocation: text.count))
        let tableNames = suggestions.filter { $0.kind == .table }.map(\.title)
        #expect(tableNames.contains("fable2"), "fable2 should appear from db2.dbo")
        #expect(!tableNames.contains("table1"), "table1 is in db1, not db2")
    }

    @Test func tableInsertTextIncludesDatabaseAndSchemaPrefix() {
        let engine = makeCrossDBEngine(selectedDatabase: "db1")
        let text = "SELECT * FROM db2.dbo."
        let query = SQLAutoCompletionQuery(
            token: "db2.dbo.", prefix: "", pathComponents: ["db2", "dbo"],
            replacementRange: NSRange(location: text.count, length: 0),
            precedingKeyword: "from", precedingCharacter: ".",
            focusTable: nil, tablesInScope: [], clause: .from
        )
        let suggestions = allSuggestions(from: engine.suggestions(for: query, text: text, caretLocation: text.count))
        let fable2Suggestion = suggestions.first { $0.title == "fable2" }
        #expect(fable2Suggestion != nil)
        // The replacement range covers 0 characters (pure append after the typed path),
        // so insertText is just the final component — the engine strips the already-typed
        // "db2.dbo." prefix via adjustedInsertText.
        #expect(fable2Suggestion?.insertText == "fable2")
    }

    // MARK: No cross-server leakage

    @Test func doesNotSuggestTablesFromWrongDatabase() {
        // When connected to db2, table1 (in db1) should not appear for db2.dbo.
        let engine = makeCrossDBEngine(selectedDatabase: "db2")
        let text = "SELECT * FROM db2.dbo."
        let query = SQLAutoCompletionQuery(
            token: "db2.dbo.", prefix: "", pathComponents: ["db2", "dbo"],
            replacementRange: NSRange(location: text.count, length: 0),
            precedingKeyword: "from", precedingCharacter: ".",
            focusTable: nil, tablesInScope: [], clause: .from
        )
        let suggestions = allSuggestions(from: engine.suggestions(for: query, text: text, caretLocation: text.count))
        let tableNames = suggestions.filter { $0.kind == .table }.map(\.title)
        #expect(!tableNames.contains("table1"), "table1 is in db1, not db2")
    }

    @Test func databaseSuggestionsOnlyAppearsAtFirstPathComponent() {
        let engine = makeCrossDBEngine(selectedDatabase: "db1")
        // At db2.dbo. level, no database-name suggestions should appear
        let text = "SELECT * FROM db2.dbo."
        let query = SQLAutoCompletionQuery(
            token: "db2.dbo.", prefix: "", pathComponents: ["db2", "dbo"],
            replacementRange: NSRange(location: text.count, length: 0),
            precedingKeyword: "from", precedingCharacter: ".",
            focusTable: nil, tablesInScope: [], clause: .from
        )
        let suggestions = allSuggestions(from: engine.suggestions(for: query, text: text, caretLocation: text.count))
        // db1 and db2 should NOT appear as suggestions at this level
        let dbSuggestion = suggestions.first { $0.id.hasPrefix("database|") }
        #expect(dbSuggestion == nil, "Database names should not appear after db.schema.")
    }

    // MARK: - Database suggestion kind

    @Test func databaseSuggestionsUseDatabaseKind() {
        let engine = makeCrossDBEngine(selectedDatabase: "db1")
        let text = "SELECT * FROM d"
        let query = SQLAutoCompletionQuery(
            token: "d", prefix: "d", pathComponents: [],
            replacementRange: NSRange(location: text.count - 1, length: 1),
            precedingKeyword: "from", precedingCharacter: nil,
            focusTable: nil, tablesInScope: [], clause: .from
        )
        let suggestions = allSuggestions(from: engine.suggestions(for: query, text: text, caretLocation: text.count))
        let db2Suggestion = suggestions.first { $0.title == "db2" }
        #expect(db2Suggestion?.kind == .database, "Database suggestions should use .database kind, not .schema")
    }

    // MARK: - 3-part name parsing

    @Test func parserExtracts3PartTableReference() {
        let engine = makeCrossDBEngine(selectedDatabase: "db1")
        // The engine re-parses text — tablesInScope come from the parser.
        let text = "SELECT * FROM db2.dbo.fable2 "
        let query = SQLAutoCompletionQuery(
            token: "", prefix: "", pathComponents: [],
            replacementRange: NSRange(location: text.count, length: 0),
            precedingKeyword: nil, precedingCharacter: " ",
            focusTable: nil,
            tablesInScope: [
                SQLAutoCompletionTableFocus(database: "db2", schema: "dbo", name: "fable2", alias: nil)
            ],
            clause: .selectList
        )
        let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
        // The metadata should contain db2 as the database for fable2
        let tableRef = result.metadata.tablesInScope.first { $0.name == "fable2" }
        #expect(tableRef != nil, "fable2 should be in tablesInScope")
        #expect(tableRef?.database == "db2", "database should be 'db2'")
        #expect(tableRef?.schema == "dbo", "schema should be 'dbo'")
    }

    // MARK: - Cross-database column resolution

    @Test func suggestsColumnsFromCrossDatabaseTable() {
        let engine = makeCrossDBEngine(selectedDatabase: "db1")
        // User wrote: SELECT db2.dbo.fable2. (wanting columns from fable2 in db2)
        // The engine will parse the FROM clause and find fable2 in db2.
        // We need a FROM clause so fable2 is in tablesInScope.
        let text = "SELECT db2.dbo.fable2. FROM db2.dbo.fable2"
        let caretLocation = "SELECT db2.dbo.fable2.".count
        let query = SQLAutoCompletionQuery(
            token: "db2.dbo.fable2.", prefix: "", pathComponents: ["db2", "dbo", "fable2"],
            replacementRange: NSRange(location: caretLocation, length: 0),
            precedingKeyword: nil, precedingCharacter: ".",
            focusTable: nil, tablesInScope: [], clause: .selectList
        )
        let suggestions = allSuggestions(from: engine.suggestions(for: query, text: text, caretLocation: caretLocation))
        let columnNames = suggestions.filter { $0.kind == .column }.map(\.title)
        #expect(columnNames.contains("id"), "Should suggest columns from fable2 in db2")
    }

    // MARK: - Join target in cross-database context

    @Test func joinTargetShowsSchemasFromOtherDatabase() {
        let engine = makeCrossDBEngine(selectedDatabase: "db1")
        let text = "SELECT * FROM table1 INNER JOIN db2."
        let query = SQLAutoCompletionQuery(
            token: "db2.", prefix: "", pathComponents: ["db2"],
            replacementRange: NSRange(location: text.count, length: 0),
            precedingKeyword: "join", precedingCharacter: ".",
            focusTable: nil,
            tablesInScope: [
                SQLAutoCompletionTableFocus(schema: "dbo", name: "table1", alias: nil)
            ],
            clause: .joinTarget
        )
        let suggestions = allSuggestions(from: engine.suggestions(for: query, text: text, caretLocation: text.count))
        let schemaNames = suggestions.filter { $0.kind == .schema }.map(\.title)
        #expect(schemaNames.contains("dbo"), "Should suggest schemas from db2 after INNER JOIN db2.")
    }
}
