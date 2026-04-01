import Foundation

extension SQLAutoCompletionEngine {

    func mapSuggestions(_ suggestions: [SQLCompletionSuggestion],
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
        let filtered = results.filter { matchesQuery($0, query: query) }
        return rerankByMatchQuality(filtered, query: query)
    }

    /// Re-sorts filtered suggestions by fuzzy match quality against the current prefix so that
    /// shorter / tighter matches surface above longer ones regardless of base priority.
    /// When no prefix is typed, the original priority order is preserved.
    private func rerankByMatchQuality(_ suggestions: [SQLAutoCompletionSuggestion],
                                      query: SQLAutoCompletionQuery) -> [SQLAutoCompletionSuggestion] {
        let rawPrefix = query.prefix.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let prefixLower = rawPrefix.trimmingCharacters(in: SQLAutoCompletionEngine.identifierDelimiterCharacterSet)
        guard !prefixLower.isEmpty else { return suggestions }

        struct Scored {
            let suggestion: SQLAutoCompletionSuggestion
            let score: Double
        }

        let scored: [Scored] = suggestions.map { s in
            let titleLower = s.title.lowercased()
            if titleLower.hasPrefix(prefixLower) {
                // Prefer shorter titles for prefix matches — "employee" beats "employees" for "e"
                let coverage = Double(prefixLower.count) / Double(max(titleLower.count, 1))
                return Scored(suggestion: s, score: 0.90 + coverage * 0.10)
            } else if let match = FuzzyMatcher.match(pattern: prefixLower, candidate: titleLower) {
                return Scored(suggestion: s, score: match.score * 0.89)
            } else {
                return Scored(suggestion: s, score: 0.0)
            }
        }

        return scored.sorted { lhs, rhs in
            let diff = lhs.score - rhs.score
            if abs(diff) > 0.005 { return lhs.score > rhs.score }
            if lhs.suggestion.priority != rhs.suggestion.priority { return lhs.suggestion.priority > rhs.suggestion.priority }
            return lhs.suggestion.title.localizedCaseInsensitiveCompare(rhs.suggestion.title) == .orderedAscending
        }.map(\.suggestion)
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

    func mapKind(_ kind: SQLCompletionSuggestion.Kind) -> SQLAutoCompletionKind? {
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
        case .database: return .database
        }
    }

    func mapBackKind(_ kind: SQLAutoCompletionKind) -> SQLCompletionSuggestion.Kind? {
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
        case .database: return .database
        }
    }

    func matchesQuery(_ suggestion: SQLAutoCompletionSuggestion,
                      query: SQLAutoCompletionQuery) -> Bool {
        let rawToken = query.token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let tokenLower = rawToken.trimmingCharacters(in: SQLAutoCompletionEngine.identifierDelimiterCharacterSet)
        let rawPrefix = query.prefix.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let prefixLower = rawPrefix.trimmingCharacters(in: SQLAutoCompletionEngine.identifierDelimiterCharacterSet)
        let pathLower = query.pathComponents.map {
            $0.trimmingCharacters(in: SQLAutoCompletionEngine.identifierDelimiterCharacterSet).lowercased()
        }

        if suggestion.kind == .keyword {
            if tokenLower.isEmpty && prefixLower.isEmpty {
                return true
            }
            let insertLower = suggestion.insertText.lowercased()
            return FuzzyMatcher.match(pattern: tokenLower, candidate: insertLower) != nil ||
                   FuzzyMatcher.match(pattern: prefixLower, candidate: insertLower) != nil
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
                comparisonPool.contains(where: { FuzzyMatcher.match(pattern: tokenLower, candidate: $0) != nil }) {
                return true
            }

            if !prefixLower.isEmpty &&
                comparisonPool.contains(where: { FuzzyMatcher.match(pattern: prefixLower, candidate: $0) != nil }) {
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
           FuzzyMatcher.match(pattern: tokenLower, candidate: targetComponent) != nil,
           pathMatches() {
            return true
        }

        if let targetComponent,
           !prefixLower.isEmpty,
           FuzzyMatcher.match(pattern: prefixLower, candidate: targetComponent) != nil,
           pathMatches() {
            return true
        }

        // When the user has finished typing a dotted path qualifier (token ends with ".")
        // and no additional prefix has been typed yet, any single-component adjusted
        // insert text is a valid completion at this depth — providers already filtered
        // for the correct catalog/schema level.
        if tokenLower.hasSuffix(".") && prefixLower.isEmpty && !suggestion.insertText.contains(".") {
            return true
        }

        if tokenLower.isEmpty && prefixLower.isEmpty && pathMatches() {
            return true
        }

        let insertLower = suggestion.insertText.lowercased()

        if !tokenLower.isEmpty && FuzzyMatcher.match(pattern: tokenLower, candidate: insertLower) != nil {
            return true
        }

        if !prefixLower.isEmpty && FuzzyMatcher.match(pattern: prefixLower, candidate: insertLower) != nil {
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
            // Exact prefix match first, then fall back to fuzzy matching
            if suggestion.title.lowercased().hasPrefix(tokenLower) {
                return true
            }
            return FuzzyMatcher.match(pattern: tokenLower, candidate: suggestion.title) != nil
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

    func makeInsertText(from suggestion: SQLCompletionSuggestion,
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

}
