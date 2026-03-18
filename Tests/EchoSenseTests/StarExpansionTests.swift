import Foundation
import Testing
@testable import EchoSense

@Suite("Star Expansion")
struct StarExpansionTests {

    // MARK: - Helpers

    private func makeStructure(columnCount: Int? = nil) -> EchoSenseDatabaseStructure {
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

        var usersColumns = [idCol, nameCol, emailCol, createdAtCol]
        if let count = columnCount {
            // Add extra columns for the "many columns" test
            for i in 0..<max(0, count - usersColumns.count) {
                usersColumns.append(EchoSenseColumnInfo(name: "extra_col_\(i)", dataType: "text", isNullable: true))
            }
        }

        let usersTable = EchoSenseSchemaObjectInfo(name: "users", schema: "public",
                                                    type: .table, columns: usersColumns)
        let ordersTable = EchoSenseSchemaObjectInfo(name: "orders", schema: "public",
                                                     type: .table, columns: [idCol, userIdCol, amountCol, statusCol])

        let publicSchema = EchoSenseSchemaInfo(name: "public", objects: [usersTable, ordersTable])
        let database = EchoSenseDatabaseInfo(name: "testdb", schemas: [publicSchema])
        return EchoSenseDatabaseStructure(databases: [database])
    }

    private func makeEngine(columnCount: Int? = nil) -> SQLAutoCompletionEngine {
        let engine = SQLAutoCompletionEngine()
        let context = SQLEditorCompletionContext(databaseType: .postgresql,
                                                  selectedDatabase: "testdb",
                                                  defaultSchema: "public",
                                                  structure: makeStructure(columnCount: columnCount))
        engine.updateContext(context)
        engine.updateAggressiveness(.eager)
        engine.updateHistoryPreference(includeHistory: false)
        return engine
    }

    private func allSuggestions(from result: SQLAutoCompletionResult) -> [SQLAutoCompletionSuggestion] {
        result.sections.flatMap(\.suggestions)
    }

    private func starSuggestions(from result: SQLAutoCompletionResult) -> [SQLAutoCompletionSuggestion] {
        allSuggestions(from: result).filter { $0.id.hasPrefix("star|") }
    }

    // MARK: - Basic Star Expansion

    @Test func starExpansionSuggestedForStarToken() {
        let engine = makeEngine()
        engine.beginManualTrigger()
        let usersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "users", alias: nil)
        let text = "SELECT * FROM users"
        let query = SQLAutoCompletionQuery(token: "*", prefix: "*", pathComponents: [],
                                            replacementRange: NSRange(location: 7, length: 1),
                                            precedingKeyword: "select", precedingCharacter: nil,
                                            focusTable: usersFocus,
                                            tablesInScope: [usersFocus],
                                            clause: .selectList)

        let result = engine.suggestions(for: query, text: text, caretLocation: 8)
        let stars = starSuggestions(from: result)
        engine.endManualTrigger()

        #expect(!stars.isEmpty, "Star expansion should be suggested for * token with manual trigger")
    }

    @Test func starExpansionContainsColumnNames() {
        let engine = makeEngine()
        engine.beginManualTrigger()
        let usersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "users", alias: nil)
        let text = "SELECT * FROM users"
        let query = SQLAutoCompletionQuery(token: "*", prefix: "*", pathComponents: [],
                                            replacementRange: NSRange(location: 7, length: 1),
                                            precedingKeyword: "select", precedingCharacter: nil,
                                            focusTable: usersFocus,
                                            tablesInScope: [usersFocus],
                                            clause: .selectList)

        let result = engine.suggestions(for: query, text: text, caretLocation: 8)
        let stars = starSuggestions(from: result)
        engine.endManualTrigger()

        guard let starSuggestion = stars.first else {
            #expect(Bool(false), "Should have star expansion suggestion")
            return
        }

        // insertText should contain all column names
        #expect(starSuggestion.insertText.contains("id"), "Expansion should contain id")
        #expect(starSuggestion.insertText.contains("email"), "Expansion should contain email")
        #expect(starSuggestion.insertText.contains("created_at"), "Expansion should contain created_at")
    }

    // MARK: - Alias-Qualified Star Expansion

    @Test func aliasStarExpansionQualifiesColumns() {
        let engine = makeEngine()
        engine.beginManualTrigger()
        let usersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "users", alias: "u")
        let text = "SELECT u.* FROM users u"
        let query = SQLAutoCompletionQuery(token: "u.*", prefix: "*", pathComponents: ["u"],
                                            replacementRange: NSRange(location: 7, length: 3),
                                            precedingKeyword: "select", precedingCharacter: nil,
                                            focusTable: usersFocus,
                                            tablesInScope: [usersFocus],
                                            clause: .selectList)

        let result = engine.suggestions(for: query, text: text, caretLocation: 10)
        let stars = starSuggestions(from: result)
        engine.endManualTrigger()

        guard let starSuggestion = stars.first else {
            #expect(Bool(false), "Should have alias-qualified star expansion")
            return
        }

        // Columns should be qualified with alias
        #expect(starSuggestion.insertText.contains("u."), "Expansion should qualify with alias u")
    }

    // MARK: - No Manual Trigger = No Expansion

    @Test func starExpansionRequiresManualTrigger() {
        let engine = makeEngine()
        // NOTE: Not calling beginManualTrigger
        let usersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "users", alias: nil)
        let text = "SELECT * FROM users"
        let query = SQLAutoCompletionQuery(token: "*", prefix: "*", pathComponents: [],
                                            replacementRange: NSRange(location: 7, length: 1),
                                            precedingKeyword: "select", precedingCharacter: nil,
                                            focusTable: usersFocus,
                                            tablesInScope: [usersFocus],
                                            clause: .selectList)

        let result = engine.suggestions(for: query, text: text, caretLocation: 8)
        let suggestions = allSuggestions(from: result)
        // Without manual trigger, * token should produce no suggestions
        #expect(suggestions.isEmpty, "Without manual trigger, * should not produce suggestions")
    }

    // MARK: - No Focus Table

    @Test func starExpansionWithNoTablesInScope() {
        let engine = makeEngine()
        engine.beginManualTrigger()
        let text = "SELECT *"
        let query = SQLAutoCompletionQuery(token: "*", prefix: "*", pathComponents: [],
                                            replacementRange: NSRange(location: 7, length: 1),
                                            precedingKeyword: "select", precedingCharacter: nil,
                                            focusTable: nil,
                                            tablesInScope: [],
                                            clause: .selectList)

        let result = engine.suggestions(for: query, text: text, caretLocation: 8)
        let stars = starSuggestions(from: result)
        engine.endManualTrigger()

        // Without tables in scope, star expansion should produce nothing
        #expect(stars.isEmpty, "Star expansion without tables in scope should be empty")
    }

    // MARK: - Column Ordering

    @Test func starExpansionPreservesColumnOrder() {
        let engine = makeEngine()
        engine.beginManualTrigger()
        let usersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "users", alias: nil)
        let text = "SELECT * FROM users"
        let query = SQLAutoCompletionQuery(token: "*", prefix: "*", pathComponents: [],
                                            replacementRange: NSRange(location: 7, length: 1),
                                            precedingKeyword: "select", precedingCharacter: nil,
                                            focusTable: usersFocus,
                                            tablesInScope: [usersFocus],
                                            clause: .selectList)

        let result = engine.suggestions(for: query, text: text, caretLocation: 8)
        let stars = starSuggestions(from: result)
        engine.endManualTrigger()

        guard let starSuggestion = stars.first else {
            #expect(Bool(false), "Should have star expansion")
            return
        }

        // The column order should follow table definition: id, name, email, created_at
        let columns = starSuggestion.insertText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        if columns.count >= 4 {
            #expect(columns[0] == "id" || columns[0].hasSuffix(".id"), "First column should be id")
        }
    }

    // MARK: - Many Columns

    @Test func starExpansionWithManyColumns() {
        let engine = makeEngine(columnCount: 55)
        engine.beginManualTrigger()
        let usersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "users", alias: nil)
        let text = "SELECT * FROM users"
        let query = SQLAutoCompletionQuery(token: "*", prefix: "*", pathComponents: [],
                                            replacementRange: NSRange(location: 7, length: 1),
                                            precedingKeyword: "select", precedingCharacter: nil,
                                            focusTable: usersFocus,
                                            tablesInScope: [usersFocus],
                                            clause: .selectList)

        let result = engine.suggestions(for: query, text: text, caretLocation: 8)
        let stars = starSuggestions(from: result)
        engine.endManualTrigger()

        guard let starSuggestion = stars.first else {
            #expect(Bool(false), "Should handle 50+ columns")
            return
        }

        // insertText should contain all columns
        let columns = starSuggestion.insertText.split(separator: ",")
        #expect(columns.count == 55, "Should expand all 55 columns, got \(columns.count)")
    }

    // MARK: - Multiple Tables Star Expansion

    @Test func starExpansionWithMultipleTables() {
        let engine = makeEngine()
        engine.beginManualTrigger()
        let usersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "users", alias: "u")
        let ordersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "orders", alias: "o")
        let text = "SELECT * FROM users u JOIN orders o ON u.id = o.user_id"
        let query = SQLAutoCompletionQuery(token: "*", prefix: "*", pathComponents: [],
                                            replacementRange: NSRange(location: 7, length: 1),
                                            precedingKeyword: "select", precedingCharacter: nil,
                                            focusTable: usersFocus,
                                            tablesInScope: [usersFocus, ordersFocus],
                                            clause: .selectList)

        let result = engine.suggestions(for: query, text: text, caretLocation: 8)
        let stars = starSuggestions(from: result)
        engine.endManualTrigger()

        guard let starSuggestion = stars.first else {
            #expect(Bool(false), "Should expand * with multiple tables")
            return
        }

        // Should contain columns from both tables, qualified with alias
        #expect(starSuggestion.insertText.contains("u."), "Should have u-qualified columns")
        #expect(starSuggestion.insertText.contains("o."), "Should have o-qualified columns")
    }

    // MARK: - Star Expansion Not in Other Clauses

    @Test func starExpansionOnlyInSelectList() {
        let engine = makeEngine()
        engine.beginManualTrigger()
        let usersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "users", alias: nil)
        let text = "SELECT * FROM users WHERE *"
        let query = SQLAutoCompletionQuery(token: "*", prefix: "*", pathComponents: [],
                                            replacementRange: NSRange(location: 26, length: 1),
                                            precedingKeyword: "where", precedingCharacter: nil,
                                            focusTable: usersFocus,
                                            tablesInScope: [usersFocus],
                                            clause: .whereClause)

        let result = engine.suggestions(for: query, text: text, caretLocation: 27)
        let stars = starSuggestions(from: result)
        engine.endManualTrigger()

        #expect(stars.isEmpty, "Star expansion should only work in SELECT list")
    }

    // MARK: - Star Suggestion Metadata

    @Test func starSuggestionHasSnippetKind() {
        let engine = makeEngine()
        engine.beginManualTrigger()
        let usersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "users", alias: nil)
        let text = "SELECT * FROM users"
        let query = SQLAutoCompletionQuery(token: "*", prefix: "*", pathComponents: [],
                                            replacementRange: NSRange(location: 7, length: 1),
                                            precedingKeyword: "select", precedingCharacter: nil,
                                            focusTable: usersFocus,
                                            tablesInScope: [usersFocus],
                                            clause: .selectList)

        let result = engine.suggestions(for: query, text: text, caretLocation: 8)
        let stars = starSuggestions(from: result)
        engine.endManualTrigger()

        guard let star = stars.first else {
            #expect(Bool(false), "Should have star suggestion")
            return
        }

        // Star expansion is a snippet
        #expect(star.kind == .snippet, "Star expansion should be kind .snippet")
        #expect(star.title == "Expand * to columns", "Star expansion should have descriptive title")
    }

    // MARK: - Star Expansion ID Uniqueness

    @Test func starExpansionIDIsUnique() {
        let engine = makeEngine()
        engine.beginManualTrigger()
        let usersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "users", alias: nil)
        let text = "SELECT * FROM users"
        let query = SQLAutoCompletionQuery(token: "*", prefix: "*", pathComponents: [],
                                            replacementRange: NSRange(location: 7, length: 1),
                                            precedingKeyword: "select", precedingCharacter: nil,
                                            focusTable: usersFocus,
                                            tablesInScope: [usersFocus],
                                            clause: .selectList)

        let result = engine.suggestions(for: query, text: text, caretLocation: 8)
        let stars = starSuggestions(from: result)
        engine.endManualTrigger()

        // Should have exactly one star expansion
        #expect(stars.count <= 1, "Should have at most one star expansion, got \(stars.count)")
        if let star = stars.first {
            #expect(star.id.hasPrefix("star|"), "Star ID should start with 'star|'")
        }
    }

    // MARK: - Detail Preview

    @Test func starExpansionDetailShowsPreview() {
        let engine = makeEngine()
        engine.beginManualTrigger()
        let usersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "users", alias: nil)
        let text = "SELECT * FROM users"
        let query = SQLAutoCompletionQuery(token: "*", prefix: "*", pathComponents: [],
                                            replacementRange: NSRange(location: 7, length: 1),
                                            precedingKeyword: "select", precedingCharacter: nil,
                                            focusTable: usersFocus,
                                            tablesInScope: [usersFocus],
                                            clause: .selectList)

        let result = engine.suggestions(for: query, text: text, caretLocation: 8)
        let stars = starSuggestions(from: result)
        engine.endManualTrigger()

        guard let star = stars.first else {
            #expect(Bool(false), "Should have star suggestion")
            return
        }

        // Detail should be a preview of columns (first few)
        #expect(star.detail != nil, "Star expansion should have a detail preview")
        if let detail = star.detail {
            #expect(detail.contains("id"), "Detail should contain id column")
        }
    }

    // MARK: - Manual Trigger State

    @Test func manualTriggerStateIsCorrectlyToggled() {
        let engine = makeEngine()

        #expect(!engine.isManualTriggerActive, "Should start inactive")

        engine.beginManualTrigger()
        #expect(engine.isManualTriggerActive, "Should be active after begin")

        engine.endManualTrigger()
        #expect(!engine.isManualTriggerActive, "Should be inactive after end")
    }
}
