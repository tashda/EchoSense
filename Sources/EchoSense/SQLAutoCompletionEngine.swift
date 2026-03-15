import Foundation

typealias DatabaseStructure = EchoSenseDatabaseStructure
typealias DatabaseInfo = EchoSenseDatabaseInfo
typealias SchemaInfo = EchoSenseSchemaInfo
typealias SchemaObjectInfo = EchoSenseSchemaObjectInfo
typealias ColumnInfo = EchoSenseColumnInfo
typealias ForeignKeyReference = EchoSenseForeignKeyReference
typealias DatabaseType = EchoSenseDatabaseType

public final class SQLAutoCompletionEngine {
    private let completionEngine: SQLCompletionProviding
    static let identifierDelimiterCharacterSet: CharacterSet = {
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

    public init(completionEngine: SQLCompletionProviding? = nil) {
        if let completionEngine {
            self.completionEngine = completionEngine
        } else {
            self.completionEngine = SQLCompletionEngine(builderFactory: CachingSuggestionBuilderFactory())
        }
    }

    var context: SQLEditorCompletionContext?
    var catalog: SQLMetadataCatalog?
    private var builtInFunctions: [String] = []
    private var useTableAliasShortcuts = false
    let historyStore = SQLAutoCompletionHistoryStore.shared
    public private(set) var isMetadataLimited: Bool = false
    private var metadataProvider: SQLStructureMetadataProvider = .empty
    private var lastAcceptedClause: SQLClause?
    private var lastAcceptedCaretLocation: Int?
    var includeHistorySuggestions = true
    var preferQualifiedTableInsertions = false
    var aggressiveness: SQLCompletionAggressiveness = .balanced
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

    static let objectContextKeywords: Set<String> = [
        "from", "join", "inner", "left", "right", "full", "outer", "cross",
        "update", "into", "delete"
    ]

    private static let columnContextKeywords: Set<String> = [
        "select", "where", "on", "and", "or", "having", "group", "order",
        "by", "set", "values", "case", "when", "then", "else", "returning",
        "using"
    ]

    static let postObjectClauseKeywordOrder: [String] = [
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

    static let relationLikeKinds: Set<SQLAutoCompletionKind> = [
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
        lastAcceptedClause = nil
        lastAcceptedCaretLocation = nil
    }

    public func recordSelection(_ suggestion: SQLAutoCompletionSuggestion, query: SQLAutoCompletionQuery) {
        historyStore.record(suggestion, context: context)
        lastAcceptedClause = query.clause
        lastAcceptedCaretLocation = query.replacementRange.location + query.replacementRange.length
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
            // Only suppress if caret is still at the exact position where we accepted
            // AND the clause hasn't changed (user hasn't moved to a new context).
            if let acceptedClause = lastAcceptedClause,
               let acceptedCaret = lastAcceptedCaretLocation,
               acceptedClause == query.clause,
               caretLocation == acceptedCaret {
                return SQLAutoCompletionResult(sections: [],
                                               metadata: SQLAutoCompletionEngine.emptyMetadata)
            }
        }
        // Clear suppression state once the user starts typing or moves
        if !trimmedToken.isEmpty || !query.pathComponents.isEmpty {
            lastAcceptedClause = nil
            lastAcceptedCaretLocation = nil
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

    private func shouldProvideCompletions(for query: SQLAutoCompletionQuery) -> Bool {
        let trimmedToken = query.token.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedToken.isEmpty && query.pathComponents.isEmpty {
            if query.precedingCharacter == "*" {
                return false
            }
            // In SELECT list: show completions when tables are in scope or after comma
            if query.clause == .selectList {
                if manualTriggerInProgress { return true }
                if query.precedingCharacter == "," { return true }
                if !query.tablesInScope.isEmpty { return true }
                return false
            }
            if isObjectContext(query: query) {
                return true
            }
            // In FROM clause with tables already in scope: offer clause-continuation keywords
            if query.clause == .from && !query.tablesInScope.isEmpty {
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

    static func builtInFunctions(for databaseType: DatabaseType) -> [String] {
        switch databaseType {
        case .microsoftSQL:
            return [
                // Aggregate
                "COUNT", "SUM", "AVG", "MIN", "MAX", "STRING_AGG", "COUNT_BIG",
                // String
                "LEN", "LOWER", "UPPER", "CONCAT", "CHARINDEX", "PATINDEX",
                "REPLACE", "STUFF", "QUOTENAME", "TRIM", "LTRIM", "RTRIM",
                "LEFT", "RIGHT", "SUBSTRING", "REVERSE", "REPLICATE",
                // Date/Time
                "GETDATE", "GETUTCDATE", "SYSDATETIME", "DATEADD", "DATEDIFF",
                "DATEPART", "DATENAME", "EOMONTH", "FORMAT",
                // Conversion
                "CONVERT", "CAST", "TRY_CONVERT", "TRY_CAST", "PARSE", "TRY_PARSE",
                // Null handling
                "ISNULL", "COALESCE", "NULLIF",
                // Math
                "ROUND", "ABS", "CEILING", "FLOOR", "POWER", "SQRT", "SIGN",
                // Window
                "ROW_NUMBER", "RANK", "DENSE_RANK", "NTILE",
                "LAG", "LEAD", "FIRST_VALUE", "LAST_VALUE",
                // JSON
                "JSON_VALUE", "JSON_QUERY", "JSON_MODIFY", "ISJSON", "OPENJSON",
                // System
                "NEWID", "SCOPE_IDENTITY", "OBJECT_ID", "DB_NAME", "SCHEMA_NAME",
                "ERROR_MESSAGE", "ERROR_NUMBER",
                // Logic
                "IIF", "CHOOSE"
            ]
        case .postgresql:
            return [
                // Aggregate
                "COUNT", "SUM", "AVG", "MIN", "MAX", "STRING_AGG", "ARRAY_AGG",
                "BOOL_AND", "BOOL_OR", "JSONB_AGG", "JSON_AGG",
                // String
                "LOWER", "UPPER", "CONCAT", "LEFT", "RIGHT", "REPLACE",
                "REGEXP_REPLACE", "SPLIT_PART", "TRIM", "LTRIM", "RTRIM",
                "LENGTH", "CHAR_LENGTH", "POSITION", "SUBSTRING", "REVERSE",
                "INITCAP", "REPEAT", "LPAD", "RPAD",
                // Date/Time
                "NOW", "CURRENT_DATE", "CURRENT_TIMESTAMP", "AGE",
                "DATE_TRUNC", "DATE_PART", "EXTRACT", "TO_CHAR", "TO_DATE",
                "TO_TIMESTAMP", "MAKE_INTERVAL", "MAKE_DATE",
                // Conversion
                "CAST", "TO_NUMBER",
                // Null handling
                "COALESCE", "NULLIF",
                // Math
                "ROUND", "ABS", "CEIL", "FLOOR", "POWER", "SQRT", "SIGN",
                "GREATEST", "LEAST", "MOD", "RANDOM",
                // Window
                "ROW_NUMBER", "RANK", "DENSE_RANK", "NTILE",
                "LAG", "LEAD", "FIRST_VALUE", "LAST_VALUE", "NTH_VALUE",
                // JSON
                "JSON_BUILD_OBJECT", "JSON_BUILD_ARRAY",
                "JSONB_BUILD_OBJECT", "JSONB_BUILD_ARRAY",
                "JSON_EXTRACT_PATH_TEXT", "JSONB_EXTRACT_PATH_TEXT",
                "TO_JSON", "TO_JSONB", "JSON_TYPEOF", "JSONB_TYPEOF",
                // Array
                "UNNEST", "ARRAY_LENGTH", "ARRAY_POSITION", "ARRAY_REMOVE",
                "ARRAY_APPEND", "ARRAY_CAT",
                // Utility
                "GENERATE_SERIES", "GENERATE_SUBSCRIPTS",
                "PG_TYPEOF"
            ]
        case .mysql:
            return [
                "COUNT", "SUM", "AVG", "MIN", "MAX",
                "LOWER", "UPPER", "CONCAT", "LEFT", "RIGHT",
                "NOW", "CURDATE", "CURTIME", "DATE_ADD", "DATE_SUB",
                "COALESCE", "IFNULL", "ROUND", "TRIM",
                "REPLACE", "SUBSTRING", "CHAR_LENGTH", "LENGTH",
                "DATE_FORMAT", "STR_TO_DATE",
                "JSON_EXTRACT", "JSON_OBJECT", "JSON_ARRAY",
                "ROW_NUMBER", "RANK", "DENSE_RANK", "LAG", "LEAD",
                "CAST", "CONVERT", "NULLIF", "IF", "GROUP_CONCAT"
            ]
        case .sqlite:
            return [
                "COUNT", "SUM", "AVG", "MIN", "MAX",
                "LOWER", "UPPER", "LENGTH", "REPLACE", "SUBSTR", "TRIM",
                "DATE", "DATETIME", "TIME", "STRFTIME", "JULIANDAY",
                "COALESCE", "IFNULL", "NULLIF",
                "ROUND", "ABS", "RANDOM",
                "TYPEOF", "UNICODE", "QUOTE",
                "INSTR", "HEX", "ZEROBLOB",
                "GROUP_CONCAT", "TOTAL",
                "JSON", "JSON_EXTRACT", "JSON_ARRAY", "JSON_OBJECT",
                "ROW_NUMBER", "RANK", "DENSE_RANK", "LAG", "LEAD"
            ]
        }
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
