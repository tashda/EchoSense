import Foundation

/// Splits a SQL buffer into statement ranges using token-level boundaries.
///
/// Boundaries (evaluated at paren depth 0, outside strings and comments):
///   1. `;` — hard terminator.
///   2. `GO` alone on a line — MSSQL batch terminator.
///   3. A statement-initiating keyword (SELECT, INSERT, …) whose preceding
///      non-trivia token is not a continuation token. After `WITH`, `INSERT`,
///      or `UPDATE` we expect a DML body (subsequent SELECT/INSERT/UPDATE/
///      DELETE/MERGE at depth 0 belongs to the same statement).
///
/// Designed so a malformed statement does not poison the parse of its
/// neighbours: callers can scope analysis to a single statement range.
enum SQLStatementSegmenter {

    /// Returns the half-open NSRange `[start, end)` of the statement containing `caret`.
    static func statementRange(in text: NSString,
                                caret: Int,
                                dialect: SQLDialect) -> NSRange {
        let boundaries = boundaries(in: text, dialect: dialect)
        let clamped = max(0, min(caret, text.length))
        var start = 0
        var end = text.length
        for boundary in boundaries {
            if boundary <= clamped {
                start = boundary
            } else {
                end = boundary
                break
            }
        }
        return NSRange(location: start, length: max(0, end - start))
    }

    /// Returns the sorted list of segment-start offsets in `text`. Always includes 0.
    static func boundaries(in text: NSString, dialect: SQLDialect) -> [Int] {
        guard text.length > 0 else { return [0] }
        let tokens = SQLTokenizer.tokenize(text)

        var boundaries: [Int] = [0]
        var parenDepth = 0
        var lastSig: SQLToken?
        var sawStatementHead = false
        // After WITH/INSERT/UPDATE/MERGE at the head of a segment we expect a DML body,
        // so the next select/insert/update/delete/merge keyword at depth 0 belongs to
        // this statement, not the next.
        var expectingDMLBody = false

        func recordBoundary(at location: Int) {
            let clamped = max(0, min(location, text.length))
            if boundaries.last != clamped {
                boundaries.append(clamped)
            }
            sawStatementHead = false
            expectingDMLBody = false
        }

        for token in tokens {
            switch token.kind {
            case .whitespace, .comment:
                continue
            default:
                break
            }

            // Track paren depth — boundaries only fire at depth 0.
            if token.kind == .punctuation {
                if token.text == "(" {
                    parenDepth += 1
                    lastSig = token
                    continue
                } else if token.text == ")" {
                    if parenDepth > 0 { parenDepth -= 1 }
                    lastSig = token
                    continue
                } else if token.text == ";" && parenDepth == 0 {
                    recordBoundary(at: NSMaxRange(token.range))
                    lastSig = nil
                    continue
                }
            }

            // GO alone on a line (MSSQL batch terminator).
            if dialect == .microsoftSQL,
               parenDepth == 0,
               (token.kind == .identifier || token.kind == .keyword),
               token.lowercased == "go",
               isAloneOnLine(token: token, in: text) {
                recordBoundary(at: token.range.location)
                recordBoundary(at: NSMaxRange(token.range))
                lastSig = nil
                continue
            }

            // Top-level statement-initiating keyword.
            if parenDepth == 0,
               (token.kind == .keyword || token.kind == .identifier),
               Self.statementInitiators.contains(token.lowercased) {
                let lowercased = token.lowercased

                // Within an existing statement that expects a DML body
                // (WITH …, INSERT INTO t …, etc.), absorb the body keyword.
                if expectingDMLBody, Self.dmlBodyHeads.contains(lowercased) {
                    expectingDMLBody = Self.bodyExpectingHeads.contains(lowercased)
                    sawStatementHead = true
                    lastSig = token
                    continue
                }

                let isContinuation = isContinuationToken(lastSig)
                if !isContinuation && sawStatementHead {
                    recordBoundary(at: token.range.location)
                }
                sawStatementHead = true
                if Self.bodyExpectingHeads.contains(lowercased) {
                    expectingDMLBody = true
                }
                lastSig = token
                continue
            }

            lastSig = token
        }

        return boundaries
    }

    // MARK: - Helpers

    private static func isAloneOnLine(token: SQLToken, in text: NSString) -> Bool {
        var i = token.range.location - 1
        while i >= 0 {
            let c = text.character(at: i)
            if c == 0x0A || c == 0x0D { break }
            if c == 0x20 || c == 0x09 { i -= 1; continue }
            return false
        }
        var j = NSMaxRange(token.range)
        while j < text.length {
            let c = text.character(at: j)
            if c == 0x0A || c == 0x0D { break }
            if c == 0x20 || c == 0x09 { j += 1; continue }
            if c == 0x2D, j + 1 < text.length, text.character(at: j + 1) == 0x2D {
                return true
            }
            return false
        }
        return true
    }

    private static func isContinuationToken(_ token: SQLToken?) -> Bool {
        guard let token else { return true }
        switch token.kind {
        case .operatorSymbol:
            return true
        case .keyword, .identifier:
            return continuationKeywords.contains(token.lowercased)
        case .punctuation:
            return token.text == "," || token.text == "("
        case .number, .stringLiteral, .quotedIdentifier, .parameter:
            return false
        case .whitespace, .comment:
            return false
        }
    }

    /// Keywords that, at depth 0 with a non-continuation predecessor, open a new statement.
    /// Deliberately conservative — keywords like `SET`, `BEGIN`, `IF` are excluded because
    /// they appear inside other statements (UPDATE … SET, BEGIN TRAN, IF … SELECT).
    private static let statementInitiators: Set<String> = [
        "select", "insert", "update", "delete", "merge", "with",
        "create", "alter", "drop", "truncate",
        "exec", "execute", "call",
        "use", "declare", "print",
        "grant", "revoke", "deny"
    ]

    /// Heads that, once parsed, expect a DML body within the same statement.
    /// E.g. `WITH … SELECT`, `INSERT INTO t SELECT …`.
    private static let bodyExpectingHeads: Set<String> = [
        "with", "insert", "update", "merge"
    ]

    /// DML heads that complete a body-expecting prelude.
    private static let dmlBodyHeads: Set<String> = [
        "select", "insert", "update", "delete", "merge"
    ]

    /// Tokens that, when they precede a statement-initiating keyword, force it to be
    /// treated as part of the previous statement (not a new one).
    private static let continuationKeywords: Set<String> = [
        // Set operations — next SELECT is a continuation.
        "union", "intersect", "except", "all",
        // Clause keywords expecting more.
        "from", "join", "inner", "left", "right", "full", "outer", "cross",
        "on", "where", "group", "order", "by", "having", "into", "values",
        "using", "returning", "as", "and", "or", "not", "in", "like",
        "between", "case", "when", "then", "else", "partition", "over",
        "distinct", "top", "limit", "offset", "with", "set", "for", "to"
    ]
}
