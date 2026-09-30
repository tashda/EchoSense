import EchoSense
import Foundation

/// Every domain, in the order the lab lists them.
public enum ScenarioDomains {
    public static let all: [ScenarioDomain] = [
        statements, statementAtCaret, goBatches, sqlcmd,
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
}
