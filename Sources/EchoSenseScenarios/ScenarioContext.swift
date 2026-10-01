import Foundation

/// What a scenario's query says around the caret, read independently of the completion engine (so
/// an engine bug can't hide behind it): the tables in the query and their aliases, CTEs and derived
/// tables with their columns, what is before a dot, what is typed, the table being changed and the
/// columns already in the SELECT list. Popup rules ("columns of the tables in the query") resolve
/// against it. A scenario can store its own when the reader gets one wrong.
public struct ScenarioContext: Codable, Sendable, Hashable {
    public struct Table: Codable, Sendable, Hashable {
        public var database: String?
        public var schema: String?
        public var name: String
        public var alias: String?
        public init(database: String? = nil, schema: String? = nil, name: String, alias: String? = nil) {
            self.database = database; self.schema = schema; self.name = name; self.alias = alias
        }
        /// "users (u)".
        public var label: String { alias.map { "\(name) (\($0))" } ?? name }
    }

    /// What the path before the caret names: `u.` is an alias, `analytics.` a schema, `otherdb.` a database.
    public struct Dot: Codable, Sendable, Hashable {
        public enum Kind: String, Codable, Sendable, Hashable { case alias, table, derived, schema, database, unknown }
        public var kind: Kind
        /// The last name before the dot, as typed.
        public var name: String
        /// The table an alias or table name stands for.
        public var table: String?
        /// The database a schema is in, when the path names one (`otherdb.dbo.`).
        public var database: String?
        public init(kind: Kind, name: String, table: String? = nil, database: String? = nil) {
            self.kind = kind; self.name = name; self.table = table; self.database = database
        }
    }

    public var tables: [Table]
    /// CTEs and derived tables (subqueries in FROM) by name, with their columns.
    public var derived: [String: [String]]
    public var dot: Dot?
    /// What is typed at the caret after the last dot.
    public var typed: String
    /// The table an INSERT, UPDATE or DELETE changes.
    public var changedTable: String?
    /// Plain column names already in the SELECT list.
    public var selectList: [String]

    public init(tables: [Table] = [], derived: [String: [String]] = [:], dot: Dot? = nil, typed: String = "", changedTable: String? = nil, selectList: [String] = []) {
        self.tables = tables; self.derived = derived; self.dot = dot; self.typed = typed; self.changedTable = changedTable; self.selectList = selectList
    }

    private enum CodingKeys: String, CodingKey { case tables, derived, dot, typed, changedTable, selectList }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tables = try c.decodeIfPresent([Table].self, forKey: .tables) ?? []
        derived = try c.decodeIfPresent([String: [String]].self, forKey: .derived) ?? [:]
        dot = try c.decodeIfPresent(Dot.self, forKey: .dot)
        typed = try c.decodeIfPresent(String.self, forKey: .typed) ?? ""
        changedTable = try c.decodeIfPresent(String.self, forKey: .changedTable)
        selectList = try c.decodeIfPresent([String].self, forKey: .selectList) ?? []
    }

    /// Table names in the query, without aliases.
    public var tableNames: [String] { tables.map(\.name) }
}
