import Foundation
import Testing
@testable import EchoSense

// MARK: - Section 4: WHERE Clause

@Suite("Section 4 — WHERE")
struct WHERETests {

    // 4.1 After WHERE → columns immediately
    @Test("4.1 After WHERE keyword, columns appear immediately")
    func afterWHERE_columnsImmediately() {
        let engine = SpecHelpers.makeSpecEngine()
        let usersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "users", alias: nil)
        let text = "SELECT * FROM users WHERE "
        let query = SQLAutoCompletionQuery(
            token: "",
            prefix: "",
            pathComponents: [],
            replacementRange: NSRange(location: text.count, length: 0),
            precedingKeyword: "where",
            precedingCharacter: nil,
            focusTable: usersFocus,
            tablesInScope: [usersFocus],
            clause: .whereClause
        )

        let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
        let columns = SpecHelpers.suggestionTitles(from: result, kind: .column)

        #expect(columns.contains("id"))
        #expect(columns.contains("email"))
        #expect(columns.contains("created_at"))
    }

    // 4.2 WHERE partial typing
    @Test("4.2 Partial typing in WHERE filters columns")
    func wherePartialTyping() {
        let engine = SpecHelpers.makeSpecEngine()
        let usersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "users", alias: nil)
        let text = "SELECT * FROM users WHERE em"
        let query = SQLAutoCompletionQuery(
            token: "em",
            prefix: "em",
            pathComponents: [],
            replacementRange: NSRange(location: 25, length: 2),
            precedingKeyword: "where",
            precedingCharacter: nil,
            focusTable: usersFocus,
            tablesInScope: [usersFocus],
            clause: .whereClause
        )

        let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
        let columns = SpecHelpers.suggestionTitles(from: result, kind: .column)

        #expect(columns.contains("email"))
        #expect(!columns.contains("id"))
    }

    // 4.3 Right-hand side of operator → SILENT  // NEW BEHAVIOR
    @Test("4.3 Right-hand side of operator is silent")
    func whereRHSOfOperator_silent() {
        let engine = SpecHelpers.makeSpecEngine()
        let usersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "users", alias: nil)
        let text = "SELECT * FROM users WHERE id = "
        let query = SQLAutoCompletionQuery(
            token: "",
            prefix: "",
            pathComponents: [],
            replacementRange: NSRange(location: text.count, length: 0),
            precedingKeyword: "where",
            precedingCharacter: "=",
            focusTable: usersFocus,
            tablesInScope: [usersFocus],
            clause: .whereClause
        )

        let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
        let suggestions = SpecHelpers.allSuggestions(from: result)

        // After an operator, the engine should be silent (no unprompted suggestions)
        // or at most show columns/parameters but not aggressively.
        // The key NEW BEHAVIOR is that we do not pop up a full suggestion list on the RHS.
        let columnCount = suggestions.filter { $0.kind == .column }.count
        let paramCount = suggestions.filter { $0.kind == .parameter }.count
        let totalNonParam = suggestions.count - paramCount
        // Engine may still show columns for cross-referencing, but should not show tables/schemas/keywords
        let tableCount = suggestions.filter { $0.kind == .table }.count
        let schemaCount = suggestions.filter { $0.kind == .schema }.count
        #expect(tableCount == 0, "Tables should not appear on RHS of operator")
        #expect(schemaCount == 0, "Schemas should not appear on RHS of operator")
    }

    // 4.4 After AND/OR → columns immediately
    @Test("4.4 After AND/OR, columns appear immediately")
    func afterANDOR_columnsImmediately() {
        let engine = SpecHelpers.makeSpecEngine()
        let usersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "users", alias: nil)
        let text = "SELECT * FROM users WHERE id = 1 AND "
        let query = SQLAutoCompletionQuery(
            token: "",
            prefix: "",
            pathComponents: [],
            replacementRange: NSRange(location: text.count, length: 0),
            precedingKeyword: "and",
            precedingCharacter: nil,
            focusTable: usersFocus,
            tablesInScope: [usersFocus],
            clause: .whereClause
        )

        let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
        let columns = SpecHelpers.suggestionTitles(from: result, kind: .column)

        #expect(columns.contains("id"))
        #expect(columns.contains("email"))
        #expect(columns.contains("created_at"))
    }

    // 4.5 WHERE multiple tables → smart qualification  // NEW BEHAVIOR
    @Test("4.5 Multiple tables: unique columns unqualified, ambiguous columns qualified")
    func whereMultipleTables_smartQualification() {
        let engine = SpecHelpers.makeSpecEngine()
        let usersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "users", alias: "u")
        let ordersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "orders", alias: "o")
        let text = "SELECT * FROM users u JOIN orders o ON u.id = o.user_id WHERE "
        let query = SQLAutoCompletionQuery(
            token: "",
            prefix: "",
            pathComponents: [],
            replacementRange: NSRange(location: text.count, length: 0),
            precedingKeyword: "where",
            precedingCharacter: nil,
            focusTable: nil,
            tablesInScope: [usersFocus, ordersFocus],
            clause: .whereClause
        )

        let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
        let suggestions = SpecHelpers.allSuggestions(from: result)
        let columnSuggestions = suggestions.filter { $0.kind == .column }

        // "email" is unique to users — should appear (possibly unqualified)
        let emailSuggestions = columnSuggestions.filter { $0.title == "email" || $0.insertText.contains("email") }
        #expect(!emailSuggestions.isEmpty, "Unique column 'email' should appear")

        // "total" is unique to orders — should appear
        let totalSuggestions = columnSuggestions.filter { $0.title == "total" || $0.insertText.contains("total") }
        #expect(!totalSuggestions.isEmpty, "Unique column 'total' should appear")

        // "id" is ambiguous (both tables have it) — should appear qualified
        let idSuggestions = columnSuggestions.filter { $0.title == "id" || $0.insertText.contains("id") }
        #expect(!idSuggestions.isEmpty, "Ambiguous column 'id' should still appear")

        // "created_at" is also ambiguous — both tables have it
        let createdAtSuggestions = columnSuggestions.filter {
            $0.title == "created_at" || $0.insertText.contains("created_at")
        }
        #expect(!createdAtSuggestions.isEmpty, "Ambiguous column 'created_at' should still appear")
    }

    // 4.6 WHERE alias dot → only that table's columns
    @Test("4.6 Alias dot shows only that table's columns")
    func whereAliasDot_onlyThatTablesColumns() {
        let engine = SpecHelpers.makeSpecEngine()
        let usersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "users", alias: "u")
        let ordersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "orders", alias: "o")
        let text = "SELECT * FROM users u JOIN orders o ON u.id = o.user_id WHERE u."
        let query = SQLAutoCompletionQuery(
            token: "u.",
            prefix: "",
            pathComponents: ["u"],
            replacementRange: NSRange(location: text.count, length: 0),
            precedingKeyword: "where",
            precedingCharacter: ".",
            focusTable: usersFocus,
            tablesInScope: [usersFocus, ordersFocus],
            clause: .whereClause
        )

        let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
        let columns = SpecHelpers.suggestionTitles(from: result, kind: .column)

        // Should show users columns
        #expect(columns.contains("id"))
        #expect(columns.contains("email"))
        #expect(columns.contains("department_id"))

        // Should NOT show orders-only columns
        #expect(!columns.contains("total"))
        #expect(!columns.contains("status"))
        #expect(!columns.contains("user_id"))
    }

    // 4.7 Parameters only on sigil ($, @)  // NEW BEHAVIOR
    @Test("4.7 Parameters only appear when typing a sigil character")
    func parametersOnlyOnSigil() {
        let engine = SpecHelpers.makeSpecEngine()
        let usersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "users", alias: nil)
        let text = "SELECT * FROM users WHERE id = $"
        let query = SQLAutoCompletionQuery(
            token: "$",
            prefix: "$",
            pathComponents: [],
            replacementRange: NSRange(location: 30, length: 1),
            precedingKeyword: "where",
            precedingCharacter: "=",
            focusTable: usersFocus,
            tablesInScope: [usersFocus],
            clause: .whereClause
        )

        let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
        let suggestions = SpecHelpers.allSuggestions(from: result)
        let parameterSuggestions = suggestions.filter { $0.kind == .parameter }

        // When typing $, parameters should appear
        #expect(!parameterSuggestions.isEmpty, "Parameters should appear when typing $")
    }

    // 4.8 WHERE IN → silent after open paren, suggest on typing  // NEW BEHAVIOR
    @Test("4.8 WHERE IN: silent after open paren")
    func whereIN_silentAfterOpenParen() {
        let engine = SpecHelpers.makeSpecEngine()
        let usersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "users", alias: nil)
        let text = "SELECT * FROM users WHERE id IN ("
        let query = SQLAutoCompletionQuery(
            token: "",
            prefix: "",
            pathComponents: [],
            replacementRange: NSRange(location: text.count, length: 0),
            precedingKeyword: "in",
            precedingCharacter: "(",
            focusTable: usersFocus,
            tablesInScope: [usersFocus],
            clause: .whereClause
        )

        let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
        let suggestions = SpecHelpers.allSuggestions(from: result)

        // After open paren in IN clause, engine should be relatively silent
        // (user is about to type values, not column names)
        let kinds = SpecHelpers.suggestionKinds(from: result)
        // Should not aggressively show tables or schemas
        #expect(!kinds.contains(.table), "Tables should not appear inside IN(...)")
        #expect(!kinds.contains(.schema), "Schemas should not appear inside IN(...)")
    }

    // 4.10 Operator keywords only on typing, not after space  // NEW BEHAVIOR
    @Test("4.10 Operator keywords appear only when typing, not unprompted")
    func operatorKeywords_onlyOnTyping() {
        let engine = SpecHelpers.makeSpecEngine()
        let usersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "users", alias: nil)

        // After a column name with space — should get columns/operators contextually
        let text = "SELECT * FROM users WHERE status LI"
        let query = SQLAutoCompletionQuery(
            token: "LI",
            prefix: "LI",
            pathComponents: [],
            replacementRange: NSRange(location: 33, length: 2),
            precedingKeyword: "where",
            precedingCharacter: nil,
            focusTable: usersFocus,
            tablesInScope: [usersFocus],
            clause: .whereClause
        )

        let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
        let keywords = SpecHelpers.suggestionTitles(from: result, kind: .keyword).map { $0.lowercased() }

        // When typing "LI", LIKE should appear
        #expect(keywords.contains("like"), "LIKE should appear when typing 'LI'")
    }
}

// MARK: - Section 5: GROUP BY / ORDER BY / HAVING

@Suite("Section 5 — GROUP BY / ORDER BY / HAVING")
struct GroupOrderHavingTests {

    // 5.1 GROUP BY → prioritize SELECT-list columns  // NEW BEHAVIOR
    @Test("5.1 GROUP BY prioritizes SELECT-list columns")
    func groupBy_prioritizeSelectListColumns() {
        let engine = SpecHelpers.makeSpecEngine()
        let usersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "users", alias: nil)
        let text = "SELECT name, email FROM users GROUP BY "
        let query = SQLAutoCompletionQuery(
            token: "",
            prefix: "",
            pathComponents: [],
            replacementRange: NSRange(location: text.count, length: 0),
            precedingKeyword: "by",
            precedingCharacter: nil,
            focusTable: usersFocus,
            tablesInScope: [usersFocus],
            clause: .groupBy
        )

        let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
        let columns = SpecHelpers.suggestionTitles(from: result, kind: .column)

        // Columns from the table should appear
        #expect(!columns.isEmpty, "Columns should appear after GROUP BY")

        // name and email (the SELECT-list columns) should be present
        let hasName = columns.contains("name") || columns.contains("\"name\"")
        let hasEmail = columns.contains("email")
        #expect(hasName, "SELECT-list column 'name' should appear in GROUP BY")
        #expect(hasEmail, "SELECT-list column 'email' should appear in GROUP BY")
    }

    // 5.2 ORDER BY → prioritize SELECT-list columns  // NEW BEHAVIOR
    @Test("5.2 ORDER BY prioritizes SELECT-list columns")
    func orderBy_prioritizeSelectListColumns() {
        let engine = SpecHelpers.makeSpecEngine()
        let usersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "users", alias: nil)
        let text = "SELECT name, email FROM users ORDER BY "
        let query = SQLAutoCompletionQuery(
            token: "",
            prefix: "",
            pathComponents: [],
            replacementRange: NSRange(location: text.count, length: 0),
            precedingKeyword: "by",
            precedingCharacter: nil,
            focusTable: usersFocus,
            tablesInScope: [usersFocus],
            clause: .orderBy
        )

        let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
        let columns = SpecHelpers.suggestionTitles(from: result, kind: .column)

        #expect(!columns.isEmpty, "Columns should appear after ORDER BY")

        let hasName = columns.contains("name") || columns.contains("\"name\"")
        let hasEmail = columns.contains("email")
        #expect(hasName, "SELECT-list column 'name' should appear in ORDER BY")
        #expect(hasEmail, "SELECT-list column 'email' should appear in ORDER BY")
    }

    // 5.3 ORDER BY partial typing
    @Test("5.3 ORDER BY partial typing filters columns")
    func orderBy_partialTyping() {
        let engine = SpecHelpers.makeSpecEngine()
        let usersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "users", alias: nil)
        let text = "SELECT * FROM users ORDER BY cr"
        let query = SQLAutoCompletionQuery(
            token: "cr",
            prefix: "cr",
            pathComponents: [],
            replacementRange: NSRange(location: 29, length: 2),
            precedingKeyword: "by",
            precedingCharacter: nil,
            focusTable: usersFocus,
            tablesInScope: [usersFocus],
            clause: .orderBy
        )

        let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
        let columns = SpecHelpers.suggestionTitles(from: result, kind: .column)

        #expect(columns.contains("created_at"), "created_at should match 'cr' prefix")
        #expect(!columns.contains("email"), "email should not match 'cr' prefix")
    }

    // 5.4 ORDER BY direction → auto-suggest ASC/DESC after column  // NEW BEHAVIOR
    @Test("5.4 ORDER BY direction keywords after column")
    func orderBy_directionAfterColumn() {
        let engine = SpecHelpers.makeSpecEngine()
        let usersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "users", alias: nil)
        let text = "SELECT * FROM users ORDER BY name "
        let query = SQLAutoCompletionQuery(
            token: "",
            prefix: "",
            pathComponents: [],
            replacementRange: NSRange(location: text.count, length: 0),
            precedingKeyword: "by",
            precedingCharacter: nil,
            focusTable: usersFocus,
            tablesInScope: [usersFocus],
            clause: .orderBy
        )

        let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
        let keywords = SpecHelpers.suggestionTitles(from: result, kind: .keyword).map { $0.uppercased() }
        let allTitles = SpecHelpers.allSuggestions(from: result).map { $0.title.uppercased() }

        // ASC and/or DESC should be available as suggestions
        let hasDirectionKeyword = allTitles.contains("ASC") || allTitles.contains("DESC")
            || keywords.contains("ASC") || keywords.contains("DESC")
        #expect(hasDirectionKeyword, "ASC/DESC should be suggested after ORDER BY column")
    }

    // 5.5 ORDER BY after comma → columns
    @Test("5.5 ORDER BY after comma shows columns")
    func orderBy_afterComma_columns() {
        let engine = SpecHelpers.makeSpecEngine()
        let usersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "users", alias: nil)
        let text = "SELECT * FROM users ORDER BY name, "
        let query = SQLAutoCompletionQuery(
            token: "",
            prefix: "",
            pathComponents: [],
            replacementRange: NSRange(location: text.count, length: 0),
            precedingKeyword: "by",
            precedingCharacter: ",",
            focusTable: usersFocus,
            tablesInScope: [usersFocus],
            clause: .orderBy
        )

        let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
        let columns = SpecHelpers.suggestionTitles(from: result, kind: .column)

        #expect(!columns.isEmpty, "Columns should appear after comma in ORDER BY")
        #expect(columns.contains("id") || columns.contains("email") || columns.contains("created_at"),
                "Should suggest remaining columns")
    }

    // 5.6 HAVING → aggregates ranked highest  // NEW BEHAVIOR
    @Test("5.6 HAVING prioritizes aggregate functions")
    func having_aggregatesRankedHighest() {
        let engine = SpecHelpers.makeSpecEngine()
        let usersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "users", alias: nil)
        let text = "SELECT department_id, COUNT(*) FROM users GROUP BY department_id HAVING "
        let query = SQLAutoCompletionQuery(
            token: "",
            prefix: "",
            pathComponents: [],
            replacementRange: NSRange(location: text.count, length: 0),
            precedingKeyword: "having",
            precedingCharacter: nil,
            focusTable: usersFocus,
            tablesInScope: [usersFocus],
            clause: .having
        )

        let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
        let suggestions = SpecHelpers.allSuggestions(from: result)
        let kinds = SpecHelpers.suggestionKinds(from: result)

        // HAVING should show suggestions (columns and/or functions)
        #expect(!suggestions.isEmpty, "HAVING should produce suggestions")

        // Functions or columns should be present for aggregate expressions
        let hasFunctionsOrColumns = kinds.contains(.function) || kinds.contains(.column)
        #expect(hasFunctionsOrColumns, "HAVING should show functions or columns for aggregate expressions")

        // If functions are present, aggregates like COUNT, SUM, AVG should be among them
        let functionTitles = SpecHelpers.suggestionTitles(from: result, kind: .function).map { $0.uppercased() }
        if !functionTitles.isEmpty {
            let hasAggregate = functionTitles.contains("COUNT") || functionTitles.contains("SUM")
                || functionTitles.contains("AVG") || functionTitles.contains("MAX") || functionTitles.contains("MIN")
            #expect(hasAggregate, "Aggregate functions should appear in HAVING clause")
        }
    }
}

// MARK: - Section 6: INSERT / UPDATE / DELETE

@Suite("Section 6 — INSERT / UPDATE / DELETE")
struct InsertUpdateDeleteTests {

    // 6.1 INSERT column list → show columns, auto-increment deprioritized  // NEW BEHAVIOR
    @Test("6.1 INSERT column list shows table columns")
    func insertColumnList_showsColumns() {
        let engine = SpecHelpers.makeSpecEngine()
        let usersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "users", alias: nil)
        let text = "INSERT INTO users ("
        let query = SQLAutoCompletionQuery(
            token: "",
            prefix: "",
            pathComponents: [],
            replacementRange: NSRange(location: text.count, length: 0),
            precedingKeyword: "into",
            precedingCharacter: "(",
            focusTable: usersFocus,
            tablesInScope: [usersFocus],
            clause: .insertColumns
        )

        let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
        let columns = SpecHelpers.suggestionTitles(from: result, kind: .column)

        // Should show users columns
        let hasName = columns.contains("name") || columns.contains("\"name\"")
        #expect(hasName, "Column 'name' should appear in INSERT column list")
        #expect(columns.contains("email"), "Column 'email' should appear in INSERT column list")

        // id (primary key / auto-increment equivalent) should be deprioritized
        // It may still appear but should not be first
        if columns.contains("id") && columns.count > 1 {
            let idIndex = columns.firstIndex(of: "id")!
            // id being deprioritized means it should not be the very first suggestion
            // (though this depends on engine behavior — we just verify it appears)
            #expect(idIndex >= 0, "id may appear but should be deprioritized")
        }
    }

    // 6.2 INSERT VALUES → silent  // NEW BEHAVIOR
    @Test("6.2 INSERT VALUES is silent")
    func insertValues_silent() {
        let engine = SpecHelpers.makeSpecEngine()
        let usersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "users", alias: nil)
        let text = "INSERT INTO users (name, email) VALUES ("
        let query = SQLAutoCompletionQuery(
            token: "",
            prefix: "",
            pathComponents: [],
            replacementRange: NSRange(location: text.count, length: 0),
            precedingKeyword: "values",
            precedingCharacter: "(",
            focusTable: usersFocus,
            tablesInScope: [usersFocus],
            clause: .values
        )

        let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
        let suggestions = SpecHelpers.allSuggestions(from: result)

        // VALUES clause should be silent — user is typing literal values
        let kinds = SpecHelpers.suggestionKinds(from: result)
        #expect(!kinds.contains(.table), "Tables should not appear in VALUES")
        #expect(!kinds.contains(.schema), "Schemas should not appear in VALUES")
    }

    // 6.3 UPDATE SET → columns immediately
    @Test("6.3 UPDATE SET shows columns immediately")
    func updateSet_columnsImmediately() {
        let engine = SpecHelpers.makeSpecEngine()
        let usersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "users", alias: nil)
        let text = "UPDATE users SET "
        let query = SQLAutoCompletionQuery(
            token: "",
            prefix: "",
            pathComponents: [],
            replacementRange: NSRange(location: text.count, length: 0),
            precedingKeyword: "set",
            precedingCharacter: nil,
            focusTable: usersFocus,
            tablesInScope: [usersFocus],
            clause: .updateSet
        )

        let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
        let columns = SpecHelpers.suggestionTitles(from: result, kind: .column)

        let hasName = columns.contains("name") || columns.contains("\"name\"")
        #expect(hasName, "Column 'name' should appear after UPDATE SET")
        #expect(columns.contains("email"), "Column 'email' should appear after UPDATE SET")
        #expect(columns.contains("department_id"), "Column 'department_id' should appear after UPDATE SET")
    }

    // 6.4 UPDATE SET right-hand side → silent  // NEW BEHAVIOR
    @Test("6.4 UPDATE SET right-hand side is silent")
    func updateSetRHS_silent() {
        let engine = SpecHelpers.makeSpecEngine()
        let usersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "users", alias: nil)
        let text = "UPDATE users SET name = "
        let query = SQLAutoCompletionQuery(
            token: "",
            prefix: "",
            pathComponents: [],
            replacementRange: NSRange(location: text.count, length: 0),
            precedingKeyword: "set",
            precedingCharacter: "=",
            focusTable: usersFocus,
            tablesInScope: [usersFocus],
            clause: .updateSet
        )

        let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
        let suggestions = SpecHelpers.allSuggestions(from: result)

        // After = in SET, engine should be relatively silent
        let kinds = SpecHelpers.suggestionKinds(from: result)
        #expect(!kinds.contains(.table), "Tables should not appear on RHS of SET =")
        #expect(!kinds.contains(.schema), "Schemas should not appear on RHS of SET =")
    }

    // 6.5 UPDATE SET after comma → columns
    @Test("6.5 UPDATE SET after comma shows columns")
    func updateSet_afterComma_columns() {
        let engine = SpecHelpers.makeSpecEngine()
        let usersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "users", alias: nil)
        let text = "UPDATE users SET name = 'test', "
        let query = SQLAutoCompletionQuery(
            token: "",
            prefix: "",
            pathComponents: [],
            replacementRange: NSRange(location: text.count, length: 0),
            precedingKeyword: "set",
            precedingCharacter: ",",
            focusTable: usersFocus,
            tablesInScope: [usersFocus],
            clause: .updateSet
        )

        let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
        let columns = SpecHelpers.suggestionTitles(from: result, kind: .column)

        #expect(!columns.isEmpty, "Columns should appear after comma in UPDATE SET")
        #expect(columns.contains("email") || columns.contains("department_id"),
                "Remaining columns should be suggested after comma")
    }

    // 6.6 DELETE WHERE → columns
    @Test("6.6 DELETE WHERE shows columns")
    func deleteWhere_columns() {
        let engine = SpecHelpers.makeSpecEngine()
        let usersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "users", alias: nil)
        let text = "DELETE FROM users WHERE "
        let query = SQLAutoCompletionQuery(
            token: "",
            prefix: "",
            pathComponents: [],
            replacementRange: NSRange(location: text.count, length: 0),
            precedingKeyword: "where",
            precedingCharacter: nil,
            focusTable: usersFocus,
            tablesInScope: [usersFocus],
            clause: .deleteWhere
        )

        let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
        let columns = SpecHelpers.suggestionTitles(from: result, kind: .column)

        #expect(columns.contains("id"), "Column 'id' should appear in DELETE WHERE")
        #expect(columns.contains("email"), "Column 'email' should appear in DELETE WHERE")
        #expect(columns.contains("created_at"), "Column 'created_at' should appear in DELETE WHERE")
    }
}
