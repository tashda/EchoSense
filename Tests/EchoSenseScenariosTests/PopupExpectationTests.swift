import EchoSense
import Testing
@testable import EchoSenseScenarios

/// Popup rules: the query as a scenario reads it, what blocks name there, and the checks they make.
@Suite("Popup rules")
struct PopupExpectationTests {
    private let structure = ScenarioSchemas.structure(id: ScenarioSchemas.specID, dialect: .postgresql)!
    private let mssql = ScenarioSchemas.structure(id: ScenarioSchemas.specID, dialect: .mssql)!

    private func read(_ sql: String, _ structure: EchoSenseDatabaseStructure? = nil) -> ScenarioContext {
        let scenario = CompletionScenario(id: "T", group: "g", title: "t", sql: sql)
        let (text, caret) = scenario.textAndCaret
        return ScenarioContextReader.read(text, caret: caret, structure: structure ?? self.structure, database: "mydb")
    }

    private func resolver(_ sql: String, dialect: ScenarioDialect = .postgresql) -> PopupResolver {
        let structure = dialect == .mssql ? mssql : self.structure
        return PopupResolver(context: read(sql, structure), structure: structure, dialect: dialect, database: "mydb")
    }

    @Test("Tables, aliases, the dot and what is typed")
    func readsTheQuery() {
        let join = read("SELECT * FROM users u JOIN orders o ON u.id = o.user_id WHERE u.na|")
        #expect(join.tables.map(\.label) == ["users (u)", "orders (o)"])
        #expect(join.dot == .init(kind: .alias, name: "u", table: "users"))
        #expect(join.typed == "na")
        #expect(read("SELECT * FROM us|").tables.isEmpty)
        #expect(read("SELECT * FROM analytics.|").dot?.kind == .schema)
        #expect(read("SELECT * FROM otherdb.|", mssql).dot?.kind == .database)
        #expect(read("SELECT * FROM otherdb.dbo.|", mssql).dot == .init(kind: .schema, name: "dbo", database: "otherdb"))
        #expect(read("SELECT * FROM users -- WHERE |").tables.map(\.name) == ["users"])
    }

    @Test("CTEs, subqueries, the changed table and the SELECT list")
    func readsTheRest() {
        #expect(read("WITH active(id, name) AS (SELECT id, name FROM users) SELECT | FROM active").derived["active"] == ["id", "name"])
        #expect(read("SELECT sub.| FROM (SELECT id AS user_id, name FROM users) sub").derived["sub"] == ["user_id", "name"])
        #expect(read("UPDATE users SET |").changedTable == "users")
        #expect(read("INSERT INTO users (|)").changedTable == "users")
        #expect(read("SELECT name, email FROM users ORDER BY |").selectList == ["name", "email"])
    }

    @Test("Blocks name kinds of things from places")
    func blocksResolve() {
        let join = resolver("SELECT * FROM users u JOIN |")
        #expect(join.items(PopupBlock(.objects, .linkedByForeignKey, kinds: ["table"]))?.map(\.name).sorted() == ["departments", "orders"])
        #expect(join.items(PopupBlock(.objects, .inQuery))?.map(\.name) == ["users"])
        let dot = resolver("SELECT u.| FROM users u")
        #expect(dot.items(PopupBlock(.columns, .beforeDot, keysOnly: true))?.map(\.name) == ["id", "department_id"])
        #expect(resolver("SELECT * FROM us|").items(PopupBlock(.objects, .defaultSchema, kinds: ["table"]), typed: true)?.map(\.name) == ["users"])
        #expect(dot.items(PopupBlock(.functions, .builtIn)) == nil)
        #expect(dot.describe(PopupBlock(.columns, .beforeDot)) == "Columns of `u` (users), before the dot")
    }

    @Test("Rows are judged group by group")
    func groupsAndRest() {
        let r = resolver("SELECT u.| FROM users u")
        let rule = PopupExpectation(groups: [PopupGroup(PopupBlock(.columns, .beforeDot, keysOnly: true)), PopupGroup(PopupBlock(.columns, .beforeDot))], rest: .none)
        let row = { (title: String, kind: String) in ScenarioActual.Row(title: title, kind: kind, insertText: title) }
        let good = [row("id", "column"), row("department_id", "column"), row("name", "column"), row("email", "column"), row("created_at", "column")]
        #expect(r.checks(rule, rows: good).allSatisfy { $0.passed })
        let swapped = [row("name", "column")] + good.filter { $0.title != "name" }
        #expect(r.checks(rule, rows: swapped).first { $0.id == "groups:order" }?.passed == false)
        let extra = good + [row("ABS", "function")]
        #expect(r.checks(rule, rows: extra).first { $0.id == "rest" }?.problem == .offered(["ABS"]))
        let twice = good + [row("id", "column")]
        #expect(r.checks(rule, rows: twice).first { $0.id == "repeats" }?.problem == .offered(["id"]))
    }

    @Test("Scenarios with popup rules pass and fail for the right reasons")
    func realScenarios() throws {
        let library = try ScenarioLibrary.bundled()
        func failing(_ id: String) throws -> [String] {
            let scenario = try #require(library.scenario(id: id))
            #expect(scenario.popup != nil, "\(id) has a popup rule")
            return CompletionScenarioRunner().run(scenario).checks.filter { !$0.passed }.map(\.id)
        }
        #expect(try failing("SPEC-2.2").isEmpty)
        #expect(try failing("FN-002").isEmpty)
        #expect(try failing("SPEC-9.2") == ["rest"])
        #expect(try failing("SPEC-9.3") == ["rest"])
        #expect(try failing("SPEC-3.3") == ["repeats"])
        #expect(try failing("SPEC-11.1") == ["group:2:order"])
    }
}
