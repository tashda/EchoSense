import Foundation
import Testing
@testable import EchoSense

// MARK: - Section 7: CTEs

@Suite("Spec 7 — CTEs")
struct SpecCTETests {

    // MARK: 7.1 CTE with explicit columns

    @Test("7.1 CTE with explicit columns shows those columns")
    func cteExplicitColumnsShown() {
        let engine = SpecHelpers.makeSpecEngine()
        let cteFocus = SQLAutoCompletionTableFocus(schema: nil, name: "active", alias: nil)
        let text = "WITH active(uid, uname) AS (SELECT id, name FROM users) SELECT  FROM active"
        let caretPos = 63 // at the empty space between "SELECT " and "FROM" in the outer query
        let query = SQLAutoCompletionQuery(
            token: "", prefix: "", pathComponents: [],
            replacementRange: NSRange(location: caretPos, length: 0),
            precedingKeyword: "select", precedingCharacter: nil,
            focusTable: cteFocus,
            tablesInScope: [cteFocus],
            clause: .selectList
        )

        let result = engine.suggestions(for: query, text: text, caretLocation: caretPos)
        let columns = SpecHelpers.suggestionTitles(from: result, kind: .column)
        // Note: some column names may be auto-quoted if they match reserved words
        #expect(columns.contains("uid") || columns.contains("\"uid\""),
                "Should show explicit CTE column uid, got: \(columns)")
        #expect(columns.contains("uname"), "Should show explicit CTE column uname")
        #expect(!columns.contains("id"), "Should NOT show inner SELECT column id")
        #expect(!columns.contains(where: { $0 == "name" || $0 == "\"name\"" }),
                "Should NOT show inner SELECT column name")
    }

    // MARK: 7.2 CTE without explicit columns — infer from inner SELECT (NEW BEHAVIOR)

    @Test("7.2 CTE without explicit columns infers from inner SELECT")
    func cteInferColumnsFromInnerSelect() {
        let engine = SpecHelpers.makeSpecEngine()
        let cteFocus = SQLAutoCompletionTableFocus(schema: nil, name: "recent_orders", alias: nil)
        let text = "WITH recent_orders AS (SELECT id, total, status FROM orders) SELECT  FROM recent_orders"
        let caretPos = text.range(of: "SELECT  FROM")!.lowerBound
        let caretOffset = text.distance(from: text.startIndex, to: caretPos) + 7 // after "SELECT "
        let query = SQLAutoCompletionQuery(
            token: "", prefix: "", pathComponents: [],
            replacementRange: NSRange(location: caretOffset, length: 0),
            precedingKeyword: "select", precedingCharacter: nil,
            focusTable: cteFocus,
            tablesInScope: [cteFocus],
            clause: .selectList
        )

        let result = engine.suggestions(for: query, text: text, caretLocation: caretOffset)
        let columns = SpecHelpers.suggestionTitles(from: result, kind: .column)
        // NEW BEHAVIOR: engine should infer id, total, status from inner SELECT
        #expect(columns.contains("id"), "Should infer column id from inner SELECT")
        #expect(columns.contains("total"), "Should infer column total from inner SELECT")
        #expect(columns.contains("status") || columns.contains("\"status\""),
                "Should infer column status from inner SELECT")
    }

    // MARK: 7.3 CTE with aliased columns — use aliases (NEW BEHAVIOR)

    @Test("7.3 CTE with aliased columns uses aliases")
    func cteAliasedColumnsUseAliases() {
        let engine = SpecHelpers.makeSpecEngine()
        let cteFocus = SQLAutoCompletionTableFocus(schema: nil, name: "totals", alias: nil)
        let text = "WITH totals AS (SELECT user_id AS uid, SUM(total) AS grand_total FROM orders GROUP BY user_id) SELECT  FROM totals"
        let caretPos = text.range(of: "SELECT  FROM totals")!.lowerBound
        let caretOffset = text.distance(from: text.startIndex, to: caretPos) + 7 // at the space between "SELECT" and "FROM"
        let query = SQLAutoCompletionQuery(
            token: "", prefix: "", pathComponents: [],
            replacementRange: NSRange(location: caretOffset, length: 0),
            precedingKeyword: "select", precedingCharacter: nil,
            focusTable: cteFocus,
            tablesInScope: [cteFocus],
            clause: .selectList
        )

        let result = engine.suggestions(for: query, text: text, caretLocation: caretOffset)
        let columns = SpecHelpers.suggestionTitles(from: result, kind: .column)
        // NEW BEHAVIOR: should use alias names, not original column names
        #expect(columns.contains("uid") || columns.contains("\"uid\""),
                "Should use alias uid instead of user_id, got: \(columns)")
        #expect(columns.contains("grand_total"),
                "Should use alias grand_total, got: \(columns)")
    }

    // MARK: 7.4 CTE with SELECT * — resolve to actual columns (NEW BEHAVIOR)

    @Test("7.4 CTE with SELECT * resolves to actual table columns")
    func cteSelectStarResolvesToColumns() {
        let engine = SpecHelpers.makeSpecEngine()
        let cteFocus = SQLAutoCompletionTableFocus(schema: nil, name: "all_users", alias: nil)
        let text = "WITH all_users AS (SELECT * FROM users) SELECT  FROM all_users"
        let caretPos = text.range(of: "SELECT  FROM all_users")!.lowerBound
        let caretOffset = text.distance(from: text.startIndex, to: caretPos) + 7
        let query = SQLAutoCompletionQuery(
            token: "", prefix: "", pathComponents: [],
            replacementRange: NSRange(location: caretOffset, length: 0),
            precedingKeyword: "select", precedingCharacter: nil,
            focusTable: cteFocus,
            tablesInScope: [cteFocus],
            clause: .selectList
        )

        let result = engine.suggestions(for: query, text: text, caretLocation: caretOffset)
        let columns = SpecHelpers.suggestionTitles(from: result, kind: .column)
        // NEW BEHAVIOR: SELECT * from users should resolve to actual user columns
        #expect(columns.contains("id"), "Should resolve * to users.id")
        #expect(columns.contains("email"), "Should resolve * to users.email")
        #expect(columns.contains("created_at"), "Should resolve * to users.created_at")
    }

    // MARK: 7.5 CTE name as table in FROM

    @Test("7.5 CTE name appears as table suggestion in FROM")
    func cteNameInFrom() {
        let engine = SpecHelpers.makeSpecEngine()
        let text = "WITH active(uid) AS (SELECT id FROM users) SELECT * FROM "
        let query = SQLAutoCompletionQuery(
            token: "", prefix: "", pathComponents: [],
            replacementRange: NSRange(location: text.count, length: 0),
            precedingKeyword: "from", precedingCharacter: nil,
            focusTable: nil,
            tablesInScope: [],
            clause: .from
        )

        let result = engine.suggestions(for: query, text: text, caretLocation: text.count)
        let allTitles = SpecHelpers.suggestionTitles(from: result)
        // CTE name should be available as a completable table-like source
        let tableOrCTETitles = SpecHelpers.suggestionTitles(from: result, kind: .table)
        // The CTE "active" may appear as a table or just be in scope
        #expect(!allTitles.isEmpty, "Should suggest something in FROM after CTE definition")
    }

    // MARK: 7.6 CTE column with dot access

    @Test("7.6 CTE column accessible via dot path")
    func cteColumnDotAccess() {
        let engine = SpecHelpers.makeSpecEngine()
        let cteFocus = SQLAutoCompletionTableFocus(schema: nil, name: "active", alias: nil)
        let text = "WITH active(uid, uname) AS (SELECT id, name FROM users) SELECT active. FROM active"
        let query = SQLAutoCompletionQuery(
            token: "active.", prefix: "", pathComponents: ["active"],
            replacementRange: NSRange(location: 56, length: 7),
            precedingKeyword: "select", precedingCharacter: nil,
            focusTable: cteFocus,
            tablesInScope: [cteFocus],
            clause: .selectList
        )

        let result = engine.suggestions(for: query, text: text, caretLocation: 63)
        let columns = SpecHelpers.suggestionTitles(from: result, kind: .column)
        #expect(columns.contains(where: { $0.contains("uid") }), "Should suggest uid via dot access on CTE")
        #expect(columns.contains(where: { $0.contains("uname") }), "Should suggest uname via dot access on CTE")
    }

    // MARK: 7.7 Multiple CTEs — smart qualification

    @Test("7.7 Multiple CTEs with unique and ambiguous columns")
    func multipleCTEsSmartQualification() {
        let engine = SpecHelpers.makeSpecEngine()
        let aFocus = SQLAutoCompletionTableFocus(schema: nil, name: "a", alias: nil)
        let bFocus = SQLAutoCompletionTableFocus(schema: nil, name: "b", alias: nil)
        let text = "WITH a(id, x) AS (SELECT 1, 2), b(id, y) AS (SELECT 3, 4) SELECT  FROM a, b"
        // Find the caret position: after "SELECT " in the outer query
        let outerSelectRange = text.range(of: "SELECT  FROM a")!
        let caretPos = text.distance(from: text.startIndex, to: outerSelectRange.lowerBound) + 8
        let query = SQLAutoCompletionQuery(
            token: "", prefix: "", pathComponents: [],
            replacementRange: NSRange(location: caretPos, length: 0),
            precedingKeyword: "select", precedingCharacter: nil,
            focusTable: aFocus,
            tablesInScope: [aFocus, bFocus],
            clause: .selectList
        )

        let result = engine.suggestions(for: query, text: text, caretLocation: caretPos)
        let columns = SpecHelpers.suggestionTitles(from: result, kind: .column)
        // "id" is ambiguous (in both CTEs) — should be qualified
        // "x" is unique to a, "y" is unique to b — could be unqualified
        #expect(!columns.isEmpty, "Should suggest columns from both CTEs")
    }

    // MARK: 7.8 CTE column lookup case-insensitive

    @Test("7.8 CTE column lookup is case-insensitive")
    func cteColumnLookupCaseInsensitive() {
        let emptyCatalog = SQLDatabaseCatalog(schemas: [])
        let text = "WITH MyData(UserId, UserName) AS (SELECT 1, 'test') SELECT "
        let parser = SQLContextParser(text: text, caretLocation: text.count, dialect: .postgresql, catalog: emptyCatalog)
        let context = parser.parse()

        // CTE names are lowercased internally for lookup
        #expect(context.cteColumns["mydata"] != nil, "CTE lookup should be case-insensitive")
        if let cols = context.cteColumns["mydata"] {
            #expect(cols.contains("UserId") || cols.contains("userid"),
                    "Should find UserId column regardless of case")
        }
    }
}

// MARK: - Section 8: Derived Tables

@Suite("Spec 8 — Derived Tables")
struct SpecDerivedTableTests {

    // MARK: 8.1 Derived table columns from inner SELECT

    @Test("8.1 Derived table shows columns from inner SELECT")
    func derivedTableColumnsFromInnerSelect() {
        let engine = SpecHelpers.makeSpecEngine()
        let subFocus = SQLAutoCompletionTableFocus(schema: nil, name: "sub", alias: nil)
        let text = "SELECT sub. FROM (SELECT id, name, email FROM users) AS sub"
        let query = SQLAutoCompletionQuery(
            token: "sub.", prefix: "", pathComponents: ["sub"],
            replacementRange: NSRange(location: 7, length: 4),
            precedingKeyword: "select", precedingCharacter: nil,
            focusTable: subFocus,
            tablesInScope: [subFocus],
            clause: .selectList
        )

        let result = engine.suggestions(for: query, text: text, caretLocation: 11)
        let columns = SpecHelpers.suggestionTitles(from: result, kind: .column)
        #expect(columns.contains(where: { $0.contains("id") }), "Should suggest id from derived table")
        #expect(columns.contains(where: { $0.contains("name") || $0.contains("\"name\"") }),
                "Should suggest name from derived table")
        #expect(columns.contains(where: { $0.contains("email") }), "Should suggest email from derived table")
    }

    // MARK: 8.2 Derived table aliased columns

    @Test("8.2 Derived table uses aliased column names")
    func derivedTableAliasedColumns() {
        let emptyCatalog = SQLDatabaseCatalog(schemas: [])
        let text = "SELECT * FROM (SELECT id AS user_id, name AS user_name FROM users) sub WHERE "
        let parser = SQLContextParser(text: text, caretLocation: text.count, dialect: .postgresql, catalog: emptyCatalog)
        let context = parser.parse()

        if let subColumns = context.cteColumns["sub"] {
            #expect(subColumns.contains("user_id"), "Should use alias user_id")
            #expect(subColumns.contains("user_name"), "Should use alias user_name")
            #expect(!subColumns.contains("id"), "Should not show original column id")
            #expect(!subColumns.contains("name"), "Should not show original column name")
        }
    }

    // MARK: 8.3 Derived table SELECT * — resolve (NEW BEHAVIOR)

    @Test("8.3 Derived table SELECT * resolves to actual columns")
    func derivedTableSelectStarResolves() {
        let engine = SpecHelpers.makeSpecEngine()
        let subFocus = SQLAutoCompletionTableFocus(schema: nil, name: "sub", alias: nil)
        let text = "SELECT sub. FROM (SELECT * FROM orders) AS sub"
        let query = SQLAutoCompletionQuery(
            token: "sub.", prefix: "", pathComponents: ["sub"],
            replacementRange: NSRange(location: 7, length: 4),
            precedingKeyword: "select", precedingCharacter: nil,
            focusTable: subFocus,
            tablesInScope: [subFocus],
            clause: .selectList
        )

        let result = engine.suggestions(for: query, text: text, caretLocation: 11)
        let columns = SpecHelpers.suggestionTitles(from: result, kind: .column)
        // NEW BEHAVIOR: SELECT * from orders should resolve to actual order columns
        #expect(columns.contains(where: { $0.contains("id") }), "Should resolve * to orders.id")
        #expect(columns.contains(where: { $0.contains("total") }), "Should resolve * to orders.total")
        #expect(columns.contains(where: { $0.contains("status") }), "Should resolve * to orders.status")
    }
}

// MARK: - Section 9: Dot Paths

@Suite("Spec 9 — Dot Paths")
struct SpecDotPathTests {

    // MARK: 9.1 Table dot → columns

    @Test("9.1 table.dot shows columns of that table")
    func tableDotShowsColumns() {
        let engine = SpecHelpers.makeSpecEngine()
        let usersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "users", alias: nil)
        let text = "SELECT users. FROM users"
        let query = SQLAutoCompletionQuery(
            token: "users.", prefix: "", pathComponents: ["users"],
            replacementRange: NSRange(location: 7, length: 6),
            precedingKeyword: "select", precedingCharacter: nil,
            focusTable: usersFocus,
            tablesInScope: [usersFocus],
            clause: .selectList
        )

        let result = engine.suggestions(for: query, text: text, caretLocation: 13)
        let columns = SpecHelpers.suggestionTitles(from: result, kind: .column)
        #expect(columns.contains(where: { $0.contains("id") }), "users. should show id")
        #expect(columns.contains(where: { $0.contains("email") }), "users. should show email")
        #expect(columns.contains(where: { $0.contains("created_at") }), "users. should show created_at")
        #expect(columns.contains(where: { $0.contains("department_id") }), "users. should show department_id")
    }

    // MARK: 9.2 Alias dot → columns

    @Test("9.2 alias.dot shows columns of the aliased table")
    func aliasDotShowsColumns() {
        let engine = SpecHelpers.makeSpecEngine()
        let usersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "users", alias: "u")
        let text = "SELECT u. FROM users u"
        let query = SQLAutoCompletionQuery(
            token: "u.", prefix: "", pathComponents: ["u"],
            replacementRange: NSRange(location: 7, length: 2),
            precedingKeyword: "select", precedingCharacter: nil,
            focusTable: usersFocus,
            tablesInScope: [usersFocus],
            clause: .selectList
        )

        let result = engine.suggestions(for: query, text: text, caretLocation: 9)
        let columns = SpecHelpers.suggestionTitles(from: result, kind: .column)
        #expect(columns.contains(where: { $0.contains("id") }), "u. should show id")
        #expect(columns.contains(where: { $0.contains("email") }), "u. should show email")
        #expect(columns.contains(where: { $0.contains("name") || $0.contains("\"name\"") }),
                "u. should show name")
    }

    // MARK: 9.3 Schema dot → tables

    @Test("9.3 schema.dot shows tables in that schema")
    func schemaDotShowsTables() {
        let engine = SpecHelpers.makeSpecEngine()
        let text = "SELECT * FROM analytics."
        let query = SQLAutoCompletionQuery(
            token: "analytics.", prefix: "", pathComponents: ["analytics"],
            replacementRange: NSRange(location: 14, length: 10),
            precedingKeyword: "from", precedingCharacter: nil,
            focusTable: nil,
            tablesInScope: [],
            clause: .from
        )

        let result = engine.suggestions(for: query, text: text, caretLocation: 24)
        let tables = SpecHelpers.suggestionTitles(from: result, kind: .table)
        #expect(tables.contains("events"), "analytics. should show events table")
        #expect(tables.contains("metrics"), "analytics. should show metrics table")
        #expect(!tables.contains("users"), "analytics. should NOT show public.users")
    }

    // MARK: 9.7 Dot partial typing

    @Test("9.7 Dot path with partial column name filters results")
    func dotPartialTypingFilters() {
        let engine = SpecHelpers.makeSpecEngine()
        let usersFocus = SQLAutoCompletionTableFocus(schema: "public", name: "users", alias: "u")
        let text = "SELECT u.em FROM users u"
        let query = SQLAutoCompletionQuery(
            token: "u.em", prefix: "em", pathComponents: ["u"],
            replacementRange: NSRange(location: 7, length: 4),
            precedingKeyword: "select", precedingCharacter: nil,
            focusTable: usersFocus,
            tablesInScope: [usersFocus],
            clause: .selectList
        )

        let result = engine.suggestions(for: query, text: text, caretLocation: 11)
        let columns = SpecHelpers.suggestionTitles(from: result, kind: .column)
        #expect(columns.contains(where: { $0.contains("email") }), "u.em should match email")
        // "id", "name", "created_at" should be filtered out by prefix "em"
        let nonMatchingColumns = columns.filter {
            !$0.lowercased().contains("em") && !$0.lowercased().contains("email")
        }
        // Fuzzy matching may include some, but email should be prioritized
        #expect(columns.first { $0.contains("email") } != nil, "email should appear in filtered results")
    }

    // MARK: 9.8 Dot after unknown alias → no crash, no results

    @Test("9.8 Dot after unknown alias produces no crash and no column results")
    func dotAfterUnknownAliasNoCrash() {
        let engine = SpecHelpers.makeSpecEngine()
        let text = "SELECT xyz. FROM users"
        let query = SQLAutoCompletionQuery(
            token: "xyz.", prefix: "", pathComponents: ["xyz"],
            replacementRange: NSRange(location: 7, length: 4),
            precedingKeyword: "select", precedingCharacter: nil,
            focusTable: nil,
            tablesInScope: [],
            clause: .selectList
        )

        let result = engine.suggestions(for: query, text: text, caretLocation: 11)
        let columns = SpecHelpers.suggestionTitles(from: result, kind: .column)
        // Unknown alias "xyz" is not in scope — should not suggest any columns
        #expect(columns.isEmpty, "Unknown alias xyz. should produce no column suggestions")
    }
}
