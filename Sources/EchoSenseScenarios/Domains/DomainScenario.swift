import Foundation

/// A scenario for anything that turns text into lines of text: "this input should give exactly these
/// lines". The expectation is a list of lines; the actual lines come from the domain's function
/// (statement splitting, error marks, ...). Completion scenarios keep their richer `CompletionScenario`.
public struct DomainScenario: Codable, Sendable, Identifiable, Equatable {
    public var id: String
    /// Which `ScenarioDomain` runs it ("statements", "statement-at-caret", ...).
    public var domain: String
    public var group: String
    public var title: String
    /// What should happen, in words.
    public var should: String
    /// The text the domain works on. Domains with a caret mark it with `caretMarker`.
    public var input: String
    public var caretMarker: String
    /// Settings the domain reads (`dialect: mssql`); missing keys use the domain's defaults.
    public var options: [String: String]
    /// The expected lines; nil until someone has said what should happen.
    public var expected: [String]?
    public var knownIssue: String?
    public var notes: String?

    public init(id: String, domain: String, group: String, title: String, should: String, input: String,
                caretMarker: String = "|", options: [String: String] = [:], expected: [String]? = nil,
                knownIssue: String? = nil, notes: String? = nil) {
        self.id = id; self.domain = domain; self.group = group; self.title = title; self.should = should
        self.input = input; self.caretMarker = caretMarker; self.options = options; self.expected = expected
        self.knownIssue = knownIssue; self.notes = notes
    }

    private enum CodingKeys: String, CodingKey {
        case id, domain, group, title, should, input, caretMarker, options, expected, knownIssue, notes
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        domain = try c.decode(String.self, forKey: .domain)
        group = try c.decodeIfPresent(String.self, forKey: .group) ?? "Ungrouped"
        title = try c.decode(String.self, forKey: .title)
        should = try c.decodeIfPresent(String.self, forKey: .should) ?? ""
        input = try c.decode(String.self, forKey: .input)
        caretMarker = try c.decodeIfPresent(String.self, forKey: .caretMarker) ?? "|"
        options = try c.decodeIfPresent([String: String].self, forKey: .options) ?? [:]
        expected = try c.decodeIfPresent([String].self, forKey: .expected)
        knownIssue = try c.decodeIfPresent(String.self, forKey: .knownIssue)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
    }

    /// The input without the caret marker, and the caret's UTF-16 offset (the end when there is no marker).
    public var inputAndCaret: (text: String, caret: Int) {
        guard !caretMarker.isEmpty, let range = input.range(of: caretMarker) else {
            return (input, input.utf16.count)
        }
        let caret = input[..<range.lowerBound].utf16.count
        return (input.replacingCharacters(in: range, with: ""), caret)
    }
}

public enum DomainVerdict: Sendable, Equatable {
    case pass
    case fail
    /// Fails today and the scenario says so.
    case knownIssue
    case noExpectation
}

public struct DomainResult: Sendable, Equatable {
    public var scenario: DomainScenario
    public var actual: [String]
    public var verdict: DomainVerdict

    /// The lines that differ, for showing and for test output.
    public var differences: [String] {
        guard let expected = scenario.expected else { return [] }
        var out: [String] = []
        for index in 0..<max(expected.count, actual.count) {
            let want = index < expected.count ? expected[index] : nil
            let got = index < actual.count ? actual[index] : nil
            if want != got { out.append("line \(index + 1): expected \(want.map { "“\($0)”" } ?? "nothing"), got \(got.map { "“\($0)”" } ?? "nothing")") }
        }
        return out
    }

    public var isFailing: Bool { verdict == .fail }
}

/// One kind of scenario: how its input becomes lines.
public struct ScenarioDomain: Sendable, Identifiable {
    public var id: String
    public var title: String
    public var summary: String
    /// What the input box holds ("A script, caret marked with |").
    public var inputLabel: String
    /// What one expected line is ("One statement").
    public var expectedLabel: String
    public var run: @Sendable (DomainScenario) -> [String]

    public init(id: String, title: String, summary: String, inputLabel: String, expectedLabel: String,
                run: @escaping @Sendable (DomainScenario) -> [String]) {
        self.id = id; self.title = title; self.summary = summary
        self.inputLabel = inputLabel; self.expectedLabel = expectedLabel; self.run = run
    }

    public func result(for scenario: DomainScenario) -> DomainResult {
        let actual = run(scenario)
        let verdict: DomainVerdict
        if let expected = scenario.expected {
            let matches = expected == actual
            verdict = matches ? .pass : (scenario.knownIssue != nil ? .knownIssue : .fail)
        } else {
            verdict = .noExpectation
        }
        return DomainResult(scenario: scenario, actual: actual, verdict: verdict)
    }
}
