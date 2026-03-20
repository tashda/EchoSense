import Foundation
import Testing
@testable import EchoSense

// MARK: - SELECT Clause Behavioral Tests (per AUTOCOMPLETE_SPEC.md)

@Suite("SELECT Clause Completions")
struct SpecBehavioralTests_SELECT {

    // MARK: - 1.1 Empty SELECT, no tables in scope → NONE

    @Test("1.1 Empty SELECT with no tables returns no suggestions")
    func emptySelectNoTables() {
        let engine = SpecHelpers.makeSpecEngine()
        let text = "SELECT "
        let query = SQLAutoCompletionQuery(token: "", prefix: "", pathComponents: [],
                                            replacementRange: NSRange(location: 7, length: 0),
                                            precedingKeyword: "select", precedingCharacter: nil,
                                            focusTable: nil, tablesInScope: [], clause: .selectList)

        let result = engine.suggestions(for: query, text: text, caretLocation: 7)
        let suggestions = SpecHelpers.allSuggestions(from: result)

        #expect(suggestions.isEmpty, "No tables in scope → no column/function suggestions")
    }

    // MARK: - 1.2 SELECT with tables in scope → columns + functions

    @Test("1.2 SELECT with tables in scope returns columns and functions, columns ranked first, PK boosted")
    func selectWithTablesInScope() {
        let engine = SpecHelpers.makeSpecEngine()
        let usersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "users", alias: nil)
        let text = "SELECT  FROM users"
        let query = SQLAutoCompletionQuery(token: "", prefix: "", pathComponents: [],
                                            replacementRange: NSRange(location: 7, length: 0),
                                            precedingKeyword: "select", precedingCharacter: nil,
                                            focusTable: usersFocus,
                                            tablesInScope: [usersFocus], clause: .selectList)

        let result = engine.suggestions(for: query, text: text, caretLocation: 7)
        let suggestions = SpecHelpers.allSuggestions(from: result)
        let kinds = SpecHelpers.suggestionKinds(from: result)

        // Should contain columns
        #expect(kinds.contains(.column), "Should suggest columns when tables are in scope")

        // Should contain functions
        #expect(kinds.contains(.function), "Should suggest functions in SELECT list")

        let columns = suggestions.filter { $0.kind == .column }
        let functions = suggestions.filter { $0.kind == .function }

        // Columns should appear before functions (lower index = higher rank)
        if let lastColumnIndex = suggestions.lastIndex(where: { $0.kind == .column }),
           let firstFunctionIndex = suggestions.firstIndex(where: { $0.kind == .function }) {
            #expect(lastColumnIndex < firstFunctionIndex,
                    "Columns should be ranked before functions in SELECT list")
        }

        // PK column (id) should be first among columns — NEW BEHAVIOR
        let columnTitles = columns.map(\.title)
        #expect(columnTitles.first == "id",
                "Primary key column should be boosted to top of column list")

        // Users table columns should all be present
        #expect(columnTitles.contains("id"))
        #expect(columnTitles.contains("email"))
        #expect(columnTitles.contains("created_at"))
        #expect(columnTitles.contains("department_id"))

        // Functions should include built-in SQL functions
        let functionTitles = functions.map(\.title)
        #expect(!functionTitles.isEmpty, "Should include built-in functions")
    }

    // MARK: - 1.3 SELECT partial typing → matching columns first, matching functions last

    @Test("1.3 Partial typing filters to matching columns first, then functions")
    func selectPartialTyping() {
        let engine = SpecHelpers.makeSpecEngine()
        let usersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "users", alias: nil)
        // User types "na" — should match "name" column and e.g. "NTH_VALUE" function (if fuzzy)
        let text = "SELECT na FROM users"
        let query = SQLAutoCompletionQuery(token: "na", prefix: "na", pathComponents: [],
                                            replacementRange: NSRange(location: 7, length: 2),
                                            precedingKeyword: "select", precedingCharacter: nil,
                                            focusTable: usersFocus,
                                            tablesInScope: [usersFocus], clause: .selectList)

        let result = engine.suggestions(for: query, text: text, caretLocation: 9)
        let suggestions = SpecHelpers.allSuggestions(from: result)

        // Should include "name" column
        let columnTitles = SpecHelpers.suggestionTitles(from: result, kind: .column)
        #expect(columnTitles.contains(where: { $0.lowercased().contains("name") }),
                "Typing 'na' should match 'name' column")

        // Matching columns should appear before any matching functions
        if let lastMatchingColumn = suggestions.lastIndex(where: { $0.kind == .column }),
           let firstMatchingFunction = suggestions.firstIndex(where: { $0.kind == .function }) {
            #expect(lastMatchingColumn < firstMatchingFunction,
                    "Matching columns should rank before matching functions")
        }
    }

    // MARK: - 1.4 SELECT after comma → deduplication (already-selected columns excluded)

    @Test("1.4 After comma, already-selected columns are excluded")
    func selectAfterCommaDeduplication() {
        // NEW BEHAVIOR — engine should parse selected columns from text and exclude them
        let engine = SpecHelpers.makeSpecEngine()
        let usersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "users", alias: nil)
        let text = "SELECT id,  FROM users"
        let query = SQLAutoCompletionQuery(token: "", prefix: "", pathComponents: [],
                                            replacementRange: NSRange(location: 11, length: 0),
                                            precedingKeyword: nil, precedingCharacter: ",",
                                            focusTable: usersFocus,
                                            tablesInScope: [usersFocus], clause: .selectList)

        let result = engine.suggestions(for: query, text: text, caretLocation: 11)
        let columnTitles = SpecHelpers.suggestionTitles(from: result, kind: .column)

        // Should still show columns
        #expect(!columnTitles.isEmpty, "Should offer remaining columns after comma")

        // "id" is already selected — should be excluded
        #expect(!columnTitles.contains("id"),
                "Already-selected column 'id' should be excluded from suggestions")

        // Other columns should still be present
        #expect(columnTitles.contains("email") || columnTitles.contains("created_at"),
                "Non-selected columns should still appear")
    }

    // MARK: - 1.5 SELECT after comma with partial

    @Test("1.5 After comma with partial typing, filters and deduplicates")
    func selectAfterCommaWithPartial() {
        // NEW BEHAVIOR
        let engine = SpecHelpers.makeSpecEngine()
        let usersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "users", alias: nil)
        let text = "SELECT id, em FROM users"
        let query = SQLAutoCompletionQuery(token: "em", prefix: "em", pathComponents: [],
                                            replacementRange: NSRange(location: 11, length: 2),
                                            precedingKeyword: nil, precedingCharacter: nil,
                                            focusTable: usersFocus,
                                            tablesInScope: [usersFocus], clause: .selectList)

        let result = engine.suggestions(for: query, text: text, caretLocation: 13)
        let columnTitles = SpecHelpers.suggestionTitles(from: result, kind: .column)

        // Should match "email"
        #expect(columnTitles.contains("email"), "Typing 'em' should match 'email' column")

        // "id" is already selected — should not appear even if it matched
        #expect(!columnTitles.contains("id"),
                "Already-selected column 'id' should be excluded even with partial typing")
    }

    // MARK: - 1.6 Multiple tables → smart qualification

    @Test("1.6 Multiple tables: unique columns unqualified, ambiguous columns qualified")
    func multipleTablesSmartQualification() {
        // NEW BEHAVIOR — both users and orders have "id" and "created_at"
        let engine = SpecHelpers.makeSpecEngine()
        let usersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "users", alias: "u")
        let ordersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "orders", alias: "o")
        let text = "SELECT  FROM users u JOIN orders o ON u.id = o.user_id"
        let query = SQLAutoCompletionQuery(token: "", prefix: "", pathComponents: [],
                                            replacementRange: NSRange(location: 7, length: 0),
                                            precedingKeyword: "select", precedingCharacter: nil,
                                            focusTable: usersFocus,
                                            tablesInScope: [usersFocus, ordersFocus], clause: .selectList)

        let result = engine.suggestions(for: query, text: text, caretLocation: 7)
        let columns = SpecHelpers.allSuggestions(from: result).filter { $0.kind == .column }
        let insertTexts = columns.map(\.insertText)

        // "email" is unique to users → should appear unqualified
        #expect(insertTexts.contains("email"),
                "Unique column 'email' should be unqualified")

        // "id" exists in both users and orders → should appear qualified
        #expect(insertTexts.contains("u.id") || insertTexts.contains("o.id"),
                "Ambiguous column 'id' should be qualified with alias")

        // "created_at" exists in both tables → should appear qualified
        #expect(insertTexts.contains("u.created_at") || insertTexts.contains("o.created_at"),
                "Ambiguous column 'created_at' should be qualified with alias")

        // Unique columns from orders (total, status) should appear unqualified
        #expect(insertTexts.contains("total") || insertTexts.contains("status"),
                "Unique columns from orders should appear unqualified")
    }

    // MARK: - 1.7 Alias dot → only that table's columns, insert text is column name only

    @Test("1.7 Alias dot shows only that table's columns with unqualified insert text")
    func aliasDotColumns() {
        let engine = SpecHelpers.makeSpecEngine()
        let usersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "users", alias: "u")
        let ordersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "orders", alias: "o")
        let text = "SELECT u. FROM users u JOIN orders o ON u.id = o.user_id"
        let query = SQLAutoCompletionQuery(token: "u.", prefix: "", pathComponents: ["u"],
                                            replacementRange: NSRange(location: 9, length: 0),
                                            precedingKeyword: "select", precedingCharacter: nil,
                                            focusTable: usersFocus,
                                            tablesInScope: [usersFocus, ordersFocus], clause: .selectList)

        let result = engine.suggestions(for: query, text: text, caretLocation: 9)
        let columns = SpecHelpers.allSuggestions(from: result).filter { $0.kind == .column }

        // Should only show users columns
        let columnTitles = columns.map(\.title)
        #expect(columnTitles.contains("id"))
        #expect(columnTitles.contains("email"))
        #expect(columnTitles.contains("created_at"))
        #expect(columnTitles.contains("department_id"))

        // Should NOT show orders columns
        #expect(!columnTitles.contains("total"), "Should not show orders columns after u.")
        #expect(!columnTitles.contains("status"), "Should not show orders columns after u.")
        #expect(!columnTitles.contains("user_id"), "Should not show orders columns after u.")

        // Insert text should be column name only (not u.column)
        for column in columns {
            #expect(!column.insertText.contains("."),
                    "Insert text after alias dot should be column name only, got: \(column.insertText)")
        }
    }

    // MARK: - 1.8 Alias dot partial typing

    @Test("1.8 Alias dot with partial typing filters to matching columns")
    func aliasDotPartialTyping() {
        let engine = SpecHelpers.makeSpecEngine()
        let usersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "users", alias: "u")
        let ordersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "orders", alias: "o")
        let text = "SELECT u.em FROM users u JOIN orders o ON u.id = o.user_id"
        let query = SQLAutoCompletionQuery(token: "u.em", prefix: "em", pathComponents: ["u"],
                                            replacementRange: NSRange(location: 9, length: 2),
                                            precedingKeyword: "select", precedingCharacter: nil,
                                            focusTable: usersFocus,
                                            tablesInScope: [usersFocus, ordersFocus], clause: .selectList)

        let result = engine.suggestions(for: query, text: text, caretLocation: 11)
        let columns = SpecHelpers.allSuggestions(from: result).filter { $0.kind == .column }

        let columnTitles = columns.map(\.title)
        #expect(columnTitles.contains("email"), "Typing 'u.em' should match 'email'")
        #expect(!columnTitles.contains("id"), "'id' should not match prefix 'em'")

        // Insert text should still be column name only
        for column in columns {
            #expect(!column.insertText.contains("."),
                    "Insert text should be column name only after alias dot")
        }
    }

    // MARK: - 1.9 Table name dot (no alias)

    @Test("1.9 Table name dot shows that table's columns")
    func tableNameDot() {
        let engine = SpecHelpers.makeSpecEngine()
        let usersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "users", alias: nil)
        let text = "SELECT users. FROM users"
        let query = SQLAutoCompletionQuery(token: "users.", prefix: "", pathComponents: ["users"],
                                            replacementRange: NSRange(location: 13, length: 0),
                                            precedingKeyword: "select", precedingCharacter: nil,
                                            focusTable: usersFocus,
                                            tablesInScope: [usersFocus], clause: .selectList)

        let result = engine.suggestions(for: query, text: text, caretLocation: 13)
        let columns = SpecHelpers.allSuggestions(from: result).filter { $0.kind == .column }

        let columnTitles = columns.map(\.title)
        #expect(columnTitles.contains("id"))
        #expect(columnTitles.contains("email"))
        #expect(!columns.isEmpty, "Should show columns after table_name.")

        // Insert text should be column name only
        for column in columns {
            #expect(!column.insertText.contains("."),
                    "Insert text after table dot should be column name only")
        }
    }

    // MARK: - 1.10 SELECT DISTINCT

    @Test("1.10 SELECT DISTINCT shows same completions as SELECT")
    func selectDistinct() {
        let engine = SpecHelpers.makeSpecEngine()
        let usersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "users", alias: nil)
        let text = "SELECT DISTINCT  FROM users"
        let query = SQLAutoCompletionQuery(token: "", prefix: "", pathComponents: [],
                                            replacementRange: NSRange(location: 16, length: 0),
                                            precedingKeyword: "distinct", precedingCharacter: nil,
                                            focusTable: usersFocus,
                                            tablesInScope: [usersFocus], clause: .selectList)

        let result = engine.suggestions(for: query, text: text, caretLocation: 16)
        let suggestions = SpecHelpers.allSuggestions(from: result)
        let kinds = SpecHelpers.suggestionKinds(from: result)

        #expect(kinds.contains(.column),
                "SELECT DISTINCT should show column suggestions just like SELECT")

        let columnTitles = SpecHelpers.suggestionTitles(from: result, kind: .column)
        #expect(columnTitles.contains("id"))
        #expect(columnTitles.contains("email"))
    }

    // MARK: - 1.11 CASE WHEN

    @Test("1.11 CASE WHEN shows columns and functions")
    func caseWhen() {
        // NEW BEHAVIOR — CASE WHEN is a column context inside SELECT
        let engine = SpecHelpers.makeSpecEngine()
        let usersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "users", alias: nil)
        let text = "SELECT CASE WHEN  FROM users"
        let query = SQLAutoCompletionQuery(token: "", prefix: "", pathComponents: [],
                                            replacementRange: NSRange(location: 17, length: 0),
                                            precedingKeyword: "when", precedingCharacter: nil,
                                            focusTable: usersFocus,
                                            tablesInScope: [usersFocus], clause: .selectList)

        let result = engine.suggestions(for: query, text: text, caretLocation: 17)
        let kinds = SpecHelpers.suggestionKinds(from: result)

        #expect(kinds.contains(.column),
                "CASE WHEN should suggest columns for the condition")

        let columnTitles = SpecHelpers.suggestionTitles(from: result, kind: .column)
        #expect(columnTitles.contains("id") || columnTitles.contains("email"),
                "Should suggest table columns in CASE WHEN condition")
    }

    // MARK: - 1.12 CASE THEN

    @Test("1.12 CASE THEN shows columns and functions")
    func caseThen() {
        // NEW BEHAVIOR
        let engine = SpecHelpers.makeSpecEngine()
        let usersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "users", alias: nil)
        let text = "SELECT CASE WHEN status = 'active' THEN  FROM users"
        let query = SQLAutoCompletionQuery(token: "", prefix: "", pathComponents: [],
                                            replacementRange: NSRange(location: 40, length: 0),
                                            precedingKeyword: "then", precedingCharacter: nil,
                                            focusTable: usersFocus,
                                            tablesInScope: [usersFocus], clause: .selectList)

        let result = engine.suggestions(for: query, text: text, caretLocation: 40)
        let kinds = SpecHelpers.suggestionKinds(from: result)

        #expect(kinds.contains(.column),
                "CASE THEN should suggest columns for the result expression")
    }

    // MARK: - 1.13 CASE ELSE

    @Test("1.13 CASE ELSE shows columns and functions")
    func caseElse() {
        // NEW BEHAVIOR
        let engine = SpecHelpers.makeSpecEngine()
        let usersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "users", alias: nil)
        let text = "SELECT CASE WHEN status = 'active' THEN name ELSE  FROM users"
        let query = SQLAutoCompletionQuery(token: "", prefix: "", pathComponents: [],
                                            replacementRange: NSRange(location: 51, length: 0),
                                            precedingKeyword: "else", precedingCharacter: nil,
                                            focusTable: usersFocus,
                                            tablesInScope: [usersFocus], clause: .selectList)

        let result = engine.suggestions(for: query, text: text, caretLocation: 51)
        let kinds = SpecHelpers.suggestionKinds(from: result)

        #expect(kinds.contains(.column),
                "CASE ELSE should suggest columns for the fallback expression")
    }

    // MARK: - 1.14 Partial typing ambiguous column → both qualified

    @Test("1.14 Partial typing an ambiguous column name shows both qualified versions")
    func partialTypingAmbiguousColumn() {
        // NEW BEHAVIOR — "id" exists in both users and orders
        let engine = SpecHelpers.makeSpecEngine()
        let usersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "users", alias: "u")
        let ordersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "orders", alias: "o")
        let text = "SELECT id FROM users u JOIN orders o ON u.id = o.user_id"
        let query = SQLAutoCompletionQuery(token: "id", prefix: "id", pathComponents: [],
                                            replacementRange: NSRange(location: 7, length: 2),
                                            precedingKeyword: "select", precedingCharacter: nil,
                                            focusTable: usersFocus,
                                            tablesInScope: [usersFocus, ordersFocus], clause: .selectList)

        let result = engine.suggestions(for: query, text: text, caretLocation: 9)
        let columns = SpecHelpers.allSuggestions(from: result).filter { $0.kind == .column }
        let insertTexts = columns.map(\.insertText)

        // Both qualified versions should appear
        #expect(insertTexts.contains("u.id"),
                "Should offer u.id for ambiguous column")
        #expect(insertTexts.contains("o.id"),
                "Should offer o.id for ambiguous column")

        // Should NOT offer unqualified "id" since it's ambiguous
        let unqualifiedIds = columns.filter { $0.insertText == "id" }
        #expect(unqualifiedIds.isEmpty,
                "Ambiguous column should not appear unqualified")
    }

    // MARK: - 1.15 Window function columns don't count as selected for deduplication

    @Test("1.15 Columns inside window functions are not treated as selected for deduplication")
    func windowFunctionColumnsNotDeduped() {
        // NEW BEHAVIOR — ROW_NUMBER() OVER (ORDER BY created_at) uses created_at,
        // but created_at should still be available for selection
        let engine = SpecHelpers.makeSpecEngine()
        let usersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "users", alias: nil)
        let text = "SELECT ROW_NUMBER() OVER (ORDER BY created_at),  FROM users"
        let query = SQLAutoCompletionQuery(token: "", prefix: "", pathComponents: [],
                                            replacementRange: NSRange(location: 49, length: 0),
                                            precedingKeyword: nil, precedingCharacter: ",",
                                            focusTable: usersFocus,
                                            tablesInScope: [usersFocus], clause: .selectList)

        let result = engine.suggestions(for: query, text: text, caretLocation: 49)
        let columnTitles = SpecHelpers.suggestionTitles(from: result, kind: .column)

        // created_at is used inside a window function, not as a select-list item
        #expect(columnTitles.contains("created_at"),
                "Columns inside window functions should not count as selected for deduplication")

        // Other columns should be present
        #expect(columnTitles.contains("id") || columnTitles.contains("email"),
                "Regular columns should still be suggested")
    }
}
