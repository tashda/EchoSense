import XCTest
@testable import EchoAutocomplete

final class AliasDetectionTests: XCTestCase {
    private struct MockMetadata: SQLMetadataProvider {
        let catalog: SQLDatabaseCatalog?
        func catalog(for database: String?) -> SQLDatabaseCatalog? { catalog }
    }

    private func makeCatalog() -> SQLDatabaseCatalog {
        let columns = [SQLColumn(name: "id", dataType: "int"),
                       SQLColumn(name: "name", dataType: "text"),
                       SQLColumn(name: "created_at", dataType: "timestamp")]
        let table = SQLObject(name: "employees", type: .table, columns: columns)
        let schema = SQLSchema(name: "public", objects: [table])
        return SQLDatabaseCatalog(schemas: [schema])
    }

    func testAliasExtractionWithAsKeyword() {
        let request = SQLCompletionRequest(text: "SELECT e. FROM employees AS e",
                                           caretLocation: "SELECT e.".count,
                                           dialect: .postgresql,
                                           selectedDatabase: nil,
                                           defaultSchema: "public",
                                           metadata: MockMetadata(catalog: makeCatalog()),
                                           options: .init(enableAliasShortcuts: true))
        let engine = SQLCompletionEngine()
        let result = engine.completions(for: request)
        XCTAssertTrue(result.suggestions.contains(where: { $0.insertText == "e.id" }))
    }

    func testAliasExtractionWithoutAsKeyword() {
        let request = SQLCompletionRequest(text: "SELECT emp. FROM employees emp",
                                           caretLocation: "SELECT emp.".count,
                                           dialect: .postgresql,
                                           selectedDatabase: nil,
                                           defaultSchema: "public",
                                           metadata: MockMetadata(catalog: makeCatalog()),
                                           options: .init(enableAliasShortcuts: true))
        let engine = SQLCompletionEngine()
        let result = engine.completions(for: request)
        XCTAssertTrue(result.suggestions.contains(where: { $0.insertText == "emp.name" }))
    }

    func testFallbackWithoutAlias() {
        let request = SQLCompletionRequest(text: "SELECT employees. FROM employees",
                                           caretLocation: "SELECT employees.".count,
                                           dialect: .postgresql,
                                           selectedDatabase: nil,
                                           defaultSchema: "public",
                                           metadata: MockMetadata(catalog: makeCatalog()),
                                           options: .init(enableAliasShortcuts: false))
        let engine = SQLCompletionEngine()
        let result = engine.completions(for: request)
        XCTAssertTrue(result.suggestions.contains(where: { $0.insertText == "name" }))
    }
}
