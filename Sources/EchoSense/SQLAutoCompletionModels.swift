import Foundation

public enum SQLCompletionAggressiveness: String, CaseIterable, Codable, Sendable {
    case focused
    case balanced
    case eager
}

public struct SQLEditorCompletionContext: Equatable, Sendable {
    public var databaseType: EchoSenseDatabaseType
    public var selectedDatabase: String?
    public var defaultSchema: String?
    public var structure: EchoSenseDatabaseStructure?

    public init(
        databaseType: EchoSenseDatabaseType,
        selectedDatabase: String? = nil,
        defaultSchema: String? = nil,
        structure: EchoSenseDatabaseStructure? = nil
    ) {
        self.databaseType = databaseType
        self.selectedDatabase = selectedDatabase
        self.defaultSchema = defaultSchema
        self.structure = structure
    }
}

public enum SQLAutoCompletionKind: String, Equatable, Codable, Sendable {
    case schema
    case table
    case view
    case materializedView
    case column
    case function
    case keyword
    case snippet
    case parameter
    case join
    case database

    public var iconSystemName: String {
        switch self {
        case .schema: return "square.grid.2x2"
        case .database: return "cylinder"
        case .table: return "tablecells"
        case .view: return "rectangle.stack"
        case .materializedView: return "rectangle.stack.fill"
        case .column: return "doc.text"
        case .function: return "function"
        case .keyword: return "textformat"
        case .snippet: return "text.badge.plus"
        case .parameter: return "number"
        case .join: return "link"
        }
    }
}

public struct SQLAutoCompletionSuggestion: Identifiable, Equatable, Codable, Sendable {
    public struct Origin: Equatable, Codable, Sendable {
        public let database: String?
        public let schema: String?
        public let object: String?
        public let column: String?

        public init(database: String? = nil,
                    schema: String? = nil,
                    object: String? = nil,
                    column: String? = nil) {
            self.database = database?.trimmingCharacters(in: .whitespacesAndNewlines)
            self.schema = schema?.trimmingCharacters(in: .whitespacesAndNewlines)
            self.object = object?.trimmingCharacters(in: .whitespacesAndNewlines)
            self.column = column?.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var hasServerContext: Bool {
            if let database, !database.isEmpty { return true }
            if let schema, !schema.isEmpty { return true }
            if let object, !object.isEmpty { return true }
            return column?.isEmpty == false
        }
    }

    public struct TableColumn: Equatable, Codable, Sendable {
        public let name: String
        public let dataType: String
        public let isNullable: Bool
        public let isPrimaryKey: Bool

        public init(name: String,
                    dataType: String,
                    isNullable: Bool,
                    isPrimaryKey: Bool) {
            self.name = name
            self.dataType = dataType
            self.isNullable = isNullable
            self.isPrimaryKey = isPrimaryKey
        }
    }

    public enum Source: Equatable, Codable, Sendable {
        case engine
        case history
        case fallback
    }

    public let id: String
    public let title: String
    public let subtitle: String?
    public let detail: String?
    public let insertText: String
    public let kind: SQLAutoCompletionKind
    public let origin: Origin?
    public let dataType: String?
    public let tableColumns: [TableColumn]?
    public let snippetText: String?
    public let priority: Int
    public let source: Source

    public init(id: String = UUID().uuidString,
                title: String,
                subtitle: String? = nil,
                detail: String? = nil,
                insertText: String,
                kind: SQLAutoCompletionKind,
                origin: Origin? = nil,
                dataType: String? = nil,
                tableColumns: [TableColumn]? = nil,
                snippetText: String? = nil,
                priority: Int = 1000,
                source: Source = .engine) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.detail = detail ?? subtitle
        self.insertText = insertText
        self.kind = kind
        if let origin, origin.hasServerContext {
            self.origin = origin
        } else {
            self.origin = nil
        }
        self.dataType = dataType
        self.tableColumns = tableColumns?.isEmpty == true ? nil : tableColumns
        self.snippetText = snippetText
        self.priority = priority
        self.source = source
    }
}

extension SQLAutoCompletionSuggestion {
    public var displayKindTitle: String {
        switch kind {
        case .schema: return "Schema"
        case .table: return "Table"
        case .view: return "View"
        case .materializedView: return "Materialized View"
        case .column: return "Column"
        case .function: return "Function"
        case .keyword: return "Keyword"
        case .snippet: return "Snippet"
        case .parameter: return "Parameter"
        case .join: return "Join"
        case .database: return "Database"
        }
    }

    public var serverDisplayName: String? {
        guard let name = origin?.database, !name.isEmpty else { return nil }
        return name
    }

    public var displayObjectPath: String? {
        guard let origin else { return title.isEmpty ? (detail ?? subtitle) : title }

        func joined(_ components: [String?], separator: String = ".") -> String? {
            let trimmed = components.compactMap { component -> String? in
                guard let value = component?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
                    return nil
                }
                return value
            }
            guard !trimmed.isEmpty else { return nil }
            return trimmed.joined(separator: separator)
        }

        switch kind {
        case .schema:
            return joined([origin.schema])
        case .database:
            return joined([origin.database])
        case .table, .view, .materializedView:
            return joined([origin.schema, origin.object])
        case .column:
            return joined([origin.object, origin.column])
        case .function:
            return joined([origin.schema, origin.object])
        case .keyword:
            return detail ?? subtitle
        case .snippet, .parameter, .join:
            return detail ?? subtitle
        }
    }
}

extension SQLAutoCompletionSuggestion {
    public func withSource(_ newSource: Source) -> SQLAutoCompletionSuggestion {
        guard source != newSource else { return self }
        return SQLAutoCompletionSuggestion(id: id,
                                           title: title,
                                           subtitle: subtitle,
                                           detail: detail,
                                           insertText: insertText,
                                           kind: kind,
                                           origin: origin,
                                           dataType: dataType,
                                           tableColumns: tableColumns,
                                           snippetText: snippetText,
                                           priority: priority,
                                           source: newSource)
    }

    public func withInsertText(_ newInsertText: String) -> SQLAutoCompletionSuggestion {
        guard insertText != newInsertText else { return self }
        return SQLAutoCompletionSuggestion(id: id,
                                           title: title,
                                           subtitle: subtitle,
                                           detail: detail,
                                           insertText: newInsertText,
                                           kind: kind,
                                           origin: origin,
                                           dataType: dataType,
                                           tableColumns: tableColumns,
                                           snippetText: snippetText,
                                           priority: priority,
                                           source: source)
    }
}

public struct SQLAutoCompletionSection: Identifiable, Equatable, Sendable {
    public var id: String { title }
    public let title: String
    public let suggestions: [SQLAutoCompletionSuggestion]
}

public struct SQLAutoCompletionResult: Sendable {
    public let sections: [SQLAutoCompletionSection]
    public let metadata: SQLCompletionMetadata
}

public struct SQLAutoCompletionTableFocus: Equatable, Sendable {
    public let database: String?
    public let schema: String?
    public let name: String
    public let alias: String?

    public init(database: String? = nil, schema: String?, name: String, alias: String?) {
        self.database = database
        self.schema = schema
        self.name = name
        self.alias = alias
    }

    public func matches(schema otherSchema: String?, name otherName: String) -> Bool {
        guard name.caseInsensitiveCompare(otherName) == .orderedSame else { return false }
        guard let schema else { return true }
        guard let otherSchema else { return false }
        return schema.caseInsensitiveCompare(otherSchema) == .orderedSame
    }

    public func isEquivalent(to other: SQLAutoCompletionTableFocus) -> Bool {
        guard matches(schema: other.schema, name: other.name) else { return false }
        let lhsAlias = alias?.lowercased()
        let rhsAlias = other.alias?.lowercased()
        return lhsAlias == rhsAlias
    }
}

public struct SQLAutoCompletionQuery: Equatable, Sendable {
    public let token: String
    public let prefix: String
    public let pathComponents: [String]
    public let replacementRange: NSRange
    public let precedingKeyword: String?
    public let precedingCharacter: Character?
    public let focusTable: SQLAutoCompletionTableFocus?
    public let tablesInScope: [SQLAutoCompletionTableFocus]
    public let clause: SQLClause

    public init(token: String,
                prefix: String,
                pathComponents: [String],
                replacementRange: NSRange,
                precedingKeyword: String?,
                precedingCharacter: Character?,
                focusTable: SQLAutoCompletionTableFocus?,
                tablesInScope: [SQLAutoCompletionTableFocus],
                clause: SQLClause) {
        self.token = token
        self.prefix = prefix
        self.pathComponents = pathComponents
        self.replacementRange = replacementRange
        self.precedingKeyword = precedingKeyword
        self.precedingCharacter = precedingCharacter
        self.focusTable = focusTable
        self.tablesInScope = tablesInScope
        self.clause = clause
    }

    public var normalizedPrefix: String { prefix.trimmingCharacters(in: .whitespacesAndNewlines) }
    public var hasNonEmptyPrefix: Bool { !normalizedPrefix.isEmpty }
    public var dotCount: Int { token.filter { $0 == "." }.count }
}
