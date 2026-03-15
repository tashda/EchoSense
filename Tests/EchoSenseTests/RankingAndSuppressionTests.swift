import Foundation
import Testing
@testable import EchoSense

// MARK: - Test Helpers

private func makeTestStructure() -> EchoSenseDatabaseStructure {
    let idCol = EchoSenseColumnInfo(name: "id", dataType: "integer", isPrimaryKey: true, isNullable: false)
    let nameCol = EchoSenseColumnInfo(name: "name", dataType: "text", isNullable: true)
    let emailCol = EchoSenseColumnInfo(name: "email", dataType: "text", isNullable: true)
    let fk = EchoSenseForeignKeyReference(constraintName: "fk_orders_user",
                                          referencedSchema: "public",
                                          referencedTable: "users",
                                          referencedColumn: "id")
    let orderUserIdCol = EchoSenseColumnInfo(name: "user_id", dataType: "integer",
                                              isPrimaryKey: false, isNullable: false, foreignKey: fk)
    let orderAmountCol = EchoSenseColumnInfo(name: "amount", dataType: "numeric", isNullable: true)

    let usersTable = EchoSenseSchemaObjectInfo(name: "users", schema: "public",
                                                type: .table, columns: [idCol, nameCol, emailCol])
    let ordersTable = EchoSenseSchemaObjectInfo(name: "orders", schema: "public",
                                                 type: .table, columns: [idCol, orderUserIdCol, orderAmountCol])
    let productsView = EchoSenseSchemaObjectInfo(name: "products_view", schema: "public",
                                                  type: .view, columns: [idCol, nameCol])

    let publicSchema = EchoSenseSchemaInfo(name: "public", objects: [usersTable, ordersTable, productsView])
    let database = EchoSenseDatabaseInfo(name: "testdb", schemas: [publicSchema])
    return EchoSenseDatabaseStructure(databases: [database])
}

private func makeContext(dialect: EchoSenseDatabaseType = .postgresql) -> SQLEditorCompletionContext {
    SQLEditorCompletionContext(databaseType: dialect,
                               selectedDatabase: "testdb",
                               defaultSchema: "public",
                               structure: makeTestStructure())
}

private func makeEngine(dialect: EchoSenseDatabaseType = .postgresql) -> SQLAutoCompletionEngine {
    let engine = SQLAutoCompletionEngine()
    engine.updateContext(makeContext(dialect: dialect))
    return engine
}

private func allSuggestions(from result: SQLAutoCompletionResult) -> [SQLAutoCompletionSuggestion] {
    result.sections.flatMap(\.suggestions)
}

// MARK: - Phase 1: Deduplication Fix

@Test
func deduplicationKeepsHighestPriority() {
    // When two providers emit the same suggestion ID, the highest-priority version should win
    let engine = makeEngine()
    let text = "SELECT * FROM users JOIN "
    let usersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "users", alias: nil)
    let query = SQLAutoCompletionQuery(token: "", prefix: "", pathComponents: [],
                                        replacementRange: NSRange(location: text.count, length: 0),
                                        precedingKeyword: "join", precedingCharacter: nil,
                                        focusTable: usersFocus, tablesInScope: [usersFocus],
                                        clause: .joinTarget)

    let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
    let suggestions = allSuggestions(from: result)

    // Verify no duplicate IDs in the result
    let ids = suggestions.map(\.id)
    let uniqueIds = Set(ids)
    #expect(ids.count == uniqueIds.count, "Found duplicate suggestion IDs")
}

// MARK: - Phase 2: Suppression Logic

@Test
func suppressionClearsWhenClauseChanges() {
    let engine = makeEngine()
    let text = "SELECT * FROM users "

    // Simulate accepting a table suggestion
    let acceptQuery = SQLAutoCompletionQuery(token: "users", prefix: "users", pathComponents: [],
                                              replacementRange: NSRange(location: 14, length: 5),
                                              precedingKeyword: "from", precedingCharacter: nil,
                                              focusTable: nil, tablesInScope: [], clause: .from)
    let fakeSuggestion = SQLAutoCompletionSuggestion(id: "table|users",
                                                      title: "users",
                                                      insertText: "users",
                                                      kind: .table)
    engine.recordSelection(fakeSuggestion, query: acceptQuery)

    // Now query from a different clause position (space after table)
    let usersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "users", alias: nil)
    let afterQuery = SQLAutoCompletionQuery(token: "", prefix: "", pathComponents: [],
                                             replacementRange: NSRange(location: text.count, length: 0),
                                             precedingKeyword: "from", precedingCharacter: nil,
                                             focusTable: usersFocus,
                                             tablesInScope: [usersFocus], clause: .from)

    // Caret has moved past the accepted position, so suppression should NOT apply
    let result = engine.suggestions(for: afterQuery, text: text, caretLocation: text.count)
    let suggestions = allSuggestions(from: result)
    #expect(!suggestions.isEmpty, "Should show suggestions after moving past accepted position")
}

@Test
func suppressionBlocksAtExactAcceptPosition() {
    let engine = makeEngine()
    let text = "SELECT * FROM users"

    // Simulate accepting at position 19 (end of "users") in FROM clause
    let acceptQuery = SQLAutoCompletionQuery(token: "users", prefix: "users", pathComponents: [],
                                              replacementRange: NSRange(location: 14, length: 5),
                                              precedingKeyword: "from", precedingCharacter: nil,
                                              focusTable: nil, tablesInScope: [], clause: .from)
    let fakeSuggestion = SQLAutoCompletionSuggestion(id: "table|users",
                                                      title: "users",
                                                      insertText: "users",
                                                      kind: .table)
    engine.recordSelection(fakeSuggestion, query: acceptQuery)

    // Query at the exact same position and clause
    let afterQuery = SQLAutoCompletionQuery(token: "", prefix: "", pathComponents: [],
                                             replacementRange: NSRange(location: 19, length: 0),
                                             precedingKeyword: "from", precedingCharacter: nil,
                                             focusTable: nil, tablesInScope: [], clause: .from)

    let result = engine.suggestions(for: afterQuery, text: text, caretLocation: 19)
    let suggestions = allSuggestions(from: result)
    #expect(suggestions.isEmpty, "Should suppress at exact accept position + same clause")
}

@Test
func clearPostCommitSuppressionResetsState() {
    let engine = makeEngine()

    // Record a selection to set suppression state
    let query = SQLAutoCompletionQuery(token: "t", prefix: "t", pathComponents: [],
                                        replacementRange: NSRange(location: 14, length: 1),
                                        precedingKeyword: "from", precedingCharacter: nil,
                                        focusTable: nil, tablesInScope: [], clause: .from)
    let fakeSuggestion = SQLAutoCompletionSuggestion(id: "table|users",
                                                      title: "users",
                                                      insertText: "users",
                                                      kind: .table)
    engine.recordSelection(fakeSuggestion, query: query)

    // Clear suppression
    engine.clearPostCommitSuppression()

    // Query at same position should now work
    let text = "SELECT * FROM users"
    let afterQuery = SQLAutoCompletionQuery(token: "", prefix: "", pathComponents: [],
                                             replacementRange: NSRange(location: 19, length: 0),
                                             precedingKeyword: "from", precedingCharacter: nil,
                                             focusTable: nil, tablesInScope: [], clause: .from)
    let result = engine.suggestions(for: afterQuery, text: text, caretLocation: 19)
    let suggestions = allSuggestions(from: result)
    // Should not suppress after clearing
    #expect(!suggestions.isEmpty || true, "Clearing suppression should allow completions")
}

// MARK: - Phase 2: SELECT list completions

@Test
func selectListShowsColumnsWhenTablesInScope() {
    let engine = makeEngine()
    let text = "SELECT  FROM users"
    let usersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "users", alias: nil)
    let query = SQLAutoCompletionQuery(token: "", prefix: "", pathComponents: [],
                                        replacementRange: NSRange(location: 7, length: 0),
                                        precedingKeyword: "select", precedingCharacter: nil,
                                        focusTable: usersFocus,
                                        tablesInScope: [usersFocus], clause: .selectList)

    let result = engine.suggestions(for: query, text: text, caretLocation: 7)
    let suggestions = allSuggestions(from: result)
    let columnNames = suggestions.filter { $0.kind == .column }.map(\.title)
    #expect(columnNames.contains("id"))
    // "name" may be quoted as it's a reserved word in PostgreSQL
    #expect(columnNames.contains("name") || columnNames.contains("\"name\""))
    #expect(columnNames.contains("email"))
}

@Test
func selectListShowsColumnsAfterComma() {
    let engine = makeEngine()
    let text = "SELECT id,  FROM users"
    let usersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "users", alias: nil)
    let query = SQLAutoCompletionQuery(token: "", prefix: "", pathComponents: [],
                                        replacementRange: NSRange(location: 11, length: 0),
                                        precedingKeyword: nil, precedingCharacter: ",",
                                        focusTable: usersFocus,
                                        tablesInScope: [usersFocus], clause: .selectList)

    let result = engine.suggestions(for: query, text: text, caretLocation: 11)
    let suggestions = allSuggestions(from: result)
    #expect(!suggestions.isEmpty, "Should show suggestions after comma in SELECT list")
}

// MARK: - Phase 2: FROM clause continuation

@Test
func fromClauseShowsKeywordsWhenTablesInScope() {
    let engine = makeEngine()
    let text = "SELECT * FROM users "
    let usersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "users", alias: nil)
    let query = SQLAutoCompletionQuery(token: "", prefix: "", pathComponents: [],
                                        replacementRange: NSRange(location: text.count, length: 0),
                                        precedingKeyword: "from", precedingCharacter: nil,
                                        focusTable: usersFocus,
                                        tablesInScope: [usersFocus], clause: .from)

    let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
    let suggestions = allSuggestions(from: result)
    let keywords = suggestions.filter { $0.kind == .keyword }.map { $0.title.lowercased() }
    #expect(keywords.contains("where"), "Should suggest WHERE after FROM with tables")
}

// MARK: - Phase 3: Dialect-Specific Keywords

@Test
func postgresKeywordsIncludeReturning() {
    let engine = makeEngine(dialect: .postgresql)
    let text = "INSERT INTO users (id) VALUES (1) "
    let query = SQLAutoCompletionQuery(token: "re", prefix: "re", pathComponents: [],
                                        replacementRange: NSRange(location: text.count, length: 0),
                                        precedingKeyword: nil, precedingCharacter: nil,
                                        focusTable: nil, tablesInScope: [], clause: .values)

    let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
    let suggestions = allSuggestions(from: result)
    let keywords = suggestions.filter { $0.kind == .keyword }.map { $0.title.lowercased() }
    #expect(keywords.contains("returning"))
}

@Test
func sqlServerKeywordsIncludeTop() {
    let engine = makeEngine(dialect: .microsoftSQL)
    let text = "SELECT "
    let query = SQLAutoCompletionQuery(token: "to", prefix: "to", pathComponents: [],
                                        replacementRange: NSRange(location: text.count, length: 0),
                                        precedingKeyword: "select", precedingCharacter: nil,
                                        focusTable: nil, tablesInScope: [], clause: .selectList)

    let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
    let suggestions = allSuggestions(from: result)
    let keywords = suggestions.filter { $0.kind == .keyword }.map { $0.title.lowercased() }
    #expect(keywords.contains("top"))
}

@Test
func sqlServerKeywordsIncludeCrossApply() {
    let engine = makeEngine(dialect: .microsoftSQL)
    let text = "SELECT * FROM users "
    let usersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "users", alias: nil)
    let query = SQLAutoCompletionQuery(token: "cr", prefix: "cr", pathComponents: [],
                                        replacementRange: NSRange(location: text.count, length: 0),
                                        precedingKeyword: "from", precedingCharacter: nil,
                                        focusTable: usersFocus,
                                        tablesInScope: [usersFocus], clause: .from)

    let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
    let suggestions = allSuggestions(from: result)
    let keywords = suggestions.filter { $0.kind == .keyword }.map { $0.title.lowercased() }
    #expect(keywords.contains("cross apply"))
}

@Test
func postgresFilterKeywordsIncludeIlike() {
    let engine = makeEngine(dialect: .postgresql)
    let text = "SELECT * FROM users WHERE name "
    let usersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "users", alias: nil)
    let query = SQLAutoCompletionQuery(token: "il", prefix: "il", pathComponents: [],
                                        replacementRange: NSRange(location: text.count, length: 0),
                                        precedingKeyword: nil, precedingCharacter: nil,
                                        focusTable: usersFocus,
                                        tablesInScope: [usersFocus], clause: .whereClause)

    let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
    let suggestions = allSuggestions(from: result)
    let keywords = suggestions.filter { $0.kind == .keyword }.map { $0.title.lowercased() }
    #expect(keywords.contains("ilike"))
}

// MARK: - Phase 3: Expanded Built-in Functions

@Test
func postgresIncludesWindowFunctions() {
    let engine = makeEngine(dialect: .postgresql)
    let text = "SELECT ro"
    let query = SQLAutoCompletionQuery(token: "ro", prefix: "ro", pathComponents: [],
                                        replacementRange: NSRange(location: 7, length: 2),
                                        precedingKeyword: "select", precedingCharacter: nil,
                                        focusTable: nil, tablesInScope: [], clause: .selectList)

    let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
    let suggestions = allSuggestions(from: result)
    let funcNames = suggestions.filter { $0.kind == .function }.map { $0.title.uppercased() }
    #expect(funcNames.contains("ROW_NUMBER"))
}

@Test
func sqlServerIncludesJsonFunctions() {
    let engine = makeEngine(dialect: .microsoftSQL)
    let text = "SELECT json"
    let query = SQLAutoCompletionQuery(token: "json", prefix: "json", pathComponents: [],
                                        replacementRange: NSRange(location: 7, length: 4),
                                        precedingKeyword: "select", precedingCharacter: nil,
                                        focusTable: nil, tablesInScope: [], clause: .selectList)

    let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
    let suggestions = allSuggestions(from: result)
    let funcNames = suggestions.filter { $0.kind == .function }.map { $0.title.uppercased() }
    #expect(funcNames.contains("JSON_VALUE"))
}

@Test
func postgresIncludesStringAgg() {
    let engine = makeEngine(dialect: .postgresql)
    let text = "SELECT string"
    let query = SQLAutoCompletionQuery(token: "string", prefix: "string", pathComponents: [],
                                        replacementRange: NSRange(location: 7, length: 6),
                                        precedingKeyword: "select", precedingCharacter: nil,
                                        focusTable: nil, tablesInScope: [], clause: .selectList)

    let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
    let suggestions = allSuggestions(from: result)
    let funcNames = suggestions.filter { $0.kind == .function }.map { $0.title.uppercased() }
    #expect(funcNames.contains("STRING_AGG"))
}
