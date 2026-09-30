import Foundation

/// One thing a scenario checks, in plain words, and whether it holds.
///
/// A scenario's expectation is read as a list of these ("offers `customers`", "never offers `users`",
/// "`name` inserts `u.name`"). The verdict is "every check holds": `CompletionScenarioRunner.compare`
/// is built from the same list, so Echo Labs (which shows the checks one per line) and the package's
/// tests can never disagree about what "as expected" means.
public struct ScenarioCheck: Sendable, Hashable, Identifiable {
    /// Whose behaviour the check is about: the completion engine, or Echo's editor around it.
    public enum Subject: String, Sendable, Hashable {
        case echoSense, editor
    }

    /// What went wrong, as data: a list row says it in a few words, and a test can assert on it.
    public enum Problem: Sendable, Hashable {
        /// Expected, but not offered.
        case missing([String])
        /// Offered, but the scenario forbids it.
        case unwanted([String])
        /// Offered when the scenario expects nothing, or more than the exact list.
        case offered([String])
        /// Suggestions were expected; EchoSense had none.
        case nothingOffered
        /// EchoSense had suggestions, but the editor doesn't ask for them here.
        case popupClosed
        /// The right items, in the wrong order.
        case wrongOrder
        /// This title inserts the wrong text, or isn't offered to insert anything.
        case wrongInsert(String)
        /// Something the editor does differently, in a few words.
        case editor(String)

        /// A few words for a list row: "missing invoices".
        public var brief: String {
            switch self {
            case .missing(let titles): "missing \(CompletionScenarioRunner.list(titles))"
            case .unwanted(let titles): "shouldn't offer \(CompletionScenarioRunner.list(titles))"
            case .offered(let titles): "offered \(CompletionScenarioRunner.list(titles))"
            case .nothingOffered: "offers nothing"
            case .popupClosed: "popup doesn't open"
            case .wrongOrder: "wrong order"
            case .wrongInsert(let title): "\(title) inserts the wrong text"
            case .editor(let text): text
            }
        }
    }

    /// Stable within its scenario ("offers:customers"), so a list can keep its place.
    public var id: String
    public var subject: Subject
    /// What should be true, with code in backticks: "offers `customers`".
    public var statement: String
    /// Nil when the check holds.
    public var problem: Problem?
    /// Why it doesn't hold, in one sentence. Nil when it holds.
    public var failure: String?

    public var passed: Bool { problem == nil }

    public init(id: String, subject: Subject = .echoSense, statement: String, problem: Problem? = nil, failure: String? = nil) {
        self.id = id; self.subject = subject; self.statement = statement; self.problem = problem; self.failure = failure
    }
}

public extension ScenarioResult {
    /// Every check the scenario's expectations make, EchoSense's first, then the editor's. Empty when
    /// the scenario has no expectation yet or could not run.
    var checks: [ScenarioCheck] {
        guard let actual else { return [] }
        let engine = scenario.echoSense.map { CompletionScenarioRunner.checks($0, actual: actual, trigger: scenario.trigger) } ?? []
        let editor = scenario.echo.map { CompletionScenarioRunner.checks($0, actual: actual) } ?? []
        return engine + editor
    }

    /// What is wrong, in a few words, for a list row: "missing id, name · offered status". Nil when
    /// nothing is. Problems of the same kind are merged.
    var briefProblem: String? {
        if case .error(let message) = verdict { return message }
        var missing: [String] = [], unwanted: [String] = [], offered: [String] = [], others: [ScenarioCheck.Problem] = []
        for problem in checks.compactMap(\.problem) {
            switch problem {
            case .missing(let titles): missing += titles.filter { !missing.contains($0) }
            case .unwanted(let titles): unwanted += titles.filter { !unwanted.contains($0) }
            case .offered(let titles): offered += titles.filter { !offered.contains($0) }
            default: if !others.contains(problem) { others.append(problem) }
            }
        }
        var parts: [ScenarioCheck.Problem] = []
        if !missing.isEmpty { parts.append(.missing(missing)) }
        if !unwanted.isEmpty { parts.append(.unwanted(unwanted)) }
        if !offered.isEmpty { parts.append(.offered(offered)) }
        parts += others
        return parts.isEmpty ? nil : parts.map(\.brief).joined(separator: " · ")
    }
}
