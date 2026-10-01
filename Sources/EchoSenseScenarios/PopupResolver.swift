import EchoSense
import Foundation

/// Turns blocks into what they mean in one scenario: the items they name, a sentence describing them,
/// whether a popup row belongs to them, and where a popup row comes from.
public struct PopupResolver: Sendable, Hashable {
    public let context: ScenarioContext
    public let structure: EchoSenseDatabaseStructure
    public let dialect: ScenarioDialect
    /// The database the editor is connected to.
    public let database: String
    public let defaultSchema: String

    public init(context: ScenarioContext, structure: EchoSenseDatabaseStructure, dialect: ScenarioDialect, database: String?) {
        self.context = context; self.structure = structure; self.dialect = dialect
        self.database = database ?? structure.databases.first?.name ?? ""
        self.defaultSchema = ScenarioSchemas.defaultSchema(for: dialect) ?? "main"
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(context); hasher.combine(dialect); hasher.combine(database)
    }

    public static let aggregates = ["COUNT", "SUM", "AVG", "MIN", "MAX"]
    public static let sortKeywords = ["ASC", "DESC", "NULLS FIRST", "NULLS LAST"]

    public static func operatorKeywords(_ dialect: ScenarioDialect) -> [String] {
        dialect == .postgresql ? ["IN", "IS NULL", "IS NOT NULL", "LIKE", "ILIKE", "BETWEEN"] : ["IN", "IS NULL", "IS NOT NULL", "LIKE", "BETWEEN"]
    }

    /// Functions that belong to other databases, never this one.
    public static func otherDialectFunctions(_ dialect: ScenarioDialect) -> [String] {
        switch dialect {
        case .postgresql: ["ISNULL", "STUFF", "IFNULL", "GETDATE"]
        case .mssql: ["IFNULL", "UNNEST", "ARRAY_AGG", "NOW"]
        case .mysql: ["ISNULL", "STUFF", "UNNEST", "ARRAY_AGG"]
        case .sqlite: ["ISNULL", "STUFF", "UNNEST", "ARRAY_AGG", "GETDATE"]
        }
    }

    // MARK: Items

    /// What the block names here, narrowed to what is typed when `typed`; nil when it is matched by
    /// kind instead (built-in functions, fitting keywords, snippets, parameters).
    public func items(_ block: PopupBlock, typed: Bool = false, order: [String] = []) -> [PopupItem]? {
        guard var items = unfilteredItems(block) else { return nil }
        if typed, !context.typed.isEmpty { items = items.filter { Self.starts($0.name, with: context.typed) } }
        if !order.isEmpty {
            items.sort { (order.firstIndex(of: $0.name) ?? Int.max) < (order.firstIndex(of: $1.name) ?? Int.max) }
        }
        return items
    }

    private func unfilteredItems(_ block: PopupBlock) -> [PopupItem]? {
        switch block.family {
        case .objects: return objects(block)
        case .columns: return columns(block)
        case .functions:
            switch block.place {
            case .aggregate?: return Self.aggregates.map { PopupItem(name: $0, kind: "function", parent: "built-in") }
            case .database?:
                return currentSchemas.flatMap { schema in schema.objects.filter { $0.type == .function || $0.type == .procedure }
                    .map { PopupItem(name: $0.name, kind: $0.type.rawValue, parent: schema.name) } }
            case .otherDialects?: return Self.otherDialectFunctions(dialect).map { PopupItem(name: $0, kind: "function", parent: "not \(dialect.title)") }
            default: return nil
            }
        case .keywords:
            switch block.place {
            case .sort?: return Self.sortKeywords.map { PopupItem(name: $0, kind: "keyword") }
            case .operators?: return Self.operatorKeywords(dialect).map { PopupItem(name: $0, kind: "keyword") }
            default: return nil
            }
        case .schemas:
            let db = block.place == .databaseBeforeDot ? context.dot?.name : database
            return (structure.databases.first { $0.name.lowercased() == db?.lowercased() }?.schemas ?? [])
                .map { PopupItem(name: $0.name, kind: "schema", parent: db ?? "") }
        case .databases: return structure.databases.map { PopupItem(name: $0.name, kind: "database", parent: "server") }
        case .snippets, .parameters: return nil
        }
    }

    private var currentSchemas: [EchoSenseSchemaInfo] { structure.databases.first { $0.name == database }?.schemas ?? [] }

    private func objects(_ block: PopupBlock) -> [PopupItem] {
        let kinds = block.kinds.isEmpty ? PopupBlock.objectKinds : block.kinds
        let inQuery = Set(context.tableNames.map { $0.lowercased() })
        var found: [(db: String, schema: String, object: EchoSenseSchemaObjectInfo)] = []
        for db in structure.databases {
            for schema in db.schemas {
                for object in schema.objects where kinds.contains(object.type.rawValue) { found.append((db.name, schema.name, object)) }
            }
        }
        let here = { (db: String) in db.lowercased() == self.database.lowercased() }
        switch block.place {
        case .defaultSchema?: found = found.filter { here($0.db) && $0.schema == defaultSchema }
        case .otherSchemas?: found = found.filter { here($0.db) && $0.schema != defaultSchema }
        case .schemaBeforeDot?:
            let db = context.dot?.database ?? database
            found = found.filter { $0.db.lowercased() == db.lowercased() && $0.schema.lowercased() == context.dot?.name.lowercased() }
        case .databaseBeforeDot?: found = found.filter { $0.db.lowercased() == context.dot?.name.lowercased() }
        case .inQuery?: found = found.filter { here($0.db) && inQuery.contains($0.object.name.lowercased()) }
        case .linkedByForeignKey?:
            let queryObjects = found.filter { here($0.db) && inQuery.contains($0.object.name.lowercased()) }.map(\.object)
            found = found.filter { candidate in
                here(candidate.db) && !inQuery.contains(candidate.object.name.lowercased()) && candidate.object.type == .table
                    && queryObjects.contains { Self.linked($0, candidate.object) }
            }
        case .derived?:
            return context.derived.keys.sorted().map { PopupItem(name: $0, kind: "table", parent: "this query") }
        default: found = found.filter { here($0.db) }
        }
        if block.notInQuery { found = found.filter { !inQuery.contains($0.object.name.lowercased()) } }
        return found.map { PopupItem(name: $0.object.name, kind: $0.object.type.rawValue, parent: here($0.db) ? $0.schema : "\($0.db).\($0.schema)") }
    }

    static func linked(_ a: EchoSenseSchemaObjectInfo, _ b: EchoSenseSchemaObjectInfo) -> Bool {
        a.columns.contains { $0.foreignKey?.referencedTable.lowercased() == b.name.lowercased() }
            || b.columns.contains { $0.foreignKey?.referencedTable.lowercased() == a.name.lowercased() }
    }

    private func columns(_ block: PopupBlock) -> [PopupItem] {
        let sources: [String]
        switch block.place {
        case .beforeDot?: sources = context.dot?.table.map { [$0] } ?? []
        case .changedTable?: sources = context.changedTable.map { [$0] } ?? []
        case .selectList?: return context.selectList.map { PopupItem(name: $0, kind: "column", parent: "the SELECT list") }
        default: sources = context.tableNames
        }
        var items: [PopupItem] = []
        for source in sources {
            for column in columns(of: source) where !block.keysOnly || column.key {
                if !items.contains(where: { $0.name == column.name && $0.parent == source }) { items.append(PopupItem(name: column.name, kind: "column", parent: source)) }
            }
        }
        return items
    }

    /// A table's columns, or a CTE's or subquery's (expanding `SELECT *`).
    func columns(of source: String) -> [(name: String, key: Bool)] {
        if let derived = context.derived.first(where: { $0.key.lowercased() == source.lowercased() })?.value {
            return derived.flatMap { name in name.hasPrefix("*") ? columns(of: String(name.dropFirst())) : [(name, false)] }
        }
        guard let object = currentSchemas.flatMap(\.objects).first(where: { $0.name.lowercased() == source.lowercased() }) else { return [] }
        return object.columns.map { ($0.name, $0.isPrimaryKey || $0.foreignKey != nil) }
    }

    // MARK: Matching popup rows

    /// Whether a popup row (title and EchoSense's kind) belongs to the block.
    public func matches(title: String, kind: String, block: PopupBlock, typed: Bool = false) -> Bool {
        let name = CompletionScenarioRunner.unquoted(title)
        if let items = items(block, typed: typed) {
            return items.contains { $0.name.lowercased() == name.lowercased() && Self.sameKind(kind, $0.kind) }
        }
        if typed, !context.typed.isEmpty, !Self.starts(name, with: context.typed) { return false }
        switch block.family {
        case .functions: return kind == "function" && !currentSchemas.flatMap(\.objects).contains { $0.name.lowercased() == name.lowercased() }
        case .keywords: return kind == "keyword"
        case .snippets: return kind == "snippet"
        case .parameters: return kind == "parameter"
        default: return false
        }
    }

    /// The elements that match first, then the rest, each in their own order.
    static func first<T>(_ elements: [T], where isFirst: (T) -> Bool) -> [T] { elements.filter(isFirst) + elements.filter { !isFirst($0) } }

    static func sameKind(_ rowKind: String, _ itemKind: String) -> Bool {
        rowKind == itemKind || (rowKind == "join" && itemKind == "table")
    }

    static func starts(_ name: String, with typed: String) -> Bool {
        CompletionScenarioRunner.unquoted(name).lowercased().hasPrefix(CompletionScenarioRunner.unquoted(typed).lowercased())
    }

    /// Where a popup row comes from, in words: "in public", "of users", "built-in".
    public func origin(title: String, kind: String) -> String {
        let name = CompletionScenarioRunner.unquoted(title).lowercased()
        switch kind {
        case "table", "view", "materializedView", "join":
            let preferred = context.dot?.kind == .database ? context.dot?.name ?? database : database
            for db in Self.first(structure.databases, where: { $0.name == preferred }) {
                for schema in Self.first(db.schemas, where: { $0.name == defaultSchema }) where schema.objects.contains(where: { $0.name.lowercased() == name }) {
                    return db.name == database ? "in \(schema.name)" : "in \(db.name).\(schema.name)"
                }
            }
            return context.derived.keys.contains { $0.lowercased() == name } ? "in this query" : ""
        case "column":
            let sources = context.dot?.table.map { [$0] } ?? context.tableNames
            let owners = sources.filter { source in columns(of: source).contains { $0.name.lowercased() == name } }
            return owners.isEmpty ? "" : "of \(owners.joined(separator: ", "))"
        case "function", "procedure":
            return currentSchemas.first { $0.objects.contains { $0.name.lowercased() == name } }.map { "in \($0.name)" } ?? "built-in"
        case "schema":
            return title == "Built-in" ? "not a real schema: built-in functions" : "in \(context.dot?.kind == .database ? context.dot?.name ?? database : database)"
        default: return ""
        }
    }
}
