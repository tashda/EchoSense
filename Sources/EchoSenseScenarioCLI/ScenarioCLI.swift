import EchoSenseScenarios
import Foundation

// echosense-scenarios run [--failing] [--group "SELECT Clause"] [--id SPEC-1.4]
// echosense-scenarios triage     mark failing scenarios as known issues, clear ones that now pass
// Both read and write Sources/EchoSenseScenarios/Scenarios in this checkout.

@main
enum ScenarioCLI {
    static func main() {
        let directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Sources/EchoSenseScenarios/Scenarios")

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
                    switch result.verdict {
                    case .pass: pass += 1
                    case .unchecked: unchecked += 1
                    case .fail, .error: if scenario.knownIssue != nil { known += 1 } else { fail += 1 }
                    }
                    if args.contains("--failing"), result.isAsExpected { continue }
                    let mark: String
                    switch result.verdict {
                    case .pass: mark = "PASS "
                    case .unchecked: mark = "  -  "
                    case .fail, .error: mark = scenario.knownIssue != nil ? "known" : "FAIL "
                    }
                    print("\(mark) \(scenario.id)  \(scenario.title)")
                    if case .fail(let reasons) = result.verdict, scenario.knownIssue == nil {
                        for reason in reasons { print("        \(reason)") }
                    }
                }
                print("\n\(pass) pass, \(fail) fail, \(known) known issues, \(unchecked) without an expectation")
                exit(fail == 0 ? 0 : 1)
            case "triage":
                var marked = 0, cleared = 0
                for index in library.scenarios.indices {
                    let scenario = library.scenarios[index]
                    let result = runner.run(scenario)
                    if case .fail(let reasons) = result.verdict, scenario.knownIssue == nil {
                        library.scenarios[index].knownIssue = "Fails today: " + (reasons.first ?? "it disagrees")
                        marked += 1
                    } else if result.verdict.isPass, scenario.knownIssue != nil {
                        library.scenarios[index].knownIssue = nil
                        cleared += 1
                    }
                }
                try library.write(to: directory)
                print("Marked \(marked) as known issues, cleared \(cleared) that pass now.")
            default:
                print("Usage: echosense-scenarios run [--failing] [--group NAME] [--id ID] | triage")
                exit(2)
            }
        } catch {
            print("\(error)")
            exit(2)
        }

    }
}
