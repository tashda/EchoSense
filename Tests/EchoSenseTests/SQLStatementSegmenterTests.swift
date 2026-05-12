import Foundation
import Testing
@testable import EchoSense

@Suite("Statement Segmenter")
struct SQLStatementSegmenterTests {

    private func segments(_ text: String, dialect: SQLDialect = .microsoftSQL) -> [String] {
        let ns = text as NSString
        let boundaries = SQLStatementSegmenter.boundaries(in: ns, dialect: dialect)
        var ranges: [NSRange] = []
        for index in boundaries.indices {
            let start = boundaries[index]
            let end = index + 1 < boundaries.count ? boundaries[index + 1] : ns.length
            ranges.append(NSRange(location: start, length: end - start))
        }
        return ranges.map { ns.substring(with: $0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    @Test func singleStatementWithoutTerminator() {
        let parts = segments("SELECT * FROM a")
        #expect(parts.count == 1)
        #expect(parts[0] == "SELECT * FROM a")
    }

    @Test func semicolonSeparated() {
        let parts = segments("SELECT * FROM a; SELECT * FROM b")
        #expect(parts.count == 2)
        #expect(parts[1] == "SELECT * FROM b")
    }

    /// The user's reported case: two SELECT statements with no semicolon,
    /// only a blank line between them. The segmenter must still split them.
    @Test func keywordAnchoredSplitWithoutSemicolon() {
        let text = """
        select *
        from oh_tbl
        order by ddate desc

        select top 100 *
        from ba_history
        order by ba_history.histDate desc
        """
        let parts = segments(text)
        #expect(parts.count == 2)
        #expect(parts[0].hasPrefix("select *"))
        #expect(parts[1].hasPrefix("select top 100 *"))
    }

    /// Even without a blank line, two adjacent statements are split by the keyword anchor.
    @Test func keywordAnchoredSplitNoBlankLine() {
        let text = "SELECT * FROM a ORDER BY id DESC\nSELECT * FROM b"
        let parts = segments(text)
        #expect(parts.count == 2)
    }

    /// UNION continues the previous SELECT — must NOT split.
    @Test func unionDoesNotSplit() {
        let parts = segments("SELECT a FROM t1 UNION SELECT b FROM t2")
        #expect(parts.count == 1)
    }

    @Test func unionAllDoesNotSplit() {
        let parts = segments("SELECT a FROM t1 UNION ALL SELECT b FROM t2")
        #expect(parts.count == 1)
    }

    @Test func subquerySelectDoesNotSplit() {
        let parts = segments("SELECT (SELECT MAX(x) FROM t2) FROM t1")
        #expect(parts.count == 1)
    }

    @Test func cteIsOneStatement() {
        let parts = segments("WITH a AS (SELECT * FROM x) SELECT * FROM a")
        #expect(parts.count == 1)
    }

    @Test func cteChainIsOneStatement() {
        let parts = segments("WITH a AS (SELECT 1), b AS (SELECT 2) SELECT * FROM b")
        #expect(parts.count == 1)
    }

    @Test func insertSelectIsOneStatement() {
        let parts = segments("INSERT INTO t SELECT * FROM s")
        #expect(parts.count == 1)
    }

    @Test func updateSetIsOneStatement() {
        let parts = segments("UPDATE t SET col = 1 WHERE id = 2")
        #expect(parts.count == 1)
    }

    @Test func goSeparatorMSSQL() {
        let text = "SELECT * FROM a\nGO\nSELECT * FROM b"
        let parts = segments(text, dialect: .microsoftSQL)
        #expect(parts.count == 3) // a / GO / b
    }

    @Test func goNotSeparatorOnOtherDialects() {
        let text = "SELECT * FROM a\nGO\nSELECT * FROM b"
        let parts = segments(text, dialect: .postgresql)
        #expect(parts.count == 2) // GO is identifier; SELECT after still splits
    }

    @Test func statementRangeContainsCaret() {
        let text = "SELECT * FROM a\nSELECT * FROM b"
        let ns = text as NSString
        let range = SQLStatementSegmenter.statementRange(in: ns,
                                                          caret: ns.length - 1,
                                                          dialect: .microsoftSQL)
        let slice = ns.substring(with: range)
        #expect(slice.contains("FROM b"))
        #expect(!slice.contains("FROM a"))
    }

    /// The bug we are fixing: tables in a sibling statement must NOT leak into
    /// the active statement's table-in-scope set.
    @Test func tablesInScopeDoNotLeakAcrossStatements() {
        let catalog = SQLDatabaseCatalog(schemas: [])
        let text = """
        select * from oh_tbl order by ddate desc

        select * from oh_history order by dd
        """
        // Caret at the end (in the second statement).
        let parser = SQLContextParser(text: text,
                                       caretLocation: text.count,
                                       dialect: .microsoftSQL,
                                       catalog: catalog)
        let context = parser.parse()
        let names = context.tablesInScope.map { $0.name.lowercased() }
        #expect(names.contains("oh_history"))
        #expect(!names.contains("oh_tbl"))
    }
}
