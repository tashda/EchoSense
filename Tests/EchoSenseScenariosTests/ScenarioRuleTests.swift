import Foundation
import Testing
@testable import EchoSenseScenarios

/// Shared rules add their checks to every scenario that follows them; comments carry the owner's feedback.
@Suite("Scenario rules and comments")
struct ScenarioRuleTests {
    private func actual(_ entries: [(String, String)]) -> ScenarioActual {
        let titles = entries.map(\.0)
        return ScenarioActual(titles: titles, insertText: [:], kinds: Dictionary(uniqueKeysWithValues: entries), clause: "select", token: "",
                              manualTitles: titles, isMetadataLimited: false, engineTitles: titles, popupShown: !titles.isEmpty, triggerNote: "")
    }

    @Test("A rule's forbidden titles and kinds are checks of their own")
    func forbidden() {
        let rule = ScenarioRule(id: "RULE-9", title: "t", excludes: ["users"], excludedKinds: ["database"])
        let checks = CompletionScenarioRunner.checks(rule, actual: actual([("mydb", "database"), ("id", "column")]))
        #expect(checks.map(\.statement) == ["never offers `users`", "never offers a database"])
        #expect(checks.compactMap(\.problem) == [.unwanted(["mydb"])])
        #expect(checks.allSatisfy { $0.rule == "RULE-9" })
    }

    @Test("Kind order: an earlier kind after a later one fails")
    func kindOrder() {
        let rule = ScenarioRule(id: "RULE-9", title: "t", kindOrder: ["column", "table", "keyword"])
        let good = CompletionScenarioRunner.checks(rule, actual: actual([("id", "column"), ("users", "table"), ("FROM", "keyword")]))
        #expect(good.allSatisfy { $0.passed })
        let bad = CompletionScenarioRunner.checks(rule, actual: actual([("id", "column"), ("FROM", "keyword"), ("users", "table")]))
        #expect(bad.compactMap(\.problem) == [.wrongOrder])
        #expect(bad.first?.failure?.contains("`users` (table) comes after `FROM` (keyword)") == true)
    }

    @Test("An order failure says where each expected item is")
    func orderFailureShowsRanks() {
        let expected = EchoSenseExpectation(outcome: .suggests, items: ["a", "b"], order: .leading)
        let checks = CompletionScenarioRunner.checks(expected, actual: actual([("b", "column"), ("x", "column"), ("a", "column")]), trigger: .typing)
        #expect(checks.first { $0.id == "first" }?.failure == "Expected these first, in this order: a, b. Now: a is #3, b is #1.")
    }

    @Test("A scenario that names a missing rule fails")
    func unknownRule() {
        let scenario = CompletionScenario(id: "T-1", group: "g", title: "t", sql: "SELECT | FROM users", rules: ["RULE-404"])
        let result = CompletionScenarioRunner(rules: []).run(scenario)
        #expect(result.isFailing)
        #expect(result.checks.contains { $0.rule == "RULE-404" && !$0.passed })
    }

    @Test("Every rule a scenario names exists")
    func rulesExist() throws {
        let rules = Set(ScenarioRuleLibrary.bundled.rules.map(\.id))
        for scenario in ScenarioSuite.all {
            for id in scenario.rules { #expect(rules.contains(id), "\(scenario.id) names \(id)") }
        }
    }

    @Test("Comments round-trip, and the owner's last word waits for the agent")
    func comments() throws {
        var scenario = CompletionScenario(id: "T-1", group: "g", title: "t", sql: "|")
        scenario.comments = [ScenarioComment(author: .owner, text: "Order matters", about: "first")]
        #expect(scenario.waitsForAgent)
        let decoded = try JSONDecoder().decode(CompletionScenario.self, from: JSONEncoder().encode(scenario))
        #expect(decoded.comments == scenario.comments)
        scenario.comments.append(ScenarioComment(author: .agent, text: "Fixed"))
        #expect(!scenario.waitsForAgent)
    }

    @Test("Ranks ignore identifier quoting")
    func ranks() {
        let result = actual([("\"name\"", "column"), ("id", "column")])
        #expect(result.rank(of: "name") == 1)
        #expect(result.rank(of: "id") == 2)
        #expect(result.rank(of: "nope") == nil)
    }
}
