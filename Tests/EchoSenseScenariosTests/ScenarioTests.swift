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

/// The other kinds of scenario (statements, GO batches, ...) under `DomainScenarios`.
enum DomainScenarioSuite {
    static let all: [DomainScenario] = (try? DomainLibrary.bundled().scenarios) ?? []
}

@Test("The domain scenario files load, every id is unique and every domain exists")
func domainScenarioFilesLoad() throws {
    let library = try DomainLibrary.bundled()
    #expect(!library.scenarios.isEmpty)
    for scenario in library.scenarios {
        #expect(ScenarioDomains.domain(id: scenario.domain) != nil, "\(scenario.id) names an unknown domain")
    }
}

@Test("Domain scenario", arguments: DomainScenarioSuite.all)
func domainScenarioBehavesAsExpected(_ scenario: DomainScenario) throws {
    let domain = try #require(ScenarioDomains.domain(id: scenario.domain))
    let result = domain.result(for: scenario)
    if let issue = scenario.knownIssue {
        withKnownIssue("\(scenario.id): \(issue)") {
            if result.isFailing || result.verdict == .knownIssue { Issue.record("\(result.differences.joined(separator: " "))") }
        }
        return
    }
    if result.isFailing { Issue.record("\(scenario.id) \(scenario.title): \(result.differences.joined(separator: " "))") }
}
