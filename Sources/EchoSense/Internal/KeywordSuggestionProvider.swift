import Foundation

struct KeywordSuggestionProvider: SuggestionProvider {
    func suggestions(in context: ProviderContext) -> [SQLCompletionSuggestion] {
        let keywords = context.keywordProvider.keywords(for: context.dialect,
                                                        context: context.sqlContext)

        var seen = Set<String>()
        var results: [SQLCompletionSuggestion] = []

        for keyword in keywords {
            let lower = keyword.lowercased()
            guard seen.insert(lower).inserted else { continue }

            guard let score = context.identifier.fuzzyScore(for: lower) else {
                continue
            }

            let (display, insert) = KeywordSuggestionProvider.casedKeyword(keyword,
                                                                           option: context.request.options.keywordCasing)
            let basePriority = KeywordSuggestionProvider.priority(for: context.sqlContext.clause)
            let fuzzyAdjustment = score < 0.95 ? Int(-100 * (1.0 - score)) : 0
            let priority = basePriority + fuzzyAdjustment

            results.append(SQLCompletionSuggestion(id: "keyword|\(lower)",
                                                   title: display,
                                                   subtitle: nil,
                                                   detail: nil,
                                                   insertText: insert,
                                                   kind: .keyword,
                                                   priority: priority))
        }

        return results
    }

    private static func casedKeyword(_ keyword: String,
                                     option: SQLEngineOptions.KeywordCasing) -> (display: String, insert: String) {
        switch option {
        case .upper:
            let upper = keyword.uppercased()
            return (upper, upper)
        case .lower:
            let lower = keyword.lowercased()
            return (lower, lower)
        case .preserve:
            return (keyword.uppercased(), keyword)
        }
    }

    private static func priority(for clause: SQLClause) -> Int {
        switch clause {
        case .selectList, .whereClause, .having, .groupBy, .orderBy, .joinCondition:
            return 750
        case .from, .joinTarget, .deleteWhere:
            return 700
        default:
            return 650
        }
    }
}

protocol SQLKeywordProvider {
    func keywords(for dialect: SQLDialect, context: SQLContext) -> [String]
}

struct DefaultKeywordProvider: SQLKeywordProvider {
    func keywords(for dialect: SQLDialect, context: SQLContext) -> [String] {
        var ordered: [String] = []

        switch context.clause {
        case .selectList:
            ordered.append(contentsOf: Self.selectKeywords)
            ordered.append(contentsOf: dialectSelectKeywords(for: dialect))
        case .from, .joinTarget, .withCTE, .deleteWhere:
            ordered.append(contentsOf: Self.fromKeywords)
            ordered.append(contentsOf: dialectFromKeywords(for: dialect))
        case .whereClause, .joinCondition, .having:
            ordered.append(contentsOf: Self.filterKeywords)
            ordered.append(contentsOf: dialectFilterKeywords(for: dialect))
        case .groupBy:
            ordered.append(contentsOf: Self.groupKeywords)
        case .orderBy:
            ordered.append(contentsOf: Self.orderKeywords)
        case .values:
            ordered.append(contentsOf: Self.valuesKeywords)
            ordered.append(contentsOf: dialectValuesKeywords(for: dialect))
        case .updateSet:
            ordered.append(contentsOf: Self.updateKeywords)
            ordered.append(contentsOf: dialectUpdateKeywords(for: dialect))
        default:
            break
        }

        ordered.append(contentsOf: Self.commonKeywords)
        ordered.append(contentsOf: dialectCommonKeywords(for: dialect))
        return DefaultKeywordProvider.unique(ordered)
    }

    // MARK: - Shared keyword sets

    private static let commonKeywords: [String] = [
        "select", "where", "update", "delete", "group", "order", "from", "by",
        "create", "table", "drop", "alter", "view", "execute", "procedure",
        "distinct", "insert", "join", "having", "limit", "offset", "values", "set", "into"
    ]

    private static let selectKeywords: [String] = [
        "select", "distinct", "case", "when", "then", "else", "end", "from", "where",
        "group", "order", "limit", "offset", "having", "union", "intersect", "except",
        "as", "cast"
    ]

    private static let fromKeywords: [String] = [
        "from",
        "inner join",
        "left join",
        "right join",
        "full join",
        "left outer join",
        "right outer join",
        "full outer join",
        "cross join",
        "join",
        "on",
        "using",
        "where",
        "group",
        "partition",
        "lateral"
    ]

    private static let filterKeywords: [String] = [
        "where", "and", "or", "not", "exists", "in", "between", "like", "ilike",
        "is", "null", "coalesce", "any", "all", "some"
    ]

    private static let groupKeywords: [String] = [
        "group", "by", "rollup", "cube", "grouping", "sets", "having"
    ]

    private static let orderKeywords: [String] = [
        "order", "by", "asc", "desc", "nulls", "first", "last"
    ]

    private static let valuesKeywords: [String] = [
        "values", "returning", "default"
    ]

    private static let updateKeywords: [String] = [
        "set", "from", "where", "returning"
    ]

    // MARK: - Dialect-specific keyword sets

    private func dialectSelectKeywords(for dialect: SQLDialect) -> [String] {
        switch dialect {
        case .postgresql:
            return ["distinct on", "filter", "within group", "over", "partition by"]
        case .microsoftSQL:
            return ["top", "over", "partition by", "with ties"]
        default:
            return []
        }
    }

    private func dialectFromKeywords(for dialect: SQLDialect) -> [String] {
        switch dialect {
        case .postgresql:
            return ["lateral", "tablesample"]
        case .microsoftSQL:
            return ["cross apply", "outer apply", "with (nolock)", "with (readuncommitted)"]
        default:
            return []
        }
    }

    private func dialectFilterKeywords(for dialect: SQLDialect) -> [String] {
        switch dialect {
        case .postgresql:
            return ["ilike", "similar to", "is distinct from", "is not distinct from"]
        case .microsoftSQL:
            return []
        default:
            return []
        }
    }

    private func dialectValuesKeywords(for dialect: SQLDialect) -> [String] {
        switch dialect {
        case .postgresql:
            return ["on conflict", "on conflict do nothing", "on conflict do update", "returning"]
        case .microsoftSQL:
            return ["output"]
        default:
            return []
        }
    }

    private func dialectUpdateKeywords(for dialect: SQLDialect) -> [String] {
        switch dialect {
        case .postgresql:
            return ["returning"]
        case .microsoftSQL:
            return ["output"]
        default:
            return []
        }
    }

    private func dialectCommonKeywords(for dialect: SQLDialect) -> [String] {
        switch dialect {
        case .postgresql:
            return ["returning", "on conflict", "for update", "for share",
                    "generated", "with", "recursive"]
        case .microsoftSQL:
            return ["top", "output", "merge", "declare", "go",
                    "begin", "end", "try", "catch", "throw",
                    "cross apply", "outer apply", "option", "fetch next",
                    "offset", "rows", "with"]
        default:
            return []
        }
    }

    private static func unique(_ keywords: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for keyword in keywords {
            let lower = keyword.lowercased()
            if seen.insert(lower).inserted {
                result.append(lower)
            }
        }
        return result
    }
}

enum AliasGenerator {
    static func shortcut(for name: String) -> String? {
        let components = name.split { !$0.isLetter && !$0.isNumber }
        var result: [Character] = []
        for component in components where !component.isEmpty {
            if let first = component.first {
                result.append(Character(first.lowercased()))
            }
            for scalar in component.unicodeScalars.dropFirst() {
                if CharacterSet.uppercaseLetters.contains(scalar) {
                    result.append(Character(String(scalar).lowercased()))
                }
            }
        }

        if !result.isEmpty {
            return String(result)
        }

        let trimmed = name.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard !trimmed.isEmpty else { return nil }
        let fallback = trimmed.prefix(3).map { Character(String($0).lowercased()) }
        return fallback.isEmpty ? nil : String(fallback)
    }
}
