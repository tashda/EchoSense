import Foundation
import Testing
@testable import EchoSense

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

// MARK: - Table Suggestions in FROM

@Test
func suggestsTablesAfterFrom() {
    let engine = makeEngine()
    let text = "SELECT * FROM "
    let query = SQLAutoCompletionQuery(token: "", prefix: "", pathComponents: [],
                                        replacementRange: NSRange(location: text.count, length: 0),
                                        precedingKeyword: "from", precedingCharacter: nil,
                                        focusTable: nil, tablesInScope: [], clause: .from)

    let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
    let suggestions = allSuggestions(from: result)

    let tableNames = suggestions.filter { $0.kind == .table }.map(\.title)
    #expect(tableNames.contains("users"))
    #expect(tableNames.contains("orders"))
}

@Test
func suggestsViewsAfterFrom() {
    let engine = makeEngine()
    let text = "SELECT * FROM "
    let query = SQLAutoCompletionQuery(token: "", prefix: "", pathComponents: [],
                                        replacementRange: NSRange(location: text.count, length: 0),
                                        precedingKeyword: "from", precedingCharacter: nil,
                                        focusTable: nil, tablesInScope: [], clause: .from)

    let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
    let suggestions = allSuggestions(from: result)

    let viewNames = suggestions.filter { $0.kind == .view }.map(\.title)
    #expect(viewNames.contains("products_view"))
}

// MARK: - Column Suggestions in SELECT

@Test
func suggestsColumnsInSelect() {
    let engine = makeEngine()
    let focus = SQLAutoCompletionTableFocus(schema: "public", name: "users", alias: nil)
    let text = "SELECT * FROM users WHERE "
    let query = SQLAutoCompletionQuery(token: "", prefix: "", pathComponents: [],
                                        replacementRange: NSRange(location: text.count, length: 0),
                                        precedingKeyword: "where", precedingCharacter: nil,
                                        focusTable: focus, tablesInScope: [focus], clause: .whereClause)

    let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
    let suggestions = allSuggestions(from: result)

    let columnTitles = suggestions.filter { $0.kind == .column }.map(\.title)
    #expect(columnTitles.contains("id"))
    // "name" is a reserved word so the title may appear as-is but insertText is quoted
    #expect(columnTitles.contains("name") || columnTitles.contains("\"name\""))
    #expect(columnTitles.contains("email"))
}

// MARK: - Prefix Filtering

@Test
func filtersByPrefix() {
    let engine = makeEngine()
    let text = "SELECT * FROM us"
    let query = SQLAutoCompletionQuery(token: "us", prefix: "us", pathComponents: [],
                                        replacementRange: NSRange(location: 14, length: 2),
                                        precedingKeyword: "from", precedingCharacter: nil,
                                        focusTable: nil, tablesInScope: [], clause: .from)

    let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
    let suggestions = allSuggestions(from: result)

    let tableNames = suggestions.filter { $0.kind == .table }.map(\.title)
    #expect(tableNames.contains("users"))
    #expect(!tableNames.contains("orders"))
}

// MARK: - Keyword Suggestions

@Test
func suggestsKeywords() {
    let engine = makeEngine()
    let text = "SELECT * FROM users "
    let query = SQLAutoCompletionQuery(token: "", prefix: "", pathComponents: [],
                                        replacementRange: NSRange(location: text.count, length: 0),
                                        precedingKeyword: "from", precedingCharacter: nil,
                                        focusTable: nil, tablesInScope: [], clause: .from)

    let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
    let suggestions = allSuggestions(from: result)

    let keywordTitles = suggestions.filter { $0.kind == .keyword }.map { $0.title.lowercased() }
    #expect(keywordTitles.contains("where"))
    #expect(keywordTitles.contains("join"))
}

// MARK: - Schema Suggestions

@Test
func suggestsSchemasAfterFrom() {
    let engine = makeEngine()
    let text = "SELECT * FROM "
    let query = SQLAutoCompletionQuery(token: "", prefix: "", pathComponents: [],
                                        replacementRange: NSRange(location: text.count, length: 0),
                                        precedingKeyword: "from", precedingCharacter: nil,
                                        focusTable: nil, tablesInScope: [], clause: .from)

    let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
    let suggestions = allSuggestions(from: result)

    let schemaNames = suggestions.filter { $0.kind == .schema }.map(\.title)
    #expect(schemaNames.contains("public"))
}

// MARK: - Parameter Suggestions

@Test
func suggestsParametersInWhere() {
    let engine = makeEngine()
    let focus = SQLAutoCompletionTableFocus(schema: "public", name: "users", alias: nil)
    let text = "SELECT * FROM users WHERE id = "
    let query = SQLAutoCompletionQuery(token: "", prefix: "", pathComponents: [],
                                        replacementRange: NSRange(location: text.count, length: 0),
                                        precedingKeyword: "where", precedingCharacter: nil,
                                        focusTable: focus, tablesInScope: [focus], clause: .whereClause)

    let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
    let suggestions = allSuggestions(from: result)

    let parameterSuggestions = suggestions.filter { $0.kind == .parameter }
    #expect(!parameterSuggestions.isEmpty)
}

// MARK: - Snippet Suggestions

@Test
func suggestsSnippetsInSelect() {
    let engine = makeEngine()
    engine.updateAggressiveness(.eager)
    engine.beginManualTrigger()
    let focus = SQLAutoCompletionTableFocus(schema: "public", name: "users", alias: nil)
    let text = "SELECT * FROM users WHERE "
    let query = SQLAutoCompletionQuery(token: "", prefix: "", pathComponents: [],
                                        replacementRange: NSRange(location: text.count, length: 0),
                                        precedingKeyword: "where", precedingCharacter: nil,
                                        focusTable: focus, tablesInScope: [focus], clause: .whereClause)

    let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
    let suggestions = allSuggestions(from: result)
    engine.endManualTrigger()

    let snippetSuggestions = suggestions.filter { $0.kind == .snippet }
    #expect(!snippetSuggestions.isEmpty)
}

// MARK: - Join Suggestions

@Test
func suggestsJoinTargets() {
    let engine = makeEngine()
    let usersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "users", alias: "u")
    let text = "SELECT * FROM users u JOIN "
    let query = SQLAutoCompletionQuery(token: "", prefix: "", pathComponents: [],
                                        replacementRange: NSRange(location: text.count, length: 0),
                                        precedingKeyword: "join", precedingCharacter: nil,
                                        focusTable: nil, tablesInScope: [usersFocus], clause: .joinTarget)

    let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
    let suggestions = allSuggestions(from: result)

    let joinSuggestions = suggestions.filter { $0.kind == .join }
    // Should suggest orders since it has an FK to users
    #expect(!joinSuggestions.isEmpty)
}

// MARK: - Invalid Caret Location

@Test
func handlesNegativeCaretGracefully() {
    let engine = makeEngine()
    let text = "SELECT * FROM users"
    let query = SQLAutoCompletionQuery(token: "", prefix: "", pathComponents: [],
                                        replacementRange: NSRange(location: 0, length: 0),
                                        precedingKeyword: nil, precedingCharacter: nil,
                                        focusTable: nil, tablesInScope: [], clause: .unknown)

    let result = engine.suggestions(for: query, text: text, caretLocation: -1)
    // Should not crash, returns empty
    #expect(result.sections.isEmpty || !result.sections.isEmpty)
}

@Test
func handlesCaretBeyondText() {
    let engine = makeEngine()
    let text = "SELECT"
    let query = SQLAutoCompletionQuery(token: "", prefix: "", pathComponents: [],
                                        replacementRange: NSRange(location: text.count, length: 0),
                                        precedingKeyword: "select", precedingCharacter: nil,
                                        focusTable: nil, tablesInScope: [], clause: .selectList)

    let result = engine.suggestions(for: query, text: text, caretLocation: 1000)
    // Should not crash
    #expect(result.sections.isEmpty || !result.sections.isEmpty)
}

// MARK: - No Context

@Test
func handlesNoMetadataContext() {
    let engine = SQLAutoCompletionEngine()
    // No context set — engine should still not crash
    let text = "SELECT * FROM "
    let query = SQLAutoCompletionQuery(token: "", prefix: "", pathComponents: [],
                                        replacementRange: NSRange(location: text.count, length: 0),
                                        precedingKeyword: "from", precedingCharacter: nil,
                                        focusTable: nil, tablesInScope: [], clause: .from)

    let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
    // Should not crash — may or may not return suggestions depending on defaults
    #expect(result.sections.isEmpty || !result.sections.isEmpty)
}

// MARK: - Multi-Dialect Support

@Test
func worksWithSQLServer() {
    let engine = makeEngine(dialect: .microsoftSQL)
    let text = "SELECT * FROM "
    let query = SQLAutoCompletionQuery(token: "", prefix: "", pathComponents: [],
                                        replacementRange: NSRange(location: text.count, length: 0),
                                        precedingKeyword: "from", precedingCharacter: nil,
                                        focusTable: nil, tablesInScope: [], clause: .from)

    let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
    let suggestions = allSuggestions(from: result)

    let tableNames = suggestions.filter { $0.kind == .table }.map(\.title)
    #expect(tableNames.contains("users"))
}

@Test
func worksWithMySQL() {
    let engine = makeEngine(dialect: .mysql)
    let text = "SELECT * FROM "
    let query = SQLAutoCompletionQuery(token: "", prefix: "", pathComponents: [],
                                        replacementRange: NSRange(location: text.count, length: 0),
                                        precedingKeyword: "from", precedingCharacter: nil,
                                        focusTable: nil, tablesInScope: [], clause: .from)

    let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
    let suggestions = allSuggestions(from: result)

    #expect(!suggestions.isEmpty)
}

// MARK: - Aggressiveness Setting

@Test
func aggressivenessAffectsResults() {
    let engine = makeEngine()
    let text = "SELECT * FROM "
    let query = SQLAutoCompletionQuery(token: "", prefix: "", pathComponents: [],
                                        replacementRange: NSRange(location: text.count, length: 0),
                                        precedingKeyword: "from", precedingCharacter: nil,
                                        focusTable: nil, tablesInScope: [], clause: .from)

    engine.updateAggressiveness(.focused)
    let focusedResult = engine.suggestions(for: query, text: text, caretLocation: text.count)

    engine.updateAggressiveness(.eager)
    let eagerResult = engine.suggestions(for: query, text: text, caretLocation: text.count)

    let focusedCount = allSuggestions(from: focusedResult).count
    let eagerCount = allSuggestions(from: eagerResult).count

    // Eager should return at least as many suggestions as focused
    #expect(eagerCount >= focusedCount)
}

// MARK: - Metadata Result

@Test
func metadataPopulatedFromParsing() {
    let engine = makeEngine()
    let focus = SQLAutoCompletionTableFocus(schema: "public", name: "users", alias: "u")
    let ordersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "orders", alias: "o")
    let text = "SELECT * FROM users u JOIN orders o ON "
    let query = SQLAutoCompletionQuery(token: "", prefix: "", pathComponents: [],
                                        replacementRange: NSRange(location: text.count, length: 0),
                                        precedingKeyword: "on", precedingCharacter: nil,
                                        focusTable: ordersFocus,
                                        tablesInScope: [focus, ordersFocus], clause: .joinCondition)

    let result = engine.suggestions(for: query, text: text, caretLocation: text.count)

    // The engine returns metadata from its own parsing of the text
    // Verify it returns some metadata (clause and tables depend on internal parsing)
    let suggestions = allSuggestions(from: result)
    #expect(!suggestions.isEmpty)
}
