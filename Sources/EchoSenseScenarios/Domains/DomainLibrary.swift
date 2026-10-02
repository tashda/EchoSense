import Foundation

/// The domain scenario files: one JSON file per domain under `DomainScenarios/`.
public struct DomainLibrary: Sendable {
    public var scenarios: [DomainScenario]

    public init(scenarios: [DomainScenario]) { self.scenarios = scenarios }

    public func scenarios(in domain: String) -> [DomainScenario] { scenarios.filter { $0.domain == domain } }
    public func groups(in domain: String) -> [String] {
        var seen: [String] = []
        for scenario in scenarios(in: domain) where !seen.contains(scenario.group) { seen.append(scenario.group) }
        return seen
    }

    public static func bundled() throws -> DomainLibrary {
        guard let url = Bundle.module.url(forResource: "DomainScenarios", withExtension: nil) else {
            throw ScenarioLibraryError.missingDirectory("DomainScenarios")
        }
        return try load(directory: url)
    }

    public static func load(directory: URL) throws -> DomainLibrary {
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        var all: [DomainScenario] = []
        for file in files {
            do { all += try JSONDecoder().decode([DomainScenario].self, from: Data(contentsOf: file)) }
            catch { throw ScenarioLibraryError.unreadable(file.lastPathComponent, "\(error)") }
        }
        var seen = Set<String>()
        for scenario in all where !seen.insert(scenario.id).inserted { throw ScenarioLibraryError.duplicateID(scenario.id) }
        return DomainLibrary(scenarios: all)
    }

    /// One file per domain, scenarios sorted by id, stable formatting.
    public func write(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var domains: [String] = []
        for scenario in scenarios where !domains.contains(scenario.domain) { domains.append(scenario.domain) }
        for domain in domains {
            let sorted = scenarios(in: domain).sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
            try (encoder.encode(sorted) + Data("\n".utf8)).write(to: directory.appending(path: domain + ".json"), options: .atomic)
        }
    }

    public func nextID(prefix: String) -> String {
        let numbers = scenarios.compactMap { scenario -> Int? in
            guard scenario.id.hasPrefix(prefix + "-") else { return nil }
            return Int(scenario.id.dropFirst(prefix.count + 1))
        }
        return String(format: "%@-%03d", prefix, (numbers.max() ?? 0) + 1)
    }

    /// Runs every scenario of a domain.
    public func run(domain: ScenarioDomain) -> [DomainResult] {
        scenarios(in: domain.id).map { domain.result(for: $0) }
    }
}
