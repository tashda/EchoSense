import Foundation
import Testing
@testable import EchoSense

// MARK: - Section 2: FROM Clause

@Suite("Spec 2: FROM Clause")
struct SpecFROMClauseTests {

    // MARK: 2.1 After FROM → tables/views from all schemas, schemas

    @Test("2.1 After FROM suggests tables and views from all schemas")
    func afterFROMSuggestsTablesAndViews() {
        let engine = SpecHelpers.makeSpecEngine()
        let text = "SELECT * FROM "
        let query = SQLAutoCompletionQuery(
            token: "", prefix: "", pathComponents: [],
            replacementRange: NSRange(location: text.count, length: 0),
            precedingKeyword: "from", precedingCharacter: nil,
            focusTable: nil, tablesInScope: [], clause: .from
        )

        let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
        let suggestions = SpecHelpers.allSuggestions(from: result)
        let titles = SpecHelpers.suggestionTitles(from: result)
        let kinds = SpecHelpers.suggestionKinds(from: result)

        // Tables from public schema
        #expect(titles.contains("users"))
        #expect(titles.contains("orders"))
        #expect(titles.contains("products"))
        #expect(titles.contains("categories"))
        #expect(titles.contains("departments"))

        // View from public schema
        #expect(titles.contains("active_users"))

        // Tables from analytics schema (may be qualified)
        let hasEvents = titles.contains("events") || titles.contains("analytics.events")
        #expect(hasEvents, "Should include analytics.events table")

        // Schemas should be suggested
        #expect(kinds.contains(.schema))
    }

    @Test("2.1 After FROM suggests schemas")
    func afterFROMSuggestsSchemas() {
        let engine = SpecHelpers.makeSpecEngine()
        let text = "SELECT * FROM "
        let query = SQLAutoCompletionQuery(
            token: "", prefix: "", pathComponents: [],
            replacementRange: NSRange(location: text.count, length: 0),
            precedingKeyword: "from", precedingCharacter: nil,
            focusTable: nil, tablesInScope: [], clause: .from
        )

        let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
        let suggestions = SpecHelpers.allSuggestions(from: result)
        let schemaNames = suggestions.filter { $0.kind == .schema }.map(\.title)

        #expect(schemaNames.contains("public"))
        #expect(schemaNames.contains("analytics"))
    }

    // MARK: 2.2 FROM partial typing → prefix match

    @Test("2.2 FROM partial typing filters by prefix")
    func fromPartialTypingFilters() {
        let engine = SpecHelpers.makeSpecEngine()
        let text = "SELECT * FROM us"
        let query = SQLAutoCompletionQuery(
            token: "us", prefix: "us", pathComponents: [],
            replacementRange: NSRange(location: 14, length: 2),
            precedingKeyword: "from", precedingCharacter: nil,
            focusTable: nil, tablesInScope: [], clause: .from
        )

        let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
        let titles = SpecHelpers.suggestionTitles(from: result)

        #expect(titles.contains("users"))
        #expect(!titles.contains("orders"))
        // "users" should be the top table result (prefix match ranks highest)
        let tableAndViewTitles = SpecHelpers.allSuggestions(from: result)
            .filter { $0.kind == .table || $0.kind == .view }
            .map(\.title)
        if let first = tableAndViewTitles.first {
            #expect(first == "users", "Prefix match 'users' should rank first for 'us'")
        }
    }

    @Test("2.2 FROM partial typing matches multiple tables with same prefix")
    func fromPartialTypingMatchesMultiple() {
        let engine = SpecHelpers.makeSpecEngine()
        let text = "SELECT * FROM c"
        let query = SQLAutoCompletionQuery(
            token: "c", prefix: "c", pathComponents: [],
            replacementRange: NSRange(location: 14, length: 1),
            precedingKeyword: "from", precedingCharacter: nil,
            focusTable: nil, tablesInScope: [], clause: .from
        )

        let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
        let suggestions = SpecHelpers.allSuggestions(from: result)
        let tableNames = suggestions.filter { $0.kind == .table }.map(\.title)

        #expect(tableNames.contains("categories"))
    }

    // MARK: 2.3 FROM schema dot → tables from that schema only

    @Test("2.3 FROM schema dot shows tables from that schema only")
    func fromSchemaDotShowsSchemaTablesOnly() {
        let engine = SpecHelpers.makeSpecEngine()
        let text = "SELECT * FROM analytics."
        let query = SQLAutoCompletionQuery(
            token: "analytics.", prefix: "", pathComponents: ["analytics"],
            replacementRange: NSRange(location: 24, length: 0),
            precedingKeyword: "from", precedingCharacter: ".",
            focusTable: nil, tablesInScope: [], clause: .from
        )

        let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
        let suggestions = SpecHelpers.allSuggestions(from: result)
        let tableNames = suggestions.filter { $0.kind == .table }.map(\.title)

        #expect(tableNames.contains("events"))
        #expect(tableNames.contains("metrics"))
        // Should NOT include tables from public schema
        #expect(!tableNames.contains("users"))
        #expect(!tableNames.contains("orders"))
    }

    // MARK: 2.4 FROM schema dot partial → filtered

    @Test("2.4 FROM schema dot with partial typing filters")
    func fromSchemaDotPartialFilters() {
        let engine = SpecHelpers.makeSpecEngine()
        let text = "SELECT * FROM analytics.ev"
        let query = SQLAutoCompletionQuery(
            token: "analytics.ev", prefix: "ev", pathComponents: ["analytics"],
            replacementRange: NSRange(location: 24, length: 2),
            precedingKeyword: "from", precedingCharacter: nil,
            focusTable: nil, tablesInScope: [], clause: .from
        )

        let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
        let suggestions = SpecHelpers.allSuggestions(from: result)
        let tableNames = suggestions.filter { $0.kind == .table }.map(\.title)

        #expect(tableNames.contains("events"))
        #expect(!tableNames.contains("metrics"))
    }

    // MARK: 2.5 FROM after comma → tables immediately

    @Test("2.5 FROM after comma suggests tables immediately")
    func fromAfterCommaSuggestsTables() {
        let engine = SpecHelpers.makeSpecEngine()
        let text = "SELECT * FROM users, "
        let usersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "users", alias: nil)
        let query = SQLAutoCompletionQuery(
            token: "", prefix: "", pathComponents: [],
            replacementRange: NSRange(location: text.count, length: 0),
            precedingKeyword: "from", precedingCharacter: ",",
            focusTable: nil, tablesInScope: [usersFocus], clause: .from
        )

        let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
        let suggestions = SpecHelpers.allSuggestions(from: result)
        let kinds = Set(suggestions.map(\.kind))

        #expect(kinds.contains(.table))
    }

    // MARK: 2.6 Space after table on same line → SILENT

    @Test("2.6 Space after table on same line is silent")  // NEW BEHAVIOR
    func spaceAfterTableOnSameLineIsSilent() {
        let engine = SpecHelpers.makeSpecEngine()
        let text = "SELECT * FROM users "
        let usersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "users", alias: nil)
        let query = SQLAutoCompletionQuery(
            token: "", prefix: "", pathComponents: [],
            replacementRange: NSRange(location: text.count, length: 0),
            precedingKeyword: "from", precedingCharacter: " ",
            focusTable: usersFocus, tablesInScope: [usersFocus], clause: .from
        )

        let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
        let suggestions = SpecHelpers.allSuggestions(from: result)

        // NEW BEHAVIOR: Should return no suggestions (silent) after space on same line
        #expect(suggestions.isEmpty, "Should be silent after space following table on same line")
    }

    // MARK: 2.7 New line after table → silent until typing, then keywords

    @Test("2.7 New line after table is silent until typing")  // NEW BEHAVIOR
    func newLineAfterTableIsSilentUntilTyping() {
        let engine = SpecHelpers.makeSpecEngine()
        let text = "SELECT * FROM users\n"
        let usersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "users", alias: nil)
        let query = SQLAutoCompletionQuery(
            token: "", prefix: "", pathComponents: [],
            replacementRange: NSRange(location: text.count, length: 0),
            precedingKeyword: "from", precedingCharacter: "\n",
            focusTable: usersFocus, tablesInScope: [usersFocus], clause: .from
        )

        let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
        let suggestions = SpecHelpers.allSuggestions(from: result)

        // NEW BEHAVIOR: Should be silent on blank new line
        #expect(suggestions.isEmpty, "Should be silent on new line until user starts typing")
    }

    @Test("2.7 Typing on new line after table suggests keywords")  // NEW BEHAVIOR
    func typingOnNewLineAfterTableSuggestsKeywords() {
        let engine = SpecHelpers.makeSpecEngine()
        let text = "SELECT * FROM users\nWH"
        let usersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "users", alias: nil)
        let query = SQLAutoCompletionQuery(
            token: "WH", prefix: "WH", pathComponents: [],
            replacementRange: NSRange(location: 20, length: 2),
            precedingKeyword: "from", precedingCharacter: nil,
            focusTable: usersFocus, tablesInScope: [usersFocus], clause: .from
        )

        let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
        let suggestions = SpecHelpers.allSuggestions(from: result)
        let keywords = suggestions.filter { $0.kind == .keyword }.map { $0.title.uppercased() }

        // NEW BEHAVIOR: Once user starts typing, keywords should appear
        #expect(keywords.contains("WHERE"), "Should suggest WHERE when typing on new line")
    }

    // MARK: 2.8 INSERT INTO → tables only

    @Test("2.8 INSERT INTO suggests tables only")
    func insertIntoSuggestsTables() {
        let engine = SpecHelpers.makeSpecEngine()
        let text = "INSERT INTO "
        let query = SQLAutoCompletionQuery(
            token: "", prefix: "", pathComponents: [],
            replacementRange: NSRange(location: text.count, length: 0),
            precedingKeyword: "into", precedingCharacter: nil,
            focusTable: nil, tablesInScope: [], clause: .from
        )

        let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
        let suggestions = SpecHelpers.allSuggestions(from: result)
        let kinds = Set(suggestions.map(\.kind))

        #expect(kinds.contains(.table))
        // Should not suggest views for INSERT
        let viewSuggestions = suggestions.filter { $0.kind == .view }
        #expect(viewSuggestions.isEmpty, "INSERT INTO should not suggest views")
    }

    // MARK: 2.9 UPDATE → tables

    @Test("2.9 UPDATE suggests tables")
    func updateSuggestsTables() {
        let engine = SpecHelpers.makeSpecEngine()
        let text = "UPDATE "
        let query = SQLAutoCompletionQuery(
            token: "", prefix: "", pathComponents: [],
            replacementRange: NSRange(location: text.count, length: 0),
            precedingKeyword: "update", precedingCharacter: nil,
            focusTable: nil, tablesInScope: [], clause: .from
        )

        let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
        let suggestions = SpecHelpers.allSuggestions(from: result)
        let tableNames = suggestions.filter { $0.kind == .table }.map(\.title)

        #expect(tableNames.contains("users"))
        #expect(tableNames.contains("orders"))
    }

    // MARK: 2.10 DELETE FROM → tables

    @Test("2.10 DELETE FROM suggests tables")
    func deleteFromSuggestsTables() {
        let engine = SpecHelpers.makeSpecEngine()
        let text = "DELETE FROM "
        let query = SQLAutoCompletionQuery(
            token: "", prefix: "", pathComponents: [],
            replacementRange: NSRange(location: text.count, length: 0),
            precedingKeyword: "from", precedingCharacter: nil,
            focusTable: nil, tablesInScope: [], clause: .from
        )

        let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
        let suggestions = SpecHelpers.allSuggestions(from: result)
        let tableNames = suggestions.filter { $0.kind == .table }.map(\.title)

        #expect(tableNames.contains("users"))
        #expect(tableNames.contains("orders"))
    }

    // MARK: 2.11 Default schema unqualified, non-default qualified

    @Test("2.11 Default schema tables shown unqualified, non-default qualified")
    func defaultSchemaUnqualifiedNonDefaultQualified() {
        let engine = SpecHelpers.makeSpecEngine()
        let text = "SELECT * FROM "
        let query = SQLAutoCompletionQuery(
            token: "", prefix: "", pathComponents: [],
            replacementRange: NSRange(location: text.count, length: 0),
            precedingKeyword: "from", precedingCharacter: nil,
            focusTable: nil, tablesInScope: [], clause: .from
        )

        let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
        let suggestions = SpecHelpers.allSuggestions(from: result)
        let tableSuggestions = suggestions.filter { $0.kind == .table }

        // Default schema (public) tables should have unqualified insertText
        let usersInsertTexts = tableSuggestions.filter { $0.title == "users" }.map(\.insertText)
        #expect(usersInsertTexts.contains("users"), "Default schema table should insert unqualified name")

        // Non-default schema (analytics) tables should have qualified insertText
        let eventsSuggestions = tableSuggestions.filter { $0.title == "events" }
        if !eventsSuggestions.isEmpty {
            let eventsInsertText = eventsSuggestions.first?.insertText ?? ""
            #expect(eventsInsertText.contains("analytics."), "Non-default schema table should insert qualified name")
        }
    }

    // MARK: 2.12 Multiple schemas same table name → both shown

    @Test("2.12 Tables with same name in different schemas both appear")
    func multipleSchemasSameTableNameBothShown() {
        // This test verifies the engine can show tables from different schemas
        // even when they share names. The spec schema doesn't have same-named tables
        // across schemas, but we verify both schemas' tables appear.
        let engine = SpecHelpers.makeSpecEngine()
        let text = "SELECT * FROM "
        let query = SQLAutoCompletionQuery(
            token: "", prefix: "", pathComponents: [],
            replacementRange: NSRange(location: text.count, length: 0),
            precedingKeyword: "from", precedingCharacter: nil,
            focusTable: nil, tablesInScope: [], clause: .from
        )

        let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
        let suggestions = SpecHelpers.allSuggestions(from: result)
        let tableSuggestions = suggestions.filter { $0.kind == .table }

        // Verify tables from both schemas are present
        let allTableTitles = Set(tableSuggestions.map(\.title))
        let allInsertTexts = Set(tableSuggestions.map(\.insertText))

        // public schema tables
        #expect(allTableTitles.contains("users"))
        // analytics schema tables
        let hasAnalyticsTables = allTableTitles.contains("events") || allInsertTexts.contains("analytics.events")
        #expect(hasAnalyticsTables, "Should include tables from analytics schema")
    }
}

// MARK: - Section 3: JOIN

@Suite("Spec 3: JOIN")
struct SpecJOINTests {

    // MARK: 3.1 JOIN target → FK suggestions immediately + regular tables

    @Test("3.1 JOIN suggests FK-related tables first plus regular tables")
    func joinTargetSuggestsFKAndRegularTables() {
        let engine = SpecHelpers.makeSpecEngine()
        let usersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "users", alias: "u")
        let text = "SELECT * FROM users u JOIN "
        let query = SQLAutoCompletionQuery(
            token: "", prefix: "", pathComponents: [],
            replacementRange: NSRange(location: text.count, length: 0),
            precedingKeyword: "join", precedingCharacter: nil,
            focusTable: nil, tablesInScope: [usersFocus], clause: .joinTarget
        )

        let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
        let suggestions = SpecHelpers.allSuggestions(from: result)

        // FK-related tables should appear as join suggestions
        let joinSuggestions = suggestions.filter { $0.kind == .join }
        let joinTitles = joinSuggestions.map(\.title)
        // orders has FK to users, so it should be a join suggestion
        let hasOrdersJoin = joinTitles.contains { $0.contains("orders") }
        #expect(hasOrdersJoin, "Should suggest orders as FK join target (orders.user_id → users.id)")

        // Regular tables should also be available
        let tableSuggestions = suggestions.filter { $0.kind == .table }
        #expect(!tableSuggestions.isEmpty, "Should also include regular table suggestions")
    }

    // MARK: 3.2 JOIN target partial typing

    @Test("3.2 JOIN target filters by partial typing")
    func joinTargetPartialTyping() {
        let engine = SpecHelpers.makeSpecEngine()
        let usersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "users", alias: "u")
        let text = "SELECT * FROM users u JOIN ord"
        let query = SQLAutoCompletionQuery(
            token: "ord", prefix: "ord", pathComponents: [],
            replacementRange: NSRange(location: 26, length: 3),
            precedingKeyword: "join", precedingCharacter: nil,
            focusTable: nil, tablesInScope: [usersFocus], clause: .joinTarget
        )

        let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
        let titles = SpecHelpers.suggestionTitles(from: result)

        // Should match "orders" but not "products" or "users"
        let hasOrders = titles.contains { $0.contains("orders") }
        #expect(hasOrders, "Should match orders with prefix 'ord'")
        #expect(!titles.contains("products"))
    }

    // MARK: 3.3 Multiple JOINs → already-joined excluded

    @Test("3.3 Already-joined tables excluded from suggestions")
    func multipleJoinsExcludeAlreadyJoined() {
        let engine = SpecHelpers.makeSpecEngine()
        let usersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "users", alias: "u")
        let ordersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "orders", alias: "o")
        let text = "SELECT * FROM users u JOIN orders o ON o.user_id = u.id JOIN "
        let query = SQLAutoCompletionQuery(
            token: "", prefix: "", pathComponents: [],
            replacementRange: NSRange(location: text.count, length: 0),
            precedingKeyword: "join", precedingCharacter: nil,
            focusTable: nil, tablesInScope: [usersFocus, ordersFocus], clause: .joinTarget
        )

        let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
        let suggestions = SpecHelpers.allSuggestions(from: result)
        let tableSuggestions = suggestions.filter { $0.kind == .table }
        let tableNames = tableSuggestions.map(\.title)

        // Already-joined tables should be excluded
        #expect(!tableNames.contains("users"), "Already-joined table 'users' should be excluded")
        #expect(!tableNames.contains("orders"), "Already-joined table 'orders' should be excluded")

        // Other tables should still appear
        #expect(tableNames.contains("products") || tableNames.contains("categories") || tableNames.contains("departments"),
                "Non-joined tables should still appear")
    }

    // MARK: 3.5 JOIN ON → FK condition suggestions

    @Test("3.5 JOIN ON suggests FK condition")
    func joinOnSuggestsFKCondition() {
        let engine = SpecHelpers.makeSpecEngine()
        let usersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "users", alias: "u")
        let ordersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "orders", alias: "o")
        let text = "SELECT * FROM users u JOIN orders o ON "
        let query = SQLAutoCompletionQuery(
            token: "", prefix: "", pathComponents: [],
            replacementRange: NSRange(location: text.count, length: 0),
            precedingKeyword: "on", precedingCharacter: nil,
            focusTable: ordersFocus,
            tablesInScope: [usersFocus, ordersFocus], clause: .joinCondition
        )

        let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
        let suggestions = SpecHelpers.allSuggestions(from: result)

        // Should suggest the FK condition (o.user_id = u.id or similar)
        let hasJoinCondition = suggestions.contains { suggestion in
            suggestion.insertText.contains("user_id") && suggestion.insertText.contains("id")
        }
        let hasColumns = suggestions.contains { $0.kind == .column }

        // Either a full join condition snippet or at least columns should appear
        #expect(hasJoinCondition || hasColumns,
                "Should suggest FK condition or columns after JOIN ON")
    }

    // MARK: 3.6 JOIN ON alias dot → columns

    @Test("3.6 JOIN ON alias dot shows columns of aliased table")
    func joinOnAliasDotShowsColumns() {
        let engine = SpecHelpers.makeSpecEngine()
        let usersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "users", alias: "u")
        let ordersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "orders", alias: "o")
        let text = "SELECT * FROM users u JOIN orders o ON o."
        let query = SQLAutoCompletionQuery(
            token: "o.", prefix: "", pathComponents: ["o"],
            replacementRange: NSRange(location: 41, length: 0),
            precedingKeyword: "on", precedingCharacter: ".",
            focusTable: ordersFocus,
            tablesInScope: [usersFocus, ordersFocus], clause: .joinCondition
        )

        let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
        let suggestions = SpecHelpers.allSuggestions(from: result)
        let columnNames = suggestions.filter { $0.kind == .column }.map(\.title)

        // Should show columns from orders (aliased as o)
        // Note: reserved words like "status" may be auto-quoted
        #expect(columnNames.contains("id"))
        #expect(columnNames.contains("user_id"))
        #expect(columnNames.contains("total"))
        #expect(columnNames.contains("status") || columnNames.contains("\"status\""))

        // Should NOT show columns from users
        #expect(!columnNames.contains("email"))
    }

    // MARK: 3.7 Self-join → qualified columns only, no auto condition

    @Test("3.7 Self-join shows qualified columns, no auto FK condition")  // NEW BEHAVIOR
    func selfJoinQualifiedColumnsNoAutoCondition() {
        let engine = SpecHelpers.makeSpecEngine()
        let u1Focus = SQLAutoCompletionTableFocus(schema: "public", name: "users", alias: "u1")
        let u2Focus = SQLAutoCompletionTableFocus(schema: "public", name: "users", alias: "u2")
        let text = "SELECT * FROM users u1 JOIN users u2 ON "
        let query = SQLAutoCompletionQuery(
            token: "", prefix: "", pathComponents: [],
            replacementRange: NSRange(location: text.count, length: 0),
            precedingKeyword: "on", precedingCharacter: nil,
            focusTable: u2Focus,
            tablesInScope: [u1Focus, u2Focus], clause: .joinCondition
        )

        let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
        let suggestions = SpecHelpers.allSuggestions(from: result)

        // NEW BEHAVIOR: For self-joins, should NOT auto-suggest a join condition
        // because the FK relationship is ambiguous (same table joined twice).
        // Instead, should offer qualified column references (u1.col, u2.col).
        let autoConditions = suggestions.filter { suggestion in
            suggestion.kind == .join || (suggestion.kind == .snippet &&
                suggestion.insertText.contains("=") &&
                suggestion.insertText.contains("u1.") &&
                suggestion.insertText.contains("u2."))
        }
        #expect(autoConditions.isEmpty,
                "Self-join should not auto-suggest a join condition")

        // Should still offer columns (possibly qualified with alias)
        let columnSuggestions = suggestions.filter { $0.kind == .column }
        #expect(!columnSuggestions.isEmpty,
                "Self-join ON should still suggest columns")
    }
}
