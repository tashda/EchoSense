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
    /// What the engine returned when asked, whether or not the editor would have asked.
    public var engineTitles: [String]
    /// Whether the editor opens the popup for this trigger (`SQLEditorTriggerPolicy`) and there is something to show.
    public var popupShown: Bool
    /// Why the editor does or doesn't ask.
    public var triggerNote: String
    /// The text after accepting the first suggestion, with the caret written as the scenario's marker.
    public var textAfterAccepting: String?
    /// The same for every suggestion, by title, so an expectation can name which one is accepted.
    public var textAfterAcceptingByTitle: [String: String] = [:]
    /// The engine's priority per title (higher ranks earlier), to explain an order.
    public var priorities: [String: Int] = [:]

    /// Where a title is in the popup, from 1; nil when it isn't offered. Quoting is ignored.
    public func rank(of title: String) -> Int? {
        let plain = CompletionScenarioRunner.unquoted(title)
        return titles.firstIndex { CompletionScenarioRunner.unquoted($0) == plain }.map { $0 + 1 }
    }

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
    /// Every check the scenario makes (its own, then its rules', then the editor's), each passing or
    /// failing on its own. The verdicts above are exactly the failing ones.
    public var checks: [ScenarioCheck] = []
    /// The rules the scenario follows, as they were when it ran.
    public var rules: [ScenarioRule] = []
    public var id: String { scenario.id }

    /// Everything that disagrees, from EchoSense and from the editor rules.
    public var failureReasons: [String] {
        var reasons: [String] = []
        switch verdict {
        case .fail(let items): reasons += items
        case .error(let message): reasons.append(message)
        default: break
        }
        if case .fail(let items) = echo { reasons += items.map { "Editor: " + $0 } }
        return reasons
    }

    public var isFailing: Bool { !failureReasons.isEmpty }

    /// True when the result is what the scenario says it should be: no disagreement, or a disagreement
    /// the scenario already lists as a known issue.
    public var isAsExpected: Bool {
        scenario.knownIssue != nil ? isFailing : !isFailing
    }

    /// Pass, fail or nothing to compare, for the scenario as a whole.
    public var isPass: Bool { !isFailing && (verdict.isPass || { if case .pass = echo { true } else { false } }()) }
}

/// Runs scenarios against the real completion engine. Used by Echo Labs, the package's tests and Echo's tests.
public struct CompletionScenarioRunner: Sendable {
    /// A structure from a live connection, used instead of the scenario's built-in schema.
    public var liveStructure: EchoSenseDatabaseStructure?
    /// The shared rules scenarios can name, by id.
    public var rules: [String: ScenarioRule]

    public init(liveStructure: EchoSenseDatabaseStructure? = nil, rules: [ScenarioRule] = ScenarioRuleLibrary.bundled.rules) {
        self.liveStructure = liveStructure
        self.rules = Dictionary(rules.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    public func run(_ scenario: CompletionScenario) -> ScenarioResult {
        guard let structure = liveStructure ?? ScenarioSchemas.structure(id: scenario.schema, dialect: scenario.dialect) else {
            return ScenarioResult(scenario: scenario, actual: nil, verdict: .error("Unknown schema “\(scenario.schema)”."), echo: .unchecked)
        }
        let actual = complete(scenario, structure: structure)
        let followed = scenario.rules.compactMap { rules[$0] }
        var engineChecks = scenario.echoSense.map { Self.checks($0, actual: actual, trigger: scenario.trigger) } ?? []
        for id in scenario.rules {
            engineChecks += rules[id].map { Self.checks($0, actual: actual) }
                ?? [ScenarioCheck(id: "rule:\(id)", statement: "follows rule \(id)", problem: .editor("unknown rule \(id)"), failure: "Rule \(id) doesn't exist.", rule: id)]
        }
        let editorChecks = scenario.echo.map { Self.checks($0, actual: actual) } ?? []
        let verdict = scenario.echoSense == nil && scenario.rules.isEmpty ? .unchecked : Self.verdict(engineChecks)
        let echo: EchoVerdict = scenario.echo == nil ? .unchecked : { if case .fail(let reasons) = Self.verdict(editorChecks) { .fail(reasons) } else { .pass } }()
        return ScenarioResult(scenario: scenario, actual: actual, verdict: verdict, echo: echo, checks: engineChecks + editorChecks, rules: followed)
    }

    public func run(_ scenarios: [CompletionScenario]) -> [ScenarioResult] { scenarios.map(run) }

    /// The engine's answer for the scenario, without comparing it with anything.
    public func complete(_ scenario: CompletionScenario, structure: EchoSenseDatabaseStructure) -> ScenarioActual {
        var (text, caret) = scenario.textAndCaret
        let engine = SQLAutoCompletionEngine()
        let type = Self.databaseType(scenario.dialect)
        let database = liveStructure == nil ? ScenarioSchemas.databaseName(id: scenario.schema) : structure.databases.first?.name
        engine.updateContext(SQLEditorCompletionContext(
            databaseType: type, selectedDatabase: database,
            defaultSchema: ScenarioSchemas.defaultSchema(for: scenario.dialect), structure: structure))
        engine.updatePreferences(SQLCompletionPreferences(
            includeHistory: false, includeSystemSchemas: scenario.options.includeSystemSchemas,
            qualifyTableInsertions: scenario.options.qualifyTableInsertions, autoJoinOnClause: true))
        if let title = scenario.afterAccepting {
            // The user picks a suggestion first; the engine is told, as the editor tells it.
            let before = engine.completions(in: text, at: caret)
            let wanted = title.isEmpty ? before.suggestions.first : before.suggestions.first(where: { Self.unquoted($0.title) == Self.unquoted(title) })
            if let picked = wanted {
                let accepted = SQLEditorAcceptance.accept(picked, from: before, in: text)
                engine.recordSelection(picked, from: before)
                text = accepted.text
                caret = accepted.caret
                if let typed = scenario.thenTyped, !typed.isEmpty {
                    let ns = text as NSString
                    text = ns.replacingCharacters(in: NSRange(location: caret, length: 0), with: typed)
                    caret += (typed as NSString).length
                }
            }
        }
        let automatic = engine.completions(in: text, at: caret)
        let manual = engine.manualCompletions(in: text, at: caret)
        // What the editor does: typing asks only for some characters; a manual trigger always asks.
        let policy = scenario.trigger == .manual
            ? (opens: true, reason: "The manual trigger (⌘.) always asks EchoSense.")
            : SQLEditorTriggerPolicy.opensAfterTyping(text: text, caret: caret)
        let response = scenario.trigger == .manual ? manual : automatic
        let asked = policy.opens ? response.suggestions : []
        var accepted: String?
        var acceptedByTitle: [String: String] = [:]
        for (index, suggestion) in asked.prefix(200).enumerated() {
            let result = SQLEditorAcceptance.accept(suggestion, from: response, in: text)
            let ns = result.text as NSString
            let marked = ns.substring(to: result.caret) + scenario.caretMarker + ns.substring(from: result.caret)
            if index == 0 { accepted = marked }
            acceptedByTitle[Self.unquoted(suggestion.title)] = acceptedByTitle[Self.unquoted(suggestion.title)] ?? marked
        }
        return ScenarioActual(
            titles: asked.map(\.title),
            insertText: Dictionary(asked.map { ($0.title, $0.insertText) }, uniquingKeysWith: { first, _ in first }),
            kinds: Dictionary(asked.map { ($0.title, "\($0.kind)") }, uniquingKeysWith: { first, _ in first }),
            clause: "\(response.clause)", token: response.token,
            manualTitles: manual.suggestions.map(\.title), isMetadataLimited: response.isMetadataLimited,
            engineTitles: response.suggestions.map(\.title), popupShown: !asked.isEmpty, triggerNote: policy.reason,
            textAfterAccepting: accepted, textAfterAcceptingByTitle: acceptedByTitle,
            priorities: Dictionary(asked.map { ($0.title, $0.priority) }, uniquingKeysWith: { first, _ in first }))
    }

    public static func databaseType(_ dialect: ScenarioDialect) -> EchoSenseDatabaseType {
        switch dialect { case .postgresql: .postgresql; case .mssql: .microsoftSQL; case .mysql: .mysql; case .sqlite: .sqlite }
    }

    /// Compares one expectation with what came back: every check it makes (`checks(_:actual:trigger:)`) must hold.
    public static func compare(_ expected: EchoSenseExpectation, actual: ScenarioActual, trigger: ScenarioTrigger) -> ScenarioVerdict {
        verdict(checks(expected, actual: actual, trigger: trigger))
    }

    /// Compares what the editor should do with what it does: the popup, the selected suggestion and the text after accepting.
    public static func compare(_ expected: EchoExpectation, actual: ScenarioActual) -> EchoVerdict {
        switch verdict(checks(expected, actual: actual)) {
        case .fail(let reasons): .fail(reasons)
        default: .pass
        }
    }

    /// A title without identifier quoting: "name", `name` and [name] are name.
    public static func unquoted(_ title: String) -> String {
        guard title.count >= 2 else { return title }
        let pairs: [(Character, Character)] = [("\"", "\""), ("`", "`"), ("[", "]")]
        for (open, close) in pairs where title.first == open && title.last == close { return String(title.dropFirst().dropLast()) }
        return title
    }

    static func list(_ titles: [String]) -> String {
        titles.isEmpty ? "nothing" : titles.prefix(12).joined(separator: ", ") + (titles.count > 12 ? " and \(titles.count - 12) more" : "")
    }
}

public extension CompletionScenario {
    /// An expectation that describes exactly what the engine returned now: "accept actual as expected".
    func expectation(matching actual: ScenarioActual) -> EchoSenseExpectation {
        actual.titles.isEmpty
            ? EchoSenseExpectation(outcome: trigger == .manual ? .nothing : (actual.manualTitles.isEmpty ? .nothing : .silent))
            : EchoSenseExpectation(outcome: .suggests, items: actual.titles.map(CompletionScenarioRunner.unquoted), order: .leading)
    }
}
