import Foundation
import Testing
@testable import EchoSense

@Suite("Multi-Dialect Completion")
struct MultiDialectCompletionTests {

    // MARK: - Helpers

    private func makeStructure() -> EchoSenseDatabaseStructure {
        let idCol = EchoSenseColumnInfo(name: "id", dataType: "integer", isPrimaryKey: true, isNullable: false)
        let nameCol = EchoSenseColumnInfo(name: "name", dataType: "text", isNullable: true)
        let emailCol = EchoSenseColumnInfo(name: "email", dataType: "text", isNullable: true)
        let priceCol = EchoSenseColumnInfo(name: "price", dataType: "numeric", isNullable: true)
        let createdAtCol = EchoSenseColumnInfo(name: "created_at", dataType: "timestamp", isNullable: true)
        let statusCol = EchoSenseColumnInfo(name: "status", dataType: "text", isNullable: true)

        let fk = EchoSenseForeignKeyReference(constraintName: "fk_orders_user",
                                               referencedSchema: "public",
                                               referencedTable: "users",
                                               referencedColumn: "id")
        let userIdCol = EchoSenseColumnInfo(name: "user_id", dataType: "integer",
                                             isPrimaryKey: false, isNullable: false, foreignKey: fk)
        let amountCol = EchoSenseColumnInfo(name: "amount", dataType: "numeric", isNullable: true)

        let usersTable = EchoSenseSchemaObjectInfo(name: "users", schema: "public",
                                                    type: .table, columns: [idCol, nameCol, emailCol, createdAtCol])
        let ordersTable = EchoSenseSchemaObjectInfo(name: "orders", schema: "public",
                                                     type: .table, columns: [idCol, userIdCol, amountCol, statusCol])
        let productsTable = EchoSenseSchemaObjectInfo(name: "products", schema: "public",
                                                       type: .table, columns: [idCol, nameCol, priceCol])

        let publicSchema = EchoSenseSchemaInfo(name: "public", objects: [usersTable, ordersTable, productsTable])

        // Add a second schema
        let auditTable = EchoSenseSchemaObjectInfo(name: "audit_log", schema: "audit",
                                                    type: .table, columns: [idCol, nameCol, createdAtCol])
        let auditSchema = EchoSenseSchemaInfo(name: "audit", objects: [auditTable])

        // System schemas for visibility tests
        let pgCatalogTable = EchoSenseSchemaObjectInfo(name: "pg_class", schema: "pg_catalog",
                                                        type: .table, columns: [idCol, nameCol])
        let pgCatalogSchema = EchoSenseSchemaInfo(name: "pg_catalog", objects: [pgCatalogTable])

        let sysTable = EchoSenseSchemaObjectInfo(name: "sysobjects", schema: "sys",
                                                  type: .table, columns: [idCol, nameCol])
        let sysSchema = EchoSenseSchemaInfo(name: "sys", objects: [sysTable])

        let infoSchemaTable = EchoSenseSchemaObjectInfo(name: "tables", schema: "information_schema",
                                                         type: .table, columns: [idCol, nameCol])
        let infoSchema = EchoSenseSchemaInfo(name: "information_schema", objects: [infoSchemaTable])

        // dbo schema for MSSQL
        let dboTable = EchoSenseSchemaObjectInfo(name: "customers", schema: "dbo",
                                                  type: .table, columns: [idCol, nameCol, emailCol])
        let dboSchema = EchoSenseSchemaInfo(name: "dbo", objects: [dboTable])

        let database = EchoSenseDatabaseInfo(name: "testdb",
                                              schemas: [publicSchema, auditSchema,
                                                        pgCatalogSchema, sysSchema, infoSchema, dboSchema])
        return EchoSenseDatabaseStructure(databases: [database])
    }

    private func makeEngine(dialect: EchoSenseDatabaseType,
                             defaultSchema: String? = nil) -> SQLAutoCompletionEngine {
        let engine = SQLAutoCompletionEngine()
        let schema = defaultSchema ?? (dialect == .microsoftSQL ? "dbo" : "public")
        let context = SQLEditorCompletionContext(databaseType: dialect,
                                                  selectedDatabase: "testdb",
                                                  defaultSchema: schema,
                                                  structure: makeStructure())
        engine.updateContext(context)
        engine.updateAggressiveness(.eager)
        engine.updateHistoryPreference(includeHistory: false)
        return engine
    }

    private func allSuggestions(from result: SQLAutoCompletionResult) -> [SQLAutoCompletionSuggestion] {
        result.sections.flatMap(\.suggestions)
    }

    // MARK: - PostgreSQL Specifics

    @Test func postgresReturningKeyword() {
        let engine = makeEngine(dialect: .postgresql)
        let text = "INSERT INTO users (name) VALUES ('test') "
        let query = SQLAutoCompletionQuery(token: "re", prefix: "re", pathComponents: [],
                                            replacementRange: NSRange(location: text.count, length: 0),
                                            precedingKeyword: nil, precedingCharacter: nil,
                                            focusTable: nil, tablesInScope: [], clause: .values)

        let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
        let keywords = allSuggestions(from: result).filter { $0.kind == .keyword }.map { $0.title.lowercased() }
        #expect(keywords.contains("returning"), "PG should suggest RETURNING")
    }

    @Test func postgresIlikeKeyword() {
        let engine = makeEngine(dialect: .postgresql)
        let usersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "users", alias: nil)
        let text = "SELECT * FROM users WHERE name "
        let query = SQLAutoCompletionQuery(token: "il", prefix: "il", pathComponents: [],
                                            replacementRange: NSRange(location: text.count, length: 0),
                                            precedingKeyword: nil, precedingCharacter: nil,
                                            focusTable: usersFocus,
                                            tablesInScope: [usersFocus], clause: .whereClause)

        let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
        let keywords = allSuggestions(from: result).filter { $0.kind == .keyword }.map { $0.title.lowercased() }
        #expect(keywords.contains("ilike"), "PG should suggest ILIKE")
    }

    @Test func postgresFunctions() {
        let engine = makeEngine(dialect: .postgresql)
        let text = "SELECT now"
        let query = SQLAutoCompletionQuery(token: "now", prefix: "now", pathComponents: [],
                                            replacementRange: NSRange(location: 7, length: 3),
                                            precedingKeyword: "select", precedingCharacter: nil,
                                            focusTable: nil, tablesInScope: [], clause: .selectList)

        let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
        let funcs = allSuggestions(from: result).filter { $0.kind == .function }.map { $0.title.uppercased() }
        #expect(funcs.contains("NOW"), "PG should suggest NOW()")
    }

    @Test func postgresWindowFunctions() {
        let engine = makeEngine(dialect: .postgresql)
        let text = "SELECT row"
        let query = SQLAutoCompletionQuery(token: "row", prefix: "row", pathComponents: [],
                                            replacementRange: NSRange(location: 7, length: 3),
                                            precedingKeyword: "select", precedingCharacter: nil,
                                            focusTable: nil, tablesInScope: [], clause: .selectList)

        let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
        let funcs = allSuggestions(from: result).filter { $0.kind == .function }.map { $0.title.uppercased() }
        #expect(funcs.contains("ROW_NUMBER"), "PG should suggest ROW_NUMBER")
    }

    @Test func postgresStringAgg() {
        let engine = makeEngine(dialect: .postgresql)
        let text = "SELECT string"
        let query = SQLAutoCompletionQuery(token: "string", prefix: "string", pathComponents: [],
                                            replacementRange: NSRange(location: 7, length: 6),
                                            precedingKeyword: "select", precedingCharacter: nil,
                                            focusTable: nil, tablesInScope: [], clause: .selectList)

        let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
        let funcs = allSuggestions(from: result).filter { $0.kind == .function }.map { $0.title.uppercased() }
        #expect(funcs.contains("STRING_AGG"), "PG should suggest STRING_AGG")
    }

    @Test func postgresArrayFunctions() {
        let engine = makeEngine(dialect: .postgresql)
        let text = "SELECT unnest"
        let query = SQLAutoCompletionQuery(token: "unnest", prefix: "unnest", pathComponents: [],
                                            replacementRange: NSRange(location: 7, length: 6),
                                            precedingKeyword: "select", precedingCharacter: nil,
                                            focusTable: nil, tablesInScope: [], clause: .selectList)

        let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
        let funcs = allSuggestions(from: result).filter { $0.kind == .function }.map { $0.title.uppercased() }
        #expect(funcs.contains("UNNEST"), "PG should suggest UNNEST")
    }

    @Test func postgresSchemaQualifiedFrom() {
        let engine = makeEngine(dialect: .postgresql)
        let text = "SELECT * FROM audit."
        let query = SQLAutoCompletionQuery(token: "audit.", prefix: "", pathComponents: ["audit"],
                                            replacementRange: NSRange(location: 14, length: 6),
                                            precedingKeyword: "from", precedingCharacter: nil,
                                            focusTable: nil, tablesInScope: [], clause: .from)

        let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
        let tables = allSuggestions(from: result).filter { $0.kind == .table }.map(\.title)
        #expect(tables.contains("audit_log"), "Schema-qualified lookup should find audit.audit_log")
    }

    // MARK: - MSSQL Specifics

    @Test func mssqlTopKeyword() {
        let engine = makeEngine(dialect: .microsoftSQL)
        let text = "SELECT "
        let query = SQLAutoCompletionQuery(token: "to", prefix: "to", pathComponents: [],
                                            replacementRange: NSRange(location: text.count, length: 0),
                                            precedingKeyword: "select", precedingCharacter: nil,
                                            focusTable: nil, tablesInScope: [], clause: .selectList)

        let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
        let keywords = allSuggestions(from: result).filter { $0.kind == .keyword }.map { $0.title.lowercased() }
        #expect(keywords.contains("top"), "MSSQL should suggest TOP")
    }

    @Test func mssqlCrossApplyKeyword() {
        let engine = makeEngine(dialect: .microsoftSQL)
        let usersFocus = SQLAutoCompletionTableFocus(schema: "dbo", name: "users", alias: nil)
        let text = "SELECT * FROM users "
        let query = SQLAutoCompletionQuery(token: "cr", prefix: "cr", pathComponents: [],
                                            replacementRange: NSRange(location: text.count, length: 0),
                                            precedingKeyword: "from", precedingCharacter: nil,
                                            focusTable: usersFocus,
                                            tablesInScope: [usersFocus], clause: .from)

        let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
        let keywords = allSuggestions(from: result).filter { $0.kind == .keyword }.map { $0.title.lowercased() }
        #expect(keywords.contains("cross apply"), "MSSQL should suggest CROSS APPLY")
    }

    @Test func mssqlJsonFunctions() {
        let engine = makeEngine(dialect: .microsoftSQL)
        let text = "SELECT json"
        let query = SQLAutoCompletionQuery(token: "json", prefix: "json", pathComponents: [],
                                            replacementRange: NSRange(location: 7, length: 4),
                                            precedingKeyword: "select", precedingCharacter: nil,
                                            focusTable: nil, tablesInScope: [], clause: .selectList)

        let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
        let funcs = allSuggestions(from: result).filter { $0.kind == .function }.map { $0.title.uppercased() }
        #expect(funcs.contains("JSON_VALUE"), "MSSQL should suggest JSON_VALUE")
        #expect(funcs.contains("JSON_QUERY"), "MSSQL should suggest JSON_QUERY")
    }

    @Test func mssqlNullHandlingFunctions() {
        let engine = makeEngine(dialect: .microsoftSQL)
        let text = "SELECT isn"
        let query = SQLAutoCompletionQuery(token: "isn", prefix: "isn", pathComponents: [],
                                            replacementRange: NSRange(location: 7, length: 3),
                                            precedingKeyword: "select", precedingCharacter: nil,
                                            focusTable: nil, tablesInScope: [], clause: .selectList)

        let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
        let funcs = allSuggestions(from: result).filter { $0.kind == .function }.map { $0.title.uppercased() }
        #expect(funcs.contains("ISNULL"), "MSSQL should suggest ISNULL")
    }

    @Test func mssqlConversionFunctions() {
        let engine = makeEngine(dialect: .microsoftSQL)
        let text = "SELECT conv"
        let query = SQLAutoCompletionQuery(token: "conv", prefix: "conv", pathComponents: [],
                                            replacementRange: NSRange(location: 7, length: 4),
                                            precedingKeyword: "select", precedingCharacter: nil,
                                            focusTable: nil, tablesInScope: [], clause: .selectList)

        let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
        let funcs = allSuggestions(from: result).filter { $0.kind == .function }.map { $0.title.uppercased() }
        #expect(funcs.contains("CONVERT"), "MSSQL should suggest CONVERT")
    }

    @Test func mssqlSuggestsTablesFromDbo() {
        let engine = makeEngine(dialect: .microsoftSQL, defaultSchema: "dbo")
        let text = "SELECT * FROM "
        let query = SQLAutoCompletionQuery(token: "", prefix: "", pathComponents: [],
                                            replacementRange: NSRange(location: text.count, length: 0),
                                            precedingKeyword: "from", precedingCharacter: nil,
                                            focusTable: nil, tablesInScope: [], clause: .from)

        let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
        let tables = allSuggestions(from: result).filter { $0.kind == .table }.map(\.title)
        #expect(tables.contains("customers"), "MSSQL should suggest dbo tables")
    }

    // MARK: - MySQL Specifics

    @Test func mysqlSuggestsTables() {
        let engine = makeEngine(dialect: .mysql)
        let text = "SELECT * FROM "
        let query = SQLAutoCompletionQuery(token: "", prefix: "", pathComponents: [],
                                            replacementRange: NSRange(location: text.count, length: 0),
                                            precedingKeyword: "from", precedingCharacter: nil,
                                            focusTable: nil, tablesInScope: [], clause: .from)

        let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
        let tables = allSuggestions(from: result).filter { $0.kind == .table }.map(\.title)
        #expect(tables.contains("users"), "MySQL should suggest tables")
    }

    @Test func mysqlFunctions() {
        let engine = makeEngine(dialect: .mysql)
        let text = "SELECT ifn"
        let query = SQLAutoCompletionQuery(token: "ifn", prefix: "ifn", pathComponents: [],
                                            replacementRange: NSRange(location: 7, length: 3),
                                            precedingKeyword: "select", precedingCharacter: nil,
                                            focusTable: nil, tablesInScope: [], clause: .selectList)

        let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
        let funcs = allSuggestions(from: result).filter { $0.kind == .function }.map { $0.title.uppercased() }
        #expect(funcs.contains("IFNULL"), "MySQL should suggest IFNULL")
    }

    @Test func mysqlGroupConcat() {
        let engine = makeEngine(dialect: .mysql)
        let text = "SELECT group_c"
        let query = SQLAutoCompletionQuery(token: "group_c", prefix: "group_c", pathComponents: [],
                                            replacementRange: NSRange(location: 7, length: 7),
                                            precedingKeyword: "select", precedingCharacter: nil,
                                            focusTable: nil, tablesInScope: [], clause: .selectList)

        let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
        let funcs = allSuggestions(from: result).filter { $0.kind == .function }.map { $0.title.uppercased() }
        #expect(funcs.contains("GROUP_CONCAT"), "MySQL should suggest GROUP_CONCAT")
    }

    // MARK: - SQLite Specifics

    @Test func sqliteSuggestsTables() {
        let engine = makeEngine(dialect: .sqlite)
        let text = "SELECT * FROM "
        let query = SQLAutoCompletionQuery(token: "", prefix: "", pathComponents: [],
                                            replacementRange: NSRange(location: text.count, length: 0),
                                            precedingKeyword: "from", precedingCharacter: nil,
                                            focusTable: nil, tablesInScope: [], clause: .from)

        let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
        let tables = allSuggestions(from: result).filter { $0.kind == .table }.map(\.title)
        #expect(tables.contains("users"), "SQLite should suggest tables")
    }

    @Test func sqliteFunctions() {
        let engine = makeEngine(dialect: .sqlite)
        let text = "SELECT typeof"
        let query = SQLAutoCompletionQuery(token: "typeof", prefix: "typeof", pathComponents: [],
                                            replacementRange: NSRange(location: 7, length: 6),
                                            precedingKeyword: "select", precedingCharacter: nil,
                                            focusTable: nil, tablesInScope: [], clause: .selectList)

        let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
        let funcs = allSuggestions(from: result).filter { $0.kind == .function }.map { $0.title.uppercased() }
        #expect(funcs.contains("TYPEOF"), "SQLite should suggest TYPEOF")
    }

    @Test func sqliteDateFunctions() {
        let engine = makeEngine(dialect: .sqlite)
        let text = "SELECT strftime"
        let query = SQLAutoCompletionQuery(token: "strftime", prefix: "strftime", pathComponents: [],
                                            replacementRange: NSRange(location: 7, length: 8),
                                            precedingKeyword: "select", precedingCharacter: nil,
                                            focusTable: nil, tablesInScope: [], clause: .selectList)

        let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
        let funcs = allSuggestions(from: result).filter { $0.kind == .function }.map { $0.title.uppercased() }
        #expect(funcs.contains("STRFTIME"), "SQLite should suggest STRFTIME")
    }

    // MARK: - Cross-Dialect Consistency

    @Test func allDialectsSuggestBasicAggregateFunctions() {
        for dialect: EchoSenseDatabaseType in [.postgresql, .microsoftSQL, .mysql, .sqlite] {
            let engine = makeEngine(dialect: dialect)
            let text = "SELECT coun"
            let query = SQLAutoCompletionQuery(token: "coun", prefix: "coun", pathComponents: [],
                                                replacementRange: NSRange(location: 7, length: 4),
                                                precedingKeyword: "select", precedingCharacter: nil,
                                                focusTable: nil, tablesInScope: [], clause: .selectList)

            let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
            let funcs = allSuggestions(from: result).filter { $0.kind == .function }.map { $0.title.uppercased() }
            #expect(funcs.contains("COUNT"), "All dialects should suggest COUNT — failed for \(dialect)")
        }
    }

    @Test func allDialectsSuggestWindowFunctions() {
        for dialect: EchoSenseDatabaseType in [.postgresql, .microsoftSQL, .mysql, .sqlite] {
            let engine = makeEngine(dialect: dialect)
            let text = "SELECT row_n"
            let query = SQLAutoCompletionQuery(token: "row_n", prefix: "row_n", pathComponents: [],
                                                replacementRange: NSRange(location: 7, length: 5),
                                                precedingKeyword: "select", precedingCharacter: nil,
                                                focusTable: nil, tablesInScope: [], clause: .selectList)

            let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
            let funcs = allSuggestions(from: result).filter { $0.kind == .function }.map { $0.title.uppercased() }
            #expect(funcs.contains("ROW_NUMBER"), "All dialects should suggest ROW_NUMBER — failed for \(dialect)")
        }
    }

    @Test func allDialectsSuggestCoalesce() {
        for dialect: EchoSenseDatabaseType in [.postgresql, .microsoftSQL, .mysql, .sqlite] {
            let engine = makeEngine(dialect: dialect)
            let text = "SELECT coal"
            let query = SQLAutoCompletionQuery(token: "coal", prefix: "coal", pathComponents: [],
                                                replacementRange: NSRange(location: 7, length: 4),
                                                precedingKeyword: "select", precedingCharacter: nil,
                                                focusTable: nil, tablesInScope: [], clause: .selectList)

            let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
            let funcs = allSuggestions(from: result).filter { $0.kind == .function }.map { $0.title.uppercased() }
            #expect(funcs.contains("COALESCE"), "All dialects should suggest COALESCE — failed for \(dialect)")
        }
    }

    // MARK: - Dialect-Specific Functions NOT in Other Dialects

    @Test func isnullOnlyInMSSQL() {
        let builtInFunctionsMSSQL = SQLAutoCompletionEngine.builtInFunctions(for: .microsoftSQL)
        let builtInFunctionsPG = SQLAutoCompletionEngine.builtInFunctions(for: .postgresql)
        let builtInFunctionsMySQL = SQLAutoCompletionEngine.builtInFunctions(for: .mysql)

        #expect(builtInFunctionsMSSQL.contains("ISNULL"), "MSSQL should have ISNULL")
        #expect(!builtInFunctionsPG.contains("ISNULL"), "PG should NOT have ISNULL")
        #expect(!builtInFunctionsMySQL.contains("ISNULL"), "MySQL should NOT have ISNULL")
    }

    @Test func ifnullOnlyInMySQLAndSQLite() {
        let builtInMySQL = SQLAutoCompletionEngine.builtInFunctions(for: .mysql)
        let builtInSQLite = SQLAutoCompletionEngine.builtInFunctions(for: .sqlite)
        let builtInPG = SQLAutoCompletionEngine.builtInFunctions(for: .postgresql)
        let builtInMSSQL = SQLAutoCompletionEngine.builtInFunctions(for: .microsoftSQL)

        #expect(builtInMySQL.contains("IFNULL"), "MySQL should have IFNULL")
        #expect(builtInSQLite.contains("IFNULL"), "SQLite should have IFNULL")
        #expect(!builtInPG.contains("IFNULL"), "PG should NOT have IFNULL")
        #expect(!builtInMSSQL.contains("IFNULL"), "MSSQL should NOT have IFNULL")
    }

    @Test func unnestOnlyInPostgres() {
        let builtInPG = SQLAutoCompletionEngine.builtInFunctions(for: .postgresql)
        let builtInMSSQL = SQLAutoCompletionEngine.builtInFunctions(for: .microsoftSQL)
        let builtInMySQL = SQLAutoCompletionEngine.builtInFunctions(for: .mysql)
        let builtInSQLite = SQLAutoCompletionEngine.builtInFunctions(for: .sqlite)

        #expect(builtInPG.contains("UNNEST"), "PG should have UNNEST")
        #expect(!builtInMSSQL.contains("UNNEST"), "MSSQL should NOT have UNNEST")
        #expect(!builtInMySQL.contains("UNNEST"), "MySQL should NOT have UNNEST")
        #expect(!builtInSQLite.contains("UNNEST"), "SQLite should NOT have UNNEST")
    }

    // MARK: - BuiltIn Function Counts

    @Test func eachDialectHasReasonableFunctionCount() {
        for dialect: EchoSenseDatabaseType in [.postgresql, .microsoftSQL, .mysql, .sqlite] {
            let funcs = SQLAutoCompletionEngine.builtInFunctions(for: dialect)
            #expect(funcs.count > 20, "\(dialect) should have >20 built-in functions, has \(funcs.count)")
        }
    }

    @Test func noDuplicateBuiltInFunctions() {
        for dialect: EchoSenseDatabaseType in [.postgresql, .microsoftSQL, .mysql, .sqlite] {
            let funcs = SQLAutoCompletionEngine.builtInFunctions(for: dialect)
            let uniqueFuncs = Set(funcs)
            #expect(funcs.count == uniqueFuncs.count,
                    "\(dialect) has duplicate built-in functions: count \(funcs.count) vs unique \(uniqueFuncs.count)")
        }
    }
}
