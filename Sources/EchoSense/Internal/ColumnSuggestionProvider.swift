import Foundation

struct ColumnSuggestionProvider: SuggestionProvider {
    func suggestions(in context: ProviderContext) -> [SQLCompletionSuggestion] {
        guard !context.sqlContext.tablesInScope.isEmpty else { return [] }

        let clause = context.sqlContext.clause
        let isColumnClause = Self.supportedClauses.contains(clause) || context.hasColumnKeywordContext
        guard isColumnClause else { return [] }

        let identifier = context.identifier
        let prefix = identifier.lowercasePrefix
        let segments = identifier.precedingLowercased

        var results: [SQLCompletionSuggestion] = []
        var seen = Set<String>()

        let forceQualifier = context.sqlContext.tablesInScope.count > 1

        for tableRef in context.sqlContext.tablesInScope {
            let match = Self.matchKind(for: tableRef, segments: segments)
            guard match != .none else { continue }

            if let resolved = context.resolve(tableRef) {
                appendColumns(from: resolved,
                              tableRef: tableRef,
                              match: match,
                              prefix: prefix,
                              clause: clause,
                              forceQualifier: forceQualifier,
                              context: context,
                              results: &results,
                              seen: &seen)
            } else if let cteColumns = context.cteColumns(for: tableRef) {
                appendCTEColumns(cteColumns,
                                 tableRef: tableRef,
                                 match: match,
                                 prefix: prefix,
                                 clause: clause,
                                 forceQualifier: forceQualifier,
                                 context: context,
                                 results: &results,
                                 seen: &seen)
            }
        }

        return results
    }

    private static func matchKind(for reference: SQLContext.TableReference,
                                  segments: [String]) -> ColumnPathMatch {
        guard !segments.isEmpty else { return .any }

        let last = segments.last!
        if let alias = reference.alias?.lowercased(),
           last == alias {
            return .alias
        }

        if last == reference.name.lowercased() {
            if segments.count == 1 {
                return .table
            }
            let beforeLast = segments[segments.count - 2]
            if let schema = reference.schema?.lowercased(),
               schema == beforeLast {
                return .table
            }
        }

        if segments.count >= 2,
           let alias = reference.alias?.lowercased(),
           segments[segments.count - 2] == alias,
           last == reference.name.lowercased() {
            return .alias
        }

        return .none
    }

    private static func priority(for clause: SQLClause) -> Int {
        switch clause {
        case .selectList:
            return 1500
        case .whereClause, .having, .joinCondition:
            return 1450
        case .groupBy, .orderBy:
            return 1400
        case .values, .updateSet:
            return 1350
        default:
            return 1250
        }
    }

    private enum ColumnPathMatch {
        case any
        case alias
        case table
        case none
    }

    private static let supportedClauses: Set<SQLClause> = [
        .selectList, .whereClause, .having, .joinCondition, .groupBy, .orderBy, .values, .updateSet
    ]

    private func appendColumns(from resolution: TableResolution,
                               tableRef: SQLContext.TableReference,
                               match: ColumnPathMatch,
                               prefix: String,
                               clause: SQLClause,
                               forceQualifier: Bool,
                               context: ProviderContext,
                               results: inout [SQLCompletionSuggestion],
                               seen: inout Set<String>) {
        let includeAlias = match != .table ? tableRef.alias != nil : (tableRef.alias != nil)
        let includeUnqualified = match != .alias

        for column in resolution.object.columns {
            let lower = column.name.lowercased()
            var fuzzyPenalty = 0
            if !prefix.isEmpty {
                guard let score = FuzzyMatcher.match(pattern: prefix, candidate: column.name)?.score else {
                    continue
                }
                if score < 0.95 { fuzzyPenalty = Int(-100 * (1.0 - score)) }
            }

            let baseID = "column|\(resolution.schema.name.lowercased())|\(resolution.object.name.lowercased())|\(lower)"
            let priority = Self.priority(for: clause) + ColumnSuggestionProvider.priorityBoost(for: column) + fuzzyPenalty

            if includeAlias, let alias = tableRef.alias {
                let aliasKey = baseID + "|alias=" + alias.lowercased()
                if seen.insert(aliasKey).inserted {
                    let columnName = context.quotedColumn(column.name)
                    let title = "\(alias).\(columnName)"
                    results.append(SQLCompletionSuggestion(id: aliasKey,
                                                           title: title,
                                                           subtitle: "\(resolution.object.name) • \(resolution.schema.name)",
                                                           detail: "Column \(resolution.schema.name).\(resolution.object.name).\(column.name)",
                                                           insertText: title,
                                                           kind: .column,
                                                           priority: priority + 10))
                }
            }

            if includeUnqualified, seen.insert(baseID).inserted {
                let needsQualifier = qualifierNeeded(match: match, forceQualifier: forceQualifier)
                let chosenQualifier = tableRef.alias ?? tableRef.name
                let columnName = context.quotedColumn(column.name)
                let insert: String
                if needsQualifier {
                    let qualifierText = context.qualifier(for: tableRef, candidate: chosenQualifier)
                    insert = "\(qualifierText).\(columnName)"
                } else {
                    insert = columnName
                }
                let title = insert
                results.append(SQLCompletionSuggestion(id: baseID,
                                                       title: title,
                                                       subtitle: "\(resolution.object.name) • \(resolution.schema.name)",
                                                       detail: "Column \(resolution.schema.name).\(resolution.object.name).\(column.name)",
                                                       insertText: insert,
                                                       kind: .column,
                                                       priority: priority))
            }
        }
    }

    private func appendCTEColumns(_ columns: [String],
                                  tableRef: SQLContext.TableReference,
                                  match: ColumnPathMatch,
                                  prefix: String,
                                  clause: SQLClause,
                                  forceQualifier: Bool,
                                  context: ProviderContext,
                                  results: inout [SQLCompletionSuggestion],
                                  seen: inout Set<String>) {
        let includeAlias = match != .table ? tableRef.alias != nil : (tableRef.alias != nil)
        let includeUnqualified = match != .alias
        let qualifier = tableRef.alias ?? tableRef.name

        for column in columns {
            let lower = column.lowercased()
            var fuzzyPenalty = 0
            if !prefix.isEmpty {
                guard let score = FuzzyMatcher.match(pattern: prefix, candidate: column)?.score else {
                    continue
                }
                if score < 0.95 { fuzzyPenalty = Int(-100 * (1.0 - score)) }
            }

            let baseID = "cte|\(qualifier.lowercased())|\(lower)"
            let priority = Self.priority(for: clause) + fuzzyPenalty

            if includeAlias, let alias = tableRef.alias {
                let aliasKey = baseID + "|alias=" + alias.lowercased()
                if seen.insert(aliasKey).inserted {
                    let columnName = context.quotedColumn(column)
                    let title = "\(alias).\(columnName)"
                    results.append(SQLCompletionSuggestion(id: aliasKey,
                                                           title: title,
                                                           subtitle: qualifier,
                                                           detail: "CTE Column \(qualifier).\(column)",
                                                           insertText: title,
                                                           kind: .column,
                                                           priority: priority + 5))
                }
            }

            if includeUnqualified, seen.insert(baseID).inserted {
                let needsQualifier = qualifierNeeded(match: match, forceQualifier: forceQualifier)
                let chosenQualifier = tableRef.alias ?? tableRef.name
                let columnName = context.quotedColumn(column)
                let insert: String
                if needsQualifier {
                    let qualifierText = context.qualifier(for: tableRef, candidate: chosenQualifier)
                    insert = "\(qualifierText).\(columnName)"
                } else {
                    insert = columnName
                }
                let title = insert
                results.append(SQLCompletionSuggestion(id: baseID,
                                                       title: title,
                                                       subtitle: qualifier,
                                                       detail: "CTE Column \(qualifier).\(column)",
                                                       insertText: insert,
                                                       kind: .column,
                                                       priority: priority))
            }
        }
    }

    private static func priorityBoost(for column: SQLColumn) -> Int {
        if column.isPrimaryKey {
            return 40
        }
        if column.isForeignKey {
            return 20
        }
        return 0
    }

    private func qualifierNeeded(match: ColumnPathMatch, forceQualifier: Bool) -> Bool {
        switch match {
        case .alias:
            return true
        case .table:
            return forceQualifier
        case .any:
            return forceQualifier
        case .none:
            return false
        }
    }
}

struct StarExpansionProvider: SuggestionProvider {
    func suggestions(in context: ProviderContext) -> [SQLCompletionSuggestion] {
        guard context.sqlContext.clause == .selectList else { return [] }
        let token = context.identifier.trimmedToken
        guard token == "*" || token.hasSuffix(".*") else { return [] }

        let aliasFilter = context.identifier.precedingLowercased.last
        let references = context.sqlContext.tablesInScope.filter { reference in
            guard let aliasFilter else { return true }
            if let alias = reference.alias?.lowercased(), alias == aliasFilter {
                return true
            }
            return reference.name.lowercased() == aliasFilter
        }

        let targets = references.isEmpty ? context.sqlContext.tablesInScope : references
        guard !targets.isEmpty else { return [] }

        var columnIdentifiers: [String] = []
        for reference in targets {
            if let resolution = context.resolve(reference) {
                let qualifier = qualifierFor(reference: reference,
                                             forceQualifier: aliasFilter != nil,
                                             totalTargets: targets.count)
                for column in resolution.object.columns {
                    if let qualifier {
                        columnIdentifiers.append("\(qualifier).\(column.name)")
                    } else {
                        columnIdentifiers.append(column.name)
                    }
                }
            } else if let cteColumns = context.cteColumns(for: reference) {
                let qualifier = qualifierFor(reference: reference,
                                             forceQualifier: aliasFilter != nil,
                                             totalTargets: targets.count)
                for column in cteColumns {
                    if let qualifier {
                        let qualifierText = context.qualifier(for: reference, candidate: qualifier)
                        let columnName = context.quotedColumn(column)
                        columnIdentifiers.append("\(qualifierText).\(columnName)")
                    } else {
                        columnIdentifiers.append(context.quotedColumn(column))
                    }
                }
            }
        }

        guard !columnIdentifiers.isEmpty else { return [] }

        let insertText = columnIdentifiers.joined(separator: ", ")
        let detailPreviewCount = min(4, columnIdentifiers.count)
        let preview = columnIdentifiers.prefix(detailPreviewCount).joined(separator: ", ")
        let detail = columnIdentifiers.count > detailPreviewCount ? preview + ", …" : preview

        let identifier = columnIdentifiers.joined(separator: "|").lowercased()
        return [
            SQLCompletionSuggestion(id: "star|\(identifier)",
                                    title: "Expand * to columns",
                                    subtitle: "Star Expansion",
                                    detail: detail,
                                    insertText: insertText,
                                    kind: .snippet,
                                    priority: 1600)
        ]
    }

    private func qualifierFor(reference: SQLContext.TableReference,
                              forceQualifier: Bool,
                              totalTargets: Int) -> String? {
        if forceQualifier {
            return reference.alias ?? reference.name
        }
        if totalTargets > 1 {
            return reference.alias ?? reference.name
        }
        return reference.alias
    }
}
