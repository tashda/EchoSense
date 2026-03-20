import Foundation

extension SQLAutoCompletionEngine {

    // MARK: - Clean API

    /// Returns completions for the given text at the specified cursor position.
    ///
    /// This is the primary entry point for the clean API. Consumers provide raw text
    /// and a cursor position; EchoSense handles all parsing, filtering, ranking, and
    /// deduplication internally.
    ///
    /// - Parameters:
    ///   - text: The full SQL text in the editor.
    ///   - caretLocation: The cursor position (UTF-16 offset) in the text.
    /// - Returns: A ``SQLCompletionResponse`` with ranked suggestions and metadata.
    public func completions(in text: String, at caretLocation: Int) -> SQLCompletionResponse {
        performCompletions(in: text, at: caretLocation)
    }

    /// Returns completions triggered manually (e.g. via keyboard shortcut).
    ///
    /// Behaves identically to ``completions(in:at:)`` but temporarily relaxes
    /// suppression rules so that suggestions appear even in contexts where
    /// automatic completion would stay silent.
    public func manualCompletions(in text: String, at caretLocation: Int) -> SQLCompletionResponse {
        manualTriggerInProgress = true
        defer { manualTriggerInProgress = false }
        return performCompletions(in: text, at: caretLocation)
    }

    /// Records that the user accepted a suggestion from a previous response.
    ///
    /// This feeds the history store so future completions can boost frequently
    /// selected items, and sets up post-commit suppression to avoid immediately
    /// re-showing the popover at the same position.
    public func recordSelection(_ suggestion: SQLAutoCompletionSuggestion,
                                from response: SQLCompletionResponse) {
        historyStore.record(suggestion, context: context)
        lastAcceptedClause = response.clause
        lastAcceptedCaretLocation = response.replacementRange.location + response.replacementRange.length
    }

    /// Updates all engine preferences from a consolidated struct.
    public func updatePreferences(_ preferences: SQLCompletionPreferences) {
        updateHistoryPreference(includeHistory: preferences.includeHistory)
        updateSystemSchemaVisibility(includeSystemSchemas: preferences.includeSystemSchemas)
        updateQualifiedInsertionPreference(includeSchema: preferences.qualifyTableInsertions)
        // autoJoinOnClause is reserved for future use when join-on-clause
        // generation is configurable at the engine level.
    }

    /// Records table usage from an executed query.
    ///
    /// Call this after a query is successfully executed. EchoSense parses the
    /// FROM/JOIN clauses to extract table references and records them to history.
    /// This allows history to learn from all queries, not just popover selections.
    ///
    /// - Parameter sql: The SQL text that was executed.
    public func recordQueryExecution(_ sql: String) {
        guard let context else { return }
        guard !sql.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let catalogForParser: SQLDatabaseCatalog
        if let provider = catalog?.metadataProvider {
            catalogForParser = provider.catalog(for: context.selectedDatabase) ?? SQLDatabaseCatalog(schemas: [])
        } else {
            catalogForParser = SQLDatabaseCatalog(schemas: [])
        }

        let parser = SQLContextParser(text: sql,
                                       caretLocation: sql.count,
                                       dialect: context.databaseType.completionDialect,
                                       catalog: catalogForParser)
        let parsed = parser.parse()

        for tableRef in parsed.tablesInScope {
            // Build a minimal suggestion for history recording
            let schemaName = tableRef.schema ?? context.defaultSchema ?? ""
            let id = "object|\(schemaName.lowercased())|\(tableRef.name.lowercased())"

            // Look up the table in the catalog for full metadata
            var tableColumns: [SQLAutoCompletionSuggestion.TableColumn]?
            for schema in catalogForParser.schemas {
                if let obj = schema.objects.first(where: { $0.name.caseInsensitiveCompare(tableRef.name) == .orderedSame }) {
                    tableColumns = obj.columns.map {
                        SQLAutoCompletionSuggestion.TableColumn(name: $0.name, dataType: $0.dataType,
                                                                 isNullable: $0.isNullable, isPrimaryKey: $0.isPrimaryKey)
                    }
                    break
                }
            }

            let suggestion = SQLAutoCompletionSuggestion(
                id: id,
                title: tableRef.name,
                subtitle: schemaName.isEmpty ? nil : schemaName,
                detail: schemaName.isEmpty ? tableRef.name : "\(schemaName).\(tableRef.name)",
                insertText: tableRef.name,
                kind: .table,
                origin: .init(database: context.selectedDatabase, schema: schemaName, object: tableRef.name),
                tableColumns: tableColumns
            )

            historyStore.record(suggestion, context: context)
        }
    }

    /// Clears post-commit suppression state so completions can appear again
    /// at the current cursor position.
    public func clearSuppression() {
        clearPostCommitSuppression()
    }

    // MARK: - Internal

    private func performCompletions(in text: String, at caretLocation: Int) -> SQLCompletionResponse {
        let empty = SQLCompletionResponse(suggestions: [],
                                           replacementRange: NSRange(location: caretLocation, length: 0),
                                           token: "",
                                           clause: .unknown,
                                           isMetadataLimited: isMetadataLimited,
                                           caretLocation: caretLocation)

        guard let context else { return empty }
        guard !text.isEmpty else { return empty }

        let nsText = text as NSString
        let clampedCaret = max(0, min(caretLocation, nsText.length))

        // Parse the SQL context at the cursor position.
        let catalogForParser: SQLDatabaseCatalog
        if let provider = catalog?.metadataProvider {
            catalogForParser = provider.catalog(for: context.selectedDatabase) ?? SQLDatabaseCatalog(schemas: [])
        } else {
            catalogForParser = SQLDatabaseCatalog(schemas: [])
        }

        let parser = SQLContextParser(text: text,
                                       caretLocation: clampedCaret,
                                       dialect: context.databaseType.completionDialect,
                                       catalog: catalogForParser)
        let parsed = parser.parse()

        // Extract token, prefix, and path components from the parsed context.
        let token = parsed.currentToken
        let components = token.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        let prefix = components.last ?? ""
        let pathComponents = Array(components.dropLast().filter { !$0.isEmpty })

        // Compute the replacement range: covers only the prefix portion.
        let replacementRange = NSRange(location: clampedCaret - prefix.count, length: prefix.count)

        // Compute the preceding character by scanning backward from the token start.
        let tokenStart = clampedCaret - token.count
        let precedingCharacter = Self.findPrecedingCharacter(in: nsText, before: tokenStart)

        // Convert parsed tables to the query model.
        let tablesInScope = parsed.tablesInScope.map {
            SQLAutoCompletionTableFocus(schema: $0.schema, name: $0.name, alias: $0.alias)
        }
        let focusTable = parsed.focusTable.map {
            SQLAutoCompletionTableFocus(schema: $0.schema, name: $0.name, alias: $0.alias)
        }

        // Suppress completions in column contexts when no tables are known.
        // Without tables, columns/functions are meaningless noise.
        if tablesInScope.isEmpty && pathComponents.isEmpty {
            let columnClauses: Set<SQLClause> = [
                .selectList, .whereClause, .groupBy, .orderBy, .having,
                .joinCondition, .values, .updateSet, .unknown
            ]
            if columnClauses.contains(parsed.clause) && !manualTriggerInProgress {
                return SQLCompletionResponse(suggestions: [],
                                              replacementRange: replacementRange,
                                              token: token,
                                              clause: parsed.clause,
                                              isMetadataLimited: isMetadataLimited,
                                              caretLocation: clampedCaret)
            }
        }

        // Build the query for the existing pipeline.
        let query = SQLAutoCompletionQuery(token: token,
                                            prefix: prefix,
                                            pathComponents: pathComponents,
                                            replacementRange: replacementRange,
                                            precedingKeyword: parsed.precedingKeyword,
                                            precedingCharacter: precedingCharacter,
                                            focusTable: focusTable,
                                            tablesInScope: tablesInScope,
                                            clause: parsed.clause)

        // Run through the existing suggestions pipeline.
        let result = suggestions(for: query, text: text, caretLocation: clampedCaret)

        // Flatten sections into a single ranked list, limited to 60 items.
        let allSuggestions = result.sections.flatMap(\.suggestions)
        let limited = allSuggestions.count > 60 ? Array(allSuggestions.prefix(60)) : allSuggestions

        return SQLCompletionResponse(suggestions: limited,
                                      replacementRange: replacementRange,
                                      token: token,
                                      clause: parsed.clause,
                                      isMetadataLimited: isMetadataLimited,
                                      caretLocation: clampedCaret)
    }

    /// Scans backward from `position` in `text` to find the first non-whitespace character.
    private static func findPrecedingCharacter(in text: NSString, before position: Int) -> Character? {
        guard position > 0 else { return nil }
        var pos = position - 1
        while pos >= 0 {
            let unichar = text.character(at: pos)
            guard let scalar = UnicodeScalar(unichar) else {
                pos -= 1
                continue
            }
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                pos -= 1
                continue
            }
            return Character(scalar)
        }
        return nil
    }
}

// MARK: - DatabaseType dialect conversion (internal)

private extension EchoSenseDatabaseType {
    var completionDialect: SQLDialect {
        switch self {
        case .postgresql: return .postgresql
        case .mysql: return .mysql
        case .sqlite: return .sqlite
        case .microsoftSQL: return .microsoftSQL
        }
    }
}
