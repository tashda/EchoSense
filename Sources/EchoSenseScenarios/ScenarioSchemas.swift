import EchoSense
import Foundation

/// The schemas scenarios run against. `spec` is the test schema of `AUTOCOMPLETE_SPEC.md`.
public enum ScenarioSchemas {
    public static let specID = "spec"
    public static let shopID = "shop"
    public static let ids = [specID, shopID]

    public static func structure(id: String, dialect: ScenarioDialect) -> EchoSenseDatabaseStructure? {
        switch id {
        case specID: spec(dialect: dialect)
        case shopID: shop(dialect: dialect)
        default: nil
        }
    }

    public static func defaultSchema(for dialect: ScenarioDialect) -> String? {
        switch dialect { case .postgresql: "public"; case .mssql: "dbo"; case .mysql, .sqlite: nil }
    }

    public static func databaseName(id: String) -> String { id == shopID ? "shop" : "mydb" }

    private static func column(_ name: String, _ type: String, pk: Bool = false, nullable: Bool = true,
                               references: (String, String, String)? = nil) -> EchoSenseColumnInfo {
        EchoSenseColumnInfo(
            name: name, dataType: type, isPrimaryKey: pk, isNullable: nullable && !pk,
            foreignKey: references.map {
                EchoSenseForeignKeyReference(constraintName: "fk_\(name)", referencedSchema: $0.0, referencedTable: $0.1, referencedColumn: $0.2)
            })
    }

    /// users, orders, products, categories, departments, the view active_users, the materialized
    /// view user_stats and the schema analytics (events, metrics), as in the spec.
    static func spec(dialect: ScenarioDialect) -> EchoSenseDatabaseStructure {
        let main = defaultSchema(for: dialect) ?? "main"
        let idType = dialect == .mssql ? "int identity" : "serial"
        func id() -> EchoSenseColumnInfo { column("id", idType, pk: true) }
        let departments = EchoSenseSchemaObjectInfo(name: "departments", schema: main, type: .table,
            columns: [id(), column("name", "text"), column("budget", "numeric")])
        let users = EchoSenseSchemaObjectInfo(name: "users", schema: main, type: .table, columns: [
            id(), column("name", "text"), column("email", "text"), column("created_at", "timestamp"),
            column("department_id", "integer", references: (main, "departments", "id"))])
        let orders = EchoSenseSchemaObjectInfo(name: "orders", schema: main, type: .table, columns: [
            id(), column("user_id", "integer", references: (main, "users", "id")), column("total", "numeric"),
            column("status", "text"), column("created_at", "timestamp")])
        let categories = EchoSenseSchemaObjectInfo(name: "categories", schema: main, type: .table,
            columns: [id(), column("name", "text"), column("description", "text")])
        let products = EchoSenseSchemaObjectInfo(name: "products", schema: main, type: .table, columns: [
            id(), column("name", "text"), column("price", "numeric"),
            column("category_id", "integer", references: (main, "categories", "id"))])
        let activeUsers = EchoSenseSchemaObjectInfo(name: "active_users", schema: main, type: .view,
            columns: [column("id", "integer"), column("name", "text"), column("email", "text")])
        var objects = [users, orders, products, categories, departments, activeUsers]
        if dialect == .postgresql {
            objects.append(EchoSenseSchemaObjectInfo(name: "user_stats", schema: main, type: .materializedView,
                columns: [column("user_id", "integer"), column("order_count", "integer"), column("total_spent", "numeric")]))
        }
        let events = EchoSenseSchemaObjectInfo(name: "events", schema: "analytics", type: .table, columns: [
            id(), column("user_id", "integer"), column("event_type", "text"), column("payload", "text"), column("created_at", "timestamp")])
        let metrics = EchoSenseSchemaObjectInfo(name: "metrics", schema: "analytics", type: .table, columns: [
            id(), column("name", "text"), column("value", "numeric"), column("recorded_at", "timestamp")])
        var schemas = [EchoSenseSchemaInfo(name: main, objects: objects)]
        if dialect == .postgresql || dialect == .mssql { schemas.append(EchoSenseSchemaInfo(name: "analytics", objects: [events, metrics])) }
        return EchoSenseDatabaseStructure(serverVersion: "scenario", databases: [EchoSenseDatabaseInfo(name: "mydb", schemas: schemas)])
    }

    /// The small sales database Echo Labs used for its first completion page.
    static func shop(dialect: ScenarioDialect) -> EchoSenseDatabaseStructure {
        let sales = "sales", hr = "hr"
        let customers = EchoSenseSchemaObjectInfo(name: "customers", schema: sales, type: .table, columns: [
            column("customer_id", "int", pk: true), column("name", "varchar(120)", nullable: false), column("email", "varchar(200)"),
            column("country", "varchar(2)"), column("created_at", "timestamp", nullable: false)])
        let orders = EchoSenseSchemaObjectInfo(name: "orders", schema: sales, type: .table, columns: [
            column("order_id", "int", pk: true), column("customer_id", "int", nullable: false, references: (sales, "customers", "customer_id")),
            column("status", "varchar(20)", nullable: false), column("total", "numeric(12,2)", nullable: false), column("ordered_at", "timestamp", nullable: false)])
        let items = EchoSenseSchemaObjectInfo(name: "order_items", schema: sales, type: .table, columns: [
            column("order_id", "int", pk: true, references: (sales, "orders", "order_id")), column("line", "int", pk: true),
            column("product_id", "int", nullable: false, references: (sales, "products", "product_id")), column("quantity", "int", nullable: false)])
        let products = EchoSenseSchemaObjectInfo(name: "products", schema: sales, type: .table, columns: [
            column("product_id", "int", pk: true), column("title", "varchar(160)", nullable: false), column("price", "numeric(10,2)", nullable: false)])
        let revenue = EchoSenseSchemaObjectInfo(name: "monthly_revenue", schema: sales, type: .view,
            columns: [column("month", "date"), column("revenue", "numeric(14,2)")])
        let employees = EchoSenseSchemaObjectInfo(name: "employees", schema: hr, type: .table, columns: [
            column("employee_id", "int", pk: true), column("full_name", "varchar(120)", nullable: false),
            column("manager_id", "int", references: (hr, "employees", "employee_id"))])
        return EchoSenseDatabaseStructure(serverVersion: "scenario", databases: [EchoSenseDatabaseInfo(name: "shop", schemas: [
            EchoSenseSchemaInfo(name: sales, objects: [customers, orders, items, products, revenue]),
            EchoSenseSchemaInfo(name: hr, objects: [employees])])])
    }
}
