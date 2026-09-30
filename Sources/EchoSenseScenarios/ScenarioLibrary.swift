import Foundation

/// The scenario files: one JSON file per group under `Scenarios/`, each an array of scenarios.
public struct ScenarioLibrary: Sendable {
    public var scenarios: [CompletionScenario]

    public init(scenarios: [CompletionScenario]) {
        self.scenarios = scenarios
    }

    /// The groups, in the order their first scenario appears.
    public var groups: [String] {
        var seen: [String] = []
        for scenario in scenarios where !seen.contains(scenario.group) { seen.append(scenario.group) }
        return seen
    }

    public func scenarios(in group: String) -> [CompletionScenario] { scenarios.filter { $0.group == group } }
    public func scenario(id: String) -> CompletionScenario? { scenarios.first { $0.id == id } }

    /// The scenarios shipped with the package (what tests run).
    public static func bundled() throws -> ScenarioLibrary {
        guard let url = Bundle.module.url(forResource: "Scenarios", withExtension: nil) else {
            throw ScenarioLibraryError.missingDirectory("Scenarios")
        }
        return try load(directory: url)
    }

    public static func load(directory: URL) throws -> ScenarioLibrary {
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        var all: [CompletionScenario] = []
        for file in files {
            do { all += try JSONDecoder().decode([CompletionScenario].self, from: Data(contentsOf: file)) }
            catch { throw ScenarioLibraryError.unreadable(file.lastPathComponent, "\(error)") }
        }
        var seen = Set<String>()
        for scenario in all where !seen.insert(scenario.id).inserted { throw ScenarioLibraryError.duplicateID(scenario.id) }
        return ScenarioLibrary(scenarios: all)
    }

    /// Writes the scenarios as one file per group (sorted by id, stable formatting so git diffs are small)
    /// and removes files for groups that no longer exist.
    public func write(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var written = Set<String>()
        for group in groups {
            let name = Self.fileName(for: group)
            let sorted = scenarios(in: group).sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
            try (encoder.encode(sorted) + Data("\n".utf8)).write(to: directory.appending(path: name), options: .atomic)
            written.insert(name)
        }
        for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        where file.pathExtension == "json" && !written.contains(file.lastPathComponent) {
            try FileManager.default.removeItem(at: file)
        }
    }

    public static func fileName(for group: String) -> String {
        let slug = group.lowercased().map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined()
            .split(separator: "-").joined(separator: "-")
        return (slug.isEmpty ? "ungrouped" : slug) + ".json"
    }

    /// The next free id in a group's series: "SEL-015" after "SEL-014".
    public func nextID(prefix: String) -> String {
        let numbers = scenarios.compactMap { scenario -> Int? in
            guard scenario.id.hasPrefix(prefix + "-") else { return nil }
            return Int(scenario.id.dropFirst(prefix.count + 1))
        }
        return String(format: "%@-%03d", prefix, (numbers.max() ?? 0) + 1)
    }
}

public enum ScenarioLibraryError: Error, CustomStringConvertible {
    case missingDirectory(String)
    case unreadable(String, String)
    case duplicateID(String)

    public var description: String {
        switch self {
        case .missingDirectory(let name): "The scenario directory “\(name)” is missing."
        case .unreadable(let file, let reason): "Could not read \(file): \(reason)"
        case .duplicateID(let id): "Two scenarios have the id \(id)."
        }
    }
}
