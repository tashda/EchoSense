import Foundation

struct TableSuggestionProvider: SuggestionProvider {
    func suggestions(in context: ProviderContext) -> [SQLCompletionSuggestion] {
        let clause = context.sqlContext.clause
        let isObjectClause = Self.supportedClauses.contains(clause) || context.hasObjectKeywordContext
        guard isObjectClause else { return [] }

        let identifier = context.identifier
        let preceding = identifier.precedingLowercased

        // Resolve catalog for cross-database references.
        // Pattern: db.schema.⟨table⟩ → preceding = ["db", "schema"]
        let targetCatalog: SQLDatabaseCatalog
        if preceding.count == 2 {
            let potentialDB = preceding[0]
            if context.metadata.databaseNames.contains(where: { $0.lowercased() == potentialDB }),
               let dbCatalog = context.metadata.catalog(for: potentialDB) {
                targetCatalog = dbCatalog
            } else {
                targetCatalog = context.catalog
            }
        } else if preceding.count == 1 {
            // If the single preceding component is a database name, schema suggestions handle this step.
            let potentialDB = preceding[0]
            if context.metadata.databaseNames.contains(where: { $0.lowercased() == potentialDB }) {
                return []
            }
            targetCatalog = context.catalog
        } else if preceding.count > 2 {
            return []
        } else {
            targetCatalog = context.catalog
        }

        let schemaFilterLower = preceding.last
        let exactSchema = schemaFilterLower.flatMap { filter in
            targetCatalog.schemas.first(where: { $0.name.lowercased() == filter })
        }

        var candidateSchemas: [SQLSchema]
        if let exactSchema {
            candidateSchemas = [exactSchema]
        } else {
            candidateSchemas = targetCatalog.schemas
        }

        // In JOIN target context, exclude tables already in scope
        let excludedTables: Set<String> = clause == .joinTarget
            ? Set(context.sqlContext.tablesInScope.map { $0.name.lowercased() })
            : []

        var results: [SQLCompletionSuggestion] = []
        for schema in candidateSchemas {
            if exactSchema == nil,
               let filter = schemaFilterLower,
               !filter.isEmpty,
               !schema.name.lowercased().hasPrefix(filter) {
                continue
            }

            let isInsertContext = context.sqlContext.precedingKeyword == "into"
            for object in schema.objects where Self.supportedObjectTypes.contains(object.type)
                                              && (!isInsertContext || object.type == .table)
                                              && !excludedTables.contains(object.name.lowercased()) {
                guard let fuzzyScore = context.identifier.fuzzyScore(for: object.name) else {
                    continue
                }

                var components = identifier.precedingSegments
                if components.isEmpty {
                    if let defaultSchema = context.defaultSchemaLowercased,
                       schema.name.lowercased() == defaultSchema {
                        components = []
                    } else {
                        components = [schema.name]
                    }
                } else if let lastIndex = components.indices.last,
                          schema.name.lowercased().hasPrefix(components[lastIndex].lowercased()) {
                    components[lastIndex] = schema.name
                }

                components.append(object.name)
                var insertText = context.qualify(components)

                if context.request.options.enableAliasShortcuts,
                   let alias = AliasGenerator.shortcut(for: object.name) {
                    insertText += " \(alias)"
                }

                let objectLower = object.name.lowercased()
                let id = "object|\(schema.name.lowercased())|\(objectLower)"
                let basePriority = Self.priority(for: clause,
                                             schema: schema,
                                             defaultSchemaLower: context.defaultSchemaLowercased)
                let fuzzyAdjustment = fuzzyScore < 0.95 ? Int(-100 * (1.0 - fuzzyScore)) : 0
                let priority = basePriority + fuzzyAdjustment

                results.append(SQLCompletionSuggestion(id: id,
                                                       title: object.name,
                                                       subtitle: schema.name,
                                                       detail: "\(schema.name).\(object.name)",
                                                       insertText: insertText,
                                                       kind: Self.kind(for: object.type),
                                                       priority: priority))
            }
        }

        return results
    }

    private static func priority(for clause: SQLClause,
                                 schema: SQLSchema,
                                 defaultSchemaLower: String?) -> Int {
        var base: Int
        switch clause {
        case .from, .joinTarget:
            base = 1300
        case .deleteWhere:
            base = 1200
        case .withCTE:
            base = 1100
        default:
            base = 1000
        }
        if let defaultSchemaLower,
           schema.name.lowercased() == defaultSchemaLower {
            base += 25
        }
        return base
    }

    private static func kind(for objectType: SQLObject.ObjectType) -> SQLCompletionSuggestion.Kind {
        switch objectType {
        case .table: return .table
        case .view: return .view
        case .materializedView: return .materializedView
        case .procedure: return .procedure
        case .function: return .function
        }
    }

    private static let supportedClauses: Set<SQLClause> = [
        .from, .joinTarget, .deleteWhere, .withCTE, .unknown
    ]

    private static let supportedObjectTypes: Set<SQLObject.ObjectType> = [
        .table, .view, .materializedView
    ]

}

struct SchemaSuggestionProvider: SuggestionProvider {
    func suggestions(in context: ProviderContext) -> [SQLCompletionSuggestion] {
        let clause = context.sqlContext.clause
        let isObjectClause = Self.supportedClauses.contains(clause) || context.hasObjectKeywordContext
        guard isObjectClause else { return [] }

        let identifier = context.identifier
        let preceding = identifier.precedingLowercased

        if preceding.count == 0 {
            // No path prefix: suggest schemas from the current database.
            return schemaResults(from: context.catalog,
                                 identifier: identifier,
                                 displayDatabase: context.request.selectedDatabase,
                                 context: context)
        } else if preceding.count == 1 {
            let component = preceding[0]
            if context.metadata.databaseNames.contains(where: { $0.lowercased() == component }),
               let dbCatalog = context.metadata.catalog(for: component) {
                // The preceding component is a database name — suggest its schemas.
                // If it's a trailing dot after a schema name inside that catalog, let table suggestions handle it.
                if identifier.isTrailingDot,
                   dbCatalog.schemas.contains(where: { $0.name.lowercased() == component }) {
                    return []
                }
                let displayDB = context.metadata.databaseNames.first { $0.lowercased() == component } ?? component
                return schemaResults(from: dbCatalog,
                                     identifier: identifier,
                                     displayDatabase: displayDB,
                                     context: context)
            } else {
                // The preceding component is a schema name in the current database.
                if identifier.isTrailingDot,
                   context.catalog.schemas.contains(where: { $0.name.lowercased() == component }) {
                    return []
                }
                // Has a preceding non-DB segment and a non-empty prefix → table-level typing.
                if !identifier.lowercasePrefix.isEmpty { return [] }
                return []
            }
        } else {
            // Two or more preceding segments: at table level or deeper.
            return []
        }
    }

    private func schemaResults(from catalog: SQLDatabaseCatalog,
                               identifier: IdentifierContext,
                               displayDatabase: String?,
                               context: ProviderContext) -> [SQLCompletionSuggestion] {
        // In FROM/JOIN context, schemas rank alongside tables so they appear interleaved by match quality.
        // In other clauses keep schemas lower so they don't crowd out column suggestions.
        let basePriority: Int
        switch context.sqlContext.clause {
        case .from, .joinTarget: basePriority = 1290
        case .withCTE:           basePriority = 1090
        default:                 basePriority = 950
        }

        var results: [SQLCompletionSuggestion] = []
        for schema in catalog.schemas {
            guard let score = identifier.fuzzyScore(for: schema.name) else { continue }

            var components = identifier.precedingSegments
            if let last = components.last,
               schema.name.lowercased().hasPrefix(last.lowercased()) {
                components.removeLast()
            }
            components.append(schema.name)

            let insertText = context.qualify(components) + "."
            let detail = displayDatabase.map { "\($0).\(schema.name)" }
            let fuzzyAdjustment = score < 0.95 ? Int(-100 * (1.0 - score)) : 0

            results.append(SQLCompletionSuggestion(id: "schema|\(schema.name.lowercased())",
                                                   title: schema.name,
                                                   subtitle: displayDatabase,
                                                   detail: detail,
                                                   insertText: insertText,
                                                   kind: .schema,
                                                   priority: basePriority + fuzzyAdjustment))
        }
        return results
    }

    private static let supportedClauses: Set<SQLClause> = [
        .from, .joinTarget, .withCTE, .unknown
    ]
}

// MARK: - Database Suggestion Provider

/// Suggests database names when the user is at the first segment of a dotted identifier.
/// Enables cross-database completion: typing `db2.` → schemas from db2; `db2.dbo.` → tables from db2.dbo.
struct DatabaseSuggestionProvider: SuggestionProvider {
    func suggestions(in context: ProviderContext) -> [SQLCompletionSuggestion] {
        let clause = context.sqlContext.clause
        let isObjectClause = Self.supportedClauses.contains(clause) || context.hasObjectKeywordContext
        guard isObjectClause else { return [] }

        // Only suggest databases when at the very first segment (no preceding path components).
        guard context.identifier.precedingSegments.isEmpty else { return [] }

        let databaseNames = context.metadata.databaseNames
        guard !databaseNames.isEmpty else { return [] }

        var results: [SQLCompletionSuggestion] = []
        for dbName in databaseNames {
            guard let score = context.identifier.fuzzyScore(for: dbName) else { continue }
            let fuzzyAdjustment = score < 0.95 ? Int(-100 * (1.0 - score)) : 0
            // Databases rank slightly below schemas from the current database so local objects stay on top.
            let priority = 920 + fuzzyAdjustment
            let insertText = context.qualify([dbName]) + "."
            results.append(SQLCompletionSuggestion(id: "database|\(dbName.lowercased())",
                                                   title: dbName,
                                                   subtitle: "Database",
                                                   detail: dbName,
                                                   insertText: insertText,
                                                   kind: .schema,
                                                   priority: priority))
        }
        return results
    }

    private static let supportedClauses: Set<SQLClause> = [
        .from, .joinTarget, .withCTE, .unknown
    ]
}

struct JoinSuggestionProvider: SuggestionProvider {
    func suggestions(in context: ProviderContext) -> [SQLCompletionSuggestion] {
        switch context.sqlContext.clause {
        case .joinCondition:
            return joinConditionSuggestions(in: context)
        case .joinTarget:
            return joinTargetSuggestions(in: context)
        default:
            return []
        }
    }

    private func joinConditionSuggestions(in context: ProviderContext) -> [SQLCompletionSuggestion] {
        let references = context.sqlContext.tablesInScope
        guard references.count >= 2 else { return [] }

        let identifierToken = context.identifier.trimmedToken.lowercased()
        var resolved: [(ref: SQLContext.TableReference, res: TableResolution?)] = []
        resolved.reserveCapacity(references.count)
        for ref in references {
            resolved.append((ref, context.resolve(ref)))
        }

        var results: [SQLCompletionSuggestion] = []
        var seen = Set<String>()

        for (sourceRef, sourceResolution) in resolved {
            guard let sourceResolution else { continue }
            for fk in sourceResolution.object.foreignKeys {
                for target in resolved {
                    guard let targetRes = target.res else { continue }
                    if target.ref.isEquivalent(to: sourceRef) { continue }
                    guard Self.matches(foreignKey: fk, target: targetRes) else { continue }

                    let expression = Self.joinExpression(source: sourceRef,
                                                         target: target.ref,
                                                         foreignKey: fk,
                                                         context: context)
                    guard !expression.isEmpty else { continue }

                    if !identifierToken.isEmpty && !expression.lowercased().hasPrefix(identifierToken) {
                        continue
                    }

                    let id = "join|\(sourceResolution.schema.name.lowercased())|\(sourceResolution.object.name.lowercased())|\(fk.columns.joined(separator: ","))|\(target.ref.alias?.lowercased() ?? target.ref.name.lowercased())"
                    guard seen.insert(id).inserted else { continue }

                    let detail = fk.name.map { "FK \($0)" } ?? "\(sourceResolution.schema.name).\(sourceResolution.object.name)"
                    let snippet = Self.appendSnippetPlaceholder(to: expression)

                    results.append(SQLCompletionSuggestion(id: id,
                                                           title: expression,
                                                           subtitle: "Join Condition",
                                                           detail: detail,
                                                           insertText: snippet,
                                                           kind: .join,
                                                           priority: 1700))
                }
            }
        }

        return results
    }

    private func joinTargetSuggestions(in context: ProviderContext) -> [SQLCompletionSuggestion] {
        let references = context.sqlContext.tablesInScope
        guard !references.isEmpty else { return [] }

        var resolved: [(ref: SQLContext.TableReference, res: TableResolution?)] = []
        resolved.reserveCapacity(references.count)
        for ref in references {
            resolved.append((ref, context.resolve(ref)))
        }

        let existingKeys: Set<ObjectKey> = Set(resolved.compactMap { pair in
            guard let resolution = pair.res else { return nil }
            return ObjectKey(schema: resolution.schema.name.lowercased(),
                             name: resolution.object.name.lowercased())
        })
        let existingAliases: Set<String> = Set(resolved.map { ($0.ref.alias ?? $0.ref.name).lowercased() })
        let inboundIndex = Self.buildInboundIndex(catalog: context.catalog)

        var results: [SQLCompletionSuggestion] = []
        var seen = Set<String>()
        let identifier = context.identifier
        let prefix = identifier.lowercasePrefix

        for (sourceRef, maybeResolution) in resolved {
            guard let sourceResolution = maybeResolution else { continue }

            // Outgoing FK suggestions (source → target)
            for fk in sourceResolution.object.foreignKeys {
                guard let targetResolution = Self.resolveTarget(for: fk,
                                                                sourceSchema: sourceResolution.schema,
                                                                catalog: context.catalog) else { continue }

                let targetKey = ObjectKey(schema: targetResolution.schema.name.lowercased(),
                                          name: targetResolution.object.name.lowercased())
                if existingKeys.contains(targetKey) { continue }

                let alias = Self.makeAlias(for: targetResolution.object.name,
                                           existing: existingAliases)
                let targetRef = SQLContext.TableReference(schema: targetResolution.schema.name,
                                                          name: targetResolution.object.name,
                                                          alias: alias,
                                                          matchLocation: sourceRef.matchLocation)
                let expression = Self.joinExpression(source: sourceRef,
                                                     target: targetRef,
                                                     foreignKey: fk,
                                                     context: context)
                guard !expression.isEmpty else { continue }

                let (identifierText, displayName) = Self.joinTargetIdentifier(for: targetResolution,
                                                                              identifier: identifier,
                                                                              defaultSchemaLower: context.defaultSchemaLowercased,
                                                                              context: context)

                if !prefix.isEmpty {
                    let candidates = [identifierText, displayName] + (alias.map { [$0] } ?? [])
                    let bestScore = candidates.compactMap { FuzzyMatcher.match(pattern: prefix, candidate: $0)?.score }.max()
                    guard bestScore != nil else { continue }
                }

                let coreInsert = "\(identifierText)\(alias.map { " \($0)" } ?? "") ON \(expression)"
                let snippet = Self.appendSnippetPlaceholder(to: coreInsert)
                let id = "join-target|out|\(sourceResolution.schema.name.lowercased())|\(sourceResolution.object.name.lowercased())|\(fk.columns.joined(separator: ","))|\(targetResolution.schema.name.lowercased())|\(targetResolution.object.name.lowercased())"
                guard seen.insert(id).inserted else { continue }

                let subtitle = alias.map { "\($0) • Join helper" } ?? "Join helper"
                let detail = fk.name.map { "FK \($0)" } ?? "\(sourceResolution.object.name) → \(targetResolution.object.name)"

                results.append(SQLCompletionSuggestion(id: id,
                                                       title: displayName,
                                                       subtitle: subtitle,
                                                       detail: detail,
                                                       insertText: snippet,
                                                       kind: .join,
                                                       priority: 1680))
            }

            // Inbound FK suggestions (other → source)
            let sourceKey = ObjectKey(schema: sourceResolution.schema.name.lowercased(),
                                      name: sourceResolution.object.name.lowercased())
            if let inboundEntries = inboundIndex[sourceKey] {
                for entry in inboundEntries {
                    let targetResolution = TableResolution(schema: entry.schema, object: entry.object)
                    let targetKey = ObjectKey(schema: targetResolution.schema.name.lowercased(),
                                              name: targetResolution.object.name.lowercased())
                    if existingKeys.contains(targetKey) { continue }

                    let alias = Self.makeAlias(for: targetResolution.object.name,
                                               existing: existingAliases)
                    let targetRef = SQLContext.TableReference(schema: targetResolution.schema.name,
                                                              name: targetResolution.object.name,
                                                              alias: alias,
                                                              matchLocation: sourceRef.matchLocation)
                    let expression = Self.joinExpression(source: targetRef,
                                                         target: sourceRef,
                                                         foreignKey: entry.foreignKey,
                                                         context: context)
                    guard !expression.isEmpty else { continue }

                    let (identifierText, displayName) = Self.joinTargetIdentifier(for: targetResolution,
                                                                                  identifier: identifier,
                                                                                  defaultSchemaLower: context.defaultSchemaLowercased,
                                                                                  context: context)

                    if !prefix.isEmpty {
                        let candidates = [identifierText, displayName] + (alias.map { [$0] } ?? [])
                        let bestScore = candidates.compactMap { FuzzyMatcher.match(pattern: prefix, candidate: $0)?.score }.max()
                        guard bestScore != nil else { continue }
                    }

                    let coreInsert = "\(identifierText)\(alias.map { " \($0)" } ?? "") ON \(expression)"
                    let snippet = Self.appendSnippetPlaceholder(to: coreInsert)
                    let id = "join-target|in|\(targetResolution.schema.name.lowercased())|\(targetResolution.object.name.lowercased())|\(entry.foreignKey.columns.joined(separator: ","))|\(sourceResolution.schema.name.lowercased())|\(sourceResolution.object.name.lowercased())"
                    guard seen.insert(id).inserted else { continue }

                    let subtitle = alias.map { "\($0) • Join helper" } ?? "Join helper"
                    let detail = entry.foreignKey.name.map { "FK \($0)" } ?? "\(targetResolution.object.name) → \(sourceResolution.object.name)"

                    results.append(SQLCompletionSuggestion(id: id,
                                                           title: displayName,
                                                           subtitle: subtitle,
                                                           detail: detail,
                                                           insertText: snippet,
                                                           kind: .join,
                                                           priority: 1675))
                }
            }
        }

        return results
    }

    private static func appendSnippetPlaceholder(to text: String) -> String {
        if text.contains("<#") {
            return text
        }
        return text + "<# #>"
    }

    private static func matches(foreignKey: SQLForeignKey,
                                target: TableResolution) -> Bool {
        let referencedSchema = foreignKey.referencedSchema?.lowercased()
        let targetSchema = target.schema.name.lowercased()
        if let referencedSchema, referencedSchema != targetSchema {
            return false
        }
        return foreignKey.referencedTable.lowercased() == target.object.name.lowercased()
    }

    private static func joinExpression(source: SQLContext.TableReference,
                                       target: SQLContext.TableReference,
                                       foreignKey: SQLForeignKey,
                                       context: ProviderContext) -> String {
        guard foreignKey.columns.count == foreignKey.referencedColumns.count else { return "" }
        let leftQualifier = context.qualifier(for: source)
        let rightQualifier = context.qualifier(for: target)

        let pairs = zip(foreignKey.columns, foreignKey.referencedColumns)
        let segments = pairs.map { lhs, rhs in
            let leftColumn = context.quotedColumn(lhs)
            let rightColumn = context.quotedColumn(rhs)
            return "\(leftQualifier).\(leftColumn) = \(rightQualifier).\(rightColumn)"
        }
        return segments.joined(separator: " AND ")
    }

    private static func resolveTarget(for foreignKey: SQLForeignKey,
                                      sourceSchema: SQLSchema,
                                      catalog: SQLDatabaseCatalog) -> TableResolution? {
        if let referencedSchema = foreignKey.referencedSchema?.lowercased() {
            if let schema = catalog.schemas.first(where: { $0.name.lowercased() == referencedSchema }),
               let object = schema.objects.first(where: { $0.name.caseInsensitiveCompare(foreignKey.referencedTable) == .orderedSame }) {
                return TableResolution(schema: schema, object: object)
            }
        } else {
            if let object = sourceSchema.objects.first(where: { $0.name.caseInsensitiveCompare(foreignKey.referencedTable) == .orderedSame }) {
                return TableResolution(schema: sourceSchema, object: object)
            }
            for schema in catalog.schemas {
                if let object = schema.objects.first(where: { $0.name.caseInsensitiveCompare(foreignKey.referencedTable) == .orderedSame }) {
                    return TableResolution(schema: schema, object: object)
                }
            }
        }
        return nil
    }

    private static func joinTargetIdentifier(for resolution: TableResolution,
                                             identifier: IdentifierContext,
                                             defaultSchemaLower: String?,
                                             context: ProviderContext) -> (String, String) {
        var components = identifier.precedingSegments
        if components.isEmpty {
            if let defaultSchemaLower,
               resolution.schema.name.lowercased() == defaultSchemaLower {
                components = []
            } else {
                components = [resolution.schema.name]
            }
        } else if let lastIndex = components.indices.last {
            let typedSchema = components[lastIndex]
            if resolution.schema.name.lowercased().hasPrefix(typedSchema.lowercased()) {
                components[lastIndex] = resolution.schema.name
            }
        }
        components.append(resolution.object.name)

        let identifierText = context.qualify(components)
        let displayName = resolution.object.name
        return (identifierText, displayName)
    }

    private static func makeAlias(for name: String,
                                  existing: Set<String>) -> String? {
        guard var base = AliasGenerator.shortcut(for: name) else { return nil }
        base = base.lowercased()
        var candidate = base
        var suffix = 2
        while existing.contains(candidate) {
            candidate = base + "\(suffix)"
            suffix += 1
        }
        return candidate
    }

    private static func buildInboundIndex(catalog: SQLDatabaseCatalog) -> [ObjectKey: [InboundEntry]] {
        var index: [ObjectKey: [InboundEntry]] = [:]
        for schema in catalog.schemas {
            for object in schema.objects {
                guard !object.foreignKeys.isEmpty else { continue }
                for fk in object.foreignKeys {
                    let referencedSchemaLower = fk.referencedSchema?.lowercased() ?? schema.name.lowercased()
                    let key = ObjectKey(schema: referencedSchemaLower,
                                        name: fk.referencedTable.lowercased())
                    let entry = InboundEntry(schema: schema, object: object, foreignKey: fk)
                    index[key, default: []].append(entry)
                }
            }
        }
        return index
    }

    private struct ObjectKey: Hashable {
        let schema: String
        let name: String
    }

    private struct InboundEntry {
        let schema: SQLSchema
        let object: SQLObject
        let foreignKey: SQLForeignKey
    }
}
