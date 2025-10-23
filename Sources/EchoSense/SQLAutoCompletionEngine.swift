import Foundation

typealias DatabaseStructure = EchoSenseDatabaseStructure
typealias DatabaseInfo = EchoSenseDatabaseInfo
typealias SchemaInfo = EchoSenseSchemaInfo
typealias SchemaObjectInfo = EchoSenseSchemaObjectInfo
typealias ColumnInfo = EchoSenseColumnInfo
typealias ForeignKeyReference = EchoSenseForeignKeyReference
typealias DatabaseType = EchoSenseDatabaseType

public final class SQLAutoCompletionEngine {
    private let completionEngine: SQLCompletionEngineProtocol
    private static let identifierDelimiterCharacterSet: CharacterSet = {
        var set = CharacterSet()
        set.insert(charactersIn: "\"")
        set.insert(charactersIn: "`")
        set.insert(charactersIn: "[")
        set.insert(charactersIn: "]")
        return set
    }()

    private final class CachingSuggestionBuilderFactory: SQLSuggestionBuilderFactory {
        private var cache: [SQLDialect: SQLSuggestionBuilder] = [:]

        func makeBuilder(for dialect: SQLDialect) -> SQLSuggestionBuilder {
            if let existing = cache[dialect] {
                return existing
            }
            let builder = DefaultSuggestionBuilder(dialect: dialect)
            cache[dialect] = builder
            return builder
        }
    }

    public init(completionEngine: SQLCompletionEngineProtocol? = nil) {
        if let completionEngine {
            self.completionEngine = completionEngine
        } else {
            self.completionEngine = SQLCompletionEngine(builderFactory: CachingSuggestionBuilderFactory())
        }
    }

    private var context: SQLEditorCompletionContext?
    private var catalog: SQLMetadataCatalog?
    private var builtInFunctions: [String] = []
    private var useTableAliasShortcuts = false
    private let historyStore = SQLAutoCompletionHistoryStore.shared
    public private(set) var isMetadataLimited: Bool = false
    private var metadataProvider: SQLStructureMetadataProvider = .empty
    private var suppressEmptyTokenCompletions = false
    private var includeHistorySuggestions = true
    private var preferQualifiedTableInsertions = false
    private var aggressiveness: SQLCompletionAggressiveness = .balanced
    private var includeSystemSchemas = false
    private var manualTriggerInProgress = false
    private static let emptyMetadata = SQLCompletionMetadata(clause: .unknown,
                                                             currentToken: "",
                                                             precedingKeyword: nil,
                                                             pathComponents: [],
                                                             tablesInScope: [],
                                                             focusTable: nil,
                                                             cteColumns: [:])

    private static let reservedLeadingKeywords: Set<String> = [
        "select", "from", "where", "join", "inner", "left", "right", "full",
        "outer", "cross", "on", "group", "by", "having", "order", "limit",
        "offset", "insert", "into", "values", "update", "set", "delete",
        "create", "drop", "alter", "vacuum", "analyze", "with", "as",
        "when", "then", "else", "case", "using"
    ]

    private static let objectContextKeywords: Set<String> = [
        "from", "join", "inner", "left", "right", "full", "outer", "cross",
        "update", "into", "delete"
    ]

    private static let columnContextKeywords: Set<String> = [
        "select", "where", "on", "and", "or", "having", "group", "order",
        "by", "set", "values", "case", "when", "then", "else", "returning",
        "using"
    ]

    private static let postObjectClauseKeywordOrder: [String] = [
        "where",
        "inner",
        "left",
        "right",
        "full",
        "outer",
        "join",
        "on",
        "group",
        "order",
        "having",
        "limit",
        "offset"
    ]

    private static let relationLikeKinds: Set<SQLAutoCompletionKind> = [
        .schema,
        .table,
        .view,
        .materializedView
    ]

    public func updateContext(_ newContext: SQLEditorCompletionContext?) {
        context = newContext
        if let newContext {
            builtInFunctions = SQLAutoCompletionEngine.builtInFunctions(for: newContext.databaseType)
            let newCatalog = SQLMetadataCatalog(context: newContext,
                                     builtInFunctions: builtInFunctions,
                                     includeSystemSchemas: includeSystemSchemas)
            catalog = newCatalog
            metadataProvider = newCatalog.metadataProvider
            isMetadataLimited = newContext.structure == nil
        } else {
            catalog = nil
            builtInFunctions = []
            metadataProvider = .empty
            isMetadataLimited = false
        }
    }

    public func updateAliasPreference(useTableAliases: Bool) {
        useTableAliasShortcuts = useTableAliases
    }

    public func updateHistoryPreference(includeHistory: Bool) {
        includeHistorySuggestions = includeHistory
    }

    public func updateQualifiedInsertionPreference(includeSchema: Bool) {
        preferQualifiedTableInsertions = includeSchema
    }

    public func updateAggressiveness(_ level: SQLCompletionAggressiveness) {
        aggressiveness = level
    }

    public func updateSystemSchemaVisibility(includeSystemSchemas: Bool) {
        guard self.includeSystemSchemas != includeSystemSchemas else { return }
        self.includeSystemSchemas = includeSystemSchemas
        if let current = context {
            updateContext(current)
        }
    }

    public func beginManualTrigger() {
        manualTriggerInProgress = true
    }

    public func endManualTrigger() {
        manualTriggerInProgress = false
    }

    public var isManualTriggerActive: Bool {
        manualTriggerInProgress
    }

    public func clearPostCommitSuppression() {
        suppressEmptyTokenCompletions = false
    }

    public func recordSelection(_ suggestion: SQLAutoCompletionSuggestion, query: SQLAutoCompletionQuery) {
        historyStore.record(suggestion, context: context)
        suppressEmptyTokenCompletions = true
    }

    public func suggestions(for query: SQLAutoCompletionQuery,
                            text: String,
                            caretLocation: Int) -> SQLAutoCompletionResult {
        guard let context else {
            return SQLAutoCompletionResult(sections: [],
                                           metadata: SQLAutoCompletionEngine.emptyMetadata)
        }

        let trimmedToken = query.token.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedToken.isEmpty && query.pathComponents.isEmpty {
            if suppressEmptyTokenCompletions {
                return SQLAutoCompletionResult(sections: [],
                                               metadata: SQLAutoCompletionEngine.emptyMetadata)
            }
        } else {
            suppressEmptyTokenCompletions = false
        }

        guard shouldProvideCompletions(for: query) else {
            return SQLAutoCompletionResult(sections: [],
                                           metadata: SQLAutoCompletionEngine.emptyMetadata)
        }

        let options = SQLEngineOptions(enableAliasShortcuts: useTableAliasShortcuts,
                                       keywordCasing: .upper)

        let request = SQLCompletionRequest(text: text,
                                           caretLocation: caretLocation,
                                           dialect: context.databaseType.sqlDialect,
                                           selectedDatabase: context.selectedDatabase,
                                           defaultSchema: context.defaultSchema,
                                           metadata: metadataProvider,
                                           options: options)

        let result = completionEngine.completions(for: request)

        let mapped = mapSuggestions(result.suggestions,
                                    query: query,
                                    context: context)
        let combined = injectHistorySuggestions(base: mapped,
                                                query: query,
                                                context: context)
        let ranked = rankSuggestions(combined, query: query, context: context)

        let sections = [SQLAutoCompletionSection(title: "Suggestions", suggestions: ranked)]
        return SQLAutoCompletionResult(sections: sections, metadata: result.metadata)
    }

    private func mapSuggestions(_ suggestions: [SQLCompletionSuggestion],
                                query: SQLAutoCompletionQuery,
                                context: SQLEditorCompletionContext) -> [SQLAutoCompletionSuggestion] {
        var results: [SQLAutoCompletionSuggestion] = []
        results.reserveCapacity(suggestions.count)

        for suggestion in suggestions {
            guard let mapped = mapSuggestion(suggestion,
                                             query: query,
                                             context: context) else { continue }
            results.append(mapped)
        }
        return results.filter { matchesQuery($0, query: query) }
    }

    private func mapSuggestion(_ suggestion: SQLCompletionSuggestion,
                               query: SQLAutoCompletionQuery,
                               context: SQLEditorCompletionContext) -> SQLAutoCompletionSuggestion? {
        guard let mappedKind = mapKind(suggestion.kind) else { return nil }

        var origin: SQLAutoCompletionSuggestion.Origin?
        var dataType: String?
        var tableColumns: [SQLAutoCompletionSuggestion.TableColumn]?

        switch suggestion.kind {
        case .table, .view, .materializedView:
            let schemaName = suggestion.subtitle ?? context.defaultSchema
            if let entry = lookupObject(schema: schemaName,
                                        name: suggestion.title,
                                        context: context) {
                origin = SQLAutoCompletionSuggestion.Origin(database: entry.database,
                                                            schema: entry.schema,
                                                            object: entry.object.name)
                tableColumns = self.tableColumns(from: entry.object)
            } else {
                origin = SQLAutoCompletionSuggestion.Origin(database: context.selectedDatabase,
                                                            schema: schemaName,
                                                            object: suggestion.title)
            }
        case .schema:
            origin = SQLAutoCompletionSuggestion.Origin(database: context.selectedDatabase,
                                                        schema: suggestion.title)
        case .column:
            let details = mapColumnSuggestion(suggestion, context: context)
            origin = details.origin
            dataType = details.dataType
        case .function, .procedure:
            origin = mapFunctionOrigin(suggestion, context: context)
        default:
            break
        }

        var insertText = makeInsertText(from: suggestion,
                                        mappedKind: mappedKind,
                                        query: query,
                                        origin: origin)

        var snippetText: String?
        if mappedKind == .snippet && !suggestion.id.hasPrefix("star|") {
            snippetText = suggestion.insertText
        } else if mappedKind == .join, suggestion.insertText.contains("<#") {
            snippetText = suggestion.insertText
            insertText = stripSnippetMarkers(from: suggestion.insertText)
        }

        return SQLAutoCompletionSuggestion(id: suggestion.id,
                                           title: suggestion.title,
                                           subtitle: suggestion.subtitle,
                                           detail: suggestion.detail,
                                           insertText: insertText,
                                           kind: mappedKind,
                                           origin: origin,
                                           dataType: dataType,
                                           tableColumns: tableColumns,
                                           snippetText: snippetText,
                                           priority: suggestion.priority)
    }

    private enum ClauseRelevance: Int {
        case primary = 3
        case secondary = 2
        case peripheral = 1
        case irrelevant = 0
    }

    private func rankSuggestions(_ suggestions: [SQLAutoCompletionSuggestion],
                                 query: SQLAutoCompletionQuery,
                                 context: SQLEditorCompletionContext) -> [SQLAutoCompletionSuggestion] {
        guard !suggestions.isEmpty else { return suggestions }

        var ranked: [(index: Int, suggestion: SQLAutoCompletionSuggestion, score: Double, relevance: ClauseRelevance)] = []
        ranked.reserveCapacity(suggestions.count)
        let promoteClauseKeywords = shouldPromoteClauseKeywords(query: query)

        for (index, suggestion) in suggestions.enumerated() {
            let (relevance, boost) = clauseBoost(for: query.clause, kind: suggestion.kind)

            switch aggressiveness {
            case .focused:
                if relevance == .peripheral || relevance == .irrelevant {
                    continue
                }
            case .balanced:
                if relevance == .irrelevant {
                    continue
                }
            case .eager:
                break
            }

            var score = Double(suggestion.priority) + boost

            if suggestion.source == .history {
                let historyBoost = historyStore.weight(for: suggestion, context: context)
                score += historyBoost
            } else if suggestion.source == .fallback {
                score -= 40
            }

            if suggestion.kind == .column,
               let focus = query.focusTable,
               matchesFocus(suggestion, focus: focus) {
                score += 80
            }

            if suggestion.kind == .column {
                score += aliasBonus(for: suggestion, query: query)
            }

            if suggestion.kind == .keyword {
                if promoteClauseKeywords {
                    score += clauseKeywordPromotionBonus(for: suggestion)
                } else {
                    score -= 90
                }
            } else if promoteClauseKeywords &&
                        SQLAutoCompletionEngine.relationLikeKinds.contains(suggestion.kind) {
                score -= 140
            }

            ranked.append((index, suggestion, score, relevance))
        }

        ranked.sort { lhs, rhs in
            if lhs.score == rhs.score {
                if lhs.relevance.rawValue == rhs.relevance.rawValue {
                    let comparison = lhs.suggestion.title.localizedCaseInsensitiveCompare(rhs.suggestion.title)
                    if comparison == .orderedSame {
                        return lhs.index < rhs.index
                    }
                    return comparison == .orderedAscending
                }
                return lhs.relevance.rawValue > rhs.relevance.rawValue
            }
            return lhs.score > rhs.score
        }

        return ranked.map { $0.suggestion }
    }

    private func shouldPromoteClauseKeywords(query: SQLAutoCompletionQuery) -> Bool {
        if query.clause != .from { return false }
        if !query.token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
        if !query.pathComponents.isEmpty { return false }
        if query.precedingCharacter == "," { return false }
        if let keyword = query.precedingKeyword,
           SQLAutoCompletionEngine.objectContextKeywords.contains(keyword) {
            return false
        }
        return !query.tablesInScope.isEmpty
    }

    private func clauseKeywordPromotionBonus(for suggestion: SQLAutoCompletionSuggestion) -> Double {
        let normalized = suggestion.title.lowercased()
        if let orderIndex = SQLAutoCompletionEngine.postObjectClauseKeywordOrder.firstIndex(of: normalized) {
            let base = 1900.0
            return base - Double(orderIndex) * 25.0
        }
        return 900.0
    }

    private func stripSnippetMarkers(from snippet: String) -> String {
        var output = ""
        var searchStart = snippet.startIndex

        while let startRange = snippet.range(of: "<#", range: searchStart..<snippet.endIndex) {
            output.append(contentsOf: snippet[searchStart..<startRange.lowerBound])
            guard let endRange = snippet.range(of: "#>", range: startRange.upperBound..<snippet.endIndex) else {
                output.append(contentsOf: snippet[startRange.lowerBound..<snippet.endIndex])
                return output
            }
            let placeholderContent = String(snippet[startRange.upperBound..<endRange.lowerBound])
            let trimmed = placeholderContent.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                output.append(contentsOf: trimmed)
            }
            searchStart = endRange.upperBound
        }

        if searchStart < snippet.endIndex {
            output.append(contentsOf: snippet[searchStart..<snippet.endIndex])
        }

        return output
    }

    private func mapKind(_ kind: SQLCompletionSuggestion.Kind) -> SQLAutoCompletionKind? {
        switch kind {
        case .schema: return .schema
        case .table: return .table
        case .view: return .view
        case .materializedView: return .materializedView
        case .column: return .column
        case .function, .procedure: return .function
        case .keyword: return .keyword
        case .snippet: return .snippet
        case .parameter: return .parameter
        case .join: return .join
        }
    }

    private func clauseBoost(for clause: SQLClause,
                             kind: SQLAutoCompletionKind) -> (ClauseRelevance, Double) {
        switch clause {
        case .selectList, .whereClause, .groupBy, .orderBy, .having, .values, .updateSet:
            return columnContextBoost(for: kind)
        case .joinCondition:
            return joinConditionBoost(for: kind)
        case .from, .joinTarget, .insertColumns, .deleteWhere, .withCTE:
            return objectContextBoost(for: kind)
        case .limit, .offset:
            return limitContextBoost(for: kind)
        case .unknown:
            return fallbackBoost(for: kind)
        }
    }

    private func columnContextBoost(for kind: SQLAutoCompletionKind) -> (ClauseRelevance, Double) {
        switch kind {
        case .column:
            return (.primary, 520)
        case .function, .snippet, .parameter:
            return (.secondary, 260)
        case .keyword:
            return (.peripheral, -220)
        case .table, .view, .materializedView, .schema, .join:
            return (.peripheral, -260)
        @unknown default:
            return (.peripheral, -200)
        }
    }

    private func joinConditionBoost(for kind: SQLAutoCompletionKind) -> (ClauseRelevance, Double) {
        switch kind {
        case .join:
            return (.primary, 560)
        case .column:
            return (.primary, 500)
        case .function, .snippet, .parameter:
            return (.secondary, 220)
        case .keyword:
            return (.peripheral, -260)
        case .table, .view, .materializedView, .schema:
            return (.peripheral, -280)
        }
    }

    private func objectContextBoost(for kind: SQLAutoCompletionKind) -> (ClauseRelevance, Double) {
        switch kind {
        case .table, .view, .materializedView:
            return (.primary, 520)
        case .join:
            return (.primary, 500)
        case .schema:
            return (.secondary, 200)
        case .snippet, .parameter:
            return (.secondary, 180)
        case .column, .function:
            return (.peripheral, -220)
        case .keyword:
            return (.peripheral, -260)
        }
    }

    private func limitContextBoost(for kind: SQLAutoCompletionKind) -> (ClauseRelevance, Double) {
        switch kind {
        case .keyword:
            return (.primary, 420)
        case .parameter, .snippet:
            return (.secondary, 160)
        case .column, .table, .view, .materializedView, .function, .schema, .join:
            return (.peripheral, -200)
        }
    }

    private func fallbackBoost(for kind: SQLAutoCompletionKind) -> (ClauseRelevance, Double) {
        switch kind {
        case .column, .table, .view, .materializedView, .function:
            return (.secondary, 140)
        case .keyword, .snippet, .parameter, .schema:
            return (.peripheral, -120)
        case .join:
            return (.peripheral, -180)
        }
    }

    private func matchesFocus(_ suggestion: SQLAutoCompletionSuggestion,
                              focus: SQLAutoCompletionTableFocus) -> Bool {
        guard let origin = suggestion.origin else { return false }

        if let object = origin.object,
           object.caseInsensitiveCompare(focus.name) != .orderedSame {
            return false
        }

        if let focusSchema = focus.schema,
           let originSchema = origin.schema,
           focusSchema.caseInsensitiveCompare(originSchema) != .orderedSame {
            return false
        }

        if origin.object == nil {
            return false
        }

        return true
    }

    private func aliasBonus(for suggestion: SQLAutoCompletionSuggestion,
                            query: SQLAutoCompletionQuery) -> Double {
        guard suggestion.kind == .column else { return 0 }
        guard !query.tablesInScope.isEmpty else { return 0 }

        let insertLower = suggestion.insertText.lowercased()
        for table in query.tablesInScope {
            if let alias = table.alias?.lowercased(),
               insertLower.hasPrefix("\(alias).") {
                return 60
            }
        }

        return 0
    }

    private func adjustedInsertText(original: String,
                                    for kind: SQLCompletionSuggestion.Kind,
                                    query: SQLAutoCompletionQuery) -> String {
        switch kind {
        case .table, .view, .materializedView, .column, .function:
            break
        default:
            return original
        }

        guard !query.pathComponents.isEmpty else { return original }

        let originalComponents = original.split(separator: ".").map(String.init)
        var remaining = originalComponents
        let typedComponents = query.pathComponents.map { $0.lowercased() }

        var index = 0
        while index < min(typedComponents.count, remaining.count),
              remaining[index].lowercased() == typedComponents[index] {
            index += 1
        }

        if index > 0 {
            remaining = Array(remaining.dropFirst(index))
            if remaining.isEmpty, let last = originalComponents.last {
                return last
            }
            return remaining.joined(separator: ".")
        }

        return original
    }

    private func makeInsertText(from suggestion: SQLCompletionSuggestion,
                                mappedKind: SQLAutoCompletionKind,
                                query: SQLAutoCompletionQuery,
                                origin: SQLAutoCompletionSuggestion.Origin?) -> String {
        let adjusted = adjustedInsertText(original: suggestion.insertText,
                                          for: suggestion.kind,
                                          query: query)

        guard preferQualifiedTableInsertions,
              query.pathComponents.isEmpty,
              (mappedKind == .table || mappedKind == .view || mappedKind == .materializedView),
              let schema = origin?.schema?.trimmingCharacters(in: .whitespacesAndNewlines),
              !schema.isEmpty,
              !adjusted.contains(".") else {
            return adjusted
        }

        return qualifiedInsertText(schema: schema,
                                   object: adjusted)
    }

    private func qualifiedInsertText(schema: String,
                                     object: String) -> String {
        let trimmedSchema = schema.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSchema.isEmpty else { return object }

        if let delimiters = identifierDelimiters(for: object) {
            let quotedSchema = apply(delimiters: delimiters, to: trimmedSchema)
            return "\(quotedSchema).\(object)"
        }

        return "\(trimmedSchema).\(object)"
    }

    private func identifierDelimiters(for text: String) -> (start: Character, end: Character)? {
        guard let first = text.first,
              let last = text.last else { return nil }
        let pairs: [Character: Character] = [
            "\"": "\"",
            "`": "`",
            "[": "]"
        ]
        guard let expected = pairs[first], expected == last else { return nil }
        return (first, last)
    }

    private func apply(delimiters: (start: Character, end: Character),
                       to identifier: String) -> String {
        switch delimiters.start {
        case "[":
            return "[\(identifier)]"
        default:
            return "\(delimiters.start)\(identifier)\(delimiters.end)"
        }
    }

    private func matchesQuery(_ suggestion: SQLAutoCompletionSuggestion,
                              query: SQLAutoCompletionQuery) -> Bool {
        let rawToken = query.token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let tokenLower = rawToken.trimmingCharacters(in: SQLAutoCompletionEngine.identifierDelimiterCharacterSet)
        let rawPrefix = query.prefix.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let prefixLower = rawPrefix.trimmingCharacters(in: SQLAutoCompletionEngine.identifierDelimiterCharacterSet)
        let pathLower = query.pathComponents.map {
            $0.trimmingCharacters(in: SQLAutoCompletionEngine.identifierDelimiterCharacterSet).lowercased()
        }

        if suggestion.id.hasPrefix("star|") {
            let trimmedToken = query.token.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedPrefix = query.prefix.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedToken == "*" || trimmedPrefix == "*" {
                return true
            }
        }

        if suggestion.kind == .join {
            if tokenLower.isEmpty && prefixLower.isEmpty {
                return true
            }

            let comparisonPool: [String] = [
                suggestion.title.lowercased(),
                suggestion.insertText.lowercased(),
                suggestion.detail?.lowercased() ?? ""
            ]

            if !tokenLower.isEmpty &&
                comparisonPool.contains(where: { $0.hasPrefix(tokenLower) }) {
                return true
            }

            if !prefixLower.isEmpty &&
                comparisonPool.contains(where: { $0.hasPrefix(prefixLower) }) {
                return true
            }
        }

        let insertComponents = suggestion.insertText.split(separator: ".").map(String.init)
        let sanitizedComponents = insertComponents.map {
            $0.trimmingCharacters(in: SQLAutoCompletionEngine.identifierDelimiterCharacterSet).lowercased()
        }

        func pathMatches() -> Bool {
            guard !pathLower.isEmpty else { return true }
            guard sanitizedComponents.count >= pathLower.count + 1 else { return false }
            for (typed, candidate) in zip(pathLower, sanitizedComponents) {
                if !candidate.hasPrefix(typed) {
                    return false
                }
            }
            return true
        }

        let targetIndex = min(pathLower.count, max(sanitizedComponents.count - 1, 0))
        let targetComponent = targetIndex < sanitizedComponents.count ? sanitizedComponents[targetIndex] : sanitizedComponents.last

        if let targetComponent,
           !tokenLower.isEmpty,
           targetComponent.hasPrefix(tokenLower),
           pathMatches() {
            return true
        }

        if let targetComponent,
           !prefixLower.isEmpty,
           targetComponent.hasPrefix(prefixLower),
           pathMatches() {
            return true
        }

        if tokenLower.isEmpty && prefixLower.isEmpty && pathMatches() {
            return true
        }

        let insertLower = suggestion.insertText.lowercased()

        if !tokenLower.isEmpty && insertLower.hasPrefix(tokenLower) {
            return true
        }

        if !prefixLower.isEmpty && insertLower.hasPrefix(prefixLower) {
            return true
        }

        if tokenLower.isEmpty && prefixLower.isEmpty && !pathLower.isEmpty {
            let aliasMatch = query.tablesInScope.contains { focus in
                focus.alias?.lowercased() == pathLower.first
            }
            if aliasMatch {
                return true
            }

            if let origin = suggestion.origin {
                var originComponents: [String] = []
                if let schema = origin.schema?.lowercased() {
                    originComponents.append(schema)
                }
                if let object = origin.object?.lowercased() {
                    originComponents.append(object)
                }
                if pathLower.count == 1 {
                    return originComponents.first == pathLower.first
                }
                if pathLower.count <= originComponents.count {
                    for (lhs, rhs) in zip(pathLower, originComponents) where lhs != rhs {
                        return false
                    }
                    return true
                }
            }
            return false
        }

        if tokenLower.isEmpty && prefixLower.isEmpty && pathLower.isEmpty {
            return true
        }

        if !tokenLower.isEmpty {
            return suggestion.title.lowercased().hasPrefix(tokenLower)
        }

        return true
    }

    private func lookupObject(schema: String?,
                              name: String,
                              context: SQLEditorCompletionContext) -> SQLMetadataCatalog.ObjectEntry? {
        guard let catalog else { return nil }

        if let schema,
           let entry = catalog.object(database: context.selectedDatabase,
                                      schema: schema,
                                      name: name) {
            return entry
        }

        if let schema,
           let entry = catalog.object(database: nil,
                                      schema: schema,
                                      name: name) {
            return entry
        }

        let matches = catalog.objects(named: name)
        guard !matches.isEmpty else { return nil }

        if let schema,
           let match = matches.first(where: { $0.schema.caseInsensitiveCompare(schema) == .orderedSame }) {
            return match
        }

        if let selected = context.selectedDatabase?.lowercased(),
           let match = matches.first(where: { $0.database.lowercased() == selected }) {
            return match
        }

        return matches.first
    }

    private func tableColumns(from object: SchemaObjectInfo) -> [SQLAutoCompletionSuggestion.TableColumn]? {
        guard !object.columns.isEmpty else { return nil }
        return object.columns.map {
            SQLAutoCompletionSuggestion.TableColumn(name: $0.name,
                                                    dataType: $0.dataType,
                                                    isNullable: $0.isNullable,
                                                    isPrimaryKey: $0.isPrimaryKey)
        }
    }

    private func mapColumnSuggestion(_ suggestion: SQLCompletionSuggestion,
                                     context: SQLEditorCompletionContext) -> (origin: SQLAutoCompletionSuggestion.Origin?, dataType: String?) {
        guard let components = parseColumnIdentifier(from: suggestion.id) else {
            return (nil, nil)
        }

        if components.isCTE {
            let qualifier = components.table ?? ""
            let origin = SQLAutoCompletionSuggestion.Origin(database: context.selectedDatabase,
                                                            schema: nil,
                                                            object: qualifier,
                                                            column: components.column)
            return (origin, nil)
        }

        guard let tableName = components.table else {
            let origin = SQLAutoCompletionSuggestion.Origin(database: context.selectedDatabase,
                                                            schema: components.schema,
                                                            object: nil,
                                                            column: components.column)
            return (origin, nil)
        }

        if let entry = lookupObject(schema: components.schema,
                                    name: tableName,
                                    context: context) {
            let origin = SQLAutoCompletionSuggestion.Origin(database: entry.database,
                                                            schema: entry.schema,
                                                            object: entry.object.name,
                                                            column: components.column)
            if let columnInfo = entry.object.columns.first(where: { $0.name.caseInsensitiveCompare(components.column) == .orderedSame }) {
                return (origin, columnInfo.dataType)
            }
            return (origin, nil)
        }

        let origin = SQLAutoCompletionSuggestion.Origin(database: context.selectedDatabase,
                                                        schema: components.schema,
                                                        object: tableName,
                                                        column: components.column)
        return (origin, nil)
    }

    private func parseColumnIdentifier(from identifier: String) -> (schema: String?, table: String?, column: String, isCTE: Bool)? {
        let parts = identifier.split(separator: "|")
        guard let prefix = parts.first else { return nil }

        switch prefix {
        case "column":
            guard parts.count >= 4 else { return nil }
            let schema = parts[1].isEmpty ? nil : String(parts[1])
            let table = parts[2].isEmpty ? nil : String(parts[2])
            let column = String(parts[3])
            return (schema, table, column, false)
        case "cte":
            guard parts.count >= 3 else { return nil }
            let qualifier = String(parts[1])
            let column = String(parts[2])
            return (schema: nil, table: qualifier, column: column, isCTE: true)
        default:
            return nil
        }
    }

    private func mapFunctionOrigin(_ suggestion: SQLCompletionSuggestion,
                                   context: SQLEditorCompletionContext) -> SQLAutoCompletionSuggestion.Origin? {
        if let schemaName = suggestion.subtitle,
           let entry = lookupObject(schema: schemaName,
                                    name: suggestion.title,
                                    context: context) {
            return SQLAutoCompletionSuggestion.Origin(database: entry.database,
                                                      schema: entry.schema,
                                                      object: entry.object.name)
        }

        if suggestion.subtitle == "Built-in" {
            return SQLAutoCompletionSuggestion.Origin(database: nil,
                                                      schema: "Built-in",
                                                      object: suggestion.title)
        }

        return SQLAutoCompletionSuggestion.Origin(database: context.selectedDatabase,
                                                  schema: suggestion.subtitle,
                                                  object: suggestion.title)
    }

    private func injectHistorySuggestions(base: [SQLAutoCompletionSuggestion],
                                          query: SQLAutoCompletionQuery,
                                          context: SQLEditorCompletionContext) -> [SQLAutoCompletionSuggestion] {
        guard includeHistorySuggestions else { return base }
        let history = historyStore.suggestions(matching: query.normalizedPrefix,
                                               context: context,
                                               limit: 6)
            .filter { matchesQuery($0, query: query) }
        guard !history.isEmpty else { return base }

        var seen = Set<String>()
        var combined: [SQLAutoCompletionSuggestion] = []

        for rawSuggestion in history {
            let suggestion = refinedHistorySuggestion(rawSuggestion.withSource(.history),
                                                      query: query)
            let key = suggestion.id.lowercased()
            if seen.insert(key).inserted {
                combined.append(suggestion)
            }
        }

        for suggestion in base {
            let key = suggestion.id.lowercased()
            if seen.insert(key).inserted {
                combined.append(suggestion)
            }
        }

        return combined
    }

    private func mapBackKind(_ kind: SQLAutoCompletionKind) -> SQLCompletionSuggestion.Kind? {
        switch kind {
        case .keyword: return .keyword
        case .schema: return .schema
        case .table: return .table
        case .view: return .view
        case .materializedView: return .materializedView
        case .column: return .column
        case .function: return .function
        case .snippet: return .snippet
        case .parameter: return .parameter
        case .join: return .join
        default:
            return nil
        }
    }

    private func refinedHistorySuggestion(_ suggestion: SQLAutoCompletionSuggestion,
                                          query: SQLAutoCompletionQuery) -> SQLAutoCompletionSuggestion {
        guard let originalKind = mapBackKind(suggestion.kind) else {
            return suggestion
        }

        let baseInsertText: String
        if let originObject = suggestion.origin?.object, !originObject.isEmpty {
            baseInsertText = originObject
        } else {
            baseInsertText = suggestion.insertText
        }

        let completionSuggestion = SQLCompletionSuggestion(id: suggestion.id,
                                                           title: suggestion.title,
                                                           subtitle: suggestion.subtitle,
                                                           detail: suggestion.detail,
                                                           insertText: baseInsertText,
                                                           kind: originalKind,
                                                           priority: suggestion.priority)

        let adjustedInsert = makeInsertText(from: completionSuggestion,
                                            mappedKind: suggestion.kind,
                                            query: query,
                                            origin: suggestion.origin)
        return suggestion.withInsertText(adjustedInsert)
    }

    private func shouldProvideCompletions(for query: SQLAutoCompletionQuery) -> Bool {
        let trimmedToken = query.token.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedToken.isEmpty && query.pathComponents.isEmpty {
            if query.precedingCharacter == "*" {
                return false
            }
            if query.clause == .selectList {
                return manualTriggerInProgress
            }
            if isObjectContext(query: query) {
                return true
            }
            if isColumnContext(query: query) || query.precedingCharacter == "," {
                let scopeTables = tablesForColumnSuggestions(query: query)
                if !scopeTables.isEmpty {
                    return true
                }
            }
            return false
        }
        if trimmedToken == "*" && query.pathComponents.isEmpty {
            return manualTriggerInProgress
        }
        let tokenLower = trimmedToken.lowercased()
        if SQLAutoCompletionEngine.reservedLeadingKeywords.contains(tokenLower) && query.pathComponents.isEmpty {
            return false
        }
        return true
    }

    private static func builtInFunctions(for databaseType: DatabaseType) -> [String] {
        switch databaseType {
        case .microsoftSQL:
            return [
                "COUNT",
                "SUM",
                "AVG",
                "MIN",
                "MAX",
                "LEN",
                "LOWER",
                "UPPER",
                "GETDATE",
                "DATEADD",
                "DATEDIFF",
                "ISNULL",
                "COALESCE",
                "ROUND",
                "ABS",
                "CEILING",
                "FLOOR",
                "NEWID",
                "CONVERT",
                "CAST",
                "FORMAT",
                "LEFT",
                "RIGHT",
                "SUBSTRING"
            ]
        case .postgresql:
            return [
                "COUNT",
                "SUM",
                "AVG",
                "MIN",
                "MAX",
                "LOWER",
                "UPPER",
                "CURRENT_DATE",
                "CURRENT_TIMESTAMP",
                "NOW",
                "COALESCE",
                "TO_CHAR",
                "TO_DATE",
                "TO_TIMESTAMP",
                "ROUND",
                "TRIM"
            ]
        case .mysql:
            return [
                "COUNT",
                "SUM",
                "AVG",
                "MIN",
                "MAX",
                "LOWER",
                "UPPER",
                "NOW",
                "CURDATE",
                "CURTIME",
                "DATE_ADD",
                "DATE_SUB",
                "COALESCE",
                "IFNULL",
                "ROUND",
                "TRIM"
            ]
        case .sqlite:
            return [
                "COUNT",
                "SUM",
                "AVG",
                "MIN",
                "MAX",
                "LOWER",
                "UPPER",
                "DATE",
                "DATETIME",
                "COALESCE",
                "IFNULL",
                "ROUND",
                "ABS",
                "LENGTH"
            ]
        }
    }

    private func isObjectContext(query: SQLAutoCompletionQuery) -> Bool {
        if !query.pathComponents.isEmpty { return true }
        switch query.clause {
        case .from, .joinTarget, .insertColumns, .deleteWhere, .withCTE:
            return true
        default:
            break
        }
        guard let keyword = query.precedingKeyword else { return false }
        return SQLAutoCompletionEngine.objectContextKeywords.contains(keyword)
    }

    private func isColumnContext(query: SQLAutoCompletionQuery) -> Bool {
        if query.precedingCharacter == "," { return true }
        if !query.pathComponents.isEmpty { return true }
        switch query.clause {
        case .selectList, .whereClause, .joinCondition, .groupBy, .orderBy, .having, .values, .updateSet:
            return true
        default:
            break
        }
        guard let keyword = query.precedingKeyword else { return false }
        if SQLAutoCompletionEngine.objectContextKeywords.contains(keyword) {
            return false
        }
        return SQLAutoCompletionEngine.columnContextKeywords.contains(keyword)
    }

    private func tablesForColumnSuggestions(query: SQLAutoCompletionQuery) -> [SQLAutoCompletionTableFocus] {
        var tables: [SQLAutoCompletionTableFocus] = []
        if !query.tablesInScope.isEmpty {
            tables = query.tablesInScope
        } else if let focus = query.focusTable {
            tables = [focus]
        }

        guard !tables.isEmpty else { return [] }

        var unique: [SQLAutoCompletionTableFocus] = []
        for table in tables {
            if !unique.contains(where: { $0.isEquivalent(to: table) }) {
                unique.append(table)
            }
        }
        return unique
    }

}

private extension DatabaseType {
    var sqlDialect: SQLDialect {
        switch self {
        case .postgresql:
            return .postgresql
        case .mysql:
            return .mysql
        case .sqlite:
            return .sqlite
        case .microsoftSQL:
            return .microsoftSQL
        }
    }
}
