import Foundation
import Testing
@testable import EchoSense

// MARK: - Phase 5: Derived Table Column Extraction

@Test
func extractsColumnsFromSimpleDerivedTable() {
    let sql = "SELECT sub.id FROM (SELECT id, name FROM users) sub WHERE sub."
    let catalog = SQLDatabaseCatalog(schemas: [])
    let parser = SQLContextParser(text: sql, caretLocation: sql.count, dialect: .postgresql, catalog: catalog)
    let context = parser.parse()

    // The derived table alias "sub" should have columns "id" and "name"
    let subColumns = context.cteColumns["sub"]
    #expect(subColumns != nil, "Should extract derived table columns for alias 'sub'")
    #expect(subColumns?.contains("id") == true)
    #expect(subColumns?.contains("name") == true)
}

@Test
func extractsColumnsFromDerivedTableWithAS() {
    let sql = "SELECT s.amount FROM (SELECT amount, total FROM orders) AS s WHERE s."
    let catalog = SQLDatabaseCatalog(schemas: [])
    let parser = SQLContextParser(text: sql, caretLocation: sql.count, dialect: .postgresql, catalog: catalog)
    let context = parser.parse()

    let columns = context.cteColumns["s"]
    #expect(columns != nil, "Should extract derived table columns with AS alias")
    #expect(columns?.contains("amount") == true)
    #expect(columns?.contains("total") == true)
}

@Test
func extractsColumnsFromDerivedTableWithAliasedColumns() {
    let sql = "SELECT sub.total FROM (SELECT SUM(amount) AS total, user_id FROM orders GROUP BY user_id) sub"
    let catalog = SQLDatabaseCatalog(schemas: [])
    let parser = SQLContextParser(text: sql, caretLocation: sql.count, dialect: .postgresql, catalog: catalog)
    let context = parser.parse()

    let columns = context.cteColumns["sub"]
    #expect(columns != nil)
    #expect(columns?.contains("total") == true)
    #expect(columns?.contains("user_id") == true)
}

@Test
func doesNotExtractFromStarInDerivedTable() {
    let sql = "SELECT sub.x FROM (SELECT * FROM users) sub WHERE sub."
    let catalog = SQLDatabaseCatalog(schemas: [])
    let parser = SQLContextParser(text: sql, caretLocation: sql.count, dialect: .postgresql, catalog: catalog)
    let context = parser.parse()

    // SELECT * inside a derived table should not produce column mappings
    // (we can't resolve * without recursive resolution)
    let columns = context.cteColumns["sub"]
    #expect(columns == nil || columns?.isEmpty == true,
            "Should not extract columns from SELECT * in derived table")
}

@Test
func derivedTableDoesNotOverrideCTE() {
    // If a CTE and derived table share an alias, CTE takes precedence
    let sql = "WITH sub (a, b) AS (SELECT 1, 2) SELECT sub.x FROM (SELECT x, y FROM t) sub"
    let catalog = SQLDatabaseCatalog(schemas: [])
    let parser = SQLContextParser(text: sql, caretLocation: sql.count, dialect: .postgresql, catalog: catalog)
    let context = parser.parse()

    let columns = context.cteColumns["sub"]
    #expect(columns != nil)
    // CTE definition should win
    #expect(columns?.contains("a") == true)
    #expect(columns?.contains("b") == true)
}

@Test
func ignoresSubqueryWithoutAlias() {
    let sql = "SELECT * FROM (SELECT id FROM users) WHERE"
    let catalog = SQLDatabaseCatalog(schemas: [])
    let parser = SQLContextParser(text: sql, caretLocation: sql.count, dialect: .postgresql, catalog: catalog)
    let context = parser.parse()

    // WHERE follows the subquery, so it shouldn't be treated as an alias
    // The derived table has no valid alias
    for (key, _) in context.cteColumns {
        #expect(key != "where", "Should not use keywords as derived table aliases")
    }
}

@Test
func extractsFromQualifiedColumns() {
    let sql = "SELECT d.user_id FROM (SELECT users.id AS user_id, orders.amount FROM users JOIN orders ON users.id = orders.user_id) d"
    let catalog = SQLDatabaseCatalog(schemas: [])
    let parser = SQLContextParser(text: sql, caretLocation: sql.count, dialect: .postgresql, catalog: catalog)
    let context = parser.parse()

    let columns = context.cteColumns["d"]
    #expect(columns != nil)
    #expect(columns?.contains("user_id") == true)
    #expect(columns?.contains("amount") == true)
}
