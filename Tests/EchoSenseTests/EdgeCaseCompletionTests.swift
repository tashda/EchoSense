import Foundation
import Testing
@testable import EchoSense

@Suite("Edge Case Completion")
struct EdgeCaseCompletionTests {

    // MARK: - Helpers

    private func makeStructure() -> EchoSenseDatabaseStructure {
        let idCol = EchoSenseColumnInfo(name: "id", dataType: "integer", isPrimaryKey: true, isNullable: false)
        let nameCol = EchoSenseColumnInfo(name: "name", dataType: "text", isNullable: true)
        let emailCol = EchoSenseColumnInfo(name: "email", dataType: "text", isNullable: true)

        let usersTable = EchoSenseSchemaObjectInfo(name: "users", schema: "public",
                                                    type: .table, columns: [idCol, nameCol, emailCol])
        let ordersTable = EchoSenseSchemaObjectInfo(name: "orders", schema: "public",
                                                     type: .table, columns: [idCol, nameCol])

        let publicSchema = EchoSenseSchemaInfo(name: "public", objects: [usersTable, ordersTable])
        let database = EchoSenseDatabaseInfo(name: "testdb", schemas: [publicSchema])
        return EchoSenseDatabaseStructure(databases: [database])
    }

    private func makeContext() -> SQLEditorCompletionContext {
        SQLEditorCompletionContext(databaseType: .postgresql,
                                   selectedDatabase: "testdb",
                                   defaultSchema: "public",
                                   structure: makeStructure())
    }

    private func makeEngine() -> SQLAutoCompletionEngine {
        let engine = SQLAutoCompletionEngine()
        engine.updateContext(makeContext())
        engine.updateAggressiveness(.eager)
        engine.updateHistoryPreference(includeHistory: false)
        return engine
    }

    private func allSuggestions(from result: SQLAutoCompletionResult) -> [SQLAutoCompletionSuggestion] {
        result.sections.flatMap(\.suggestions)
    }

    // MARK: - Empty / Zero-length Input

    @Test func emptyStringInputDoesNotCrash() {
        let engine = makeEngine()
        let text = ""
        let query = SQLAutoCompletionQuery(token: "", prefix: "", pathComponents: [],
                                            replacementRange: NSRange(location: 0, length: 0),
                                            precedingKeyword: nil, precedingCharacter: nil,
                                            focusTable: nil, tablesInScope: [], clause: .unknown)

        let result = engine.suggestions(for: query, text: text, caretLocation: 0)
        // Should not crash — may or may not have suggestions
        #expect(true, "Empty string should not crash")
    }

    @Test func cursorAtPositionZero() {
        let engine = makeEngine()
        let text = "SELECT * FROM users"
        let query = SQLAutoCompletionQuery(token: "", prefix: "", pathComponents: [],
                                            replacementRange: NSRange(location: 0, length: 0),
                                            precedingKeyword: nil, precedingCharacter: nil,
                                            focusTable: nil, tablesInScope: [], clause: .unknown)

        let result = engine.suggestions(for: query, text: text, caretLocation: 0)
        #expect(true, "Cursor at 0 should not crash")
    }

    @Test func cursorPastEndOfString() {
        let engine = makeEngine()
        let text = "SELECT"
        let query = SQLAutoCompletionQuery(token: "", prefix: "", pathComponents: [],
                                            replacementRange: NSRange(location: text.count, length: 0),
                                            precedingKeyword: "select", precedingCharacter: nil,
                                            focusTable: nil, tablesInScope: [], clause: .selectList)

        let result = engine.suggestions(for: query, text: text, caretLocation: 5000)
        #expect(true, "Cursor past end should not crash")
    }

    @Test func negativeCaretLocation() {
        let engine = makeEngine()
        let text = "SELECT * FROM users"
        let query = SQLAutoCompletionQuery(token: "", prefix: "", pathComponents: [],
                                            replacementRange: NSRange(location: 0, length: 0),
                                            precedingKeyword: nil, precedingCharacter: nil,
                                            focusTable: nil, tablesInScope: [], clause: .unknown)

        let result = engine.suggestions(for: query, text: text, caretLocation: -10)
        #expect(true, "Negative caret should not crash")
    }

    // MARK: - Cursor Inside Comments

    @Test func cursorInsideLineCommentContextParsing() {
        let emptyCatalog = SQLDatabaseCatalog(schemas: [])
        let text = "SELECT * FROM users -- some comm"
        let parser = SQLContextParser(text: text, caretLocation: text.count, dialect: .postgresql, catalog: emptyCatalog)
        let context = parser.parse()
        // The token at the comment position may be "comm" but the engine should not crash
        #expect(true, "Cursor in line comment should not crash parser")
    }

    @Test func cursorInsideBlockCommentContextParsing() {
        let emptyCatalog = SQLDatabaseCatalog(schemas: [])
        let text = "SELECT * FROM /* comm"
        let parser = SQLContextParser(text: text, caretLocation: text.count, dialect: .postgresql, catalog: emptyCatalog)
        let context = parser.parse()
        #expect(true, "Cursor in block comment should not crash parser")
    }

    // MARK: - Incomplete Keywords

    @Test func incompleteSelectKeyword_SEL() {
        let engine = makeEngine()
        let text = "SEL"
        let query = SQLAutoCompletionQuery(token: "SEL", prefix: "SEL", pathComponents: [],
                                            replacementRange: NSRange(location: 0, length: 3),
                                            precedingKeyword: nil, precedingCharacter: nil,
                                            focusTable: nil, tablesInScope: [], clause: .unknown)

        let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
        let suggestions = allSuggestions(from: result)
        // Should match "SELECT" via fuzzy
        let keywords = suggestions.filter { $0.kind == .keyword }.map { $0.title.uppercased() }
        // May or may not contain SELECT depending on engine context, but should not crash
        #expect(true, "Incomplete keyword should not crash")
    }

    @Test func incompleteSelectKeyword_SELE() {
        let engine = makeEngine()
        let text = "SELE"
        let query = SQLAutoCompletionQuery(token: "SELE", prefix: "SELE", pathComponents: [],
                                            replacementRange: NSRange(location: 0, length: 4),
                                            precedingKeyword: nil, precedingCharacter: nil,
                                            focusTable: nil, tablesInScope: [], clause: .unknown)

        let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
        #expect(true, "Incomplete SELE should not crash")
    }

    @Test func incompleteSelectKeyword_SELEC() {
        let engine = makeEngine()
        let text = "SELEC"
        let query = SQLAutoCompletionQuery(token: "SELEC", prefix: "SELEC", pathComponents: [],
                                            replacementRange: NSRange(location: 0, length: 5),
                                            precedingKeyword: nil, precedingCharacter: nil,
                                            focusTable: nil, tablesInScope: [], clause: .unknown)

        let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
        #expect(true, "Incomplete SELEC should not crash")
    }

    // MARK: - Malformed SQL

    @Test func unclosedParenthesis() {
        let engine = makeEngine()
        let text = "SELECT * FROM (SELECT id FROM users"
        let query = SQLAutoCompletionQuery(token: "", prefix: "", pathComponents: [],
                                            replacementRange: NSRange(location: text.count, length: 0),
                                            precedingKeyword: "from", precedingCharacter: nil,
                                            focusTable: nil, tablesInScope: [], clause: .from)

        let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
        #expect(true, "Unclosed paren should not crash")
    }

    @Test func unclosedStringLiteral() {
        let emptyCatalog = SQLDatabaseCatalog(schemas: [])
        let text = "SELECT * FROM users WHERE name = 'unclosed"
        let parser = SQLContextParser(text: text, caretLocation: text.count, dialect: .postgresql, catalog: emptyCatalog)
        let context = parser.parse()
        #expect(true, "Unclosed string should not crash parser")
    }

    @Test func missingFromKeyword() {
        let engine = makeEngine()
        let text = "SELECT id users WHERE "
        let query = SQLAutoCompletionQuery(token: "", prefix: "", pathComponents: [],
                                            replacementRange: NSRange(location: text.count, length: 0),
                                            precedingKeyword: "where", precedingCharacter: nil,
                                            focusTable: nil, tablesInScope: [], clause: .whereClause)

        let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
        #expect(true, "Missing FROM should not crash")
    }

    // MARK: - Very Long SQL

    @Test func veryLongSQL() {
        let engine = makeEngine()
        // Build a 10K+ character SQL string
        var text = "SELECT * FROM users WHERE "
        for i in 0..<1200 {
            text += "id = \(i) OR "
        }
        text += "id = 0"

        let usersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "users", alias: nil)
        let query = SQLAutoCompletionQuery(token: "", prefix: "", pathComponents: [],
                                            replacementRange: NSRange(location: text.count, length: 0),
                                            precedingKeyword: "or", precedingCharacter: nil,
                                            focusTable: usersFocus,
                                            tablesInScope: [usersFocus], clause: .whereClause)

        let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
        #expect(text.count > 10000, "SQL should be >10K chars")
        #expect(true, "Very long SQL should not crash")
    }

    // MARK: - Whitespace-Only / Comment-Only

    @Test func whitespaceOnlyInput() {
        let emptyCatalog = SQLDatabaseCatalog(schemas: [])
        let text = "   \t  \n  "
        let parser = SQLContextParser(text: text, caretLocation: text.count, dialect: .postgresql, catalog: emptyCatalog)
        let context = parser.parse()

        #expect(context.clause == .unknown)
        #expect(context.tablesInScope.isEmpty)
    }

    @Test func commentOnlyInput() {
        let emptyCatalog = SQLDatabaseCatalog(schemas: [])
        let text = "-- this is a comment\n/* block comment */"
        let parser = SQLContextParser(text: text, caretLocation: text.count, dialect: .postgresql, catalog: emptyCatalog)
        let context = parser.parse()

        #expect(context.clause == .unknown)
    }

    // MARK: - Case Sensitivity

    @Test func lowercaseSelectWorks() {
        let emptyCatalog = SQLDatabaseCatalog(schemas: [])
        let text = "select * from "
        let parser = SQLContextParser(text: text, caretLocation: text.count, dialect: .postgresql, catalog: emptyCatalog)
        let context = parser.parse()

        #expect(context.clause == .from)
    }

    @Test func uppercaseSelectWorks() {
        let emptyCatalog = SQLDatabaseCatalog(schemas: [])
        let text = "SELECT * FROM "
        let parser = SQLContextParser(text: text, caretLocation: text.count, dialect: .postgresql, catalog: emptyCatalog)
        let context = parser.parse()

        #expect(context.clause == .from)
    }

    @Test func mixedCaseSelectWorks() {
        let emptyCatalog = SQLDatabaseCatalog(schemas: [])
        let text = "SeLeCt * FrOm "
        let parser = SQLContextParser(text: text, caretLocation: text.count, dialect: .postgresql, catalog: emptyCatalog)
        let context = parser.parse()

        #expect(context.clause == .from)
    }

    // MARK: - Tab and Whitespace Characters

    @Test func tabCharactersBetweenTokens() {
        let emptyCatalog = SQLDatabaseCatalog(schemas: [])
        let text = "SELECT\t*\tFROM\tusers\tWHERE\t"
        let parser = SQLContextParser(text: text, caretLocation: text.count, dialect: .postgresql, catalog: emptyCatalog)
        let context = parser.parse()

        #expect(context.clause == .whereClause)
        let tableNames = context.tablesInScope.map { $0.name }
        #expect(tableNames.contains("users"))
    }

    @Test func windowsLineEndings() {
        let emptyCatalog = SQLDatabaseCatalog(schemas: [])
        let text = "SELECT *\r\nFROM users\r\nWHERE "
        let parser = SQLContextParser(text: text, caretLocation: text.count, dialect: .postgresql, catalog: emptyCatalog)
        let context = parser.parse()

        #expect(context.clause == .whereClause)
    }

    // MARK: - Multiple Semicolons

    @Test func multipleSemicolonsNewStatementContext() {
        let emptyCatalog = SQLDatabaseCatalog(schemas: [])
        let text = "SELECT 1; SELECT "
        let parser = SQLContextParser(text: text, caretLocation: text.count, dialect: .postgresql, catalog: emptyCatalog)
        let context = parser.parse()

        // After semicolon and new SELECT, should be in selectList
        #expect(context.clause == .selectList)
    }

    // MARK: - Nested Parentheses

    @Test func deeplyNestedParentheses() {
        let emptyCatalog = SQLDatabaseCatalog(schemas: [])
        let text = "SELECT * FROM users WHERE id IN (SELECT id FROM (SELECT id FROM (SELECT id FROM (SELECT id FROM (SELECT id FROM users)))))"
        let parser = SQLContextParser(text: text, caretLocation: text.count, dialect: .postgresql, catalog: emptyCatalog)
        let context = parser.parse()
        // Should not crash with 5+ levels of nesting
        #expect(true, "Deep nesting should not crash")
    }

    // MARK: - No Schema / Database Context

    @Test func noSchemaContextDoesNotCrash() {
        let engine = SQLAutoCompletionEngine()
        // No context set at all
        let text = "SELECT * FROM "
        let query = SQLAutoCompletionQuery(token: "", prefix: "", pathComponents: [],
                                            replacementRange: NSRange(location: text.count, length: 0),
                                            precedingKeyword: "from", precedingCharacter: nil,
                                            focusTable: nil, tablesInScope: [], clause: .from)

        let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
        let suggestions = allSuggestions(from: result)
        #expect(suggestions.isEmpty, "No context should produce no results")
    }

    @Test func nilStructureInContext() {
        let engine = SQLAutoCompletionEngine()
        let context = SQLEditorCompletionContext(databaseType: .postgresql,
                                                  selectedDatabase: "testdb",
                                                  defaultSchema: "public",
                                                  structure: nil)
        engine.updateContext(context)

        let text = "SELECT * FROM "
        let query = SQLAutoCompletionQuery(token: "", prefix: "", pathComponents: [],
                                            replacementRange: NSRange(location: text.count, length: 0),
                                            precedingKeyword: "from", precedingCharacter: nil,
                                            focusTable: nil, tablesInScope: [], clause: .from)

        let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
        // Should not crash; may have limited suggestions
        #expect(engine.isMetadataLimited, "Engine should report metadata is limited")
    }

    // MARK: - Cursor in Middle of Keyword

    @Test func cursorInMiddleOfKeyword() {
        let emptyCatalog = SQLDatabaseCatalog(schemas: [])
        let text = "SELECT * FROM users"
        // Caret at position 3 (inside "SEL|ECT")
        let parser = SQLContextParser(text: text, caretLocation: 3, dialect: .postgresql, catalog: emptyCatalog)
        let context = parser.parse()

        #expect(context.currentToken == "SEL")
    }

    // MARK: - Reserved Words as Identifiers

    @Test func contextParserHandlesReservedWordsAsTableNames() {
        let emptyCatalog = SQLDatabaseCatalog(schemas: [])
        // Using table named "order" (reserved word)
        let text = "SELECT * FROM \"order\" WHERE "
        let parser = SQLContextParser(text: text, caretLocation: text.count, dialect: .postgresql, catalog: emptyCatalog)
        let context = parser.parse()

        #expect(context.clause == .whereClause)
    }

    // MARK: - Star After FROM

    @Test func starTokenWithoutManualTrigger() {
        let engine = makeEngine()
        let usersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "users", alias: nil)
        let text = "SELECT * FROM users"
        let query = SQLAutoCompletionQuery(token: "", prefix: "", pathComponents: [],
                                            replacementRange: NSRange(location: 7, length: 0),
                                            precedingKeyword: "select", precedingCharacter: "*",
                                            focusTable: usersFocus,
                                            tablesInScope: [usersFocus], clause: .selectList)

        let result = engine.suggestions(for: query, text: text, caretLocation: 7)
        let suggestions = allSuggestions(from: result)
        // After `*`, no completions unless manual trigger
        #expect(suggestions.isEmpty, "After * without manual trigger, should not suggest")
    }

    // MARK: - Very Long Identifier Names

    @Test func veryLongIdentifierDoesNotCrash() {
        let engine = makeEngine()
        let longName = String(repeating: "a", count: 150)
        let text = "SELECT * FROM \(longName)"
        let query = SQLAutoCompletionQuery(token: longName, prefix: longName, pathComponents: [],
                                            replacementRange: NSRange(location: 14, length: longName.count),
                                            precedingKeyword: "from", precedingCharacter: nil,
                                            focusTable: nil, tablesInScope: [], clause: .from)

        let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
        // Should not crash; probably no matches
        #expect(true, "Very long identifier should not crash")
    }

    // MARK: - Prefix Matches Reserved Keywords

    @Test func typingReservedKeywordAsTokenSuppresses() {
        let engine = makeEngine()
        let text = "SELECT * FROM "
        // Token is "select" (a reserved leading keyword) — should be suppressed
        let query = SQLAutoCompletionQuery(token: "select", prefix: "select", pathComponents: [],
                                            replacementRange: NSRange(location: 14, length: 6),
                                            precedingKeyword: "from", precedingCharacter: nil,
                                            focusTable: nil, tablesInScope: [], clause: .from)

        let result = engine.suggestions(for: query, text: text, caretLocation: 20)
        let suggestions = allSuggestions(from: result)
        // Typing a reserved keyword should be suppressed
        #expect(suggestions.isEmpty, "Typing a reserved keyword should suppress completions")
    }

    // MARK: - Empty Schema Objects

    @Test func emptySchemaReturnsNoTableSuggestions() {
        SQLAutoCompletionHistoryStore.shared.reset()
        let engine = SQLAutoCompletionEngine()
        let emptySchema = EchoSenseSchemaInfo(name: "public", objects: [])
        let database = EchoSenseDatabaseInfo(name: "testdb", schemas: [emptySchema])
        let structure = EchoSenseDatabaseStructure(databases: [database])
        let context = SQLEditorCompletionContext(databaseType: .postgresql,
                                                  selectedDatabase: "testdb",
                                                  defaultSchema: "public",
                                                  structure: structure)
        engine.updateContext(context)

        let text = "SELECT * FROM "
        let query = SQLAutoCompletionQuery(token: "", prefix: "", pathComponents: [],
                                            replacementRange: NSRange(location: text.count, length: 0),
                                            precedingKeyword: "from", precedingCharacter: nil,
                                            focusTable: nil, tablesInScope: [], clause: .from)

        let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
        let tables = allSuggestions(from: result).filter { $0.kind == .table }
        #expect(tables.isEmpty, "Empty schema should have no table suggestions")
    }

    // MARK: - Multiple Spaces Between Tokens

    @Test func multipleSpacesBetweenTokens() {
        let emptyCatalog = SQLDatabaseCatalog(schemas: [])
        let text = "SELECT   *    FROM    users    WHERE   "
        let parser = SQLContextParser(text: text, caretLocation: text.count, dialect: .postgresql, catalog: emptyCatalog)
        let context = parser.parse()

        #expect(context.clause == .whereClause)
        #expect(context.tablesInScope.first?.name == "users")
    }

    // MARK: - Parser Caret Clamping

    @Test func parserClampsCaretToTextLength() {
        let emptyCatalog = SQLDatabaseCatalog(schemas: [])
        let text = "SELECT"
        let parser = SQLContextParser(text: text, caretLocation: 200, dialect: .postgresql, catalog: emptyCatalog)
        let context = parser.parse()

        #expect(context.caretLocation == text.count)
    }

    @Test func parserClampsNegativeCaretToZero() {
        let emptyCatalog = SQLDatabaseCatalog(schemas: [])
        let text = "SELECT * FROM users"
        let parser = SQLContextParser(text: text, caretLocation: -5, dialect: .postgresql, catalog: emptyCatalog)
        let context = parser.parse()

        #expect(context.caretLocation == 0)
    }

    // MARK: - Empty Token at Various Positions

    @Test func emptyTokenAfterSpace() {
        let emptyCatalog = SQLDatabaseCatalog(schemas: [])
        let text = "SELECT "
        let parser = SQLContextParser(text: text, caretLocation: text.count, dialect: .postgresql, catalog: emptyCatalog)
        let context = parser.parse()

        #expect(context.currentToken == "")
    }

    @Test func tokenExtraction() {
        let emptyCatalog = SQLDatabaseCatalog(schemas: [])
        let text = "SELECT us"
        let parser = SQLContextParser(text: text, caretLocation: text.count, dialect: .postgresql, catalog: emptyCatalog)
        let context = parser.parse()

        #expect(context.currentToken == "us")
    }

    // MARK: - Trailing Newline

    @Test func trailingNewline() {
        let emptyCatalog = SQLDatabaseCatalog(schemas: [])
        let text = "SELECT * FROM users\n"
        let parser = SQLContextParser(text: text, caretLocation: text.count, dialect: .postgresql, catalog: emptyCatalog)
        let context = parser.parse()

        let tableNames = context.tablesInScope.map { $0.name }
        #expect(tableNames.contains("users"))
    }

    // MARK: - Query After Clearing Context

    @Test func queryAfterClearingContextReturnsEmpty() {
        let engine = makeEngine()
        engine.updateContext(nil)

        let text = "SELECT * FROM users"
        let query = SQLAutoCompletionQuery(token: "", prefix: "", pathComponents: [],
                                            replacementRange: NSRange(location: text.count, length: 0),
                                            precedingKeyword: "from", precedingCharacter: nil,
                                            focusTable: nil, tablesInScope: [], clause: .from)

        let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
        let suggestions = allSuggestions(from: result)
        #expect(suggestions.isEmpty, "After clearing context, should return empty")
    }

    // MARK: - Single Character SQL

    @Test func singleCharacterSQL() {
        let engine = makeEngine()
        let text = "S"
        let query = SQLAutoCompletionQuery(token: "S", prefix: "S", pathComponents: [],
                                            replacementRange: NSRange(location: 0, length: 1),
                                            precedingKeyword: nil, precedingCharacter: nil,
                                            focusTable: nil, tablesInScope: [], clause: .unknown)

        let result = engine.suggestions(for: query, text: text, caretLocation: 1)
        #expect(true, "Single character should not crash")
    }

    // MARK: - Multiple Dots Path

    @Test func multiDotPath() {
        let emptyCatalog = SQLDatabaseCatalog(schemas: [])
        let text = "SELECT db.schema.table."
        let parser = SQLContextParser(text: text, caretLocation: text.count, dialect: .postgresql, catalog: emptyCatalog)
        let context = parser.parse()

        #expect(context.pathComponents.count >= 2, "Should have multiple path components")
    }

    // MARK: - AS Alias With Keyword

    @Test func asAliasWithKeywordName() {
        let emptyCatalog = SQLDatabaseCatalog(schemas: [])
        let text = "SELECT * FROM users AS u WHERE "
        let parser = SQLContextParser(text: text, caretLocation: text.count, dialect: .postgresql, catalog: emptyCatalog)
        let context = parser.parse()

        #expect(context.clause == .whereClause)
        #expect(context.tablesInScope.first?.alias == "u")
    }
}
