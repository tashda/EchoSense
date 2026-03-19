import Foundation
import Testing
@testable import EchoSense

// MARK: - Shared Spec Test Helpers

/// Namespace for spec test helpers to avoid collisions with private helpers in other test files.
enum SpecHelpers {

/// Builds the canonical spec test schema:
/// - Database "mydb"
/// - Schema "public" (default): users, orders, products, categories, departments, active_users (view), calculate_tax (function)
/// - Schema "analytics": events, metrics
static func makeSpecStructure() -> EchoSenseDatabaseStructure {
    // --- Reusable Columns ---
    let idCol = EchoSenseColumnInfo(name: "id", dataType: "integer", isPrimaryKey: true, isNullable: false)
    let nameCol = EchoSenseColumnInfo(name: "name", dataType: "text", isNullable: true)
    let emailCol = EchoSenseColumnInfo(name: "email", dataType: "text", isNullable: true)
    let createdAtCol = EchoSenseColumnInfo(name: "created_at", dataType: "timestamp", isNullable: true)
    let totalCol = EchoSenseColumnInfo(name: "total", dataType: "numeric", isNullable: true)
    let statusCol = EchoSenseColumnInfo(name: "status", dataType: "text", isNullable: true)
    let priceCol = EchoSenseColumnInfo(name: "price", dataType: "numeric", isNullable: true)
    let descriptionCol = EchoSenseColumnInfo(name: "description", dataType: "text", isNullable: true)
    let budgetCol = EchoSenseColumnInfo(name: "budget", dataType: "numeric", isNullable: true)

    // --- Foreign Keys ---
    let deptFk = EchoSenseForeignKeyReference(constraintName: "fk_users_dept",
                                               referencedSchema: "public",
                                               referencedTable: "departments",
                                               referencedColumn: "id")
    let userFk = EchoSenseForeignKeyReference(constraintName: "fk_orders_user",
                                               referencedSchema: "public",
                                               referencedTable: "users",
                                               referencedColumn: "id")
    let catFk = EchoSenseForeignKeyReference(constraintName: "fk_products_cat",
                                              referencedSchema: "public",
                                              referencedTable: "categories",
                                              referencedColumn: "id")

    let departmentIdCol = EchoSenseColumnInfo(name: "department_id", dataType: "integer",
                                               isPrimaryKey: false, isNullable: true, foreignKey: deptFk)
    let userIdCol = EchoSenseColumnInfo(name: "user_id", dataType: "integer",
                                         isPrimaryKey: false, isNullable: false, foreignKey: userFk)
    let categoryIdCol = EchoSenseColumnInfo(name: "category_id", dataType: "integer",
                                             isPrimaryKey: false, isNullable: true, foreignKey: catFk)

    // --- Public Schema Tables ---
    let usersTable = EchoSenseSchemaObjectInfo(name: "users", schema: "public", type: .table,
                                                columns: [idCol, nameCol, emailCol, createdAtCol, departmentIdCol])
    let ordersTable = EchoSenseSchemaObjectInfo(name: "orders", schema: "public", type: .table,
                                                 columns: [idCol, userIdCol, totalCol, statusCol, createdAtCol])
    let productsTable = EchoSenseSchemaObjectInfo(name: "products", schema: "public", type: .table,
                                                   columns: [idCol, nameCol, priceCol, categoryIdCol])
    let categoriesTable = EchoSenseSchemaObjectInfo(name: "categories", schema: "public", type: .table,
                                                     columns: [idCol, nameCol, descriptionCol])
    let departmentsTable = EchoSenseSchemaObjectInfo(name: "departments", schema: "public", type: .table,
                                                      columns: [idCol, nameCol, budgetCol])

    // --- Public Schema Views ---
    let activeUsersView = EchoSenseSchemaObjectInfo(name: "active_users", schema: "public", type: .view,
                                                     columns: [idCol, nameCol, emailCol])

    // --- Public Schema Functions ---
    let calcTaxFunc = EchoSenseSchemaObjectInfo(name: "calculate_tax", schema: "public", type: .function,
                                                 columns: [])

    // --- Analytics Schema ---
    let eventTypeCol = EchoSenseColumnInfo(name: "event_type", dataType: "text", isNullable: true)
    let payloadCol = EchoSenseColumnInfo(name: "payload", dataType: "jsonb", isNullable: true)
    let valueCol = EchoSenseColumnInfo(name: "value", dataType: "numeric", isNullable: true)
    let recordedAtCol = EchoSenseColumnInfo(name: "recorded_at", dataType: "timestamp", isNullable: true)
    let analyticsUserIdCol = EchoSenseColumnInfo(name: "user_id", dataType: "integer", isNullable: true)

    let eventsTable = EchoSenseSchemaObjectInfo(name: "events", schema: "analytics", type: .table,
                                                 columns: [idCol, analyticsUserIdCol, eventTypeCol, payloadCol, createdAtCol])
    let metricsTable = EchoSenseSchemaObjectInfo(name: "metrics", schema: "analytics", type: .table,
                                                  columns: [idCol, nameCol, valueCol, recordedAtCol])

    // --- Assemble ---
    let publicSchema = EchoSenseSchemaInfo(name: "public",
                                            objects: [usersTable, ordersTable, productsTable, categoriesTable,
                                                      departmentsTable, activeUsersView, calcTaxFunc])
    let analyticsSchema = EchoSenseSchemaInfo(name: "analytics",
                                              objects: [eventsTable, metricsTable])

    let database = EchoSenseDatabaseInfo(name: "mydb", schemas: [publicSchema, analyticsSchema])
    return EchoSenseDatabaseStructure(databases: [database])
}

static func makeSpecContext(dialect: EchoSenseDatabaseType = .postgresql) -> SQLEditorCompletionContext {
    SQLEditorCompletionContext(databaseType: dialect,
                               selectedDatabase: "mydb",
                               defaultSchema: "public",
                               structure: makeSpecStructure())
}

static func makeSpecEngine(dialect: EchoSenseDatabaseType = .postgresql) -> SQLAutoCompletionEngine {
    let engine = SQLAutoCompletionEngine()
    engine.updateContext(makeSpecContext(dialect: dialect))
    engine.updateHistoryPreference(includeHistory: false)
    return engine
}

static func allSuggestions(from result: SQLAutoCompletionResult) -> [SQLAutoCompletionSuggestion] {
    result.sections.flatMap(\.suggestions)
}

static func suggestionTitles(from result: SQLAutoCompletionResult, kind: SQLAutoCompletionKind? = nil) -> [String] {
    let all = allSuggestions(from: result)
    if let kind {
        return all.filter { $0.kind == kind }.map(\.title)
    }
    return all.map(\.title)
}

static func suggestionKinds(from result: SQLAutoCompletionResult) -> Set<SQLAutoCompletionKind> {
    Set(allSuggestions(from: result).map(\.kind))
}

} // end enum SpecHelpers
