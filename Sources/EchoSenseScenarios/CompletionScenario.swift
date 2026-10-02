import Foundation

/// One thing EchoSense (and the editor around it) should do: a place in some SQL, what should
/// happen there in plain words, and the exact result to compare with.
///
/// Scenarios are data (JSON files under `Scenarios/`), so hundreds can be added without code. The
/// same scenarios run in Echo Labs (one by one, expected beside actual), in the package's tests and
/// in Echo's tests, through `CompletionScenarioRunner`.
public struct CompletionScenario: Codable, Sendable, Identifiable, Hashable {
    /// Stable, never reused: "SEL-014". Feedback and known-issue notes point at it.
    public var id: String
    /// The group it belongs to, for browsing: "SELECT clause".
    public var group: String
    public var title: String
    /// What should happen, in the owner's words. This is the requirement; the expectations below are
    /// its checkable form. A scenario may have this and no expectation yet.
    public var should: String
    public var dialect: ScenarioDialect
    /// A built-in schema (`ScenarioSchemas.ids`), or a live one supplied by the host.
    public var schema: String
    /// The SQL, with the caret written as `caretMarker` ("|").
    public var sql: String
    public var caretMarker: String
    public var trigger: ScenarioTrigger
    public var options: ScenarioOptions
    /// What the completion engine should return. Nil while the scenario has only `should`.
    public var echoSense: EchoSenseExpectation?
    /// What the editor should do with it. Nil until written; run by Echo's own code.
    public var echo: EchoExpectation?
    /// Where it came from, such as "AUTOCOMPLETE_SPEC.md 1.4".
    public var source: String?
    public var notes: String?
    /// Accept this suggestion (by title; empty for the first) at the caret before the scenario is
    /// evaluated, as the editor does when the user picks it. What is checked is what happens next: the
    /// engine's post-commit suppression stays silent at the same place.
    public var afterAccepting: String?
    /// Text typed at the caret after that (for example " " or "R"), to check what re-enables completion.
    public var thenTyped: String?
    /// Set while the scenario is known to fail today; the reason, or the ticket. Tests then expect the
    /// failure and turn red when it starts to pass, so the flag is removed.
    public var knownIssue: String?
    /// `imported` until the owner has read it: `approved` when it is right, `flagged` when it needs a change.
    public var review: ScenarioReview
    /// Shared rules this scenario follows (`ScenarioRule` ids); their checks are added to its own.
    public var rules: [String]
    /// What the popup should hold, as groups of blocks. When set, it replaces the listed titles
    /// (`echoSense.items`, `order`, `excludes`); `echoSense` still says suggests, nothing or silent,
    /// and its insert text is still checked.
    public var popup: PopupExpectation?
    /// The query as the scenario reads it, stored only when the reader gets it wrong.
    public var context: ScenarioContext?
    /// The conversation about this scenario between the owner and agents, oldest first.
    public var comments: [ScenarioComment]

    /// True while the owner's message is the last one: an agent should read and answer it.
    public var waitsForAgent: Bool { comments.last?.author == .owner }

    public init(
        id: String, group: String, title: String, should: String = "",
        dialect: ScenarioDialect = .postgresql, schema: String = ScenarioSchemas.specID,
        sql: String, caretMarker: String = "|", trigger: ScenarioTrigger = .typing,
        options: ScenarioOptions = .init(), echoSense: EchoSenseExpectation? = nil, echo: EchoExpectation? = nil,
        afterAccepting: String? = nil, thenTyped: String? = nil,
        source: String? = nil, notes: String? = nil, knownIssue: String? = nil, review: ScenarioReview = .imported,
        rules: [String] = [], comments: [ScenarioComment] = [], popup: PopupExpectation? = nil, context: ScenarioContext? = nil
    ) {
        self.rules = rules; self.comments = comments; self.popup = popup; self.context = context
        self.afterAccepting = afterAccepting; self.thenTyped = thenTyped
        self.id = id; self.group = group; self.title = title; self.should = should
        self.dialect = dialect; self.schema = schema; self.sql = sql; self.caretMarker = caretMarker
        self.trigger = trigger; self.options = options; self.echoSense = echoSense; self.echo = echo
        self.source = source; self.notes = notes; self.knownIssue = knownIssue; self.review = review
    }

    /// The text without the caret marker, and where the caret is (UTF-16 offset).
    public var textAndCaret: (text: String, caret: Int) {
        guard let range = sql.range(of: caretMarker) else { return (sql, sql.utf16.count) }
        let caret = sql[..<range.lowerBound].utf16.count
        var text = sql
        text.removeSubrange(range)
        return (text, caret)
    }

    // Decoding tolerates files written by hand or by an older version.
    private enum CodingKeys: String, CodingKey {
        case id, group, title, should, dialect, schema, sql, caretMarker, trigger, options, echoSense, echo, afterAccepting, thenTyped, source, notes, knownIssue, review, rules, comments, popup, context
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        group = try c.decodeIfPresent(String.self, forKey: .group) ?? "Ungrouped"
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? id
        should = try c.decodeIfPresent(String.self, forKey: .should) ?? ""
        dialect = try c.decodeIfPresent(ScenarioDialect.self, forKey: .dialect) ?? .postgresql
        schema = try c.decodeIfPresent(String.self, forKey: .schema) ?? ScenarioSchemas.specID
        sql = try c.decode(String.self, forKey: .sql)
        caretMarker = try c.decodeIfPresent(String.self, forKey: .caretMarker) ?? "|"
        trigger = try c.decodeIfPresent(ScenarioTrigger.self, forKey: .trigger) ?? .typing
        options = try c.decodeIfPresent(ScenarioOptions.self, forKey: .options) ?? .init()
        echoSense = try c.decodeIfPresent(EchoSenseExpectation.self, forKey: .echoSense)
        echo = try c.decodeIfPresent(EchoExpectation.self, forKey: .echo)
        afterAccepting = try c.decodeIfPresent(String.self, forKey: .afterAccepting)
        thenTyped = try c.decodeIfPresent(String.self, forKey: .thenTyped)
        source = try c.decodeIfPresent(String.self, forKey: .source)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        knownIssue = try c.decodeIfPresent(String.self, forKey: .knownIssue)
        review = try c.decodeIfPresent(ScenarioReview.self, forKey: .review) ?? .imported
        rules = try c.decodeIfPresent([String].self, forKey: .rules) ?? []
        comments = try c.decodeIfPresent([ScenarioComment].self, forKey: .comments) ?? []
        popup = try c.decodeIfPresent(PopupExpectation.self, forKey: .popup)
        context = try c.decodeIfPresent(ScenarioContext.self, forKey: .context)
    }
}

public enum ScenarioDialect: String, Codable, Sendable, CaseIterable, Hashable {
    case postgresql, mssql, mysql, sqlite
    public var title: String {
        switch self { case .postgresql: "PostgreSQL"; case .mssql: "SQL Server"; case .mysql: "MySQL"; case .sqlite: "SQLite" }
    }
}

public enum ScenarioTrigger: String, Codable, Sendable, CaseIterable, Hashable {
    /// The user is typing: the popup opens by itself, or stays silent.
    case typing
    /// The user pressed the manual trigger (⌘.).
    case manual
}

public struct ScenarioOptions: Codable, Sendable, Hashable {
    public var includeSystemSchemas = false
    public var qualifyTableInsertions = false
    public init(includeSystemSchemas: Bool = false, qualifyTableInsertions: Bool = false) {
        self.includeSystemSchemas = includeSystemSchemas
        self.qualifyTableInsertions = qualifyTableInsertions
    }

    private enum CodingKeys: String, CodingKey { case includeSystemSchemas, qualifyTableInsertions }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        includeSystemSchemas = try c.decodeIfPresent(Bool.self, forKey: .includeSystemSchemas) ?? false
        qualifyTableInsertions = try c.decodeIfPresent(Bool.self, forKey: .qualifyTableInsertions) ?? false
    }
}

public enum ScenarioReview: String, Codable, Sendable, Hashable, CaseIterable {
    /// Not read by the owner yet.
    case imported
    /// The owner agrees this is what should happen (whether or not EchoSense does it yet).
    case approved
    /// The owner says the expectation is wrong; `notes` says why. For an agent to fix.
    case flagged
}

/// What the completion engine should return at the caret.
public struct EchoSenseExpectation: Codable, Sendable, Hashable {
    public enum Outcome: String, Codable, Sendable, Hashable, CaseIterable {
        /// Suggestions appear; `items` says which.
        case suggests
        /// Nothing at all, even when triggered by hand (`=> NONE`).
        case nothing = "none"
        /// Nothing while typing; a manual trigger may show something (`=> SILENT`).
        case silent
    }

    /// How `items` is compared with what came back.
    public enum Order: String, Codable, Sendable, Hashable, CaseIterable {
        /// The result is exactly these, in this order.
        case exact
        /// These come first, in this order; more may follow.
        case leading
        /// All of these are in the result, in any order; more may be too. Not offered for new
        /// scenarios: order always matters (the owner's rule), so use `leading`.
        case includes
    }

    public var outcome: Outcome
    /// Suggestion titles.
    public var items: [String]
    public var order: Order
    /// Titles that must not appear.
    public var excludes: [String]
    /// Insert text per title, where it matters ("name" rather than "u.name" after "u.").
    public var insertText: [String: String]

    public init(outcome: Outcome, items: [String] = [], order: Order = .leading, excludes: [String] = [], insertText: [String: String] = [:]) {
        self.outcome = outcome; self.items = items; self.order = order; self.excludes = excludes; self.insertText = insertText
    }

    private enum CodingKeys: String, CodingKey { case outcome, items, order, excludes, insertText }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        outcome = try c.decode(Outcome.self, forKey: .outcome)
        items = try c.decodeIfPresent([String].self, forKey: .items) ?? []
        order = try c.decodeIfPresent(Order.self, forKey: .order) ?? .exact
        excludes = try c.decodeIfPresent([String].self, forKey: .excludes) ?? []
        insertText = try c.decodeIfPresent([String: String].self, forKey: .insertText) ?? [:]
    }
}

/// What the editor around EchoSense should do (Echo's own rules, run by Echo's code).
public struct EchoExpectation: Codable, Sendable, Hashable {
    public enum Popup: String, Codable, Sendable, Hashable, CaseIterable { case shown, hidden }
    public var popup: Popup?
    /// The suggestion that is selected when the popup opens.
    public var selected: String?
    /// The suggestion accepted for `textAfterAccepting` (by title); the first when empty.
    public var accept: String?
    /// The text after accepting the selected suggestion, with the caret as the scenario's marker.
    public var textAfterAccepting: String?
    /// The grey ghost text, when that setting is on.
    public var ghostText: String?

    public init(popup: Popup? = nil, selected: String? = nil, accept: String? = nil, textAfterAccepting: String? = nil, ghostText: String? = nil) {
        self.popup = popup; self.selected = selected; self.accept = accept; self.textAfterAccepting = textAfterAccepting; self.ghostText = ghostText
    }
}
