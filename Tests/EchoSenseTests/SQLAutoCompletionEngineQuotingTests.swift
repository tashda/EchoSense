import Foundation
import Testing
@testable import EchoSense

private func makeSampleStructure() -> EchoSenseDatabaseStructure {
    let orderIdColumn = EchoSenseColumnInfo(name: "id",
                                            dataType: "uuid",
                                            isPrimaryKey: true,
                                            isNullable: false)
    let orderSelectColumn = EchoSenseColumnInfo(name: "select",
                                                dataType: "text",
                                                isPrimaryKey: false,
                                                isNullable: true)
    let orderTotalColumn = EchoSenseColumnInfo(name: "order total",
                                               dataType: "numeric",
                                               isPrimaryKey: false,
                                               isNullable: true)

    let orderTable = EchoSenseSchemaObjectInfo(name: "Orders",
                                               schema: "public",
                                               type: .table,
                                               columns: [orderIdColumn, orderSelectColumn, orderTotalColumn])

    let fk = EchoSenseForeignKeyReference(constraintName: "fk_order_lines_order",
                                          referencedSchema: "public",
                                          referencedTable: "Orders",
                                          referencedColumn: "select")

    let orderLinesId = EchoSenseColumnInfo(name: "id",
                                           dataType: "uuid",
                                           isPrimaryKey: true,
                                           isNullable: false)
    let orderLinesOrderId = EchoSenseColumnInfo(name: "select",
                                                dataType: "uuid",
                                                isPrimaryKey: false,
                                                isNullable: false,
                                                foreignKey: fk)

    let orderLinesTable = EchoSenseSchemaObjectInfo(name: "OrderItems",
                                                    schema: "public",
                                                    type: .table,
                                                    columns: [orderLinesId, orderLinesOrderId])

    let schema = EchoSenseSchemaInfo(name: "public", objects: [orderTable, orderLinesTable])
    let database = EchoSenseDatabaseInfo(name: "appdb", schemas: [schema])
    return EchoSenseDatabaseStructure(databases: [database])
}

private func configuredEngine() -> SQLAutoCompletionEngine {
    let engine = SQLAutoCompletionEngine()
    let context = SQLEditorCompletionContext(databaseType: .postgresql,
                                             selectedDatabase: "appdb",
                                             defaultSchema: "public",
                                             structure: makeSampleStructure())
    engine.updateContext(context)
    return engine
}

@Test
func tableSuggestionUsesQuotedIdentifiers() async throws {
    let engine = configuredEngine()
    let text = "SELECT * FROM "
    let query = SQLAutoCompletionQuery(token: "",
                                       prefix: "",
                                       pathComponents: [],
                                       replacementRange: NSRange(location: text.count, length: 0),
                                       precedingKeyword: "from",
                                       precedingCharacter: nil,
                                       focusTable: nil,
                                       tablesInScope: [],
                                       clause: .from)

    let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
    let suggestions = result.sections.first?.suggestions ?? []
    let tableSuggestion = suggestions.first { $0.title == "Orders" }

    #expect(tableSuggestion != nil)
    #expect(tableSuggestion?.insertText == "\"Orders\"")
}

@Test
func columnSuggestionQuotesReservedNames() async throws {
    let engine = configuredEngine()
    let focus = SQLAutoCompletionTableFocus(schema: "public", name: "Orders", alias: "o")
    let text = "SELECT sel FROM \"Orders\" o"
    let caretLocation = (text as NSString).range(of: "sel").location + 3
    let query = SQLAutoCompletionQuery(token: "sel",
                                       prefix: "sel",
                                       pathComponents: [],
                                       replacementRange: NSRange(location: caretLocation, length: 0),
                                       precedingKeyword: "select",
                                       precedingCharacter: nil,
                                       focusTable: focus,
                                       tablesInScope: [focus],
                                       clause: .selectList)

    let result = engine.suggestions(for: query, text: text, caretLocation: caretLocation)
    let columnSuggestions = result.sections.first?.suggestions.filter { $0.kind == .column } ?? []
    let hasQuotedColumn = columnSuggestions.contains { $0.insertText == "\"select\"" }

    #expect(hasQuotedColumn)

}

@Test
func joinSuggestionQuotesColumnsAndTables() async throws {
    let engine = configuredEngine()
    let focus = SQLAutoCompletionTableFocus(schema: "public", name: "Orders", alias: "o")
    let text = "SELECT * FROM \"Orders\" o JOIN "
    let query = SQLAutoCompletionQuery(token: "",
                                       prefix: "",
                                       pathComponents: [],
                                       replacementRange: NSRange(location: text.count, length: 0),
                                       precedingKeyword: "join",
                                       precedingCharacter: nil,
                                       focusTable: nil,
                                       tablesInScope: [focus],
                                       clause: .joinTarget)

    let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
    let joinSuggestion = result.sections.first?.suggestions.first { $0.kind == .join }

    #expect(joinSuggestion != nil)
    if let insertText = joinSuggestion?.insertText {
        #expect(insertText.contains("o.\"select\""))
        #expect(insertText.contains("oi.\"select\""))
    }
}
