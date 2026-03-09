import Testing
@testable import EchoSense

@Test
func postgresSnippetsExist() {
    let snippets = SQLSnippetCatalog.snippets(for: .postgresql)
    #expect(snippets.count >= 3)

    let ids = snippets.map(\.id)
    #expect(ids.contains("pg.case"))
    #expect(ids.contains("pg.coalesce"))
    #expect(ids.contains("pg.json_extract"))
}

@Test
func mysqlSnippetsExist() {
    let snippets = SQLSnippetCatalog.snippets(for: .mysql)
    #expect(snippets.count >= 2)

    let ids = snippets.map(\.id)
    #expect(ids.contains("mysql.case"))
    #expect(ids.contains("mysql.json_extract"))
}

@Test
func sqliteSnippetsExist() {
    let snippets = SQLSnippetCatalog.snippets(for: .sqlite)
    #expect(snippets.count >= 2)

    let ids = snippets.map(\.id)
    #expect(ids.contains("sqlite.case"))
    #expect(ids.contains("sqlite.datetime"))
}

@Test
func sqlServerSnippetsExist() {
    let snippets = SQLSnippetCatalog.snippets(for: .microsoftSQL)
    #expect(snippets.count >= 2)

    let ids = snippets.map(\.id)
    #expect(ids.contains("mssql.case"))
    #expect(ids.contains("mssql.output"))
}

@Test
func allSnippetsHaveNonEmptyFields() {
    for dialect: SQLDialect in [.postgresql, .mysql, .sqlite, .microsoftSQL] {
        let snippets = SQLSnippetCatalog.snippets(for: dialect)
        for snippet in snippets {
            #expect(!snippet.id.isEmpty, "Snippet ID empty for \(dialect)")
            #expect(!snippet.title.isEmpty, "Snippet title empty for \(snippet.id)")
            #expect(!snippet.insertText.isEmpty, "Snippet insertText empty for \(snippet.id)")
            #expect(snippet.priority > 0, "Snippet priority <= 0 for \(snippet.id)")
        }
    }
}

@Test
func caseSnippetContainsPlaceholders() {
    let snippets = SQLSnippetCatalog.snippets(for: .postgresql)
    let caseSnippet = snippets.first { $0.id == "pg.case" }

    #expect(caseSnippet != nil)
    #expect(caseSnippet?.insertText.contains("<#condition#>") == true)
    #expect(caseSnippet?.insertText.contains("<#result#>") == true)
    #expect(caseSnippet?.insertText.contains("<#fallback#>") == true)
}

@Test
func snippetIdsAreUnique() {
    for dialect: SQLDialect in [.postgresql, .mysql, .sqlite, .microsoftSQL] {
        let snippets = SQLSnippetCatalog.snippets(for: dialect)
        let ids = snippets.map(\.id)
        let uniqueIds = Set(ids)
        #expect(ids.count == uniqueIds.count, "Duplicate snippet IDs for \(dialect)")
    }
}
