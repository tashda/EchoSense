import EchoSenseScenarios
import Foundation

// echosense-scenarios run [--failing] [--group "SELECT Clause"] [--id SPEC-1.4]
// echosense-scenarios triage     mark failing scenarios as known issues, clear ones that now pass
// echosense-scenarios comment <id> "text" [--reopen]   answer the owner in a scenario's thread
//                    (--reopen sets its review back to not reviewed, so the owner looks again)
// echosense-scenarios domains [--domain statements] [--failing]   the other kinds (statements, GO, ...)
// echosense-scenarios domains-triage
// They read and write Sources/EchoSenseScenarios/Scenarios in this checkout.

@main
enum ScenarioCLI {
    static func main() {
        let directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Sources/EchoSenseScenarios/Scenarios")

        let domainDirectory = directory.deletingLastPathComponent().appending(path: "DomainScenarios")

        var arguments = Array(CommandLine.arguments.dropFirst())
        let command = arguments.isEmpty ? "run" : arguments.removeFirst()
        let args = arguments
        func option(_ name: String) -> String? {
            guard let index = args.firstIndex(of: name), args.indices.contains(index + 1) else { return nil }
            return args[index + 1]
        }

        do {
            var library = try ScenarioLibrary.load(directory: directory)
            let runner = CompletionScenarioRunner()
            switch command {
            case "run":
                var pass = 0, fail = 0, known = 0, unchecked = 0
                for scenario in library.scenarios {
                    if let group = option("--group"), scenario.group != group { continue }
                    if let id = option("--id"), scenario.id != id { continue }
                    let result = runner.run(scenario)
                    let mark: String
                    if result.isFailing {
                        if scenario.knownIssue != nil { known += 1; mark = "known" } else { fail += 1; mark = "FAIL " }
                    } else if result.isPass { pass += 1; mark = "PASS " } else { unchecked += 1; mark = "  -  " }
                    if args.contains("--failing"), result.isAsExpected { continue }
                    print("\(mark) \(scenario.id)  \(scenario.title)")
                    if result.isFailing, scenario.knownIssue == nil {
                        for reason in result.failureReasons { print("        \(reason)") }
                    }
                }
                print("\n\(pass) pass, \(fail) fail, \(known) known issues, \(unchecked) without an expectation")
                exit(fail == 0 ? 0 : 1)
            case "comment":
                guard args.count >= 2, let index = library.scenarios.firstIndex(where: { $0.id == args[0] }) else {
                    print("Usage: echosense-scenarios comment <id> \"text\" [--reopen]"); exit(1)
                }
                library.scenarios[index].comments.append(ScenarioComment(author: .agent, text: args[1]))
                if args.contains("--reopen") { library.scenarios[index].review = .imported }
                try library.write(to: directory)
                print("Answered \(args[0])\(args.contains("--reopen") ? " and set it back to not reviewed" : "").")
            case "triage":
                var marked = 0, cleared = 0
                for index in library.scenarios.indices {
                    let scenario = library.scenarios[index]
                    let result = runner.run(scenario)
                    if result.isFailing, scenario.knownIssue == nil {
                        library.scenarios[index].knownIssue = "Fails today: " + (result.failureReasons.first ?? "it disagrees")
                        marked += 1
                    } else if !result.isFailing, scenario.knownIssue != nil {
                        library.scenarios[index].knownIssue = nil
                        cleared += 1
                    }
                }
                try library.write(to: directory)
                print("Marked \(marked) as known issues, cleared \(cleared) that pass now.")
            case "domains", "domains-triage":
                var domainLibrary = try DomainLibrary.load(directory: domainDirectory)
                var pass = 0, fail = 0, known = 0, unchecked = 0, changed = 0
                for domain in ScenarioDomains.all {
                    if let only = option("--domain"), domain.id != only { continue }
                    for index in domainLibrary.scenarios.indices where domainLibrary.scenarios[index].domain == domain.id {
                        let scenario = domainLibrary.scenarios[index]
                        let result = domain.result(for: scenario)
                        if command == "domains-triage" {
                            let failing = scenario.expected != nil && scenario.expected != result.actual
                            if failing, scenario.knownIssue == nil {
                                domainLibrary.scenarios[index].knownIssue = "Fails today: " + (result.differences.first ?? "it disagrees")
                                changed += 1
                            } else if !failing, scenario.knownIssue != nil, scenario.expected != nil {
                                domainLibrary.scenarios[index].knownIssue = nil
                                changed += 1
                            }
                            continue
                        }
                        let mark: String
                        switch result.verdict {
                        case .pass: pass += 1; mark = "PASS "
                        case .fail: fail += 1; mark = "FAIL "
                        case .knownIssue: known += 1; mark = "known"
                        case .noExpectation: unchecked += 1; mark = "  -  "
                        }
                        if args.contains("--failing"), result.verdict == .pass { continue }
                        print("\(mark) \(scenario.id)  \(scenario.title)")
                        if result.verdict == .fail || (args.contains("--why") && result.verdict == .knownIssue) {
                            for line in result.differences { print("        \(line.replacingOccurrences(of: "\n", with: "\\n"))") }
                        }
                    }
                }
                if command == "domains-triage" {
                    try domainLibrary.write(to: domainDirectory)
                    print("Changed \(changed) known-issue flags.")
                } else {
                    print("\n\(pass) pass, \(fail) fail, \(known) known issues, \(unchecked) without an expectation")
                    exit(fail == 0 ? 0 : 1)
                }
            default:
                print("Usage: echosense-scenarios run [--failing] [--group NAME] [--id ID] | triage | domains [--domain ID] [--failing] [--why] | domains-triage")
                exit(2)
            }
        } catch {
            print("\(error)")
            exit(2)
        }

    }
}
