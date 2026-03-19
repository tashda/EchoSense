import Foundation

/// A state machine that tracks the current SQL clause as tokens are fed in sequentially.
///
/// Replaces the scattered boolean flags in `SQLContextParser.inferClause()` with explicit
/// state tracking. The behavior is identical to the original implementation, with added
/// support for UNION/INTERSECT/EXCEPT, window functions (OVER / PARTITION BY), and
/// parenthesis-depth awareness for subqueries.
struct ClauseStateMachine: Sendable {

    // MARK: - Statement Type

    enum StatementType: Equatable, Sendable {
        case unknown
        case select
        case insert
        case update
        case delete
        case with
    }

    // MARK: - Internal State

    private struct State: Sendable {
        var clause: SQLClause = .unknown
        var statementType: StatementType = .unknown
        var pendingGroupBy: Bool = false
        var pendingOrderBy: Bool = false
        var insertColumnDepth: Int = 0
        /// Total parenthesis depth (for subquery awareness).
        var parenDepth: Int = 0
        /// Whether we are inside an OVER(...) window specification.
        var insideOver: Bool = false
        /// Parenthesis depth at the point OVER was entered, so we know when we leave it.
        var overParenDepth: Int = 0
        /// The clause that was active before entering an OVER window specification.
        var clauseBeforeOver: SQLClause = .unknown
    }

    private var state = State()

    // MARK: - Public Interface

    /// The clause the state machine currently believes the caret is in.
    var currentClause: SQLClause {
        if state.clause == .unknown && state.statementType == .delete {
            return .deleteWhere
        }
        return state.clause
    }

    /// The type of the outermost statement encountered so far.
    var statementType: StatementType {
        state.statementType
    }

    /// Feed a single token into the state machine.
    mutating func feed(_ token: SQLToken) {
        let value = token.lowercased

        switch token.kind {
        case .keyword, .identifier:
            feedKeywordOrIdentifier(value)
        default:
            feedPunctuation(token.text)
        }
    }

    // MARK: - Keyword / Identifier Handling

    private mutating func feedKeywordOrIdentifier(_ value: String) {
        // Inside a window specification, only watch for PARTITION BY and closing paren;
        // don't let keywords change the clause.
        if state.insideOver {
            // "partition" just sets up a pending-like state but we don't expose it;
            // "by" after "partition" keeps the clause unchanged. We simply ignore
            // everything while inside the OVER parentheses — the paren tracking in
            // feedPunctuation will end the window context.
            return
        }

        switch value {

        // ── Set operations ──────────────────────────────────────────────
        case "union", "intersect", "except":
            resetForSetOperation()

        // ── OVER (window function) ──────────────────────────────────────
        case "over":
            // Mark that the next open-paren starts a window spec.
            // We intentionally do NOT change the clause here.
            state.clauseBeforeOver = state.clause
            state.insideOver = true
            state.overParenDepth = state.parenDepth
            return

        // ── WITH / SELECT ───────────────────────────────────────────────
        case "with":
            state.clause = .withCTE
            state.statementType = .with

        case "select":
            state.clause = .selectList
            state.statementType = .select
            state.pendingGroupBy = false
            state.pendingOrderBy = false
            state.insertColumnDepth = 0

        // ── FROM / JOIN ─────────────────────────────────────────────────
        case "from":
            state.clause = .from

        case "join", "inner", "left", "right", "full", "outer", "cross":
            state.clause = .joinTarget

        case "on":
            state.clause = .joinCondition

        // ── WHERE / GROUP BY / ORDER BY / HAVING ────────────────────────
        case "where":
            state.clause = .whereClause

        case "group":
            state.pendingGroupBy = true

        case "order":
            state.pendingOrderBy = true

        case "by":
            if state.pendingGroupBy {
                state.clause = .groupBy
                state.pendingGroupBy = false
            } else if state.pendingOrderBy {
                state.clause = .orderBy
                state.pendingOrderBy = false
            }

        case "having":
            state.clause = .having

        case "limit":
            state.clause = .limit

        case "offset":
            state.clause = .offset

        // ── INSERT ──────────────────────────────────────────────────────
        case "insert":
            state.statementType = .insert
            state.insertColumnDepth = 0
            state.clause = .from

        case "into" where state.statementType == .insert:
            state.clause = .from

        case "values":
            state.clause = .values
            state.statementType = statementTypeAfterValues()
            state.insertColumnDepth = 0

        // ── UPDATE ──────────────────────────────────────────────────────
        case "update":
            state.statementType = .update
            state.insertColumnDepth = 0
            state.clause = .from

        case "set" where state.statementType == .update:
            state.clause = .updateSet

        // ── DELETE ──────────────────────────────────────────────────────
        case "delete":
            state.statementType = .delete
            state.insertColumnDepth = 0
            state.clause = .from

        // ── RETURNING ───────────────────────────────────────────────────
        case "returning":
            state.clause = .selectList

        default:
            break
        }
    }

    // MARK: - Punctuation Handling

    private mutating func feedPunctuation(_ text: String) {
        switch text {
        case ",":
            handleComma()
        case "(":
            handleOpenParen()
        case ")":
            handleCloseParen()
        case ";":
            handleSemicolon()
        default:
            break
        }
    }

    private mutating func handleSemicolon() {
        // Semicolon ends the current statement — reset everything
        state = State()
    }

    private mutating func handleComma() {
        // Inside OVER(...) or subquery parens — don't change clause.
        if state.insideOver { return }
        if state.parenDepth > 0 && state.insertColumnDepth == 0 { return }

        switch state.clause {
        case .insertColumns:
            break // stays insertColumns
        case .from, .joinTarget:
            state.clause = .from
        case .selectList, .groupBy, .orderBy:
            break // clause stays for comma-separated expressions
        default:
            break
        }
    }

    private mutating func handleOpenParen() {
        state.parenDepth += 1

        if state.insideOver {
            // We are entering (or going deeper inside) the OVER window spec.
            // Don't change the clause.
            return
        }

        state.pendingGroupBy = false
        state.pendingOrderBy = false

        if state.statementType == .insert && state.clause == .from {
            state.clause = .insertColumns
            state.insertColumnDepth += 1
        } else if state.insertColumnDepth > 0 {
            state.insertColumnDepth += 1
        }
        // For subqueries (paren depth > 0 and not insert columns), we intentionally
        // do not change the clause — the keywords inside the subquery will drive state.
    }

    private mutating func handleCloseParen() {
        if state.parenDepth > 0 {
            state.parenDepth -= 1
        }

        // Check if we are leaving the OVER window spec.
        if state.insideOver && state.parenDepth == state.overParenDepth {
            state.insideOver = false
            state.clause = state.clauseBeforeOver
            return
        }

        if state.insertColumnDepth > 0 {
            state.insertColumnDepth -= 1
            if state.insertColumnDepth == 0 {
                state.clause = .from
            }
        }
    }

    // MARK: - Helpers

    /// After VALUES, the statement type should no longer be considered insert for the
    /// purposes of the `into` guard, matching the original behavior which cleared
    /// `encounteredInsert`.
    private func statementTypeAfterValues() -> StatementType {
        // Keep the broader statement type so delete-where fallback still works if needed,
        // but clear insert so `into` doesn't re-trigger.
        switch state.statementType {
        case .insert:
            return .unknown
        default:
            return state.statementType
        }
    }

    private mutating func resetForSetOperation() {
        // UNION / INTERSECT / EXCEPT start a new query block.
        state.clause = .unknown
        state.pendingGroupBy = false
        state.pendingOrderBy = false
        state.insertColumnDepth = 0
        // Keep statementType — the overall statement context doesn't change,
        // but the clause resets so the next SELECT will set it to .selectList.
    }
}
