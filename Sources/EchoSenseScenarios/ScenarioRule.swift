import Foundation

/// A rule many scenarios share, whatever their area: something that must hold wherever it applies.
/// "Database names are never offered", "Columns come before tables, then keywords".
///
/// A scenario lists the rules it follows by id (`CompletionScenario.rules`); each rule adds its checks
/// to the scenario's own, so one change to a rule changes every scenario that uses it. Rules live in
/// `Rules/rules.json`, next to the scenarios.
public struct ScenarioRule: Codable, Sendable, Hashable, Identifiable {
    /// Stable, never reused: "RULE-001".
    public var id: String
    public var title: String
    /// What the rule means, in the owner's words.
    public var should: String
    /// Titles that must never be offered.
    public var excludes: [String]
    /// Kinds that must never be offered ("database").
    public var excludedKinds: [String]
    /// Kinds in the order they must rank: every suggestion of an earlier kind comes before any
    /// suggestion of a later one. Kinds not named here may appear anywhere.
    public var kindOrder: [String]

    public init(id: String, title: String, should: String = "", excludes: [String] = [], excludedKinds: [String] = [], kindOrder: [String] = []) {
        self.id = id; self.title = title; self.should = should
        self.excludes = excludes; self.excludedKinds = excludedKinds; self.kindOrder = kindOrder
    }

    private enum CodingKeys: String, CodingKey { case id, title, should, excludes, excludedKinds, kindOrder }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? id
        should = try c.decodeIfPresent(String.self, forKey: .should) ?? ""
        excludes = try c.decodeIfPresent([String].self, forKey: .excludes) ?? []
        excludedKinds = try c.decodeIfPresent([String].self, forKey: .excludedKinds) ?? []
        kindOrder = try c.decodeIfPresent([String].self, forKey: .kindOrder) ?? []
    }

    /// True when the rule checks nothing yet.
    public var isEmpty: Bool { excludes.isEmpty && excludedKinds.isEmpty && kindOrder.count < 2 }
}

/// The rules file: `Rules/rules.json`, an array of rules sorted by id.
public struct ScenarioRuleLibrary: Sendable {
    public var rules: [ScenarioRule]

    public init(rules: [ScenarioRule] = []) { self.rules = rules }

    public func rule(id: String) -> ScenarioRule? { rules.first { $0.id == id } }

    /// The rules shipped with the package (what tests run). Empty when there are none yet.
    public static let bundled: ScenarioRuleLibrary = {
        guard let url = Bundle.module.url(forResource: "Rules", withExtension: nil) else { return ScenarioRuleLibrary() }
        return (try? load(directory: url)) ?? ScenarioRuleLibrary()
    }()

    public static let fileName = "rules.json"

    /// Reads `rules.json` in the directory; a missing file is an empty library.
    public static func load(directory: URL) throws -> ScenarioRuleLibrary {
        let url = directory.appending(path: fileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return ScenarioRuleLibrary() }
        do { return ScenarioRuleLibrary(rules: try JSONDecoder().decode([ScenarioRule].self, from: Data(contentsOf: url))) }
        catch { throw ScenarioLibraryError.unreadable(fileName, "\(error)") }
    }

    public func write(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let sorted = rules.sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
        try (encoder.encode(sorted) + Data("\n".utf8)).write(to: directory.appending(path: Self.fileName), options: .atomic)
    }

    /// The next free id: "RULE-004" after "RULE-003".
    public func nextID() -> String {
        let numbers = rules.compactMap { Int($0.id.replacingOccurrences(of: "RULE-", with: "")) }
        return String(format: "RULE-%03d", (numbers.max() ?? 0) + 1)
    }
}

/// One message about a scenario, from the owner or from an agent. The thread is how feedback reaches
/// an agent: the scenario waits for the agent while the last message is the owner's.
public struct ScenarioComment: Codable, Sendable, Hashable, Identifiable {
    public enum Author: String, Codable, Sendable, Hashable { case owner, agent }

    public var id: String
    public var author: Author
    /// ISO 8601.
    public var date: String
    public var text: String
    /// What in the scenario it is about: a check id ("offers:customers"), or nil for the whole scenario.
    public var about: String?

    public init(id: String = UUID().uuidString, author: Author, date: String = Date.now.ISO8601Format(), text: String, about: String? = nil) {
        self.id = id; self.author = author; self.date = date; self.text = text; self.about = about
    }
}
