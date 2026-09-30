import Foundation
import Testing
@testable import EchoSenseScenarios

/// Every scenario in `Sources/EchoSenseScenarios/Scenarios` is a test. A scenario that fails today is
/// listed as a known issue in its file; it must keep failing until someone fixes it and removes the flag.
enum ScenarioSuite {
    static let all: [CompletionScenario] = (try? ScenarioLibrary.bundled().scenarios) ?? []
}

@Test("The scenario files load and every id is unique")
func scenarioFilesLoad() throws {
    _ = try ScenarioLibrary.bundled()
}

@Test("Scenario", arguments: ScenarioSuite.all)
func scenarioBehavesAsExpected(_ scenario: CompletionScenario) {
    let result = CompletionScenarioRunner().run(scenario)
    if let issue = scenario.knownIssue {
        withKnownIssue("\(scenario.id): \(issue)") {
            if result.isFailing { Issue.record("\(result.failureReasons.joined(separator: " "))") }
        }
        return
    }
    if result.isFailing { Issue.record("\(scenario.id) \(scenario.title): \(result.failureReasons.joined(separator: " "))") }
}
