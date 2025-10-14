import Foundation

public struct SQLCompletionRequest {
    public let text: String
    public let caretLocation: Int
    public let dialect: SQLDialect
    public let selectedDatabase: String?
    public let defaultSchema: String?
    public let metadata: SQLMetadataProvider
    public let options: SQLEngineOptions

    public init(text: String,
                caretLocation: Int,
                dialect: SQLDialect,
                selectedDatabase: String?,
                defaultSchema: String?,
                metadata: SQLMetadataProvider,
                options: SQLEngineOptions) {
        self.text = text
        self.caretLocation = caretLocation
        self.dialect = dialect
        self.selectedDatabase = selectedDatabase
        self.defaultSchema = defaultSchema
        self.metadata = metadata
        self.options = options
    }
}

public struct SQLCompletionResult {
    public let suggestions: [SQLCompletionSuggestion]

    public init(suggestions: [SQLCompletionSuggestion]) {
        self.suggestions = suggestions
    }
}

public struct SQLCompletionSuggestion: Identifiable, Equatable {
    public enum Kind: String {
        case keyword
        case schema
        case table
        case view
        case materializedView
        case column
        case function
        case procedure
        case snippet
    }

    public let id: String
    public let title: String
    public let subtitle: String?
    public let detail: String?
    public let insertText: String
    public let kind: Kind
    public let priority: Int

    public init(id: String = UUID().uuidString,
                title: String,
                subtitle: String? = nil,
                detail: String? = nil,
                insertText: String,
                kind: Kind,
                priority: Int = 1000) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.detail = detail
        self.insertText = insertText
        self.kind = kind
        self.priority = priority
    }
}

public enum SQLDialect: String {
    case postgresql
    case mysql
    case sqlite
    case microsoftSQL
}

public struct SQLEngineOptions {
    public var enableAliasShortcuts: Bool
    public var keywordCasing: KeywordCasing

    public enum KeywordCasing {
        case upper
        case lower
        case preserve
    }

    public init(enableAliasShortcuts: Bool = false,
                keywordCasing: KeywordCasing = .upper) {
        self.enableAliasShortcuts = enableAliasShortcuts
        self.keywordCasing = keywordCasing
    }
}

public protocol SQLMetadataProvider {
    /// Returns metadata for the specified database (or default database when `name` is nil).
    func catalog(for database: String?) -> SQLDatabaseCatalog?
}

public struct SQLDatabaseCatalog {
    public let schemas: [SQLSchema]

    public init(schemas: [SQLSchema]) {
        self.schemas = schemas
    }
}

public struct SQLSchema {
    public let name: String
    public let objects: [SQLObject]

    public init(name: String, objects: [SQLObject]) {
        self.name = name
        self.objects = objects
    }
}

public struct SQLObject {
    public enum ObjectType {
        case table
        case view
        case materializedView
        case function
        case procedure
    }

    public let name: String
    public let type: ObjectType
    public let columns: [SQLColumn]

    public init(name: String, type: ObjectType, columns: [SQLColumn] = []) {
        self.name = name
        self.type = type
        self.columns = columns
    }
}

public struct SQLColumn {
    public let name: String
    public let dataType: String

    public init(name: String, dataType: String) {
        self.name = name
        self.dataType = dataType
    }
}

public protocol SQLCompletionEngineProtocol {
    func completions(for request: SQLCompletionRequest) -> SQLCompletionResult
}

public enum SQLAutocompleteHeuristics {
    public static let objectContextKeywords: Set<String> = SQLContextParser.objectContextKeywords
    public static let columnContextKeywords: Set<String> = SQLContextParser.columnContextKeywords
}
