import Foundation
import Testing
@testable import EchoSense

/// Column suggestions carry the schema's nullability and keys, so an editor can describe a
/// column (Echo's EchoSense details footer) without another metadata lookup.
@Suite("Column facts on suggestions")
struct ColumnFactsTests {
    private func columnSuggestions(text: String, table: String) -> [SQLAutoCompletionSuggestion] {
        let engine = SpecHelpers.makeSpecEngine()
        let focus = SQLAutoCompletionTableFocus(schema: "public", name: table, alias: nil)
        let query = SQLAutoCompletionQuery(token: "", prefix: "", pathComponents: [],
                                           replacementRange: NSRange(location: 7, length: 0),
                                           precedingKeyword: "select", precedingCharacter: nil,
                                           focusTable: focus, tablesInScope: [focus], clause: .selectList)
        let result = engine.suggestions(for: query, text: text, caretLocation: 7)
        return SpecHelpers.allSuggestions(from: result).filter { $0.kind == .column }
    }

    @Test func primaryKeyIsNotNullAndMarked() throws {
        let id = try #require(columnSuggestions(text: "SELECT  FROM users", table: "users").first { $0.title == "id" })
        let facts = try #require(id.columnFacts)
        #expect(facts.isPrimaryKey)
        #expect(!facts.isNullable)
        #expect(facts.foreignKeyTarget == nil)
    }

    @Test func foreignKeyNamesItsTarget() throws {
        let userID = try #require(columnSuggestions(text: "SELECT  FROM orders", table: "orders").first { $0.title == "user_id" })
        let facts = try #require(userID.columnFacts)
        #expect(!facts.isPrimaryKey)
        #expect(!facts.isNullable)
        #expect(facts.foreignKeyTarget == "public.users.id")
    }

    @Test func nullableColumnHasNoKeys() throws {
        let email = try #require(columnSuggestions(text: "SELECT  FROM users", table: "users").first { $0.title == "email" })
        let facts = try #require(email.columnFacts)
        #expect(facts.isNullable)
        #expect(!facts.isPrimaryKey)
    }

    @Test func factsSurviveCoding() throws {
        let facts = SQLAutoCompletionSuggestion.ColumnFacts(isNullable: false, isPrimaryKey: true, foreignKeyTarget: "dbo.t.id")
        let suggestion = SQLAutoCompletionSuggestion(title: "id", insertText: "id", kind: .column, columnFacts: facts)
        let decoded = try JSONDecoder().decode(SQLAutoCompletionSuggestion.self, from: JSONEncoder().encode(suggestion))
        #expect(decoded.columnFacts == facts)
    }
}
