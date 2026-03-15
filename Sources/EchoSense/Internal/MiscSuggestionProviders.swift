import Foundation

struct FunctionSuggestionProvider: SuggestionProvider {
    func suggestions(in context: ProviderContext) -> [SQLCompletionSuggestion] {
        let clause = context.sqlContext.clause
        let isColumnClause = Self.supportedClauses.contains(clause) || context.hasColumnKeywordContext
        guard isColumnClause else { return [] }

        var results: [SQLCompletionSuggestion] = []
        var seen = Set<String>()

        for schema in context.catalog.schemas {
            for object in schema.objects where object.type == .function {
                let lower = object.name.lowercased()
                guard let score = context.identifier.fuzzyScore(for: object.name) else {
                    continue
                }
                let id = "function|\(schema.name.lowercased())|\(lower)"
                guard seen.insert(id).inserted else { continue }

                let fuzzyAdjustment = score < 0.95 ? Int(-100 * (1.0 - score)) : 0
                let priority = Self.priority(for: clause) + fuzzyAdjustment
                results.append(SQLCompletionSuggestion(id: id,
                                                       title: object.name,
                                                       subtitle: schema.name,
                                                       detail: "Function \(schema.name).\(object.name)",
                                                       insertText: object.name + "(",
                                                       kind: .function,
                                                       priority: priority))
            }
        }

        return results
    }

    private static func priority(for clause: SQLClause) -> Int {
        switch clause {
        case .selectList:
            return 1200
        case .whereClause, .having, .joinCondition:
            return 1150
        default:
            return 1100
        }
    }

    private static let supportedClauses: Set<SQLClause> = [
        .selectList, .whereClause, .having, .groupBy, .orderBy, .joinCondition, .values, .updateSet
    ]
}

struct ParameterSuggestionProvider: SuggestionProvider {
    func suggestions(in context: ProviderContext) -> [SQLCompletionSuggestion] {
        guard Self.supportedClauses.contains(context.sqlContext.clause) else { return [] }

        let candidates = SQLParameterSuggester.parameterSuggestions(for: context.request.text,
                                                                    dialect: context.dialect)
        var results: [SQLCompletionSuggestion] = []

        for candidate in candidates {
            let lower = candidate.lowercased()
            guard context.identifier.fuzzyScore(for: candidate) != nil else {
                continue
            }
            results.append(SQLCompletionSuggestion(id: "parameter|\(lower)",
                                                   title: candidate,
                                                   subtitle: "Parameter",
                                                   detail: nil,
                                                   insertText: candidate,
                                                   kind: .parameter,
                                                   priority: 1300))
        }

        return results
    }

    private static let supportedClauses: Set<SQLClause> = [
        .whereClause, .having, .joinCondition, .values, .updateSet, .selectList
    ]
}

struct SnippetSuggestionProvider: SuggestionProvider {
    func suggestions(in context: ProviderContext) -> [SQLCompletionSuggestion] {
        let allowedGroups = Self.allowedGroups(for: context.sqlContext.clause)
        guard !allowedGroups.isEmpty else { return [] }

        let snippets = SQLSnippetCatalog.snippets(for: context.dialect)

        var results: [SQLCompletionSuggestion] = []
        for snippet in snippets where allowedGroups.contains(snippet.group) {
            guard let score = context.identifier.fuzzyScore(for: snippet.title) else {
                continue
            }
            let fuzzyAdjustment = score < 0.95 ? Int(-100 * (1.0 - score)) : 0
            results.append(SQLCompletionSuggestion(id: "snippet|\(snippet.id)",
                                                   title: snippet.title,
                                                   subtitle: "Snippet",
                                                   detail: snippet.detail,
                                                   insertText: snippet.insertText,
                                                   kind: .snippet,
                                                   priority: snippet.priority + fuzzyAdjustment))
        }

        return results
    }

    private static func allowedGroups(for clause: SQLClause) -> Set<SQLSnippet.Group> {
        switch clause {
        case .selectList:
            return [.select, .json, .general]
        case .whereClause, .having, .joinCondition:
            return [.filter, .json, .general]
        case .from, .joinTarget:
            return [.join, .general]
        case .values, .updateSet:
            return [.modification, .general]
        default:
            return [.general]
        }
    }
}
