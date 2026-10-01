import EchoSense
import Foundation

/// Every domain, in the order the lab lists them.
public enum ScenarioDomains {
    public static let all: [ScenarioDomain] = [
        statements, statementAtCaret, goBatches, sqlcmd,
        errorLine, runNote, connectionLoss, tablePreview, gridSelection, jsonOutline, tableDDL,
    ]

    public static func domain(id: String) -> ScenarioDomain? { all.first { $0.id == id } }

    public static let statements = ScenarioDomain(
        id: "statements", title: "Statements",
        summary: "How a T-SQL script is cut into statements (strings, comments, BEGIN…END, GO).",
        inputLabel: "A script", expectedLabel: "One statement, as “Lline: text”"
    ) { scenario in
        TSQLStatementSplitter.split(scenario.input).map { "L\($0.lineNumber): \($0.text)" }
    }

    public static let statementAtCaret = ScenarioDomain(
        id: "statement-at-caret", title: "Statement at caret",
        summary: "Which statement Run Statement at Cursor sends for the caret position.",
        inputLabel: "A script with the caret marked", expectedLabel: "The statement, or “(none)”"
    ) { scenario in
        let (text, caret) = scenario.inputAndCaret
        return [SQLStatementAtCaret.statement(in: text, caret: caret)?.text ?? "(none)"]
    }

    public static let goBatches = ScenarioDomain(
        id: "go-batches", title: "GO batches",
        summary: "How a SQL Server script is cut at GO lines, and how often each batch runs.",
        inputLabel: "A script", expectedLabel: "One batch, as “×count: text”"
    ) { scenario in
        MSSQLBatchSplitter.split(scenario.input).batches.map { "×\($0.repeatCount): \($0.text)" }
    }

    public static let sqlcmd = ScenarioDomain(
        id: "sqlcmd", title: "SQLCMD",
        summary: "What :setvar, $(var) and other SQLCMD lines turn a script into before it runs.",
        inputLabel: "A script", expectedLabel: "One batch, then “warning: …” lines"
    ) { scenario in
        let result = SQLCMDPreprocessor.process(scenario.input)
        return result.batches.map { "batch: \($0)" } + result.warnings.map { "warning: \($0)" }
    }

    /// Numbers in scenarios are written for one locale, so the expected lines are the same on every Mac.
    static let fixedLocale = Locale(identifier: "en_US")

    // MARK: Results and messages

    public static let errorLine = ScenarioDomain(
        id: "error-line", title: "Error line",
        summary: "Which line of the script a database error message points at (SQL Server, Postgres, MySQL).",
        inputLabel: "The server's error message", expectedLabel: "The line number, or “(none)”"
    ) { scenario in
        [QueryErrorLocation.line(in: scenario.input).map(String.init) ?? "(none)"]
    }

    public static let runNote = ScenarioDomain(
        id: "run-note", title: "Run note",
        summary: "The short note shown after a statement ran: rows and time, an error, or a cancel.",
        inputLabel: "For an error: the message. Options: kind (success, failure, shortFailure, cancelled), rows, seconds, hasResults, rollback",
        expectedLabel: "The note's text, then “tooltip: …”"
    ) { scenario in
        let range: NSRange? = NSRange(location: 0, length: 1)
        let rows = Int(scenario.options["rows"] ?? "") ?? 0
        let seconds = Double(scenario.options["seconds"] ?? "")
        let note: QueryRunNote?
        switch scenario.options["kind"] ?? "success" {
        case "failure": note = QueryRunNote.failure(range: range, message: scenario.input)
        case "shortFailure": note = QueryRunNote.shortFailure(range: range, message: scenario.input)
        case "cancelled": note = QueryRunNote.cancelled(range: range, duration: seconds, rows: rows, locale: fixedLocale)
        default: note = QueryRunNote.success(range: range, rows: rows, hasResults: scenario.options["hasResults"] != "false", duration: seconds, locale: fixedLocale)
        }
        guard var note else { return ["(no note)"] }
        if scenario.options["rollback"] == "true" { note = note.needingRollback() }
        return [note.text, "tooltip: \(note.detail)"]
    }

    public static let connectionLoss = ScenarioDomain(
        id: "connection-loss", title: "Connection lost",
        summary: "What Echo says when a query tab's connection drops, reconnects or fails to.",
        inputLabel: "Options: kind (droppedWithTransaction, notification, droppedIdle, awaitingReconnect, reconnected, reconnectFailed), database, tab, reason",
        expectedLabel: "The message"
    ) { scenario in
        let database = scenario.options["database"] ?? "mydb"
        let tab = scenario.options["tab"] ?? "Query 1"
        switch scenario.options["kind"] ?? "droppedWithTransaction" {
        case "notification": return [QueryConnectionLossText.notification(tabTitle: tab, database: database)]
        case "droppedIdle": return [QueryConnectionLossText.droppedIdle(tabTitle: tab, database: database)]
        case "awaitingReconnect": return [QueryConnectionLossText.awaitingReconnect(database: database)]
        case "reconnected": return [QueryConnectionLossText.reconnected(database: database)]
        case "reconnectFailed": return [QueryConnectionLossText.reconnectFailed(database: database, reason: scenario.options["reason"] ?? "")]
        default: return [QueryConnectionLossText.droppedWithTransaction(database: database)]
        }
    }

    public static let tablePreview = ScenarioDomain(
        id: "table-preview", title: "Table preview",
        summary: "The first-rows query the Explorer's Data action puts in the editor, per database.",
        inputLabel: "schema.table (a dot inside a name cannot be written here; use the options schema and table). Option: dialect (postgresql, mssql, mysql, sqlite)",
        expectedLabel: "The query"
    ) { scenario in
        let parts = scenario.input.split(separator: ".", maxSplits: 1).map(String.init)
        let schema = scenario.options["schema"] ?? (parts.count == 2 ? parts[0] : "public")
        let table = scenario.options["table"] ?? (parts.last ?? "")
        let type: EchoSenseDatabaseType = switch scenario.options["dialect"] ?? "postgresql" {
        case "mssql": .microsoftSQL
        case "mysql": .mysql
        case "sqlite": .sqlite
        default: .postgresql
        }
        return [TablePreviewQuery.sql(schema: schema, table: table, databaseType: type)]
    }

    public static let gridSelection = ScenarioDomain(
        id: "grid-selection", title: "Grid selection",
        summary: "What the results footer says about the selected cells: the pill's count, then the popover's figures (round 41.2).",
        inputLabel: "One cell per line; a line holding only ∅ is NULL. Option: cellCount (when more cells are selected than listed)",
        expectedLabel: "The pill, then one line per figure: label, a space, the value"
    ) { scenario in
        let cells: [String?] = scenario.input.components(separatedBy: "\n").map { $0 == "∅" ? nil : $0 }
        let count = Int(scenario.options["cellCount"] ?? "") ?? cells.count
        let summary = GridSelectionSummary.summarize(cells, cellCount: count)
        return [summary.text(locale: fixedLocale)] + summary.figures(locale: fixedLocale).map { "\($0.label) \($0.value)" }
    }

    public static let jsonOutline = ScenarioDomain(
        id: "json-outline", title: "JSON viewer",
        summary: "How a JSON value is laid out in the inspector: each node's title, what it shows and the path you copy.",
        inputLabel: "The JSON text", expectedLabel: "One node: indent, title, “: ”, what it shows, two spaces, its path; or “(invalid)”"
    ) { scenario in
        guard let value = try? JsonValue.parse(from: scenario.input) else { return ["(invalid)"] }
        func lines(_ node: JsonOutlineNode, path: String, depth: Int) -> [String] {
            let nodePath = node.jsonPath(parentPath: path)
            var out = [String(repeating: "  ", count: depth) + "\(node.title): \(node.subtitle)  \(nodePath)"]
            for child in node.children { out += lines(child, path: nodePath, depth: depth + 1) }
            return out
        }
        return lines(value.toOutlineNode(), path: "$", depth: 0)
    }

    public static let tableDDL = ScenarioDomain(
        id: "table-ddl", title: "Table DDL",
        summary: "The statements the table editor writes for each change, per database.",
        inputLabel: "Not used. Options: dialect (postgresql, mssql, mysql), schema, table, op and the op's fields (column, to, type, nullable, default, expression, identity, collation, name, columns, include, unique, filter, indexType, refSchema, refTable, refColumns, onUpdate, onDelete, deferrable, deferred, properties)",
        expectedLabel: "One statement"
    ) { scenario in
        let o = scenario.options
        let dialect = o["dialect"] ?? "postgresql"
        let schema = o["schema"] ?? (dialect == "mssql" ? "dbo" : dialect == "mysql" ? "shop" : "public")
        let generator: SQLDialectGenerator = switch dialect {
        case "mssql": SQLServerDialectGenerator(schema: schema, database: "")
        case "mysql": MySQLDialectGenerator(schema: schema)
        default: PostgreSQLDialectGenerator(schema: schema)
        }
        let table = generator.qualifiedTable(schema: schema, table: o["table"] ?? "orders")
        func list(_ key: String) -> [String] {
            (o[key] ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        let column = o["column"] ?? "status"
        let name = o["name"] ?? "c1"
        let nullable = o["nullable"] != "false"
        let deferrable = o["deferrable"] == "true"
        let deferred = o["deferred"] == "true"
        switch o["op"] ?? "" {
        case "begin": return [generator.beginTransaction()]
        case "commit": return [generator.commitTransaction()]
        case "rollback": return [generator.rollbackTransaction()]
        case "dropColumn": return [generator.dropColumn(table: table, column: column)]
        case "renameColumn": return [generator.renameColumn(table: table, from: column, to: o["to"] ?? "state")]
        case "addColumn":
            let identity: (seed: Int, increment: Int, generation: String?)? = list("identity").isEmpty ? nil : {
                let parts = list("identity")
                return (Int(parts[0]) ?? 1, parts.count > 1 ? Int(parts[1]) ?? 1 : 1, parts.count > 2 ? parts[2] : nil)
            }()
            return [generator.addColumn(table: table, name: column, dataType: o["type"] ?? "text", isNullable: nullable,
                                        defaultValue: o["default"], generatedExpression: o["expression"], identity: identity, collation: o["collation"])]
        case "alterColumnType": return [generator.alterColumnType(table: table, column: column, newType: o["type"] ?? "bigint", isNullable: nullable)]
        case "alterColumnNullability": return [generator.alterColumnNullability(table: table, column: column, isNullable: nullable, currentType: o["type"] ?? "text")]
        case "setDefault": return [generator.alterColumnSetDefault(table: table, column: column, defaultValue: o["default"] ?? "0")]
        case "dropDefault": return [generator.alterColumnDropDefault(table: table, column: column)]
        case "addPrimaryKey": return [generator.addPrimaryKey(table: table, name: name, columns: list("columns"), isDeferrable: deferrable, isInitiallyDeferred: deferred)]
        case "dropConstraint": return [generator.dropConstraint(table: table, name: name)]
        case "createIndex":
            let columns = list("columns").map { entry -> (name: String, sort: String) in
                let parts = entry.split(separator: " ", maxSplits: 1).map(String.init)
                return (parts[0], parts.count > 1 ? parts[1] : "ASC")
            }
            return [generator.createIndex(table: table, name: name, columns: columns, includeColumns: list("include"),
                                          isUnique: o["unique"] == "true", filter: o["filter"], indexType: o["indexType"])]
        case "dropIndex": return [generator.dropIndex(schema: schema, name: name, table: table)]
        case "addUnique": return [generator.addUniqueConstraint(table: table, name: name, columns: list("columns"), isDeferrable: deferrable, isInitiallyDeferred: deferred)]
        case "addCheck": return [generator.addCheckConstraint(table: table, name: name, expression: o["expression"] ?? "true")]
        case "addForeignKey":
            return [generator.addForeignKey(table: table, name: name, columns: list("columns"), referencedSchema: o["refSchema"] ?? schema,
                                            referencedTable: o["refTable"] ?? "customers", referencedColumns: list("refColumns"),
                                            onUpdate: o["onUpdate"], onDelete: o["onDelete"], isDeferrable: deferrable, isInitiallyDeferred: deferred)]
        case "tableProperties":
            let pairs = list("properties").map { entry -> (key: String, value: String) in
                let parts = entry.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                return (parts[0], parts.count > 1 ? parts[1] : "")
            }
            return generator.alterTableProperties(table: table, properties: pairs)
        default: return ["(unknown op)"]
        }
    }
}
