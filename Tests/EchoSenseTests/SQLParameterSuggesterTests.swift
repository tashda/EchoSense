import Testing
@testable import EchoSense

// MARK: - PostgreSQL Parameters

@Test
func postgresFirstParameter() {
    let suggestions = SQLParameterSuggester.parameterSuggestions(for: "SELECT ", dialect: .postgresql)
    #expect(suggestions == ["$1"])
}

@Test
func postgresIncrementingParameter() {
    let suggestions = SQLParameterSuggester.parameterSuggestions(for: "SELECT $1, $2, ", dialect: .postgresql)
    #expect(suggestions == ["$3"])
}

@Test
func postgresFindsHighestParameter() {
    let suggestions = SQLParameterSuggester.parameterSuggestions(for: "WHERE id = $3 AND name = $1", dialect: .postgresql)
    #expect(suggestions == ["$4"])
}

// MARK: - SQLite Parameters

@Test
func sqliteUsesNumberedParams() {
    let suggestions = SQLParameterSuggester.parameterSuggestions(for: "SELECT $1 FROM ", dialect: .sqlite)
    #expect(suggestions == ["$2"])
}

@Test
func sqliteFirstParameter() {
    let suggestions = SQLParameterSuggester.parameterSuggestions(for: "SELECT ", dialect: .sqlite)
    #expect(suggestions == ["$1"])
}

// MARK: - MySQL Parameters

@Test
func mysqlUsesQuestionMark() {
    let suggestions = SQLParameterSuggester.parameterSuggestions(for: "SELECT ", dialect: .mysql)
    #expect(suggestions == ["?"])
}

@Test
func mysqlAlwaysReturnsQuestionMark() {
    let suggestions = SQLParameterSuggester.parameterSuggestions(for: "WHERE id = ? AND name = ?", dialect: .mysql)
    #expect(suggestions == ["?"])
}

// MARK: - SQL Server Parameters

@Test
func sqlServerFirstParameter() {
    let suggestions = SQLParameterSuggester.parameterSuggestions(for: "SELECT ", dialect: .microsoftSQL)
    #expect(suggestions == ["@p1"])
}

@Test
func sqlServerIncrementingParameter() {
    let suggestions = SQLParameterSuggester.parameterSuggestions(for: "WHERE id = @p1 AND name = @p2", dialect: .microsoftSQL)
    #expect(suggestions == ["@p3"])
}

@Test
func sqlServerCaseInsensitive() {
    let suggestions = SQLParameterSuggester.parameterSuggestions(for: "WHERE id = @P1", dialect: .microsoftSQL)
    #expect(suggestions == ["@p2"])
}
