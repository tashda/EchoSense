import Foundation

/// Generates dialect-specific SQL statements for table structure modifications.
public protocol SQLDialectGenerator: Sendable {
    func quoteIdentifier(_ name: String) -> String
    func qualifiedTable(schema: String, table: String) -> String
    func beginTransaction() -> String
    func commitTransaction() -> String
    func rollbackTransaction() -> String
    func dropColumn(table: String, column: String) -> String
    func renameColumn(table: String, from: String, to: String) -> String
    func addColumn(table: String, name: String, dataType: String, isNullable: Bool, defaultValue: String?, generatedExpression: String?, identity: (seed: Int, increment: Int, generation: String?)?, collation: String?) -> String
    func alterColumnType(table: String, column: String, newType: String, isNullable: Bool) -> String
    func alterColumnNullability(table: String, column: String, isNullable: Bool, currentType: String) -> String
    func alterColumnSetDefault(table: String, column: String, defaultValue: String) -> String
    func alterColumnDropDefault(table: String, column: String) -> String
    func addPrimaryKey(table: String, name: String, columns: [String], isDeferrable: Bool, isInitiallyDeferred: Bool) -> String
    func dropConstraint(table: String, name: String) -> String
    func createIndex(table: String, name: String, columns: [(name: String, sort: String)], includeColumns: [String], isUnique: Bool, filter: String?, indexType: String?) -> String
    func dropIndex(schema: String, name: String, table: String) -> String
    func addUniqueConstraint(table: String, name: String, columns: [String], isDeferrable: Bool, isInitiallyDeferred: Bool) -> String
    func addCheckConstraint(table: String, name: String, expression: String) -> String
    func addForeignKey(table: String, name: String, columns: [String], referencedSchema: String, referencedTable: String, referencedColumns: [String], onUpdate: String?, onDelete: String?, isDeferrable: Bool, isInitiallyDeferred: Bool) -> String
    func alterTableProperties(table: String, properties: [(key: String, value: String)]) -> [String]
}

extension SQLDialectGenerator {
    public func addColumn(table: String, name: String, dataType: String, isNullable: Bool, defaultValue: String?, generatedExpression: String?) -> String {
        addColumn(table: table, name: name, dataType: dataType, isNullable: isNullable, defaultValue: defaultValue, generatedExpression: generatedExpression, identity: nil, collation: nil)
    }

    public func addPrimaryKey(table: String, name: String, columns: [String]) -> String {
        addPrimaryKey(table: table, name: name, columns: columns, isDeferrable: false, isInitiallyDeferred: false)
    }

    public func createIndex(table: String, name: String, columns: [(name: String, sort: String)], isUnique: Bool, filter: String?) -> String {
        createIndex(table: table, name: name, columns: columns, includeColumns: [], isUnique: isUnique, filter: filter, indexType: nil)
    }

    public func addUniqueConstraint(table: String, name: String, columns: [String]) -> String {
        addUniqueConstraint(table: table, name: name, columns: columns, isDeferrable: false, isInitiallyDeferred: false)
    }

    public func addForeignKey(table: String, name: String, columns: [String], referencedSchema: String, referencedTable: String, referencedColumns: [String], onUpdate: String?, onDelete: String?) -> String {
        addForeignKey(table: table, name: name, columns: columns, referencedSchema: referencedSchema, referencedTable: referencedTable, referencedColumns: referencedColumns, onUpdate: onUpdate, onDelete: onDelete, isDeferrable: false, isInitiallyDeferred: false)
    }
}

public struct PostgreSQLDialectGenerator: SQLDialectGenerator {
    public let schema: String
    public init(schema: String) { self.schema = schema }

    public func quoteIdentifier(_ name: String) -> String {
        "\"\(name.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    public func qualifiedTable(schema: String, table: String) -> String {
        "\(quoteIdentifier(schema)).\(quoteIdentifier(table))"
    }

    public func beginTransaction() -> String { "BEGIN;" }
    public func commitTransaction() -> String { "COMMIT;" }
    public func rollbackTransaction() -> String { "ROLLBACK;" }

    public func dropColumn(table: String, column: String) -> String {
        "ALTER TABLE \(table) DROP COLUMN \(quoteIdentifier(column)) CASCADE;"
    }

    public func renameColumn(table: String, from: String, to: String) -> String {
        "ALTER TABLE \(table) RENAME COLUMN \(quoteIdentifier(from)) TO \(quoteIdentifier(to));"
    }

    public func addColumn(table: String, name: String, dataType: String, isNullable: Bool, defaultValue: String?, generatedExpression: String?, identity: (seed: Int, increment: Int, generation: String?)?, collation: String?) -> String {
        var clause = "ALTER TABLE \(table) ADD COLUMN \(quoteIdentifier(name)) \(dataType)"
        if let collation, !collation.isEmpty { clause += " COLLATE \(quoteIdentifier(collation))" }
        if let identity {
            let generation = identity.generation ?? "ALWAYS"
            clause += " GENERATED \(generation) AS IDENTITY (START WITH \(identity.seed) INCREMENT BY \(identity.increment))"
        }
        if !isNullable { clause += " NOT NULL" }
        if let expression = generatedExpression, !expression.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            clause += " GENERATED ALWAYS AS (\(expression)) STORED"
        } else if identity == nil, let defaultValue, !defaultValue.isEmpty {
            clause += " DEFAULT \(defaultValue)"
        }
        return clause + ";"
    }

    public func alterColumnType(table: String, column: String, newType: String, isNullable: Bool) -> String {
        "ALTER TABLE \(table) ALTER COLUMN \(quoteIdentifier(column)) TYPE \(newType);"
    }

    public func alterColumnNullability(table: String, column: String, isNullable: Bool, currentType: String) -> String {
        let clause = isNullable ? "DROP NOT NULL" : "SET NOT NULL"
        return "ALTER TABLE \(table) ALTER COLUMN \(quoteIdentifier(column)) \(clause);"
    }

    public func alterColumnSetDefault(table: String, column: String, defaultValue: String) -> String {
        "ALTER TABLE \(table) ALTER COLUMN \(quoteIdentifier(column)) SET DEFAULT \(defaultValue);"
    }

    public func alterColumnDropDefault(table: String, column: String) -> String {
        "ALTER TABLE \(table) ALTER COLUMN \(quoteIdentifier(column)) DROP DEFAULT;"
    }

    public func addPrimaryKey(table: String, name: String, columns: [String], isDeferrable: Bool, isInitiallyDeferred: Bool) -> String {
        let cols = columns.map(quoteIdentifier).joined(separator: ", ")
        var sql = "ALTER TABLE \(table) ADD CONSTRAINT \(quoteIdentifier(name)) PRIMARY KEY (\(cols))"
        sql += deferrableClause(isDeferrable: isDeferrable, isInitiallyDeferred: isInitiallyDeferred)
        return sql + ";"
    }

    public func dropConstraint(table: String, name: String) -> String {
        "ALTER TABLE \(table) DROP CONSTRAINT \(quoteIdentifier(name));"
    }

    public func createIndex(table: String, name: String, columns: [(name: String, sort: String)], includeColumns: [String], isUnique: Bool, filter: String?, indexType: String?) -> String {
        let columnsClause = columns.map { "\(quoteIdentifier($0.name)) \($0.sort)" }.joined(separator: ", ")
        var sql = "CREATE \(isUnique ? "UNIQUE " : "")INDEX \(quoteIdentifier(name)) ON \(table)"
        if let indexType, !indexType.isEmpty, indexType.lowercased() != "btree" {
            sql += " USING \(indexType.lowercased())"
        }
        sql += " (\(columnsClause))"
        if !includeColumns.isEmpty {
            sql += " INCLUDE (\(includeColumns.map(quoteIdentifier).joined(separator: ", ")))"
        }
        if let filter { sql += " WHERE \(filter)" }
        return sql + ";"
    }

    public func dropIndex(schema: String, name: String, table: String) -> String {
        "DROP INDEX IF EXISTS \(quoteIdentifier(schema)).\(quoteIdentifier(name));"
    }

    public func addUniqueConstraint(table: String, name: String, columns: [String], isDeferrable: Bool, isInitiallyDeferred: Bool) -> String {
        let cols = columns.map(quoteIdentifier).joined(separator: ", ")
        var sql = "ALTER TABLE \(table) ADD CONSTRAINT \(quoteIdentifier(name)) UNIQUE (\(cols))"
        sql += deferrableClause(isDeferrable: isDeferrable, isInitiallyDeferred: isInitiallyDeferred)
        return sql + ";"
    }

    public func addCheckConstraint(table: String, name: String, expression: String) -> String {
        "ALTER TABLE \(table) ADD CONSTRAINT \(quoteIdentifier(name)) CHECK (\(expression));"
    }

    public func addForeignKey(table: String, name: String, columns: [String], referencedSchema: String, referencedTable: String, referencedColumns: [String], onUpdate: String?, onDelete: String?, isDeferrable: Bool, isInitiallyDeferred: Bool) -> String {
        let columnsList = columns.map(quoteIdentifier).joined(separator: ", ")
        let refTable = qualifiedTable(schema: referencedSchema, table: referencedTable)
        let refCols = referencedColumns.map(quoteIdentifier).joined(separator: ", ")
        var sql = "ALTER TABLE \(table) ADD CONSTRAINT \(quoteIdentifier(name)) FOREIGN KEY (\(columnsList)) REFERENCES \(refTable) (\(refCols))"
        if let onUpdate, !onUpdate.isEmpty { sql += " ON UPDATE \(onUpdate)" }
        if let onDelete, !onDelete.isEmpty { sql += " ON DELETE \(onDelete)" }
        sql += deferrableClause(isDeferrable: isDeferrable, isInitiallyDeferred: isInitiallyDeferred)
        return sql + ";"
    }

    public func alterTableProperties(table: String, properties: [(key: String, value: String)]) -> [String] {
        guard !properties.isEmpty else { return [] }
        let pairs = properties.map { "\($0.key) = \($0.value)" }.joined(separator: ", ")
        return ["ALTER TABLE \(table) SET (\(pairs));"]
    }

    private func deferrableClause(isDeferrable: Bool, isInitiallyDeferred: Bool) -> String {
        guard isDeferrable else { return "" }
        return isInitiallyDeferred ? " DEFERRABLE INITIALLY DEFERRED" : " DEFERRABLE INITIALLY IMMEDIATE"
    }
}

public struct SQLServerDialectGenerator: SQLDialectGenerator {
    public let schema: String
    public let database: String
    public init(schema: String, database: String) { self.schema = schema; self.database = database }

    public func quoteIdentifier(_ name: String) -> String {
        "[\(name.replacingOccurrences(of: "]", with: "]]"))]"
    }

    /// Text inside a single-quoted T-SQL string: quotes are doubled.
    private static func literal(_ text: String) -> String {
        text.replacingOccurrences(of: "'", with: "''")
    }

    /// `[dbo].[orders]` → `orders`.
    private static func bareName(of qualifiedTable: String) -> String {
        let last = qualifiedTable.replacingOccurrences(of: "]]", with: "\u{1}").split(separator: ".").last.map(String.init) ?? qualifiedTable
        return last.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).replacingOccurrences(of: "\u{1}", with: "]")
    }

    public func qualifiedTable(schema: String, table: String) -> String {
        "\(quoteIdentifier(schema)).\(quoteIdentifier(table))"
    }

    public func beginTransaction() -> String { "BEGIN TRANSACTION;" }
    public func commitTransaction() -> String { "COMMIT TRANSACTION;" }
    public func rollbackTransaction() -> String { "ROLLBACK TRANSACTION;" }

    public func dropColumn(table: String, column: String) -> String {
        "ALTER TABLE \(table) DROP COLUMN \(quoteIdentifier(column));"
    }

    public func renameColumn(table: String, from: String, to: String) -> String {
        // SQL Server uses sp_rename for column renames
        // table here is already qualified like [schema].[table]
        let tableParts = Self.literal(table.replacingOccurrences(of: "[", with: "").replacingOccurrences(of: "]", with: ""))
        return "EXEC sp_rename '\(tableParts).\(Self.literal(from))', '\(Self.literal(to))', 'COLUMN';"
    }

    public func addColumn(table: String, name: String, dataType: String, isNullable: Bool, defaultValue: String?, generatedExpression: String?, identity: (seed: Int, increment: Int, generation: String?)?, collation: String?) -> String {
        var clause = "ALTER TABLE \(table) ADD \(quoteIdentifier(name)) "
        if let expression = generatedExpression, !expression.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            clause += "AS (\(expression)) PERSISTED"
        } else {
            clause += dataType
            if let collation, !collation.isEmpty { clause += " COLLATE \(collation)" }
            if let identity { clause += " IDENTITY(\(identity.seed), \(identity.increment))" }
            clause += isNullable ? " NULL" : " NOT NULL"
            if identity == nil, let defaultValue, !defaultValue.isEmpty {
                clause += " DEFAULT \(defaultValue)"
            }
        }
        return clause + ";"
    }

    public func alterColumnType(table: String, column: String, newType: String, isNullable: Bool) -> String {
        let nullClause = isNullable ? "NULL" : "NOT NULL"
        return "ALTER TABLE \(table) ALTER COLUMN \(quoteIdentifier(column)) \(newType) \(nullClause);"
    }

    public func alterColumnNullability(table: String, column: String, isNullable: Bool, currentType: String) -> String {
        let nullClause = isNullable ? "NULL" : "NOT NULL"
        return "ALTER TABLE \(table) ALTER COLUMN \(quoteIdentifier(column)) \(currentType) \(nullClause);"
    }

    public func alterColumnSetDefault(table: String, column: String, defaultValue: String) -> String {
        // Constraint names are unique per schema, so the table is part of the name.
        let constraintName = "DF_\(Self.bareName(of: table))_\(column)"
        return "ALTER TABLE \(table) ADD CONSTRAINT \(quoteIdentifier(constraintName)) DEFAULT \(defaultValue) FOR \(quoteIdentifier(column));"
    }

    public func alterColumnDropDefault(table: String, column: String) -> String {
        let tableParts = Self.literal(table.replacingOccurrences(of: "[", with: "").replacingOccurrences(of: "]", with: ""))
        let column = Self.literal(column)
        let parts = tableParts.split(separator: ".")
        let schemaName = parts.count > 1 ? String(parts[0]) : "dbo"
        let tableName = parts.count > 1 ? String(parts[1]) : tableParts
        return """
        DECLARE @constraint NVARCHAR(256); \
        SELECT @constraint = d.name FROM sys.default_constraints d \
        JOIN sys.columns c ON d.parent_column_id = c.column_id AND d.parent_object_id = c.object_id \
        WHERE d.parent_object_id = OBJECT_ID('\(schemaName).\(tableName)') AND c.name = '\(column)'; \
        IF @constraint IS NOT NULL EXEC('ALTER TABLE \(table) DROP CONSTRAINT ' + @constraint);
        """
    }

    public func addPrimaryKey(table: String, name: String, columns: [String], isDeferrable: Bool, isInitiallyDeferred: Bool) -> String {
        let cols = columns.map(quoteIdentifier).joined(separator: ", ")
        return "ALTER TABLE \(table) ADD CONSTRAINT \(quoteIdentifier(name)) PRIMARY KEY (\(cols));"
    }

    public func dropConstraint(table: String, name: String) -> String {
        "ALTER TABLE \(table) DROP CONSTRAINT \(quoteIdentifier(name));"
    }

    public func createIndex(table: String, name: String, columns: [(name: String, sort: String)], includeColumns: [String], isUnique: Bool, filter: String?, indexType: String?) -> String {
        let columnsClause = columns.map { "\(quoteIdentifier($0.name)) \($0.sort)" }.joined(separator: ", ")
        var sql = "CREATE \(isUnique ? "UNIQUE " : "")INDEX \(quoteIdentifier(name)) ON \(table) (\(columnsClause))"
        if !includeColumns.isEmpty {
            sql += " INCLUDE (\(includeColumns.map(quoteIdentifier).joined(separator: ", ")))"
        }
        if let filter { sql += " WHERE \(filter)" }
        return sql + ";"
    }

    public func dropIndex(schema: String, name: String, table: String) -> String {
        "DROP INDEX \(quoteIdentifier(name)) ON \(table);"
    }

    public func addUniqueConstraint(table: String, name: String, columns: [String], isDeferrable: Bool, isInitiallyDeferred: Bool) -> String {
        let cols = columns.map(quoteIdentifier).joined(separator: ", ")
        return "ALTER TABLE \(table) ADD CONSTRAINT \(quoteIdentifier(name)) UNIQUE (\(cols));"
    }

    public func addCheckConstraint(table: String, name: String, expression: String) -> String {
        "ALTER TABLE \(table) ADD CONSTRAINT \(quoteIdentifier(name)) CHECK (\(expression));"
    }

    public func addForeignKey(table: String, name: String, columns: [String], referencedSchema: String, referencedTable: String, referencedColumns: [String], onUpdate: String?, onDelete: String?, isDeferrable: Bool, isInitiallyDeferred: Bool) -> String {
        let columnsList = columns.map(quoteIdentifier).joined(separator: ", ")
        let refTable = qualifiedTable(schema: referencedSchema, table: referencedTable)
        let refCols = referencedColumns.map(quoteIdentifier).joined(separator: ", ")
        var sql = "ALTER TABLE \(table) ADD CONSTRAINT \(quoteIdentifier(name)) FOREIGN KEY (\(columnsList)) REFERENCES \(refTable) (\(refCols))"
        if let onUpdate, !onUpdate.isEmpty { sql += " ON UPDATE \(onUpdate)" }
        if let onDelete, !onDelete.isEmpty { sql += " ON DELETE \(onDelete)" }
        return sql + ";"
    }

    public func alterTableProperties(table: String, properties: [(key: String, value: String)]) -> [String] {
        // MSSQL uses different statements per property type
        var statements: [String] = []
        for (key, value) in properties {
            switch key {
            case "DATA_COMPRESSION":
                statements.append("ALTER TABLE \(table) REBUILD WITH (DATA_COMPRESSION = \(value));")
            case "LOCK_ESCALATION":
                statements.append("ALTER TABLE \(table) SET (LOCK_ESCALATION = \(value));")
            default:
                break
            }
        }
        return statements
    }
}

public struct MySQLDialectGenerator: SQLDialectGenerator {
    public let schema: String
    public init(schema: String) { self.schema = schema }

    public func quoteIdentifier(_ name: String) -> String {
        "`\(name.replacingOccurrences(of: "`", with: "``"))`"
    }

    public func qualifiedTable(schema: String, table: String) -> String {
        "\(quoteIdentifier(schema)).\(quoteIdentifier(table))"
    }

    public func beginTransaction() -> String { "START TRANSACTION;" }
    public func commitTransaction() -> String { "COMMIT;" }
    public func rollbackTransaction() -> String { "ROLLBACK;" }

    public func dropColumn(table: String, column: String) -> String {
        "ALTER TABLE \(table) DROP COLUMN \(quoteIdentifier(column));"
    }

    public func renameColumn(table: String, from: String, to: String) -> String {
        "ALTER TABLE \(table) RENAME COLUMN \(quoteIdentifier(from)) TO \(quoteIdentifier(to));"
    }

    public func addColumn(table: String, name: String, dataType: String, isNullable: Bool, defaultValue: String?, generatedExpression: String?, identity: (seed: Int, increment: Int, generation: String?)?, collation: String?) -> String {
        var clause = "ALTER TABLE \(table) ADD COLUMN \(quoteIdentifier(name)) \(dataType)"
        if let collation, !collation.isEmpty {
            clause += " COLLATE \(quoteIdentifier(collation))"
        }
        if !isNullable {
            clause += " NOT NULL"
        }
        if let expression = generatedExpression, !expression.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            clause += " GENERATED ALWAYS AS (\(expression)) STORED"
        } else {
            if let defaultValue, !defaultValue.isEmpty {
                clause += " DEFAULT \(defaultValue)"
            }
            if identity != nil {
                clause += " AUTO_INCREMENT"
            }
        }
        return clause + ";"
    }

    public func alterColumnType(table: String, column: String, newType: String, isNullable: Bool) -> String {
        let nullClause = isNullable ? "NULL" : "NOT NULL"
        return "ALTER TABLE \(table) MODIFY COLUMN \(quoteIdentifier(column)) \(newType) \(nullClause);"
    }

    public func alterColumnNullability(table: String, column: String, isNullable: Bool, currentType: String) -> String {
        let nullClause = isNullable ? "NULL" : "NOT NULL"
        return "ALTER TABLE \(table) MODIFY COLUMN \(quoteIdentifier(column)) \(currentType) \(nullClause);"
    }

    public func alterColumnSetDefault(table: String, column: String, defaultValue: String) -> String {
        "ALTER TABLE \(table) ALTER COLUMN \(quoteIdentifier(column)) SET DEFAULT \(defaultValue);"
    }

    public func alterColumnDropDefault(table: String, column: String) -> String {
        "ALTER TABLE \(table) ALTER COLUMN \(quoteIdentifier(column)) DROP DEFAULT;"
    }

    public func addPrimaryKey(table: String, name: String, columns: [String], isDeferrable: Bool, isInitiallyDeferred: Bool) -> String {
        let cols = columns.map(quoteIdentifier).joined(separator: ", ")
        return "ALTER TABLE \(table) ADD PRIMARY KEY (\(cols));"
    }

    public func dropConstraint(table: String, name: String) -> String {
        if name.uppercased() == "PRIMARY" {
            return "ALTER TABLE \(table) DROP PRIMARY KEY;"
        }
        return "ALTER TABLE \(table) DROP FOREIGN KEY \(quoteIdentifier(name));"
    }

    public func createIndex(table: String, name: String, columns: [(name: String, sort: String)], includeColumns: [String], isUnique: Bool, filter: String?, indexType: String?) -> String {
        let columnsClause = columns.map { "\(quoteIdentifier($0.name)) \($0.sort)" }.joined(separator: ", ")
        let normalizedType = indexType?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "btree"
        var sql: String
        switch normalizedType {
        case "fulltext":
            sql = "CREATE FULLTEXT INDEX \(quoteIdentifier(name)) ON \(table)"
        case "spatial":
            sql = "CREATE SPATIAL INDEX \(quoteIdentifier(name)) ON \(table)"
        default:
            sql = "CREATE \(isUnique ? "UNIQUE " : "")INDEX \(quoteIdentifier(name)) ON \(table)"
            if normalizedType != "btree" && !normalizedType.isEmpty {
                sql += " USING \(normalizedType.uppercased())"
            }
        }
        sql += " (\(columnsClause))"
        return sql + ";"
    }

    public func dropIndex(schema: String, name: String, table: String) -> String {
        "DROP INDEX \(quoteIdentifier(name)) ON \(table);"
    }

    public func addUniqueConstraint(table: String, name: String, columns: [String], isDeferrable: Bool, isInitiallyDeferred: Bool) -> String {
        let cols = columns.map(quoteIdentifier).joined(separator: ", ")
        return "ALTER TABLE \(table) ADD CONSTRAINT \(quoteIdentifier(name)) UNIQUE (\(cols));"
    }

    public func addCheckConstraint(table: String, name: String, expression: String) -> String {
        "ALTER TABLE \(table) ADD CONSTRAINT \(quoteIdentifier(name)) CHECK (\(expression));"
    }

    public func addForeignKey(table: String, name: String, columns: [String], referencedSchema: String, referencedTable: String, referencedColumns: [String], onUpdate: String?, onDelete: String?, isDeferrable: Bool, isInitiallyDeferred: Bool) -> String {
        let columnsList = columns.map(quoteIdentifier).joined(separator: ", ")
        let refTable = qualifiedTable(schema: referencedSchema, table: referencedTable)
        let refCols = referencedColumns.map(quoteIdentifier).joined(separator: ", ")
        var sql = "ALTER TABLE \(table) ADD CONSTRAINT \(quoteIdentifier(name)) FOREIGN KEY (\(columnsList)) REFERENCES \(refTable) (\(refCols))"
        if let onUpdate, !onUpdate.isEmpty { sql += " ON UPDATE \(onUpdate)" }
        if let onDelete, !onDelete.isEmpty { sql += " ON DELETE \(onDelete)" }
        return sql + ";"
    }

    public func alterTableProperties(table: String, properties: [(key: String, value: String)]) -> [String] {
        guard !properties.isEmpty else { return [] }

        var tableOptions: [String] = []
        var statements: [String] = []

        for (key, value) in properties {
            switch key.uppercased() {
            case "ENGINE", "AUTO_INCREMENT", "ROW_FORMAT", "COMMENT":
                tableOptions.append("\(key.uppercased()) = \(value)")
            case "CHARACTER SET":
                statements.append("ALTER TABLE \(table) CONVERT TO CHARACTER SET \(value);")
            case "COLLATE":
                statements.append("ALTER TABLE \(table) COLLATE = \(value);")
            default:
                continue
            }
        }

        if !tableOptions.isEmpty {
            statements.insert("ALTER TABLE \(table) \(tableOptions.joined(separator: ", "));", at: 0)
        }

        return statements
    }
}
