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

        // Build a set of ambiguous column names (exist in more than one table)
        let ambiguousColumns = Self.findAmbiguousColumns(tables: context.sqlContext.tablesInScope, context: context)
        let multipleTablesInScope = context.sqlContext.tablesInScope.count > 1

        for tableRef in context.sqlContext.tablesInScope {
            let match = Self.matchKind(for: tableRef, segments: segments)
            guard match != .none else { continue }

            if let resolved = context.resolve(tableRef) {
                appendColumns(from: resolved,
                              tableRef: tableRef,
                              match: match,
                              prefix: prefix,
                              clause: clause,
                              ambiguousColumns: ambiguousColumns,
                              multipleTablesInScope: multipleTablesInScope,
                              context: context,
                              results: &results,
                              seen: &seen)
            } else if let cteColumns = context.cteColumns(for: tableRef) {
                appendCTEColumns(cteColumns,
                                 tableRef: tableRef,
                                 match: match,
                                 prefix: prefix,
                                 clause: clause,
                                 ambiguousColumns: ambiguousColumns,
                                 multipleTablesInScope: multipleTablesInScope,
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
        .selectList, .whereClause, .having, .joinCondition, .groupBy, .orderBy, .values, .updateSet, .deleteWhere, .insertColumns
    ]

    private func appendColumns(from resolution: TableResolution,
                               tableRef: SQLContext.TableReference,
                               match: ColumnPathMatch,
                               prefix: String,
                               clause: SQLClause,
                               ambiguousColumns: Set<String>,
                               multipleTablesInScope: Bool,
                               context: ProviderContext,
                               results: inout [SQLCompletionSuggestion],
                               seen: inout Set<String>) {
        // When user typed an explicit qualifier (alias. or table.), only emit
        // unqualified column names — the qualifier is already in the editor.
        let userTypedQualifier = (match == .alias || match == .table) && !context.identifier.precedingSegments.isEmpty

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
            let columnName = context.quotedColumn(column.name)
            let isAmbiguous = ambiguousColumns.contains(lower)

            if userTypedQualifier {
                // User already typed the qualifier — just the column name
                let id = baseID + (tableRef.alias.map { "|alias=\($0.lowercased())" } ?? "")
                if seen.insert(id).inserted {
                    results.append(SQLCompletionSuggestion(id: id,
                                                           title: columnName,
                                                           subtitle: "\(resolution.object.name) • \(resolution.schema.name)",
                                                           detail: "Column \(resolution.schema.name).\(resolution.object.name).\(column.name)",
                                                           insertText: columnName,
                                                           kind: .column,
                                                           priority: priority))
                }
            } else if multipleTablesInScope && isAmbiguous {
                // Ambiguous column — must be qualified with alias/table
                let qualifier = tableRef.alias ?? tableRef.name
                let qualifierText = context.qualifier(for: tableRef, candidate: qualifier)
                let qualifiedTitle = "\(qualifierText).\(columnName)"
                let id = baseID + "|q=\(qualifier.lowercased())"
                if seen.insert(id).inserted {
                    results.append(SQLCompletionSuggestion(id: id,
                                                           title: qualifiedTitle,
                                                           subtitle: "\(resolution.object.name) • \(resolution.schema.name)",
                                                           detail: "Column \(resolution.schema.name).\(resolution.object.name).\(column.name)",
                                                           insertText: qualifiedTitle,
                                                           kind: .column,
                                                           priority: priority))
                }
            } else {
                // Unique column or single table — unqualified
                if seen.insert(baseID).inserted {
                    results.append(SQLCompletionSuggestion(id: baseID,
                                                           title: columnName,
                                                           subtitle: "\(resolution.object.name) • \(resolution.schema.name)",
                                                           detail: "Column \(resolution.schema.name).\(resolution.object.name).\(column.name)",
                                                           insertText: columnName,
                                                           kind: .column,
                                                           priority: priority))
                }
            }
        }
    }

    private func appendCTEColumns(_ columns: [String],
                                  tableRef: SQLContext.TableReference,
                                  match: ColumnPathMatch,
                                  prefix: String,
                                  clause: SQLClause,
                                  ambiguousColumns: Set<String>,
                                  multipleTablesInScope: Bool,
                                  context: ProviderContext,
                                  results: inout [SQLCompletionSuggestion],
                                  seen: inout Set<String>) {
        let userTypedQualifier = (match == .alias || match == .table) && !context.identifier.precedingSegments.isEmpty
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
            let columnName = context.quotedColumn(column)
            let isAmbiguous = ambiguousColumns.contains(lower)

            if userTypedQualifier {
                let id = baseID + (tableRef.alias.map { "|alias=\($0.lowercased())" } ?? "")
                if seen.insert(id).inserted {
                    results.append(SQLCompletionSuggestion(id: id,
                                                           title: columnName,
                                                           subtitle: qualifier,
                                                           detail: "CTE Column \(qualifier).\(column)",
                                                           insertText: columnName,
                                                           kind: .column,
                                                           priority: priority))
                }
            } else if multipleTablesInScope && isAmbiguous {
                let qualifierText = context.qualifier(for: tableRef, candidate: qualifier)
                let qualifiedTitle = "\(qualifierText).\(columnName)"
                let id = baseID + "|q=\(qualifier.lowercased())"
                if seen.insert(id).inserted {
                    results.append(SQLCompletionSuggestion(id: id,
                                                           title: qualifiedTitle,
                                                           subtitle: qualifier,
                                                           detail: "CTE Column \(qualifier).\(column)",
                                                           insertText: qualifiedTitle,
                                                           kind: .column,
                                                           priority: priority))
                }
            } else {
                if seen.insert(baseID).inserted {
                    results.append(SQLCompletionSuggestion(id: baseID,
                                                           title: columnName,
                                                           subtitle: qualifier,
                                                           detail: "CTE Column \(qualifier).\(column)",
                                                           insertText: columnName,
                                                           kind: .column,
                                                           priority: priority))
                }
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

    /// Returns the set of column names (lowercased) that appear in more than one table in scope.
    private static func findAmbiguousColumns(tables: [SQLContext.TableReference],
                                              context: ProviderContext) -> Set<String> {
        guard tables.count > 1 else { return [] }
        var columnCounts: [String: Int] = [:]
        for tableRef in tables {
            if let resolved = context.resolve(tableRef) {
                for column in resolved.object.columns {
                    columnCounts[column.name.lowercased(), default: 0] += 1
                }
            } else if let cteColumns = context.cteColumns(for: tableRef) {
                for column in cteColumns {
                    columnCounts[column.lowercased(), default: 0] += 1
                }
            }
        }
        return Set(columnCounts.filter { $0.value > 1 }.keys)
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
