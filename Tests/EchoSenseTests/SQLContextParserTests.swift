import Foundation
import Testing
@testable import EchoSense

private let emptyCatalog = SQLDatabaseCatalog(schemas: [])

// MARK: - Clause Detection

@Test
func detectsSelectClause() {
    let text = "SELECT "
    let parser = SQLContextParser(text: text, caretLocation: text.count, dialect: .postgresql, catalog: emptyCatalog)
    let context = parser.parse()

    #expect(context.clause == .selectList)
}

@Test
func detectsFromClause() {
    let text = "SELECT id FROM "
    let parser = SQLContextParser(text: text, caretLocation: text.count, dialect: .postgresql, catalog: emptyCatalog)
    let context = parser.parse()

    #expect(context.clause == .from)
}

@Test
func detectsWhereClause() {
    let text = "SELECT id FROM users WHERE "
    let parser = SQLContextParser(text: text, caretLocation: text.count, dialect: .postgresql, catalog: emptyCatalog)
    let context = parser.parse()

    #expect(context.clause == .whereClause)
}

@Test
func detectsJoinTarget() {
    let text = "SELECT * FROM users JOIN "
    let parser = SQLContextParser(text: text, caretLocation: text.count, dialect: .postgresql, catalog: emptyCatalog)
    let context = parser.parse()

    #expect(context.clause == .joinTarget)
}

@Test
func detectsJoinCondition() {
    let text = "SELECT * FROM users JOIN orders ON "
    let parser = SQLContextParser(text: text, caretLocation: text.count, dialect: .postgresql, catalog: emptyCatalog)
    let context = parser.parse()

    #expect(context.clause == .joinCondition)
}

@Test
func detectsGroupByClause() {
    let text = "SELECT name FROM users GROUP BY "
    let parser = SQLContextParser(text: text, caretLocation: text.count, dialect: .postgresql, catalog: emptyCatalog)
    let context = parser.parse()

    #expect(context.clause == .groupBy)
}

@Test
func detectsOrderByClause() {
    let text = "SELECT name FROM users ORDER BY "
    let parser = SQLContextParser(text: text, caretLocation: text.count, dialect: .postgresql, catalog: emptyCatalog)
    let context = parser.parse()

    #expect(context.clause == .orderBy)
}

@Test
func detectsHavingClause() {
    let text = "SELECT name, COUNT(*) FROM users GROUP BY name HAVING "
    let parser = SQLContextParser(text: text, caretLocation: text.count, dialect: .postgresql, catalog: emptyCatalog)
    let context = parser.parse()

    #expect(context.clause == .having)
}

@Test
func detectsLimitClause() {
    let text = "SELECT name FROM users LIMIT "
    let parser = SQLContextParser(text: text, caretLocation: text.count, dialect: .postgresql, catalog: emptyCatalog)
    let context = parser.parse()

    #expect(context.clause == .limit)
}

@Test
func detectsOffsetClause() {
    let text = "SELECT name FROM users LIMIT 10 OFFSET "
    let parser = SQLContextParser(text: text, caretLocation: text.count, dialect: .postgresql, catalog: emptyCatalog)
    let context = parser.parse()

    #expect(context.clause == .offset)
}

@Test
func detectsInsertColumns() {
    let text = "INSERT INTO users ("
    let parser = SQLContextParser(text: text, caretLocation: text.count, dialect: .postgresql, catalog: emptyCatalog)
    let context = parser.parse()

    #expect(context.clause == .insertColumns)
}

@Test
func detectsValuesClause() {
    let text = "INSERT INTO users (name) VALUES "
    let parser = SQLContextParser(text: text, caretLocation: text.count, dialect: .postgresql, catalog: emptyCatalog)
    let context = parser.parse()

    #expect(context.clause == .values)
}

@Test
func detectsUpdateSetClause() {
    let text = "UPDATE users SET "
    let parser = SQLContextParser(text: text, caretLocation: text.count, dialect: .postgresql, catalog: emptyCatalog)
    let context = parser.parse()

    #expect(context.clause == .updateSet)
}

@Test
func detectsDeleteClause() {
    // DELETE alone sets clause to .from initially (for the table name)
    let text = "DELETE "
    let parser = SQLContextParser(text: text, caretLocation: text.count, dialect: .postgresql, catalog: emptyCatalog)
    let context = parser.parse()

    #expect(context.clause == .from)
}

@Test
func detectsDeleteWhereAfterFrom() {
    // After DELETE FROM table, unknown clause + encounteredDelete => deleteWhere
    let text = "DELETE FROM users WHERE "
    let parser = SQLContextParser(text: text, caretLocation: text.count, dialect: .postgresql, catalog: emptyCatalog)
    let context = parser.parse()

    #expect(context.clause == .whereClause)
}

@Test
func detectsWithCTE() {
    let text = "WITH "
    let parser = SQLContextParser(text: text, caretLocation: text.count, dialect: .postgresql, catalog: emptyCatalog)
    let context = parser.parse()

    #expect(context.clause == .withCTE)
}

@Test
func detectsReturningAsSelectList() {
    let text = "INSERT INTO users (name) VALUES ('test') RETURNING "
    let parser = SQLContextParser(text: text, caretLocation: text.count, dialect: .postgresql, catalog: emptyCatalog)
    let context = parser.parse()

    #expect(context.clause == .selectList)
}

// MARK: - Left/Right/Full Join Variants

@Test
func detectsLeftJoinTarget() {
    let text = "SELECT * FROM users LEFT JOIN "
    let parser = SQLContextParser(text: text, caretLocation: text.count, dialect: .postgresql, catalog: emptyCatalog)
    let context = parser.parse()

    #expect(context.clause == .joinTarget)
}

@Test
func detectsInnerJoinTarget() {
    let text = "SELECT * FROM users INNER JOIN "
    let parser = SQLContextParser(text: text, caretLocation: text.count, dialect: .postgresql, catalog: emptyCatalog)
    let context = parser.parse()

    #expect(context.clause == .joinTarget)
}

// MARK: - Table Extraction

@Test
func extractsTableFromSelect() {
    let text = "SELECT * FROM users WHERE "
    let parser = SQLContextParser(text: text, caretLocation: text.count, dialect: .postgresql, catalog: emptyCatalog)
    let context = parser.parse()

    #expect(context.tablesInScope.count == 1)
    #expect(context.tablesInScope[0].name == "users")
    #expect(context.tablesInScope[0].alias == nil)
}

@Test
func extractsTableWithAlias() {
    let text = "SELECT * FROM users u WHERE "
    let parser = SQLContextParser(text: text, caretLocation: text.count, dialect: .postgresql, catalog: emptyCatalog)
    let context = parser.parse()

    #expect(context.tablesInScope.count == 1)
    #expect(context.tablesInScope[0].name == "users")
    #expect(context.tablesInScope[0].alias == "u")
}

@Test
func extractsTableWithASAlias() {
    let text = "SELECT * FROM users AS u WHERE "
    let parser = SQLContextParser(text: text, caretLocation: text.count, dialect: .postgresql, catalog: emptyCatalog)
    let context = parser.parse()

    #expect(context.tablesInScope.count == 1)
    #expect(context.tablesInScope[0].name == "users")
    #expect(context.tablesInScope[0].alias == "u")
}

@Test
func extractsSchemaQualifiedTable() {
    let text = "SELECT * FROM public.users WHERE "
    let parser = SQLContextParser(text: text, caretLocation: text.count, dialect: .postgresql, catalog: emptyCatalog)
    let context = parser.parse()

    #expect(context.tablesInScope.count == 1)
    #expect(context.tablesInScope[0].schema == "public")
    #expect(context.tablesInScope[0].name == "users")
}

@Test
func extractsMultipleTables() {
    let text = "SELECT * FROM users u JOIN orders o ON u.id = o.user_id"
    let parser = SQLContextParser(text: text, caretLocation: text.count, dialect: .postgresql, catalog: emptyCatalog)
    let context = parser.parse()

    #expect(context.tablesInScope.count == 2)
    let names = context.tablesInScope.map { $0.name }
    #expect(names.contains("users"))
    #expect(names.contains("orders"))
}

@Test
func extractsUpdateTable() {
    let text = "UPDATE users SET name = 'test'"
    let parser = SQLContextParser(text: text, caretLocation: text.count, dialect: .postgresql, catalog: emptyCatalog)
    let context = parser.parse()

    #expect(context.tablesInScope.count == 1)
    #expect(context.tablesInScope[0].name == "users")
}

@Test
func extractsInsertIntoTable() {
    let text = "INSERT INTO users (name) VALUES "
    let parser = SQLContextParser(text: text, caretLocation: text.count, dialect: .postgresql, catalog: emptyCatalog)
    let context = parser.parse()

    #expect(context.tablesInScope.count == 1)
    #expect(context.tablesInScope[0].name == "users")
}

// MARK: - Focus Table

@Test
func focusTableIsLastTableBeforeCaret() {
    let text = "SELECT * FROM users u JOIN orders o ON "
    let parser = SQLContextParser(text: text, caretLocation: text.count, dialect: .postgresql, catalog: emptyCatalog)
    let context = parser.parse()

    #expect(context.focusTable?.name == "orders")
    #expect(context.focusTable?.alias == "o")
}

// MARK: - Token at Caret

@Test
func extractsCurrentToken() {
    let text = "SELECT us"
    let parser = SQLContextParser(text: text, caretLocation: text.count, dialect: .postgresql, catalog: emptyCatalog)
    let context = parser.parse()

    #expect(context.currentToken == "us")
}

@Test
func extractsDottedToken() {
    let text = "SELECT u.na"
    let parser = SQLContextParser(text: text, caretLocation: text.count, dialect: .postgresql, catalog: emptyCatalog)
    let context = parser.parse()

    #expect(context.currentToken == "u.na")
    #expect(context.pathComponents == ["u"])
}

@Test
func emptyTokenAtSpace() {
    let text = "SELECT "
    let parser = SQLContextParser(text: text, caretLocation: text.count, dialect: .postgresql, catalog: emptyCatalog)
    let context = parser.parse()

    #expect(context.currentToken == "")
}

// MARK: - Preceding Keyword

@Test
func detectsPrecedingKeyword() {
    let text = "SELECT * FROM "
    let parser = SQLContextParser(text: text, caretLocation: text.count, dialect: .postgresql, catalog: emptyCatalog)
    let context = parser.parse()

    #expect(context.precedingKeyword == "from")
}

@Test
func detectsPrecedingKeywordSelect() {
    let text = "SELECT "
    let parser = SQLContextParser(text: text, caretLocation: text.count, dialect: .postgresql, catalog: emptyCatalog)
    let context = parser.parse()

    #expect(context.precedingKeyword == "select")
}

// MARK: - CTE Column Parsing

@Test
func parsesCTEColumns() {
    let text = "WITH cte(id, name) AS (SELECT 1, 'test') SELECT "
    let parser = SQLContextParser(text: text, caretLocation: text.count, dialect: .postgresql, catalog: emptyCatalog)
    let context = parser.parse()

    #expect(context.cteColumns["cte"] == ["id", "name"])
}

// MARK: - Edge Cases

@Test
func handlesEmptyText() {
    let text = ""
    let parser = SQLContextParser(text: text, caretLocation: 0, dialect: .postgresql, catalog: emptyCatalog)
    let context = parser.parse()

    #expect(context.clause == .unknown)
    #expect(context.tablesInScope.isEmpty)
    #expect(context.currentToken == "")
}

@Test
func handlesCaretBeyondTextLength() {
    let text = "SELECT"
    let parser = SQLContextParser(text: text, caretLocation: 100, dialect: .postgresql, catalog: emptyCatalog)
    let context = parser.parse()

    #expect(context.caretLocation == text.count)
}

@Test
func handlesNegativeCaretLocation() {
    let text = "SELECT * FROM users"
    let parser = SQLContextParser(text: text, caretLocation: -5, dialect: .postgresql, catalog: emptyCatalog)
    let context = parser.parse()

    #expect(context.caretLocation == 0)
}

// MARK: - Static Keyword Sets

@Test
func objectContextKeywordsContainsExpected() {
    let expected: Set<String> = ["from", "join", "inner", "left", "right", "full", "outer", "cross", "update", "into", "delete"]
    #expect(SQLContextParser.objectContextKeywords == expected)
}

@Test
func columnContextKeywordsContainsExpected() {
    #expect(SQLContextParser.columnContextKeywords.contains("select"))
    #expect(SQLContextParser.columnContextKeywords.contains("where"))
    #expect(SQLContextParser.columnContextKeywords.contains("on"))
    #expect(SQLContextParser.columnContextKeywords.contains("returning"))
}
