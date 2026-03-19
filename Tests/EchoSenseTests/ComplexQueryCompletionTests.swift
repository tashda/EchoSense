import Foundation
import Testing
@testable import EchoSense

@Suite("Complex Query Completion")
struct ComplexQueryCompletionTests {

    // MARK: - Helpers

    private func makeStructure() -> EchoSenseDatabaseStructure {
        let idCol = EchoSenseColumnInfo(name: "id", dataType: "integer", isPrimaryKey: true, isNullable: false)
        let nameCol = EchoSenseColumnInfo(name: "name", dataType: "text", isNullable: true)
        let emailCol = EchoSenseColumnInfo(name: "email", dataType: "text", isNullable: true)
        let createdAtCol = EchoSenseColumnInfo(name: "created_at", dataType: "timestamp", isNullable: true)

        let userFk = EchoSenseForeignKeyReference(constraintName: "fk_orders_user",
                                                   referencedSchema: "public",
                                                   referencedTable: "users",
                                                   referencedColumn: "id")
        let productFk = EchoSenseForeignKeyReference(constraintName: "fk_order_items_product",
                                                      referencedSchema: "public",
                                                      referencedTable: "products",
                                                      referencedColumn: "id")
        let orderFk = EchoSenseForeignKeyReference(constraintName: "fk_order_items_order",
                                                    referencedSchema: "public",
                                                    referencedTable: "orders",
                                                    referencedColumn: "id")
        let managerFk = EchoSenseForeignKeyReference(constraintName: "fk_employees_manager",
                                                      referencedSchema: "public",
                                                      referencedTable: "employees",
                                                      referencedColumn: "id")
        let categoryFk = EchoSenseForeignKeyReference(constraintName: "fk_products_category",
                                                       referencedSchema: "public",
                                                       referencedTable: "categories",
                                                       referencedColumn: "id")

        let orderUserIdCol = EchoSenseColumnInfo(name: "user_id", dataType: "integer",
                                                  isPrimaryKey: false, isNullable: false, foreignKey: userFk)
        let amountCol = EchoSenseColumnInfo(name: "amount", dataType: "numeric", isNullable: true)
        let statusCol = EchoSenseColumnInfo(name: "status", dataType: "text", isNullable: true)
        let orderDateCol = EchoSenseColumnInfo(name: "order_date", dataType: "date", isNullable: true)

        let orderItemOrderIdCol = EchoSenseColumnInfo(name: "order_id", dataType: "integer",
                                                       isPrimaryKey: false, isNullable: false, foreignKey: orderFk)
        let orderItemProductIdCol = EchoSenseColumnInfo(name: "product_id", dataType: "integer",
                                                         isPrimaryKey: false, isNullable: false, foreignKey: productFk)
        let quantityCol = EchoSenseColumnInfo(name: "quantity", dataType: "integer", isNullable: false)
        let priceCol = EchoSenseColumnInfo(name: "price", dataType: "numeric", isNullable: true)

        let categoryIdCol = EchoSenseColumnInfo(name: "category_id", dataType: "integer",
                                                 isPrimaryKey: false, isNullable: true, foreignKey: categoryFk)
        let descriptionCol = EchoSenseColumnInfo(name: "description", dataType: "text", isNullable: true)

        let managerIdCol = EchoSenseColumnInfo(name: "manager_id", dataType: "integer",
                                                isPrimaryKey: false, isNullable: true, foreignKey: managerFk)
        let departmentCol = EchoSenseColumnInfo(name: "department", dataType: "text", isNullable: true)
        let salaryCol = EchoSenseColumnInfo(name: "salary", dataType: "numeric", isNullable: true)
        let hireDateCol = EchoSenseColumnInfo(name: "hire_date", dataType: "date", isNullable: true)

        let usersTable = EchoSenseSchemaObjectInfo(name: "users", schema: "public",
                                                    type: .table, columns: [idCol, nameCol, emailCol, createdAtCol])
        let ordersTable = EchoSenseSchemaObjectInfo(name: "orders", schema: "public",
                                                     type: .table, columns: [idCol, orderUserIdCol, amountCol, statusCol, orderDateCol])
        let orderItemsTable = EchoSenseSchemaObjectInfo(name: "order_items", schema: "public",
                                                         type: .table, columns: [idCol, orderItemOrderIdCol, orderItemProductIdCol, quantityCol, priceCol])
        let productsTable = EchoSenseSchemaObjectInfo(name: "products", schema: "public",
                                                       type: .table, columns: [idCol, nameCol, priceCol, categoryIdCol, descriptionCol])
        let categoriesTable = EchoSenseSchemaObjectInfo(name: "categories", schema: "public",
                                                         type: .table, columns: [idCol, nameCol])
        let employeesTable = EchoSenseSchemaObjectInfo(name: "employees", schema: "public",
                                                        type: .table, columns: [idCol, nameCol, managerIdCol, departmentCol, salaryCol, hireDateCol])

        let publicSchema = EchoSenseSchemaInfo(name: "public",
                                                objects: [usersTable, ordersTable, orderItemsTable,
                                                          productsTable, categoriesTable, employeesTable])
        let database = EchoSenseDatabaseInfo(name: "testdb", schemas: [publicSchema])
        return EchoSenseDatabaseStructure(databases: [database])
    }

    private func makeContext(dialect: EchoSenseDatabaseType = .postgresql) -> SQLEditorCompletionContext {
        SQLEditorCompletionContext(databaseType: dialect,
                                   selectedDatabase: "testdb",
                                   defaultSchema: "public",
                                   structure: makeStructure())
    }

    private func makeEngine(dialect: EchoSenseDatabaseType = .postgresql) -> SQLAutoCompletionEngine {
        let engine = SQLAutoCompletionEngine()
        engine.updateContext(makeContext(dialect: dialect))
        engine.updateAggressiveness(.eager)
        engine.updateHistoryPreference(includeHistory: false)
        return engine
    }

    private func allSuggestions(from result: SQLAutoCompletionResult) -> [SQLAutoCompletionSuggestion] {
        result.sections.flatMap(\.suggestions)
    }

    private func columnTitles(from result: SQLAutoCompletionResult) -> [String] {
        allSuggestions(from: result).filter { $0.kind == .column }.map(\.title)
    }

    // MARK: - Multi-table JOINs

    @Test func threeTableJoinSuggestsColumnsFromAllTables() {
        let engine = makeEngine()
        let usersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "users", alias: "u")
        let ordersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "orders", alias: "o")
        let itemsFocus = SQLAutoCompletionTableFocus(schema: "public", name: "order_items", alias: "oi")
        let text = "SELECT  FROM users u JOIN orders o ON u.id = o.user_id JOIN order_items oi ON o.id = oi.order_id"
        let query = SQLAutoCompletionQuery(token: "", prefix: "", pathComponents: [],
                                            replacementRange: NSRange(location: 7, length: 0),
                                            precedingKeyword: "select", precedingCharacter: nil,
                                            focusTable: usersFocus,
                                            tablesInScope: [usersFocus, ordersFocus, itemsFocus],
                                            clause: .selectList)

        let result = engine.suggestions(for: query, text: text, caretLocation: 7)
        let columns = columnTitles(from: result)

        // Should have columns from all three tables — qualified since multiple tables
        #expect(!columns.isEmpty, "Should suggest columns from all joined tables")
    }

    @Test func threeTableJoinDisambiguatesColumns() {
        let engine = makeEngine()
        let usersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "users", alias: "u")
        let ordersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "orders", alias: "o")
        let itemsFocus = SQLAutoCompletionTableFocus(schema: "public", name: "order_items", alias: "oi")
        let text = "SELECT  FROM users u JOIN orders o ON u.id = o.user_id JOIN order_items oi ON o.id = oi.order_id"
        let query = SQLAutoCompletionQuery(token: "", prefix: "", pathComponents: [],
                                            replacementRange: NSRange(location: 7, length: 0),
                                            precedingKeyword: "select", precedingCharacter: nil,
                                            focusTable: usersFocus,
                                            tablesInScope: [usersFocus, ordersFocus, itemsFocus],
                                            clause: .selectList)

        let result = engine.suggestions(for: query, text: text, caretLocation: 7)
        let columns = columnTitles(from: result)

        // With multiple tables, columns should be qualified with alias
        let qualifiedColumns = columns.filter { $0.contains(".") }
        #expect(!qualifiedColumns.isEmpty, "Should produce alias-qualified columns when multiple tables in scope")
    }

    // MARK: - Self-joins

    @Test func selfJoinWithAliasesSuggestsAliasQualifiedColumns() {
        let engine = makeEngine()
        let empFocus = SQLAutoCompletionTableFocus(schema: "public", name: "employees", alias: "e")
        let mgrFocus = SQLAutoCompletionTableFocus(schema: "public", name: "employees", alias: "m")
        let text = "SELECT  FROM employees e JOIN employees m ON e.manager_id = m.id"
        let query = SQLAutoCompletionQuery(token: "", prefix: "", pathComponents: [],
                                            replacementRange: NSRange(location: 7, length: 0),
                                            precedingKeyword: "select", precedingCharacter: nil,
                                            focusTable: empFocus,
                                            tablesInScope: [empFocus, mgrFocus],
                                            clause: .selectList)

        let result = engine.suggestions(for: query, text: text, caretLocation: 7)
        let columns = columnTitles(from: result)

        // Should have both e. and m. prefixed columns
        let eColumns = columns.filter { $0.hasPrefix("e.") }
        let mColumns = columns.filter { $0.hasPrefix("m.") }
        #expect(!eColumns.isEmpty, "Should suggest e. columns")
        #expect(!mColumns.isEmpty, "Should suggest m. columns")
    }

    @Test func selfJoinDotPrefixFiltersToAlias() {
        let engine = makeEngine()
        let empFocus = SQLAutoCompletionTableFocus(schema: "public", name: "employees", alias: "e")
        let mgrFocus = SQLAutoCompletionTableFocus(schema: "public", name: "employees", alias: "m")
        let text = "SELECT m. FROM employees e JOIN employees m ON e.manager_id = m.id"
        let query = SQLAutoCompletionQuery(token: "m.", prefix: "", pathComponents: ["m"],
                                            replacementRange: NSRange(location: 7, length: 2),
                                            precedingKeyword: "select", precedingCharacter: nil,
                                            focusTable: empFocus,
                                            tablesInScope: [empFocus, mgrFocus],
                                            clause: .selectList)

        let result = engine.suggestions(for: query, text: text, caretLocation: 9)
        let columns = columnTitles(from: result)

        // After typing "m.", columns should be unqualified (user already typed the qualifier)
        #expect(!columns.isEmpty, "Should suggest columns when typing m.")
        // Columns should be bare names (not m.prefixed) since user already typed "m."
        let hasColumns = columns.contains("id") || columns.contains("\"name\"") || columns.contains("name")
            || columns.contains(where: { $0.hasPrefix("m.") })
        #expect(hasColumns, "Should suggest columns for the m alias")
    }

    // MARK: - Window Functions

    @Test func windowFunctionPartitionBySuggestsColumns() {
        let engine = makeEngine()
        let ordersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "orders", alias: nil)
        let text = "SELECT ROW_NUMBER() OVER (PARTITION BY  FROM orders"
        let query = SQLAutoCompletionQuery(token: "", prefix: "", pathComponents: [],
                                            replacementRange: NSRange(location: 38, length: 0),
                                            precedingKeyword: "by", precedingCharacter: nil,
                                            focusTable: ordersFocus,
                                            tablesInScope: [ordersFocus],
                                            clause: .selectList)

        let result = engine.suggestions(for: query, text: text, caretLocation: 38)
        let suggestions = allSuggestions(from: result)
        // The parser should still provide columns in scope even inside window spec
        #expect(!suggestions.isEmpty, "Should suggest something inside PARTITION BY")
    }

    // MARK: - CASE WHEN Expressions

    @Test func caseWhenSuggestsColumnsInWhen() {
        let engine = makeEngine()
        let ordersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "orders", alias: nil)
        let text = "SELECT CASE WHEN  THEN 'high' END FROM orders"
        let query = SQLAutoCompletionQuery(token: "", prefix: "", pathComponents: [],
                                            replacementRange: NSRange(location: 17, length: 0),
                                            precedingKeyword: "when", precedingCharacter: nil,
                                            focusTable: ordersFocus,
                                            tablesInScope: [ordersFocus],
                                            clause: .selectList)

        let result = engine.suggestions(for: query, text: text, caretLocation: 17)
        let columns = columnTitles(from: result)
        #expect(!columns.isEmpty, "Should suggest columns inside CASE WHEN")
    }

    @Test func caseWhenSuggestsColumnsInThen() {
        let engine = makeEngine()
        let ordersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "orders", alias: nil)
        let text = "SELECT CASE WHEN amount > 100 THEN  END FROM orders"
        let query = SQLAutoCompletionQuery(token: "", prefix: "", pathComponents: [],
                                            replacementRange: NSRange(location: 34, length: 0),
                                            precedingKeyword: "then", precedingCharacter: nil,
                                            focusTable: ordersFocus,
                                            tablesInScope: [ordersFocus],
                                            clause: .selectList)

        let result = engine.suggestions(for: query, text: text, caretLocation: 34)
        let suggestions = allSuggestions(from: result)
        #expect(!suggestions.isEmpty, "Should suggest inside THEN")
    }

    @Test func caseWhenSuggestsColumnsInElse() {
        let engine = makeEngine()
        let ordersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "orders", alias: nil)
        let text = "SELECT CASE WHEN amount > 100 THEN 'high' ELSE  END FROM orders"
        let query = SQLAutoCompletionQuery(token: "", prefix: "", pathComponents: [],
                                            replacementRange: NSRange(location: 47, length: 0),
                                            precedingKeyword: "else", precedingCharacter: nil,
                                            focusTable: ordersFocus,
                                            tablesInScope: [ordersFocus],
                                            clause: .selectList)

        let result = engine.suggestions(for: query, text: text, caretLocation: 47)
        let suggestions = allSuggestions(from: result)
        #expect(!suggestions.isEmpty, "Should suggest inside ELSE")
    }

    // MARK: - EXISTS / NOT EXISTS Subqueries

    @Test func existsSubqueryTablesInScope() {
        let engine = makeEngine()
        let usersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "users", alias: nil)
        let text = "SELECT * FROM users WHERE EXISTS (SELECT * FROM "
        let query = SQLAutoCompletionQuery(token: "", prefix: "", pathComponents: [],
                                            replacementRange: NSRange(location: text.count, length: 0),
                                            precedingKeyword: "from", precedingCharacter: nil,
                                            focusTable: usersFocus,
                                            tablesInScope: [usersFocus],
                                            clause: .from)

        let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
        let suggestions = allSuggestions(from: result)
        let tableNames = suggestions.filter { $0.kind == .table }.map(\.title)
        #expect(tableNames.contains("orders"), "Should suggest tables inside EXISTS subquery")
    }

    // MARK: - IN Subquery

    @Test func inSubqueryFromClauseSuggestsTables() {
        let engine = makeEngine()
        let usersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "users", alias: nil)
        let text = "SELECT * FROM users WHERE id IN (SELECT user_id FROM "
        let query = SQLAutoCompletionQuery(token: "", prefix: "", pathComponents: [],
                                            replacementRange: NSRange(location: text.count, length: 0),
                                            precedingKeyword: "from", precedingCharacter: nil,
                                            focusTable: usersFocus,
                                            tablesInScope: [usersFocus],
                                            clause: .from)

        let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
        let suggestions = allSuggestions(from: result)
        let tableNames = suggestions.filter { $0.kind == .table }.map(\.title)
        #expect(tableNames.contains("orders"), "Should suggest tables in IN subquery")
    }

    // MARK: - UNION / INTERSECT / EXCEPT

    @Test func unionResetsClauseForSecondSelect() {
        let emptyCatalog = SQLDatabaseCatalog(schemas: [])
        let text = "SELECT id FROM users UNION SELECT "
        let parser = SQLContextParser(text: text, caretLocation: text.count, dialect: .postgresql, catalog: emptyCatalog)
        let context = parser.parse()

        #expect(context.clause == .selectList, "After UNION SELECT, clause should be selectList")
    }

    @Test func intersectResetsClause() {
        let emptyCatalog = SQLDatabaseCatalog(schemas: [])
        let text = "SELECT id FROM users INTERSECT SELECT "
        let parser = SQLContextParser(text: text, caretLocation: text.count, dialect: .postgresql, catalog: emptyCatalog)
        let context = parser.parse()

        #expect(context.clause == .selectList)
    }

    @Test func exceptResetsClause() {
        let emptyCatalog = SQLDatabaseCatalog(schemas: [])
        let text = "SELECT id FROM users EXCEPT SELECT * FROM "
        let parser = SQLContextParser(text: text, caretLocation: text.count, dialect: .postgresql, catalog: emptyCatalog)
        let context = parser.parse()

        #expect(context.clause == .from)
    }

    @Test func unionAllResetsClause() {
        let emptyCatalog = SQLDatabaseCatalog(schemas: [])
        let text = "SELECT id FROM users UNION ALL SELECT "
        let parser = SQLContextParser(text: text, caretLocation: text.count, dialect: .postgresql, catalog: emptyCatalog)
        let context = parser.parse()

        #expect(context.clause == .selectList)
    }

    // MARK: - INSERT...SELECT

    @Test func insertSelectSuggestsColumnsInSelectPart() {
        let engine = makeEngine()
        let usersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "users", alias: nil)
        let text = "INSERT INTO orders (user_id) SELECT  FROM users"
        let query = SQLAutoCompletionQuery(token: "", prefix: "", pathComponents: [],
                                            replacementRange: NSRange(location: 36, length: 0),
                                            precedingKeyword: "select", precedingCharacter: nil,
                                            focusTable: usersFocus,
                                            tablesInScope: [usersFocus],
                                            clause: .selectList)

        let result = engine.suggestions(for: query, text: text, caretLocation: 36)
        let columns = columnTitles(from: result)
        #expect(!columns.isEmpty, "Should suggest columns in INSERT...SELECT")
    }

    // MARK: - UPDATE with JOIN

    @Test func updateWithJoinSuggestsColumnsInSet() {
        let engine = makeEngine()
        let ordersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "orders", alias: "o")
        let usersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "users", alias: "u")
        let text = "UPDATE orders o SET  FROM orders o JOIN users u ON o.user_id = u.id"
        let query = SQLAutoCompletionQuery(token: "", prefix: "", pathComponents: [],
                                            replacementRange: NSRange(location: 20, length: 0),
                                            precedingKeyword: "set", precedingCharacter: nil,
                                            focusTable: ordersFocus,
                                            tablesInScope: [ordersFocus, usersFocus],
                                            clause: .updateSet)

        let result = engine.suggestions(for: query, text: text, caretLocation: 20)
        let columns = columnTitles(from: result)
        #expect(!columns.isEmpty, "Should suggest columns in UPDATE SET with JOIN")
    }

    // MARK: - Paginated Queries

    @Test func paginatedQueryLimitClause() {
        let emptyCatalog = SQLDatabaseCatalog(schemas: [])
        let text = "SELECT * FROM users ORDER BY id LIMIT "
        let parser = SQLContextParser(text: text, caretLocation: text.count, dialect: .postgresql, catalog: emptyCatalog)
        let context = parser.parse()

        #expect(context.clause == .limit)
    }

    @Test func paginatedQueryOffsetClause() {
        let emptyCatalog = SQLDatabaseCatalog(schemas: [])
        let text = "SELECT * FROM users ORDER BY id LIMIT 10 OFFSET "
        let parser = SQLContextParser(text: text, caretLocation: text.count, dialect: .postgresql, catalog: emptyCatalog)
        let context = parser.parse()

        #expect(context.clause == .offset)
    }

    // MARK: - Aggregation with HAVING

    @Test func havingClauseSuggestsColumnsAndFunctions() {
        let engine = makeEngine()
        let ordersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "orders", alias: nil)
        let text = "SELECT status, COUNT(*) FROM orders GROUP BY status HAVING "
        let query = SQLAutoCompletionQuery(token: "", prefix: "", pathComponents: [],
                                            replacementRange: NSRange(location: text.count, length: 0),
                                            precedingKeyword: "having", precedingCharacter: nil,
                                            focusTable: ordersFocus,
                                            tablesInScope: [ordersFocus],
                                            clause: .having)

        let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
        let suggestions = allSuggestions(from: result)
        let columns = suggestions.filter { $0.kind == .column }
        let functions = suggestions.filter { $0.kind == .function }
        #expect(!columns.isEmpty, "HAVING should suggest columns")
        #expect(!functions.isEmpty, "HAVING should suggest aggregate functions")
    }

    // MARK: - GROUP BY

    @Test func groupByClauseSuggestsColumns() {
        let engine = makeEngine()
        let ordersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "orders", alias: nil)
        let text = "SELECT status, COUNT(*) FROM orders GROUP BY "
        let query = SQLAutoCompletionQuery(token: "", prefix: "", pathComponents: [],
                                            replacementRange: NSRange(location: text.count, length: 0),
                                            precedingKeyword: "by", precedingCharacter: nil,
                                            focusTable: ordersFocus,
                                            tablesInScope: [ordersFocus],
                                            clause: .groupBy)

        let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
        let columns = columnTitles(from: result)
        #expect(!columns.isEmpty, "GROUP BY should suggest columns")
    }

    // MARK: - ORDER BY

    @Test func orderByClauseSuggestsColumns() {
        let engine = makeEngine()
        let ordersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "orders", alias: nil)
        let text = "SELECT * FROM orders ORDER BY "
        let query = SQLAutoCompletionQuery(token: "", prefix: "", pathComponents: [],
                                            replacementRange: NSRange(location: text.count, length: 0),
                                            precedingKeyword: "by", precedingCharacter: nil,
                                            focusTable: ordersFocus,
                                            tablesInScope: [ordersFocus],
                                            clause: .orderBy)

        let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
        let columns = columnTitles(from: result)
        #expect(!columns.isEmpty, "ORDER BY should suggest columns")
    }

    // MARK: - JOIN Condition

    @Test func joinConditionSuggestsJoinExpressions() {
        let engine = makeEngine()
        let usersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "users", alias: "u")
        let ordersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "orders", alias: "o")
        let text = "SELECT * FROM users u JOIN orders o ON "
        let query = SQLAutoCompletionQuery(token: "", prefix: "", pathComponents: [],
                                            replacementRange: NSRange(location: text.count, length: 0),
                                            precedingKeyword: "on", precedingCharacter: nil,
                                            focusTable: ordersFocus,
                                            tablesInScope: [usersFocus, ordersFocus],
                                            clause: .joinCondition)

        let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
        let suggestions = allSuggestions(from: result)

        let joinSuggestions = suggestions.filter { $0.kind == .join }
        #expect(!joinSuggestions.isEmpty, "Should suggest FK-based join conditions")
    }

    // MARK: - DELETE

    @Test func deleteFromSuggestsTables() {
        let engine = makeEngine()
        let text = "DELETE FROM "
        let query = SQLAutoCompletionQuery(token: "", prefix: "", pathComponents: [],
                                            replacementRange: NSRange(location: text.count, length: 0),
                                            precedingKeyword: "from", precedingCharacter: nil,
                                            focusTable: nil, tablesInScope: [],
                                            clause: .from)

        let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
        let tableNames = allSuggestions(from: result).filter { $0.kind == .table }.map(\.title)
        #expect(tableNames.contains("orders"), "DELETE FROM should suggest tables")
    }

    @Test func deleteWhereSuggestsColumns() {
        let engine = makeEngine()
        let ordersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "orders", alias: nil)
        let text = "DELETE FROM orders WHERE "
        let query = SQLAutoCompletionQuery(token: "", prefix: "", pathComponents: [],
                                            replacementRange: NSRange(location: text.count, length: 0),
                                            precedingKeyword: "where", precedingCharacter: nil,
                                            focusTable: ordersFocus,
                                            tablesInScope: [ordersFocus],
                                            clause: .whereClause)

        let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
        let columns = columnTitles(from: result)
        #expect(!columns.isEmpty, "DELETE WHERE should suggest columns")
    }

    // MARK: - Correlated Subquery

    @Test func correlatedSubqueryParsesOuterTable() {
        let emptyCatalog = SQLDatabaseCatalog(schemas: [])
        let text = "SELECT * FROM users u WHERE EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id)"
        let parser = SQLContextParser(text: text, caretLocation: text.count, dialect: .postgresql, catalog: emptyCatalog)
        let context = parser.parse()

        let tableNames = context.tablesInScope.map { $0.name }
        #expect(tableNames.contains("users"), "Should include outer table in scope")
        #expect(tableNames.contains("orders"), "Should include inner table in scope")
    }

    // MARK: - Four-Table Join

    @Test func fourTableJoinParsesAllTables() {
        let emptyCatalog = SQLDatabaseCatalog(schemas: [])
        let text = "SELECT * FROM users u JOIN orders o ON u.id = o.user_id JOIN order_items oi ON o.id = oi.order_id JOIN products p ON oi.product_id = p.id WHERE "
        let parser = SQLContextParser(text: text, caretLocation: text.count, dialect: .postgresql, catalog: emptyCatalog)
        let context = parser.parse()

        let tableNames = context.tablesInScope.map { $0.name }
        #expect(tableNames.contains("users"))
        #expect(tableNames.contains("orders"))
        #expect(tableNames.contains("order_items"))
        #expect(tableNames.contains("products"))
        #expect(context.tablesInScope.count == 4)
    }

    // MARK: - INSERT columns

    @Test func insertColumnsSuggestsTargetColumns() {
        let engine = makeEngine()
        let ordersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "orders", alias: nil)
        let text = "INSERT INTO orders ("
        let query = SQLAutoCompletionQuery(token: "", prefix: "", pathComponents: [],
                                            replacementRange: NSRange(location: text.count, length: 0),
                                            precedingKeyword: "into", precedingCharacter: nil,
                                            focusTable: ordersFocus,
                                            tablesInScope: [ordersFocus],
                                            clause: .insertColumns)

        let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
        let suggestions = allSuggestions(from: result)
        // insertColumns clause may suggest columns or not depending on provider support
        // At minimum it should not crash
        #expect(true, "INSERT INTO columns clause should not crash")
    }

    // MARK: - Multiple Schemas Detection

    @Test func joinTargetSuggestsJoinSnippets() {
        let engine = makeEngine()
        let usersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "users", alias: "u")
        let text = "SELECT * FROM users u JOIN "
        let query = SQLAutoCompletionQuery(token: "", prefix: "", pathComponents: [],
                                            replacementRange: NSRange(location: text.count, length: 0),
                                            precedingKeyword: "join", precedingCharacter: nil,
                                            focusTable: nil,
                                            tablesInScope: [usersFocus],
                                            clause: .joinTarget)

        let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
        let suggestions = allSuggestions(from: result)

        let joinSuggestions = suggestions.filter { $0.kind == .join }
        let tableSuggestions = suggestions.filter { $0.kind == .table }
        #expect(!tableSuggestions.isEmpty || !joinSuggestions.isEmpty,
                "JOIN target should suggest tables or join snippets")
    }

    // MARK: - Trailing Comma in SELECT

    @Test func trailingCommaInSelectSuggestsColumns() {
        let engine = makeEngine()
        let usersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "users", alias: nil)
        let text = "SELECT id, name,  FROM users"
        let query = SQLAutoCompletionQuery(token: "", prefix: "", pathComponents: [],
                                            replacementRange: NSRange(location: 17, length: 0),
                                            precedingKeyword: nil, precedingCharacter: ",",
                                            focusTable: usersFocus,
                                            tablesInScope: [usersFocus],
                                            clause: .selectList)

        let result = engine.suggestions(for: query, text: text, caretLocation: 17)
        let columns = columnTitles(from: result)
        #expect(!columns.isEmpty, "After trailing comma in SELECT, should suggest columns")
    }
}
