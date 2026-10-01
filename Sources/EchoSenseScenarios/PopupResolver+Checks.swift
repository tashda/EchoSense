import Foundation

/// A popup rule in words, and judged against a real popup.
public extension PopupResolver {
    // MARK: Words

    /// "Tables and views in public, not yet in the query, starting with `us`".
    func describe(_ block: PopupBlock, typed: Bool = false) -> String {
        let typedText = typed && !context.typed.isEmpty ? ", starting with `\(context.typed)`" : ""
        let query = context.tables.isEmpty ? "none yet" : context.tables.map(\.label).joined(separator: ", ")
        let dotName = context.dot.map { "`\($0.name)`" } ?? "the name"
        var text: String
        switch block.family {
        case .objects:
            let kinds = (block.kinds.isEmpty ? PopupBlock.objectKinds : block.kinds).map(Self.plural)
            let what = kinds.count > 1 ? kinds.dropLast().joined(separator: ", ") + " and " + (kinds.last ?? "") : kinds.first ?? "tables"
            let place: String = switch block.place {
            case .defaultSchema?: "in \(defaultSchema)"
            case .otherSchemas?: "in other schemas"
            case .schemaBeforeDot?: "in \(dotName), the schema before the dot"
            case .databaseBeforeDot?: "in \(dotName), the database before the dot"
            case .linkedByForeignKey?: "linked by a foreign key to the tables in the query (\(query))"
            case .inQuery?: "already in the query (\(query))"
            case .derived?: "defined in this query (CTEs and subqueries)"
            default: "in \(database)"
            }
            text = "\(what) \(place)\(block.notInQuery ? ", not yet in the query" : "")"
        case .columns:
            let which = block.keysOnly ? "key columns (primary and foreign keys)" : "columns"
            let of: String = switch block.place {
            case .beforeDot?: "of \(dotName)\(context.dot?.table.map { $0 != context.dot?.name ? " (\($0))" : "" } ?? ""), before the dot"
            case .changedTable?: "of \(context.changedTable.map { "`\($0)`" } ?? "the table"), the table being changed"
            case .selectList?: "already in the SELECT list"
            default: "of the \(context.tables.count == 1 ? "table" : "\(context.tables.count) tables") in the query (\(query))"
            }
            text = "\(which) \(of)"
        case .functions:
            text = switch block.place {
            case .aggregate?: "aggregate functions (COUNT, SUM, AVG, MIN, MAX)"
            case .database?: "functions and procedures in \(database)"
            case .otherDialects?: "functions from other databases (\(Self.otherDialectFunctions(dialect).joined(separator: ", ")))"
            default: "built-in \(dialect.title) functions"
            }
        case .keywords:
            text = switch block.place {
            case .sort?: "sort keywords (ASC, DESC, NULLS FIRST, NULLS LAST)"
            case .operators?: "operator keywords (\(Self.operatorKeywords(dialect).joined(separator: ", ")))"
            default: "keywords that fit here"
            }
        case .schemas: text = block.place == .databaseBeforeDot ? "schemas in \(dotName), the database before the dot" : "schemas in \(database)"
        case .databases: text = "database names"
        case .snippets: text = "snippets"
        case .parameters: text = "parameters"
        }
        text += typedText
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    static func plural(_ kind: String) -> String {
        switch kind { case "materializedView": "materialized views"; default: kind + "s" }
    }

    /// The whole rule as one paragraph, for a list or for an agent.
    func describe(_ rule: PopupExpectation) -> String {
        var parts = rule.groups.enumerated().map { index, group in
            "\(Self.ordinal(index)): \(describe(group.block, typed: group.typed))"
                + (group.order.count > 1 ? " (\(group.order.joined(separator: ", ")) in this order)" : "")
                + (group.include.isEmpty ? "" : " (including \(group.include.joined(separator: ", ")))")
        }
        parts.append(rule.rest == .none ? "nothing else" : "anything else after")
        parts += rule.never.map { "never " + describe($0).lowercased() }
        return parts.joined(separator: "; ") + "."
    }

    static func ordinal(_ index: Int) -> String {
        ["1st", "2nd", "3rd"].indices.contains(index) ? ["1st", "2nd", "3rd"][index] : "\(index + 1)th"
    }

    // MARK: Checks

    /// The checks a popup rule makes against a popup, in the order the owner reads the rule.
    func checks(_ rule: PopupExpectation, rows: [ScenarioActual.Row]) -> [ScenarioCheck] {
        var checks: [ScenarioCheck] = []
        // Each row belongs to the first group that names it; a repeated title is reported once, as a repeat.
        var seen = Set<String>()
        let placed: [(row: ScenarioActual.Row, index: Int, group: Int?, repeated: Bool)] = rows.enumerated().map { index, row in
            let key = CompletionScenarioRunner.unquoted(row.title).lowercased()
            let repeated = !seen.insert(key).inserted
            let group = repeated ? nil : rule.groups.firstIndex { matches(title: row.title, kind: row.kind, block: $0.block, typed: $0.typed) }
            return (row, index, group, repeated)
        }

        var claimed = Set<String>()
        for (index, group) in rule.groups.enumerated() {
            let label = "\(Self.ordinal(index)): \(describe(group.block, typed: group.typed))"
            let items = items(group.block, typed: group.typed, order: group.order)
            var needed = (items ?? []).map(\.name).filter { !claimed.contains($0.lowercased()) } + group.include
            items?.forEach { claimed.insert($0.name.lowercased()) }
            needed = needed.reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
            let offered = Set(rows.map { CompletionScenarioRunner.unquoted($0.title).lowercased() })
            let missing = needed.filter { !offered.contains($0.lowercased()) }
            if let items, items.isEmpty {
                checks.append(ScenarioCheck(id: "group:\(index)", statement: label + " (none here)"))
            } else {
                checks.append(ScenarioCheck(id: "group:\(index)", statement: label,
                    problem: missing.isEmpty ? nil : .missing(missing), failure: missing.isEmpty ? nil : "Missing: \(CompletionScenarioRunner.list(missing))."))
            }
            let order = group.order.isEmpty ? group.include : group.order
            if order.count > 1 {
                let got = placed.filter { $0.group == index }.map { CompletionScenarioRunner.unquoted($0.row.title) }.filter { order.contains($0) }
                let want = order.filter { got.contains($0) }
                checks.append(ScenarioCheck(id: "group:\(index):order", statement: "inside the \(Self.ordinal(index).lowercased()) group: \(order.map { "`\($0)`" }.joined(separator: ", ")), in this order",
                    problem: got == want ? nil : .wrongOrder, failure: got == want ? nil : "It has \(got.joined(separator: ", "))."))
            }
        }

        if rule.groups.count > 1 {
            var top: (group: Int, title: String)?
            var broken: (early: String, earlyGroup: Int, late: String, lateGroup: Int)?
            for entry in placed {
                guard let group = entry.group else { continue }
                if let current = top, group < current.group, broken == nil {
                    broken = (CompletionScenarioRunner.unquoted(entry.row.title), group, current.title, current.group)
                }
                if top == nil || group > (top?.group ?? -1) { top = (group, CompletionScenarioRunner.unquoted(entry.row.title)) }
            }
            checks.append(ScenarioCheck(id: "groups:order", statement: "the groups come in this order, 1st before 2nd and so on",
                problem: broken == nil ? nil : .wrongOrder,
                failure: broken.map { "`\($0.early)` (\(Self.ordinal($0.earlyGroup)) group) comes after `\($0.late)` (\(Self.ordinal($0.lateGroup)) group)." }))
        }

        let forbidden = { (row: ScenarioActual.Row) in rule.never.contains { matches(title: row.title, kind: row.kind, block: $0) } }
        let others = placed.filter { $0.group == nil && !$0.repeated && !forbidden($0.row) }
        if rule.rest == .none {
            checks.append(ScenarioCheck(id: "rest", statement: "nothing else",
                problem: others.isEmpty ? nil : .offered(others.map { CompletionScenarioRunner.unquoted($0.row.title) }),
                failure: others.isEmpty ? nil : "Also offers \(Self.summary(others.map(\.row)))."))
        } else if !rule.groups.isEmpty {
            let last = placed.last { $0.group != nil }?.index ?? -1
            let early = others.filter { $0.index < last }
            checks.append(ScenarioCheck(id: "rest", statement: "anything else comes after the groups",
                problem: early.isEmpty ? nil : .wrongOrder,
                failure: early.isEmpty ? nil : "\(Self.summary(early.map(\.row))) before rows the rule lists."))
        }
        for (index, block) in rule.never.enumerated() {
            let bad = rows.filter { matches(title: $0.title, kind: $0.kind, block: block) }
            checks.append(ScenarioCheck(id: "never:\(index)", statement: "never: " + describe(block).lowercased(),
                problem: bad.isEmpty ? nil : .unwanted(bad.map { CompletionScenarioRunner.unquoted($0.title) }),
                failure: bad.isEmpty ? nil : "Offers \(Self.summary(bad))."))
        }
        let repeats = placed.filter(\.repeated).map { CompletionScenarioRunner.unquoted($0.row.title) }
        checks.append(ScenarioCheck(id: "repeats", statement: "nothing is offered twice",
            problem: repeats.isEmpty ? nil : .offered(repeats), failure: repeats.isEmpty ? nil : "\(repeats.joined(separator: ", ")) \(repeats.count == 1 ? "appears" : "appear") twice."))
        return checks
    }

    /// "44 keywords (ALTER, BY, CREATE, …), 1 schema (Built-in)".
    static func summary(_ rows: [ScenarioActual.Row]) -> String {
        var order: [String] = []
        var byKind: [String: [String]] = [:]
        for row in rows {
            if byKind[row.kind] == nil { order.append(row.kind) }
            byKind[row.kind, default: []].append(CompletionScenarioRunner.unquoted(row.title))
        }
        return order.map { kind in
            let names = byKind[kind] ?? []
            let word = kind == "materializedView" ? "materialized view" : kind
            return "\(names.count) \(word)\(names.count == 1 ? "" : "s") (\(names.prefix(4).joined(separator: ", "))\(names.count > 4 ? ", …" : ""))"
        }.joined(separator: ", ")
    }
}
