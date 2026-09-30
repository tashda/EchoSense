import EchoSense
import Foundation

/// What the engine actually returned for a scenario.
public struct ScenarioActual: Codable, Sendable, Hashable {
    /// Suggestion titles, in the order the engine ranked them (for the scenario's trigger).
    public var titles: [String]
    /// Insert text per title.
    public var insertText: [String: String]
    /// Kind per title, for reading ("column", "table").
    public var kinds: [String: String]
    /// The clause the engine believes the caret is in.
    public var clause: String
    public var token: String
    /// What a manual trigger returned, recorded for typing scenarios that expect silence.
    public var manualTitles: [String]
    public var isMetadataLimited: Bool

    public var isEmpty: Bool { titles.isEmpty }
}

public enum ScenarioVerdict: Sendable, Hashable {
    case pass
    /// It disagrees; each reason is one plain sentence.
    case fail([String])
    /// The scenario has no expectation yet, so there is nothing to compare.
    case unchecked
    /// The scenario could not run (unknown schema, no caret).
    case error(String)

    public var isPass: Bool { if case .pass = self { true } else { false } }
    public var isFail: Bool { if case .fail = self { true } else { false } }
}

/// The verdict on the editor's side. Echo's rules run in Echo's code; until they run here it says so.
public enum EchoVerdict: Sendable, Hashable {
    case notRun(String)
    case unchecked
    case pass
    case fail([String])
}

public struct ScenarioResult: Sendable, Hashable, Identifiable {
    public var scenario: CompletionScenario
    public var actual: ScenarioActual?
    public var verdict: ScenarioVerdict
    public var echo: EchoVerdict
    public var id: String { scenario.id }

    /// True when the result is what the scenario says it should be: a pass, or a failure that the
    /// scenario already lists as a known issue.
    public var isAsExpected: Bool {
        if scenario.knownIssue != nil { return verdict.isFail }
        return verdict.isPass || verdict == .unchecked
    }
}

/// Runs scenarios against the real completion engine. Used by Echo Labs, the package's tests and Echo's tests.
public struct CompletionScenarioRunner: Sendable {
    /// A structure from a live connection, used instead of the scenario's built-in schema.
    public var liveStructure: EchoSenseDatabaseStructure?

    public init(liveStructure: EchoSenseDatabaseStructure? = nil) {
        self.liveStructure = liveStructure
    }

    public func run(_ scenario: CompletionScenario) -> ScenarioResult {
        guard let structure = liveStructure ?? ScenarioSchemas.structure(id: scenario.schema, dialect: scenario.dialect) else {
            return ScenarioResult(scenario: scenario, actual: nil, verdict: .error("Unknown schema “\(scenario.schema)”."), echo: .unchecked)
        }
        let actual = complete(scenario, structure: structure)
        let verdict = scenario.echoSense.map { Self.compare($0, actual: actual, trigger: scenario.trigger) } ?? .unchecked
        let echo: EchoVerdict = scenario.echo == nil ? .unchecked : .notRun("Echo's editor rules don't run in this package yet.")
        return ScenarioResult(scenario: scenario, actual: actual, verdict: verdict, echo: echo)
    }

    public func run(_ scenarios: [CompletionScenario]) -> [ScenarioResult] { scenarios.map(run) }

    /// The engine's answer for the scenario, without comparing it with anything.
    public func complete(_ scenario: CompletionScenario, structure: EchoSenseDatabaseStructure) -> ScenarioActual {
        let (text, caret) = scenario.textAndCaret
        let engine = SQLAutoCompletionEngine()
        let type = Self.databaseType(scenario.dialect)
        let database = liveStructure == nil ? ScenarioSchemas.databaseName(id: scenario.schema) : structure.databases.first?.name
        engine.updateContext(SQLEditorCompletionContext(
            databaseType: type, selectedDatabase: database,
            defaultSchema: ScenarioSchemas.defaultSchema(for: scenario.dialect), structure: structure))
        engine.updatePreferences(SQLCompletionPreferences(
            includeHistory: false, includeSystemSchemas: scenario.options.includeSystemSchemas,
            qualifyTableInsertions: scenario.options.qualifyTableInsertions, autoJoinOnClause: true))
        let automatic = engine.completions(in: text, at: caret)
        let manual = engine.manualCompletions(in: text, at: caret)
        let response = scenario.trigger == .manual ? manual : automatic
        return ScenarioActual(
            titles: response.suggestions.map(\.title),
            insertText: Dictionary(response.suggestions.map { ($0.title, $0.insertText) }, uniquingKeysWith: { first, _ in first }),
            kinds: Dictionary(response.suggestions.map { ($0.title, "\($0.kind)") }, uniquingKeysWith: { first, _ in first }),
            clause: "\(response.clause)", token: response.token,
            manualTitles: manual.suggestions.map(\.title), isMetadataLimited: response.isMetadataLimited)
    }

    public static func databaseType(_ dialect: ScenarioDialect) -> EchoSenseDatabaseType {
        switch dialect { case .postgresql: .postgresql; case .mssql: .microsoftSQL; case .mysql: .mysql; case .sqlite: .sqlite }
    }

    /// Compares one expectation with what came back.
    public static func compare(_ expected: EchoSenseExpectation, actual: ScenarioActual, trigger: ScenarioTrigger) -> ScenarioVerdict {
        var reasons: [String] = []
        switch expected.outcome {
        case .none:
            if !actual.titles.isEmpty { reasons.append("Expected nothing, but it offered \(list(actual.titles)).") }
            if !actual.manualTitles.isEmpty { reasons.append("Expected nothing even when triggered by hand, but that offered \(list(actual.manualTitles)).") }
        case .silent:
            if !actual.titles.isEmpty { reasons.append("Expected silence while typing, but it offered \(list(actual.titles)).") }
        case .suggests:
            if actual.titles.isEmpty { reasons.append("Expected suggestions, but it offered nothing.") }
            switch expected.order {
            case .exact:
                if actual.titles != expected.items { reasons.append(differences(expected.items, actual.titles)) }
            case .leading:
                if Array(actual.titles.prefix(expected.items.count)) != expected.items {
                    reasons.append("Expected these first, in order: \(list(expected.items)). Got: \(list(Array(actual.titles.prefix(max(expected.items.count, 1))))).")
                }
            case .includes:
                let missing = expected.items.filter { !actual.titles.contains($0) }
                if !missing.isEmpty { reasons.append("Missing: \(list(missing)).") }
            }
        }
        let present = expected.excludes.filter { actual.titles.contains($0) }
        if !present.isEmpty { reasons.append("Should not offer: \(list(present)).") }
        for (title, text) in expected.insertText.sorted(by: { $0.key < $1.key }) {
            if let got = actual.insertText[title] {
                if got != text { reasons.append("“\(title)” should insert “\(text)”, but inserts “\(got)”.") }
            } else {
                reasons.append("“\(title)” should insert “\(text)”, but it isn't offered.")
            }
        }
        return reasons.isEmpty ? .pass : .fail(reasons)
    }

    private static func list(_ titles: [String]) -> String {
        titles.isEmpty ? "nothing" : titles.prefix(12).joined(separator: ", ") + (titles.count > 12 ? " and \(titles.count - 12) more" : "")
    }

    private static func differences(_ expected: [String], _ actual: [String]) -> String {
        let missing = expected.filter { !actual.contains($0) }
        let extra = actual.filter { !expected.contains($0) }
        var parts: [String] = []
        if !missing.isEmpty { parts.append("missing \(list(missing))") }
        if !extra.isEmpty { parts.append("unexpected \(list(extra))") }
        if parts.isEmpty { parts.append("same items, different order") }
        return "Expected \(list(expected)); \(parts.joined(separator: ", "))."
    }
}

public extension CompletionScenario {
    /// An expectation that describes exactly what the engine returned now: "accept actual as expected".
    func expectation(matching actual: ScenarioActual) -> EchoSenseExpectation {
        actual.titles.isEmpty
            ? EchoSenseExpectation(outcome: trigger == .manual ? .none : (actual.manualTitles.isEmpty ? .none : .silent))
            : EchoSenseExpectation(outcome: .suggests, items: actual.titles, order: .exact)
    }
}
