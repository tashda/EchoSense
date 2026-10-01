import Foundation

/// What the popup should hold, written the way the owner thinks about it: groups in order, each a
/// block ("tables in the default schema", "columns of the tables in the query", "aggregate
/// functions"), then whether anything else may follow, and what must never appear.
///
/// A block resolves against the scenario's query (`ScenarioContext`) and sample database, so the rule
/// names kinds of things from places, not loose titles: `users` is "a table in public", not a word.
public struct PopupExpectation: Codable, Sendable, Hashable {
    public enum Rest: String, Codable, Sendable, Hashable, CaseIterable {
        /// Anything else may follow the groups (but not come before them).
        case any
        /// Nothing but the groups.
        case none
    }

    public var groups: [PopupGroup]
    public var rest: Rest
    public var never: [PopupBlock]

    public init(groups: [PopupGroup] = [], rest: Rest = .any, never: [PopupBlock] = []) {
        self.groups = groups; self.rest = rest; self.never = never
    }

    private enum CodingKeys: String, CodingKey { case groups, rest, never }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        groups = try c.decodeIfPresent([PopupGroup].self, forKey: .groups) ?? []
        rest = try c.decodeIfPresent(Rest.self, forKey: .rest) ?? .any
        never = try c.decodeIfPresent([PopupBlock].self, forKey: .never) ?? []
    }
}

/// One group: a block, narrowed to what is typed if wanted, with an order inside it or names it must include.
public struct PopupGroup: Codable, Sendable, Hashable {
    public var block: PopupBlock
    /// Only those starting with what is typed at the caret.
    public var typed: Bool
    /// These names, in this order, inside the group (all or some of what the block covers).
    public var order: [String]
    /// For blocks matched by kind (built-in functions, keywords): names it must include.
    public var include: [String]

    public init(_ block: PopupBlock, typed: Bool = false, order: [String] = [], include: [String] = []) {
        self.block = block; self.typed = typed; self.order = order; self.include = include
    }

    private enum CodingKeys: String, CodingKey { case block, typed, order, include }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        block = try c.decode(PopupBlock.self, forKey: .block)
        typed = try c.decodeIfPresent(Bool.self, forKey: .typed) ?? false
        order = try c.decodeIfPresent([String].self, forKey: .order) ?? []
        include = try c.decodeIfPresent([String].self, forKey: .include) ?? []
    }
}

/// A kind of thing from a place. Families and places come from reading every scenario's "what should happen".
public struct PopupBlock: Codable, Sendable, Hashable {
    public enum Family: String, Codable, Sendable, Hashable, CaseIterable {
        case objects, columns, functions, keywords, schemas, databases, snippets, parameters
    }

    public enum Place: String, Codable, Sendable, Hashable, CaseIterable {
        // Objects (tables, views, materialized views)
        case defaultSchema, otherSchemas, schemaBeforeDot, databaseBeforeDot, linkedByForeignKey, inQuery, derived
        // Columns
        case beforeDot, query, changedTable, selectList
        // Functions
        case aggregate, builtIn, database, otherDialects
        // Keywords
        case fitting, sort, operators
        // Schemas
        case thisDatabase
    }

    public var family: Family
    public var place: Place?
    /// For objects: "table", "view", "materializedView".
    public var kinds: [String]
    /// For columns: only primary and foreign keys.
    public var keysOnly: Bool
    /// For objects: leave out tables already in the query.
    public var notInQuery: Bool

    public init(_ family: Family, _ place: Place? = nil, kinds: [String] = [], keysOnly: Bool = false, notInQuery: Bool = false) {
        self.family = family; self.place = place; self.kinds = kinds; self.keysOnly = keysOnly; self.notInQuery = notInQuery
    }

    private enum CodingKeys: String, CodingKey { case family, place, kinds, keysOnly, notInQuery }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        family = try c.decode(Family.self, forKey: .family)
        place = try c.decodeIfPresent(Place.self, forKey: .place)
        kinds = try c.decodeIfPresent([String].self, forKey: .kinds) ?? []
        keysOnly = try c.decodeIfPresent(Bool.self, forKey: .keysOnly) ?? false
        notInQuery = try c.decodeIfPresent(Bool.self, forKey: .notInQuery) ?? false
    }

    public static let objectKinds = ["table", "view", "materializedView"]
}

/// One thing a block names here: `users`, a table in public.
public struct PopupItem: Sendable, Hashable {
    public var name: String
    /// As EchoSense names kinds: "table", "column", "function", "keyword", "schema", ...
    public var kind: String
    /// Where it lives, in words: "public", "users", "built-in", "otherdb.dbo".
    public var parent: String

    public init(name: String, kind: String, parent: String = "") { self.name = name; self.kind = kind; self.parent = parent }
}
