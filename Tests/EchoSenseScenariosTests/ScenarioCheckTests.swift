import Testing
@testable import EchoSenseScenarios

/// The checks are the expectation in plain words; the verdict is built from them.
@Suite("Scenario checks")
struct ScenarioCheckTests {
    private func actual(_ titles: [String], insert: [String: String] = [:]) -> ScenarioActual {
        ScenarioActual(titles: titles, insertText: insert, kinds: [:], clause: "from", token: "", manualTitles: titles,
                       isMetadataLimited: false, engineTitles: titles, popupShown: !titles.isEmpty, triggerNote: "")
    }

    @Test("A missing item fails its own check and nothing else")
    func missingItem() {
        let expected = EchoSenseExpectation(outcome: .suggests, items: ["invoices", "customers"], order: .includes, excludes: ["users"])
        let checks = CompletionScenarioRunner.checks(expected, actual: actual(["customers"]), trigger: .typing)
        #expect(checks.map(\.statement) == ["opens the popup with suggestions", "offers `invoices`", "offers `customers`", "never offers `users`"])
        #expect(checks.filter { !$0.passed }.map(\.problem) == [.missing(["invoices"])])
    }

    @Test("A forbidden item is reported as unwanted")
    func unwantedItem() {
        let expected = EchoSenseExpectation(outcome: .suggests, items: ["id"], order: .includes, excludes: ["status"])
        let checks = CompletionScenarioRunner.checks(expected, actual: actual(["id", "status"]), trigger: .typing)
        #expect(checks.compactMap(\.problem) == [.unwanted(["status"])])
    }

    @Test("Exact order: extra items and a wrong order are separate checks")
    func exactOrder() {
        let expected = EchoSenseExpectation(outcome: .suggests, items: ["a", "b"], order: .exact)
        #expect(CompletionScenarioRunner.checks(expected, actual: actual(["b", "a"]), trigger: .typing).compactMap(\.problem) == [.wrongOrder])
        #expect(CompletionScenarioRunner.checks(expected, actual: actual(["a", "b", "c"]), trigger: .typing).compactMap(\.problem) == [.offered(["c"])])
        #expect(CompletionScenarioRunner.checks(expected, actual: actual(["a", "b"]), trigger: .typing).allSatisfy { $0.passed })
    }

    @Test("Insert text is checked per title")
    func insertText() {
        let expected = EchoSenseExpectation(outcome: .suggests, order: .includes, insertText: ["name": "u.name"])
        let checks = CompletionScenarioRunner.checks(expected, actual: actual(["name"], insert: ["name": "name"]), trigger: .typing)
        #expect(checks.compactMap(\.problem) == [.wrongInsert("name")])
    }

    @Test("Nothing expected, something offered")
    func nothingExpected() {
        let checks = CompletionScenarioRunner.checks(EchoSenseExpectation(outcome: .nothing), actual: actual(["x"]), trigger: .typing)
        #expect(checks.compactMap(\.problem) == [.offered(["x"]), .offered(["x"])])
    }

    @Test("Every scenario's verdict is exactly its failing checks", arguments: ScenarioSuite.all)
    func verdictMatchesChecks(_ scenario: CompletionScenario) {
        let result = CompletionScenarioRunner().run(scenario)
        guard result.actual != nil else { return }
        let failing = result.checks.filter { !$0.passed }
        #expect(result.isFailing == !failing.isEmpty, "\(scenario.id)")
        #expect(failing.allSatisfy { $0.failure != nil }, "\(scenario.id)")
        #expect((result.briefProblem == nil) == failing.isEmpty, "\(scenario.id)")
    }
}
