import Foundation

/// An expectation, read as checks. `compare` is built from these, so a verdict is always "every check holds".
public extension CompletionScenarioRunner {
    /// Presence is checked per title up to this many; a longer list is one check.
    static let itemChecksLimit = 8

    /// What EchoSense should return, as checks against what it returned.
    static func checks(_ expected: EchoSenseExpectation, actual rawActual: ScenarioActual, trigger: ScenarioTrigger) -> [ScenarioCheck] {
        // Titles are compared without identifier quoting: "name" and name are the same suggestion. What
        // gets inserted (with its quotes) is checked by `insertText`.
        let titles = rawActual.titles.map(unquoted)
        let manualTitles = rawActual.manualTitles.map(unquoted)
        let engineTitles = rawActual.engineTitles.map(unquoted)
        let insertText = Dictionary(rawActual.insertText.map { (unquoted($0.key), $0.value) }, uniquingKeysWith: { first, _ in first })
        var checks: [ScenarioCheck] = []

        switch expected.outcome {
        case .nothing:
            checks.append(ScenarioCheck(
                id: "nothing", statement: "offers nothing",
                problem: titles.isEmpty ? nil : .offered(titles),
                failure: titles.isEmpty ? nil : "Expected nothing, but it offered \(list(titles))."))
            checks.append(ScenarioCheck(
                id: "nothing-by-hand", statement: "offers nothing when asked by hand (⌘.) either",
                problem: manualTitles.isEmpty ? nil : .offered(manualTitles),
                failure: manualTitles.isEmpty ? nil : "Expected nothing even when triggered by hand, but that offered \(list(manualTitles))."))
        case .silent:
            checks.append(ScenarioCheck(
                id: "silent", statement: "stays silent while typing",
                problem: titles.isEmpty ? nil : .offered(titles),
                failure: titles.isEmpty ? nil : "Expected silence while typing, but it offered \(list(titles))."))
        case .suggests:
            checks.append(popupCheck(titles: titles, engineTitles: engineTitles, triggerNote: rawActual.triggerNote))
            checks += presenceChecks(expected.items, titles: titles)
            checks += orderChecks(expected, titles: titles)
        }

        for title in expected.excludes {
            let offered = titles.contains(title)
            checks.append(ScenarioCheck(
                id: "never:\(title)", statement: "never offers `\(title)`",
                problem: offered ? .unwanted([title]) : nil,
                failure: offered ? "Should not offer: \(title)." : nil))
        }

        for (title, text) in expected.insertText.sorted(by: { $0.key < $1.key }) {
            let got = insertText[title]
            let failure: String? = switch got {
            case .some(let got) where got == text: nil
            case .some(let got): "“\(title)” should insert “\(text)”, but inserts “\(got)”."
            case .none: "“\(title)” should insert “\(text)”, but it isn't offered."
            }
            checks.append(ScenarioCheck(
                id: "inserts:\(title)", statement: "`\(title)` inserts `\(text)`",
                problem: failure == nil ? nil : .wrongInsert(title), failure: failure))
        }
        return checks
    }

    /// What Echo's editor should do, as checks: the popup, the selected suggestion, the text after accepting.
    static func checks(_ expected: EchoExpectation, actual: ScenarioActual) -> [ScenarioCheck] {
        var checks: [ScenarioCheck] = []
        if let popup = expected.popup {
            let holds = (popup == .shown) == actual.popupShown
            checks.append(ScenarioCheck(
                id: "editor:popup", subject: .editor, statement: popup == .shown ? "the popup opens" : "the popup stays closed",
                problem: holds ? nil : .editor(popup == .shown ? "popup doesn't open" : "popup opens"),
                failure: holds ? nil : (popup == .shown ? "Expected the popup to open. \(actual.triggerNote)" : "Expected no popup, but it opens with \(list(actual.titles)).")))
        }
        if let selected = expected.selected {
            let first = actual.titles.first.map(unquoted)
            let holds = first == unquoted(selected)
            checks.append(ScenarioCheck(
                id: "editor:selected", subject: .editor, statement: "`\(selected)` is selected when the popup opens",
                problem: holds ? nil : .editor(first.map { "selects \($0)" } ?? "nothing selected"),
                failure: holds ? nil : "Expected “\(selected)” to be selected, but \(first.map { "“\($0)” is" } ?? "nothing is")."))
        }
        if let after = expected.textAfterAccepting {
            let accept = expected.accept.flatMap { $0.isEmpty ? nil : $0 }
            let got = accept.flatMap { actual.textAfterAcceptingByTitle[unquoted($0)] } ?? actual.textAfterAccepting
            let holds = after == got
            let which = accept.map { "accepting `\($0)`" } ?? "accepting the selected suggestion"
            checks.append(ScenarioCheck(
                id: "editor:after", subject: .editor, statement: "\(which) gives `\(after.replacingOccurrences(of: "\n", with: "⏎"))`",
                problem: holds ? nil : .editor("wrong text after accepting"),
                failure: holds ? nil : "Expected the text after accepting\(accept.map { " “\($0)”" } ?? "") to be “\(after.replacingOccurrences(of: "\n", with: "⏎"))”, but it is “\((got ?? "not offered").replacingOccurrences(of: "\n", with: "⏎"))”."))
        }
        return checks
    }

    /// What a shared rule checks: titles and kinds it forbids, and the order kinds must rank in.
    static func checks(_ rule: ScenarioRule, actual rawActual: ScenarioActual) -> [ScenarioCheck] {
        let titles = rawActual.titles.map(unquoted)
        let kinds = Dictionary(rawActual.kinds.map { (unquoted($0.key), $0.value) }, uniquingKeysWith: { first, _ in first })
        var checks: [ScenarioCheck] = []
        for title in rule.excludes {
            let offered = titles.contains(title)
            checks.append(ScenarioCheck(
                id: "rule:\(rule.id):never:\(title)", statement: "never offers `\(title)`",
                problem: offered ? .unwanted([title]) : nil, failure: offered ? "Should not offer: \(title) (rule \(rule.id))." : nil, rule: rule.id))
        }
        for kind in rule.excludedKinds {
            let offending = titles.filter { kinds[$0] == kind }
            checks.append(ScenarioCheck(
                id: "rule:\(rule.id):never-kind:\(kind)", statement: "never offers a \(kindName(kind))",
                problem: offending.isEmpty ? nil : .unwanted(offending),
                failure: offending.isEmpty ? nil : "Offers \(kindName(kind, plural: true)) \(list(offending)), which rule \(rule.id) forbids.", rule: rule.id))
        }
        if rule.kindOrder.count > 1 {
            // Walk the popup: a suggestion of an earlier kind after one of a later kind breaks the order.
            var latest: (index: Int, title: String)?
            var broken: (early: String, late: String)?
            for title in titles {
                guard let kind = kinds[title], let index = rule.kindOrder.firstIndex(of: kind) else { continue }
                if let current = latest, index < current.index { broken = (title, current.title); break }
                if latest == nil || index > latest!.index { latest = (index, title) }
            }
            let order = rule.kindOrder.map { kindName($0, plural: true) }
            checks.append(ScenarioCheck(
                id: "rule:\(rule.id):kind-order", statement: "\(order.joined(separator: " before "))",
                problem: broken == nil ? nil : .wrongOrder,
                failure: broken.map { "`\($0.early)` (\(kindName(kinds[$0.early] ?? ""))) comes after `\($0.late)` (\(kindName(kinds[$0.late] ?? ""))); rule \(rule.id) wants \(order.joined(separator: " before "))." },
                rule: rule.id))
        }
        return checks
    }

    /// A kind for reading: "materializedView" is "materialized view".
    static func kindName(_ kind: String, plural: Bool = false) -> String {
        let spaced = kind.reduce(into: "") { text, character in
            if character.isUppercase { text += " " + character.lowercased() } else { text.append(character) }
        }
        return plural ? spaced + "s" : spaced
    }

    /// "`a` is #3, `b` isn't offered".
    static func ranks(_ items: [String], in titles: [String]) -> String {
        items.prefix(6).map { item in
            titles.firstIndex(of: item).map { "\(item) is #\($0 + 1)" } ?? "\(item) isn't offered"
        }.joined(separator: ", ") + (items.count > 6 ? " and \(items.count - 6) more" : "")
    }

    /// Every check that doesn't hold, as a verdict.
    static func verdict(_ checks: [ScenarioCheck]) -> ScenarioVerdict {
        let failures = checks.compactMap(\.failure)
        return failures.isEmpty ? .pass : .fail(failures)
    }

    // MARK: Pieces

    private static func popupCheck(titles: [String], engineTitles: [String], triggerNote: String) -> ScenarioCheck {
        guard titles.isEmpty else { return ScenarioCheck(id: "suggests", statement: "opens the popup with suggestions") }
        return engineTitles.isEmpty
            ? ScenarioCheck(id: "suggests", statement: "opens the popup with suggestions", problem: .nothingOffered,
                            failure: "Expected suggestions, but EchoSense offered nothing.")
            : ScenarioCheck(id: "suggests", statement: "opens the popup with suggestions", problem: .popupClosed,
                            failure: "Expected suggestions, but the popup doesn't open. \(triggerNote) EchoSense would offer \(list(engineTitles)).")
    }

    private static func presenceChecks(_ items: [String], titles: [String]) -> [ScenarioCheck] {
        guard !items.isEmpty else { return [] }
        if items.count > itemChecksLimit {
            let missing = items.filter { !titles.contains($0) }
            return [ScenarioCheck(
                id: "offers:all", statement: "offers all \(items.count) expected items",
                problem: missing.isEmpty ? nil : .missing(missing),
                failure: missing.isEmpty ? nil : "Missing: \(list(missing)).")]
        }
        return items.map { title in
            let offered = titles.contains(title)
            return ScenarioCheck(
                id: "offers:\(title)", statement: "offers `\(title)`",
                problem: offered ? nil : .missing([title]),
                failure: offered ? nil : "Missing: \(title).")
        }
    }

    private static func orderChecks(_ expected: EchoSenseExpectation, titles: [String]) -> [ScenarioCheck] {
        let items = expected.items
        switch expected.order {
        case .includes:
            return []
        case .leading:
            let got = Array(titles.prefix(items.count))
            let holds = got == items
            let shown = items.prefix(4).map { "`\($0)`" }.joined(separator: ", ") + (items.count > 4 ? " and \(items.count - 4) more" : "")
            return [ScenarioCheck(
                id: "first", statement: items.count == 1 ? "offers \(shown) first" : "offers \(shown) first, in this order",
                problem: holds ? nil : .wrongOrder,
                failure: holds ? nil : "Expected these first, in this order: \(list(items)). Now: \(ranks(items, in: titles)).")]
        case .exact:
            let extra = titles.filter { !items.contains($0) }
            var checks = [ScenarioCheck(
                id: "nothing-else", statement: items.isEmpty ? "offers nothing" : "offers nothing else",
                problem: extra.isEmpty ? nil : .offered(extra),
                failure: extra.isEmpty ? nil : "Also offers \(list(extra)).")]
            let sameItems = extra.isEmpty && items.allSatisfy(titles.contains)
            if items.count > 1 {
                let holds = !sameItems || titles == items
                checks.append(ScenarioCheck(
                    id: "order", statement: "in exactly this order",
                    problem: holds ? nil : .wrongOrder,
                    failure: holds ? nil : "Same items, different order. Got: \(list(titles))."))
            }
            return checks
        }
    }
}
