import Foundation
import Testing
@testable import EchoSense

// MARK: - SQLAutoCompletionKind

@Test
func allKindsHaveIconNames() {
    let kinds: [SQLAutoCompletionKind] = [.schema, .table, .view, .materializedView,
                                           .column, .function, .keyword, .snippet, .parameter, .join]
    for kind in kinds {
        #expect(!kind.iconSystemName.isEmpty, "Icon missing for \(kind)")
    }
}

// MARK: - SQLAutoCompletionSuggestion

@Test
func suggestionDisplayKindTitles() {
    let suggestion = SQLAutoCompletionSuggestion(title: "test", insertText: "test", kind: .table)
    #expect(suggestion.displayKindTitle == "Table")

    let colSuggestion = SQLAutoCompletionSuggestion(title: "id", insertText: "id", kind: .column)
    #expect(colSuggestion.displayKindTitle == "Column")
}

@Test
func suggestionWithSourcePreservesFields() {
    let suggestion = SQLAutoCompletionSuggestion(id: "test-id", title: "users",
                                                  insertText: "users", kind: .table,
                                                  priority: 1500, source: .engine)
    let historySuggestion = suggestion.withSource(.history)

    #expect(historySuggestion.id == "test-id")
    #expect(historySuggestion.title == "users")
    #expect(historySuggestion.kind == .table)
    #expect(historySuggestion.source == .history)
    #expect(historySuggestion.priority == 1500)
}

@Test
func suggestionWithSourceReturnsSelfWhenSame() {
    let suggestion = SQLAutoCompletionSuggestion(title: "test", insertText: "test",
                                                  kind: .table, source: .engine)
    let same = suggestion.withSource(.engine)

    #expect(same.id == suggestion.id)
}

@Test
func suggestionWithInsertTextPreservesFields() {
    let suggestion = SQLAutoCompletionSuggestion(id: "test-id", title: "users",
                                                  insertText: "users", kind: .table)
    let modified = suggestion.withInsertText("\"users\"")

    #expect(modified.id == "test-id")
    #expect(modified.title == "users")
    #expect(modified.insertText == "\"users\"")
}

@Test
func suggestionWithInsertTextReturnsSelfWhenSame() {
    let suggestion = SQLAutoCompletionSuggestion(title: "test", insertText: "test", kind: .table)
    let same = suggestion.withInsertText("test")

    #expect(same.id == suggestion.id)
}

// MARK: - Origin

@Test
func originWithServerContext() {
    let origin = SQLAutoCompletionSuggestion.Origin(database: "testdb", schema: "public", object: "users")
    #expect(origin.hasServerContext)
}

@Test
func originWithoutServerContext() {
    let origin = SQLAutoCompletionSuggestion.Origin()
    #expect(!origin.hasServerContext)
}

@Test
func originTrimsWhitespace() {
    let origin = SQLAutoCompletionSuggestion.Origin(database: " testdb ", schema: " public ")
    #expect(origin.database == "testdb")
    #expect(origin.schema == "public")
}

@Test
func suggestionWithEmptyOriginSetsNil() {
    let origin = SQLAutoCompletionSuggestion.Origin()
    let suggestion = SQLAutoCompletionSuggestion(title: "test", insertText: "test",
                                                  kind: .keyword, origin: origin)
    #expect(suggestion.origin == nil)
}

// MARK: - Display Object Path

@Test
func displayObjectPathForTable() {
    let origin = SQLAutoCompletionSuggestion.Origin(database: "testdb", schema: "public", object: "users")
    let suggestion = SQLAutoCompletionSuggestion(title: "users", insertText: "users",
                                                  kind: .table, origin: origin)
    #expect(suggestion.displayObjectPath == "public.users")
}

@Test
func displayObjectPathForColumn() {
    let origin = SQLAutoCompletionSuggestion.Origin(database: "testdb", schema: "public",
                                                     object: "users", column: "name")
    let suggestion = SQLAutoCompletionSuggestion(title: "name", insertText: "name",
                                                  kind: .column, origin: origin)
    #expect(suggestion.displayObjectPath == "users.name")
}

@Test
func serverDisplayName() {
    let origin = SQLAutoCompletionSuggestion.Origin(database: "testdb", schema: "public")
    let suggestion = SQLAutoCompletionSuggestion(title: "test", insertText: "test",
                                                  kind: .table, origin: origin)
    #expect(suggestion.serverDisplayName == "testdb")
}

@Test
func serverDisplayNameNilWithoutDatabase() {
    let suggestion = SQLAutoCompletionSuggestion(title: "test", insertText: "test", kind: .keyword)
    #expect(suggestion.serverDisplayName == nil)
}

// MARK: - SQLAutoCompletionQuery

@Test
func queryNormalizedPrefix() {
    let query = SQLAutoCompletionQuery(token: " test ", prefix: " test ", pathComponents: [],
                                        replacementRange: NSRange(location: 0, length: 5),
                                        precedingKeyword: nil, precedingCharacter: nil,
                                        focusTable: nil, tablesInScope: [], clause: .unknown)
    #expect(query.normalizedPrefix == "test")
}

@Test
func queryHasNonEmptyPrefix() {
    let query = SQLAutoCompletionQuery(token: "test", prefix: "test", pathComponents: [],
                                        replacementRange: NSRange(location: 0, length: 4),
                                        precedingKeyword: nil, precedingCharacter: nil,
                                        focusTable: nil, tablesInScope: [], clause: .unknown)
    #expect(query.hasNonEmptyPrefix)

    let emptyQuery = SQLAutoCompletionQuery(token: "", prefix: "", pathComponents: [],
                                             replacementRange: NSRange(location: 0, length: 0),
                                             precedingKeyword: nil, precedingCharacter: nil,
                                             focusTable: nil, tablesInScope: [], clause: .unknown)
    #expect(!emptyQuery.hasNonEmptyPrefix)
}

@Test
func queryDotCount() {
    let query = SQLAutoCompletionQuery(token: "schema.table.col", prefix: "col", pathComponents: ["schema", "table"],
                                        replacementRange: NSRange(location: 0, length: 17),
                                        precedingKeyword: nil, precedingCharacter: nil,
                                        focusTable: nil, tablesInScope: [], clause: .unknown)
    #expect(query.dotCount == 2)
}

// MARK: - SQLAutoCompletionTableFocus

@Test
func tableFocusMatches() {
    let focus = SQLAutoCompletionTableFocus(schema: "public", name: "users", alias: nil)
    #expect(focus.matches(schema: "public", name: "users"))
    #expect(focus.matches(schema: "PUBLIC", name: "USERS"))
    #expect(!focus.matches(schema: "public", name: "orders"))
}

@Test
func tableFocusMatchesWithoutSchema() {
    let focus = SQLAutoCompletionTableFocus(schema: nil, name: "users", alias: nil)
    #expect(focus.matches(schema: nil, name: "users"))
    #expect(focus.matches(schema: "public", name: "users"))
}

@Test
func tableFocusEquivalence() {
    let a = SQLAutoCompletionTableFocus(schema: "public", name: "users", alias: "u")
    let b = SQLAutoCompletionTableFocus(schema: "public", name: "users", alias: "u")
    let c = SQLAutoCompletionTableFocus(schema: "public", name: "users", alias: "usr")

    #expect(a.isEquivalent(to: b))
    #expect(!a.isEquivalent(to: c))
}

// MARK: - SQLCompletionAggressiveness

@Test
func aggressivenessAllCases() {
    let cases = SQLCompletionAggressiveness.allCases
    #expect(cases.count == 3)
    #expect(cases.contains(.focused))
    #expect(cases.contains(.balanced))
    #expect(cases.contains(.eager))
}

// MARK: - TableColumn

@Test
func emptyTableColumnsBecomesNil() {
    let suggestion = SQLAutoCompletionSuggestion(title: "test", insertText: "test",
                                                  kind: .table, tableColumns: [])
    #expect(suggestion.tableColumns == nil)
}

@Test
func nonEmptyTableColumnsPreserved() {
    let columns = [SQLAutoCompletionSuggestion.TableColumn(name: "id", dataType: "int",
                                                            isNullable: false, isPrimaryKey: true)]
    let suggestion = SQLAutoCompletionSuggestion(title: "test", insertText: "test",
                                                  kind: .table, tableColumns: columns)
    #expect(suggestion.tableColumns?.count == 1)
}

// MARK: - EchoSenseDatabaseType

@Test
func databaseTypeCases() {
    let types = EchoSenseDatabaseType.allCases
    #expect(types.count == 4)
    #expect(types.contains(.postgresql))
    #expect(types.contains(.mysql))
    #expect(types.contains(.sqlite))
    #expect(types.contains(.microsoftSQL))
}

// MARK: - SQLAutoCompletionSection

@Test
func sectionIdIsTitleBased() {
    let section = SQLAutoCompletionSection(title: "Tables", suggestions: [])
    #expect(section.id == "Tables")
}
