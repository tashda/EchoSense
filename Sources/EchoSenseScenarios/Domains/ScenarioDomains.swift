import EchoSense
import Foundation

/// Every domain, in the order the lab lists them.
public enum ScenarioDomains {
    public static let all: [ScenarioDomain] = [
        statements, statementAtCaret, goBatches, sqlcmd,
        errorLine, runNote, connectionLoss, tablePreview, gridSelection,
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
        summary: "What the results footer says about the selected cells: how many, the sum and the average.",
        inputLabel: "One cell per line; a line holding only ∅ is NULL. Option: cellCount (when more cells are selected than listed)",
        expectedLabel: "The footer text"
    ) { scenario in
        let cells: [String?] = scenario.input.components(separatedBy: "\n").map { $0 == "∅" ? nil : $0 }
        let count = Int(scenario.options["cellCount"] ?? "") ?? cells.count
        return [GridSelectionSummary.summarize(cells, cellCount: count).text(locale: fixedLocale)]
    }
}
