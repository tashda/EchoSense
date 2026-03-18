import Foundation
import Testing
@testable import EchoSense

@Suite("Aggressiveness and Filtering")
struct AggressivenessAndFilteringTests {

    // MARK: - Helpers

    private func makeStructure() -> EchoSenseDatabaseStructure {
        let idCol = EchoSenseColumnInfo(name: "id", dataType: "integer", isPrimaryKey: true, isNullable: false)
        let nameCol = EchoSenseColumnInfo(name: "name", dataType: "text", isNullable: true)
        let emailCol = EchoSenseColumnInfo(name: "email", dataType: "text", isNullable: true)
        let createdAtCol = EchoSenseColumnInfo(name: "created_at", dataType: "timestamp", isNullable: true)

        let fk = EchoSenseForeignKeyReference(constraintName: "fk_orders_user",
                                               referencedSchema: "public",
                                               referencedTable: "users",
                                               referencedColumn: "id")
        let userIdCol = EchoSenseColumnInfo(name: "user_id", dataType: "integer",
                                             isPrimaryKey: false, isNullable: false, foreignKey: fk)
        let amountCol = EchoSenseColumnInfo(name: "amount", dataType: "numeric", isNullable: true)
        let statusCol = EchoSenseColumnInfo(name: "status", dataType: "text", isNullable: true)

        let usersTable = EchoSenseSchemaObjectInfo(name: "users", schema: "public",
                                                    type: .table, columns: [idCol, nameCol, emailCol, createdAtCol])
        let ordersTable = EchoSenseSchemaObjectInfo(name: "orders", schema: "public",
                                                     type: .table, columns: [idCol, userIdCol, amountCol, statusCol])
        let productsView = EchoSenseSchemaObjectInfo(name: "products_view", schema: "public",
                                                      type: .view, columns: [idCol, nameCol])

        // System schemas
        let pgTable = EchoSenseSchemaObjectInfo(name: "pg_class", schema: "pg_catalog",
                                                 type: .table, columns: [idCol, nameCol])
        let pgCatalog = EchoSenseSchemaInfo(name: "pg_catalog", objects: [pgTable])

        let sysTable = EchoSenseSchemaObjectInfo(name: "sysobjects", schema: "sys",
                                                  type: .table, columns: [idCol, nameCol])
        let sysSchema = EchoSenseSchemaInfo(name: "sys", objects: [sysTable])

        let infoTable = EchoSenseSchemaObjectInfo(name: "tables", schema: "information_schema",
                                                   type: .table, columns: [idCol, nameCol])
        let infoSchema = EchoSenseSchemaInfo(name: "information_schema", objects: [infoTable])

        let publicSchema = EchoSenseSchemaInfo(name: "public",
                                                objects: [usersTable, ordersTable, productsView])
        let database = EchoSenseDatabaseInfo(name: "testdb",
                                              schemas: [publicSchema, pgCatalog, sysSchema, infoSchema])
        return EchoSenseDatabaseStructure(databases: [database])
    }

    private func makeEngine() -> SQLAutoCompletionEngine {
        let engine = SQLAutoCompletionEngine()
        let context = SQLEditorCompletionContext(databaseType: .postgresql,
                                                  selectedDatabase: "testdb",
                                                  defaultSchema: "public",
                                                  structure: makeStructure())
        engine.updateContext(context)
        engine.updateHistoryPreference(includeHistory: false)
        return engine
    }

    private func allSuggestions(from result: SQLAutoCompletionResult) -> [SQLAutoCompletionSuggestion] {
        result.sections.flatMap(\.suggestions)
    }

    // MARK: - Aggressiveness Levels in SELECT

    @Test func selectClauseFocusedShowsPrimaryOnly() {
        let engine = makeEngine()
        engine.updateAggressiveness(.focused)
        let usersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "users", alias: nil)
        let text = "SELECT  FROM users"
        let query = SQLAutoCompletionQuery(token: "", prefix: "", pathComponents: [],
                                            replacementRange: NSRange(location: 7, length: 0),
                                            precedingKeyword: "select", precedingCharacter: nil,
                                            focusTable: usersFocus,
                                            tablesInScope: [usersFocus], clause: .selectList)

        let result = engine.suggestions(for: query, text: text, caretLocation: 7)
        let suggestions = allSuggestions(from: result)

        // In focused mode, columns are primary in SELECT — keywords/tables should be excluded
        let tableCount = suggestions.filter { $0.kind == .table || $0.kind == .view }.count
        let schemaCount = suggestions.filter { $0.kind == .schema }.count
        // focused excludes peripheral and irrelevant
        #expect(tableCount == 0, "Focused SELECT should not show tables (peripheral)")
        #expect(schemaCount == 0, "Focused SELECT should not show schemas (peripheral)")
    }

    @Test func selectClauseBalancedShowsPrimaryAndSecondary() {
        let engine = makeEngine()
        engine.updateAggressiveness(.balanced)
        let usersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "users", alias: nil)
        let text = "SELECT  FROM users"
        let query = SQLAutoCompletionQuery(token: "", prefix: "", pathComponents: [],
                                            replacementRange: NSRange(location: 7, length: 0),
                                            precedingKeyword: "select", precedingCharacter: nil,
                                            focusTable: usersFocus,
                                            tablesInScope: [usersFocus], clause: .selectList)

        let result = engine.suggestions(for: query, text: text, caretLocation: 7)
        let suggestions = allSuggestions(from: result)

        // Balanced includes primary (columns) and secondary (functions, snippets)
        let columns = suggestions.filter { $0.kind == .column }
        let functions = suggestions.filter { $0.kind == .function }
        #expect(!columns.isEmpty, "Balanced SELECT should show columns (primary)")
        #expect(!functions.isEmpty, "Balanced SELECT should show functions (secondary)")
    }

    @Test func selectClauseEagerShowsEverything() {
        let engine = makeEngine()
        engine.updateAggressiveness(.eager)
        let usersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "users", alias: nil)
        let text = "SELECT  FROM users"
        let query = SQLAutoCompletionQuery(token: "", prefix: "", pathComponents: [],
                                            replacementRange: NSRange(location: 7, length: 0),
                                            precedingKeyword: "select", precedingCharacter: nil,
                                            focusTable: usersFocus,
                                            tablesInScope: [usersFocus], clause: .selectList)

        let result = engine.suggestions(for: query, text: text, caretLocation: 7)
        let suggestions = allSuggestions(from: result)

        // Eager should include everything
        let columns = suggestions.filter { $0.kind == .column }
        let functions = suggestions.filter { $0.kind == .function }
        #expect(!columns.isEmpty, "Eager SELECT should show columns")
        #expect(!functions.isEmpty, "Eager SELECT should show functions")
    }

    // MARK: - Aggressiveness in FROM

    @Test func fromClauseFocusedShowsTablesOnly() {
        let engine = makeEngine()
        engine.updateAggressiveness(.focused)
        let text = "SELECT * FROM "
        let query = SQLAutoCompletionQuery(token: "", prefix: "", pathComponents: [],
                                            replacementRange: NSRange(location: text.count, length: 0),
                                            precedingKeyword: "from", precedingCharacter: nil,
                                            focusTable: nil, tablesInScope: [], clause: .from)

        let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
        let suggestions = allSuggestions(from: result)

        // In FROM, tables/views are primary; columns/functions are peripheral
        let columns = suggestions.filter { $0.kind == .column }
        let functions = suggestions.filter { $0.kind == .function }
        #expect(columns.isEmpty, "Focused FROM should not show columns (peripheral)")
        #expect(functions.isEmpty, "Focused FROM should not show functions (peripheral)")
    }

    @Test func fromClauseEagerShowsMore() {
        let engine = makeEngine()
        engine.updateAggressiveness(.eager)
        let text = "SELECT * FROM "
        let query = SQLAutoCompletionQuery(token: "", prefix: "", pathComponents: [],
                                            replacementRange: NSRange(location: text.count, length: 0),
                                            precedingKeyword: "from", precedingCharacter: nil,
                                            focusTable: nil, tablesInScope: [], clause: .from)

        let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
        let suggestions = allSuggestions(from: result)
        let tables = suggestions.filter { $0.kind == .table || $0.kind == .view }
        #expect(!tables.isEmpty, "Eager FROM should show tables")
    }

    // MARK: - Aggressiveness in WHERE

    @Test func whereClauseFocusedShowsColumnsAndFunctions() {
        let engine = makeEngine()
        engine.updateAggressiveness(.focused)
        let usersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "users", alias: nil)
        let text = "SELECT * FROM users WHERE "
        let query = SQLAutoCompletionQuery(token: "", prefix: "", pathComponents: [],
                                            replacementRange: NSRange(location: text.count, length: 0),
                                            precedingKeyword: "where", precedingCharacter: nil,
                                            focusTable: usersFocus,
                                            tablesInScope: [usersFocus], clause: .whereClause)

        let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
        let suggestions = allSuggestions(from: result)

        // In WHERE, columns are primary, functions are secondary
        let columns = suggestions.filter { $0.kind == .column }
        #expect(!columns.isEmpty, "Focused WHERE should show columns (primary)")
    }

    // MARK: - Suggestion Count Decreases: Eager > Balanced > Focused

    @Test func eagerHasAtLeastAsManyAsFocused() {
        let engine = makeEngine()
        let usersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "users", alias: nil)
        let text = "SELECT  FROM users"
        let query = SQLAutoCompletionQuery(token: "", prefix: "", pathComponents: [],
                                            replacementRange: NSRange(location: 7, length: 0),
                                            precedingKeyword: "select", precedingCharacter: nil,
                                            focusTable: usersFocus,
                                            tablesInScope: [usersFocus], clause: .selectList)

        engine.updateAggressiveness(.focused)
        let focusedResult = engine.suggestions(for: query, text: text, caretLocation: 7)
        let focusedCount = allSuggestions(from: focusedResult).count

        engine.updateAggressiveness(.balanced)
        let balancedResult = engine.suggestions(for: query, text: text, caretLocation: 7)
        let balancedCount = allSuggestions(from: balancedResult).count

        engine.updateAggressiveness(.eager)
        let eagerResult = engine.suggestions(for: query, text: text, caretLocation: 7)
        let eagerCount = allSuggestions(from: eagerResult).count

        #expect(eagerCount >= balancedCount,
                "Eager (\(eagerCount)) should have >= balanced (\(balancedCount))")
        #expect(balancedCount >= focusedCount,
                "Balanced (\(balancedCount)) should have >= focused (\(focusedCount))")
    }

    @Test func fromClauseAggressivenessOrdering() {
        let engine = makeEngine()
        let text = "SELECT * FROM "
        let query = SQLAutoCompletionQuery(token: "", prefix: "", pathComponents: [],
                                            replacementRange: NSRange(location: text.count, length: 0),
                                            precedingKeyword: "from", precedingCharacter: nil,
                                            focusTable: nil, tablesInScope: [], clause: .from)

        engine.updateAggressiveness(.focused)
        let focusedCount = allSuggestions(from: engine.suggestions(for: query, text: text, caretLocation: text.count)).count

        engine.updateAggressiveness(.eager)
        let eagerCount = allSuggestions(from: engine.suggestions(for: query, text: text, caretLocation: text.count)).count

        #expect(eagerCount >= focusedCount,
                "FROM: eager (\(eagerCount)) should have >= focused (\(focusedCount))")
    }

    // MARK: - System Schema Visibility

    @Test func systemSchemasHiddenByDefault() {
        let engine = makeEngine()
        engine.updateAggressiveness(.eager)
        let text = "SELECT * FROM "
        let query = SQLAutoCompletionQuery(token: "", prefix: "", pathComponents: [],
                                            replacementRange: NSRange(location: text.count, length: 0),
                                            precedingKeyword: "from", precedingCharacter: nil,
                                            focusTable: nil, tablesInScope: [], clause: .from)

        let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
        let schemas = allSuggestions(from: result).filter { $0.kind == .schema }.map(\.title)
        let tables = allSuggestions(from: result).filter { $0.kind == .table }.map(\.title)

        // For PostgreSQL dialect, pg_catalog and information_schema are system schemas
        #expect(!schemas.contains("pg_catalog"), "pg_catalog should be hidden by default")
        #expect(!schemas.contains("information_schema"), "information_schema should be hidden by default")
        #expect(!tables.contains("pg_class"), "pg_catalog tables should be hidden by default")
        // Note: "sys" is only a system schema for microsoftSQL dialect, not postgresql
    }

    @Test func systemSchemasVisibleWhenEnabled() {
        let engine = makeEngine()
        engine.updateAggressiveness(.eager)
        engine.updateSystemSchemaVisibility(includeSystemSchemas: true)

        let text = "SELECT * FROM "
        let query = SQLAutoCompletionQuery(token: "", prefix: "", pathComponents: [],
                                            replacementRange: NSRange(location: text.count, length: 0),
                                            precedingKeyword: "from", precedingCharacter: nil,
                                            focusTable: nil, tablesInScope: [], clause: .from)

        let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
        let schemas = allSuggestions(from: result).filter { $0.kind == .schema }.map(\.title)

        // System schemas should now be visible
        #expect(schemas.contains("pg_catalog"), "pg_catalog should be visible when enabled")
    }

    // MARK: - History Toggle

    @Test func historyExcludedWhenDisabled() {
        let engine = makeEngine()
        engine.updateHistoryPreference(includeHistory: false)

        // Query — history should not appear regardless of what's in the store
        let text = "SELECT * FROM "
        let query = SQLAutoCompletionQuery(token: "", prefix: "", pathComponents: [],
                                            replacementRange: NSRange(location: text.count, length: 0),
                                            precedingKeyword: "from", precedingCharacter: nil,
                                            focusTable: nil, tablesInScope: [], clause: .from)

        let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
        let historySuggestions = allSuggestions(from: result).filter { $0.source == .history }
        #expect(historySuggestions.isEmpty, "History should not appear when disabled")
    }

    // MARK: - Schema Qualification Preference

    @Test func qualifiedInsertionPreference() {
        let engine = makeEngine()
        engine.updateQualifiedInsertionPreference(includeSchema: true)
        engine.updateAggressiveness(.eager)

        let text = "SELECT * FROM "
        let query = SQLAutoCompletionQuery(token: "", prefix: "", pathComponents: [],
                                            replacementRange: NSRange(location: text.count, length: 0),
                                            precedingKeyword: "from", precedingCharacter: nil,
                                            focusTable: nil, tablesInScope: [], clause: .from)

        let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
        let tables = allSuggestions(from: result).filter { $0.kind == .table }

        // When qualified insertion is enabled, some tables should have schema-qualified insertText
        // (depends on whether they're in the default schema or not)
        #expect(!tables.isEmpty, "Should still suggest tables with qualified preference")
    }

    @Test func unqualifiedInsertionPreference() {
        let engine = makeEngine()
        engine.updateQualifiedInsertionPreference(includeSchema: false)
        engine.updateAggressiveness(.eager)

        let text = "SELECT * FROM "
        let query = SQLAutoCompletionQuery(token: "", prefix: "", pathComponents: [],
                                            replacementRange: NSRange(location: text.count, length: 0),
                                            precedingKeyword: "from", precedingCharacter: nil,
                                            focusTable: nil, tablesInScope: [], clause: .from)

        let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
        let tables = allSuggestions(from: result).filter { $0.kind == .table }
        #expect(!tables.isEmpty, "Should suggest tables with unqualified preference")
    }

    // MARK: - Alias Preference

    @Test func aliasShortcutsEnabled() {
        let engine = makeEngine()
        engine.updateAliasPreference(useTableAliases: true)
        engine.updateAggressiveness(.eager)

        let text = "SELECT * FROM "
        let query = SQLAutoCompletionQuery(token: "", prefix: "", pathComponents: [],
                                            replacementRange: NSRange(location: text.count, length: 0),
                                            precedingKeyword: "from", precedingCharacter: nil,
                                            focusTable: nil, tablesInScope: [], clause: .from)

        let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
        let tables = allSuggestions(from: result).filter { $0.kind == .table }

        // When alias shortcuts are enabled, insertText might contain alias
        let withSpaces = tables.filter { $0.insertText.contains(" ") }
        #expect(!withSpaces.isEmpty, "Alias shortcuts should add alias to insertText")
    }

    @Test func aliasShortcutsDisabled() {
        let engine = makeEngine()
        engine.updateAliasPreference(useTableAliases: false)
        engine.updateAggressiveness(.eager)

        let text = "SELECT * FROM "
        let query = SQLAutoCompletionQuery(token: "", prefix: "", pathComponents: [],
                                            replacementRange: NSRange(location: text.count, length: 0),
                                            precedingKeyword: "from", precedingCharacter: nil,
                                            focusTable: nil, tablesInScope: [], clause: .from)

        let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
        let tables = allSuggestions(from: result).filter { $0.kind == .table }

        // Without alias shortcuts, insertText should not have extra space/alias
        let withSpaces = tables.filter { $0.insertText.contains(" ") }
        #expect(withSpaces.isEmpty, "Without alias shortcuts, insertText should not contain spaces")
    }

    // MARK: - JOIN Condition Aggressiveness

    @Test func joinConditionFocusedShowsJoinSuggestions() {
        let engine = makeEngine()
        engine.updateAggressiveness(.focused)
        let usersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "users", alias: "u")
        let ordersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "orders", alias: "o")
        let text = "SELECT * FROM users u JOIN orders o ON "
        let query = SQLAutoCompletionQuery(token: "", prefix: "", pathComponents: [],
                                            replacementRange: NSRange(location: text.count, length: 0),
                                            precedingKeyword: "on", precedingCharacter: nil,
                                            focusTable: ordersFocus,
                                            tablesInScope: [usersFocus, ordersFocus],
                                            clause: .joinCondition)

        let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
        let suggestions = allSuggestions(from: result)

        // Join suggestions and columns are primary in joinCondition
        let joinSuggestions = suggestions.filter { $0.kind == .join || $0.kind == .column }
        #expect(!joinSuggestions.isEmpty, "Focused JOIN ON should show join/column suggestions")
    }

    // MARK: - Manual Trigger Override

    @Test func manualTriggerShowsSuggestionsInSuppressedContext() {
        let engine = makeEngine()
        engine.updateAggressiveness(.focused)
        engine.beginManualTrigger()

        let usersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "users", alias: nil)
        let text = "SELECT * FROM users WHERE "
        let query = SQLAutoCompletionQuery(token: "", prefix: "", pathComponents: [],
                                            replacementRange: NSRange(location: text.count, length: 0),
                                            precedingKeyword: "where", precedingCharacter: nil,
                                            focusTable: usersFocus,
                                            tablesInScope: [usersFocus], clause: .whereClause)

        let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
        let suggestions = allSuggestions(from: result)
        engine.endManualTrigger()

        #expect(!suggestions.isEmpty, "Manual trigger should show suggestions even in focused mode")
    }

    // MARK: - Limit/Offset Aggressiveness

    @Test func limitClauseFocusedShowsKeywords() {
        let engine = makeEngine()
        engine.updateAggressiveness(.focused)
        let text = "SELECT * FROM users LIMIT "
        let query = SQLAutoCompletionQuery(token: "", prefix: "", pathComponents: [],
                                            replacementRange: NSRange(location: text.count, length: 0),
                                            precedingKeyword: "limit", precedingCharacter: nil,
                                            focusTable: nil, tablesInScope: [], clause: .limit)

        let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
        let suggestions = allSuggestions(from: result)
        // In limit context, keywords are primary
        let columns = suggestions.filter { $0.kind == .column }
        #expect(columns.isEmpty, "Focused LIMIT should not show columns (peripheral)")
    }
}
